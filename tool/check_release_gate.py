"""Read-only GitHub gate: align version/tag/SHA and never update a Release."""

import argparse
import json
import os
from pathlib import Path
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


MAX_RELEASE_PAGES = 1000


class GateError(ValueError):
    pass


def read_version(pubspec):
    values = re.findall(r"(?m)^version:\s*([^\r\n]+)$", pubspec)
    if len(values) != 1:
        raise GateError("pubspec.yaml must contain exactly one top-level version")
    version = values[0].split("#", 1)[0].strip()
    if version[:1] in ("'", '"'):
        if len(version) < 2 or version[-1] != version[0]:
            raise GateError("pubspec.yaml version has an unmatched quote")
        version = version[1:-1]
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9]+)?", version):
        raise GateError("pubspec.yaml version must be a Flutter version")
    return version


class GitHubAPI:
    def __init__(self, repository, token="", api_url="https://api.github.com"):
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
            raise GateError("GITHUB_REPOSITORY must be owner/repository")
        self.repository = repository
        self.token = token
        self.api_url = api_url.rstrip("/")

    def get(self, resource):
        return self._get(resource, dict, allow_missing=True)

    def list_release_page(self, page):
        if not self.token or not self.token.strip():
            raise GateError("An authenticated token is required to verify draft Releases")
        if type(page) is not int or page < 1:
            raise GateError("Invalid Release page; release blocked")
        return self._get(f"releases?per_page=100&page={page}", list, allow_missing=False)

    def _get(self, resource, expected_type, allow_missing):
        headers = {"Accept": "application/vnd.github+json",
                   "X-GitHub-Api-Version": "2022-11-28",
                   "User-Agent": "cnkh-release-gate"}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        request = Request(f"{self.api_url}/repos/{self.repository}/{resource}",
                          headers=headers, method="GET")
        try:
            with urlopen(request, timeout=30) as response:
                data = json.load(response)
                # A missing object is represented only by HTTP 404. A successful
                # null/scalar response cannot prove that a version is unpublished.
                if not isinstance(data, expected_type):
                    raise ValueError("Invalid GitHub response object")
                return data
        except HTTPError as error:
            if error.code == 404 and allow_missing:
                return None
            raise GateError(f"GitHub read failed (HTTP {error.code}); release blocked") from None
        except (URLError, OSError, ValueError):
            raise GateError("GitHub read failed; release blocked") from None


def check_release(version, kind, staged_tag, ref, sha, api):
    if kind not in ("mobile", "desktop"):
        raise GateError("Release kind must be mobile or desktop")
    tag = "v" + version.split("+", 1)[0] + ("-mobile" if kind == "mobile" else "")
    if staged_tag != tag:
        raise GateError(f"Staged RELEASE_TAG must equal pubspec.yaml tag {tag}")
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise GateError("GITHUB_SHA must be the complete source commit SHA")
    tag_event = ref.startswith("refs/tags/")
    if tag_event and ref[len("refs/tags/"):] != tag:
        raise GateError(f"Trigger tag must equal pubspec.yaml tag {tag}")

    encoded_tag = quote(tag, safe="")
    if api.get("releases/tags/" + encoded_tag) is not None:
        raise GateError(f"Release {tag} already exists; published versions are immutable")

    # The by-tag endpoint promises published releases only. Authenticated lists
    # also expose drafts, which must not be reused with stale source or assets.
    seen_ids = set()
    for page in range(1, MAX_RELEASE_PAGES + 1):
        releases = api.list_release_page(page)
        if not isinstance(releases, list) or len(releases) > 100:
            raise GateError("Invalid Release list page; release blocked")
        for release in releases:
            if (not isinstance(release, dict) or
                    type(release.get("id")) is not int or release["id"] <= 0 or
                    not isinstance(release.get("tag_name"), str) or
                    type(release.get("draft")) is not bool):
                raise GateError("Invalid Release list item; release blocked")
            if release["id"] in seen_ids:
                raise GateError("Release pagination did not advance; release blocked")
            seen_ids.add(release["id"])
            if release["tag_name"] == tag:
                raise GateError(f"Release {tag} already exists, including drafts; release blocked")
        if len(releases) < 100:
            break
    else:
        raise GateError("Release pagination exceeded the safety limit; release blocked")

    reference = api.get("git/ref/tags/" + encoded_tag)
    if reference is None:
        if tag_event:
            raise GateError("Trigger tag was not found; release blocked")
        return tag
    if not isinstance(reference, dict) or reference.get("ref") != "refs/tags/" + tag:
        raise GateError("GitHub returned an invalid tag reference")
    obj = reference.get("object")
    visited = set()
    while isinstance(obj, dict):
        object_sha = obj.get("sha", "")
        if not isinstance(object_sha, str) or not re.fullmatch(r"[0-9a-f]{40}", object_sha):
            raise GateError("GitHub returned an invalid tag object SHA")
        if obj.get("type") == "commit":
            if object_sha != sha:
                raise GateError(f"Existing tag {tag} does not point to GITHUB_SHA")
            return tag
        if obj.get("type") != "tag" or object_sha in visited or len(visited) >= 10:
            raise GateError("Existing tag cannot be resolved to a source commit")
        visited.add(object_sha)
        annotation = api.get("git/tags/" + object_sha)
        obj = annotation.get("object") if isinstance(annotation, dict) else None
    raise GateError("GitHub returned an invalid annotated tag")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kind", required=True, choices=("mobile", "desktop"))
    parser.add_argument("--pubspec", default="pubspec.yaml")
    args = parser.parse_args()
    try:
        version = read_version(Path(args.pubspec).read_text(encoding="utf-8"))
        api = GitHubAPI(os.environ.get("GITHUB_REPOSITORY", ""),
                        os.environ.get("GH_TOKEN", os.environ.get("GITHUB_TOKEN", "")),
                        os.environ.get("GITHUB_API_URL", "https://api.github.com"))
        tag = check_release(version, args.kind,
                            os.environ.get("RELEASE_TAG", ""),
                            os.environ.get("GITHUB_REF", ""),
                            os.environ.get("GITHUB_SHA", ""), api)
        print(f"Release gate PASS: {tag}, source {os.environ['GITHUB_SHA']}")
        return 0
    except (GateError, OSError) as error:
        print(f"Release gate BLOCKED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

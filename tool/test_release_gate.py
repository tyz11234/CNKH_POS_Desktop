"""Offline release-identity and immutable-release regression tests."""

from pathlib import Path
import importlib
import io
import re
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError


ROOT = Path(__file__).resolve().parents[1]


class WorkflowContractTests(unittest.TestCase):
    def test_release_gate_precedes_publish_with_same_condition(self):
        workflows = list((ROOT / ".github/workflows").glob("*.yml"))
        releasing = [path for path in workflows
                     if "softprops/action-gh-release@" in path.read_text()]
        self.assertEqual(len(releasing), 1)
        source = releasing[0].read_text()
        steps = re.split(r"(?m)^      - name: ", source)[1:]
        publish = next(step for step in steps
                       if "softprops/action-gh-release@" in step)
        guards = [step for step in steps if "tool/check_release_gate.py" in step]
        self.assertEqual(len(guards), 1, "Release upload has no immutable-version guard")
        guard = guards[0]
        self.assertLess(steps.index(guard), steps.index(publish))
        condition = lambda step: re.search(r"(?m)^        if: (.+)$", step).group(1)
        self.assertEqual(condition(guard), condition(publish))
        self.assertIn("${{ secrets.GITHUB_TOKEN }}", guard)
        self.assertIn("tag_name: ${{ env.RELEASE_TAG }}", publish)
        self.assertNotIn("github.ref_name", publish)
        self.assertIn("overwrite_files: false", publish)

    def test_release_gate_tests_run_on_every_ci(self):
        source = next(path.read_text() for path in
                      (ROOT / ".github/workflows").glob("*.yml")
                      if "softprops/action-gh-release@" in path.read_text())
        steps = re.split(r"(?m)^      - name: ", source)[1:]
        tests = [step for step in steps if "tool/test_release_gate.py" in step]
        self.assertEqual(len(tests), 1, "Release guard has no regular CI regression")
        self.assertNotIn("        if:", tests[0])

    def test_main_and_tag_release_share_a_mutex_without_cancellation(self):
        source = next(path.read_text() for path in
                      (ROOT / ".github/workflows").glob("*.yml")
                      if "softprops/action-gh-release@" in path.read_text())
        release_predicate = ("startsWith(github.ref, 'refs/tags/') || "
                             "(github.ref == 'refs/heads/main' && "
                             "contains(github.event.head_commit.message, '[release]'))")
        concurrency = re.search(r"(?ms)^concurrency:\n(.*?)(?=^\S)", source).group(1)
        self.assertIn("(" + release_predicate + ") && 'release' ||", concurrency)
        self.assertTrue("cancel-in-progress: false" in concurrency or
                        "cancel-in-progress: ${{ !(" + release_predicate + ") }}" in concurrency)


SHA = "a" * 40
OTHER_SHA = "b" * 40
ANNOTATION_SHA = "c" * 40


class FakeAPI:
    def __init__(self, responses=None):
        self.responses = responses or {}
        self.calls = []

    def get(self, resource):
        self.calls.append(resource)
        response = self.responses.get(resource)
        if isinstance(response, Exception):
            raise response
        return response


class ReleaseIdentityTests(unittest.TestCase):
    def setUp(self):
        self.gate = importlib.import_module("check_release_gate")

    def check(self, kind="desktop", tag="v1.10.10", ref="refs/heads/main",
              sha=SHA, responses=None, version="1.10.10+38"):
        self.api = FakeAPI(responses)
        return self.gate.check_release(version, kind, tag, ref, sha, self.api)

    def reference(self, tag="v1.10.10", object_type="commit", sha=SHA):
        return {"ref": "refs/tags/" + tag,
                "object": {"type": object_type, "sha": sha}}

    def test_new_desktop_version_can_create_release(self):
        self.assertEqual(self.check(), "v1.10.10")
        self.assertEqual(self.api.calls,
                         ["releases/tags/v1.10.10", "git/ref/tags/v1.10.10"])

    def test_new_mobile_version_uses_mobile_suffix(self):
        self.assertEqual(self.check(kind="mobile", tag="v1.10.10-mobile"),
                         "v1.10.10-mobile")

    def test_existing_release_is_never_overwritten(self):
        for release in ({"id": 1, "draft": False}, {"id": 2, "draft": True}, {}):
            with self.subTest(release=release):
                with self.assertRaisesRegex(self.gate.GateError, "already exists"):
                    self.check(responses={"releases/tags/v1.10.10": release})
                self.assertEqual(self.api.calls, ["releases/tags/v1.10.10"])

    def test_build_only_change_cannot_reuse_published_semver(self):
        with self.assertRaisesRegex(self.gate.GateError, "immutable"):
            self.check(version="1.10.10+39",
                       responses={"releases/tags/v1.10.10": {"id": 1}})

    def test_mismatched_trigger_tag_is_rejected_before_network(self):
        for ref in ("refs/tags/v1.10.9", "refs/tags/v1.10.10-mobile"):
            with self.subTest(ref=ref):
                with self.assertRaisesRegex(self.gate.GateError, "Trigger tag"):
                    self.check(ref=ref)
                self.assertEqual(self.api.calls, [])

    def test_wrong_staged_tag_is_rejected_before_network(self):
        with self.assertRaisesRegex(self.gate.GateError, "RELEASE_TAG"):
            self.check(tag="v1.10.9")
        self.assertEqual(self.api.calls, [])

    def test_invalid_source_sha_is_rejected_before_network(self):
        for sha in ("", "abcdef", "x" * 40):
            with self.subTest(sha=sha):
                with self.assertRaisesRegex(self.gate.GateError, "GITHUB_SHA"):
                    self.check(sha=sha)
                self.assertEqual(self.api.calls, [])

    def test_matching_lightweight_tag_is_allowed(self):
        self.assertEqual(self.check(
            ref="refs/tags/v1.10.10",
            responses={"git/ref/tags/v1.10.10": self.reference()}), "v1.10.10")

    def test_matching_annotated_tag_is_allowed(self):
        self.assertEqual(self.check(responses={
            "git/ref/tags/v1.10.10": self.reference(object_type="tag", sha=ANNOTATION_SHA),
            "git/tags/" + ANNOTATION_SHA: {"object": {"type": "commit", "sha": SHA}},
        }), "v1.10.10")

    def test_nested_annotated_tags_are_peeled(self):
        self.assertEqual(self.check(responses={
            "git/ref/tags/v1.10.10": self.reference(object_type="tag", sha=ANNOTATION_SHA),
            "git/tags/" + ANNOTATION_SHA: {"object": {"type": "tag", "sha": OTHER_SHA}},
            "git/tags/" + OTHER_SHA: {"object": {"type": "commit", "sha": SHA}},
        }), "v1.10.10")

    def test_lightweight_tag_on_other_commit_is_rejected(self):
        with self.assertRaisesRegex(self.gate.GateError, "does not point"):
            self.check(responses={"git/ref/tags/v1.10.10": self.reference(sha=OTHER_SHA)})

    def test_annotated_tag_on_other_commit_is_rejected(self):
        with self.assertRaisesRegex(self.gate.GateError, "does not point"):
            self.check(responses={
                "git/ref/tags/v1.10.10": self.reference(object_type="tag", sha=ANNOTATION_SHA),
                "git/tags/" + ANNOTATION_SHA: {"object": {"type": "commit", "sha": OTHER_SHA}},
            })

    def test_missing_trigger_tag_is_rejected(self):
        with self.assertRaisesRegex(self.gate.GateError, "not found"):
            self.check(ref="refs/tags/v1.10.10")

    def test_cyclic_annotation_is_rejected(self):
        with self.assertRaisesRegex(self.gate.GateError, "cannot be resolved"):
            self.check(responses={
                "git/ref/tags/v1.10.10": self.reference(object_type="tag", sha=ANNOTATION_SHA),
                "git/tags/" + ANNOTATION_SHA: {"object": {"type": "tag", "sha": ANNOTATION_SHA}},
            })

    def test_non_commit_tag_is_rejected(self):
        with self.assertRaisesRegex(self.gate.GateError, "cannot be resolved"):
            self.check(responses={"git/ref/tags/v1.10.10": self.reference(object_type="tree")})

    def test_malformed_api_replies_are_rejected(self):
        references = ([], {}, {"ref": "refs/tags/other", "object": {"type": "commit", "sha": SHA}},
                      self.reference(sha="short"), self.reference(sha=None))
        for reference in references:
            with self.subTest(reference=reference):
                with self.assertRaises(self.gate.GateError):
                    self.check(responses={"git/ref/tags/v1.10.10": reference})

    def test_missing_annotation_is_rejected(self):
        with self.assertRaisesRegex(self.gate.GateError, "invalid annotated tag"):
            self.check(responses={
                "git/ref/tags/v1.10.10": self.reference(object_type="tag", sha=ANNOTATION_SHA)})

    def test_api_failure_cannot_be_treated_as_new_version(self):
        with self.assertRaisesRegex(self.gate.GateError, "unavailable"):
            self.check(responses={"releases/tags/v1.10.10": self.gate.GateError("unavailable")})


class PubspecAndTransportTests(unittest.TestCase):
    def setUp(self):
        self.gate = importlib.import_module("check_release_gate")

    def test_pubspec_version_and_yaml_scalar_forms(self):
        for scalar in ("1.10.10+38", "'1.10.10+38'", '"1.10.10+38" # next release'):
            with self.subTest(scalar=scalar):
                self.assertEqual(self.gate.read_version("name: app\nversion: " + scalar + "\n"),
                                 "1.10.10+38")

    def test_missing_duplicate_or_malformed_versions_are_rejected(self):
        for source in ("# version: 1.2.3\n", "version: 1.2.3\nversion: 2.3.4\n",
                       "version: latest\n", "version: '1.2.3\n", "version: 1.2.3+build\n"):
            with self.subTest(source=source):
                with self.assertRaises(self.gate.GateError):
                    self.gate.read_version(source)

    def test_transport_only_uses_get(self):
        with patch.object(self.gate, "urlopen", return_value=io.BytesIO(b'{"id": 1}')) as request:
            self.assertEqual(self.gate.GitHubAPI("owner/repo", "secret-token").get("releases/tags/v1"),
                             {"id": 1})
        sent = request.call_args.args[0]
        self.assertEqual(sent.get_method(), "GET")
        self.assertEqual(sent.full_url, "https://api.github.com/repos/owner/repo/releases/tags/v1")
        self.assertEqual(sent.get_header("Authorization"), "Bearer secret-token")

    def test_only_404_means_not_found(self):
        for status in (401, 403, 429, 500):
            with self.subTest(status=status):
                with patch.object(self.gate, "urlopen", side_effect=HTTPError(
                        "https://api.github.com", status, "secret-token", None, None)):
                    with self.assertRaises(self.gate.GateError) as error:
                        self.gate.GitHubAPI("owner/repo", "secret-token").get("releases/tags/v1")
                    self.assertNotIn("secret-token", str(error.exception))
        with patch.object(self.gate, "urlopen", side_effect=HTTPError(
                "https://api.github.com", 404, "missing", None, None)):
            self.assertIsNone(self.gate.GitHubAPI("owner/repo").get("releases/tags/v1"))

    def test_network_or_invalid_json_fails_closed(self):
        with patch.object(self.gate, "urlopen", side_effect=URLError("secret-token")):
            with self.assertRaisesRegex(self.gate.GateError, "release blocked"):
                self.gate.GitHubAPI("owner/repo").get("releases/tags/v1")
        with patch.object(self.gate, "urlopen", return_value=io.BytesIO(b'not JSON')):
            with self.assertRaisesRegex(self.gate.GateError, "release blocked"):
                self.gate.GitHubAPI("owner/repo").get("releases/tags/v1")


if __name__ == "__main__":
    unittest.main(verbosity=2)

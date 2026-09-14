"""Verify the actual release contains every generated training PNG and arrow."""
import argparse
import json
from pathlib import Path
import struct
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("bundle", type=Path)
parser.add_argument("--kind", choices=("desktop", "mobile"), required=True)
args = parser.parse_args()
names = "login sale payment refund stock pair sync backup einvoice_setup einvoice_credentials einvoice_history".split()
if args.kind == "mobile":
    names.append("einvoice_status")
archive = zipfile.ZipFile(args.bundle) if args.bundle.is_file() else None
if archive is None:
    if args.kind != "desktop":
        raise SystemExit("Mobile verification requires the built APK")
    for required in ("cnkh_pos_desktop.exe", "flutter_windows.dll", "data/icudtl.dat"):
        if not (args.bundle / required).is_file():
            raise SystemExit(f"Missing Windows runtime file: {required}")
    base = args.bundle / "data/flutter_assets/assets/training"
else:
    base = "assets/flutter_assets/assets/training/"

def read(name):
    return archive.read(base + name) if archive else (base / name).read_bytes()

try:
    for name in names:
        png = read(name + ".png")
        meta_bytes = read(name + ".json")
        for suffix, data in ((".png", png), (".json", meta_bytes)):
            if data != (Path("assets/training") / (name + suffix)).read_bytes():
                raise SystemExit(f"Packaged asset differs from captured source: {name}{suffix}")
        if png[:8] != b"\x89PNG\r\n\x1a\n" or png[12:16] != b"IHDR":
            raise SystemExit(f"Invalid screenshot PNG: {name}")
        width, height = struct.unpack(">II", png[16:24])
        meta = json.loads(meta_bytes)
        if (width, height) != (meta["width"], meta["height"]) or min(width, height) <= 0:
            raise SystemExit(f"Screenshot dimensions do not match arrow metadata: {name}")
        if not all(0 <= meta[key] <= 1 for key in ("x", "y")):
            raise SystemExit(f"Arrow lies outside screenshot: {name}")
        if meta["source"] != "actual Flutter widget screenshot":
            raise SystemExit(f"Unknown screenshot source: {name}")
        print(f"Verified training asset: {name} ({width}x{height})")
finally:
    if archive:
        archive.close()
print(f"TRAINING_BUNDLE_VERIFIED: {args.kind}, {len(names)} screenshots with arrow metadata")

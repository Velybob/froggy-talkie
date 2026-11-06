#!/usr/bin/env python3
"""Check a packaged or extracted app without launching it or touching preferences."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys

app = Path(sys.argv[1])
resources = app / "Contents/Resources"
with (app / "Contents/Info.plist").open("rb") as f:
    plist = plistlib.load(f)
assert plist["CFBundleIdentifier"] == "local.research.LocalDictation"
assert plist["CFBundleDisplayName"] == "Froggy Talkie"
assert plist["LSMinimumSystemVersion"] == "15.0"
binary = app / "Contents/MacOS" / plist["CFBundleExecutable"]
assert subprocess.check_output(["lipo", "-archs", str(binary)], text=True).strip() == "arm64"
linked = subprocess.check_output(["otool", "-L", str(binary)], text=True).splitlines()[1:]
assert all(line.strip().startswith(("/System/Library/", "/usr/lib/")) for line in linked), linked
bundles = sorted(p.name for p in resources.glob("*.bundle"))
assert bundles == ["LocalDictation_DictationModels.bundle"], bundles
manifest = json.loads((resources / bundles[0] / "parakeet-ultra.json").read_text())
info = json.loads((resources / "build-info.json").read_text())
assert info["version"] == plist["CFBundleShortVersionString"]
assert info["build"] == plist["CFBundleVersion"]
assert info["model_manifest_sha256"] == hashlib.sha256((resources / bundles[0] / "parakeet-ultra.json").read_bytes()).hexdigest()
assert manifest["revision"] == "95eaa59a39d4394f047a4dc5cce480388a60d1b6"
assert len(manifest["files"]) == 20
assert sum(f["bytes"] for f in manifest["files"]) == 632314500
assert (resources / "LICENSE").is_file()
assert (resources / "THIRD_PARTY_NOTICES.md").is_file()
assert (resources / "Licenses/Parakeet/CC-BY-4.0.txt").is_file()
assert (resources / "AppIcon.icns").stat().st_size > 0
for p in app.rglob("*"):
    assert not p.is_symlink(), p
    if p.is_file():
        assert p.suffix.lower() not in {".pem", ".p12", ".pfx", ".key", ".caf", ".wav", ".log"}, p
        assert p.name not in {"luxtts_en_us_g2p_aux.json", "luxtts_en_us_lexicon.tsv.zz"}, p
        assert ".mlmodelc" not in p.as_posix(), p
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
signature = subprocess.run(["codesign", "-d", "--verbose=4", str(app)], capture_output=True, text=True, check=True).stderr
assert "runtime" in signature, "Hardened Runtime is missing"
if info["signing"] == "preview":
    assert "Signature=adhoc" in signature
entitlements = subprocess.check_output(["codesign", "-d", "--entitlements", ":-", str(app)], stderr=subprocess.DEVNULL)
assert plistlib.loads(entitlements) == {"com.apple.security.device.audio-input": True}
print(f"Verified {plist['CFBundleShortVersionString']} ({plist['CFBundleVersion']}): arm64, resources, licenses, signature, audio entitlement; no bundled models.")

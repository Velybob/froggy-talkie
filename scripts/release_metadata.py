#!/usr/bin/env python3
"""Write portable build provenance; never include usernames or local paths."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
app, mode = Path(sys.argv[1]), sys.argv[2]
pins = json.loads((root / "Package.resolved").read_text())["pins"]
manifest = root / "Sources/DictationModels/Resources/parakeet-ultra.json"
inputs = sorted({p for pattern in ["Sources/**/*.swift", "Sources/DictationModels/Resources/*.json",
    "Package.swift", "Package.resolved", "Assets/AppIcon.png", "VERSION", "BUILD_NUMBER", "packaging/*"]
    for p in root.glob(pattern) if p.is_file()})
info = {
    "version": (root / "VERSION").read_text().strip(),
    "build": (root / "BUILD_NUMBER").read_text().strip(),
    "architecture": "arm64", "minimum_macos": "15.0",
    "swift": subprocess.check_output(["swift", "--version"], text=True).strip(),
    "sdk": subprocess.check_output(["xcrun", "--show-sdk-version"], text=True).strip(),
    "signing": mode, "notarized": False,
    "dependencies": [{"identity": p["identity"], **p["state"]} for p in pins],
    "model_manifest_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(),
    "models_included": False,
    "source_files_sha256": {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},
}
(app / "Contents/Resources/build-info.json").write_text(json.dumps(info, indent=2) + "\n")

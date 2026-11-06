#!/usr/bin/env python3
"""Export a reviewed allowlist, never the entire working directory or Git index."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import zipfile

root = Path(__file__).resolve().parents[1]
version = (root / "VERSION").read_text().strip()
output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / "release" / version
source = output / "FroggyTalkie-source"
archive = output / f"Froggy-Talkie-{version}-source.zip"
if source.exists() or archive.exists():
    raise SystemExit("Source export already exists. Choose a new output directory.")
patterns = [
    "Package.swift", "Package.resolved", "VERSION", "BUILD_NUMBER", ".gitignore",
    "LICENSE", "README.md", "THIRD_PARTY_NOTICES.md", "Assets/AppIcon.png",
    "Sources/**/*.swift", "Sources/DictationModels/Resources/parakeet-ultra.json",
    "Tests/**/*.swift", "Licenses/**/*", "docs/*.md", "packaging/Release.entitlements",
    "scripts/build_release.sh", "scripts/build_app_icon.sh", "scripts/render_app_icon.swift",
    "scripts/export_source.py", "scripts/release_metadata.py", "scripts/verify_release.py",
    "scripts/render_ui.swift", "scripts/check_appearance.swift",
    "scripts/download_models.py", "scripts/check_distribution.py",
]
paths = sorted({p for pattern in patterns for p in root.glob(pattern) if p.is_file()})
for p in paths:
    relative = p.relative_to(root)
    if p.is_symlink() or not p.resolve().is_relative_to(root) or any((root / parent).is_symlink() for parent in relative.parents) or any(part.startswith(".") for part in relative.parts[:-1]):
        raise SystemExit(f"Unexpected export path: {p.relative_to(root)}")
    if p.suffix.lower() in {".pem", ".key", ".p12", ".pfx", ".log", ".caf", ".wav"}:
        raise SystemExit(f"Unexpected export file: {p.relative_to(root)}")
output.mkdir(parents=True, exist_ok=True)
source.mkdir()
hashes = {}
for p in paths:
    relative = p.relative_to(root)
    destination = source / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(p, destination)
    destination.chmod(0o644)
    hashes[relative.as_posix()] = hashlib.sha256(destination.read_bytes()).hexdigest()
(source / "SOURCE_MANIFEST.json").write_text(json.dumps(hashes, indent=2, sort_keys=True) + "\n")
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for p in sorted(source.rglob("*")):
        if p.is_file():
            item = zipfile.ZipInfo("FroggyTalkie/" + p.relative_to(source).as_posix(), date_time=(2026, 1, 1, 0, 0, 0))
            item.external_attr = 0o100644 << 16
            item.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(item, p.read_bytes())
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
archive.with_suffix(".zip.sha256").write_text(f"{digest}  {archive.name}\n")
print(f"Exported {len(paths)} files: {archive}")

#!/usr/bin/env python3
"""Audit a source export and an app archive for accidental local artifacts."""
import hashlib
import json
from pathlib import Path
import re
import sys
import zipfile

source, app_zip = Path(sys.argv[1]), Path(sys.argv[2])
manifest = json.loads((source / "SOURCE_MANIFEST.json").read_text())
actual = {p.relative_to(source).as_posix() for p in source.rglob("*") if p.is_file()}
assert actual == set(manifest) | {"SOURCE_MANIFEST.json"}
secret = re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,}")
home = str(Path.home()).encode()
for name, digest in manifest.items():
    path = source / name
    assert not path.is_symlink()
    data = path.read_bytes()
    assert hashlib.sha256(data).hexdigest() == digest, name
    assert not secret.search(data), name
    assert home not in data, name
    assert not any(part in {"research", "output", "signing", "Models", ".git", ".cache", ".build", "dist"} for part in Path(name).parts), name
with zipfile.ZipFile(app_zip) as archive:
    bad_suffixes = {".caf", ".wav", ".m4a", ".log", ".pem", ".key", ".p12", ".pfx"}
    for item in archive.infolist():
        path = Path(item.filename)
        assert not path.is_absolute() and ".." not in path.parts, item.filename
        assert path.suffix.lower() not in bad_suffixes, item.filename
        assert not any(part in {".git", ".build", ".cache", "research", "Models", "signing"} for part in path.parts), item.filename
        if not item.is_dir():
            data = archive.read(item)
            assert not secret.search(data), item.filename
            assert home not in data, item.filename
    build_files = [p for p in archive.namelist() if p.endswith(".app/Contents/Resources/build-info.json")]
    assert len(build_files) == 1
    build = json.loads(archive.read(build_files[0]))
    for name, digest in build["source_files_sha256"].items():
        assert manifest.get(name) == digest, f"App/source mismatch: {name}"
print(f"Distribution audit passed: {len(manifest)} allowlisted sources; archive has no detected personal paths, keys, recordings or development directories.")

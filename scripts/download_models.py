#!/usr/bin/env python3
"""Optional command-line installer for the exact same pinned GUI model (Python 3.9+)."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
from urllib.request import HTTPRedirectHandler, Request, build_opener
import uuid


class HTTPSRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        if not newurl.startswith("https://"):
            raise ValueError("Refusing a non-HTTPS redirect")
        return super().redirect_request(request, fp, code, msg, headers, newurl)


def matches(path, entry):
    if path.is_symlink() or not path.is_file() or path.stat().st_size != entry["bytes"]:
        return False
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest() == entry["sha256"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path.home() / "Library/Application Support/Froggy Talkie/Models")
    parser.add_argument("--verify-only", action="store_true", help="Verify local files without network or writes")
    args = parser.parse_args()
    opener = build_opener(HTTPSRedirectHandler())
    manifest = json.loads((Path(__file__).resolve().parents[1] / "Sources/DictationModels/Resources/parakeet-ultra.json").read_text())
    assert manifest["repository"] == "FluidInference/parakeet-ultra-coreml"
    assert manifest["revision"] == "95eaa59a39d4394f047a4dc5cce480388a60d1b6"
    assert manifest["directory"] == "parakeet-ultra-coreml"
    root = args.directory.expanduser().resolve()
    destination = root / manifest["directory"]
    for entry in manifest["files"]:
        path = entry["path"]
        assert path and all(part not in ("", ".", "..") for part in path.split("/"))
        assert all(char.isascii() and (char.isalnum() or char in "-._/") for char in path)
        for node in [destination, *(destination / path).parents]:
            if node == root: break
            if node.is_symlink(): raise ValueError("Model directory contains a symbolic link")
    if all(matches(destination / entry["path"], entry) for entry in manifest["files"]):
        print("Verified all 20 model files; no download needed.")
        return
    if args.verify_only: raise SystemExit("Missing or corrupt model files.")
    root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".froggy-model-", dir=root) as temporary:
        staging = Path(temporary) / manifest["directory"]
        staging.mkdir()
        for entry in manifest["files"]:
            target = staging / entry["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            existing = destination / entry["path"]
            if matches(existing, entry):
                shutil.copyfile(existing, target)
            else:
                url = f"https://huggingface.co/{manifest['repository']}/resolve/{manifest['revision']}/{entry['path']}"
                print(f"Downloading {entry['path']} ({entry['bytes']} bytes)", flush=True)
                request = Request(url, headers={"User-Agent": "FroggyTalkie/0.5", "Accept-Encoding": "identity"})
                with opener.open(request, timeout=60) as response, target.open("wb") as output:
                    if response.status != 200 or not response.url.startswith("https://"):
                        raise ValueError("Unexpected server response")
                    size = 0
                    while chunk := response.read(1024 * 1024):
                        size += len(chunk)
                        if size > entry["bytes"]: raise ValueError("File exceeds expected size")
                        output.write(chunk)
            if not matches(target, entry): raise ValueError(f"Integrity check failed: {entry['path']}")
        backup = root / f"{manifest['directory']}-previous-{uuid.uuid4()}"
        had_previous = destination.exists()
        if had_previous: destination.rename(backup)
        try: staging.rename(destination)
        except OSError:
            if had_previous: backup.rename(destination)
            raise
    print(f"Ready: {destination}")


if __name__ == "__main__":
    main()

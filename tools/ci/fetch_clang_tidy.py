#!/usr/bin/env python3
"""Fetch a pinned clang-tidy binary from its PyPI wheel, without pip or a venv.

  fetch_clang_tidy.py <dest dir> [version]   -> prints the clang-tidy path

The wheel's sha256 is checked against the digest PyPI publishes for it. The
clang-tidy executable and its builtin-header resource directory are extracted.
"""
import hashlib
import json
import os
import platform
import stat
import sys
import urllib.request
import zipfile

DEFAULT_VERSION = "22.1.8"


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__.strip())
    dest = sys.argv[1]
    version = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_VERSION
    arch = {"x86_64": "x86_64", "amd64": "x86_64", "aarch64": "aarch64", "arm64": "aarch64"}.get(platform.machine().lower())
    if arch is None:
        sys.exit("fetch_clang_tidy: unsupported architecture %s" % platform.machine())

    with urllib.request.urlopen("https://pypi.org/pypi/clang-tidy/%s/json" % version) as response:
        meta = json.load(response)
    wheels = [entry for entry in meta["urls"]
              if entry["filename"].endswith(".whl") and "manylinux" in entry["filename"] and arch in entry["filename"]]
    if not wheels:
        sys.exit("fetch_clang_tidy: no manylinux %s wheel for clang-tidy %s" % (arch, version))
    wheel = wheels[0]

    with urllib.request.urlopen(wheel["url"]) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != wheel["digests"]["sha256"]:
        sys.exit("fetch_clang_tidy: sha256 mismatch for %s" % wheel["filename"])

    os.makedirs(dest, exist_ok=True)
    wheel_path = os.path.join(dest, wheel["filename"])
    with open(wheel_path, "wb") as handle:
        handle.write(data)
    with zipfile.ZipFile(wheel_path) as archive:
        member = next((name for name in archive.namelist() if name.endswith("/bin/clang-tidy")), None)
        if member is None:
            sys.exit("fetch_clang_tidy: clang-tidy binary not found in %s" % wheel["filename"])
        # Extract the whole data tree: clang-tidy finds its builtin headers
        # (stddef.h and friends) in ../lib/clang/<major>/include next to bin/.
        data_root = member[: -len("bin/clang-tidy")]
        for name in archive.namelist():
            if name.startswith(data_root):
                archive.extract(name, dest)
    binary = os.path.join(dest, member)
    os.chmod(binary, os.stat(binary).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    print(binary)


if __name__ == "__main__":
    main()

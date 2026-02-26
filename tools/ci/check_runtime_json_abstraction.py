#!/usr/bin/env python3
"""Fail when runtime sources bypass ALNJSONSerialization abstraction."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import List


ALLOWED_RELATIVE_PATHS = {
    "src/Arlen/Support/ALNJSONSerialization.m",
}


def runtime_sources(root: Path) -> List[Path]:
    paths: List[Path] = []
    for extension in ("*.m", "*.h"):
        paths.extend(root.rglob(extension))
    return sorted(paths)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate runtime sources only use ALNJSONSerialization abstraction"
    )
    parser.add_argument("--repo-root", default=".")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    src_root = repo_root / "src" / "Arlen"
    if not src_root.exists():
        raise SystemExit(f"runtime source root not found: {src_root}")

    violations: List[str] = []
    for path in runtime_sources(src_root):
        relative = path.relative_to(repo_root).as_posix()
        if relative.startswith("src/Arlen/Support/third_party/yyjson/"):
            continue
        if relative in ALLOWED_RELATIVE_PATHS:
            continue

        contents = path.read_text(encoding="utf-8")
        if "NSJSONSerialization" in contents:
            violations.append(relative)

    if violations:
        print("runtime JSON abstraction violations detected:")
        for relative in violations:
            print(f"  - {relative}")
        print("Use ALNJSONSerialization instead of direct NSJSONSerialization in runtime code.")
        return 1

    print("runtime JSON abstraction check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Keep the framework version, release notes, and release tags in agreement.

Checks, on every run:
- ALNModuleSystemFrameworkVersion in src/Arlen/Core/ALNModuleSystem.m is a
  semantic version (MAJOR.MINOR.PATCH).
- docs/RELEASE_NOTES.md opens with an `## Unreleased` section, followed by a
  `## <version> — <YYYY-MM-DD>` section for the latest release.
- That latest released version equals the framework version constant.

With --tag (used by the release workflow), also checks that the tag is
`v<framework version>`.
"""
import argparse
import re
import sys
from pathlib import Path

VERSION_SOURCE = "src/Arlen/Core/ALNModuleSystem.m"
RELEASE_NOTES = "docs/RELEASE_NOTES.md"

SEMVER = r"\d+\.\d+\.\d+"
CONSTANT_PATTERN = re.compile(
    r'ALNModuleSystemFrameworkVersion\s*=\s*@"(?P<version>[^"]*)"'
)
RELEASE_HEADING = re.compile(
    rf"^## (?P<version>{SEMVER}) — (?P<date>\d{{4}}-\d{{2}}-\d{{2}})$"
)


def framework_version(repo_root: Path, errors) -> str:
    text = (repo_root / VERSION_SOURCE).read_text(encoding="utf-8")
    match = CONSTANT_PATTERN.search(text)
    if match is None:
        errors.append(f"{VERSION_SOURCE}: ALNModuleSystemFrameworkVersion not found")
        return ""
    version = match.group("version")
    if not re.fullmatch(SEMVER, version):
        errors.append(f"{VERSION_SOURCE}: framework version `{version}` is not MAJOR.MINOR.PATCH")
    return version


def latest_released_version(repo_root: Path, errors) -> str:
    text = (repo_root / RELEASE_NOTES).read_text(encoding="utf-8")
    headings = [line for line in text.splitlines() if line.startswith("## ")]
    if not headings or headings[0] != "## Unreleased":
        errors.append(f"{RELEASE_NOTES}: first section must be `## Unreleased`")
        return ""
    if len(headings) < 2:
        errors.append(f"{RELEASE_NOTES}: missing a released `## <version> — <date>` section")
        return ""
    match = RELEASE_HEADING.match(headings[1])
    if match is None:
        errors.append(
            f"{RELEASE_NOTES}: second section must look like `## 1.2.3 — 2026-01-31`, "
            f"found `{headings[1]}`"
        )
        return ""
    return match.group("version")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate release version consistency.")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--tag", help="release tag to validate, e.g. v0.1.0")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    errors = []

    version = framework_version(repo_root, errors)
    released = latest_released_version(repo_root, errors)

    if version and released and version != released:
        errors.append(
            f"framework version `{version}` ({VERSION_SOURCE}) does not match the latest "
            f"released version `{released}` ({RELEASE_NOTES})"
        )
    if args.tag is not None and version and args.tag != f"v{version}":
        errors.append(f"release tag `{args.tag}` does not match framework version `v{version}`")

    if errors:
        for error in errors:
            print(f"release-version: {error}", file=sys.stderr)
        return 1

    suffix = f" (tag {args.tag})" if args.tag is not None else ""
    print(f"release-version: framework version {version} matches release notes{suffix}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

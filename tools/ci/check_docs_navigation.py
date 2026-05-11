#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def require_contains(errors, haystack: str, needle: str, label: str) -> None:
    if needle not in haystack:
        errors.append(f"{label}: missing expected text: {needle}")


def require_not_contains(errors, haystack: str, needle: str, label: str) -> None:
    if needle in haystack:
        errors.append(f"{label}: found stale text: {needle}")


def require_order(errors, haystack: str, first: str, second: str, label: str) -> None:
    first_index = haystack.find(first)
    second_index = haystack.find(second)
    if first_index == -1 or second_index == -1:
        errors.append(f"{label}: missing expected ordering markers: {first} / {second}")
        return
    if first_index >= second_index:
        errors.append(f"{label}: expected `{first}` before `{second}`")


def require_file(errors, path: Path, repo_root: Path) -> None:
    if not path.exists():
        rel = path.relative_to(repo_root).as_posix()
        errors.append(f"missing expected documentation file: {rel}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate newcomer-facing docs navigation surfaces.")
    parser.add_argument("--repo-root", required=True)
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    readme = read_text(repo_root / "README.md")
    docs_readme = read_text(repo_root / "docs" / "README.md")

    errors = []

    require_contains(errors, readme, "## Start Here", "README.md")
    require_contains(errors, readme, "## Quick Start", "README.md")
    require_contains(errors, readme, "## Status", "README.md")
    require_order(errors, readme, "## Start Here", "## Status", "README.md")
    require_order(errors, readme, "## Quick Start", "## Status", "README.md")
    require_contains(errors, readme, "docs/FIRST_APP_GUIDE.md", "README.md")
    require_contains(errors, readme, "docs/APP_AUTHORING_GUIDE.md", "README.md")
    require_contains(errors, readme, "docs/README.md", "README.md")

    # docs/README.md is the curated user-facing index. It must group user docs
    # by reader intent and must not surface engineering/historical material at
    # the top level. See docs/DOCUMENTATION_POLICY.md section 10.
    for marker in [
        "## Start Here",
        "## Building Apps",
        "## Modules",
        "## Data Layer",
        "## Operations and Deployment",
        "## Reference",
        "## Migration Guides",
        "## Examples",
        "## Contributing and Internal Material",
    ]:
        require_contains(errors, docs_readme, marker, "docs/README.md")

    require_contains(errors, docs_readme, "[App Authoring Guide](APP_AUTHORING_GUIDE.md)", "docs/README.md")
    require_contains(errors, docs_readme, "[Configuration Reference](CONFIGURATION_REFERENCE.md)", "docs/README.md")
    require_contains(errors, docs_readme, "[Lite Mode Guide](LITE_MODE_GUIDE.md)", "docs/README.md")
    require_contains(errors, docs_readme, "[Plugin + Service Guide](PLUGIN_SERVICE_GUIDE.md)", "docs/README.md")
    require_contains(errors, docs_readme, "[Frontend Starters Guide](FRONTEND_STARTERS.md)", "docs/README.md")
    require_contains(errors, docs_readme, "[Documentation Policy](DOCUMENTATION_POLICY.md)", "docs/README.md")
    require_contains(errors, docs_readme, "internal/", "docs/README.md")

    # The curated index must not surface phase-numbered, dated, or
    # app-specific reconciliation documents at the user-facing layer.
    for stale_pattern in [
        "PHASE",
        "SESSION_HANDOFF_",
        "_RECONCILIATION_",
        "CONCURRENCY_AUDIT_",
        "BENCHMARK_HANDOFF_",
    ]:
        # Allow references to docs/internal/<stale_pattern>… but reject
        # references to <stale_pattern> at the docs/ root layer.
        for line in docs_readme.splitlines():
            if stale_pattern in line and "internal/" not in line and "](" in line:
                errors.append(
                    f"docs/README.md: stale user-facing link to {stale_pattern} material: {line.strip()}"
                )

    for rel_path in [
        "docs/APP_AUTHORING_GUIDE.md",
        "docs/CONFIGURATION_REFERENCE.md",
        "docs/LITE_MODE_GUIDE.md",
        "docs/PLUGIN_SERVICE_GUIDE.md",
        "docs/FRONTEND_STARTERS.md",
        "docs/DOCUMENTATION_POLICY.md",
        "docs/STATUS.md",
        "docs/internal",
    ]:
        require_file(errors, repo_root / rel_path, repo_root)

    if errors:
        for error in errors:
            print(f"docs-navigation: {error}", file=sys.stderr)
        return 1

    print("docs-navigation: newcomer docs surfaces aligned")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

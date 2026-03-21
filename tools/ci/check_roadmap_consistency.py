#!/usr/bin/env python3
import argparse
import re
import sys
from pathlib import Path


def read_text(repo_root: Path, rel_path: str) -> str:
    return (repo_root / rel_path).read_text(encoding="utf-8")


def require_contains(errors, haystack: str, needle: str, label: str):
    if needle not in haystack:
        errors.append(f"{label}: missing expected text: {needle}")


def require_not_contains(errors, haystack: str, needle: str, label: str):
    if needle in haystack:
        errors.append(f"{label}: found stale text: {needle}")


def require_regex(errors, haystack: str, pattern: str, label: str):
    if not re.search(pattern, haystack, re.MULTILINE):
        errors.append(f"{label}: missing expected pattern: {pattern}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate roadmap/status summaries stay aligned")
    parser.add_argument("--repo-root", required=True)
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    errors = []

    readme = read_text(repo_root, "README.md")
    docs_readme = read_text(repo_root, "docs/README.md")
    docs_status = read_text(repo_root, "docs/STATUS.md")
    phase7 = read_text(repo_root, "docs/PHASE7_ROADMAP.md")
    phase18 = read_text(repo_root, "docs/PHASE18_ROADMAP.md")
    phase2_phase3 = read_text(repo_root, "docs/PHASE2_PHASE3_ROADMAP.md")
    eoc_v1 = read_text(repo_root, "docs/EOC_V1_ROADMAP.md")

    require_regex(
        errors,
        phase7,
        r"^Status: Complete for current first-party scope",
        "docs/PHASE7_ROADMAP.md",
    )
    require_contains(
        errors,
        readme,
        "Phase 7: complete for current first-party scope",
        "README.md",
    )
    require_contains(
        errors,
        docs_status,
        "Phase 7: complete for current first-party scope",
        "docs/STATUS.md",
    )
    require_not_contains(
        errors,
        readme,
        "Phase 7A: initial slice implemented",
        "README.md",
    )
    require_not_contains(
        errors,
        docs_status,
        "Phase 7A: initial slice implemented",
        "docs/STATUS.md",
    )

    require_regex(
        errors,
        phase18,
        r"^Status: complete on 2026-03-14 \(`18A-18H`\)",
        "docs/PHASE18_ROADMAP.md",
    )
    require_contains(
        errors,
        readme,
        "Phase 18: complete (`18A-18H` delivered on 2026-03-14",
        "README.md",
    )
    require_contains(
        errors,
        docs_status,
        "Phase 18: complete (`18A-18H` delivered on 2026-03-14",
        "docs/STATUS.md",
    )

    require_regex(
        errors,
        eoc_v1,
        r"^Status: Complete with follow-on backlog$",
        "docs/EOC_V1_ROADMAP.md",
    )
    require_not_contains(
        errors,
        eoc_v1,
        "## Suggested Immediate Next Steps",
        "docs/EOC_V1_ROADMAP.md",
    )
    require_contains(
        errors,
        eoc_v1,
        "## Post-v1 Follow-On Backlog",
        "docs/EOC_V1_ROADMAP.md",
    )

    require_contains(
        errors,
        phase2_phase3,
        "Status: Historical aggregate index",
        "docs/PHASE2_PHASE3_ROADMAP.md",
    )
    require_contains(
        errors,
        docs_readme,
        "[Combined Roadmap Index (Historical Aggregate)](PHASE2_PHASE3_ROADMAP.md)",
        "docs/README.md",
    )

    if errors:
        for error in errors:
            print(f"roadmap-consistency: {error}", file=sys.stderr)
        return 1

    print("roadmap-consistency: summary docs aligned")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

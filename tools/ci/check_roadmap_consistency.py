#!/usr/bin/env python3
"""
Validate that the user-facing status/roadmap surface stays well-formed.

This script enforces the contract from docs/DOCUMENTATION_POLICY.md section 10:
user-facing docs describe capabilities, not phase numbers. Engineering history
lives under docs/internal/ and is intentionally not policed here.

What this gate guards:
- docs/STATUS.md is a one-page capability snapshot with the expected sections.
- README.md's status summary references docs/STATUS.md and docs/internal/.
- docs/README.md's contributing section points at docs/internal/.
- User-facing copy does NOT smuggle phase IDs back in.
"""
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


def require_no_regex(errors, haystack: str, pattern: str, label: str):
    if re.search(pattern, haystack, re.MULTILINE):
        errors.append(f"{label}: found forbidden pattern: {pattern}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate user-facing status/roadmap surface")
    parser.add_argument("--repo-root", required=True)
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    errors = []

    readme = read_text(repo_root, "README.md")
    docs_readme = read_text(repo_root, "docs/README.md")
    docs_status = read_text(repo_root, "docs/STATUS.md")

    # docs/STATUS.md must be a capability-level snapshot, not the engineering
    # journal. See docs/internal/STATUS_HISTORY.md for the journal.
    for marker in [
        "## Platform Support",
        "## Capability Maturity",
        "### Shipped",
        "### Preview",
        "### In Flight",
    ]:
        require_contains(errors, docs_status, marker, "docs/STATUS.md")

    require_contains(errors, docs_status, "Linux", "docs/STATUS.md")
    require_contains(errors, docs_status, "macOS", "docs/STATUS.md")
    require_contains(errors, docs_status, "Windows", "docs/STATUS.md")
    require_contains(errors, docs_status, "docs/internal/", "docs/STATUS.md")

    # The capability table should mention each first-party module by name.
    for module in ["auth", "admin-ui", "jobs", "notifications", "storage", "ops", "search"]:
        require_contains(errors, docs_status, module, "docs/STATUS.md")

    # Phase IDs must not appear in the user-facing status snapshot or the
    # README status summary. Engineering history references must be qualified
    # by the docs/internal/ path.
    forbidden_phase_id = r"\bPhase\s*\d"
    require_no_regex(errors, docs_status, forbidden_phase_id, "docs/STATUS.md")

    # The README status summary should point at docs/STATUS.md and
    # docs/internal/ rather than naming specific phase roadmaps.
    require_contains(errors, readme, "docs/STATUS.md", "README.md")
    require_contains(errors, readme, "docs/internal/", "README.md")
    require_no_regex(
        errors,
        readme,
        r"docs/PHASE\d+_ROADMAP\.md",
        "README.md",
    )

    # The curated docs index points at docs/internal/ for historical material.
    require_contains(errors, docs_readme, "internal/", "docs/README.md")
    require_no_regex(
        errors,
        docs_readme,
        r"\]\(PHASE\d+",
        "docs/README.md",
    )
    require_no_regex(
        errors,
        docs_readme,
        r"\]\(SESSION_HANDOFF_",
        "docs/README.md",
    )

    # docs/internal/ must exist as the home of engineering history.
    internal_dir = repo_root / "docs" / "internal"
    if not internal_dir.is_dir():
        errors.append("docs/internal/: expected engineering-history directory is missing")
    else:
        # Sanity: at least one PHASE roadmap should live under docs/internal/.
        any_phase = any(p.name.startswith("PHASE") for p in internal_dir.iterdir())
        if not any_phase:
            errors.append("docs/internal/: expected at least one PHASE*_ROADMAP.md under engineering-history")

    if errors:
        for error in errors:
            print(f"roadmap-consistency: {error}", file=sys.stderr)
        return 1

    print("roadmap-consistency: user-facing status surface aligned")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

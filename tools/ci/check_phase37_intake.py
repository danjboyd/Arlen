#!/usr/bin/env python3
"""Validate Phase 37 regression-intake fixtures and docs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"{path}: expected object")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Phase 37 regression intake rules")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--output", default="build/release_confidence/phase37/intake_summary.json")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    errors: list[str] = []
    manifest = load_json(repo_root / "tests/fixtures/phase37/acceptance_sites.json")
    public_contract = (repo_root / "docs/PUBLIC_TEST_CONTRACT.md").read_text(encoding="utf-8")
    testing_workflow = (repo_root / "docs/TESTING_WORKFLOW.md").read_text(encoding="utf-8")

    checklist_terms = [
        ("focused unit/regression test",),
        ("checked-in fixture/corpus case",),
        ("acceptance probe",),
        ("docs update", "Update user-facing docs"),
    ]
    for terms in checklist_terms:
        if not any(term in public_contract or term in testing_workflow for term in terms):
            errors.append(f"missing regression intake checklist term: {terms[0]}")

    site_ids: set[str] = set()
    for site in manifest.get("sites", []):
        if not isinstance(site, dict):
            errors.append("acceptance site entry is not an object")
            continue
        site_id = site.get("id")
        if not isinstance(site_id, str) or not site_id:
            errors.append("acceptance site missing id")
            continue
        if site_id in site_ids:
            errors.append(f"duplicate acceptance site id: {site_id}")
        site_ids.add(site_id)
        if not site_id.replace("_", "").isalnum():
            errors.append(f"acceptance site id is not stable snake_case: {site_id}")
        if not isinstance(site.get("description"), str) or len(site.get("description", "")) < 12:
            errors.append(f"{site_id}: missing useful description")
        if site.get("mode", "fast") == "runtime":
            if not site.get("runtimeVariantOf"):
                errors.append(f"{site_id}: runtime site missing runtimeVariantOf")
            if not isinstance(site.get("requiredEnvironment"), list) or not site["requiredEnvironment"]:
                errors.append(f"{site_id}: runtime site missing requiredEnvironment")
        for probe in site.get("probes", []):
            if isinstance(probe, dict) and not probe.get("id"):
                errors.append(f"{site_id}: probe missing stable id")
        for check in site.get("staticChecks", []):
            if not isinstance(check, dict):
                errors.append(f"{site_id}: static check is not an object")
                continue
            rel_path = check.get("path")
            if not isinstance(rel_path, str) or not (repo_root / rel_path).exists():
                errors.append(f"{site_id}: static check path missing: {rel_path}")

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "version": "phase37-intake-check-v1",
        "status": "pass" if not errors else "fail",
        "site_count": len(site_ids),
        "errors": errors,
    }
    output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if errors:
        for error in errors:
            print(f"phase37-intake: {error}")
        return 1
    print(f"phase37-intake: validated {len(site_ids)} acceptance site entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

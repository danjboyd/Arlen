#!/usr/bin/env python3
"""Generate Phase 21 confidence artifacts from focused lane outputs."""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


VERSION = "phase21-confidence-v1"

PASS_PATTERNS = (
    r"\btests PASSED\b",
    r"Test Suite 'All tests' passed",
    r"Executed \d+ tests?, with 0 failures",
)


def load_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"expected object JSON at {path}")
    return payload


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def template_tests_passed(template_text: str) -> bool:
    for pattern in PASS_PATTERNS:
        if re.search(pattern, template_text):
            return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 21 confidence artifacts")
    parser.add_argument("--output-dir", default="build/release_confidence/phase21")
    parser.add_argument("--template-log", required=True)
    parser.add_argument("--protocol-manifest", required=True)
    parser.add_argument("--generated-app-manifest", required=True)
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    template_log = Path(args.template_log).resolve()
    protocol_manifest = load_json(Path(args.protocol_manifest).resolve())
    generated_app_manifest = load_json(Path(args.generated_app_manifest).resolve())

    template_text = template_log.read_text(encoding="utf-8")
    template_status = "pass" if template_tests_passed(template_text) else "fail"

    lane_statuses = {
        "template_tests": template_status,
        "protocol_corpus": str(protocol_manifest.get("status", "fail")),
        "generated_app_matrix": str(generated_app_manifest.get("status", "fail")),
    }
    overall_status = "pass" if all(value == "pass" for value in lane_statuses.values()) else "fail"
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    eval_payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "lanes": lane_statuses,
        "artifacts": [
            template_log.name,
            "protocol/manifest.json",
            "generated_apps/manifest.json",
        ],
    }
    write_json(output_dir / "phase21_confidence_eval.json", eval_payload)
    markdown = "\n".join(
        [
            "# Phase 21 Confidence",
            "",
            f"Generated at: `{generated_at}`",
            "",
            f"- Template tests: `{lane_statuses['template_tests']}`",
            f"- Protocol corpus: `{lane_statuses['protocol_corpus']}`",
            f"- Generated-app matrix: `{lane_statuses['generated_app_matrix']}`",
            f"- Overall status: `{overall_status}`",
            "",
            "Focused entrypoints:",
            "",
            "- `make phase21-template-tests`",
            "- `make phase21-protocol-tests`",
            "- `make phase21-generated-app-tests`",
            "- `make phase21-focused`",
            "- `make phase21-confidence`",
            "",
        ]
    )
    (output_dir / "phase21_confidence.md").write_text(markdown, encoding="utf-8")
    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "artifacts": [
            "phase21_confidence_eval.json",
            "phase21_confidence.md",
            template_log.name,
            "protocol/manifest.json",
            "generated_apps/manifest.json",
        ],
    }
    write_json(output_dir / "manifest.json", manifest)
    print(f"phase21-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())

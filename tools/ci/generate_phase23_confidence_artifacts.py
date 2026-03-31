#!/usr/bin/env python3
"""Generate Phase 23 confidence artifacts from focused lane outputs."""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


VERSION = "phase23-confidence-v1"

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


def log_passed(text: str) -> bool:
    for pattern in PASS_PATTERNS:
        if re.search(pattern, text):
            return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 23 confidence artifacts")
    parser.add_argument("--output-dir", default="build/release_confidence/phase23")
    parser.add_argument("--dataverse-log", required=True)
    parser.add_argument("--live-manifest", required=True)
    parser.add_argument("--live-log", required=True)
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    dataverse_log = Path(args.dataverse_log).resolve()
    live_manifest = load_json(Path(args.live_manifest).resolve())
    live_log = Path(args.live_log).resolve()

    dataverse_text = dataverse_log.read_text(encoding="utf-8")
    dataverse_status = "pass" if log_passed(dataverse_text) else "fail"
    live_status = str(live_manifest.get("status", "fail"))
    overall_status = (
        "pass"
        if dataverse_status == "pass" and live_status in {"pass", "skipped"}
        else "fail"
    )
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    eval_payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "lanes": {
            "dataverse_tests": dataverse_status,
            "live_codegen": live_status,
        },
        "artifacts": [
            dataverse_log.name,
            "live/manifest.json",
            live_log.name,
        ],
    }
    write_json(output_dir / "phase23_confidence_eval.json", eval_payload)

    markdown = "\n".join(
        [
            "# Phase 23 Confidence",
            "",
            f"Generated at: `{generated_at}`",
            "",
            f"- Dataverse tests: `{dataverse_status}`",
            f"- Live codegen: `{live_status}`",
            f"- Overall status: `{overall_status}`",
            "",
            "Focused entrypoints:",
            "",
            "- `make phase23-dataverse-tests`",
            "- `make phase23-focused`",
            "- `make phase23-confidence`",
            "",
            "Notes:",
            "",
            "- Live codegen is optional and is marked `skipped` when `ARLEN_DATAVERSE_*` credentials are not fully present.",
            "- When credentials are present, the confidence runner writes artifacts under `build/release_confidence/phase23/live/`.",
            "",
        ]
    )
    (output_dir / "phase23_confidence.md").write_text(markdown, encoding="utf-8")

    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "artifacts": [
            "phase23_confidence_eval.json",
            "phase23_confidence.md",
            dataverse_log.name,
            live_log.name,
            "live/manifest.json",
        ],
    }
    write_json(output_dir / "manifest.json", manifest)
    print(f"phase23-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())

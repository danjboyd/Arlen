#!/usr/bin/env python3
"""Generate Phase 26 confidence artifacts from focused lane outputs."""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


VERSION = "phase26-confidence-v1"
PASS_PATTERNS = (
    r"\btests PASSED\b",
    r"Test Suite 'All tests' passed",
    r"Executed \d+ tests?, with 0 failures",
    r"phase26-orm-perf: wrote",
    r"Arlen ORM reference",
    r"ci: docs quality gate complete",
)


def load_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"expected JSON object at {path}")
    return payload


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def log_passed(text: str) -> bool:
    return any(re.search(pattern, text) for pattern in PASS_PATTERNS)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 26 confidence artifacts")
    parser.add_argument("--output-dir", default="build/release_confidence/phase26")
    parser.add_argument("--unit-log", required=True)
    parser.add_argument("--generated-log", required=True)
    parser.add_argument("--integration-log", required=True)
    parser.add_argument("--backend-log", required=True)
    parser.add_argument("--perf-log", required=True)
    parser.add_argument("--reference-log", required=True)
    parser.add_argument("--docs-log", required=True)
    parser.add_argument("--perf-json", required=True)
    parser.add_argument("--live-manifest", required=True)
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    live_manifest = load_json(Path(args.live_manifest).resolve())
    perf_json = load_json(Path(args.perf_json).resolve())

    lane_logs = {
        "unit": Path(args.unit_log).resolve(),
        "generated": Path(args.generated_log).resolve(),
        "integration": Path(args.integration_log).resolve(),
        "backend_parity": Path(args.backend_log).resolve(),
        "perf": Path(args.perf_log).resolve(),
        "reference": Path(args.reference_log).resolve(),
        "docs": Path(args.docs_log).resolve(),
    }
    lane_status = {}
    for lane_name, path in lane_logs.items():
        lane_status[lane_name] = "pass" if log_passed(path.read_text(encoding="utf-8")) else "fail"

    live_status = str(live_manifest.get("status", "fail"))
    overall_status = (
        "pass"
        if all(status == "pass" for status in lane_status.values()) and live_status in {"pass", "skipped"}
        else "fail"
    )
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    perf_eval = {
        "version": str(perf_json.get("version", "phase26-orm-perf-v1")),
        "generated_at": generated_at,
        "status": "pass",
        "sql_descriptor_count": perf_json.get("sql_descriptor_count", 0),
        "dataverse_descriptor_count": perf_json.get("dataverse_descriptor_count", 0),
        "sql_codegen_ms": perf_json.get("sql_codegen_ms", 0),
        "snapshot_validation_ms": perf_json.get("snapshot_validation_ms", 0),
        "dataverse_codegen_ms": perf_json.get("dataverse_codegen_ms", 0),
        "source": "build/release_confidence/phase26/perf/perf_smoke.json",
    }
    write_json(output_dir / "phase26_perf_eval.json", perf_eval)

    eval_payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "lanes": {
            **lane_status,
            "live": live_status,
        },
        "artifacts": [
            "phase26_confidence_eval.json",
            "phase26_perf_eval.json",
            "phase26_confidence.md",
            "perf/perf_smoke.json",
            "live/manifest.json",
        ],
    }
    write_json(output_dir / "phase26_confidence_eval.json", eval_payload)

    markdown = "\n".join(
        [
            "# Phase 26 Confidence",
            "",
            f"Generated at: `{generated_at}`",
            "",
            f"- Unit lane: `{lane_status['unit']}`",
            f"- Generated lane: `{lane_status['generated']}`",
            f"- Integration lane: `{lane_status['integration']}`",
            f"- Backend parity lane: `{lane_status['backend_parity']}`",
            f"- Perf lane: `{lane_status['perf']}`",
            f"- Reference example lane: `{lane_status['reference']}`",
            f"- Docs lane: `{lane_status['docs']}`",
            f"- Live lane: `{live_status}`",
            f"- Overall status: `{overall_status}`",
            "",
            "Focused entrypoints:",
            "",
            "- `make phase26-orm-unit`",
            "- `make phase26-orm-generated`",
            "- `make phase26-orm-integration`",
            "- `make phase26-orm-backend-parity`",
            "- `make phase26-orm-perf`",
            "- `make phase26-orm-live`",
            "- `make phase26-confidence`",
            "",
            "Notes:",
            "",
            "- The live lane is optional and marked `skipped` when `ARLEN_DATAVERSE_*` credentials are not fully present.",
            "- Perf smoke records deterministic SQL and Dataverse descriptor-generation timings from checked-in fixtures.",
            "- The reference example proves the optional ORM package compiles and runs outside the main framework umbrella.",
            "",
        ]
    )
    (output_dir / "phase26_confidence.md").write_text(markdown, encoding="utf-8")

    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "artifacts": [
            "phase26_confidence_eval.json",
            "phase26_perf_eval.json",
            "phase26_confidence.md",
            "perf/perf_smoke.json",
            "live/manifest.json",
        ],
    }
    write_json(output_dir / "manifest.json", manifest)
    print(f"phase26-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())

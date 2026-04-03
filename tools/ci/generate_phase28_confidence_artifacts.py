#!/usr/bin/env python3
"""Generate Phase 28 confidence artifacts from focused lane outputs."""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


VERSION = "phase28-confidence-v1"
DOC_PASS_PATTERNS = (
    r"Generated API reference",
    r"(docs quality checks passed|ci: docs quality gate complete)",
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


def docs_passed(docs_text: str) -> bool:
    return all(re.search(pattern, docs_text) for pattern in DOC_PASS_PATTERNS)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 28 confidence artifacts")
    parser.add_argument("--output-dir", default="build/release_confidence/phase28")
    parser.add_argument("--unit-manifest", required=True)
    parser.add_argument("--generated-manifest", required=True)
    parser.add_argument("--integration-manifest", required=True)
    parser.add_argument("--react-reference-manifest", required=True)
    parser.add_argument("--generated-metrics", required=True)
    parser.add_argument("--docs-log", required=True)
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    unit_manifest = load_json(Path(args.unit_manifest).resolve())
    generated_manifest = load_json(Path(args.generated_manifest).resolve())
    integration_manifest = load_json(Path(args.integration_manifest).resolve())
    react_reference_manifest = load_json(Path(args.react_reference_manifest).resolve())
    generated_metrics = load_json(Path(args.generated_metrics).resolve())
    docs_log = Path(args.docs_log).resolve().read_text(encoding="utf-8")

    lane_statuses = {
        "ts_unit": str(unit_manifest.get("status", "fail")),
        "ts_generated": str(generated_manifest.get("status", "fail")),
        "ts_integration": str(integration_manifest.get("status", "fail")),
        "react_reference": str(react_reference_manifest.get("status", "fail")),
        "docs": "pass" if docs_passed(docs_log) else "fail",
    }
    overall_status = "pass" if all(status == "pass" for status in lane_statuses.values()) else "fail"
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    eval_payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "lanes": lane_statuses,
        "metrics": generated_metrics,
        "artifacts": [
            "ts_unit/manifest.json",
            "generated/manifest.json",
            "integration/manifest.json",
            "react_reference/manifest.json",
            "generated/generated_metrics.json",
            Path(args.docs_log).name,
        ],
    }
    write_json(output_dir / "phase28_confidence_eval.json", eval_payload)

    markdown = "\n".join(
        [
            "# Phase 28 Confidence",
            "",
            f"Generated at: `{generated_at}`",
            "",
            f"- TypeScript unit lane: `{lane_statuses['ts_unit']}`",
            f"- Generated package lane: `{lane_statuses['ts_generated']}`",
            f"- Live integration lane: `{lane_statuses['ts_integration']}`",
            f"- React reference lane: `{lane_statuses['react_reference']}`",
            f"- Docs lane: `{lane_statuses['docs']}`",
            f"- Overall status: `{overall_status}`",
            "",
            "Tracked generated-package metrics:",
            "",
            f"- Codegen duration (ms): `{generated_metrics.get('codegen_duration_ms', 0)}`",
            f"- Package bytes: `{generated_metrics.get('package_bytes', 0)}`",
            f"- Client bytes: `{generated_metrics.get('client_bytes', 0)}`",
            f"- React bytes: `{generated_metrics.get('react_bytes', 0)}`",
            "",
            "Focused entrypoints:",
            "",
            "- `make phase28-ts-unit`",
            "- `make phase28-ts-generated`",
            "- `make phase28-ts-integration`",
            "- `make phase28-react-reference`",
            "- `make phase28-confidence`",
            "",
        ]
    )
    (output_dir / "phase28_confidence.md").write_text(markdown, encoding="utf-8")

    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "artifacts": [
            "phase28_confidence_eval.json",
            "phase28_confidence.md",
            "ts_unit/manifest.json",
            "generated/manifest.json",
            "integration/manifest.json",
            "react_reference/manifest.json",
            "generated/generated_metrics.json",
            Path(args.docs_log).name,
        ],
    }
    write_json(output_dir / "manifest.json", manifest)
    print(f"phase28-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())

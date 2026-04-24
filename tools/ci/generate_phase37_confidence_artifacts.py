#!/usr/bin/env python3
"""Generate Phase 37 confidence summary artifacts."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"{path}: expected top-level object")
    return payload


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 37 confidence artifacts")
    parser.add_argument("--output-dir", default="build/release_confidence/phase37")
    parser.add_argument("--contract-summary", default="build/release_confidence/phase37/contract_summary.json")
    parser.add_argument("--eoc-golden-summary", default="build/release_confidence/phase37/eoc_golden_summary.json")
    parser.add_argument("--acceptance-manifest", default="build/release_confidence/phase37/acceptance/manifest.json")
    parser.add_argument("--intake-summary", default="build/release_confidence/phase37/intake_summary.json")
    parser.add_argument("--packaged-deploy-proof", default="build/release_confidence/phase37/packaged_deploy_proof.json")
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    contract = load_json(Path(args.contract_summary).resolve())
    eoc_golden = load_json(Path(args.eoc_golden_summary).resolve())
    acceptance = load_json(Path(args.acceptance_manifest).resolve())
    intake = load_json(Path(args.intake_summary).resolve())
    packaged_deploy = load_json(Path(args.packaged_deploy_proof).resolve())
    assertion_log = output_dir / "acceptance_assertion_selftest.log"
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    checks = {
        "public_surface_contract": contract.get("status") == "pass",
        "eoc_golden_catalog": contract.get("golden_case_count", 0) >= 4,
        "eoc_golden_execution": eoc_golden.get("status") == "pass"
        and eoc_golden.get("case_count", 0) >= 4,
        "parser_protocol_corpus": contract.get("template_parser_case_count", 0) >= 4
        and contract.get("http_protocol_case_count", 0) >= 4,
        "acceptance_harness": acceptance.get("status") == "pass",
        "acceptance_assertion_selftest": assertion_log.exists()
        and "assertion self-tests passed" in assertion_log.read_text(encoding="utf-8"),
        "acceptance_sites_37e_37j": {
            "eoc_kitchen_sink",
            "mvc_crud",
            "module_portal",
            "data_orm_reference",
            "live_ui_reference",
            "packaged_deploy",
        }.issubset({
            str(site.get("id"))
            for site in acceptance.get("sites", [])
            if isinstance(site, dict) and site.get("status") == "pass"
        }),
        "regression_intake_enforcement": intake.get("status") == "pass",
        "packaged_deploy_release_proof": packaged_deploy.get("status") == "pass",
        "contract_coverage_status_tracking": isinstance(contract.get("coverage_summary"), dict)
        and bool(contract.get("coverage_summary", {}).get("fixture_contract")),
    }
    status = "pass" if all(checks.values()) else "fail"
    eval_payload = {
        "version": "phase37-confidence-v1",
        "generated_at": generated_at,
        "status": status,
        "checks": checks,
        "contract_summary": str(Path(args.contract_summary)),
        "eoc_golden_summary": str(Path(args.eoc_golden_summary)),
        "acceptance_manifest": str(Path(args.acceptance_manifest)),
        "intake_summary": str(Path(args.intake_summary)),
        "packaged_deploy_proof": str(Path(args.packaged_deploy_proof)),
    }
    write_json(output_dir / "phase37_confidence_eval.json", eval_payload)
    markdown = "\n".join([
        "# Phase 37 Confidence",
        "",
        f"Generated at: `{generated_at}`",
        f"- Overall status: `{status}`",
        "",
        "Checks:",
        f"- public surface contract: `{checks['public_surface_contract']}`",
        f"- EOC golden catalog: `{checks['eoc_golden_catalog']}`",
        f"- EOC golden execution: `{checks['eoc_golden_execution']}`",
        f"- parser/protocol corpus: `{checks['parser_protocol_corpus']}`",
        f"- acceptance harness: `{checks['acceptance_harness']}`",
        f"- acceptance assertion self-test: `{checks['acceptance_assertion_selftest']}`",
        f"- acceptance sites 37E-37J: `{checks['acceptance_sites_37e_37j']}`",
        f"- regression intake enforcement: `{checks['regression_intake_enforcement']}`",
        f"- packaged deploy release proof: `{checks['packaged_deploy_release_proof']}`",
        f"- contract coverage status tracking: `{checks['contract_coverage_status_tracking']}`",
        "",
        "Focused entrypoints:",
        "",
        "- `make phase37-contract`",
        "- `make phase37-intake`",
        "- `make phase37-packaged-deploy-proof`",
        "- `make phase37-acceptance`",
        "- `make phase37-confidence`",
        "",
    ])
    (output_dir / "phase37_confidence.md").write_text(markdown, encoding="utf-8")
    manifest = {
        "version": "phase37-confidence-v1",
        "generated_at": generated_at,
        "status": status,
        "artifacts": [
            "contract_summary.json",
            "eoc_golden_summary.json",
            "intake_summary.json",
            "packaged_deploy_proof.json",
            "acceptance/manifest.json",
            "acceptance_assertion_selftest.log",
            "phase37_confidence_eval.json",
            "phase37_confidence.md",
        ],
    }
    write_json(output_dir / "manifest.json", manifest)
    print(f"phase37-confidence: generated artifacts in {output_dir} (status={status})")
    return 0 if status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())

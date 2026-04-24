#!/usr/bin/env python3
"""Validate Phase 37 public-surface and corpus fixtures."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


REQUIRED_SURFACES = {
    "eoc_transpiler_runtime",
    "mvc_controller_routing",
    "http_protocol",
    "middleware_security",
    "cli_generated_apps",
    "first_party_modules",
    "data_orm_dataverse",
    "live_realtime",
    "typescript_client_generation",
    "deploy_runtime",
    "windows_preview",
    "apple_baseline",
}


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"{path}: expected top-level object")
    return payload


def require(condition: bool, errors: list[str], message: str) -> None:
    if not condition:
        errors.append(message)


def path_exists(repo_root: Path, rel_path: str) -> bool:
    if ":" in rel_path:
        rel_path = rel_path.split(":", 1)[0]
    if rel_path.startswith("make ") or rel_path.endswith(" workflow"):
        return True
    if rel_path.startswith("ARLEN_") or rel_path.startswith("named remote"):
        return True
    return (repo_root / rel_path).exists()


def validate_public_surface_contract(repo_root: Path, errors: list[str]) -> dict[str, Any]:
    path = repo_root / "tests/fixtures/phase37/public_surface_contract.json"
    payload = load_json(path)
    require(payload.get("version") == "phase37-public-surface-contract-v1",
            errors,
            "public surface contract has unexpected version")
    surfaces = payload.get("surfaces")
    require(isinstance(surfaces, list) and len(surfaces) >= len(REQUIRED_SURFACES),
            errors,
            "public surface contract must contain all required surfaces")
    seen: set[str] = set()
    for entry in surfaces if isinstance(surfaces, list) else []:
        if not isinstance(entry, dict):
            errors.append("public surface contract entry is not an object")
            continue
        surface_id = entry.get("id")
        seen.add(surface_id)
        require(surface_id in REQUIRED_SURFACES,
                errors,
                f"unexpected public surface id: {surface_id}")
        require(entry.get("releaseLevel") in {"required", "conditional", "optional"},
                errors,
                f"{surface_id}: invalid releaseLevel")
        require(isinstance(entry.get("ownerArea"), str) and entry["ownerArea"],
                errors,
                f"{surface_id}: missing ownerArea")
        for field in ("focusedEvidence", "integrationEvidence", "requiredLanes", "acceptanceCoverage"):
            require(isinstance(entry.get(field), list),
                    errors,
                    f"{surface_id}: {field} must be a list")
        for evidence in entry.get("focusedEvidence", []) + entry.get("integrationEvidence", []):
            if isinstance(evidence, str):
                require(path_exists(repo_root, evidence),
                        errors,
                        f"{surface_id}: evidence path does not exist: {evidence}")
    missing = REQUIRED_SURFACES.difference(seen)
    require(not missing, errors, f"missing public surfaces: {sorted(missing)}")
    default_gate = payload.get("defaultReleaseGate")
    require(isinstance(default_gate, list) and "make phase37-contract" in default_gate,
            errors,
            "defaultReleaseGate must include make phase37-contract")
    return payload


def validate_eoc_golden_cases(repo_root: Path, errors: list[str]) -> dict[str, Any]:
    path = repo_root / "tests/fixtures/phase37/eoc_golden_render_cases.json"
    payload = load_json(path)
    require(payload.get("version") == "phase37-eoc-golden-render-cases-v1",
            errors,
            "EOC golden render fixture has unexpected version")
    cases = payload.get("cases")
    require(isinstance(cases, list) and len(cases) >= 4,
            errors,
            "EOC golden render fixture needs at least four cases")
    coverage: set[str] = set()
    for case in cases if isinstance(cases, list) else []:
        if not isinstance(case, dict):
            errors.append("EOC golden case is not an object")
            continue
        case_id = case.get("id", "<missing>")
        template = case.get("template")
        require(isinstance(template, str) and path_exists(repo_root, template),
                errors,
                f"{case_id}: missing template fixture")
        expected = case.get("expectedOutput")
        if expected is not None:
            require(isinstance(expected, str) and path_exists(repo_root, expected),
                    errors,
                    f"{case_id}: missing expected output fixture")
        for supporting in case.get("supportingTemplates", []):
            require(isinstance(supporting, str) and path_exists(repo_root, supporting),
                    errors,
                    f"{case_id}: missing supporting template {supporting}")
        for item in case.get("requiredCoverage", []):
            if isinstance(item, str):
                coverage.add(item)
    for required in {
        "escaped output",
        "raw output",
        "nil output",
        "strict stringify",
        "dotted keypath locals",
        "layout",
        "slot",
        "include",
        "collection render",
        "required locals",
        "filename diagnostics",
        "line diagnostics",
        "column diagnostics",
    }:
        require(required in coverage, errors, f"EOC golden coverage missing: {required}")
    return payload


def validate_parser_protocol_corpus(repo_root: Path, errors: list[str]) -> dict[str, Any]:
    path = repo_root / "tests/fixtures/phase37/parser_protocol_corpus.json"
    payload = load_json(path)
    require(payload.get("version") == "phase37-parser-protocol-corpus-v1",
            errors,
            "parser/protocol corpus has unexpected version")
    template_cases = payload.get("templateParserCases")
    protocol_cases = payload.get("httpProtocolCases")
    require(isinstance(template_cases, list) and len(template_cases) >= 4,
            errors,
            "template parser corpus needs at least four cases")
    require(isinstance(protocol_cases, list) and len(protocol_cases) >= 4,
            errors,
            "HTTP protocol corpus needs at least four cases")
    for case in template_cases if isinstance(template_cases, list) else []:
        if not isinstance(case, dict):
            errors.append("template parser corpus case is not an object")
            continue
        require(case.get("category") in {"valid", "invalid"},
                errors,
                f"{case.get('id')}: invalid parser category")
        template = case.get("template")
        require(isinstance(template, str) and path_exists(repo_root, template),
                errors,
                f"{case.get('id')}: parser template fixture missing")
    for case in protocol_cases if isinstance(protocol_cases, list) else []:
        if not isinstance(case, dict):
            errors.append("HTTP protocol corpus case is not an object")
            continue
        request_path = case.get("requestPath")
        require(isinstance(request_path, str) and path_exists(repo_root, request_path),
                errors,
                f"{case.get('id')}: protocol request fixture missing")
        require(isinstance(case.get("expectedStatus"), int),
                errors,
                f"{case.get('id')}: expectedStatus must be an integer")
    return payload


def validate_acceptance_manifest(repo_root: Path, errors: list[str]) -> dict[str, Any]:
    path = repo_root / "tests/fixtures/phase37/acceptance_sites.json"
    payload = load_json(path)
    sites = payload.get("sites")
    require(isinstance(sites, list), errors, "acceptance manifest sites must be a list")
    runtime_variants = {
        site.get("runtimeVariantOf")
        for site in sites if isinstance(site, dict) and site.get("mode") == "runtime"
    } if isinstance(sites, list) else set()
    for required in {
        "eoc_kitchen_sink",
        "mvc_crud",
        "module_portal",
        "live_ui_reference",
        "packaged_deploy",
    }:
        require(required in runtime_variants,
                errors,
                f"acceptance manifest missing runtime variant for {required}")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Phase 37 contract fixtures")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--output", help="Optional JSON summary path")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    errors: list[str] = []
    contract = validate_public_surface_contract(repo_root, errors)
    golden = validate_eoc_golden_cases(repo_root, errors)
    corpus = validate_parser_protocol_corpus(repo_root, errors)
    acceptance = validate_acceptance_manifest(repo_root, errors)

    summary = {
        "version": "phase37-contract-check-v1",
        "status": "pass" if not errors else "fail",
        "surface_count": len(contract.get("surfaces", [])),
        "golden_case_count": len(golden.get("cases", [])),
        "template_parser_case_count": len(corpus.get("templateParserCases", [])),
        "http_protocol_case_count": len(corpus.get("httpProtocolCases", [])),
        "acceptance_site_count": len(acceptance.get("sites", [])),
        "errors": errors,
    }
    if args.output:
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n",
                          encoding="utf-8")
    if errors:
        for error in errors:
            print(f"phase37-contract: {error}")
        return 1
    print(
        "phase37-contract: validated "
        f"{summary['surface_count']} surfaces, "
        f"{summary['golden_case_count']} golden cases, "
        f"{summary['template_parser_case_count']} parser cases, "
        f"{summary['http_protocol_case_count']} protocol cases"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Validate imported comparative benchmark contracts."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"expected object JSON at {path}")
    return payload


def expect(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def scenario_index(payload: dict[str, Any], errors: list[str], label: str) -> dict[str, dict[str, Any]]:
    scenarios = payload.get("scenarios")
    if not isinstance(scenarios, list):
      errors.append(f"{label}: scenarios must be an array")
      return {}
    indexed: dict[str, dict[str, Any]] = {}
    for entry in scenarios:
        if not isinstance(entry, dict):
            errors.append(f"{label}: scenario entry must be an object")
            continue
        scenario_id = entry.get("id")
        if not isinstance(scenario_id, str) or not scenario_id:
            errors.append(f"{label}: scenario entry missing non-empty id")
            continue
        indexed[scenario_id] = entry
    return indexed


def validate_http_manifest(path: Path, errors: list[str]) -> None:
    payload = load_json(path)
    expect(payload.get("schema_version") == 1, f"{path}: schema_version must be 1", errors)
    expect(
        payload.get("name") == "arlen_comparative_http_api_scenarios_v1",
        f"{path}: unexpected manifest name",
        errors,
    )
    expect(
        payload.get("source_program") == "../ArlenBenchmarking",
        f"{path}: source_program must point to ../ArlenBenchmarking",
        errors,
    )

    indexed = scenario_index(payload, errors, str(path))
    expected_ids = [
        "A_json_status",
        "B_json_transform",
        "C_middleware_heavy",
        "D_template",
        "E_db_read",
        "E_db_write",
    ]
    expect(list(indexed.keys()) == expected_ids, f"{path}: unexpected scenario id order", errors)

    status = indexed.get("A_json_status", {})
    expect(status.get("method") == "GET", f"{path}: A_json_status method mismatch", errors)
    expect(status.get("path") == "/api/status", f"{path}: A_json_status path mismatch", errors)
    expect(status.get("expected_status") == 200, f"{path}: A_json_status status mismatch", errors)
    expect(
        status.get("contract", {}).get("required_keys") == ["server", "ok", "timestamp"],
        f"{path}: A_json_status required_keys mismatch",
        errors,
    )

    transform = indexed.get("B_json_transform", {})
    expect(transform.get("method") == "GET", f"{path}: B_json_transform method mismatch", errors)
    expect(transform.get("path") == "/api/echo/{name}", f"{path}: B_json_transform path mismatch", errors)
    expect(
        transform.get("contract", {}).get("required_keys") == ["name", "path"],
        f"{path}: B_json_transform required_keys mismatch",
        errors,
    )
    expect(
        isinstance(transform.get("path_params", {}).get("name"), str)
        and len(transform.get("path_params", {}).get("name", "")) >= 64,
        f"{path}: B_json_transform path_params.name must be a long deterministic payload",
        errors,
    )

    middleware = indexed.get("C_middleware_heavy", {})
    expected_headers = [
        "content-security-policy",
        "cross-origin-opener-policy",
        "cross-origin-resource-policy",
        "referrer-policy",
        "x-content-type-options",
        "x-frame-options",
        "x-permitted-cross-domain-policies",
        "x-request-id",
        "x-correlation-id",
        "x-trace-id",
        "traceparent",
    ]
    expect(
        middleware.get("contract", {}).get("required_headers") == expected_headers,
        f"{path}: C_middleware_heavy required_headers mismatch",
        errors,
    )

    template = indexed.get("D_template", {})
    expect(template.get("method") == "GET", f"{path}: D_template method mismatch", errors)
    expect(template.get("path") == "/", f"{path}: D_template path mismatch", errors)
    expect(
        template.get("contract", {}).get("required_substrings")
        == [
            "<h1>Arlen EOC Dev Server</h1>",
            "template:multiline-ok",
            "<a href=\"/\">Home</a>",
            "<a href=\"/about\">About</a>",
        ],
        f"{path}: D_template required_substrings mismatch",
        errors,
    )

    expect(indexed.get("E_db_read", {}).get("enabled") is False, f"{path}: E_db_read placeholder must be disabled", errors)
    expect(indexed.get("E_db_write", {}).get("enabled") is False, f"{path}: E_db_write placeholder must be disabled", errors)


def validate_db_manifest(path: Path, errors: list[str]) -> None:
    payload = load_json(path)
    expect(payload.get("schema_version") == 1, f"{path}: schema_version must be 1", errors)
    expect(
        payload.get("name") == "arlen_comparative_db_scenarios_v1",
        f"{path}: unexpected manifest name",
        errors,
    )
    expect(
        payload.get("source_program") == "../ArlenBenchmarking",
        f"{path}: source_program must point to ../ArlenBenchmarking",
        errors,
    )

    indexed = scenario_index(payload, errors, str(path))
    expect(list(indexed.keys()) == ["E_db_read", "E_db_write"], f"{path}: unexpected scenario id order", errors)

    db_read = indexed.get("E_db_read", {})
    expect(db_read.get("method") == "GET", f"{path}: E_db_read method mismatch", errors)
    expect(
        db_read.get("path") == "/api/db/items?category=alpha&limit=50",
        f"{path}: E_db_read path mismatch",
        errors,
    )
    expect(db_read.get("enabled") is True, f"{path}: E_db_read must be enabled", errors)

    db_write = indexed.get("E_db_write", {})
    expect(db_write.get("method") == "POST", f"{path}: E_db_write method mismatch", errors)
    expect(db_write.get("path") == "/api/db/items", f"{path}: E_db_write path mismatch", errors)
    expect(db_write.get("expected_status") == 201, f"{path}: E_db_write status mismatch", errors)
    expect(db_write.get("enabled") is True, f"{path}: E_db_write must be enabled", errors)


def validate_contract(path: Path, repo_root: Path, errors: list[str]) -> None:
    payload = load_json(path)
    expect(payload.get("schema_version") == 1, f"{path}: schema_version must be 1", errors)
    expect(
        payload.get("name") == "arlen_comparative_benchmark_contract_v1",
        f"{path}: unexpected contract name",
        errors,
    )
    expect(
        payload.get("source_program") == "../ArlenBenchmarking",
        f"{path}: source_program must point to ../ArlenBenchmarking",
        errors,
    )
    expect(
        "not an executable runner config" in str(payload.get("contract_scope", "")),
        f"{path}: contract_scope must describe the non-executable import role",
        errors,
    )
    expect(
        payload.get("warmup") == {"duration_seconds": 15, "requests_per_scenario": 30},
        f"{path}: warmup block mismatch",
        errors,
    )
    expect(
        payload.get("measured")
        == {
            "duration_seconds": 60,
            "requests_per_scenario": 120,
            "concurrency_levels": [1, 8, 32, 128],
            "repeats": 3,
        },
        f"{path}: measured block mismatch",
        errors,
    )
    expect(
        payload.get("framework_defaults")
        == {
            "arlen": {"server": "boomhauer", "environment_mode": "production", "workers": 1},
            "fastapi": {"server": "uvicorn", "workers": 1},
        },
        f"{path}: framework_defaults mismatch",
        errors,
    )
    expect(
        payload.get("reproducibility") == {"max_cv_ratio": 0.4},
        f"{path}: reproducibility block mismatch",
        errors,
    )

    manifests = payload.get("scenarios_manifests")
    if not isinstance(manifests, dict):
        errors.append(f"{path}: scenarios_manifests must be an object")
        return
    expected_manifest_map = {
        "http_api": "tests/fixtures/benchmarking/comparative_scenarios.v1.json",
        "db": "tests/fixtures/benchmarking/comparative_scenarios.db.v1.json",
    }
    expect(manifests == expected_manifest_map, f"{path}: scenarios_manifests mismatch", errors)
    for rel_path in expected_manifest_map.values():
        expect((repo_root / rel_path).is_file(), f"{path}: referenced manifest missing: {rel_path}", errors)


def validate_docs(path: Path, errors: list[str]) -> None:
    contents = path.read_text(encoding="utf-8")
    expect(
        "tests/fixtures/benchmarking/" in contents,
        f"{path}: must mention imported benchmark contract fixtures",
        errors,
    )
    expect(
        "../ArlenBenchmarking" in contents,
        f"{path}: must mention sibling ArlenBenchmarking repo",
        errors,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate imported comparative benchmark contracts")
    parser.add_argument("--repo-root", default=".", help="Repository root")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    http_manifest = repo_root / "tests/fixtures/benchmarking/comparative_scenarios.v1.json"
    db_manifest = repo_root / "tests/fixtures/benchmarking/comparative_scenarios.db.v1.json"
    contract = repo_root / "tests/fixtures/benchmarking/comparative_benchmark_contract.v1.json"
    docs_path = repo_root / "docs/COMPARATIVE_BENCHMARKING.md"

    errors: list[str] = []
    for path in [http_manifest, db_manifest, contract, docs_path]:
        if not path.exists():
            errors.append(f"missing required file: {path}")

    if errors:
        for error in errors:
            print(f"benchmark-contracts: {error}", file=sys.stderr)
        return 1

    validate_http_manifest(http_manifest, errors)
    validate_db_manifest(db_manifest, errors)
    validate_contract(contract, repo_root, errors)
    validate_docs(docs_path, errors)

    if errors:
        for error in errors:
            print(f"benchmark-contracts: {error}", file=sys.stderr)
        return 1

    print("benchmark-contracts: imported comparative benchmark contract pack is consistent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

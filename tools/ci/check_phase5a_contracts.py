#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

CONTRACTS_FIXTURE = ROOT / "tests/fixtures/phase5a/data_layer_reliability_contracts.json"
INTAKE_FIXTURE = ROOT / "tests/fixtures/phase5a/external_regression_intake.json"
CAPABILITIES_FIXTURE = ROOT / "tests/fixtures/phase5a/adapter_capabilities.json"

TEST_NAME_PATTERN = re.compile(r"-\s*\(void\)\s*(test[A-Za-z0-9_]+)\s*\{")


def fail(message: str) -> None:
    print(f"phase5a-check: {message}")
    sys.exit(1)


def load_json(path: Path) -> dict:
    if not path.exists():
        fail(f"missing fixture: {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")


def extract_test_names(path: Path) -> set[str]:
    if not path.exists():
        fail(f"missing test source file: {path}")
    text = path.read_text(encoding="utf-8")
    return set(TEST_NAME_PATTERN.findall(text))


def check_contracts_fixture() -> set[str]:
    payload = load_json(CONTRACTS_FIXTURE)
    if payload.get("version") != "phase5a-v1":
        fail("contracts fixture version must be phase5a-v1")

    contracts = payload.get("contracts")
    if not isinstance(contracts, list) or not contracts:
        fail("contracts fixture must include a non-empty contracts array")

    seen_ids: set[str] = set()
    test_cache: dict[Path, set[str]] = {}
    allowed_kinds = {"unit", "integration", "long_run", "conformance"}

    for contract in contracts:
        if not isinstance(contract, dict):
            fail("contract entry must be a dictionary")
        contract_id = contract.get("id", "")
        claim = contract.get("claim", "")
        if not isinstance(contract_id, str) or not contract_id:
            fail("contract id must be a non-empty string")
        if contract_id in seen_ids:
            fail(f"duplicate contract id: {contract_id}")
        seen_ids.add(contract_id)
        if not isinstance(claim, str) or not claim:
            fail(f"contract '{contract_id}' must include a non-empty claim")

        source_docs = contract.get("source_docs")
        if not isinstance(source_docs, list) or not source_docs:
            fail(f"contract '{contract_id}' must include source_docs")
        for doc_path in source_docs:
            if not isinstance(doc_path, str) or not doc_path:
                fail(f"contract '{contract_id}' has invalid source_docs entry")
            if not (ROOT / doc_path).exists():
                fail(f"contract '{contract_id}' references missing source doc: {doc_path}")

        verification = contract.get("verification")
        if not isinstance(verification, list) or not verification:
            fail(f"contract '{contract_id}' must include verification entries")
        for reference in verification:
            if not isinstance(reference, dict):
                fail(f"contract '{contract_id}' has non-dict verification entry")
            kind = reference.get("kind", "")
            rel_file = reference.get("file", "")
            test_name = reference.get("test", "")
            if kind not in allowed_kinds:
                fail(f"contract '{contract_id}' has unsupported verification kind: {kind}")
            if not isinstance(rel_file, str) or not rel_file:
                fail(f"contract '{contract_id}' has invalid verification file")
            if not isinstance(test_name, str) or not test_name:
                fail(f"contract '{contract_id}' has invalid verification test")
            file_path = ROOT / rel_file
            if file_path not in test_cache:
                test_cache[file_path] = extract_test_names(file_path)
            if test_name not in test_cache[file_path]:
                fail(
                    f"contract '{contract_id}' references missing test '{test_name}' in {rel_file}"
                )

    return seen_ids


def check_external_intake(contract_ids: set[str]) -> None:
    payload = load_json(INTAKE_FIXTURE)
    if payload.get("version") != "phase5a-intake-v1":
        fail("external intake fixture version must be phase5a-intake-v1")

    scenarios = payload.get("scenarios")
    if not isinstance(scenarios, list) or not scenarios:
        fail("external intake fixture must include a non-empty scenarios array")

    seen_ids: set[str] = set()
    test_cache: dict[Path, set[str]] = {}
    allowed_statuses = {"covered", "planned"}

    for scenario in scenarios:
        if not isinstance(scenario, dict):
            fail("scenario entry must be a dictionary")
        scenario_id = scenario.get("id", "")
        if not isinstance(scenario_id, str) or not scenario_id:
            fail("scenario id must be a non-empty string")
        if scenario_id in seen_ids:
            fail(f"duplicate scenario id: {scenario_id}")
        seen_ids.add(scenario_id)

        for required in ("source_framework", "source_area", "source_reference", "bug_class"):
            value = scenario.get(required, "")
            if not isinstance(value, str) or not value:
                fail(f"scenario '{scenario_id}' must include non-empty {required}")

        contract_id = scenario.get("arlen_contract_id", "")
        if not isinstance(contract_id, str) or contract_id not in contract_ids:
            fail(f"scenario '{scenario_id}' maps to unknown contract id: {contract_id}")

        status = scenario.get("status", "")
        if status not in allowed_statuses:
            fail(f"scenario '{scenario_id}' has unsupported status: {status}")

        references = scenario.get("arlen_tests")
        if not isinstance(references, list):
            fail(f"scenario '{scenario_id}' arlen_tests must be an array")
        if status == "covered" and not references:
            fail(f"covered scenario '{scenario_id}' must include at least one test reference")

        for reference in references:
            if not isinstance(reference, dict):
                fail(f"scenario '{scenario_id}' has non-dict test reference")
            rel_file = reference.get("file", "")
            test_name = reference.get("test", "")
            if not isinstance(rel_file, str) or not rel_file:
                fail(f"scenario '{scenario_id}' has invalid test reference file")
            if not isinstance(test_name, str) or not test_name:
                fail(f"scenario '{scenario_id}' has invalid test reference name")
            file_path = ROOT / rel_file
            if file_path not in test_cache:
                test_cache[file_path] = extract_test_names(file_path)
            if test_name not in test_cache[file_path]:
                fail(
                    f"scenario '{scenario_id}' references missing test '{test_name}' in {rel_file}"
                )


def check_capabilities_fixture() -> None:
    payload = load_json(CAPABILITIES_FIXTURE)
    if payload.get("version") != "phase5a-capabilities-v1":
        fail("capabilities fixture version must be phase5a-capabilities-v1")

    adapters = payload.get("adapters")
    if not isinstance(adapters, dict):
        fail("capabilities fixture adapters must be a dictionary")

    required_adapters = {"postgresql", "gdl2"}
    missing = sorted(required_adapters - set(adapters.keys()))
    if missing:
        fail(f"capabilities fixture missing adapters: {', '.join(missing)}")

    required_bool_keys = {
        "supports_builder_compilation_cache",
        "supports_builder_diagnostics",
        "supports_cte",
        "supports_for_update",
        "supports_lateral_join",
        "supports_on_conflict",
        "supports_recursive_cte",
        "supports_set_operations",
        "supports_skip_locked",
        "supports_window_clauses",
    }
    for adapter_name in required_adapters:
        entry = adapters.get(adapter_name)
        if not isinstance(entry, dict):
            fail(f"capabilities entry for '{adapter_name}' must be a dictionary")
        for key in ("adapter", "dialect"):
            value = entry.get(key)
            if not isinstance(value, str) or not value:
                fail(f"capabilities entry for '{adapter_name}' requires non-empty '{key}'")
        for key in required_bool_keys:
            value = entry.get(key)
            if not isinstance(value, bool):
                fail(
                    f"capabilities entry for '{adapter_name}' key '{key}' must be boolean"
                )


def main() -> None:
    contract_ids = check_contracts_fixture()
    check_external_intake(contract_ids)
    check_capabilities_fixture()
    print("phase5a-check: fixtures and references validated")


if __name__ == "__main__":
    main()

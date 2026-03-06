#!/usr/bin/env python3
"""Deterministic Phase 11 protocol mutation probe."""

from __future__ import annotations

import argparse
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple

from protocol_adversarial_probe import (
    assert_health,
    git_commit,
    load_json,
    send_raw_request,
    start_server,
    stop_server,
    write_json,
)


VERSION = "phase11-protocol-fuzz-v1"
FIXTURE_VERSION = "phase11-protocol-adversarial-v1"


def alternating_case(value: str) -> str:
    chars: List[str] = []
    uppercase = False
    for ch in value:
      if ch.isalpha():
        chars.append(ch.upper() if uppercase else ch.lower())
        uppercase = not uppercase
      else:
        chars.append(ch)
    return "".join(chars)


def split_request(raw_request: str) -> Tuple[List[str], str]:
    head, separator, body = raw_request.partition("\r\n\r\n")
    if separator == "":
        return [raw_request], ""
    return head.split("\r\n"), body


def join_request(lines: Iterable[str], body: str) -> str:
    head = "\r\n".join(lines)
    return f"{head}\r\n\r\n{body}"


def mutate_header_case(raw_request: str) -> str:
    lines, body = split_request(raw_request)
    if not lines:
        return raw_request
    mutated = [lines[0]]
    for line in lines[1:]:
        if ":" not in line:
            mutated.append(line)
            continue
        name, value = line.split(":", 1)
        mutated.append(f"{alternating_case(name)}:{value}")
    return join_request(mutated, body)


def mutate_header_spacing(raw_request: str) -> str:
    lines, body = split_request(raw_request)
    if not lines:
        return raw_request
    mutated = [lines[0]]
    for line in lines[1:]:
        if ":" not in line:
            mutated.append(line)
            continue
        name, value = line.split(":", 1)
        mutated.append(f"{name}:   {value.lstrip()}")
    return join_request(mutated, body)


def mutate_add_header(raw_request: str, header_name: str, header_value: str) -> str:
    lines, body = split_request(raw_request)
    if not lines:
        return raw_request
    mutated = list(lines)
    mutated.append(f"{header_name}: {header_value}")
    return join_request(mutated, body)


def mutate_add_query(raw_request: str, suffix: str) -> str:
    lines, body = split_request(raw_request)
    if not lines:
        return raw_request
    parts = lines[0].split(" ")
    if len(parts) != 3:
        return raw_request
    method, target, version = parts
    delimiter = "&" if "?" in target else "?"
    lines[0] = f"{method} {target}{delimiter}{suffix} {version}"
    return join_request(lines, body)


def mutation_payloads(case_id: str, raw_request: str) -> List[Tuple[str, str]]:
    safe_case = re.sub(r"[^a-zA-Z0-9]+", "-", case_id).strip("-") or "case"
    return [
        ("header_case", mutate_header_case(raw_request)),
        ("header_spacing", mutate_header_spacing(raw_request)),
        ("extra_header", mutate_add_header(raw_request, "X-Phase11-Fuzz", safe_case)),
        ("query_suffix", mutate_add_query(raw_request, f"phase11_mutation={safe_case}")),
    ]


def make_markdown(payload: Dict[str, Any], output_dir: Path) -> str:
    lines: List[str] = []
    lines.append("# Phase 11 Protocol Fuzz")
    lines.append("")
    lines.append(f"Generated at: `{payload['generated_at']}`")
    lines.append(f"Git commit: `{payload['commit']}`")
    lines.append(f"Fixture version: `{payload['fixture_version']}`")
    lines.append("")
    lines.append("| Backend | Case | Mutation | Expected | Observed | Status |")
    lines.append("| --- | --- | --- | --- | --- | --- |")
    for result in payload.get("results", []):
        lines.append(
            "| {backend} | {case_id} | {mutation_id} | {expected} | {observed} | {status} |".format(
                backend=result.get("backend", ""),
                case_id=result.get("case_id", ""),
                mutation_id=result.get("mutation_id", ""),
                expected=result.get("expected_status", ""),
                observed=result.get("observed_status", ""),
                status=result.get("status", ""),
            )
        )
    lines.append("")
    lines.append("## Violations")
    lines.append("")
    violations = payload.get("violations", [])
    if isinstance(violations, list) and violations:
        for item in violations:
            lines.append(f"- {item}")
    else:
        lines.append("- none")
    lines.append("")
    lines.append("## Totals")
    lines.append("")
    summary = payload.get("summary", {})
    lines.append(f"- Total mutations: `{summary.get('total', 0)}`")
    lines.append(f"- Passed: `{summary.get('passed', 0)}`")
    lines.append(f"- Failed: `{summary.get('failed', 0)}`")
    lines.append(f"- Status: `{summary.get('status', 'fail')}`")
    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run deterministic Phase 11 protocol mutations")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--binary", default="build/boomhauer")
    parser.add_argument("--fixture", default="tests/fixtures/protocol/phase11_protocol_adversarial_cases.json")
    parser.add_argument("--output-dir", default="build/release_confidence/phase11/protocol_fuzz")
    parser.add_argument("--backends", default="llhttp,legacy")
    parser.add_argument("--allow-fail", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    binary = (repo_root / args.binary).resolve()
    fixture = (repo_root / args.fixture).resolve()
    output_dir = Path(args.output_dir).resolve()
    reproducer_dir = output_dir / "reproducers"

    if not binary.exists():
        raise SystemExit(f"binary not found: {binary}")

    fixture_payload = load_json(fixture)
    if fixture_payload.get("version") != FIXTURE_VERSION:
        raise SystemExit("phase11 protocol fuzz fixture version mismatch")

    backends = [item.strip() for item in str(args.backends).split(",") if item.strip()]
    if not backends:
        raise SystemExit("at least one backend is required")

    cases = fixture_payload.get("cases")
    if not isinstance(cases, list) or not cases:
        raise SystemExit("fixture must include non-empty cases array")

    limits = fixture_payload.get("limits", {})
    if not isinstance(limits, dict):
        limits = {}

    base_env = dict(os.environ)
    base_env.setdefault("ARLEN_WEBSOCKET_ALLOWED_ORIGINS", "https://allowed.example")

    results: List[Dict[str, Any]] = []
    violations: List[str] = []

    for backend in backends:
        port = 0
        process = None
        try:
            port, process = start_server(binary, backend, limits, base_env)
            for case in cases:
                if not isinstance(case, dict):
                    continue
                case_id = str(case.get("id", ""))
                request = case.get("request")
                expected_status = int(case.get("expectedStatus", 0))
                if not case_id or not isinstance(request, str) or expected_status <= 0:
                    violations.append(f"invalid fixture case: {case}")
                    continue

                for mutation_id, payload in mutation_payloads(case_id, request):
                    record: Dict[str, Any] = {
                        "backend": backend,
                        "case_id": case_id,
                        "mutation_id": mutation_id,
                        "expected_status": expected_status,
                        "observed_status": 0,
                        "status": "fail",
                        "status_line": "",
                        "error": "",
                        "reproducer": "",
                    }
                    try:
                        response = send_raw_request(port, payload.encode("utf-8"))
                        record["status_line"] = str(response.get("status_line", ""))
                        record["observed_status"] = int(response.get("status_code", 0))
                        if record["observed_status"] == expected_status:
                            record["status"] = "pass"
                        else:
                            record["error"] = "status_mismatch"
                    except Exception as exc:  # noqa: BLE001
                        record["error"] = str(exc)

                    if record["status"] != "pass":
                        reproducer_dir.mkdir(parents=True, exist_ok=True)
                        reproducer_name = f"{backend}_{case_id}_{mutation_id}.http"
                        reproducer_path = reproducer_dir / reproducer_name
                        reproducer_path.write_text(payload, encoding="utf-8")
                        record["reproducer"] = f"reproducers/{reproducer_name}"
                        violations.append(
                            f"backend {backend} case {case_id} mutation {mutation_id}: "
                            f"expected {expected_status}, got {record['observed_status'] or record['error']}"
                        )
                    results.append(record)
                    try:
                        assert_health(port)
                    except Exception as exc:  # noqa: BLE001
                        violations.append(
                            f"backend {backend} case {case_id} mutation {mutation_id}: health recovery failed ({exc})"
                        )
        finally:
            stop_server(process)

    total = len(results)
    passed = sum(1 for item in results if item.get("status") == "pass")
    failed = total - passed
    status = "pass" if failed == 0 and not violations else "fail"
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    payload: Dict[str, Any] = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": git_commit(repo_root),
        "fixture": str(fixture),
        "fixture_version": FIXTURE_VERSION,
        "backends": backends,
        "results": results,
        "violations": violations,
        "summary": {
            "total": total,
            "passed": passed,
            "failed": failed,
            "status": status,
        },
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    write_json(output_dir / "protocol_fuzz_results.json", payload)
    (output_dir / "phase11_protocol_fuzz.md").write_text(make_markdown(payload, output_dir), encoding="utf-8")
    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": payload["commit"],
        "status": status,
        "artifacts": [
            "protocol_fuzz_results.json",
            "phase11_protocol_fuzz.md",
        ],
    }
    if reproducer_dir.exists():
        manifest["artifacts"].append("reproducers")
    write_json(output_dir / "manifest.json", manifest)

    print(f"phase11-protocol-fuzz: generated artifacts in {output_dir} (status={status})")
    if status != "pass" and not args.allow_fail:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

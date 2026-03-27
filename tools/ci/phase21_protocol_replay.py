#!/usr/bin/env python3
"""Replay the Phase 21 raw protocol corpus or a single saved seed."""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List

from protocol_adversarial_probe import (
    assert_health,
    git_commit,
    load_json,
    send_raw_request,
    start_server,
    stop_server,
    write_json,
)


VERSION = "phase21-protocol-corpus-v1"


def request_bytes_from_path(path: Path) -> bytes:
    text = path.read_text(encoding="utf-8")
    if "\r\n" not in text:
      text = text.replace("\n", "\r\n")
    return text.encode("utf-8")


def selected_case_ids(raw: str) -> set[str]:
    return {item.strip() for item in raw.split(",") if item.strip()}


def corpus_entries(fixture_payload: Dict[str, Any], case_filter: set[str]) -> List[Dict[str, Any]]:
    entries: List[Dict[str, Any]] = []
    for section_name, default_category in (("cases", ""), ("fuzzSeeds", "fuzz_seed")):
        raw_entries = fixture_payload.get(section_name, [])
        if not isinstance(raw_entries, list):
            continue
        for entry in raw_entries:
            if not isinstance(entry, dict):
                continue
            case_id = str(entry.get("id", ""))
            if case_filter and case_id not in case_filter:
                continue
            request_path = str(entry.get("requestPath") or entry.get("path") or "")
            expected_status = int(entry.get("expectedStatus", 0))
            if not case_id or not request_path or expected_status <= 0:
                continue
            entries.append(
                {
                    "id": case_id,
                    "category": str(entry.get("category", default_category or section_name)),
                    "requestPath": request_path,
                    "expectedStatus": expected_status,
                    "expectedStatusByBackend": entry.get("expectedStatusByBackend", {}),
                    "limits": entry.get("limits", {}),
                }
            )
    return entries


def make_markdown(payload: Dict[str, Any], output_dir: Path) -> str:
    lines: List[str] = []
    lines.append("# Phase 21 Protocol Corpus")
    lines.append("")
    lines.append(f"Generated at: `{payload['generated_at']}`")
    lines.append(f"Git commit: `{payload['commit']}`")
    lines.append(f"Fixture version: `{payload.get('fixture_version', '')}`")
    lines.append("")
    lines.append("| Backend | Category | Case | Expected | Observed | Status |")
    lines.append("| --- | --- | --- | --- | --- | --- |")
    for result in payload.get("results", []):
        lines.append(
            "| {backend} | {category} | {case_id} | {expected} | {observed} | {status} |".format(
                backend=result.get("backend", ""),
                category=result.get("category", ""),
                case_id=result.get("case_id", ""),
                expected=result.get("expected_status", ""),
                observed=result.get("observed_status", ""),
                status=result.get("status", ""),
            )
        )
    lines.append("")
    lines.append("## Replay")
    lines.append("")
    lines.append(
        "- Re-run one checked-in case: "
        "`python3 tools/ci/phase21_protocol_replay.py --case <case_id> --backends llhttp --output-dir build/release_confidence/phase21/protocol_replay`"
    )
    lines.append(
        "- Re-run one saved seed: "
        "`python3 tools/ci/phase21_protocol_replay.py --raw-request build/release_confidence/phase11/protocol_fuzz/reproducers/<seed>.http --expected-status 400 --case-id replay_seed --backends llhttp`"
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
    summary = payload.get("summary", {})
    lines.append("## Totals")
    lines.append("")
    lines.append(f"- Total probes: `{summary.get('total', 0)}`")
    lines.append(f"- Passed: `{summary.get('passed', 0)}`")
    lines.append(f"- Failed: `{summary.get('failed', 0)}`")
    lines.append(f"- Skipped: `{summary.get('skipped', 0)}`")
    lines.append(f"- Status: `{summary.get('status', 'fail')}`")
    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Replay the Phase 21 raw protocol corpus")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--binary", default="build/boomhauer")
    parser.add_argument("--fixture", default="tests/fixtures/protocol/phase21_protocol_corpus.json")
    parser.add_argument("--output-dir", default="build/release_confidence/phase21/protocol")
    parser.add_argument("--backends", default="llhttp,legacy")
    parser.add_argument("--case", default="")
    parser.add_argument("--raw-request", default="")
    parser.add_argument("--expected-status", type=int, default=0)
    parser.add_argument("--case-id", default="replay_seed")
    parser.add_argument("--allow-fail", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    binary = (repo_root / args.binary).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    if not binary.exists():
        raise SystemExit(f"binary not found: {binary}")

    backends = [item.strip() for item in str(args.backends).split(",") if item.strip()]
    if not backends:
        raise SystemExit("at least one backend is required")

    results: List[Dict[str, Any]] = []
    violations: List[str] = []
    case_filter = selected_case_ids(str(args.case))

    if args.raw_request:
        raw_request_path = Path(args.raw_request).resolve()
        if not raw_request_path.exists():
            raise SystemExit(f"raw request file not found: {raw_request_path}")
        if args.expected_status <= 0:
            raise SystemExit("--expected-status is required when --raw-request is used")
        entries = [
            {
                "id": str(args.case_id or "replay_seed"),
                "category": "replay_seed",
                "requestPath": str(raw_request_path),
                "expectedStatus": int(args.expected_status),
            }
        ]
        fixture_version = "raw-request"
    else:
        fixture = (repo_root / args.fixture).resolve()
        fixture_payload = load_json(fixture)
        if fixture_payload.get("version") != VERSION:
            raise SystemExit("phase21 protocol corpus fixture version mismatch")
        entries = corpus_entries(fixture_payload, case_filter)
        fixture_version = str(fixture_payload.get("version", VERSION))
        if not entries:
            raise SystemExit("no protocol corpus entries selected")

    base_env = dict(os.environ)
    base_env.setdefault("ARLEN_WEBSOCKET_ALLOWED_ORIGINS", "https://allowed.example")

    limits: Dict[str, Any] = {}
    if not args.raw_request:
        fixture_payload = load_json((repo_root / args.fixture).resolve())
        raw_limits = fixture_payload.get("limits", {})
        if isinstance(raw_limits, dict):
            limits = raw_limits

    for backend in backends:
        port = 0
        process = None
        active_limits: Dict[str, Any] | None = None
        try:
            for entry in entries:
                entry_limits = dict(limits)
                raw_entry_limits = entry.get("limits", {})
                if isinstance(raw_entry_limits, dict):
                    entry_limits.update(raw_entry_limits)

                if process is None or active_limits != entry_limits:
                    stop_server(process)
                    port, process = start_server(binary, backend, entry_limits, base_env)
                    active_limits = entry_limits

                request_path = Path(str(entry["requestPath"]))
                if not request_path.is_absolute():
                    request_path = (repo_root / request_path).resolve()

                record: Dict[str, Any] = {
                    "backend": backend,
                    "category": entry["category"],
                    "case_id": entry["id"],
                    "request_path": str(request_path),
                    "expected_status": int(
                        entry.get("expectedStatusByBackend", {}).get(backend, entry["expectedStatus"])
                    ),
                    "limits": entry_limits,
                    "observed_status": 0,
                    "status": "fail",
                    "status_line": "",
                    "error": "",
                }

                try:
                    response = send_raw_request(port, request_bytes_from_path(request_path))
                    record["status_line"] = str(response.get("status_line", ""))
                    record["observed_status"] = int(response.get("status_code", 0))
                    if record["observed_status"] == record["expected_status"]:
                        record["status"] = "pass"
                    else:
                        record["error"] = "status_mismatch"
                        violations.append(
                            f"backend {backend} case {record['case_id']}: expected "
                            f"{record['expected_status']}, got {record['observed_status']}"
                        )
                except Exception as exc:  # noqa: BLE001
                    record["error"] = str(exc)
                    violations.append(f"backend {backend} case {record['case_id']}: exception {exc}")

                results.append(record)
                try:
                    assert_health(port)
                except Exception as exc:  # noqa: BLE001
                    violations.append(
                        f"backend {backend} case {record['case_id']}: health recovery failed ({exc})"
                    )
        finally:
            stop_server(process)

    total = len(results)
    passed = sum(1 for item in results if item.get("status") == "pass")
    failed = total - passed
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    status = "pass" if failed == 0 and not violations else "fail"
    payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": git_commit(repo_root),
        "fixture_version": fixture_version,
        "backends": backends,
        "results": results,
        "violations": violations,
        "summary": {
            "total": total,
            "passed": passed,
            "failed": failed,
            "skipped": 0,
            "status": status,
        },
    }
    write_json(output_dir / "protocol_corpus_results.json", payload)
    (output_dir / "phase21_protocol_corpus.md").write_text(
        make_markdown(payload, output_dir), encoding="utf-8"
    )
    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": payload["commit"],
        "status": status,
        "artifacts": [
            "protocol_corpus_results.json",
            "phase21_protocol_corpus.md",
        ],
    }
    write_json(output_dir / "manifest.json", manifest)
    print(f"phase21-protocol-corpus: generated artifacts in {output_dir} (status={status})")
    if status != "pass" and not args.allow_fail:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

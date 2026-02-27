#!/usr/bin/env python3
"""Generate Phase 10M backend parity matrix artifacts."""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Tuple


def load_json_text(text: str) -> Dict[str, Any]:
    decoder = json.JSONDecoder()
    best_payload: Dict[str, Any] | None = None
    best_score = -1
    for index, char in enumerate(text):
        if char != "{":
            continue
        try:
            candidate, consumed = decoder.raw_decode(text[index:])
        except json.JSONDecodeError:
            continue
        if not isinstance(candidate, dict):
            continue
        score = consumed
        if "version" in candidate:
            score += 10_000
        if score > best_score:
            best_payload = candidate
            best_score = score
    if best_payload is None:
        raise ValueError("benchmark output must contain a JSON object payload")
    return best_payload


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def git_commit(repo_root: Path) -> str:
    try:
        return (
            subprocess.check_output(
                ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
                stderr=subprocess.DEVNULL,
                text=True,
            )
            .strip()
        )
    except Exception:
        return "unknown"


def parse_combo(value: str) -> Tuple[int, int]:
    parts = value.split(":", 1)
    if len(parts) != 2:
        raise ValueError(f"invalid combo '{value}', expected <yyjson>:<llhttp>")
    yyjson = int(parts[0])
    llhttp = int(parts[1])
    if yyjson not in (0, 1) or llhttp not in (0, 1):
        raise ValueError(f"invalid combo '{value}', values must be 0 or 1")
    return yyjson, llhttp


def parse_combos(raw: str) -> List[Tuple[int, int]]:
    combos: List[Tuple[int, int]] = []
    seen = set()
    for entry in [item.strip() for item in raw.split(",") if item.strip()]:
        combo = parse_combo(entry)
        if combo in seen:
            continue
        seen.add(combo)
        combos.append(combo)
    if not combos:
        raise ValueError("at least one compile-time combo is required")
    return combos


def run_command(command: List[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=str(cwd), capture_output=True, text=True, check=False)


def backend_counts(payload: Dict[str, Any]) -> Tuple[int, int]:
    parser_backends = payload.get("available_parser_backends")
    json_backends = payload.get("available_json_backends")
    parser_count = len(parser_backends) if isinstance(parser_backends, list) else 0
    json_count = len(json_backends) if isinstance(json_backends, list) else 0
    return parser_count, json_count


def make_markdown(
    generated_at: str,
    commit: str,
    records: List[Dict[str, Any]],
    summary: Dict[str, Any],
    output_dir: Path,
) -> str:
    lines: List[str] = []
    lines.append("# Phase 10M Backend Parity Matrix")
    lines.append("")
    lines.append(f"Generated at: `{generated_at}`")
    lines.append(f"Git commit: `{commit}`")
    lines.append("")
    lines.append("| Combo (yyjson:llhttp) | Build | Contract | Backend Counts | Status |")
    lines.append("| --- | --- | --- | --- | --- |")
    for row in records:
        combo = row["combo"]
        lines.append(
            "| {combo} | {build} | {contract} | parser={parser} json={json} | {status} |".format(
                combo=combo,
                build=row["build_status"],
                contract=row["contract_status"],
                parser=row["parser_backend_count"],
                json=row["json_backend_count"],
                status=row["status"],
            )
        )

    violations = summary.get("violations", [])
    lines.append("")
    lines.append("## Violations")
    lines.append("")
    if isinstance(violations, list) and violations:
        for violation in violations:
            lines.append(f"- {violation}")
    else:
        lines.append("- none")

    lines.append("")
    lines.append("## Totals")
    lines.append("")
    lines.append(f"- Matrix combinations: `{summary.get('matrix_count', 0)}`")
    lines.append(f"- Passed combinations: `{summary.get('passed', 0)}`")
    lines.append(f"- Failed combinations: `{summary.get('failed', 0)}`")
    lines.append(f"- Status: `{summary.get('status', 'fail')}`")
    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 10M backend parity matrix artifacts")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--output-dir", default="build/release_confidence/phase10m/backend_parity")
    parser.add_argument("--http-fixtures-dir", default="tests/fixtures/performance/http_parse")
    parser.add_argument("--json-fixtures-dir", default="tests/fixtures/performance/json")
    parser.add_argument("--combos", default="1:1,1:0,0:1,0:0")
    parser.add_argument("--allow-fail", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    combos = parse_combos(args.combos)
    results: List[Dict[str, Any]] = []
    violations: List[str] = []

    for yyjson_enabled, llhttp_enabled in combos:
        combo_label = f"{yyjson_enabled}:{llhttp_enabled}"
        make_command = [
            "make",
            "backend-contract-matrix",
            f"ARLEN_ENABLE_YYJSON={yyjson_enabled}",
            f"ARLEN_ENABLE_LLHTTP={llhttp_enabled}",
        ]
        build = run_command(make_command, repo_root)
        record: Dict[str, Any] = {
            "combo": combo_label,
            "build_status": "pass" if build.returncode == 0 else "fail",
            "build_stdout": build.stdout,
            "build_stderr": build.stderr,
            "build_return_code": build.returncode,
            "contract_status": "skipped",
            "contract_return_code": None,
            "parser_backend_count": 0,
            "json_backend_count": 0,
            "status": "fail",
            "payload": {},
        }

        if build.returncode != 0:
            violations.append(f"combo {combo_label}: build failed (rc={build.returncode})")
            results.append(record)
            continue

        contract_cmd = [
            str((repo_root / "build" / "backend-contract-matrix").resolve()),
            "--http-fixtures-dir",
            str((repo_root / args.http_fixtures_dir).resolve()),
            "--json-fixtures-dir",
            str((repo_root / args.json_fixtures_dir).resolve()),
        ]
        contract = run_command(contract_cmd, repo_root)
        record["contract_return_code"] = contract.returncode

        payload: Dict[str, Any] = {}
        if contract.returncode == 0:
            try:
                payload = load_json_text(contract.stdout)
            except Exception as exc:
                violations.append(f"combo {combo_label}: failed to decode contract output ({exc})")
                record["contract_status"] = "fail"
            else:
                record["contract_status"] = str(payload.get("status", "fail"))
        else:
            try:
                payload = load_json_text(contract.stdout)
                record["contract_status"] = str(payload.get("status", "fail"))
            except Exception:
                record["contract_status"] = "fail"
            violations.append(
                f"combo {combo_label}: backend contract matrix failed (rc={contract.returncode})"
            )

        parser_count, json_count = backend_counts(payload)
        record["parser_backend_count"] = parser_count
        record["json_backend_count"] = json_count
        record["payload"] = payload

        expected_parser = 2 if llhttp_enabled == 1 else 1
        expected_json = 2 if yyjson_enabled == 1 else 1
        if parser_count != expected_parser:
            violations.append(
                f"combo {combo_label}: parser backend count {parser_count} != expected {expected_parser}"
            )
        if json_count != expected_json:
            violations.append(
                f"combo {combo_label}: json backend count {json_count} != expected {expected_json}"
            )

        embedded_violations = payload.get("violations", [])
        if isinstance(embedded_violations, list):
            for item in embedded_violations:
                violations.append(f"combo {combo_label}: {item}")

        if (
            build.returncode == 0
            and contract.returncode == 0
            and record["contract_status"] == "pass"
            and parser_count == expected_parser
            and json_count == expected_json
        ):
            record["status"] = "pass"
        else:
            record["status"] = "fail"

        results.append(record)

    passed = sum(1 for row in results if row["status"] == "pass")
    failed = len(results) - passed
    status = "pass" if failed == 0 and not violations else "fail"

    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    commit = git_commit(repo_root)

    matrix_payload = {
        "version": "phase10m-backend-parity-matrix-v1",
        "generated_at": generated_at,
        "commit": commit,
        "combos": [f"{yy}:{ll}" for yy, ll in combos],
        "results": results,
    }
    summary_payload = {
        "version": "phase10m-backend-parity-matrix-v1",
        "generated_at": generated_at,
        "commit": commit,
        "matrix_count": len(results),
        "passed": passed,
        "failed": failed,
        "status": status,
        "violations": violations,
    }

    markdown = make_markdown(generated_at, commit, results, summary_payload, output_dir)

    write_json(output_dir / "backend_parity_matrix_results.json", matrix_payload)
    write_json(output_dir / "backend_parity_summary.json", summary_payload)
    (output_dir / "phase10m_backend_parity_matrix.md").write_text(markdown, encoding="utf-8")

    manifest = {
        "version": "phase10m-backend-parity-matrix-v1",
        "generated_at": generated_at,
        "commit": commit,
        "status": status,
        "artifacts": [
            "backend_parity_matrix_results.json",
            "backend_parity_summary.json",
            "phase10m_backend_parity_matrix.md",
        ],
    }
    write_json(output_dir / "manifest.json", manifest)

    print(f"phase10m-backend-parity: generated artifacts in {output_dir} (status={status})")
    if status != "pass" and not args.allow_fail:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

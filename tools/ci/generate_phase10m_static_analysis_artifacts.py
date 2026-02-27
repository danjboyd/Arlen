#!/usr/bin/env python3
"""Generate Phase 10M static analysis/security lint artifacts."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

VERSION = "phase10m-static-analysis-v1"
POLICY_VERSION = "phase10m-static-analysis-policy-v1"

FINDING_RE = re.compile(
    r"^(?P<file>.+?):(?P<line>\d+):(?P<col>\d+):\s+(?P<kind>warning|error):\s+"
    r"(?P<message>.+?)(?:\s+\[(?P<checker>[^\]]+)\])?$"
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


def gnustep_objc_flags() -> List[str]:
    output = subprocess.check_output(["gnustep-config", "--objc-flags"], text=True).strip()
    if not output:
        return []
    return shlex.split(output)


def include_flags(repo_root: Path) -> List[str]:
    include_dirs = [
        "src/Arlen",
        "src/Arlen/Core",
        "src/Arlen/Data",
        "src/Arlen/HTTP",
        "src/Arlen/MVC/Controller",
        "src/Arlen/MVC/Middleware",
        "src/Arlen/MVC/Routing",
        "src/Arlen/MVC/Template",
        "src/Arlen/MVC/View",
        "src/Arlen/Support",
        "src/MojoObjc",
        "src/MojoObjc/Core",
        "src/MojoObjc/Data",
        "src/MojoObjc/HTTP",
        "src/MojoObjc/MVC/Controller",
        "src/MojoObjc/MVC/Middleware",
        "src/MojoObjc/MVC/Routing",
        "src/MojoObjc/MVC/Template",
        "src/MojoObjc/MVC/View",
        "src/MojoObjc/Support",
    ]
    flags = [f"-I{(repo_root / path).resolve()}" for path in include_dirs]
    flags.append("-I/usr/include/postgresql")
    return flags


def classify_finding(
    kind: str,
    checker: str,
    high_prefixes: List[str],
) -> str:
    if kind == "error":
        return "high"
    for prefix in high_prefixes:
        if checker.startswith(prefix):
            return "high"
    return "low"


def run_analyze_for_file(
    repo_root: Path,
    source_file: str,
    high_prefixes: List[str],
    enable_yyjson: int,
    enable_llhttp: int,
) -> Dict[str, Any]:
    source_path = (repo_root / source_file).resolve()
    if not source_path.exists():
        return {
            "file": source_file,
            "status": "fail",
            "return_code": 1,
            "findings": [],
            "errors": [f"missing file: {source_path}"],
        }

    analysis_output_dir = repo_root / "build" / "static_analysis"
    analysis_output_dir.mkdir(parents=True, exist_ok=True)
    analysis_output = analysis_output_dir / f"{source_path.name}.plist"

    command = [
        "clang",
        *gnustep_objc_flags(),
        "-fobjc-arc",
        f"-DARLEN_ENABLE_YYJSON={enable_yyjson}",
        f"-DARLEN_ENABLE_LLHTTP={enable_llhttp}",
        *include_flags(repo_root),
        "--analyze",
        "-Xanalyzer",
        "-analyzer-output=text",
        "-c",
        str(source_path),
        "-o",
        str(analysis_output),
    ]

    result = subprocess.run(command, cwd=str(repo_root), capture_output=True, text=True, check=False)
    combined = "\n".join([result.stdout, result.stderr]).strip()
    findings: List[Dict[str, Any]] = []
    parse_errors: List[str] = []

    for line in combined.splitlines():
        line = line.strip()
        if not line:
            continue
        match = FINDING_RE.match(line)
        if match is None:
            continue
        kind = match.group("kind")
        checker = match.group("checker") or ""
        finding = {
            "file": match.group("file"),
            "line": int(match.group("line")),
            "column": int(match.group("col")),
            "kind": kind,
            "message": match.group("message"),
            "checker": checker,
            "severity": classify_finding(kind, checker, high_prefixes),
        }
        findings.append(finding)

    if result.returncode != 0 and not findings:
        parse_errors.append(f"clang analyze failed rc={result.returncode}")

    status = "pass"
    if result.returncode != 0 and parse_errors:
        status = "fail"

    return {
        "file": source_file,
        "status": status,
        "return_code": result.returncode,
        "findings": findings,
        "errors": parse_errors,
        "stdout_tail": result.stdout[-2000:],
        "stderr_tail": result.stderr[-2000:],
    }


def render_markdown(payload: Dict[str, Any], output_dir: Path) -> str:
    lines: List[str] = []
    lines.append("# Phase 10M Static Analysis")
    lines.append("")
    lines.append(f"Generated at: `{payload['generated_at']}`")
    lines.append(f"Git commit: `{payload['commit']}`")
    lines.append(f"Policy version: `{payload.get('policy_version', '')}`")
    lines.append("")
    lines.append("| File | Status | Findings | High severity |")
    lines.append("| --- | --- | --- | --- |")
    for item in payload.get("files", []):
        findings = item.get("findings", [])
        if not isinstance(findings, list):
            findings = []
        high = sum(1 for finding in findings if finding.get("severity") == "high")
        lines.append(
            "| {file} | {status} | {count} | {high} |".format(
                file=item.get("file", ""),
                status=item.get("status", ""),
                count=len(findings),
                high=high,
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

    summary = payload.get("summary", {})
    lines.append("")
    lines.append("## Totals")
    lines.append("")
    lines.append(f"- Files scanned: `{summary.get('files_scanned', 0)}`")
    lines.append(f"- Total findings: `{summary.get('findings_total', 0)}`")
    lines.append(f"- High severity findings: `{summary.get('high_severity', 0)}`")
    lines.append(f"- Status: `{summary.get('status', 'fail')}`")
    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 10M static analysis artifacts")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument(
        "--policy",
        default="tests/fixtures/static_analysis/phase10m_static_analysis_policy.json",
    )
    parser.add_argument("--output-dir", default="build/release_confidence/phase10m/static_analysis")
    parser.add_argument("--allow-fail", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    policy_path = (repo_root / args.policy).resolve()
    output_dir = Path(args.output_dir).resolve()

    policy = load_json(policy_path)
    if policy.get("version") != POLICY_VERSION:
        raise SystemExit("phase10m static analysis policy version mismatch")

    files = policy.get("hotFiles", [])
    if not isinstance(files, list) or not files:
        raise SystemExit("static analysis policy must define non-empty hotFiles")

    high_prefixes = policy.get("highSeverityCheckers", [])
    if not isinstance(high_prefixes, list):
        high_prefixes = []
    high_prefixes = [str(item) for item in high_prefixes]

    allow_warnings = bool(policy.get("allowWarnings", True))
    enable_yyjson = int((os.environ.get("ARLEN_ENABLE_YYJSON", "1") or "1").strip())
    enable_llhttp = int((os.environ.get("ARLEN_ENABLE_LLHTTP", "1") or "1").strip())

    results: List[Dict[str, Any]] = []
    violations: List[str] = []

    for source_file in files:
        if not isinstance(source_file, str):
            continue
        result = run_analyze_for_file(
            repo_root=repo_root,
            source_file=source_file,
            high_prefixes=high_prefixes,
            enable_yyjson=enable_yyjson,
            enable_llhttp=enable_llhttp,
        )
        results.append(result)
        if result.get("status") != "pass":
            violations.append(f"analysis failed for {source_file}")

        findings = result.get("findings", [])
        if not isinstance(findings, list):
            findings = []
        for finding in findings:
            severity = str(finding.get("severity", "low"))
            checker = str(finding.get("checker", ""))
            message = str(finding.get("message", ""))
            if severity == "high":
                violations.append(
                    f"high severity finding in {source_file}: {checker} {message}"
                )
            elif not allow_warnings:
                violations.append(
                    f"warning finding in {source_file}: {checker} {message}"
                )

    findings_total = sum(
        len(result.get("findings", []))
        for result in results
        if isinstance(result.get("findings"), list)
    )
    high_total = sum(
        1
        for result in results
        for finding in (result.get("findings", []) if isinstance(result.get("findings"), list) else [])
        if str(finding.get("severity", "low")) == "high"
    )

    status = "pass" if not violations else "fail"
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": git_commit(repo_root),
        "policy": str(policy_path),
        "policy_version": policy.get("version", ""),
        "files": results,
        "violations": violations,
        "summary": {
            "files_scanned": len(results),
            "findings_total": findings_total,
            "high_severity": high_total,
            "status": status,
        },
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    write_json(output_dir / "static_analysis_results.json", payload)
    (output_dir / "phase10m_static_analysis.md").write_text(
        render_markdown(payload, output_dir),
        encoding="utf-8",
    )
    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": payload["commit"],
        "status": status,
        "artifacts": [
            "static_analysis_results.json",
            "phase10m_static_analysis.md",
        ],
    }
    write_json(output_dir / "manifest.json", manifest)

    print(f"phase10m-static-analysis: generated artifacts in {output_dir} (status={status})")
    if status != "pass" and not args.allow_fail:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

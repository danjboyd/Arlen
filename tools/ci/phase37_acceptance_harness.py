#!/usr/bin/env python3
"""Run deterministic Phase 37 acceptance-site probes."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class ProbeResult:
    site_id: str
    probe_id: str
    status: str
    detail: str


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"{path}: expected top-level object")
    return payload


def format_args(args: list[str], repo_root: Path, port: int, output_dir: Path) -> list[str]:
    replacements = {
        "{repo_root}": str(repo_root),
        "{port}": str(port),
        "{output_dir}": str(output_dir),
    }
    formatted: list[str] = []
    for arg in args:
        value = arg
        for token, replacement in replacements.items():
            value = value.replace(token, replacement)
        formatted.append(value)
    return formatted


def fetch(url: str, timeout: float) -> tuple[int, str, dict[str, str]]:
    request = urllib.request.Request(url, headers={"Connection": "close"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8", errors="replace")
            headers = {key.lower(): value for key, value in response.headers.items()}
            return response.status, body, headers
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        headers = {key.lower(): value for key, value in error.headers.items()}
        return error.code, body, headers


def run_probe(site_id: str, base_url: str, probe: dict[str, Any], timeout: float) -> ProbeResult:
    probe_id = str(probe.get("id") or probe.get("path") or "probe")
    expected_status = int(probe.get("expectedStatus", 200))
    url = base_url + str(probe.get("path", "/"))
    try:
        status, body, headers = fetch(url, timeout)
    except Exception as exc:  # noqa: BLE001 - preserve exact probe failure
        return ProbeResult(site_id, probe_id, "fail", f"{url}: request failed: {exc}")
    if status != expected_status:
        return ProbeResult(site_id, probe_id, "fail", f"{url}: expected {expected_status}, got {status}")
    contains = probe.get("contains")
    if isinstance(contains, str) and contains not in body:
        return ProbeResult(site_id, probe_id, "fail", f"{url}: missing body text {contains!r}")
    expected_headers = probe.get("headers")
    if isinstance(expected_headers, dict):
        for key, value in expected_headers.items():
            actual = headers.get(str(key).lower())
            if actual != value:
                return ProbeResult(site_id, probe_id, "fail", f"{url}: header {key} expected {value!r}, got {actual!r}")
    json_equals = probe.get("jsonEquals")
    if isinstance(json_equals, dict):
        try:
            parsed = json.loads(body)
        except json.JSONDecodeError as exc:
            return ProbeResult(site_id, probe_id, "fail", f"{url}: invalid JSON: {exc}")
        for key, value in json_equals.items():
            if not isinstance(parsed, dict) or parsed.get(key) != value:
                return ProbeResult(site_id, probe_id, "fail", f"{url}: JSON {key} expected {value!r}, got {parsed.get(key) if isinstance(parsed, dict) else None!r}")
    return ProbeResult(site_id, probe_id, "pass", f"{url}: ok")


def wait_ready(site_id: str, base_url: str, probe: dict[str, Any], timeout_seconds: float) -> ProbeResult:
    deadline = time.time() + timeout_seconds
    last = ProbeResult(site_id, "ready", "fail", "ready probe did not run")
    ready_probe = dict(probe)
    ready_probe["id"] = "ready"
    while time.time() < deadline:
        last = run_probe(site_id, base_url, ready_probe, timeout=1.0)
        if last.status == "pass":
            return last
        time.sleep(0.2)
    return last


def run_static_check(repo_root: Path, site_id: str, check: dict[str, Any]) -> ProbeResult:
    rel_path = str(check.get("path", ""))
    path = repo_root / rel_path
    check_id = f"static:{rel_path}"
    if not path.exists():
        return ProbeResult(site_id, check_id, "fail", f"{rel_path}: file missing")
    contains = check.get("contains")
    if isinstance(contains, str) and contains not in path.read_text(encoding="utf-8"):
        return ProbeResult(site_id, check_id, "fail", f"{rel_path}: missing text {contains!r}")
    return ProbeResult(site_id, check_id, "pass", f"{rel_path}: ok")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Phase 37 acceptance site manifest")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--manifest", default="tests/fixtures/phase37/acceptance_sites.json")
    parser.add_argument("--output-dir", default="build/release_confidence/phase37/acceptance")
    parser.add_argument("--include-service-backed", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest = load_json(repo_root / args.manifest)
    timeout_seconds = float(manifest.get("defaultTimeoutSeconds", 10))
    results: list[ProbeResult] = []
    site_summaries: list[dict[str, Any]] = []

    for site in manifest.get("sites", []):
        if not isinstance(site, dict):
            results.append(ProbeResult("<manifest>", "site-shape", "fail", "site entry is not an object"))
            continue
        site_id = str(site.get("id", "unknown"))
        if site.get("serviceBacked") and not args.include_service_backed:
            site_summaries.append({"id": site_id, "status": "skipped", "reason": "service-backed"})
            continue
        port = int(site.get("port", 0))
        base_url = f"http://127.0.0.1:{port}"
        site_log = output_dir / f"{site_id}.log"
        proc: subprocess.Popen[str] | None = None
        try:
            for static_check in site.get("staticChecks", []):
                if isinstance(static_check, dict):
                    results.append(run_static_check(repo_root, site_id, static_check))
            start_command = site.get("startCommand")
            if isinstance(start_command, list) and start_command:
                command = format_args([str(item) for item in start_command], repo_root, port, output_dir)
                log_handle = site_log.open("w", encoding="utf-8")
                proc = subprocess.Popen(command, stdout=log_handle, stderr=subprocess.STDOUT, text=True)
                ready_probe = site.get("readyProbe")
                if isinstance(ready_probe, dict):
                    results.append(wait_ready(site_id, base_url, ready_probe, timeout_seconds))
            for probe in site.get("probes", []):
                if isinstance(probe, dict):
                    results.append(run_probe(site_id, base_url, probe, timeout_seconds))
        finally:
            if proc is not None:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=3)
        site_failed = any(result.status == "fail" and result.site_id == site_id for result in results)
        site_summaries.append({"id": site_id, "status": "fail" if site_failed else "pass", "log": str(site_log)})

    payload = {
        "version": "phase37-acceptance-results-v1",
        "status": "fail" if any(result.status == "fail" for result in results) else "pass",
        "sites": site_summaries,
        "results": [result.__dict__ for result in results],
    }
    (output_dir / "manifest.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n",
                                               encoding="utf-8")
    for result in results:
        print(f"phase37-acceptance: {result.status}: {result.site_id}/{result.probe_id}: {result.detail}")
    return 0 if payload["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())

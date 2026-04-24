#!/usr/bin/env python3
"""Run deterministic Phase 37 acceptance-site probes."""

from __future__ import annotations

import argparse
import json
import re
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


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[override]
        return None


def fetch(url: str, probe: dict[str, Any], timeout: float) -> tuple[int, str, dict[str, str]]:
    method = str(probe.get("method", "GET")).upper()
    body_value = probe.get("body")
    data = None
    if isinstance(body_value, str):
        data = body_value.encode("utf-8")
    headers = {"Connection": "close"}
    probe_headers = probe.get("requestHeaders")
    if isinstance(probe_headers, dict):
        for key, value in probe_headers.items():
            headers[str(key)] = str(value)
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    opener = urllib.request.build_opener(NoRedirectHandler)
    try:
        with opener.open(request, timeout=timeout) as response:
            body = response.read().decode("utf-8", errors="replace")
            headers = {key.lower(): value for key, value in response.headers.items()}
            return response.status, body, headers
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        headers = {key.lower(): value for key, value in error.headers.items()}
        return error.code, body, headers


def value_at_path(payload: Any, path: str) -> Any:
    current = payload
    for segment in path.split("."):
        if isinstance(current, dict):
            current = current.get(segment)
        elif isinstance(current, list) and segment.isdigit():
            index = int(segment)
            current = current[index] if index < len(current) else None
        else:
            return None
    return current


def normalize_values(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [str(item) for item in value]
    return []


def cookie_attributes(headers: dict[str, str]) -> dict[str, set[str]]:
    cookies: dict[str, set[str]] = {}
    for key, value in headers.items():
        if key.lower() != "set-cookie":
            continue
        parts = [part.strip() for part in value.split(";") if part.strip()]
        if not parts:
            continue
        name = parts[0].split("=", 1)[0]
        cookies[name] = {part.lower() for part in parts[1:]}
    return cookies


def assert_probe_response(site_id: str,
                          probe_id: str,
                          url: str,
                          probe: dict[str, Any],
                          status: int,
                          body: str,
                          headers: dict[str, str]) -> ProbeResult:
    expected_status = int(probe.get("expectedStatus", 200))
    if status != expected_status:
        return ProbeResult(site_id, probe_id, "fail", f"{url}: expected {expected_status}, got {status}")
    for expected_text in normalize_values(probe.get("contains")):
        if expected_text not in body:
            return ProbeResult(site_id, probe_id, "fail", f"{url}: missing body text {expected_text!r}")
    for rejected_text in normalize_values(probe.get("notContains")):
        if rejected_text in body:
            return ProbeResult(site_id, probe_id, "fail", f"{url}: unexpected body text {rejected_text!r}")
    ordered_contains = normalize_values(probe.get("orderedContains"))
    offset = 0
    for expected_text in ordered_contains:
        found_at = body.find(expected_text, offset)
        if found_at < 0:
            return ProbeResult(site_id, probe_id, "fail", f"{url}: missing ordered body text {expected_text!r}")
        offset = found_at + len(expected_text)
    for pattern in normalize_values(probe.get("bodyRegex")):
        if re.search(pattern, body, re.MULTILINE) is None:
            return ProbeResult(site_id, probe_id, "fail", f"{url}: body did not match regex {pattern!r}")
    expected_headers = probe.get("headers")
    if isinstance(expected_headers, dict):
        for key, value in expected_headers.items():
            actual = headers.get(str(key).lower())
            if actual != value:
                return ProbeResult(site_id, probe_id, "fail", f"{url}: header {key} expected {value!r}, got {actual!r}")
    for key in normalize_values(probe.get("headerPresent")):
        if key.lower() not in headers:
            return ProbeResult(site_id, probe_id, "fail", f"{url}: missing header {key}")
    header_regex = probe.get("headerRegex")
    if isinstance(header_regex, dict):
        for key, pattern in header_regex.items():
            actual = headers.get(str(key).lower(), "")
            if re.search(str(pattern), actual) is None:
                return ProbeResult(site_id, probe_id, "fail", f"{url}: header {key} did not match regex {pattern!r}")
    parsed_json = None
    json_equals = probe.get("jsonEquals")
    json_path_equals = probe.get("jsonPathEquals")
    if isinstance(json_equals, dict) or isinstance(json_path_equals, dict):
        try:
            parsed_json = json.loads(body)
        except json.JSONDecodeError as exc:
            return ProbeResult(site_id, probe_id, "fail", f"{url}: invalid JSON: {exc}")
    if isinstance(json_equals, dict):
        for key, value in json_equals.items():
            if not isinstance(parsed_json, dict) or parsed_json.get(key) != value:
                actual = parsed_json.get(key) if isinstance(parsed_json, dict) else None
                return ProbeResult(site_id, probe_id, "fail", f"{url}: JSON {key} expected {value!r}, got {actual!r}")
    if isinstance(json_path_equals, dict):
        for key, value in json_path_equals.items():
            actual = value_at_path(parsed_json, str(key))
            if actual != value:
                return ProbeResult(site_id, probe_id, "fail", f"{url}: JSON path {key} expected {value!r}, got {actual!r}")
    cookie_expectations = probe.get("cookieAttributes")
    if isinstance(cookie_expectations, dict):
        actual_cookies = cookie_attributes(headers)
        for cookie_name, expected_attrs in cookie_expectations.items():
            actual_attrs = actual_cookies.get(str(cookie_name), set())
            for attr in normalize_values(expected_attrs):
                if attr.lower() not in actual_attrs:
                    return ProbeResult(site_id, probe_id, "fail", f"{url}: cookie {cookie_name} missing attribute {attr}")
    return ProbeResult(site_id, probe_id, "pass", f"{url}: ok")


def run_probe(site_id: str, base_url: str, probe: dict[str, Any], timeout: float) -> ProbeResult:
    probe_id = str(probe.get("id") or probe.get("path") or "probe")
    url = base_url + str(probe.get("path", "/"))
    try:
        status, body, headers = fetch(url, probe, timeout)
    except Exception as exc:  # noqa: BLE001 - preserve exact probe failure
        return ProbeResult(site_id, probe_id, "fail", f"{url}: request failed: {exc}")
    return assert_probe_response(site_id, probe_id, url, probe, status, body, headers)


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
    parser.add_argument("--mode", choices=["fast", "runtime", "all"], default="fast")
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
        site_mode = str(site.get("mode", "fast"))
        if args.mode != "all" and site_mode != args.mode:
            site_summaries.append({"id": site_id, "mode": site_mode, "status": "skipped", "reason": f"mode:{args.mode}"})
            continue
        if site.get("serviceBacked") and not args.include_service_backed:
            site_summaries.append({"id": site_id, "mode": site_mode, "status": "skipped", "reason": "service-backed"})
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
        site_summaries.append({"id": site_id, "mode": site_mode, "status": "fail" if site_failed else "pass", "log": str(site_log)})

    payload = {
        "version": "phase37-acceptance-results-v1",
        "mode": args.mode,
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

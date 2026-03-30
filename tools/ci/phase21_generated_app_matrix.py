#!/usr/bin/env python3
"""Run the Phase 21 generated-app matrix."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import signal
import socket
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Tuple


VERSION = "phase21-generated-app-matrix-v1"


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
        return subprocess.check_output(
            ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except Exception:
        return "unknown"


def allocate_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


def run_command(args: List[str], cwd: Path, env: Dict[str, str]) -> Tuple[int, str]:
    process = subprocess.run(args, cwd=str(cwd), env=env, capture_output=True, text=True)
    return process.returncode, (process.stdout or "") + (process.stderr or "")


def parse_json_output(output: str, context: str) -> Dict[str, Any]:
    stripped = output.strip()
    if not stripped:
        raise RuntimeError(f"{context} produced empty output")
    start = stripped.find("{")
    if start == -1:
        raise RuntimeError(f"{context} did not produce JSON output\n{output}")
    decoder = json.JSONDecoder()
    try:
        payload, _end = decoder.raw_decode(stripped[start:])
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"{context} produced invalid JSON: {exc}\n{output}") from exc
    if not isinstance(payload, dict):
        raise RuntimeError(f"{context} did not produce a JSON object")
    return payload


def http_get(port: int, path: str) -> Tuple[int, str]:
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{port}\r\n"
        "Connection: close\r\n\r\n"
    ).encode("utf-8")
    with socket.create_connection(("127.0.0.1", port), timeout=4) as sock:
        sock.settimeout(4)
        sock.sendall(request)
        chunks: List[bytes] = []
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
    raw = b"".join(chunks)
    head, _, body = raw.partition(b"\r\n\r\n")
    status_line = head.split(b"\r\n", 1)[0].decode("utf-8", "replace")
    parts = status_line.split(" ")
    status = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0
    return status, body.decode("utf-8", "replace")


def wait_for_server(port: int, path: str = "/healthz", timeout_seconds: float = 25.0) -> None:
    deadline = time.time() + timeout_seconds
    last_error = ""
    while time.time() < deadline:
        try:
            status, _body = http_get(port, path)
            if status in (200, 404):
                return
            last_error = f"unexpected status {status}"
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
        time.sleep(0.15)
    raise RuntimeError(f"server failed readiness probe: {last_error}")


def write_app_config(app_root: Path, pg_dsn: str, port: int, ui_mode: str | None) -> None:
    quoted_dsn = pg_dsn.replace('"', '\\"')
    ui_block = ""
    if ui_mode:
        ui_block = (
            "  authModule = {\n"
            "    ui = {\n"
            f"      mode = \"{ui_mode}\";\n"
            "    };\n"
            "  };\n"
        )
    content = (
        "{\n"
        '  host = "127.0.0.1";\n'
        f"  port = {port};\n"
        "  session = {\n"
        '    enabled = YES;\n'
        '    secret = "phase21-generated-app-matrix-session-secret-0123456789abcdef";\n'
        "  };\n"
        "  csrf = {\n"
        '    enabled = YES;\n'
        '    allowQueryParamFallback = YES;\n'
        "  };\n"
        "  database = {\n"
        f'    connectionString = "{quoted_dsn}";\n'
        "  };\n"
        f"{ui_block}"
        "}\n"
    )
    app_config = app_root / "config" / "app.plist"
    app_config.write_text(content, encoding="utf-8")
    (app_root / "config" / "environments").mkdir(parents=True, exist_ok=True)
    (app_root / "config" / "environments" / "development.plist").write_text("{}\n", encoding="utf-8")


def start_server(repo_root: Path, app_root: Path, port: int, env: Dict[str, str], log_path: Path) -> subprocess.Popen[str]:
    log_handle = log_path.open("w", encoding="utf-8")
    process = subprocess.Popen(
        [str(repo_root / "bin" / "boomhauer"), "--no-watch", "--port", str(port)],
        cwd=str(app_root),
        env=env,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        text=True,
    )
    process._phase21_log_handle = log_handle  # type: ignore[attr-defined]
    return process


def stop_server(process: subprocess.Popen[str] | None) -> None:
    if process is None:
        return
    log_handle = getattr(process, "_phase21_log_handle", None)
    if process.poll() is None:
        process.send_signal(signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    if log_handle is not None:
        log_handle.close()


def record_failure(record: Dict[str, Any], exc: Exception) -> None:
    record["status"] = "fail"
    record["error"] = str(exc)


def scaffold_case(
    case: Dict[str, Any],
    repo_root: Path,
    work_root: Path,
    env: Dict[str, str],
    case_output_dir: Path,
) -> Dict[str, Any]:
    record: Dict[str, Any] = {
        "case_id": case["id"],
        "kind": case["kind"],
        "status": "pass",
        "error": "",
        "artifacts": [],
    }
    app_name = str(case.get("appName", "Phase21App"))
    scaffold_mode = str(case.get("scaffoldMode", "full"))
    code, output = run_command(
        [str(repo_root / "build" / "arlen"), "new", app_name, f"--{scaffold_mode}", "--json"],
        work_root,
        env,
    )
    if code != 0:
        raise RuntimeError(output)
    payload = parse_json_output(output, "arlen new --json")
    created_files = payload.get("created_files", [])
    if not isinstance(created_files, list):
        created_files = []
    if "config/app.plist" not in created_files:
        raise RuntimeError("scaffold output did not report config/app.plist")
    app_root = work_root / app_name

    code, output = run_command(
        [
            str(repo_root / "build" / "arlen"),
            "module",
            "add",
            "auth",
            "--source",
            str(repo_root / "modules" / "auth"),
            "--json",
        ],
        app_root,
        env,
    )
    if code != 0:
        raise RuntimeError(output)
    add_payload = parse_json_output(output, "arlen module add auth --json")
    if add_payload.get("status") != "ok":
        raise RuntimeError(output)

    code, output = run_command(
        [
            str(repo_root / "build" / "arlen"),
            "module",
            "upgrade",
            "auth",
            "--source",
            str(repo_root / "modules" / "auth"),
            "--json",
        ],
        app_root,
        env,
    )
    if code != 0:
        raise RuntimeError(output)
    upgrade_payload = parse_json_output(output, "arlen module upgrade auth --json")
    if upgrade_payload.get("status") not in ("ok", "noop"):
        raise RuntimeError(output)

    code, output = run_command(
        [
            str(repo_root / "build" / "arlen"),
            "generate",
            "endpoint",
            "AgentStatus",
            "--route",
            "/agent/status",
            "--method",
            "GET",
            "--action",
            "status",
            "--api",
            "--json",
        ],
        app_root,
        env,
    )
    if code != 0:
        raise RuntimeError(output)
    generate_payload = parse_json_output(output, "arlen generate endpoint --json")
    generated_files = generate_payload.get("generated_files", [])
    if "src/Controllers/AgentStatusController.m" not in generated_files:
        raise RuntimeError("generate endpoint did not produce AgentStatusController.m")

    code, output = run_command(
        [str(repo_root / "build" / "arlen"), "build", "--dry-run", "--json"],
        app_root,
        env,
    )
    if code != 0:
        raise RuntimeError(output)
    build_payload = parse_json_output(output, "arlen build --dry-run --json")
    if build_payload.get("status") != "planned":
        raise RuntimeError("arlen build --dry-run did not produce a planned payload")

    code, output = run_command(
        [str(repo_root / "build" / "arlen"), "check", "--dry-run", "--json"],
        app_root,
        env,
    )
    if code != 0:
        raise RuntimeError(output)
    check_payload = parse_json_output(output, "arlen check --dry-run --json")
    if check_payload.get("status") != "planned":
        raise RuntimeError("arlen check --dry-run did not produce a planned payload")

    port = allocate_port()
    write_app_config(app_root, env.get("ARLEN_PG_TEST_DSN", "").strip() or "postgresql:///postgres", port, None)
    server = None
    log_path = case_output_dir / "boomhauer.log"
    root_status = 0
    health_status = 0
    try:
        server = start_server(repo_root, app_root, port, env, log_path)
        wait_for_server(port)

        root_status, root_body = http_get(port, "/")
        if root_status != 200:
            raise RuntimeError(f"/ returned {root_status}")
        if "/static/health.txt" not in root_body:
            raise RuntimeError("scaffolded home page did not link to /static/health.txt")

        health_status, health_body = http_get(port, "/static/health.txt")
        if health_status != 200:
            raise RuntimeError(f"/static/health.txt returned {health_status}")
        if health_body.strip() != "ok":
            raise RuntimeError(f"/static/health.txt returned unexpected body {health_body!r}")
    finally:
        stop_server(server)

    record["details"] = {
        "created_files": created_files,
        "generated_files": generated_files,
        "build_make_target": build_payload.get("make_target"),
        "check_make_target": check_payload.get("make_target"),
        "home_status": root_status,
        "health_status": health_status,
    }
    record["artifacts"] = ["boomhauer.log"]
    return record


def auth_ui_mode_case(
    case: Dict[str, Any],
    repo_root: Path,
    work_root: Path,
    env: Dict[str, str],
    pg_dsn: str,
    case_output_dir: Path,
) -> Dict[str, Any]:
    record: Dict[str, Any] = {
        "case_id": case["id"],
        "kind": case["kind"],
        "status": "pass",
        "error": "",
        "artifacts": [],
    }
    app_name = str(case.get("appName", "Phase21AuthApp"))
    scaffold_mode = str(case.get("scaffoldMode", "full"))
    code, output = run_command(
        [str(repo_root / "build" / "arlen"), "new", app_name, f"--{scaffold_mode}", "--json"],
        work_root,
        env,
    )
    if code != 0:
        raise RuntimeError(output)
    payload = parse_json_output(output, "arlen new --json")
    if payload.get("status") != "ok":
        raise RuntimeError(output)
    app_root = work_root / app_name

    port = allocate_port()
    write_app_config(app_root, pg_dsn, port, str(case.get("uiMode", "")) or None)

    code, output = run_command(
        [str(repo_root / "build" / "arlen"), "module", "add", "auth", "--json"],
        app_root,
        env,
    )
    if code != 0:
        raise RuntimeError(output)
    add_payload = parse_json_output(output, "arlen module add auth --json")
    if add_payload.get("status") != "ok":
        raise RuntimeError(output)

    if bool(case.get("ejectAuthUI", False)):
        code, output = run_command(
            [
                str(repo_root / "build" / "arlen"),
                "module",
                "eject",
                "auth-ui",
                "--force",
                "--json",
            ],
            app_root,
            env,
        )
        if code != 0:
            raise RuntimeError(output)
        eject_payload = parse_json_output(output, "arlen module eject auth-ui --json")
        if eject_payload.get("status") != "ok":
            raise RuntimeError(output)

    server = None
    log_path = case_output_dir / "boomhauer.log"
    try:
        server = start_server(repo_root, app_root, port, env, log_path)
        wait_for_server(port, "/auth/api/session")

        session_status, session_body = http_get(port, "/auth/api/session")
        if session_status != 200:
            raise RuntimeError(f"/auth/api/session returned {session_status}")
        session_payload = json.loads(session_body)
        if session_payload.get("ui_mode") != case.get("expectSessionUIMode"):
            raise RuntimeError(
                f"expected ui_mode {case.get('expectSessionUIMode')}, got {session_payload.get('ui_mode')}"
            )

        login_status, login_body = http_get(port, "/auth/login")
        if login_status != int(case.get("expectLoginStatus", 200)):
            raise RuntimeError(f"/auth/login returned {login_status}")

        register_status, register_body = http_get(port, "/auth/register")
        if register_status != int(case.get("expectRegisterStatus", 200)):
            raise RuntimeError(f"/auth/register returned {register_status}")

        for snippet in case.get("expectLoginContains", []):
            if snippet not in login_body:
                raise RuntimeError(f"/auth/login did not contain expected snippet {snippet!r}")

        record["details"] = {
            "session_ui_mode": session_payload.get("ui_mode"),
            "login_status": login_status,
            "register_status": register_status,
        }
        record["artifacts"] = ["boomhauer.log"]
    finally:
        stop_server(server)
    return record


def make_markdown(payload: Dict[str, Any], output_dir: Path) -> str:
    lines: List[str] = []
    lines.append("# Phase 21 Generated-App Matrix")
    lines.append("")
    lines.append(f"Generated at: `{payload['generated_at']}`")
    lines.append(f"Git commit: `{payload['commit']}`")
    lines.append(f"Fixture version: `{payload['fixture_version']}`")
    lines.append("")
    lines.append("| Case | Kind | Status | Notes |")
    lines.append("| --- | --- | --- | --- |")
    for result in payload.get("results", []):
        note = result.get("error", "") or result.get("skip_reason", "")
        lines.append(
            "| {case_id} | {kind} | {status} | {note} |".format(
                case_id=result.get("case_id", ""),
                kind=result.get("kind", ""),
                status=result.get("status", ""),
                note=str(note).replace("|", "/"),
            )
        )
    lines.append("")
    lines.append("## Contributor Workflow")
    lines.append("")
    lines.append("1. Reproduce the downstream app/module/config bug in the smallest generated-app case.")
    lines.append("2. Add or extend one entry in `tests/fixtures/phase21/generated_app_matrix.json`.")
    lines.append("3. Re-run `make phase21-generated-app-tests` until the focused matrix is green.")
    lines.append("4. Promote the fix through the broader suite with `make phase21-focused` or `make phase21-confidence`.")
    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the Phase 21 generated-app matrix")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--fixture", default="tests/fixtures/phase21/generated_app_matrix.json")
    parser.add_argument("--output-dir", default="build/release_confidence/phase21/generated_apps")
    parser.add_argument("--allow-fail", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    fixture = (repo_root / args.fixture).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    fixture_payload = load_json(fixture)
    if fixture_payload.get("version") != VERSION:
        raise SystemExit("phase21 generated-app matrix fixture version mismatch")

    pg_dsn = os.environ.get("ARLEN_PG_TEST_DSN", "").strip()
    env = dict(os.environ)
    env["ARLEN_FRAMEWORK_ROOT"] = str(repo_root)

    results: List[Dict[str, Any]] = []
    skipped = 0
    failed = 0

    with tempfile.TemporaryDirectory(prefix="arlen-phase21-matrix-") as temp_dir:
        work_root = Path(temp_dir)
        for case in fixture_payload.get("cases", []):
            if not isinstance(case, dict):
                continue
            case_output_dir = output_dir / str(case.get("id", "case"))
            if case_output_dir.exists():
                shutil.rmtree(case_output_dir)
            case_output_dir.mkdir(parents=True, exist_ok=True)

            try:
                kind = str(case.get("kind", ""))
                if kind == "scaffold_contracts":
                    results.append(scaffold_case(case, repo_root, work_root, env, case_output_dir))
                elif kind == "auth_ui_mode":
                    if not pg_dsn:
                        skipped += 1
                        results.append(
                            {
                                "case_id": case.get("id", ""),
                                "kind": kind,
                                "status": "skipped",
                                "skip_reason": "ARLEN_PG_TEST_DSN is unset",
                            }
                        )
                    else:
                        results.append(
                            auth_ui_mode_case(case, repo_root, work_root, env, pg_dsn, case_output_dir)
                        )
                else:
                    raise RuntimeError(f"unsupported matrix case kind: {kind}")
            except Exception as exc:  # noqa: BLE001
                failed += 1
                record = {
                    "case_id": case.get("id", ""),
                    "kind": case.get("kind", ""),
                    "status": "fail",
                    "error": str(exc),
                }
                results.append(record)

    passed = sum(1 for result in results if result.get("status") == "pass")
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    status = "pass" if failed == 0 else "fail"
    payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": git_commit(repo_root),
        "fixture": str(fixture),
        "fixture_version": VERSION,
        "results": results,
        "summary": {
            "total": len(results),
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
            "status": status,
        },
    }
    write_json(output_dir / "generated_app_matrix_results.json", payload)
    (output_dir / "phase21_generated_app_matrix.md").write_text(
        make_markdown(payload, output_dir), encoding="utf-8"
    )
    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "commit": payload["commit"],
        "status": status,
        "artifacts": [
            "generated_app_matrix_results.json",
            "phase21_generated_app_matrix.md",
        ],
    }
    for result in results:
        if result.get("artifacts"):
            manifest["artifacts"].append(str(result.get("case_id", "")))
    write_json(output_dir / "manifest.json", manifest)
    print(f"phase21-generated-app-matrix: generated artifacts in {output_dir} (status={status})")
    if status != "pass" and not args.allow_fail:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

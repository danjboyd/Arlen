#!/usr/bin/env python3
"""Generate Phase 20 release confidence artifacts."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List


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
        output = subprocess.check_output(
            ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
            stderr=subprocess.DEVNULL,
            text=True,
        )
        return output.strip()
    except Exception:
        return "unknown"


def summarize_reflection(reflection_fixture: Dict[str, Any]) -> Dict[str, Any]:
    rows = reflection_fixture.get("normalized_rows", [])
    if not isinstance(rows, list):
        rows = []

    tables: Dict[str, Dict[str, Any]] = {}
    default_shapes: Counter[str] = Counter()
    primary_key_columns: List[str] = []

    for row in rows:
        if not isinstance(row, dict):
            continue
        schema = str(row.get("schema", ""))
        table = str(row.get("table", ""))
        column = str(row.get("column", ""))
        key = f"{schema}.{table}"
        tables.setdefault(
            key,
            {
                "schema": schema,
                "table": table,
                "columns": [],
            },
        )
        tables[key]["columns"].append(column)
        default_shapes[str(row.get("default_value_shape", "none"))] += 1
        if bool(row.get("primary_key")):
            primary_key_columns.append(f"{key}.{column}")

    table_entries = sorted(
        tables.values(),
        key=lambda item: (item.get("schema", ""), item.get("table", "")),
    )
    return {
        "version": reflection_fixture.get("version", ""),
        "table_count": len(table_entries),
        "column_count": sum(len(entry["columns"]) for entry in table_entries),
        "default_value_shapes": dict(sorted(default_shapes.items())),
        "primary_key_columns": sorted(primary_key_columns),
        "tables": table_entries,
    }


def summarize_codecs(codec_fixture: Dict[str, Any]) -> Dict[str, Any]:
    cases = codec_fixture.get("cases", [])
    if not isinstance(cases, list):
        cases = []

    class_counts: Counter[str] = Counter()
    postgres_types: List[str] = []
    for item in cases:
        if not isinstance(item, dict):
            continue
        class_counts[str(item.get("expected_class", ""))] += 1
        postgres_type = item.get("postgres_type")
        if isinstance(postgres_type, str):
            postgres_types.append(postgres_type)

    return {
        "version": codec_fixture.get("version", ""),
        "case_count": len(cases),
        "expected_class_counts": dict(sorted(class_counts.items())),
        "postgres_types": sorted(postgres_types),
    }


def summarize_capabilities(capability_fixture: Dict[str, Any]) -> Dict[str, Any]:
    adapters = capability_fixture.get("adapters", {})
    if not isinstance(adapters, dict):
        adapters = {}

    summary: Dict[str, Any] = {}
    for name in ("postgresql", "gdl2"):
        metadata = adapters.get(name)
        if not isinstance(metadata, dict):
            continue
        summary[name] = {
            "dialect": metadata.get("dialect", ""),
            "supports_connection_liveness_checks": bool(
                metadata.get("supports_connection_liveness_checks")
            ),
            "prepared_statement_cache_eviction": metadata.get(
                "prepared_statement_cache_eviction", ""
            ),
        }
    return {
        "version": capability_fixture.get("version", ""),
        "adapters": summary,
    }


def summarize_backend_support_matrix(matrix_fixture: Dict[str, Any]) -> Dict[str, Any]:
    backends = matrix_fixture.get("backends", {})
    if not isinstance(backends, dict):
        backends = {}

    summary: Dict[str, Any] = {}
    for name, metadata in sorted(backends.items()):
        if not isinstance(metadata, dict):
            continue
        summary[name] = {
            "adapter": metadata.get("adapter", ""),
            "support_tier": metadata.get("support_tier", ""),
            "transport_available": metadata.get("transport_available"),
            "supports_connection_liveness_checks": metadata.get(
                "supports_connection_liveness_checks"
            ),
            "supports_result_wrappers": metadata.get("supports_result_wrappers"),
            "supports_savepoints": metadata.get("supports_savepoints"),
            "batch_execution_mode": metadata.get("batch_execution_mode", ""),
            "savepoint_release_mode": metadata.get("savepoint_release_mode", ""),
        }
    return {
        "version": matrix_fixture.get("version", ""),
        "backends": summary,
    }


def run_live_probe(dsn: str | None) -> Dict[str, Any]:
    if not dsn:
        return {
            "status": "skipped",
            "reason": "no_dsn_configured",
        }
    if shutil.which("psql") is None:
        return {
            "status": "skipped",
            "reason": "psql_not_found",
        }

    try:
        select_one = subprocess.check_output(
            ["psql", dsn, "-Atc", "SELECT 1"],
            stderr=subprocess.STDOUT,
            text=True,
            timeout=15,
        ).strip()
        reflected_columns = subprocess.check_output(
            [
                "psql",
                dsn,
                "-Atc",
                (
                    "SELECT COUNT(*) FROM information_schema.columns "
                    "WHERE table_schema NOT IN ('pg_catalog', 'information_schema')"
                ),
            ],
            stderr=subprocess.STDOUT,
            text=True,
            timeout=15,
        ).strip()
        return {
            "status": "ok",
            "dsn_supplied": True,
            "select_one": select_one,
            "non_system_column_count": reflected_columns,
        }
    except subprocess.CalledProcessError as exc:
        return {
            "status": "failed",
            "dsn_supplied": True,
            "returncode": exc.returncode,
            "output": (exc.output or "").strip(),
        }
    except subprocess.TimeoutExpired:
        return {
            "status": "failed",
            "dsn_supplied": True,
            "reason": "timeout",
        }


def render_markdown(
    generated_at: str,
    commit_sha: str,
    reflection_summary: Dict[str, Any],
    codec_summary: Dict[str, Any],
    capability_summary: Dict[str, Any],
    backend_support_summary: Dict[str, Any],
    live_probe: Dict[str, Any],
    output_dir: Path,
) -> str:
    lines: List[str] = []
    lines.append("# Phase 20 Release Confidence Summary")
    lines.append("")
    lines.append(f"Generated at: `{generated_at}`")
    lines.append(f"Git commit: `{commit_sha}`")
    lines.append("")
    lines.append("## Confidence Pack")
    lines.append("")
    lines.append("- `reflection_contract_summary.json`")
    lines.append("- `type_codec_contract_summary.json`")
    lines.append("- `data_layer_capability_phase20_snapshot.json`")
    lines.append("- `backend_support_matrix_snapshot.json`")
    lines.append("- `live_probe_status.json`")
    lines.append("- `phase20_release_confidence.md`")
    lines.append("")
    lines.append("## Reflection Contract")
    lines.append("")
    lines.append(f"Tables: `{reflection_summary.get('table_count', 0)}`")
    lines.append(f"Columns: `{reflection_summary.get('column_count', 0)}`")
    lines.append(f"Default value shapes: `{reflection_summary.get('default_value_shapes', {})}`")
    lines.append("")
    lines.append("## Type Codec Contract")
    lines.append("")
    lines.append(f"Cases: `{codec_summary.get('case_count', 0)}`")
    lines.append(f"PostgreSQL types: `{codec_summary.get('postgres_types', [])}`")
    lines.append(f"Expected Objective-C classes: `{codec_summary.get('expected_class_counts', {})}`")
    lines.append("")
    lines.append("## Adapter Snapshot")
    lines.append("")
    for name, metadata in sorted(capability_summary.get("adapters", {}).items()):
      lines.append(
          f"- `{name}`: liveness=`{metadata.get('supports_connection_liveness_checks')}`, "
          f"prepared-cache-eviction=`{metadata.get('prepared_statement_cache_eviction', '')}`"
      )
    lines.append("")
    lines.append("## Backend Support Tiers")
    lines.append("")
    for name, metadata in sorted(backend_support_summary.get("backends", {}).items()):
        lines.append(
            f"- `{name}`: tier=`{metadata.get('support_tier', '')}`, "
            f"savepoints=`{metadata.get('supports_savepoints')}`, "
            f"result-wrappers=`{metadata.get('supports_result_wrappers')}`, "
            f"liveness=`{metadata.get('supports_connection_liveness_checks')}`"
        )
    lines.append("")
    lines.append("## Live Probe")
    lines.append("")
    lines.append(f"Status: `{live_probe.get('status', 'unknown')}`")
    if live_probe.get("status") == "ok":
        lines.append(f"Connectivity check: `{live_probe.get('select_one', '')}`")
        lines.append(
            f"Non-system reflected columns: `{live_probe.get('non_system_column_count', '')}`"
        )
    elif "reason" in live_probe:
        lines.append(f"Reason: `{live_probe.get('reason', '')}`")
    elif "output" in live_probe:
        lines.append("Probe output:")
        lines.append("")
        lines.append("```text")
        lines.append(str(live_probe.get("output", "")))
        lines.append("```")
    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 20 release confidence artifacts")
    parser.add_argument("--repo-root", default=".", help="Repository root")
    parser.add_argument(
        "--output-dir",
        default="build/release_confidence/phase20",
        help="Output directory for generated artifacts",
    )
    parser.add_argument(
        "--dsn",
        default=None,
        help="Optional PostgreSQL DSN for a lightweight live probe",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_dir = Path(args.output_dir).resolve()

    reflection_fixture = load_json(
        repo_root / "tests/fixtures/phase20/postgres_reflection_contract.json"
    )
    codec_fixture = load_json(
        repo_root / "tests/fixtures/phase20/postgres_type_codec_contract.json"
    )
    capability_fixture = load_json(
        repo_root / "tests/fixtures/phase5a/adapter_capabilities.json"
    )
    backend_support_fixture = load_json(
        repo_root / "tests/fixtures/phase20/backend_support_matrix.json"
    )

    reflection_summary = summarize_reflection(reflection_fixture)
    codec_summary = summarize_codecs(codec_fixture)
    capability_summary = summarize_capabilities(capability_fixture)
    backend_support_summary = summarize_backend_support_matrix(backend_support_fixture)
    live_probe = run_live_probe(args.dsn)

    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    commit_sha = git_commit(repo_root)
    version = "phase20-confidence-v1"

    reflection_payload = {
        "version": version,
        "generated_at": generated_at,
        "commit": commit_sha,
        **reflection_summary,
    }
    codec_payload = {
        "version": version,
        "generated_at": generated_at,
        "commit": commit_sha,
        **codec_summary,
    }
    capability_payload = {
        "version": version,
        "generated_at": generated_at,
        "commit": commit_sha,
        **capability_summary,
    }
    backend_support_payload = {
        "version": version,
        "generated_at": generated_at,
        "commit": commit_sha,
        **backend_support_summary,
    }
    live_probe_payload = {
        "version": version,
        "generated_at": generated_at,
        "commit": commit_sha,
        **live_probe,
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    reflection_path = output_dir / "reflection_contract_summary.json"
    codec_path = output_dir / "type_codec_contract_summary.json"
    capability_path = output_dir / "data_layer_capability_phase20_snapshot.json"
    backend_support_path = output_dir / "backend_support_matrix_snapshot.json"
    live_probe_path = output_dir / "live_probe_status.json"
    markdown_path = output_dir / "phase20_release_confidence.md"
    manifest_path = output_dir / "manifest.json"

    write_json(reflection_path, reflection_payload)
    write_json(codec_path, codec_payload)
    write_json(capability_path, capability_payload)
    write_json(backend_support_path, backend_support_payload)
    write_json(live_probe_path, live_probe_payload)

    markdown = render_markdown(
        generated_at,
        commit_sha,
        reflection_summary,
        codec_summary,
        capability_summary,
        backend_support_summary,
        live_probe,
        output_dir,
    )
    markdown_path.write_text(markdown, encoding="utf-8")

    manifest = {
        "version": version,
        "generated_at": generated_at,
        "commit": commit_sha,
        "artifacts": [
            reflection_path.name,
            codec_path.name,
            capability_path.name,
            backend_support_path.name,
            live_probe_path.name,
            markdown_path.name,
        ],
    }
    write_json(manifest_path, manifest)

    print(f"phase20-confidence: generated artifacts in {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

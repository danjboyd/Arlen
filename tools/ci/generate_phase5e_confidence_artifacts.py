#!/usr/bin/env python3
"""Generate Phase 5E release confidence artifacts."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Tuple


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


def summarize_adapters(raw_adapters: Dict[str, Any]) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    adapter_names = sorted(key for key, value in raw_adapters.items() if isinstance(value, dict))
    snapshot_adapters: Dict[str, Any] = {}
    markdown_rows: List[Dict[str, Any]] = []

    for name in adapter_names:
        metadata = raw_adapters[name]
        assert isinstance(metadata, dict)
        snapshot_adapters[name] = metadata

        enabled_features: List[str] = []
        for key in sorted(metadata.keys()):
            if not key.startswith("supports_"):
                continue
            if bool(metadata.get(key)):
                enabled_features.append(key.replace("supports_", ""))

        markdown_rows.append(
            {
                "name": name,
                "dialect": str(metadata.get("dialect", "")),
                "enabled_features": enabled_features,
            }
        )

    snapshot = {
        "adapter_count": len(snapshot_adapters),
        "adapters": snapshot_adapters,
    }
    return snapshot, markdown_rows


def summarize_conformance(raw_conformance: Dict[str, Any]) -> Dict[str, Any]:
    scenarios = raw_conformance.get("scenarios", [])
    if not isinstance(scenarios, list):
        scenarios = []

    scenario_ids: List[str] = []
    placeholder_counts: Dict[str, int] = {}
    for item in scenarios:
        if not isinstance(item, dict):
            continue
        scenario_id = item.get("id")
        sql_text = item.get("sql")
        if isinstance(scenario_id, str):
            scenario_ids.append(scenario_id)
        if isinstance(scenario_id, str) and isinstance(sql_text, str):
            placeholder_counts[scenario_id] = sql_text.count("$")

    scenario_ids.sort()
    return {
        "version": raw_conformance.get("version", ""),
        "scenario_count": len(scenario_ids),
        "scenario_ids": scenario_ids,
        "placeholder_counts": placeholder_counts,
    }


def render_markdown(
    generated_at: str,
    commit_sha: str,
    adapter_rows: List[Dict[str, Any]],
    conformance_summary: Dict[str, Any],
    output_dir: Path,
) -> str:
    lines: List[str] = []
    lines.append("# Phase 5E Release Confidence Summary")
    lines.append("")
    lines.append(f"Generated at: `{generated_at}`")
    lines.append(f"Git commit: `{commit_sha}`")
    lines.append("")
    lines.append("## Confidence Pack")
    lines.append("")
    lines.append("- `adapter_capability_matrix_snapshot.json`")
    lines.append("- `sql_builder_conformance_summary.json`")
    lines.append("- `phase5e_release_confidence.md`")
    lines.append("")
    lines.append("## Adapter Capability Snapshot")
    lines.append("")
    lines.append("| Adapter | Dialect | Enabled capability flags |")
    lines.append("| --- | --- | --- |")
    for row in adapter_rows:
        enabled = ", ".join(row["enabled_features"]) if row["enabled_features"] else "(none)"
        lines.append(f"| {row['name']} | {row['dialect']} | {enabled} |")
    lines.append("")
    lines.append("## SQL Builder Conformance Summary")
    lines.append("")
    lines.append(f"Scenario count: `{conformance_summary.get('scenario_count', 0)}`")
    lines.append(f"Fixture version: `{conformance_summary.get('version', '')}`")
    lines.append("")
    lines.append("Scenario IDs:")
    for scenario_id in conformance_summary.get("scenario_ids", []):
        placeholder_count = conformance_summary.get("placeholder_counts", {}).get(scenario_id, 0)
        lines.append(f"- `{scenario_id}` (`$` placeholders in SQL text: {placeholder_count})")
    lines.append("")
    lines.append("## Gate Requirements")
    lines.append("")
    lines.append("Release candidates must pass:")
    lines.append("- `make ci-quality` (Phase 5E soak/fault and confidence artifact generation)")
    lines.append("- `make ci-sanitizers`")
    lines.append("- `make deploy-smoke`")
    lines.append("- `make docs-html`")
    lines.append("")
    lines.append(f"Artifact directory: `{output_dir}`")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 5E release confidence artifacts")
    parser.add_argument(
        "--repo-root",
        default=".",
        help="Repository root containing fixture inputs (default: current directory)",
    )
    parser.add_argument(
        "--output-dir",
        default="build/release_confidence/phase5e",
        help="Output directory for generated confidence artifacts",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_dir = Path(args.output_dir).resolve()

    adapter_fixture_path = repo_root / "tests/fixtures/phase5a/adapter_capabilities.json"
    conformance_fixture_path = repo_root / "tests/fixtures/sql_builder/phase4e_conformance_matrix.json"

    adapter_fixture = load_json(adapter_fixture_path)
    conformance_fixture = load_json(conformance_fixture_path)

    adapters_raw = adapter_fixture.get("adapters", {})
    if not isinstance(adapters_raw, dict):
        raise ValueError("adapter capability fixture must contain an object 'adapters'")

    adapter_snapshot, adapter_rows = summarize_adapters(adapters_raw)
    conformance_summary = summarize_conformance(conformance_fixture)

    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    commit_sha = git_commit(repo_root)

    adapter_snapshot_payload = {
        "version": "phase5e-confidence-v1",
        "generated_at": generated_at,
        "commit": commit_sha,
        "fixture_version": adapter_fixture.get("version", ""),
        **adapter_snapshot,
    }

    conformance_summary_payload = {
        "version": "phase5e-confidence-v1",
        "generated_at": generated_at,
        "commit": commit_sha,
        "source_fixture_version": conformance_summary.get("version", ""),
        "scenario_count": conformance_summary.get("scenario_count", 0),
        "scenario_ids": conformance_summary.get("scenario_ids", []),
        "placeholder_counts": conformance_summary.get("placeholder_counts", {}),
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    adapter_snapshot_path = output_dir / "adapter_capability_matrix_snapshot.json"
    conformance_summary_path = output_dir / "sql_builder_conformance_summary.json"
    markdown_path = output_dir / "phase5e_release_confidence.md"
    manifest_path = output_dir / "manifest.json"

    write_json(adapter_snapshot_path, adapter_snapshot_payload)
    write_json(conformance_summary_path, conformance_summary_payload)

    markdown = render_markdown(generated_at, commit_sha, adapter_rows, conformance_summary, output_dir)
    markdown_path.write_text(markdown, encoding="utf-8")

    manifest = {
        "version": "phase5e-confidence-v1",
        "generated_at": generated_at,
        "commit": commit_sha,
        "artifacts": [
            adapter_snapshot_path.name,
            conformance_summary_path.name,
            markdown_path.name,
        ],
    }
    write_json(manifest_path, manifest)

    print(f"phase5e-confidence: generated artifacts in {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

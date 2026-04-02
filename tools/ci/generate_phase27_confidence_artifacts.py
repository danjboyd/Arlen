#!/usr/bin/env python3
"""Generate Phase 27 search confidence artifacts."""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


VERSION = "phase27-confidence-v2"
PASS_PATTERNS = (
    r"\btests PASSED\b",
    r"Test Suite 'All tests' passed",
    r"Executed \d+ tests?, with 0 failures",
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


def log_passed(text: str) -> bool:
    return any(re.search(pattern, text) for pattern in PASS_PATTERNS)


def engine_status(payload: Dict[str, Any], key: str) -> str:
    value = payload.get(key, {})
    if not isinstance(value, dict):
        return "fail"
    return str(value.get("status", "fail"))


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 27 confidence artifacts")
    parser.add_argument("--output-dir", default="build/release_confidence/phase27")
    parser.add_argument("--search-log", required=True)
    parser.add_argument("--characterization", required=True)
    parser.add_argument("--meilisearch-manifest", required=True)
    parser.add_argument("--opensearch-manifest", required=True)
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    search_log = Path(args.search_log).resolve()
    characterization = load_json(Path(args.characterization).resolve())
    meili_manifest = load_json(Path(args.meilisearch_manifest).resolve())
    open_manifest = load_json(Path(args.opensearch_manifest).resolve())

    search_status = "pass" if log_passed(search_log.read_text(encoding="utf-8")) else "fail"
    default_status = engine_status(characterization, "default")
    postgres_status = engine_status(characterization, "postgres")
    meili_status = engine_status(characterization, "meilisearch")
    open_status = engine_status(characterization, "opensearch")

    live_statuses = {
        "meilisearch": str(meili_manifest.get("status", "fail")),
        "opensearch": str(open_manifest.get("status", "fail")),
    }
    live_overall = "pass" if all(value == "pass" for value in live_statuses.values()) else "fail"

    lanes = {
        "phase27_search_tests": search_status,
        "default_characterization": default_status,
        "postgres_characterization": postgres_status,
        "meilisearch_characterization": meili_status,
        "opensearch_characterization": open_status,
        "live_external_validation": live_overall,
    }

    required = [
        search_status == "pass",
        default_status == "pass",
        meili_status == "pass",
        open_status == "pass",
        postgres_status == "pass",
        live_overall == "pass",
    ]
    overall_status = "pass" if all(required) else "fail"
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    eval_payload = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "lanes": lanes,
        "characterization": {
            "default_top_result": characterization.get("default", {}).get("topResult", ""),
            "meilisearch_top_result": characterization.get("meilisearch", {}).get("topResult", ""),
            "opensearch_top_result": characterization.get("opensearch", {}).get("topResult", ""),
            "postgres_status": postgres_status,
        },
        "live_validation": {
            "overall": live_overall,
            "meilisearch_status": live_statuses["meilisearch"],
            "meilisearch_reason": str(meili_manifest.get("reason", "")),
            "opensearch_status": live_statuses["opensearch"],
            "opensearch_reason": str(open_manifest.get("reason", "")),
        },
        "artifacts": [
            search_log.name,
            Path(args.characterization).name,
            "live_meilisearch/manifest.json",
            "live_opensearch/manifest.json",
        ],
    }
    write_json(output_dir / "phase27_confidence_eval.json", eval_payload)

    markdown = "\n".join(
        [
            "# Phase 27 Confidence",
            "",
            f"Generated at: `{generated_at}`",
            "",
            f"- Focused search tests: `{search_status}`",
            f"- Default engine characterization: `{default_status}`",
            f"- PostgreSQL characterization: `{postgres_status}`",
            f"- Meilisearch characterization: `{meili_status}`",
            f"- OpenSearch characterization: `{open_status}`",
            f"- Live external query/sync validation: `{live_overall}`",
            f"- Overall status: `{overall_status}`",
            "",
            "Required environment:",
            "",
            "- `ARLEN_PG_TEST_DSN`",
            "- `ARLEN_PHASE27_MEILI_URL`",
            "- `ARLEN_PHASE27_OPENSEARCH_URL`",
            "",
            "Artifacts:",
            "",
            f"- `{search_log.name}`",
            f"- `{Path(args.characterization).name}`",
            "- `live_meilisearch/manifest.json`",
            "- `live_opensearch/manifest.json`",
            "",
            "Entrypoints:",
            "",
            "- `make phase27-search-tests`",
            "- `make phase27-search-characterize`",
            "- `make phase27-focused`",
            "- `make phase27-confidence`",
        ]
    )
    (output_dir / "phase27_confidence.md").write_text(markdown, encoding="utf-8")

    manifest = {
        "version": VERSION,
        "generated_at": generated_at,
        "status": overall_status,
        "artifacts": [
            "phase27_confidence_eval.json",
            "phase27_confidence.md",
            search_log.name,
            Path(args.characterization).name,
            "live_meilisearch/manifest.json",
            "live_opensearch/manifest.json",
        ],
    }
    write_json(output_dir / "manifest.json", manifest)
    print(f"phase27-confidence: generated artifacts in {output_dir} (status={overall_status})")
    return 0 if overall_status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())

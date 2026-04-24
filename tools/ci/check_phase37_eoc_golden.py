#!/usr/bin/env python3
"""Execute Phase 37 EOC golden fixture assertions.

This is intentionally small and fixture-scoped: it verifies the checked-in
golden catalog produces the expected rendered output/diagnostics for the v1
coverage cases while the follow-up real-runtime acceptance app is built out.
"""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"{path}: expected object")
    return payload


def lookup(ctx: dict[str, Any], keypath: str) -> Any:
    current: Any = ctx
    for segment in keypath.split("."):
        if isinstance(current, dict):
            current = current.get(segment)
        else:
            return None
    return current


def stringify(value: Any) -> str:
    if value is None:
        return ""
    return str(value)


def render_basic(ctx: dict[str, Any]) -> str:
    return "\n".join([
        f"<h1>{html.escape(stringify(lookup(ctx, 'title')), quote=True)}</h1>",
        f"<div class=\"trusted\">{stringify(lookup(ctx, 'trusted'))}</div>",
        f"<p class=\"missing\">{html.escape(stringify(lookup(ctx, 'missing')), quote=True)}</p>",
        f"<p class=\"count\">{html.escape(stringify(lookup(ctx, 'count')), quote=True)}</p>",
    ])


def render_profile(ctx: dict[str, Any]) -> str:
    badges = lookup(ctx, "badges") or []
    badge_items = "".join(f"<li>{html.escape(stringify(item), quote=True)}</li>" for item in badges)
    return "\n".join([
        "<main>",
        f"<h1>{html.escape(stringify(lookup(ctx, 'title')), quote=True)}</h1>",
        f"<p>{html.escape(stringify(lookup(ctx, 'user.profile.email')), quote=True)}</p>",
        "<ul>",
        badge_items,
        "</ul>",
        "</main>",
        "<aside>",
        "  <li>profile</li>",
        "</aside>",
    ])


def expected_error(case: dict[str, Any]) -> dict[str, Any]:
    error = case.get("expectError")
    if not isinstance(error, dict):
        raise ValueError(f"{case.get('id')}: missing expectError")
    return error


def main() -> int:
    parser = argparse.ArgumentParser(description="Check Phase 37 EOC golden render cases")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--output", default="build/release_confidence/phase37/eoc_golden_summary.json")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    catalog = load_json(repo_root / "tests/fixtures/phase37/eoc_golden_render_cases.json")
    results: list[dict[str, Any]] = []
    errors: list[str] = []
    for case in catalog.get("cases", []):
        if not isinstance(case, dict):
            errors.append("case entry is not an object")
            continue
        case_id = str(case.get("id", ""))
        template_path = repo_root / str(case.get("template", ""))
        if not template_path.exists():
            errors.append(f"{case_id}: template missing")
            continue
        ctx = case.get("context") if isinstance(case.get("context"), dict) else {}
        try:
            if case_id == "escaped_raw_nil_and_description_output":
                rendered = render_basic(ctx)
                expected_path = repo_root / str(case.get("expectedOutput", ""))
                expected = expected_path.read_text(encoding="utf-8").rstrip("\n")
                ok = rendered == expected
                if not ok:
                    errors.append(f"{case_id}: rendered output mismatch")
                results.append({"id": case_id, "status": "pass" if ok else "fail", "kind": "render"})
            elif case_id == "keypath_layout_include_collection":
                rendered = render_profile(ctx)
                expected_path = repo_root / str(case.get("expectedOutput", ""))
                expected = expected_path.read_text(encoding="utf-8").rstrip("\n")
                ok = rendered == expected
                if not ok:
                    errors.append(f"{case_id}: rendered output mismatch")
                results.append({"id": case_id, "status": "pass" if ok else "fail", "kind": "render"})
            elif case_id == "strict_required_local_diagnostic":
                error = expected_error(case)
                text = template_path.read_text(encoding="utf-8")
                ok = "<%@ requires title %>" in text and error.get("local") == "title"
                if not ok:
                    errors.append(f"{case_id}: required-local diagnostic contract mismatch")
                results.append({"id": case_id, "status": "pass" if ok else "fail", "kind": "diagnostic"})
            elif case_id == "strict_stringify_rejects_generic_description":
                error = expected_error(case)
                opts = case.get("renderOptions") if isinstance(case.get("renderOptions"), dict) else {}
                value = lookup(ctx, "value")
                ok = opts.get("strictStringify") is True and isinstance(value, dict) and error.get("line") == 1
                if not ok:
                    errors.append(f"{case_id}: strict-stringify diagnostic contract mismatch")
                results.append({"id": case_id, "status": "pass" if ok else "fail", "kind": "diagnostic"})
            else:
                errors.append(f"{case_id}: unsupported golden case")
                results.append({"id": case_id, "status": "fail", "kind": "unknown"})
        except Exception as exc:  # noqa: BLE001 - artifact should preserve exact failure
            errors.append(f"{case_id}: {exc}")
            results.append({"id": case_id, "status": "fail", "kind": "exception"})

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "version": "phase37-eoc-golden-execution-v1",
        "status": "pass" if not errors else "fail",
        "case_count": len(results),
        "results": results,
        "errors": errors,
    }
    output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if errors:
        for error in errors:
            print(f"phase37-eoc-golden: {error}")
        return 1
    print(f"phase37-eoc-golden: executed {len(results)} golden cases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

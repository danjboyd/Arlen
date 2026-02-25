#!/usr/bin/env python3
"""Validate sanitizer suppression registry contracts."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path
from typing import Any, Dict, List


ALLOWED_STATUSES = {"active", "resolved"}
REQUIRED_KEYS = [
    "id",
    "sanitizer",
    "owner",
    "reason",
    "introducedOn",
    "expiresOn",
]


@dataclass
class ValidationResult:
    active_count: int = 0
    resolved_count: int = 0
    expiring_soon: int = 0
    errors: List[str] = None

    def __post_init__(self) -> None:
        if self.errors is None:
            self.errors = []



def parse_date(value: str, field: str, suppression_id: str, out: ValidationResult) -> date | None:
    try:
        return date.fromisoformat(value)
    except Exception:
        out.errors.append(
            f"suppression {suppression_id}: invalid {field} '{value}' (expected YYYY-MM-DD)"
        )
        return None



def ensure_string(entry: Dict[str, Any], key: str, suppression_id: str, out: ValidationResult) -> str:
    value = entry.get(key)
    if not isinstance(value, str) or not value.strip():
        out.errors.append(f"suppression {suppression_id}: missing/empty '{key}'")
        return ""
    return value.strip()



def validate_registry(payload: Dict[str, Any]) -> ValidationResult:
    result = ValidationResult()
    suppressions = payload.get("suppressions")
    if not isinstance(suppressions, list):
        result.errors.append("registry must contain 'suppressions' array")
        return result

    today = date.today()
    soon_cutoff = today + timedelta(days=14)

    for idx, raw in enumerate(suppressions):
        if not isinstance(raw, dict):
            result.errors.append(f"suppression[{idx}] must be object")
            continue
        suppression_id = ensure_string(raw, "id", f"index-{idx}", result) or f"index-{idx}"

        status = raw.get("status", "active")
        if not isinstance(status, str) or status not in ALLOWED_STATUSES:
            result.errors.append(
                f"suppression {suppression_id}: status must be one of {sorted(ALLOWED_STATUSES)}"
            )
            continue

        if status == "resolved":
            result.resolved_count += 1
            continue

        result.active_count += 1

        for key in REQUIRED_KEYS:
            ensure_string(raw, key, suppression_id, result)

        introduced = raw.get("introducedOn")
        expires = raw.get("expiresOn")
        if not isinstance(introduced, str) or not isinstance(expires, str):
            continue

        introduced_date = parse_date(introduced, "introducedOn", suppression_id, result)
        expires_date = parse_date(expires, "expiresOn", suppression_id, result)
        if introduced_date is None or expires_date is None:
            continue
        if expires_date < introduced_date:
            result.errors.append(
                f"suppression {suppression_id}: expiresOn must be >= introducedOn"
            )
            continue
        if expires_date < today:
            result.errors.append(
                f"suppression {suppression_id}: suppression expired on {expires_date.isoformat()}"
            )
        elif expires_date <= soon_cutoff:
            result.expiring_soon += 1

    return result



def load_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"expected object JSON at {path}")
    return payload



def main() -> int:
    parser = argparse.ArgumentParser(description="Validate sanitizer suppression registry")
    parser.add_argument(
        "--fixture",
        default="tests/fixtures/sanitizers/phase9h_suppressions.json",
        help="Path to suppression registry fixture",
    )
    args = parser.parse_args()

    fixture_path = Path(args.fixture).resolve()
    payload = load_json(fixture_path)
    result = validate_registry(payload)

    if result.errors:
        print("sanitizer-suppressions: validation failed")
        for error in result.errors:
            print(f"- {error}")
        return 1

    print(
        "sanitizer-suppressions: ok "
        f"active={result.active_count} resolved={result.resolved_count} "
        f"expiring_soon={result.expiring_soon}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

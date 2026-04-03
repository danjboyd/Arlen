#!/usr/bin/env python3
"""Merge live Phase 28 OpenAPI output with checked-in x-arlen metadata."""

from __future__ import annotations

import argparse
import copy
import json
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


def normalize_type(schema: Dict[str, Any]) -> Any:
  raw = schema.get("type")
  if isinstance(raw, list):
      values = sorted(value for value in raw if value != "null")
      if len(values) == 1:
          return values[0]
      return values
  return raw


def normalize_schema(schema: Any) -> Dict[str, Any]:
    if not isinstance(schema, dict):
        return {}
    normalized: Dict[str, Any] = {}
    type_value = normalize_type(schema)
    if type_value not in (None, "", []):
        normalized["type"] = type_value
    if isinstance(schema.get("format"), str) and schema["format"]:
        normalized["format"] = schema["format"]
    if isinstance(schema.get("enum"), list):
        normalized["enum"] = list(schema["enum"])
    if isinstance(schema.get("required"), list):
        normalized["required"] = sorted(value for value in schema["required"] if isinstance(value, str))
    if isinstance(schema.get("items"), dict):
        normalized["items"] = normalize_schema(schema["items"])
    properties = schema.get("properties")
    if isinstance(properties, dict):
        normalized["properties"] = {
            key: normalize_schema(properties[key])
            for key in sorted(properties)
            if isinstance(key, str)
        }
    return normalized


def normalize_parameters(operation: Dict[str, Any]) -> List[Dict[str, Any]]:
    parameters = operation.get("parameters")
    if not isinstance(parameters, list):
        return []
    normalized = []
    for entry in parameters:
        if not isinstance(entry, dict):
            continue
        normalized.append(
            {
                "in": entry.get("in", ""),
                "name": entry.get("name", ""),
                "required": bool(entry.get("required", False)),
                "schema": normalize_schema(entry.get("schema", {})),
            }
        )
    return sorted(normalized, key=lambda item: (item["in"], item["name"]))


def normalize_operation(operation: Dict[str, Any]) -> Dict[str, Any]:
    responses = operation.get("responses")
    response_schema: Dict[str, Any] = {}
    if isinstance(responses, dict):
        response_200 = responses.get("200")
        if isinstance(response_200, dict):
            content = response_200.get("content")
            if isinstance(content, dict):
                json_content = content.get("application/json")
                if isinstance(json_content, dict):
                    response_schema = normalize_schema(json_content.get("schema", {}))

    request_schema: Dict[str, Any] = {}
    request_body = operation.get("requestBody")
    if isinstance(request_body, dict):
        content = request_body.get("content")
        if isinstance(content, dict):
            json_content = content.get("application/json")
            if isinstance(json_content, dict):
                request_schema = normalize_schema(json_content.get("schema", {}))

    tags = operation.get("tags")
    normalized_tags = sorted(tag for tag in tags if isinstance(tag, str)) if isinstance(tags, list) else []
    return {
        "operationId": operation.get("operationId", ""),
        "parameters": normalize_parameters(operation),
        "requestBody": request_schema,
        "response200": response_schema,
        "tags": normalized_tags,
    }


def normalize_spec(spec: Dict[str, Any]) -> Dict[str, Dict[str, Dict[str, Any]]]:
    normalized: Dict[str, Dict[str, Dict[str, Any]]] = {}
    paths = spec.get("paths")
    if not isinstance(paths, dict):
        return normalized
    for path_name in sorted(paths):
        path_item = paths[path_name]
        if not isinstance(path_item, dict):
            continue
        operations: Dict[str, Dict[str, Any]] = {}
        for method_name in sorted(path_item):
            method_item = path_item[method_name]
            if not isinstance(method_item, dict):
                continue
            operations[method_name] = normalize_operation(method_item)
        normalized[path_name] = operations
    return normalized


def compare_specs(expected: Dict[str, Any], actual: Dict[str, Any]) -> List[str]:
    mismatches: List[str] = []
    normalized_expected = normalize_spec(expected)
    normalized_actual = normalize_spec(actual)

    expected_paths = set(normalized_expected)
    actual_paths = set(normalized_actual)
    missing_paths = sorted(expected_paths - actual_paths)
    extra_paths = sorted(actual_paths - expected_paths)
    for path_name in missing_paths:
        mismatches.append(f"missing path {path_name}")
    for path_name in extra_paths:
        mismatches.append(f"unexpected path {path_name}")

    for path_name in sorted(expected_paths & actual_paths):
        expected_methods = normalized_expected[path_name]
        actual_methods = normalized_actual[path_name]
        missing_methods = sorted(set(expected_methods) - set(actual_methods))
        extra_methods = sorted(set(actual_methods) - set(expected_methods))
        for method_name in missing_methods:
            mismatches.append(f"missing operation {method_name.upper()} {path_name}")
        for method_name in extra_methods:
            mismatches.append(f"unexpected operation {method_name.upper()} {path_name}")
        for method_name in sorted(set(expected_methods) & set(actual_methods)):
            if expected_methods[method_name] != actual_methods[method_name]:
                mismatches.append(f"contract mismatch for {method_name.upper()} {path_name}")
    return mismatches


def main() -> int:
    parser = argparse.ArgumentParser(description="Merge and compare Phase 28 OpenAPI specs")
    parser.add_argument("--live-openapi", required=True)
    parser.add_argument("--metadata-openapi", required=True)
    parser.add_argument("--merged-output", required=True)
    parser.add_argument("--comparison-output", required=True)
    args = parser.parse_args()

    live_spec = load_json(Path(args.live_openapi).resolve())
    metadata_spec = load_json(Path(args.metadata_openapi).resolve())
    merged_spec = copy.deepcopy(live_spec)
    merged_spec["x-arlen"] = metadata_spec.get("x-arlen", {})
    write_json(Path(args.merged_output).resolve(), merged_spec)

    mismatches = compare_specs(metadata_spec, live_spec)
    status = "pass" if not mismatches else "fail"
    comparison_payload = {
        "status": status,
        "mismatches": mismatches,
    }
    write_json(Path(args.comparison_output).resolve(), comparison_payload)

    if mismatches:
        for mismatch in mismatches:
            print(f"phase28-openapi: {mismatch}")
        return 1
    print("phase28-openapi: live OpenAPI contract matches checked-in fixture")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Self-tests for Phase 37 acceptance assertion helpers."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools" / "ci"))

from phase37_acceptance_harness import assert_probe_response  # noqa: E402


BODY = '{"status":"ok","nested":{"value":7},"items":[{"name":"alpha"}],"text":"alpha beta gamma"}'
HEADERS = {
    "content-type": "application/json; charset=utf-8",
    "x-phase37-site": "assertion-selftest",
    "set-cookie": "phase37_session=ok; Path=/; HttpOnly",
}


PASSING_PROBE = {
    "expectedStatus": 200,
    "contains": ["alpha", "beta"],
    "notContains": "delta",
    "orderedContains": ["alpha", "beta", "gamma"],
    "bodyRegex": "\"status\"\\s*:\\s*\"ok\"",
    "headerPresent": ["content-type", "set-cookie"],
    "headerRegex": {"content-type": "application/json"},
    "jsonEquals": {"status": "ok"},
    "jsonPathEquals": {"nested.value": 7, "items.0.name": "alpha"},
    "cookieAttributes": {"phase37_session": ["Path=/", "HttpOnly"]},
}


NEGATIVE_PROBES = [
    {"expectedStatus": 201},
    {"expectedStatus": 200, "contains": "delta"},
    {"expectedStatus": 200, "notContains": "alpha"},
    {"expectedStatus": 200, "orderedContains": ["gamma", "alpha"]},
    {"expectedStatus": 200, "bodyRegex": "missing"},
    {"expectedStatus": 200, "headerPresent": "x-missing"},
    {"expectedStatus": 200, "headerRegex": {"content-type": "text/html"}},
    {"expectedStatus": 200, "jsonEquals": {"status": "bad"}},
    {"expectedStatus": 200, "jsonPathEquals": {"nested.value": 8}},
    {"expectedStatus": 200, "cookieAttributes": {"phase37_session": ["Secure"]}},
]


def main() -> int:
    passing = assert_probe_response("selftest", "pass", "fixture://pass", PASSING_PROBE, 200, BODY, HEADERS)
    if passing.status != "pass":
        print(f"phase37-assertions: passing probe failed: {passing.detail}")
        return 1
    for idx, probe in enumerate(NEGATIVE_PROBES):
        result = assert_probe_response("selftest", f"negative-{idx}", "fixture://negative", probe, 200, BODY, HEADERS)
        if result.status != "fail":
            print(f"phase37-assertions: negative probe {idx} unexpectedly passed")
            return 1
    print(f"phase37-assertions: {1 + len(NEGATIVE_PROBES)} assertion self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

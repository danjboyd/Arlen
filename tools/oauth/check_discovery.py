#!/usr/bin/env python3
"""Offline MCP discovery audit. No fetches, token issuance, or client acceptance claim."""
import argparse
import json
from pathlib import Path
from urllib.parse import urlsplit


def inspect(metadata, expected_issuer):
    def https(value):
        if not isinstance(value, str):
            return False
        try:
            parsed = urlsplit(value)
        except ValueError:
            return False
        return parsed.scheme == "https" and bool(parsed.hostname) and not parsed.username and not parsed.password
    def includes(field, value):
        entries = metadata.get(field)
        return isinstance(entries, list) and value in entries
    return {
        "issuer_matches": metadata.get("issuer") == expected_issuer,
        "pkce_s256_advertised": includes("code_challenge_methods_supported", "S256"),
        "authorization_endpoint_https": https(metadata.get("authorization_endpoint")),
        "token_endpoint_https": https(metadata.get("token_endpoint")),
        "authorization_code_advertised": includes("response_types_supported", "code"),
    }


def self_test():
    issuer = "https://issuer.example.test/tenant"
    metadata = {"issuer": issuer, "authorization_endpoint": issuer + "/authorize",
                "token_endpoint": issuer + "/token", "response_types_supported": ["code"],
                "code_challenge_methods_supported": ["S256"]}
    assert all(inspect(metadata, issuer).values())
    for field, value, failure in [
        ("code_challenge_methods_supported", None, "pkce_s256_advertised"),
        ("code_challenge_methods_supported", ["plain"], "pkce_s256_advertised"),
        ("code_challenge_methods_supported", "S256", "pkce_s256_advertised"),
        ("issuer", "https://adapter.example.test", "issuer_matches"),
        ("authorization_endpoint", "http://issuer.example.test/authorize", "authorization_endpoint_https"),
        ("token_endpoint", "http://issuer.example.test/token", "token_endpoint_https"),
        ("response_types_supported", ["token"], "authorization_code_advertised"),
    ]:
        altered = dict(metadata, **{field: value})
        assert not inspect(altered, issuer)[failure]
    print("Eight synthetic discovery cases passed; no actual client or tenant flow tested.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--metadata", type=Path)
    parser.add_argument("--expected-issuer")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if not args.metadata or not args.expected_issuer:
        parser.error("provide --metadata and --expected-issuer, or --self-test")
    with args.metadata.open("rb") as stream:
        raw = stream.read(262145)
    if len(raw) > 262144:
        parser.error("metadata exceeds 256 KiB")
    metadata = json.loads(raw)
    if not isinstance(metadata, dict):
        parser.error("metadata must be an object")
    result = inspect(metadata, args.expected_issuer)
    print(json.dumps({"checks": result, "evidence": "metadata-only; live acceptance pending"}, sort_keys=True))
    return 0 if all(result.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())

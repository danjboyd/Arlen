# Open Issues

## ISSUE-001: Worker crash under normal HTTP traffic (`malloc_consolidate` / intermittent `502`)

- Status: `resolved`
- Priority: `critical`
- GitHub: https://github.com/danjboyd/Arlen/issues/1
- Last updated: `2026-02-25`

### Summary

Under normal API traffic behind nginx + `propane` (with `propane accessories` worker count > 1), workers intermittently abort with:

- `malloc_consolidate(): unaligned fastbin chunk detected`
- worker exit status `134` (and occasional segfaults observed in process lifecycle)

Externally this presents as intermittent or sustained `502 Bad Gateway` from nginx (`upstream prematurely closed connection`).

### Known-good / known-bad

- Known-good: `3876cd8481ba74b5812e52011b3bd9bf3bb80b0b`
- Known-bad: `08ea39abccd0` (still reproducible after timestamp formatter hardening)

### Repro context (reported)

- Host: `iep-softwaredev`
- OS: Debian 13 (trixie)
- Kernel: `6.12.73+deb13-amd64`
- Compiler: clang 19.1.7
- Runtime: nginx -> `propane` -> Arlen workers
- Traffic examples:
  - `/v1/states/OK/dockets/CD_2025-002412/documents/{document_id}/pdf`
  - `/v1/states/OK/dockets/CD_2025-002412/documents`

### Resolution summary

- Fix commit: `0920889` (`fix(http): stabilize serialized dispatch connection lifecycle`)
- Final fix behavior in serialized mode:
  - force one request per HTTP connection (`Connection: close`)
  - disable detached per-connection background thread handling
  - preserve explicit serialized behavior as opt-in (`requestDispatchMode=serialized`)
- Regression coverage:
  - `HTTPIntegrationTests::testProductionSerializedDispatchClosesHTTPConnections`
  - existing production serialization/concurrent-override tests remained passing

### Verification evidence

- Live consumer validation (StateCompulsoryPoolingAPI, production-like traffic on `iep-softwaredev`) confirmed issue resolved after upgrading to `0920889`.
- Arlen CI/local validation remained green after patch:
  - unit suite
  - integration suite
  - postgres integration suite

### Post-resolution watchpoints

1. Keep serialized-mode connection lifecycle deterministic when explicitly configured.
2. Require integration coverage for any future changes to HTTP connection persistence + worker dispatch interaction.
3. Re-run ASAN/UBSAN + endpoint traffic smoke during future runtime concurrency refactors.
4. Keep `tools/ci/run_runtime_concurrency_gate.sh` in pre-merge validation for HTTP/runtime lifecycle changes.
5. Track/update concurrency hardening baselines in `docs/CONCURRENCY_AUDIT_2026-02-25.md`.

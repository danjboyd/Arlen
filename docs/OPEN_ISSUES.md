# Open Issues

## ISSUE-001: Worker crash under normal HTTP traffic (`malloc_consolidate` / intermittent `502`)

- Status: `open`
- Priority: `critical`
- GitHub: https://github.com/danjboyd/Arlen/issues/1
- Last updated: `2026-02-24`

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

### Notes from latest triage

- Timestamp formatting was hardened in `08ea39a` to remove shared `NSDateFormatter` concurrency risk.
- Unit + integration + local ASAN/UBSAN stress remained green in local environment.
- Production-like environment still reproduces crash, so root cause is not fully resolved.
- Most likely class remains a concurrency-exposed memory/lifecycle defect introduced after `3876cd8`.

### Next diagnostics to run (next session)

1. Rebuild the real app + Arlen with ASAN/UBSAN and reproduce on failing endpoints.
2. Capture first crashing stack with core dumps enabled (`coredumpctl gdb`) for `status=134/139`.
3. Run same workload with single worker and serialized request dispatch to isolate concurrency contribution.
4. If needed, bisect post-`3876cd8` commits in runtime/data paths with the real app workload.

# Known Risk Register

This register tracks active release risks that are accepted temporarily with explicit ownership and target dates.

Source of truth fixture:

- `tests/fixtures/release/phase9j_known_risks.json`

Last updated: 2026-03-24

## Active Risks

| ID | Title | Severity | Owner | Target Date | Notes |
| --- | --- | --- | --- | --- | --- |
| `phase9j-risk-tsan-nonblocking` | TSAN lane remains non-blocking while false-positive budget is stabilized | medium | runtime-core | 2026-03-31 | Nightly TSAN runs on 2026-03-23 and 2026-03-24 still reproduced the GNUstep `libobjc` lock-order-inversion signature during TSAN-instrumented `eocc` transpilation; keep TSAN non-blocking until that runtime/toolchain issue is resolved and two consecutive deterministic pass cycles are observed. |

## Mitigated Risks

| ID | Title | Severity | Owner | Target Date | Notes |
| --- | --- | --- | --- | --- | --- |
| `phase9j-risk-benchmark-ladder` | Middleware-heavy benchmark concurrency ladder remains constrained to 1,4 | low | performance-core | 2026-03-21 | Deferred benchmark roadmap removes this from active release-risk scope; higher-concurrency middleware-heavy validation now lives in the parked comparative benchmark follow-on. |
| `phase9j-risk-sanitizer-suppression-governance` | Suppression registry maintenance policy maturity | low | runtime-core | 2026-02-25 | Phase 9H introduced suppression lifecycle policy + validator. |

## Update Contract

When a risk is added or updated:

1. Update `tests/fixtures/release/phase9j_known_risks.json`
2. Update this document to match
3. Regenerate certification artifacts with `make ci-release-certification`
4. Link this register from release notes

# Known Risk Register

This register tracks active release risks that are accepted temporarily with explicit ownership and target dates.

Source of truth fixture:

- `tests/fixtures/release/phase9j_known_risks.json`

Last updated: 2026-05-11

## Active Risks

| ID | Title | Severity | Owner | Target Date | Notes |
| --- | --- | --- | --- | --- | --- |
| `phase9j-risk-tsan-nonblocking` | TSAN lane remains non-blocking while false-positive budget is stabilized | medium | runtime-core | 2026-06-30 | A fresh local `phase5e` TSAN experimental run now passes after unsanitized `eocc` bootstrap, GNUstep suppression wiring, and TSAN-only quarantine of nested CLI/script assertion tests, but the GNUstep `libobjc`/base lock-order-inversion and monitor-race signatures remain unresolved in CI governance as of 2026-04-15; keep TSAN non-blocking until that stack is resolved and two consecutive deterministic pass cycles are observed. |

## Mitigated Risks

| ID | Title | Severity | Owner | Target Date | Notes |
| --- | --- | --- | --- | --- | --- |
| `phase9j-risk-benchmark-ladder` | Middleware-heavy benchmark concurrency ladder remains constrained to 1,4 | low | performance-core | 2026-03-21 | Deferred benchmark roadmap removes this from active release-risk scope; higher-concurrency middleware-heavy validation now lives in the parked comparative benchmark follow-on. |
| `phase9j-risk-sanitizer-suppression-governance` | Suppression registry maintenance policy maturity | low | runtime-core | 2026-02-25 | Suppression lifecycle policy + validator introduced. |

## Update Contract

When a risk is added or updated:

1. Update `tests/fixtures/release/phase9j_known_risks.json`
2. Update this document to match
3. Regenerate certification artifacts with `make ci-release-certification`
4. Link this register from release notes

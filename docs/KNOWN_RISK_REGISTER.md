# Known Risk Register

This register tracks active release risks that are accepted temporarily with explicit ownership and target dates.

Source of truth fixture:

- `tests/fixtures/release/phase9j_known_risks.json`

Last updated: 2026-09-21

## Active Risks

| ID | Title | Severity | Owner | Target Date | Notes |
| --- | --- | --- | --- | --- | --- |
| `phase9j-risk-tsan-nonblocking` | TSAN runtime findings remain unresolved after coverage repair | medium | runtime-core | 2026-12-31 | Library-wide suppressions demonstrably hid a deliberate application race through Foundation. On 2026-09-21 all 14 TSAN-only test returns were removed, registry initialization lock ordering was corrected, and suppressions narrowed to three Objective-C runtime function patterns. GNUstep queue mutex-lifetime/lock-order and CLI findings are now visible; the full TSAN lane is not clean. Retained raw reproducers, positive-control race detection, explicit unavailable status, and coverage summaries prevent a misleading green result. Keep non-blocking pending runtime classification/fixes and two consecutive clean runs of the new configuration; see docs/internal/TSAN_RELIABILITY_2026-09-21.md. |

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

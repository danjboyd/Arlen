# Known Risk Register

This register tracks active release risks that are accepted temporarily with explicit ownership and target dates.

Source of truth fixture:

- `tests/fixtures/release/phase9j_known_risks.json`

Last updated: 2026-02-25

## Active Risks

| ID | Title | Severity | Owner | Target Date | Notes |
| --- | --- | --- | --- | --- | --- |
| `phase9j-risk-tsan-nonblocking` | TSAN lane remains non-blocking while false-positive budget is stabilized | medium | runtime-core | 2026-03-31 | Promote TSAN to blocking after two consecutive deterministic pass cycles. |
| `phase9j-risk-benchmark-ladder` | Middleware-heavy benchmark concurrency ladder remains constrained to 1,4 | low | performance-core | 2026-03-15 | Phase E benchmark follow-on validates higher concurrency confidence. |

## Mitigated Risks

| ID | Title | Severity | Owner | Target Date | Notes |
| --- | --- | --- | --- | --- | --- |
| `phase9j-risk-sanitizer-suppression-governance` | Suppression registry maintenance policy maturity | low | runtime-core | 2026-02-25 | Phase 9H introduced suppression lifecycle policy + validator. |

## Update Contract

When a risk is added or updated:

1. Update `tests/fixtures/release/phase9j_known_risks.json`
2. Update this document to match
3. Regenerate certification artifacts with `make ci-release-certification`
4. Link this register from release notes

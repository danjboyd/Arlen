# Known Risk Register

This register tracks active release risks that are accepted temporarily with explicit ownership and target dates. The v0.3.1 release is held on the active TSan finding until its closure criteria pass; the historical risk identifier does not waive that requirement.

Source of truth fixture:

- `tests/fixtures/release/phase9j_known_risks.json`

Last updated: 2026-10-21

## Active Risks

| ID | Title | Severity | Owner | Target Date | Notes |
| --- | --- | --- | --- | --- | --- |
| `phase9j-risk-tsan-nonblocking` | TSAN runtime findings remain unresolved after coverage repair | medium | runtime-core | 2026-12-31 | Reviewed 2026-10-21: the v0.3.1 shared clang TSan harness detects the deliberate application race, and isolated normal/instrumented dependency recipes now use the shipped GNUstep Base d898f703 pin. Six affected Base groups passed 2359 assertions with 21 upstream dashed hopes and no failures; libobjc passed 200 tests and libdispatch previously passed 22. Full diagnostic unit runs still expose dependency races, most recently dispatch group publication; zero clean full runs are recorded. The historical risk ID and 2026-12-31 runtime-core target remain unchanged. Although the nightly job remains informational in configured branch protection, v0.3.1 release is held until confirmed findings are fixed and two consecutive full unit plus HTTP-concurrency runs pass with a detecting application canary, retained artifacts, and no new broad suppressions or test exclusions. Existing function-scoped exceptions still require evidence review; see docs/internal/TSAN_RELIABILITY_2026-09-21.md. |

## Mitigated Risks

| ID | Title | Severity | Owner | Target Date | Notes |
| --- | --- | --- | --- | --- | --- |
| `phase9j-risk-benchmark-ladder` | Middleware-heavy benchmark concurrency ladder remains constrained to 1,4 | low | performance-core | 2026-03-21 | Reviewed 2026-10-21 against docs/internal/COMPETITIVE_BENCHMARK_ROADMAP.md: the archived Phase D middleware-heavy ladder is historical evidence; comparative optimization/reporting belongs to the sibling ArlenBenchmarking program. No new performance claim or expanded validation is made here. This remains mitigated and outside the active v0.3.1 release-risk scope. |
| `phase9j-risk-sanitizer-suppression-governance` | Suppression registry maintenance policy maturity | low | runtime-core | 2026-02-25 | Reviewed 2026-10-21 against docs/internal/SANITIZER_SUPPRESSION_POLICY.md, the registry, and its validator. check_sanitizer_suppressions.py passes with two active function-scoped registry entries, two retired entries, and no expiry approaching within 14 days. Registered patterns still match the suppression file and retain owners, expiry dates and evidence. No suppression or expiry was changed. Governance remains mitigated; unresolved runtime findings remain active under phase9j-risk-tsan-nonblocking, and successful registry validation is not a clean TSan run. |

## Update Contract

When a risk is added or updated:

1. Update `tests/fixtures/release/phase9j_known_risks.json`
2. Update this document to match
3. Regenerate certification artifacts with `make ci-release-certification`
4. Link this register from release notes

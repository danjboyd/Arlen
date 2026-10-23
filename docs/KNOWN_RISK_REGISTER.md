# Known Risk Register

This register tracks active release risks that are accepted temporarily with explicit ownership and target dates. Publishing v0.3.1 requires the qualification criteria below; the historical risk identifier also tracks continuing patched-runtime maintenance and does not waive those criteria.

Source of truth fixture:

- `tests/fixtures/release/phase9j_known_risks.json`

Last updated: 2026-10-22

## Active Risks

| ID | Title | Severity | Owner | Target Date | Notes |
| --- | --- | --- | --- | --- | --- |
| `phase9j-risk-tsan-nonblocking` | Patched GNUstep runtime qualification and maintenance | medium | runtime-core | 2026-12-31 | Reviewed 2026-10-22: corrections for the observed GNUstep Base, libobjc2 and libdispatch findings are integrated with pinned source revisions and checked patches. The new normal-runtime inputs restore production O2 defaults while retaining GNUstep debug filtering; their fresh prefix requires independent functional, performance, ICU and supported-native-target qualification. The 2026-10-21 review recorded dependency races and zero clean full TSan runs; those are historical observations that motivated the corrections. Prior component checks recorded 2359 Base assertions with 21 upstream dashed hopes and no failures, 200 libobjc tests and 22 libdispatch tests; these bounded checks do not replace full acceptance. Although the configured nightly check remains informational in branch protection, publishing v0.3.1 remains held until two consecutive full unit plus HTTP-concurrency runs pass on the frozen candidate with a detecting application canary, retained artifacts, and no new broad suppressions or test exclusions. Existing function-scoped exceptions still require evidence review under docs/internal/TSAN_RELIABILITY_2026-09-21.md. The historical risk ID, runtime-core owner and 2026-12-31 target remain to track pinned-patch maintenance and continuing runtime validation. Active status does not authorize releasing an unresolved confirmed finding or bypassing any qualification gate; actual acceptance is recorded in the release evidence. |

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

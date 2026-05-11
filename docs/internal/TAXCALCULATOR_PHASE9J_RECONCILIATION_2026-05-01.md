# TaxCalculator Phase 9J Reconciliation

Date: `2026-05-01`

This note records the upstream Arlen assessment of the TaxCalculator report that
`make ci-release-certification` failed during Arlen's unit-test gate while
deploying TaxCalculator commit `7986335`.

Ownership rule:

- Arlen records upstream status only.
- `TaxCalculator` keeps app-level closure authority.
- Downstream revalidation still belongs to `TaxCalculator` after it updates its
  vendored Arlen checkout.

## Current Upstream Assessment

| TaxCalculator report | Upstream status | Evidence |
| --- | --- | --- |
| Phase 9J certification failed in `BuildPolicyTests.testArlenBuildJSONCapturesLargeChildOutputWithoutPipeDeadlock_ARLEN_BUG_027` with empty redirected JSON output, then passed on focused rerun | fixed upstream; awaiting downstream revalidation | `docs/OPEN_ISSUES.md` (`ARLEN-BUG-028`), `GNUmakefile`, `tests/unit/BuildPolicyTests.m`, `docs/PHASE9J_RELEASE_CERTIFICATION.md`, `docs/TESTING_WORKFLOW.md` |

## Notes

### `ARLEN-BUG-028`: Clean Phase 9J Unit Test Dependency Gap

- Upstream accepted the failure class from the downstream report.
- Root cause:
  - Phase 9J starts with `make clean`.
  - The Phase 5E quality gate then begins with `make test-unit`.
  - `BuildPolicyTests` contains a regression that shells out to `build/arlen`.
  - The unit-test bundle did not declare `build/arlen` as a prerequisite, so a
    clean focused path could reach the test before the CLI existed.
- Current upstream behavior:
  - `$(UNIT_TEST_BIN)` depends on `$(ARLEN_TOOL)`.
  - `make test-unit` and `make test-unit-filter` rebuild `build/arlen` after
    `make clean` before running the bundle.
  - The ARLEN-BUG-027 regression now includes combined shell output, redirected
    JSON byte count, and command text in early-exit assertions.
- Regression coverage:
  - `BuildPolicyTests::testArlenBuildJSONCapturesLargeChildOutputWithoutPipeDeadlock_ARLEN_BUG_027`

Downstream revalidation should update TaxCalculator's vendored Arlen checkout
and rerun:

```bash
cd /home/danboyd/git/TaxCalculator/vendor/arlen
make ci-release-certification
```

The Phase 9J manifest requirement remains intentional. Arlen should fix release
certification flakes in the upstream gate rather than bypassing production
packaging certification.

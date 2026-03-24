# StateCompulsoryPoolingAPI Report Reconciliation

Date: `2026-03-24`

This note records the upstream Arlen assessment of the `boomhauer --prepare-only`
report logged in `/opt/StateCompulsoryPoolingAPI/docs/ARLEN_FEEDBACK_LOG.md`
on `iep-softwaredev`.

Ownership rule:

- Arlen records upstream status only.
- `StateCompulsoryPoolingAPI` keeps app-level closure authority.
- Status below should be read as the upstream status/evidence trail. Downstream
  revalidation still belongs to `StateCompulsoryPoolingAPI`.

## Current Upstream Assessment

| StateCompulsoryPoolingAPI report | Upstream status | Evidence |
| --- | --- | --- |
| `boomhauer --prepare-only` reports success on build failure | fixed in current workspace; awaiting downstream revalidation | `bin/boomhauer`, `bin/propane`, `bin/jobs-worker`, `tests/integration/HTTPIntegrationTests.m`, `docs/CLI_REFERENCE.md`, `docs/GETTING_STARTED.md` |

## Notes

- Upstream reproduced the failure on `2026-03-24` by forcing the app-root
  framework `make` step to fail under `bin/boomhauer --prepare-only`.
- Before the fix, `.boomhauer/last_build_error.meta` correctly recorded
  `exit_code=42`, but `boomhauer --prepare-only` still exited `0`.
- Root cause:
  - app-root non-watch build helpers used negated shell conditionals such as
    `if ! ...; then local status=$?`, which captured the status of the negated
    conditional rather than the underlying failing build step
  - `run_once` then flattened the failure again by exiting `1` instead of the
    original build status
- Current upstream behavior:
  - `boomhauer --prepare-only` and `--print-routes` now exit with the
    underlying non-zero build status after surfacing
    `.boomhauer/last_build_error.log`
  - `propane` and `jobs-worker` now stop startup on failed prepare steps and
    point operators at `.boomhauer/last_build_error.log` instead of reusing an
    existing app binary
- Regression coverage:
  - `HTTPIntegrationTests::testBoomhauerPrepareOnlyPropagatesUnderlyingBuildFailureExitCode`

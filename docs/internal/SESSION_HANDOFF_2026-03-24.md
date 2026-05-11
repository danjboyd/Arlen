# Session Handoff (2026-03-24 EOD)

This note captures where work stopped at end of day so the next session can
resume from a concrete state instead of chat history.

## Current Revisions

- Arlen:
  - repo: `/home/danboyd/git/Arlen`
  - branch: `main`
  - HEAD: `3037bbc` (`fix(ci): stabilize experimental tsan lane`)
  - worktree: clean
- Latest pushed docs companion commit on the same branch:
  - `304f1f5` (`docs(eoc): cover current tooling and runtime behavior`)

## Verified State

- The experimental local TSAN lane was stabilized enough to complete end to
  end without promoting TSAN to blocking:
  - `tools/ci/run_phase5e_tsan_experimental.sh` now bootstraps `eocc`
    unsanitized, stages `arlen` with the instrumented tool builds, retains its
    artifacts outside the cleaned build tree, and preserves the first failing
    non-zero exit code instead of falling through to the runtime probe
  - TSAN-hot-path `@synchronized` usage was removed from:
    - `src/Arlen/HTTP/ALNResponse.m`
    - `src/Arlen/Data/ALNPg.m`
    - `tests/unit/PgTests.m`
  - repo-managed TSAN suppression inventory is now explicit in:
    - `tests/fixtures/sanitizers/phase9h_tsan.supp`
    - `tests/fixtures/sanitizers/phase9h_suppressions.json`
  - nested shell/tooling assertions that spawn instrumented child tools are
    kept out of the active TSAN runtime in:
    - `tests/unit/BuildPolicyTests.m`
    - `tests/unit/Phase13ETests.m`
- Verified locally before stand-down:
  - `bash ./tools/ci/run_phase5e_tsan_experimental.sh`
  - `make test-unit-filter TEST=BuildPolicyTests/testTSANScriptBootstrapsEOCCUnsanitizedBeforeInstrumentedBuilds`
  - `python3 ./tools/ci/check_sanitizer_suppressions.py`
  - `make ci-release-certification`
  - `make ci-docs`

## GitHub CI State At Stand-Down

Commit under test: `3037bbc`

Status checked at: `2026-03-24T22:16:51Z`

- `phase3c-quality`
  - run `23514203424`
  - status: `success`
  - run URL: `https://github.com/danjboyd/Arlen/actions/runs/23514203424`
- `phase5e-quality`
  - run `23514203422`
  - status at stand-down: `in_progress`
  - run URL: `https://github.com/danjboyd/Arlen/actions/runs/23514203422`
- `docs-quality`
  - run `23514203423`
  - status at stand-down: `queued`
  - run URL: `https://github.com/danjboyd/Arlen/actions/runs/23514203423`
- `phase5e-sanitizers`
  - run `23514203431`
  - status at stand-down: `queued`
  - run URL: `https://github.com/danjboyd/Arlen/actions/runs/23514203431`

As of stand-down, the new push is on GitHub and the first lane
(`phase3c-quality`) is already green. The remaining quality/docs/sanitizer
workflows still need to settle on the pushed head.

## Where Work Stopped

The TSAN cleanup is committed and pushed, but TSAN promotion is still not
complete.

The remaining blocker is no longer the local `phase5e` helper path. The open
runtime/toolchain issue is that standalone instrumented `arlen` still emits
GNUstep `libobjc` lock-order-inversion noise on stderr, which contaminates
stderr-sensitive nested CLI/script assertions even after the local lane itself
was stabilized.

This is tracked as:

- `docs/KNOWN_RISK_REGISTER.md`
  - risk id: `phase9j-risk-tsan-nonblocking`
- `docs/STATUS.md`

## Resume Checklist

1. Check the final results of the pushed GitHub runs on `3037bbc`:
   - `phase5e-quality` run `23514203422`
   - `docs-quality` run `23514203423`
   - `phase5e-sanitizers` run `23514203431`
2. If `phase5e-sanitizers` passes on GitHub, record that the local TSAN
   stabilization also holds on the actual runner path.
3. If `phase5e-sanitizers` fails, inspect that log first before making new
   TSAN/runtime changes.
4. After the pushed runs settle, return to the remaining TSAN promotion item:
   - investigate the GNUstep `libobjc` lock-order-inversion output emitted by
     standalone instrumented `arlen`
   - decide whether the next move is:
     - deeper runtime/toolchain investigation,
     - narrower TSAN quarantine of nested CLI/script assertions, or
     - suppression retirement only after two deterministic pass cycles
5. Keep TSAN non-blocking until the runtime/toolchain signature is resolved and
   two consecutive deterministic pass cycles are observed.

## Open Items

- GitHub runs for `3037bbc` are not fully settled yet.
- TSAN remains non-blocking while the GNUstep runtime/toolchain false-positive
  budget is stabilized.
- Standalone instrumented `arlen` still emits GNUstep `libobjc`
  lock-order-inversion warnings even though the local `phase5e` TSAN helper now
  completes successfully.

## Notes For Tomorrow

- Start from this handoff note rather than the full chat history.
- The current branch is clean and already pushed.
- The highest-signal first check tomorrow is the GitHub status of
  `phase5e-sanitizers` run `23514203431` on commit `3037bbc`.

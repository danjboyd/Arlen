# Session Handoff (2026-03-27)

This handoff records the current Phase 22 checkpoint so the next session can
resume cleanly without re-auditing the docs work.

## Current State

- Phase 22 is in progress.
- `22A-22F` are drafted/implemented in the working tree.
- `22G` is partially complete:
  - docs-quality checks were extended and passed
  - final long-form integration verification is still pending
  - summary surfaces still need the final `complete` closeout pass after
    verification

## Completed In This Checkpoint

- Reworked newcomer entry surfaces:
  - `README.md`
  - `docs/README.md`
- Rewrote the main onboarding path around one recommended generator-first flow:
  - `docs/GETTING_STARTED.md`
  - `docs/GETTING_STARTED_QUICKSTART.md`
  - `docs/FIRST_APP_GUIDE.md`
  - `docs/GETTING_STARTED_TRACKS.md`
- Added missing user-facing guides:
  - `docs/APP_AUTHORING_GUIDE.md`
  - `docs/CONFIGURATION_REFERENCE.md`
  - `docs/LITE_MODE_GUIDE.md`
  - `docs/PLUGIN_SERVICE_GUIDE.md`
  - `docs/FRONTEND_STARTERS.md`
- Expanded module docs into a connected lifecycle guide:
  - `docs/MODULES.md`
- Tightened docs/code parity:
  - top-level CLI help now exposes `module ... eject`
  - API reference generation no longer duplicates `ALNPlugin`
  - `docs/TOOLCHAIN_MATRIX.md` now documents the extra
    `bin/arlen-doctor` matrix-presence check
- Added docs navigation quality enforcement:
  - `tools/ci/check_docs_navigation.py`
  - `tools/ci/run_docs_quality.sh`
  - `docs/DOCUMENTATION_POLICY.md`

## Bug Found During The Docs Pass

The docs rewrite relied on the generator-first endpoint workflow and uncovered a
real product regression:

- `arlen generate endpoint ...` was wiring routes into `src/main.m` and
  `app_lite.m` without inserting the matching controller import
- fixed in `tools/arlen.m`
- regression coverage added in
  `tests/integration/DeploymentIntegrationTests.m`

## Verification Completed

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make arlen build-tests
bash tools/ci/run_docs_quality.sh
```

Both passed during this checkpoint.

## Verification Still Pending

Run the full integration suite with the live PostgreSQL and MSSQL test
backends:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
source /home/danboyd/.config/arlen/mssql-test.env
export ARLEN_PG_TEST_DSN='postgresql:///postgres'
make test-integration
```

If that passes, Phase 22 can be closed out.

## Next Session

1. Finish or rerun `make test-integration`.
2. If green, update:
   - `docs/PHASE22_ROADMAP.md`
   - `README.md`
   - `docs/README.md`
   - `docs/STATUS.md`
   so Phase 22 reads as complete instead of in progress.
3. Regenerate docs if needed and run:
   - `git diff --check`
4. Commit the closeout with a Phase 22 execution message.

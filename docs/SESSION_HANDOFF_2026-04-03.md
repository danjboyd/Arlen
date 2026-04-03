# Session Handoff (2026-04-03)

This note records the Phase 28 closeout checkpoint after executing `28I-28L`.

## Current State

- Phase 28 is complete.
- `28A-28L` are now landed in the worktree and verified locally.
- The repo-native Phase 28 verification entrypoints are:
  - `make phase28-ts-generated`
  - `make phase28-ts-unit`
  - `make phase28-ts-integration`
  - `make phase28-react-reference`
  - `make phase28-confidence`

## Completed In This Checkpoint

- Added the dedicated `tests/typescript/` harness plus the checked-in
  `tests/fixtures/phase28/typescript_snapshot.json` characterization artifact.
- Added the live `examples/phase28_reference` backend used by the TypeScript
  integration and React reference lanes.
- Added the Phase 28 CI/common tooling under `tools/ci/` plus GNUmake targets
  for generated, unit, integration, React reference, and aggregate confidence
  verification.
- Hardened the generator/runtime seam:
  - fixed `generate:arlen` workspace scripts so `ARLEN_PHASE28_OPENAPI_INPUT`
    overrides work correctly
  - updated generated client output for strict
    `exactOptionalPropertyTypes` compatibility
  - kept resource/module metadata keyed and type-safe in `meta.ts`
  - taught the core route/OpenAPI path to preserve schema `format` hints such
    as `uuid`, `email`, and `date-time`
  - updated the live Node integration test to keep cookies across CSRF-
    protected mutation flows
  - updated the React reference app so it hides default-backed form fields and
    narrows model-level drafts into API request bodies
- Closed out the docs/status/API-reference set for the shipped Phase 28 path.

## Verification Completed

```bash
source tools/source_gnustep_env.sh
make phase28-ts-generated
make phase28-ts-unit
make phase28-ts-integration
make phase28-react-reference
make test-unit-filter TEST=ApplicationTests/testRouteSchemasSupportFormatHintsAndExposeThemInOpenAPI
make phase28-confidence
git diff --check
```

Notes:

- stock Debian `xctest` still ignored the focused selector and ran the full
  unit bundle for the `ApplicationTests` rerun; the bundle still passed and
  the new format-hint regression passed in the stream
- `phase28-confidence` now owns the aggregate generated/unit/integration/React
  lanes plus `make docs-api` and `bash tools/ci/run_docs_quality.sh`

## Next Session

1. Commit and push the Phase 28 closeout when ready.
2. Treat future work in this area as post-Phase-28 follow-up rather than
   unfinished roadmap work.

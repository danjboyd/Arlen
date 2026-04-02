# Session Handoff (2026-04-02)

This note records the current Phase 28 checkpoint so the next session can
resume from a concrete repo state rather than chat history.

## Current State

- Phase 28 is in progress.
- `28A-28H` are now landed.
- Remaining Phase 28 subphases:
  - `28I`: dedicated TypeScript unit-test architecture and shared support
  - `28J`: live integration and React reference coverage
  - `28K`: drift/perf/compatibility artifacts and confidence hardening
  - `28L`: docs, API reference, and release closeout

## Current Revisions

- repo: `/home/danboyd/git/Arlen`
- branch: `main`
- latest implementation commit before this handoff note:
  - `e51457e` (`phase28: ship validators query meta and example`)
- previously pushed same-day supporting commits:
  - `6aee5ba` (`fix(dataverse): handle polymorphic lookup codegen`)
  - `2c87a51` (`fix(dataverse): split non-selectable lookup helpers`)
- worktree intent:
  - tracked files are expected to be clean after this handoff commit
  - local untracked `.codex` remains unrelated and should be left alone

## Completed In This Checkpoint

- Shipped Phase `28E-28H` on top of the earlier `28A-28D` generator baseline:
  - framework-neutral `validators.ts` generation with model and request
    validation schemas plus form-field adapters
  - explicit `query.ts` contracts for relation metadata, allowed includes,
    selectable/sortable/filterable resource fields, and query-param builders
  - explicit `meta.ts` registries for resources, admin metadata, modules, and
    workspace hints from additive OpenAPI `x-arlen` metadata
  - stronger package scaffolding with explicit exports, `types`, README
    guidance, and generated package/manifest metadata suitable for app-local,
    monorepo, and internal-package workflows
- Added the checked-in React/Vite reference workspace:
  - `examples/phase28_react_reference`
  - demonstrates consumption of generated models, validators, query/resource
    metadata, client helpers, and optional React/TanStack helpers
- Tightened docs and status surfaces:
  - `README.md`
  - `docs/README.md`
  - `docs/STATUS.md`
  - `docs/CLI_REFERENCE.md`
  - `docs/ARLEN_ORM.md`
  - `docs/GETTING_STARTED_API_FIRST.md`
  - `docs/GETTING_STARTED.md`
  - `docs/PHASE28_ROADMAP.md`

## Bug Found During Validation

The new React reference workspace typecheck uncovered a real Phase 28 generator
bug:

- generated validator form-adapter flags were emitting boxed numeric `1`/`0`
  values instead of literal `true`/`false`
- fixed in `src/Arlen/ORM/ALNORMTypeScriptCodegen.m`
- regression coverage added in `tests/unit/ORMTypeScriptCodegenTests.m`

The same workspace validation also exposed an adoption ergonomics issue:

- the example had been calling `../../build/arlen` directly
- switched it to the repo-native `../../bin/arlen` entrypoint so generation
  works from a clean checkout without assuming a pre-existing build artifact

## Verification Completed

```bash
source tools/source_gnustep_env.sh
make test-unit-filter TEST=ORMTypeScriptCodegenTests
bash tools/ci/run_docs_quality.sh

cd examples/phase28_react_reference
npm install --package-lock=false
npm run generate:arlen
npm run typecheck
```

All of the above passed in this checkpoint.

## Next Session

1. Execute `28I` by adding a dedicated TypeScript-side verification layer:
   - snapshot/manifest stability tests
   - compile-only/package-shape checks
   - mocked `fetch` client tests
   - React hook/query-key tests
   - validator/query/meta parity checks
2. Execute `28J` by wiring the checked-in React reference workspace into a
   live Arlen-backed integration path instead of fixture-only generation.
3. Execute `28K` by adding drift/perf/compatibility artifacts and a Phase 28
   confidence lane.
4. Use `28L` to close out docs/API reference/status surfaces only after the
   new verification and integration lanes are green.

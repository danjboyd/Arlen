# Evening Handoff: 2026-03-13

Context: paused before more `Phase 19` build-graph work to address downstream
bug reports from `MusicianApp` and `Structurizer`.

## Completed in this slice

- Fixed shorthand nested object inference in
  `src/Arlen/Core/ALNSchemaContract.m`.
  - Root cause: shorthand object descriptors inside arrays were being inferred
    as `string` because `ALNSchemaType(...)` only treated explicit
    `properties` dictionaries as objects.
  - Effect: nested JSON objects in validated body arrays could be coerced via
    `description` and surface as property-list-style strings.
- Added regression coverage in `tests/unit/SchemaContractTests.m`.
  - New coverage: nested body array items remain dictionaries through
    `ALNSchemaCoerceRequestValues(...)`.
- Fixed the shipped umbrella-header regression in `src/Arlen/Arlen.h`.
  - The umbrella now uses `__has_include(...)` guards around optional MSSQL /
    SQL-dialect headers so apps do not break when those headers are not part of
    the tracked source tree.
- Added a tracked-tree smoke test in
  `tests/integration/DeploymentIntegrationTests.m`.
  - The test exports only tracked `src/Arlen` and `modules/*/Sources` files,
    then runs a `clang -fsyntax-only` compile against `Arlen.h`.
  - This is intended to catch future “umbrella imports a file that is only
    present locally/untracked” regressions.

## Verification status

- `source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && make build-tests`
  passed.
- `source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && xctest build/tests/ArlenUnitTests.xctest`
  passed.
  - Relevant new result: `SchemaContractTests: 8 tests PASSED`.
- `source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && xctest build/tests/ArlenIntegrationTests.xctest`
  was started and had progressed well into `HTTPIntegrationTests` when we stood
  down; it was not allowed to complete before end-of-day.

## Downstream bug-report classification

- `MusicianApp` `Arlen.h` import failure: real framework regression, fixed in
  this slice.
- `Structurizer` nested JSON array/object coercion bug: real framework
  regression, fixed in this slice.
- `MusicianApp` auth-ui eject / raw `@ requires` reports: likely stale direct
  use of vendored `build/arlen` / `build/eocc`, not missing current source
  mappings.
  - Current Arlen source already contains the expected Phase 18 auth eject
    file list and QR asset wiring.
  - No framework code change was made for that class tonight.

## Where to resume

1. Re-run `xctest build/tests/ArlenIntegrationTests.xctest` to completion and
   confirm the new `DeploymentIntegrationTests` smoke check passes in the full
   suite.
2. Decide whether to add a framework-side mitigation for stale vendored tool
   binaries (`bin/arlen` / `bin/boomhauer` guidance or stronger freshness
   checks), since that appears to be the remaining source of the latest
   `MusicianApp` auth-ui reports.
3. Resume `Phase 19` from `19A-C` after downstream bug triage is closed.

## Commit scope for this slice

- `src/Arlen/Arlen.h`
- `src/Arlen/Core/ALNSchemaContract.m`
- `tests/unit/SchemaContractTests.m`
- `tests/integration/DeploymentIntegrationTests.m`
- this handoff note

Unrelated local worktree changes remain present and intentionally untouched:

- uncommitted `Phase 19` roadmap/docs edits
- uncommitted data-layer / MSSQL / dialect work and generated API docs

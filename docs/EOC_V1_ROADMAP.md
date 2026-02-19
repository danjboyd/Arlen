# EOC v1 Implementation Roadmap

Status: Proposed  
Last updated: 2026-02-19

Related documents:

- `docs/PHASE1_SPEC.md` (framework-level Phase 1 architecture/specification)
- `docs/ARLEN_CLI_SPEC.md` (Phase 1 CLI contract for `arlen`)
- `docs/LITE_MODE_SPEC.md` (Phase 1 lite-mode behavior and boundaries)
- `docs/PHASE2_ROADMAP.md` (Phase 2 hardening milestones, including performance-gap closure)
- `docs/PHASE3_ROADMAP.md` (Phase 3 trend analysis and expanded performance maturity work)
- `V1_SPEC.md` (EOC template engine v1 details)

## Implementation Status (2026-02-18)

- Completed: Phase 2 runtime support scaffolding (`ALNEOCRuntime`).
- Completed: Phase 3 `eocc` transpiler CLI with state-machine parser and `#line` output.
- Completed: Phase 4 registry source generation (`EOCRegistry.m` output from `eocc`).
- Completed: Phase 5 initial GNUstep build integration via root `GNUmakefile` targets.
- Completed: Phase 6 unit-test baseline with XCTest (`make test`).
- Completed: initial basic-app capability checks (`eoc-smoke-render`, `boomhauer`, `bin/smoke`).
- In progress: deeper fixture coverage, richer routing/controller layers, and integration-level MVC examples.

## Cross-Cutting Rollout Alignment (2026-02-19)

- Performance-priority work that affects EOC render paths is planned in framework Phase 2/3 roadmaps.
- Phase 2C/2D define mandatory runtime timing coverage and CI perf-gate hardening.
- Phase 3C expands trend analysis and workload profile coverage for sustained performance governance.

## Goal

Deliver a working `.html.eoc` template system for GNUstep/Objective-C that compiles templates into Objective-C source and integrates with `gnustep-make`.

## Guiding Principles

- Prioritize deterministic behavior and clear diagnostics.
- Keep v1 focused on compile-time template generation.
- Maintain a path toward a full Mojolicious-style MVC stack.

## Phase Plan

## Phase 1: Freeze v1 Contract

Target: 0.5 day

Deliverables:

- Finalize syntax and semantics in `V1_SPEC.md`:
  - `<% code %>`
  - `<%= expr %>` (HTML-escaped)
  - `<%== expr %>` (raw)
  - `<%# comment %>`
- Confirm naming/path conventions for:
  - `templates/**/*.html.eoc`
  - generated `build/gen/templates/**/*.eoc.m`
  - symbol prefix `ALNEOCRender_...`
- Lock parse error shape (file, line, column, reason).

Exit criteria:

- No open ambiguity in parser/transpiler behavior for v1.

## Phase 2: Runtime Support Layer

Target: 1 day

Location: `src/Arlen/MVC/Template/`

Deliverables:

- Core runtime APIs:
  - `ALNEOCEscapeHTML(...)`
  - safe append helpers
  - `ALNEOCInclude(...)`
- Template dispatch/lookup contract for include rendering.
- Clear error propagation via `NSError **`.

Exit criteria:

- Runtime helpers compile and pass basic unit tests.

## Phase 3: `eocc` Transpiler CLI

Target: 2 days

Location: `tools/`

Deliverables:

- `eocc` command-line tool that:
  - scans template input paths
  - parses `.html.eoc` with a state machine
  - emits deterministic `.eoc.m` files
  - emits `#line` directives for diagnostic mapping
- Parser supports multiline code and expressions.
- Deterministic symbol/path sanitization.

Exit criteria:

- Valid fixtures transpile cleanly and invalid fixtures fail with accurate diagnostics.

## Phase 4: Generated Registry + Include Dispatch

Target: 1 day

Deliverables:

- Generate registry source (for example `EOCRegistry.m`) mapping:
  - logical template path -> render function pointer
- `ALNEOCInclude(...)` resolves includes through registry.

Exit criteria:

- Partials render correctly through registry-based dispatch.

## Phase 5: `gnustep-make` Integration

Target: 1 day

Deliverables:

- Prebuild step to:
  - discover `templates/**/*.html.eoc`
  - run `eocc`
  - compile generated sources
- Build fails fast on transpiler errors.
- Generated output remains untracked in Git.

Exit criteria:

- Single `make` command handles transpile + compile end-to-end.

## Phase 6: Tests and Fixtures

Target: 2 days

Locations:

- `tests/unit/`
- `tests/integration/`
- `tests/fixtures/templates/`

Deliverables:

- Fixture-driven parser/transpiler tests:
  - control flow
  - escaped output
  - raw output
  - comments
  - multiline tags
  - unclosed/malformed tag errors
- Runtime tests for include behavior and escaping.
- Integration tests for full render path.

Exit criteria:

- Core parser/runtime behavior covered by automated tests.

## Phase 7: Example App

Target: 1 day

Location: `examples/basic_app/`

Deliverables:

- Minimal MVC-style example that demonstrates:
  - context object
  - partial include
  - page template rendering
  - compiled `.html.eoc` output path

Exit criteria:

- Example app renders dynamic HTML successfully.

## Phase 8: Hardening and Release Readiness

Target: 1 day

Deliverables:

- Improve diagnostics and edge-case handling.
- Document `eocc` usage and expected build integration.
- Validate `.gitignore` coverage for generated artifacts.
- Confirm v1 acceptance criteria from `V1_SPEC.md`.

Exit criteria:

- v1 is stable for early adopters and internal expansion.

## Architecture Recommendations

- Implement `eocc` as an Objective-C CLI tool for single-language consistency.
- Keep templates trusted in v1 (no sandbox/untrusted execution model).
- Use composite template extensions (`.html.eoc`, future `.json.eoc`, `.txt.eoc`).

## Definition of Done (v1)

- Templates compile automatically during build.
- Escaped/raw output semantics are correct.
- Includes are functional and deterministic.
- Errors map back to original `.html.eoc` lines.
- Unit/integration tests pass.
- Example app demonstrates end-to-end workflow.

## Suggested Immediate Next Steps

1. Implement runtime helper interfaces in `src/Arlen/MVC/Template/`.
2. Create first `eocc` parser/transpiler prototype in `tools/`.
3. Add initial fixtures under `tests/fixtures/templates/` to drive development.

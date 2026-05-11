# EOC v1 Implementation Roadmap

Status: Complete with follow-on backlog
Last updated: 2026-03-21

Related documents:

- `docs/internal/PHASE1_SPEC.md` (framework-level Phase 1 architecture/specification)
- `docs/ARLEN_CLI_SPEC.md` (Phase 1 CLI contract for `arlen`)
- `docs/LITE_MODE_SPEC.md` (Phase 1 lite-mode behavior and boundaries)
- `docs/internal/PHASE2_ROADMAP.md` (Phase 2 hardening milestones, including performance-gap closure)
- `docs/internal/PHASE3_ROADMAP.md` (Phase 3 trend analysis and expanded performance maturity work)
- `V1_SPEC.md` (EOC template engine v1 details)

## Implementation Status (2026-03-13)

- Completed: Phase 2 runtime support scaffolding (`ALNEOCRuntime`).
- Completed: Phase 3 `eocc` transpiler CLI with state-machine parser and `#line` output.
- Completed: Phase 4 registry source generation (`EOCRegistry.m` output from `eocc`).
- Completed: Phase 5 initial GNUstep build integration via root `GNUmakefile` targets.
- Completed: Phase 6 unit-test baseline with XCTest (`make test`).
- Completed: deeper fixture coverage for multiline tags and malformed-tag diagnostics.
- Completed: template lint diagnostics for unguarded include calls (`eocc` warning contract: path/line/column/code/message).
- Completed: troubleshooting workflow docs for deterministic transpile/lint repair loops.
- Completed: initial basic-app capability checks (`eoc-smoke-render`, `boomhauer`, `bin/smoke`).
- Completed: richer routing/controller layers and integration-level MVC examples (`ALNRouter`, `ALNController`, `ALNView`, `examples/basic_app`, `examples/tech_demo`, and integration coverage).
- Completed: Phase 9 first-class template composition ergonomics for layouts, slots, partial locals, collection rendering, controller/view layout controls, and composition-first scaffold/example coverage.

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
  - sigil locals (`$name`) for zero-boilerplate context access
  - strict locals/stringify mode semantics for developer-safe defaults
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

## Phase 9: First-Class Template Composition

Target: 3 days

Goal:

Turn layouts and partials from low-level runtime helper usage into a first-class
EOC composition system that is more ergonomic than raw `ALNEOCInclude(...)`
calls while preserving deterministic behavior, explicit control flow, and
GNUstep-friendly build integration.

Completed groundwork already in repo:

- `ALNEOCInclude(...)`, template registry dispatch, and canonical logical-path
  resolution are already implemented.
- `ALNView` already supports explicit layout rendering by rendering a body
  template, injecting `content`, and rendering a second layout template.
- strict locals and strict stringify modes already provide useful failure
  behavior for template composition mistakes.
- `eocc` already emits deterministic lint diagnostics and location metadata,
  providing the base for richer composition lint rules.
- fixture coverage already exists for multiline tags, nested control flow,
  malformed sigils, and guarded/unguarded include contracts.
- module auth UI work already demonstrates real pressure for reusable partials,
  page wrappers, and app-owned layout/partial override hooks.

Completed phase steps:

1. Defined additive EOC syntax in `V1_SPEC.md` for first-class composition:
   - file-level layout directive
   - named slot/yield contract
   - partial include syntax with local overlays
   - collection-rendering shorthand
2. Implemented runtime helpers for composition:
   - overlay locals without mutating the caller context
   - render named slots deterministically
   - keep raw/escaped output boundaries explicit
3. Extended `ALNEOCTranspiler` and `eocc`:
   - parse new composition directives with the existing state-machine approach
   - rewrite directives into deterministic runtime helper calls
   - preserve `#line` diagnostics and location fidelity
4. Added composition lint and validation:
   - unknown static layout/partial paths
   - missing required locals for static calls
   - slot declared but never yielded
   - slot filled but never consumed
   - layout/include cycle detection where statically knowable
5. Expanded render ergonomics in `ALNView` and controller helpers:
   - default layout resolution model
   - page-level layout override and no-layout behavior
   - compatibility path for explicit existing render APIs
6. Added tests, fixtures, and examples:
   - layout + slot happy paths
   - nested partials with local overlays
   - collection rendering and empty-state coverage
   - regression cases for composition diagnostics
7. Updated developer-facing docs and generators:
   - `README.md`
   - `docs/GETTING_STARTED.md`
   - `docs/CLI_REFERENCE.md`
   - example templates and scaffold output where composition defaults change

Non-goals for Phase 9:

- deep multi-level template inheritance trees
- implicit magic that obscures render order or output escaping
- runtime-only composition behavior that bypasses transpile-time validation

Exit criteria:

- page templates can declare or inherit a default layout without manual
  `"content"` plumbing in application templates
- layouts can define named slots and pages can fill them deterministically
- partials can receive explicit local overlays instead of relying only on the
  shared root context
- collection rendering is ergonomic enough to replace common loop + include
  boilerplate
- static composition mistakes fail at transpile time when possible, otherwise at
  render time with deterministic path/line/column diagnostics
- docs, fixtures, and at least one example app demonstrate the composition model

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

## Post-v1 Follow-On Backlog

1. Deferred beyond v1: sound static missing-required-local validation for
   composition calls would require a stronger locals contract than the current
   inheritance model provides. Because includes/layouts/render calls overlay on
   ambient context instead of replacing it, `eocc` cannot prove absence without
   false positives unless a future revision adds explicit context-isolation or
   guaranteed-input declarations at call sites.

Resolved follow-on decisions:

- Named-slot defaults remain layout-owned only in v1; EOC does not add a
  caller-side fallback slot syntax.
- The scaffold and example apps stay on the composition-first path, and that
  path is already enforced by generated-app/example integration coverage.

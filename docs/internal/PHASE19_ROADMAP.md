# Arlen Phase 19 Roadmap

Status: complete on 2026-03-14 (`19A-19F`)
Last updated: 2026-03-14

Related docs:
- `docs/STATUS.md`
- `docs/CLI_REFERENCE.md`
- `docs/GETTING_STARTED.md`
- `docs/PHASE18_ROADMAP.md`

## 1. Objective

Replace Arlen's current coarse-grained compile/link flow with an incremental
build graph that keeps GNUmake/GNUstep compatibility while materially reducing
edit/verify latency for framework work, app-root `boomhauer` workflows, and
test execution.

Phase 19 also covers the developer-experience side of the same problem:
commands such as `boomhauer --prepare-only` and `boomhauer --print-routes`
should make their scope and progress obvious instead of feeling like opaque
"large build" operations.

## 1.1 Why Phase 19 Exists

Arlen now has enough framework surface that the current build topology is the
main cause of slow local iteration:

- many targets still compile via one large `clang` invocation instead of
  incremental object files
- test bundles frequently recompile the full framework, modules, and generated
  templates
- template transpilation paths still invalidate broad output trees
- app-root `boomhauer` builds rebuild tooling and compile large source sets
  without much visible phase-level progress

The problem is not just repo size. It is that the dependency graph is still too
coarse.

Phase 19 addresses that directly.

## 2. Design Principles

- Keep GNUmake and GNUstep as the supported build path.
- Prefer explicit dependency edges over hidden caching layers.
- Preserve deterministic generated-template behavior and diagnostics.
- Improve incremental rebuild time without weakening reproducibility.
- Keep `boomhauer` default-first: fast paths should help normal app
  development, not only framework maintainers.
- Separate true build-graph fixes from cosmetic progress output, but ship both
  in the same phase.
- Avoid introducing a second, competing build system during this phase.

## 3. Scope Summary

1. Phase 19A: object-file and dependency-file build foundation.
2. Phase 19B: shared framework/library artifact reuse across tools and tests.
3. Phase 19C: incremental EOC transpilation and generated-template object
   compilation.
4. Phase 19D: `boomhauer` command-scope tightening and progress UX.
5. Phase 19E: narrower test/example target prerequisites.
6. Phase 19F: confidence, regression, and timing documentation.

## 4. Scope Guardrails

- Do not replace GNUmake with CMake, Meson, Bazel, or another new build system
  in this phase.
- Do not paper over coarse invalidation solely with external compiler-cache
  tools.
- Do not weaken current `eocc` deterministic path/line/column diagnostics.
- Do not regress app-root compatibility or require developers to learn a new
  command set for common `boomhauer` flows.
- Do not make route inspection or prepare-only behavior "fast" by skipping
  correctness-critical freshness checks without explicit validation.

## 5. Milestones

Delivered on 2026-03-14:

- framework, modules, tools, tests, and generated templates now compile through
  deterministic object files under `build/obj/...` with depfiles and shared
  archive reuse through `build/lib/libArlenFramework.a`
- `eocc` now drives manifest-backed incremental template regeneration while
  generated `.html.eoc.m` outputs compile as first-class objects with
  per-template rebuild scope
- app-root `boomhauer --prepare-only` and `--print-routes` now report explicit
  `[1/4]` through `[4/4]` phases and reuse `.boomhauer/build/` objects/binary
  when inputs stay warm
- unit bundles no longer rebuild unrelated example servers, and integration
  bundles now depend on concrete server binaries instead of phony targets
- regression coverage now verifies framework-touch, template-touch, and
  unit-test-only rebuild scope, and `make phase19-confidence` writes timing +
  scope artifacts under `build/release_confidence/phase19`
- current Phase 19 confidence baseline (`examples/multi_module_demo_initial` app
  root):
  - `make build-tests` cold after `make clean`: `70.99s`
  - `make build-tests` warm/no-op: `0.37s`
  - `make test-unit`: `3.30s`
  - `bin/boomhauer --prepare-only`: `0.89s` cold / `0.43s` warm
  - `bin/boomhauer --print-routes`: `0.44s`

## 5.1 Phase 19A: Object + Dependency Build Foundation

Deliverables:

- Refactor `GNUmakefile` so framework, tools, tests, and generated sources
  compile to object files under a deterministic `build/obj/...` layout.
- Emit dependency files (`-MMD -MP` or equivalent) so header changes rebuild
  only the affected objects.
- Preserve current target names (`eocc`, `boomhauer`, `arlen`, `test-unit`,
  `test-integration`) while changing their internals to link from object files
  instead of compiling everything monolithically.

Acceptance (required):

- touching a single framework `.m` file rebuilds only the affected object(s)
  and dependent links
- repeated no-op builds are materially faster than the current monolithic path
- target outputs remain deterministic and compatible with current tooling

## 5.2 Phase 19B: Shared Framework Artifact Reuse

Deliverables:

- Build the framework sources once into a shared or static framework artifact
  suitable for reuse by:
  - `build/arlen`
  - `build/boomhauer`
  - example servers
  - test bundles
- Reuse compiled framework/module objects across those downstream targets
  instead of recompiling framework sources per binary.
- Keep module source reuse explicit and deterministic.

Acceptance (required):

- `arlen`, `boomhauer`, and test bundles stop recompiling the full framework on
  every build
- downstream targets mostly relink when only their own entrypoint sources
  change
- GNUstep/base linking behavior remains stable

## 5.3 Phase 19C: Incremental EOC Pipeline

Deliverables:

- Replace broad template-output invalidation with per-template incremental
  transpilation for app and module templates.
- Track generated-template freshness with a deterministic manifest or equivalent
  dependency mapping.
- Compile generated template `.m` files to reusable object files just like
  hand-written sources.
- Garbage-collect removed template outputs without forcing full tree rebuilds.

Acceptance (required):

- changing one `.html.eoc` file retranspiles only that template and rebuilds
  only its generated object plus downstream links
- generated-template diagnostics remain path/line/column accurate
- module template overrides still resolve correctly

## 5.4 Phase 19D: `boomhauer` Scope + Progress UX

Deliverables:

- Add explicit progress output for app-root build stages such as:
  - checking tool freshness
  - transpiling templates
  - compiling app objects
  - linking app binary
- Document and tighten what `--prepare-only` and `--print-routes` are expected
  to do internally.
- Add the lightest correct route-inspection/preparation path feasible without
  skipping freshness-critical rebuilds.
- Make stale-tool detection for vendored/build-time tools more visible when the
  active binary does not match source freshness.

Acceptance (required):

- developers can tell whether `boomhauer` is transpiling, compiling, linking,
  or just reusing current artifacts
- `--print-routes` and `--prepare-only` no longer feel like opaque full-server
  launches
- correctness is preserved when framework/app/tooling inputs change

## 5.5 Phase 19E: Test + Example Build Narrowing

Deliverables:

- Reduce unnecessary prerequisites for unit and integration bundles.
- Stop rebuilding unrelated example servers for targets that do not need them.
- Keep example/server binaries available through explicit targets, but avoid
  forcing them into every test rebuild.
- Reuse compiled support code across unit/integration bundles where practical.

Acceptance (required):

- `make test-unit` avoids unrelated example-server rebuilds
- `make test-integration` only builds the runtime/example binaries actually
  required by the suite
- test-target behavior stays deterministic and CI-safe

## 5.6 Phase 19F: Confidence, Measurement, + Documentation

Deliverables:

- Add build-regression coverage that verifies incremental rebuild scope for:
  - one framework source change
  - one template change
  - one test-only change
- Record before/after timing baselines for representative commands such as:
  - `make build-tests`
  - `make test-unit`
  - `./bin/boomhauer --prepare-only`
  - `./bin/boomhauer --print-routes`
- Update:
  - `docs/CLI_REFERENCE.md`
  - `docs/GETTING_STARTED.md`
  - `docs/STATUS.md`
  - any build/DX troubleshooting docs affected by the new graph

Acceptance (required):

- Arlen has an executable regression net against returning to coarse rebuilds
- documentation explains the new build behavior and command scope clearly
- timing improvements are demonstrated with reproducible numbers, not just
  anecdotal claims

# Arlen Phase 22 Roadmap

Status: In progress (`22A-22F` drafted/implemented; `22G` closeout and final verification pending)
Last updated: 2026-03-27

Related docs:
- `README.md`
- `docs/README.md`
- `docs/STATUS.md`
- `docs/GETTING_STARTED.md`
- `docs/GETTING_STARTED_QUICKSTART.md`
- `docs/FIRST_APP_GUIDE.md`
- `docs/CLI_REFERENCE.md`
- `docs/CORE_CONCEPTS.md`
- `docs/MODULES.md`
- `docs/ECOSYSTEM_SERVICES.md`
- `docs/PHASE21_ROADMAP.md`
- `docs/DOCUMENTATION_POLICY.md`

Audit basis:
- Internal documentation audit completed on 2026-03-27 against the checked-in
  README, docs index, onboarding guides, CLI/help output, generated app
  scaffolds, module/service docs, and user-facing command surfaces.

## 1. Objective

Make Arlen's documentation newcomer-friendly, code-accurate, and complete for
the user-facing features early adopters are most likely to try first.

Phase 22 is a documentation usability and trustworthiness pass. It is not a
deep internal architecture-writing phase.

## 1.1 Why Phase 22 Exists

The current documentation set is broad and mostly accurate, but it still has
three release-facing problems:

- the main entry path is maintainer-first rather than newcomer-first
- a small number of visible docs/help mismatches weaken trust
- several important product surfaces still require users to piece workflows
  together from roadmap, spec, or phase-contract material

That is survivable for internal use, but it is not the right first impression
for public OSS release.

## 1.2 Audit Summary

The documentation audit found:

- good raw coverage of many framework surfaces, especially CLI commands,
  modules, auth, jobs, data-layer capabilities, and release tooling
- relatively few direct docs-vs-code mismatches, but the ones that do exist are
  visible enough to matter
- a larger information-architecture problem where historical phase status,
  contributor workflow, and user onboarding are mixed together on the same
  pages
- missing dedicated user guides for app authoring, module lifecycle, lite-mode
  usage, plugin/service-adapter generation, frontend starters, and common
  configuration

Phase 22 addresses those directly.

## 2. Design Principles

- Put the first-user path before roadmap history and contributor-only detail.
- Prefer one obvious recommended app-creation path over multiple overlapping
  introductions.
- Focus on user-facing features and workflows, not exhaustive internal
  implementation notes.
- Keep command examples truthful to the current CLI/help output and generated
  scaffolds.
- Separate contributor/release-process material from ordinary app-author
  guidance where possible.
- Preserve the clang-built GNUstep toolchain contract and existing docs quality
  expectations.
- Add lightweight verification for docs drift where that meaningfully improves
  trust.

## 3. Scope Summary

1. Phase 22A: entrypoint and navigation reset.
2. Phase 22B: onboarding and first-app path consolidation.
3. Phase 22C: accuracy sweep and docs/code parity hardening.
4. Phase 22D: app-author guide set for routing, controllers, middleware, and
   configuration.
5. Phase 22E: module lifecycle and lite-mode guidance.
6. Phase 22F: plugin/service-adapter and frontend-starter guidance.
7. Phase 22G: docs quality gates, historical partitioning, and release closeout.

## 3.1 Recommended Rollout Order

1. `22A`
2. `22B`
3. `22C`
4. `22D`
5. `22E`
6. `22F`
7. `22G`

That order fixes discoverability first, then repairs trust/accuracy, then fills
the most important workflow gaps, and only after that locks the new structure
into the docs quality path.

## 4. Scope Guardrails

- Do not widen this phase into full internal architecture documentation for
  every subsystem.
- Do not rewrite historical roadmap/spec documents solely for style
  consistency; prefer navigation and positioning fixes over churn.
- Do not let onboarding pages become contributor checklists.
- Do not duplicate the same command reference across many pages without a clear
  canonical source.
- Do not soften or hide real prerequisites just to make docs shorter.
- Do not change supported toolchain/runtime claims unless the code and CI
  contract have actually changed.

## 5. Milestones

## 5.1 Phase 22A: Entrypoint + Navigation Reset

Status: complete

Checkpoint notes:

- `README.md` now leads with `Start Here` and `Quick Start` before the long
  phase-history status block.
- `docs/README.md` now separates newcomer docs, app authoring,
  modules/integrations, operations, reference, and contributor/history material
  into distinct sections.
- The new entry path now points newcomers at dedicated first-app, app-author,
  lite-mode, and configuration docs instead of phase-history material.

Deliverables:

- Restructure `README.md` so the primary newcomer path appears before long phase
  history and release bookkeeping.
- Rework `docs/README.md` into clearer buckets such as:
  - start here
  - build and run
  - app authoring
  - modules and integrations
  - operations and deployment
  - contributor and historical material
- Reduce the amount of roadmap/history material mixed into the first-screen
  experience for a new developer.

Acceptance (required):

- A new developer can find prerequisites, first app creation, and next-step
  guides without reading phase-history material first.
- The docs index makes a visible distinction between user docs and
  contributor/history docs.

## 5.2 Phase 22B: Onboarding + First-App Consolidation

Status: complete

Checkpoint notes:

- `docs/GETTING_STARTED.md`, `docs/GETTING_STARTED_QUICKSTART.md`, and
  `docs/FIRST_APP_GUIDE.md` were rewritten around one generator-first app path.
- The recommended first-app flow now uses `arlen generate endpoint --route`
  instead of manual bootstrap-file edits.
- Contributor-only quality-gate and release detail was pushed behind the main
  scaffold/run/add-route path.

Deliverables:

- Rewrite `docs/GETTING_STARTED.md`, `docs/GETTING_STARTED_QUICKSTART.md`, and
  `docs/FIRST_APP_GUIDE.md` around one recommended first-app path.
- Promote the generator-assisted endpoint flow (`generate endpoint --route`)
  instead of requiring manual boot-file edits in the introductory guide.
- Move contributor-only build/test/release material out of the primary first-app
  path or clearly mark it as optional follow-on material.
- Keep a short “fastest path” doc and a broader “full getting started” doc, but
  remove overlap that currently forces users to compare all three.

Acceptance (required):

- The first-app path appears before contributor quality-gate detail in the main
  onboarding docs.
- A newcomer can scaffold, run, and add one new route using only the
  recommended path without consulting a roadmap/spec page.

## 5.3 Phase 22C: Accuracy Sweep + Parity Hardening

Status: complete

Checkpoint notes:

- `./build/arlen --help` now advertises `module ... eject`, aligning the
  top-level CLI help with the module command surface.
- The API reference generator now ignores forward protocol declarations ending
  in `;`, removing the duplicate `ALNPlugin` symbol from generated docs.
- The Phase 22 docs pass uncovered and fixed a real generator regression:
  `arlen generate endpoint` now inserts the needed controller import into
  `src/main.m` / `app_lite.m`, and a deployment integration regression test was
  added for that path.
- `docs/TOOLCHAIN_MATRIX.md` now documents the extra toolchain-matrix presence
  check performed by `bin/arlen-doctor`.

Deliverables:

- Resolve the documentation mismatches surfaced by the audit, including command
  help, generated API reference presentation, and tooling-check descriptions.
- Audit high-traffic docs against current CLI help, generated scaffolds, and key
  runtime surfaces.
- Add or extend lightweight docs verification where practical for:
  - CLI/help text drift
  - generated API reference hygiene
  - known onboarding command examples
- Record the canonical regeneration/update workflow for generated docs.

Acceptance (required):

- Known docs/help mismatches from the audit are resolved.
- User-facing command examples in the main onboarding/reference docs are
  revalidated against the checked-in CLI behavior.

## 5.4 Phase 22D: App-Author Guides

Status: complete

Checkpoint notes:

- Added `docs/APP_AUTHORING_GUIDE.md` for routes, controllers, middleware,
  params, validation, sessions, auth helpers, and route metadata.
- Added `docs/CONFIGURATION_REFERENCE.md` for the early-runtime keys app
  authors are most likely to change first.
- Updated onboarding/index surfaces to point at those guides directly.

Deliverables:

- Add dedicated user guides for:
  - routing and route registration patterns
  - controllers and response/render helpers
  - middleware ordering and common middleware use
  - common configuration/runtime keys that app authors are likely to touch early
- Cross-link those guides from `README.md`, `docs/README.md`, and the getting
  started family.
- Keep the content workflow-oriented rather than API-dump oriented.

Acceptance (required):

- An app author can learn common HTML-first and JSON-first route/controller
  patterns without reading source or phase docs.
- Common runtime/config knobs used in early app development are documented in a
  dedicated, user-facing place.

## 5.5 Phase 22E: Module Lifecycle + Lite-Mode Guidance

Status: complete

Checkpoint notes:

- `docs/MODULES.md` now covers the module lifecycle as one connected workflow:
  add, list, doctor, migrate, assets, upgrade, eject, remove, and override
  boundaries.
- Added `docs/LITE_MODE_GUIDE.md` so users can choose between full and lite
  mode without reading the historical spec.
- Historical/spec docs now cross-link the new user-facing lite-mode guidance.

Deliverables:

- Expand module docs into a cohesive lifecycle guide covering:
  - add
  - list
  - doctor
  - migrate
  - assets
  - upgrade
  - eject
  - remove
  - override/customization boundaries
- Add a practical lite-mode user guide covering:
  - when to choose full vs lite
  - the actual lite scaffold shape
  - common lite workflows
  - lite-to-full migration path
- Ensure these workflows are discoverable without reading `LITE_MODE_SPEC.md` or
  phase history.

Acceptance (required):

- A new user can successfully choose between full and lite mode from user docs,
  not from specs.
- First-party module adoption and customization workflows are documented as one
  connected lifecycle.

## 5.6 Phase 22F: Plugin/Service + Frontend Guidance

Status: complete

Checkpoint notes:

- Added `docs/PLUGIN_SERVICE_GUIDE.md` for app-local plugin and service-adapter
  generation workflow.
- Added `docs/FRONTEND_STARTERS.md` for choosing and customizing the frontend
  starter presets.
- Updated the relevant historical/spec docs to point at the new practical
  guides.

Deliverables:

- Add a dedicated guide for `arlen generate plugin` and service-adapter author
  workflows.
- Add a user-facing frontend-starters guide explaining:
  - available presets
  - when to choose each one
  - generated file layout
  - typical customization and integration path
- Cross-link plugin/service/frontend docs from onboarding and modules docs where
  appropriate.

Acceptance (required):

- Users can generate a plugin/service adapter or frontend starter and understand
  the intended next edits without relying on phase-contract docs alone.
- Frontend-starter documentation is available as a product guide, not only as a
  historical phase document.

## 5.7 Phase 22G: Docs Quality + Release Closeout

Status: in progress

Checkpoint notes:

- Added `tools/ci/check_docs_navigation.py` and wired it into
  `tools/ci/run_docs_quality.sh` so the newcomer-first docs layout is checked in
  CI.
- Updated `docs/DOCUMENTATION_POLICY.md` so Phase 22 user-facing docs are part
  of the docs definition-of-done and review checklist.
- `make arlen build-tests` and `bash tools/ci/run_docs_quality.sh` passed during
  this checkpoint.
- Remaining closeout work: finish the long `make test-integration` verification
  run, then update summary surfaces from `in progress` to `complete`.

Deliverables:

- Update docs quality workflows so the new Phase 22 structure stays maintainable.
- Add explicit docs review/checklist coverage for newcomer accessibility,
  user-facing completeness, and code/help parity.
- Partition contributor/history material more cleanly now that the user-facing
  entry path is improved.
- Close the phase with updated summary surfaces and a documented docs
  confidence/maintenance path.

Acceptance (required):

- The main docs surfaces reflect the new information architecture and guide set.
- The repo has a clear maintenance path for preventing the highest-value docs
  drift from reappearing.

## 6. Exit Criteria

Phase 22 is complete when:

1. the newcomer path is shorter and clearer than the current maintainer-first
   path
2. the audit's known inaccuracies are resolved
3. the missing user-facing guides called out by the audit are present and linked
   from the main entry surfaces
4. the updated docs structure has a lightweight quality/maintenance path rather
   than depending on manual memory alone

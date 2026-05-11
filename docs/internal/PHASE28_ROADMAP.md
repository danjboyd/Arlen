# Arlen Phase 28 Roadmap

Status: Complete (`28A-28L` delivered on 2026-04-03)
Last updated: 2026-04-03

Related docs:
- `docs/STATUS.md`
- `docs/README.md`
- `docs/ARLEN_ORM.md`
- `docs/ARLEN_ORM_MIGRATIONS.md`
- `docs/GETTING_STARTED_API_FIRST.md`
- `docs/FRONTEND_STARTERS.md`
- `docs/internal/FEATURE_PARITY_MATRIX.md`
- `docs/PHASE26_ROADMAP.md`
- `docs/DOCUMENTATION_POLICY.md`

Reference inputs reviewed for this roadmap:
- `docs/ARLEN_ORM.md`
- `docs/ARLEN_ORM_MIGRATIONS.md`
- `docs/GETTING_STARTED_API_FIRST.md`
- `docs/FRONTEND_STARTERS.md`
- `docs/internal/FEATURE_PARITY_MATRIX.md`
- `docs/PHASE26_ROADMAP.md`
- `examples/arlen_orm_reference/README.md`
- `src/Arlen/ORM/ALNORMCodegen.m`
- `src/Arlen/Core/ALNOpenAPI.m`
- `https://mikro-orm.io/docs/identity-map`
- `https://mikro-orm.io/docs/unit-of-work`
- `https://typeorm.io/docs/getting-started/`
- `https://typeorm.io/docs/advanced-topics/transactions/`
- `https://www.prisma.io/docs/orm/prisma-client/testing/unit-testing`
- `https://www.prisma.io/docs/orm/prisma-client/testing/integration-testing`
- `https://orm.drizzle.team/docs/overview`
- `https://orm.drizzle.team/docs/zod`
- `https://tanstack.com/query/v5/docs/framework/react/typescript`

## 0. Starting Point

Arlen already has most of the server-side substrate this phase needs:

- Phase 26 shipped a descriptor-first optional ORM with deterministic reflection,
  codegen, snapshots, drift checks, explicit load strategies, and request-
  scoped context semantics.
- Phase 3 shipped schema/auth/OpenAPI metadata for JSON-first applications.
- Phase 7F shipped explicit frontend integration guidance without turning
  Arlen into a frontend toolchain framework.

What Arlen does not yet ship is a first-party TypeScript/React consumption
layer built from those same server-side contracts.

Today a React team evaluating Arlen still has to hand-maintain some
combination of:

- TypeScript DTOs
- fetch client wrappers
- query/mutation key helpers
- validation schemas
- relation-expansion payload types

Phase 28 exists to close that gap without changing Arlen's core architecture.

## 0.1 Phase 28 North Star

Make Arlen best-in-class for descriptor-first TypeScript and React consumers.

That means:

- React teams can generate a typed client/model layer from Arlen descriptors
  and route/OpenAPI contracts.
- Generated output feels natural in a TypeScript codebase.
- Arlen's source of truth remains schema metadata, ORM descriptors, and route
  contracts, not handwritten TypeScript entity files.
- Server-side persistence remains in Objective-C; the browser gets typed
  contracts, not a second ORM runtime.

## 1. Objective

Add a first-party TypeScript/React interop layer on top of ArlenORM and
Arlen's API-contract/OpenAPI surface.

Phase 28 should deliver:

- deterministic TypeScript codegen from ORM descriptors and route contracts
- generated model/read/write/query types for frontend consumption
- a typed transport client that works in browser and Node environments
- an optional React-oriented hook/query-key layer for common React stacks
- optional validator/schema adapters for form-heavy TypeScript apps
- regression, compile, integration, and confidence coverage strong enough to
  support a serious frontend-contract claim

Phase 28 is an additive consumer-contract phase, not a rewrite of ArlenORM
into a TypeScript-native persistence framework.

## 1.1 Why Phase 28 Exists

Phase 26 made Arlen credible for backend teams that want an honest optional
ORM. That still leaves a frontend adoption gap:

- React developers expect first-party typed contracts rather than hand-kept
  API DTO files.
- TypeScript ORM ecosystems have trained users to expect rich generated types,
  relation-aware payloads, and ergonomic query/mutation helpers.
- OpenAPI alone is not enough for all ORM-adjacent frontend ergonomics,
  especially around relation shapes, readonly semantics, and model-derived
  mutation/input contracts.

Arlen already has the core ingredients:

- normalized schema metadata
- ORM descriptors
- route schema contracts
- OpenAPI emission

The missing piece is a disciplined frontend-facing generator layer that keeps
those inputs aligned instead of duplicating them.

## 1.2 Reference Bar

Phase 28 should borrow selectively:

- MikroORM:
  - request-scoped identity and context discipline
  - data-mapper / unit-of-work honesty
  - strong warning against accidental global mutable ORM state
- TypeORM:
  - familiar entity/repository ergonomics for TypeScript developers
  - strong transaction-boundary discipline
  - relation/query feature expectations that frontend teams now treat as
    baseline vocabulary
- Prisma:
  - generated client and type ergonomics
  - explicit split between mock-friendly unit tests and dedicated integration
    database tests
  - clear generated-client entrypoint story
- Drizzle:
  - headless, opt-in tooling philosophy
  - SQL-forward/non-invasive ergonomics
  - schema-derived validator adapters
- TanStack Query:
  - typed query and mutation option helpers
  - typed query-key ergonomics that feel native in React codebases

Arlen should not copy:

- browser-side persistence or direct database access
- decorator/reflection-heavy runtime semantics where generated TypeScript
  classes become canonical
- hidden lazy loading or client-side relation IO magic
- mandatory React, Node, or validator dependencies in Arlen core runtime
- a design where TypeScript output silently exposes every ORM model or field

## 1.3 Design Principles

- Descriptor-first source of truth:
  - schema/metadata -> ORM descriptors -> Objective-C and TypeScript outputs
- Keep TypeScript generated and consumer-facing:
  - TypeScript is not the canonical persistence definition
- Preserve Objective-C server ownership:
  - database access, repositories, load plans, and mutations stay server-side
- Prefer plain typed transport first:
  - React hook wrappers come after a strong browser/Node-neutral client
- Keep frontend adapters optional:
  - React/TanStack and Zod-style outputs are opt-in targets, not mandatory
- Preserve explicit relation loading:
  - generated clients can request only declared/allowed expansions
- Keep persistence metadata and UI metadata separate:
  - frontend field/display hints should derive from route/resource contracts,
    not be smuggled into base ORM descriptors
- Preserve deterministic artifacts:
  - no timestamp noise, unstable ordering, or generator-only drift
- Keep backend capability honesty:
  - generated TypeScript contracts must not pretend PostgreSQL, MSSQL, and
    Dataverse support identical semantics
- Keep non-TypeScript apps unaffected:
  - no build/runtime cost for teams not opting into this surface

## 2. Scope Summary

1. `28A`: TypeScript contract/codegen foundation.
2. `28B`: generated model, input, and envelope surface.
3. `28C`: typed transport client generation from route/OpenAPI metadata.
4. `28D`: optional React hook/query-key layer.
5. `28E`: validator/schema adapter generation.
6. `28F`: explicit relation and query-shape contracts.
7. `28G`: module/resource/admin metadata integration.
8. `28H`: CLI, package layout, examples, and workspace ergonomics.
9. `28I`: focused TypeScript unit-test architecture and shared support.
10. `28J`: live integration and React reference-app coverage.
11. `28K`: drift/perf/compatibility artifacts and confidence hardening.
12. `28L`: docs, API reference, and release closeout.

## 2.1 Recommended Rollout Order

1. `28A`
2. `28B`
3. `28C`
4. `28D`
5. `28E`
6. `28F`
7. `28G`
8. `28H`
9. `28I`
10. `28J`
11. `28K`
12. `28L`

That order keeps descriptor and transport contracts stable before Arlen commits
to React-specific wrappers, broader module metadata, and confidence-lane
closeout.

## 3. Scope Guardrails

- Do not make handwritten TypeScript entity classes the source of truth.
- Do not add browser-side ORM persistence or direct database-driver usage.
- Do not introduce implicit lazy-loading semantics into generated clients.
- Do not require Node, npm, React, TanStack Query, or Zod for apps that do not
  opt in.
- Do not widen Arlen core runtime into a frontend build system or asset
  pipeline.
- Do not silently expose model fields or CRUD routes without explicit
  route/resource contracts.
- Do not duplicate schema truth between ORM descriptors and OpenAPI without
  parity/drift checks.
- Do not weaken the Phase 26 descriptor-history contract.
- Do not mix admin/form/display metadata into base ORM descriptor semantics.
- Do not pretend Dataverse is just another SQL-backed TypeScript target.

## 4. Milestones

## 4.1 Phase 28A: TypeScript Contract + Codegen Foundation

- Add a first-party TypeScript codegen workflow on top of Arlen descriptors and
  route/OpenAPI metadata.
- Define a stable manifest format for generated TypeScript artifacts, such as:
  - `arlen-typescript-contract-v1`
- Standardize app-owned output conventions so generation remains explicit and
  reviewable.
- Fail closed when descriptors, route metadata, or naming inputs are not
  sufficient to generate stable TypeScript output.

Likely CLI shape:

```text
arlen typescript-codegen [--out-dir <path>] [--manifest <path>] [--target <models|validators|query|client|react|meta|all>] [--force]
```

## 4.2 Phase 28B: Generated Model + Mutation Surface

- Generate TypeScript model types from `ALNORMModelDescriptor` and related
  descriptor contracts.
- Preserve:
  - readonly vs writable fields
  - nullability
  - enum/value-object shape
  - primary/unique identity fields
  - read-only/view semantics
  - relation cardinality
- Generate distinct frontend-facing types for:
  - read models
  - create input
  - update/patch input
  - list/result envelopes where route contracts define them
- Default to interfaces/types as the canonical TypeScript output; any class
  wrappers should remain ergonomic sugar rather than the required runtime model.

## 4.3 Phase 28C: Typed Transport Client

- Generate a typed `fetch`-based client from Arlen route schemas and OpenAPI
  operation metadata.
- Support browser and Node runtimes without bundler-specific assumptions.
- Emit typed:
  - request payloads
  - response envelopes
  - validation/error envelopes
  - pagination/cursor metadata
  - auth/header/base-URL configuration hooks
- Require stable operation IDs and fail closed when route contracts are too
  vague to support deterministic client generation.

## 4.4 Phase 28D: React Hook + Query-Key Layer

- Add an optional React-oriented output target layered on top of the plain
  transport client.
- Generate:
  - query-key factories
  - typed query option helpers
  - typed mutation option helpers
  - invalidation metadata keyed to explicit route/resource semantics
- Keep this layer optional and package-scoped so plain TypeScript consumers are
  not forced into React-specific dependencies.
- Prefer TanStack Query-compatible ergonomics without making Arlen's server
  story depend on TanStack Query.

## 4.5 Phase 28E: Validator + Form Schema Adapters

- Generate validator/schema outputs from the same route and descriptor inputs.
- Ship a framework-neutral base manifest plus at least one first-party adapter
  target suitable for TypeScript form workflows.
- Preserve:
  - readonly fields
  - enum domains
  - nullability
  - required/writeable field sets
  - scalar format hints already present in route contracts
- Keep validation outputs separate from persistence metadata so Arlen does not
  turn ORM descriptors into a UI-layout system.

## 4.6 Phase 28F: Relation + Query-Shape Contracts

- Expose explicit frontend-side typing for allowed relation expansions and
  result shapes.
- Make relation/query requests explicit rather than lazy:
  - `select`
  - `include` / expansion
  - pagination/cursor contracts
  - resource-specific filters and sort fields
- Align these contracts with Arlen's explicit server-side load strategies
  rather than introducing hidden nested IO semantics.
- Fail closed when an app attempts to generate relation/query shapes that the
  server contract does not actually allow.

## 4.7 Phase 28G: Module + Resource Metadata Bridge

- Allow first-party module JSON/OpenAPI surfaces to contribute TypeScript
  clients and metadata to the generated package.
- Cover at least the metadata surfaces React teams are most likely to reuse:
  - auth/session bootstrap contracts
  - admin resource metadata
  - search result/capability metadata
  - storage/job/ops JSON envelopes where already modeled explicitly
- Keep this bridge contract-driven and explicit; do not infer module behavior
  from templates or HTML output.

## 4.8 Phase 28H: CLI + Workspace Ergonomics + Examples

- Ship a deterministic codegen workflow with app-owned output directories and
  generated manifests.
- Support common adoption shapes:
  - app-local generated folder
  - monorepo package
  - publishable internal client package
- Generate supporting files where they materially improve adoption:
  - `package.json`
  - `tsconfig.json`
  - README/manifest/update notes
- Add at least one checked-in React reference example that consumes generated
  Arlen artifacts without making React a core runtime dependency.

## 4.9 Phase 28I: TypeScript Unit-Test Architecture + Shared Support

Delivered on 2026-04-03.

- Added the dedicated `tests/typescript/` harness so TypeScript-side
  verification complements, rather than replaces, Objective-C/XCTest coverage.
- Split verification into focused families:
  - generated snapshot and manifest stability tests
  - strict compile-only package checks
  - transport-client unit tests with mocked `fetch`
  - React hook/query-key tests
  - validator/query/meta parity tests
  - live integration tests that regenerate from merged OpenAPI input
- Added shared fixture/support helpers plus the checked-in
  `tests/fixtures/phase28/typescript_snapshot.json` characterization artifact.

## 4.10 Phase 28J: Integration + React Reference Coverage

Delivered on 2026-04-03.

- Added the live `examples/typescript_reference_server` backend used by the Phase 28
  TypeScript and React lanes.
- Exercised both representative frontend scenarios from the roadmap:
  - back-office CRUD/resource management
  - customer-facing dashboard/detail/query flows
- Added merged-OpenAPI verification so the live exported contract must match
  the checked-in Phase 28 fixture before TypeScript regeneration runs.
- Wired the checked-in React/Vite reference workspace into a live merged-spec
  lane instead of limiting it to fixture-only generation.

## 4.11 Phase 28K: Drift, Performance, + Confidence Artifacts

Delivered on 2026-04-03.

- Added fail-closed drift checks between checked-in Phase 28 OpenAPI contracts,
  live exported OpenAPI, and regenerated TypeScript outputs.
- Added the repo-native scripts and make targets for:
  - `phase28-ts-generated`
  - `phase28-ts-unit`
  - `phase28-ts-integration`
  - `phase28-react-reference`
  - `phase28-confidence`
- Published machine-readable manifests plus generation/build metrics under
  `build/release_confidence/phase28/`.
- Hardened the core OpenAPI export path so route schema `format` hints now
  survive readiness validation and live OpenAPI generation.

## 4.12 Phase 28L: Docs + API Reference + Release Closeout

Delivered on 2026-04-03.

- Updated the user-facing docs set so React/TypeScript adoption now has a real
  first-party path across:
  - `README.md`
  - `docs/STATUS.md`
  - `docs/README.md`
  - `docs/ARLEN_ORM.md`
  - `docs/GETTING_STARTED_API_FIRST.md`
  - `docs/FRONTEND_STARTERS.md`
  - `docs/CLI_REFERENCE.md`
  - generated API reference via `make docs-api`
- Documented both the happy path and the guardrails:
  - descriptor-first generation
  - optional React adapters
  - no browser-side ORM persistence
  - fail-closed contract drift and confidence lanes

## 5. Testing and Verification Strategy

Phase 28 should carry a deliberately broad verification strategy informed by
the strongest testing ideas from the reviewed TypeScript ORM ecosystems.

## 5.1 Core Test Families

- Descriptor/codegen determinism:
  - inspired by Prisma's generated-client posture and Arlen Phase 26
  - verify stable manifests and generated TypeScript output from unchanged
    descriptor and route inputs
- Compile-only TypeScript surface tests:
  - inspired by the expectation of type-safe generated clients in Prisma,
    Drizzle, and TanStack Query ecosystems
  - run `tsc --noEmit` against generated packages and representative consumers
- Mock-friendly client unit tests:
  - inspired by Prisma's official unit-testing guidance
  - test transport helpers and generated client behavior with injected/mock
    client context instead of a live database
- Request/context isolation coverage:
  - inspired by MikroORM's request-context and identity-map discipline
  - ensure generated examples and integration adapters never rely on process-
    global mutable request state
- Transaction-boundary coverage:
  - inspired by TypeORM's transaction-manager guidance
  - ensure transaction-scoped behaviors and mutation helpers do not fall back
    to global/shared client state
- Validator/schema parity coverage:
  - inspired by Drizzle's schema-derived validator adapters
  - verify validator outputs stay derived from the same contract inputs as the
    generated models and clients
- Relation/query-shape coverage:
  - inspired by TypeORM/MikroORM relation ergonomics and Arlen's explicit load
    strategy rules
  - assert that allowed expansions compile and disallowed ones fail closed
- Integration database/container coverage:
  - inspired by Prisma's dedicated integration-testing workflow
  - run generated clients against disposable, seeded test environments
- React hook/query-key coverage:
  - inspired by TanStack Query's typed query/mutation ergonomics
  - verify stable query keys, invalidation metadata, and typed options helpers
- Negative-path drift coverage:
  - ensure descriptor/OpenAPI/generator mismatches fail loudly rather than
    emitting silently wrong TypeScript

## 5.2 Planned Test Layout

Expected checked-in structure:

- `tests/unit/Phase28*Tests.m`
- `tests/typescript/unit/`
- `tests/typescript/integration/`
- `tests/typescript/react/`
- `tests/typescript/shared/`
- `tests/fixtures/phase28/`
- `build/release_confidence/phase28/`

Expected fixture families:

- descriptor/openapi parity fixtures
- generated package snapshots
- relation/query-shape contracts
- validation-schema snapshots
- query-key and invalidation contracts
- module metadata fixtures
- container seed/reset manifests
- React reference-app characterization artifacts

## 5.3 Phase 28 Exit Standard

Satisfied on 2026-04-03.

Arlen can claim Phase 28 complete only if:

- non-TypeScript apps remain unaffected
- descriptor-first generation remains the canonical source-of-truth model
- React teams can consume a first-party generated TypeScript package without
  hand-maintaining core DTOs
- a plain typed transport client exists independently of React wrappers
- React and validator adapters remain optional and honestly scoped
- relation and query-shape contracts stay explicit rather than lazy/magical
- descriptor/OpenAPI/generated-package drift is fail-closed and test-covered
- docs/examples/CLI guidance are current
- confidence lanes cover generation, compile, unit, integration, and reference
  app behavior

## 6. Phase-Level Acceptance

Phase 28 should be considered successful when all of the following are true:

1. Arlen remains descriptor-first and Objective-C-owned on the server.
2. React/TypeScript developers get a serious first-party generated contract
   story instead of handwritten DTO glue.
3. Generated outputs feel native in TypeScript codebases without becoming a
   second persistence runtime.
4. Plain typed transport remains first-class; React integration is additive.
5. Validator/query-key/hook outputs are derived from the same canonical
   contracts and do not drift silently.
6. The phase exits with a credible confidence story, not just a generator that
   "usually works."

## 7. Verification Targets

Phase 28 closeout verification now includes:

```bash
source tools/source_gnustep_env.sh
make build-tests
make test-unit
make phase28-ts-unit
make phase28-ts-generated
make phase28-ts-integration
make phase28-react-reference
make phase28-confidence
make docs-api
bash tools/ci/run_docs_quality.sh
git diff --check
```

Final closeout should additionally run with the full optional toolchain and
live dependencies required by the TypeScript/React reference lanes.

## 8. Explicit Non-Goals

- Replacing ArlenORM with a TypeScript-first ORM runtime.
- Browser-side database access, offline entity persistence, or client-side unit
  of work semantics.
- Making handwritten TypeScript classes or decorators the canonical schema
  source.
- Bundling React, TanStack Query, Zod, or a Node toolchain into Arlen core.
- Auto-exposing full CRUD APIs for every ORM model without explicit route and
  resource contracts.
- Turning Arlen into a frontend build framework rather than a backend framework
  with strong frontend interop.

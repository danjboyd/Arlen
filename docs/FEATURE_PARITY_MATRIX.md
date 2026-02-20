# Arlen Feature Parity Matrix

Status: Active baseline  
Last updated: 2026-02-20

Related docs:
- `docs/PHASE2_ROADMAP.md`
- `docs/PHASE3_ROADMAP.md`
- `docs/DEPLOYMENT.md`
- `docs/PHASE1_SPEC.md`

## 1. Baseline and Parity Model

- Mojolicious baseline version: `9.42`.
- Baseline freeze date: `2026-02-19`.
- Review cadence: quarterly parity delta review against upstream Mojolicious.
- Parity definition: behavior/capability parity for in-scope features, not syntax-level mirroring.
- API style: Cocoa/GNUstep-first APIs, reusing Mojolicious terminology when it improves clarity.

## 2. Scope Buckets

- In Scope: required for Arlen core roadmap and release planning.
- Deferred: desired for parity/maturity but intentionally scheduled after current core milestones.
- Out of Scope: intentionally excluded from Arlen core; may be plugin/ecosystem concerns later.

## 3. Cocoa-Forward Design Pillars

- `NSError **` subsystem contracts with consistent error domains and metadata.
- Foundation-native request/response/config/data abstractions.
- Deterministic build and runtime behavior across developer and CI environments.
- Protocol/class extension points instead of Perl-specific metaprogramming patterns.
- Compatibility/migration layers are additive and opt-in; Arlen-native APIs remain canonical defaults.

## 4. Mojolicious Capability Classification

| Capability | Bucket | Target Phase | Notes |
| --- | --- | --- | --- |
| Routing (methods, placeholders, wildcards, named routes, URL generation) | In Scope | Phase 1-2 hardening | Baseline exists; continue edge-case hardening. |
| Nested routes, route guards (`under`-style), route conditions | In Scope | Phase 2D | Needed for large app composition and policy gates. |
| Controller/action dispatch model | In Scope | Phase 1 (complete) | Keep Cocoa method contracts explicit. |
| Template rendering, layouts, partials, helpers | In Scope | Phase 1-2D | EOC foundation exists; expand helper/layout ergonomics. |
| Content negotiation and format handling | In Scope | Phase 2D | Needed for mixed HTML/JSON workloads. |
| Sessions/cookies | In Scope | Phase 2B (complete) | Already delivered; keep regression coverage. |
| Request/parameter validation | In Scope | Phase 2C | Primary 2C deliverable. |
| Hooks and plugin extension system | In Scope | Phase 3A | Needed for ecosystem growth. |
| Static file serving | In Scope | Phase 1-2 hardening | Keep baseline, preserve proxy-first production model. |
| CLI commands and app scaffolding | In Scope | Phase 2D-3C | Strengthen default-first developer workflows. |
| Dev server auto-reload (`morbo` analog) | In Scope | Phase 2C | Must remain running on compile/transpile failures. |
| Rich dev exception pages + production-safe errors | In Scope | Phase 2C | Includes structured errors with correlation IDs. |
| Testing ergonomics for HTTP/JSON/DOM flows | In Scope | Phase 2D-3A | Behavior parity benchmarked vs in-scope Mojolicious cases. |
| WebSocket support | In Scope | Phase 3D (complete) | Delivered with controller-driven upgrade contract and websocket frame loop baseline. |
| SSE support | In Scope | Phase 3D (complete) | Delivered with controller `renderSSEEvents:` contract and integration coverage. |
| App mounting/embedding patterns | In Scope | Phase 3D (complete) | Delivered via `mountApplication:atPrefix:` request rewriting/dispatch contract. |
| CGI/PSGI compatibility modes | Out of Scope | N/A | Not aligned with Cocoa/GNUstep compiled deployment model. |

## 5. Competitor-Inspired Capability Classification

| Capability | Source Inspiration | Bucket | Target Phase | Notes |
| --- | --- | --- | --- | --- |
| Convention-heavy generators/scaffolds | Rails, Phoenix | In Scope | Phase 2D-3C | Adoption and onboarding multiplier. |
| API-only mode ergonomics | Rails, FastAPI | In Scope | Phase 2D | Optimize JSON/API-first application defaults. |
| Contract-driven validation helpers | FastAPI | In Scope | Phase 2C | Unified coercion + predictable 4xx error contracts. |
| Schema-first API contracts | FastAPI | In Scope | Phase 3A | Objective-C request/response contracts with deterministic validation and OpenAPI emission. |
| OpenAPI generation and API docs integration | FastAPI | In Scope | Phase 3A | Improves API discoverability and tooling fit. |
| Built-in interactive API docs UI | FastAPI | In Scope | Phase 3B-3C | 3B delivered interactive/viewer UX; 3C completed self-hosted Swagger-style option (`/openapi/swagger`). |
| SDK/export workflow from OpenAPI artifacts | FastAPI ecosystem | In Scope | Phase 3A-3C | Start with artifact export hooks; expand official SDK guidance incrementally. |
| OAuth2 scope/JWT auth ergonomics | FastAPI | In Scope | Phase 3A | First-party auth/scope helper baseline for API teams. |
| Service dependency/lifecycle ergonomics | FastAPI, Phoenix | In Scope | Phase 3A | Explicit startup/shutdown and dependency wiring. |
| Metrics and telemetry primitives | Phoenix | In Scope | Phase 3A | First-class observability posture. |
| Release packaging with `server`/`migrate` workflow | Phoenix | In Scope | Phase 2D-3C | Core compiled-framework deployment contract. |
| Realtime channels/pubsub abstraction | Phoenix | In Scope | Phase 3D (complete) | Delivered with `ALNRealtimeHub` channel fanout abstraction over websocket channel mode. |
| LiveView-like server-driven UI | Phoenix | Deferred | Post-3D exploratory track | Strategic but high-scope; not on core path yet. |
| Background jobs abstraction | Rails | Deferred | Phase 3E candidate | Useful, but not a near-term parity blocker. |
| File attachment abstraction | Rails | Deferred | Phase 3E candidate | Prefer adapter/plugin model first. |
| Mail delivery abstraction | Rails | Deferred | Phase 3E candidate | Plugin-first approach before core inclusion. |
| Built-in caching framework | Rails | Deferred | Phase 3E candidate | Add once core observability/perf gates are mature. |
| I18n framework | Rails | Deferred | Phase 3E candidate | Platform maturity feature. |
| Multi-node clustering primitives | Phoenix | Deferred | Post-3E | Requires stronger distributed runtime contracts. |
| Full ORM as default framework layer | Rails | Deferred | Phase 3B optional track | Keep raw SQL first-class; ORM is additive only. |
| Inbound email framework | Rails | Out of Scope | N/A | Niche workload for Arlen core. |
| Rich-text/CMS layer | Rails | Out of Scope | N/A | Better as ecosystem/package concern. |
| Asset pipeline in core runtime | Rails | Out of Scope | N/A | Prefer integration with external frontend toolchains. |

## 6. GNUstepWeb Migration Compatibility Classification

| Capability | Bucket | Target Phase | Notes |
| --- | --- | --- | --- |
| GSWeb-to-Arlen migration guide + sample migrated app | In Scope | Phase 3C | Completed with `docs/MIGRATION_GSWEB.md` and `examples/gsweb_migration`. |
| Optional WebObjects/GSWeb naming and routing compatibility helpers | In Scope | Phase 3C | Compatibility package only; Arlen-native APIs remain primary. |
| Optional component-layer bridge for reusable view composition | In Scope | Phase 3B-3C | Additive module; no default runtime behavior change. |
| Optional DisplayGroup-style data-controller helper | In Scope | Phase 3B | Delivered in 3B (`ALNDisplayGroup`) for sorting/filtering/batching over adapters. |
| Optional session/page-state compatibility modes | In Scope | Phase 3B-3C | 3B baseline delivered (`ALNPageState`, opt-in); broader migration docs/package work continues in 3C. |
| Full source-level WebObjects API parity | Out of Scope | N/A | Arlen targets migration ergonomics and capability outcomes, not full API mirroring. |

## 7. Boomhauer Compile-Failure UX Contract (Agreed)

1. Default mode: when a reload compile fails, `boomhauer` remains alive and serves a rich error response instead of crashing.
2. Error source coverage: include EOC transpile errors plus Objective-C compile/link errors in one unified response format.
3. Content negotiation: return HTML error pages for browser HTML requests and structured JSON errors for API clients.
4. Recovery behavior: automatic retry on source/template change; no manual process restart required.
5. Signal-to-noise policy: show warnings in collapsed sections; keep hard errors expanded.
6. Diagnostics payload: include stage, command, exit code, file/line/column, and source snippet where available.

## 8. Compiled Deployment Contract (Agreed)

1. Packaging baseline: container-first guidance with first-class VM/systemd documentation.
2. Artifact model: immutable release artifacts for deploy/rollback determinism.
3. Runtime config: plist + environment overrides; no compile-time secrets.
4. Migration policy: explicit `migrate` step in deploy workflow by default.
5. Availability model: zero-downtime rolling reload baseline in `propane`.
6. Health model: readiness and liveness endpoints as first-class production contract.
7. Logging model: structured JSON logs to stdout/stderr by default in production.
8. Rollback model: first-class previous-release switch and restart workflow.

## 9. Refactor Program Required by Parity Goals

1. Error contract unification (Phase 2C): consolidate runtime, transpiler, and compiler error shapes.
2. Developer reload pipeline split (Phase 2C): isolate `boomhauer` supervisor from app child process/build execution.
3. Routing API expansion (Phase 2D): add grouped routes, route guards, and content-negotiation hooks without breaking existing APIs.
4. Extension surface normalization (Phase 3A): formal plugin/hook protocols, lifecycle hooks, and compatibility test harness.
5. Test harness expansion (Phase 2D-3A): fixture-driven parity tests mapped to in-scope capability matrix items.
6. Runtime stage-timing completion (Phase 2C): add deterministic parse and response-write timing stages across dynamic/static/error paths.
7. Perf configuration enforcement (Phase 2C): wire `performanceLogging` into runtime headers/log payload behavior.
8. Perf gate hardening (Phase 2D): make CI/release path run mandatory perf gate and broaden guardrails beyond single endpoint p95.
9. Baseline governance hardening (Phase 2D-3C): baseline metadata, explicit refresh policy, and trend reporting.
10. API-contract/auth platform slice (Phase 3A): schema contracts, OpenAPI/docs UI, and auth scope helpers without compromising explicit controller APIs.
11. GNUstepWeb migration package (Phase 3B-3C): bridge tools/modules/docs with strict opt-in boundaries.

## 10. Test Parity Policy

- Benchmark quality by in-scope behavior coverage and regression detection strength, not by matching raw test counts.
- Maintain a capability-to-tests mapping for every in-scope matrix item.
- Require positive-path and negative-path coverage for each new parity feature.
- Publish parity gap reports each release cycle with explicit defer/out-of-scope rationale.
- Keep performance regression checks mandatory in CI/release workflow, with any bypass requiring explicit, time-bounded rationale.

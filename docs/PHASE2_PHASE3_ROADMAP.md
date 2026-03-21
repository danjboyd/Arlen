# Arlen Phase 2 + Phase 3 Roadmap Index

Status: Historical aggregate index (authoritative current status lives in the individual phase roadmaps; delivery is complete through Phase 19, and Phase 7 is complete for current first-party scope)
Last updated: 2026-03-21

This file is a rolled-up historical index. It preserves the original rollout
sequencing for Phases 2-19, but the current source of truth for status is the
individual `docs/PHASE*_ROADMAP.md` files plus the top-level `README.md`.

This index points to the current roadmap documents:

- `docs/PHASE2_ROADMAP.md`
- `docs/PHASE3_ROADMAP.md`
- `docs/PHASE4_ROADMAP.md`
- `docs/PHASE5_ROADMAP.md`
- `docs/PHASE7_ROADMAP.md`
- `docs/PHASE8_ROADMAP.md`
- `docs/PHASE9_ROADMAP.md`
- `docs/PHASE10_ROADMAP.md`
- `docs/PHASE11_ROADMAP.md`
- `docs/PHASE12_ROADMAP.md`
- `docs/PHASE13_ROADMAP.md`
- `docs/PHASE14_ROADMAP.md`
- `docs/FEATURE_PARITY_MATRIX.md`

## Summary

Phase 2 is focused on adoption-critical capabilities:
- `propane` and production runtime hardening (Phase 2A complete)
- data/security core (Phase 2B complete)
- developer error and validation ergonomics (Phase 2C complete)
- EOC spec-conformance parity tranche (Phase 2D complete: sigil locals + strict locals/stringify)
- generated app/controller boilerplate-reduction tranche (Phase 2D complete: runner entrypoint + route-aware generation + concise render defaults)
- in-scope parity baseline completion for routing/negotiation/API-only flows (Phase 2D complete)
- compiled deployment contract baseline (Phase 2D complete: release artifacts, migrate, health, rollback)
- performance gap closure (Phase 2C/2D complete: stage coverage, runtime toggles, mandatory `make check` perf gate)

Phase 3 is focused on platform maturity:
- observability and plugin/lifecycle extension system (Phase 3A complete)
- API-contract/auth ergonomics for API-first apps (schema contracts + OpenAPI/docs + auth scopes, Phase 3A complete)
- OpenAPI docs UX parity hardening (FastAPI-style interactive API browser, Phase 3B complete)
- OpenAPI docs polish via self-hosted Swagger UI option (Phase 3C complete)
- optional SQL builder and optional GDL2 adapter path (Phase 3B complete baseline)
- optional DisplayGroup/page-state compatibility helpers for migration paths (Phase 3B complete baseline)
- GNUstepWeb migration compatibility track (opt-in bridge, docs, sample migrations)
- release/distribution and documentation maturity (Phase 3C complete baseline)
- advanced performance trend analysis and expanded workload profiles (Phase 3C complete baseline)
- deferred parity capabilities baseline (websocket/SSE/realtime/mounting, Phase 3D complete)
- deferred ecosystem services track (Phase 3E complete baseline)
- ecosystem services follow-on scaffolds (plugin presets + optional job worker runtime contract + concrete Redis cache and filesystem attachment adapters, Phase 3E follow-on complete)
- Phase 3F complete: DX + reliability hardening (`arlen doctor`, toolchain matrix, ALNPg diagnostics, API convenience helpers, static mount ergonomics, concrete jobs/mail adapters, worker supervision baseline)
- Phase 3G complete: SQL builder v2 capability expansion + standalone data-layer reuse packaging (`ArlenData`)
- Phase 3H complete: multi-node clustering/runtime primitives (`/clusterz`, cluster headers, propane cluster controls, and cluster-focused integration validation)
- Phase 4A complete: query IR + safety foundation for expression-capable SQL builder paths
- Phase 4B complete: SQL surface completion for advanced composition/locking/join/window/set clauses
- Phase 4C complete: typed schema codegen and generated table/column helper APIs
- Phase 4D complete: builder execution caching + prepared statement reuse policy + structured/redacted query diagnostics
- Phase 4E complete: SQL conformance matrix + property/long-run regression hardening + migration/deprecation policy finalization

## Rolled-Out Phases (Post-4E)

Phase 4 rollout is complete in `docs/PHASE4_ROADMAP.md`.

Phase 5 rollout is complete in `docs/PHASE5_ROADMAP.md`, including:

- reliability contract mapping for advertised behavior
- external regression intake (competitor test scenarios translated into Arlen-native contract coverage)
- multi-database routing/tooling maturity and SQL-first compile-time typed data contracts

Phase 7 execution/planning is defined in `docs/PHASE7_ROADMAP.md`, including:

- Phase 7A initial runtime hardening slice completed (`docs/PHASE7A_RUNTIME_HARDENING.md`):
  - websocket session backpressure safety boundary
  - deterministic overload diagnostics contract (`503` + `X-Arlen-Backpressure-Reason`)
- Phase 7B initial security-default slice completed (`docs/PHASE7B_SECURITY_DEFAULTS.md`):
  - security profile presets (`balanced`, `strict`, `edge`)
  - fail-fast startup diagnostics for security misconfiguration contracts
- Phase 7C initial observability/operability slice completed (`docs/PHASE7C_OBSERVABILITY_OPERABILITY.md`):
  - request trace/correlation propagation contracts (`X-Correlation-Id`, `X-Trace-Id`, `traceparent`)
  - deterministic JSON health/readiness signal payloads and strict readiness policy switch
  - deploy runbook operability validation script integration
- Phase 7D initial service-durability slice completed (`docs/PHASE7D_SERVICE_DURABILITY.md`):
  - jobs idempotency-key dedupe/release contracts for in-memory and file job adapters
  - cache conformance hardening for zero-TTL persistence and nil-removal semantics
  - retry policy wrappers for mail/attachment adapters with deterministic exhaustion diagnostics
- Phase 7E initial template-pipeline maturity slice completed (`docs/PHASE7E_TEMPLATE_PIPELINE_MATURITY.md`):
  - deterministic transpiler lint diagnostics (`unguarded_include`) and `eocc` warning output contracts
  - expanded multiline/nested/error-shape template fixture coverage
  - include/render-path integration hardening checks and troubleshooting workflow docs
- Phase 7F initial frontend integration starter slice completed (`docs/PHASE7F_FRONTEND_STARTERS.md`):
  - `arlen generate frontend` deterministic starter generation (`vanilla-spa`, `progressive-mpa`)
  - static asset/API wiring templates under `public/frontend/<slug>/`
  - deploy packaging and reproducibility integration checks
- Phase 7G initial coding-agent DX slice completed (`docs/PHASE7G_CODING_AGENT_DX_CONTRACTS.md`):
  - machine-readable JSON contracts for `arlen new`/`arlen generate` workflows
  - deterministic `arlen build`/`arlen check` dry-run planning payloads (`--dry-run --json`)
  - deploy release build planning payloads via `tools/deploy/build_release.sh --dry-run --json`
  - fix-it diagnostics and integration regression harness for coding-agent loops
- Phase 7H initial distributed-runtime depth slice completed (`docs/PHASE7H_DISTRIBUTED_RUNTIME_DEPTH.md`):
  - quorum-gated readiness contract (`readinessRequiresClusterQuorum` + observed/expected node controls)
  - expanded `/clusterz` quorum + coordination capability-matrix payload
  - deterministic cluster diagnostics headers (`X-Arlen-Cluster-Status`, observed/expected node counts)
- Phase 7 closeout for current first-party scope:
  - follow-on runtime/security/operability and ecosystem-depth work landed across later hardening phases
  - current authoritative closeout status is `docs/PHASE7_ROADMAP.md` (`Complete for current first-party scope`)

Phase 8 execution/planning is defined in `docs/PHASE8_ROADMAP.md`, including:

- Phase 8A complete:
  - EOC keypath-local support (`$identifier(.identifier)*`)
  - centralized value-transformer registry for schema/runtime conversion paths
  - unified field-error envelope contract with keypath-ready field semantics
- Phase 8B complete:
  - startup route compilation and fail-fast signature/schema readiness validation
  - cached dispatch invocation metadata to reduce runtime signature checks
- explicitly deferred (future consideration, out-of-scope for 8A/8B):
  - KVO-driven incremental server-render patch streaming
  - NSUndoManager-style command/audit/undo architecture
  - NSPredicate/NSSortDescriptor-primary query surface

Phase 9 execution/planning is defined in `docs/PHASE9_ROADMAP.md`, including:

- Phase 9A complete:
  - recursive HTML docs publishing pipeline and local docs serving command
- Phase 9B complete:
  - generated API reference from public umbrella headers with method-level purpose/usage guidance
- Phase 9C complete:
  - track-based getting-started docs (quickstart/api/html/data-layer)
- Phase 9D complete:
  - Arlen-for-X migration guide suite (Rails, Django, Laravel, FastAPI, Express/NestJS, Mojolicious)
- Phase 9E complete:
  - documentation policy quality-gate updates for API docs regeneration and HTML validation
  - CI-enforced docs gate (`make ci-docs`, `tools/ci/run_docs_quality.sh`, `docs-quality` workflow)
- Phase 9F complete:
  - inline concurrency/backpressure hardening gate expansion (HTTP queueing, websocket/realtime backpressure, mixed lifecycle stress)
- Phase 9G complete:
  - propane worker lifecycle + signal durability regressions and deterministic lifecycle diagnostics contract
- Phase 9H complete:
  - sanitizer/race-detection maturity: suppression registry policy + validation, expanded sanitizer route/data-layer coverage, TSAN artifact retention, and Phase 9H confidence artifacts
- Phase 9I complete:
  - deterministic runtime seam fault-injection harness and artifact pack (HTTP parser/dispatcher, websocket lifecycle, runtime stop/start boundaries) with seed-replay controls and CI/local command entrypoint
- Phase 9J complete:
  - enterprise release certification pack generation, threshold/fail-criteria enforcement, known-risk register validation, and release-script certification gating for release candidates

Phase 10 execution is tracked in `docs/PHASE10_ROADMAP.md` (complete; 10A/10B/10C/10D/10E/10F/10G/10H/10I/10J/10K/10L/10M complete), focused on:

- yyjson-backed JSON serialization migration with parity-focused testing before cutover
- runtime + CLI/tooling JSON call-site migration behind a deterministic backend switch
- release confidence gates for JSON behavior equivalence and performance deltas

Phase 11 execution/planning is defined in `docs/PHASE11_ROADMAP.md`, focused on:

- security and protocol-correctness hardening on session/bearer-auth/header/request-boundary/websocket/filesystem/proxy trust boundaries
- OpenBSD-style correctness tightening for ambiguous transfer semantics, websocket origin policy, attachment containment, private on-disk adapter permissions, and deterministic rejection behavior
- expanded second-pass verification plan covering duplicate `Content-Length`/`Transfer-Encoding` probes, websocket origin cases, traversal/symlink fixtures, sanitizer matrix growth, and live adversarial traffic probes

Current delivery state:

- Phase 11A complete: session/bearer secret startup validation, session-cookie cryptography hardening, and CSRF header/body-first enforcement
- Phase 11B complete: response-header validation/canonicalization plus fail-closed legacy framing rejection for duplicate `Content-Length`, unsupported `Transfer-Encoding`, and mixed `Content-Length` + `Transfer-Encoding`
- Phase 11C complete: websocket handshake validation, optional `Origin` allowlist enforcement, unmasked-frame rejection, and stalled-frame timeout closure
- Phase 11D complete: static/attachment filesystem confinement, strict attachment IDs, symlink-safe file access, and private file-backed adapter permissions
- Phase 11E complete: trusted proxy CIDR boundary enforcement and text-log control-character escaping
- Phase 11F complete: Phase 11 protocol adversarial corpus, deterministic fuzz/live probes, and sanitizer confidence artifact lanes

Phase 12 execution is defined in `docs/PHASE12_ROADMAP.md`, with current delivery state:

- Phase 12A complete: session-native auth-assurance inspection, route-level step-up policy, session rotation helpers, and deterministic HTML/API step-up rejection behavior
- Phase 12B complete: `ALNTOTP`, `ALNRecoveryCodes`, and session-upgrade helpers for local MFA flows
- Phase 12C complete: `ALNWebAuthn` registration/assertion helpers with origin/RP/challenge/sign-count verification and AAL2 session upgrade integration
- Phase 12D complete: `ALNOIDCClient` authorization-code + PKCE helpers, callback validation, token parsing, HS256/RS256 ID-token verification, and normalized provider identity output
- Phase 12E complete: `ALNAuthProviderPresets`, `ALNAuthProviderSessionBridge`, deterministic provider config merging, and provider-login session bootstrap hooks that preserve local AAL2 step-up policy
- Phase 12F complete: OIDC hostile-input fixture coverage, `OIDCClientTests`, `auth_primitives` sample app, and `make phase12-confidence` confidence artifacts under `build/release_confidence/phase12`

Phase 13 execution is defined in `docs/PHASE13_ROADMAP.md`, with current delivery state:

- a first-class Objective-C-native module system layered above plugins
- source-vendored, bundle-ready module packaging/config/migration/override contracts
- first-party optional `auth` and `admin-ui` modules with complete product flows
- a metadata-driven admin resource registry for app-owned backoffice resources
- one auth/admin domain contract supporting both EOC-rendered HTML and SPA-friendly JSON surfaces without bundling a React frontend
- sample app, module docs, and `make phase13-confidence` confidence artifacts

Phase 14 execution is defined in `docs/PHASE14_ROADMAP.md`, with current delivery state:

- Phase 14A complete:
  - first-party `jobs` module productization on top of the Phase 3 job adapter and Phase 13 module system
  - deterministic job definitions, schedule providers, protected `/jobs` HTML, and `/jobs/api` JSON/OpenAPI operator routes
- Phase 14B complete:
  - scheduler execution, dead-letter replay, leased-job inspection, and default-queue pause/resume flows through the shared worker contract
- Phase 14C complete:
  - first-party `notifications` foundation on top of mail + jobs with `/notifications/api` queue/definitions/outbox/inbox routes
- Phase 14D complete:
  - notifications inbox/outbox/preferences plus preview/test-send and shared admin resources
- Phase 14E complete:
  - first-party `storage` foundation with signed upload/download tokens and deterministic collection registration
- Phase 14F complete:
  - direct-upload, variant processing, storage-management HTML/JSON surfaces, and shared admin resource integration
- Phase 14G complete:
  - first-party `ops` dashboard and `/ops/api` runtime diagnostics/OpenAPI summary surface
- Phase 14H complete:
  - first-party `search` module with job-backed reindexing, admin auto-resource indexing, and ops/admin visibility
- Phase 14I complete:
  - sample app, module docs, and `make phase14-confidence` artifact gate

Phase 15 execution is defined in `docs/PHASE15_ROADMAP.md`, with current delivery state:

- explicit `headless`, `module-ui`, and `generated-app-ui` auth UI ownership modes shipped
- app-owned guest-shell layout/context hook and partial override model shipped
- `arlen module eject auth-ui --json` shipped for `generated-app-ui`
- docs, examples, focused HTTP coverage, and `make phase15-confidence` shipped

Phase 16 execution is defined in `docs/PHASE16_ROADMAP.md`, with delivered state:

- maturity pass across `jobs`, `notifications`, `storage`, `search`, `ops`, and `admin-ui`
- durable module-owned state where runtime snapshots are no longer sufficient
- stronger operator/admin ergonomics, drilldowns, and export/bulk-action flows
- docs, examples, and `make phase16-confidence` as the closeout gate

Scope guardrails remain unchanged:
- admin/backoffice and full account-product surfaces remain outside Arlen core and are expected to ship as optional modules/products.
- full ORM as default layer remains "Maybe Someday", not a Phase 5 default requirement.

Maybe Someday backlog:
- LiveView-like server-driven UI
- full ORM as default framework layer

## Data Layer Direction

- Raw SQL remains first-class in Arlen.
- SQL abstraction is additive and optional.
- GDL2 is scoped as a compatibility adapter path, not a core dependency.

## Parity Direction

- Arlen parity targets behavior/capability outcomes for in-scope features.
- Arlen remains Cocoa-forward and GNUstep-native in API design.
- Syntax-level mirroring with Mojolicious is optional and only used when it improves clarity.

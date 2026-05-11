# Arlen Phase 16 Roadmap

Status: Complete (`16A-16C` complete on 2026-03-10; `16D-16G` complete on 2026-03-11)
Last updated: 2026-03-11

Related docs:
- `docs/MODULES.md`
- `docs/JOBS_MODULE.md`
- `docs/NOTIFICATIONS_MODULE.md`
- `docs/STORAGE_MODULE.md`
- `docs/OPS_MODULE.md`
- `docs/SEARCH_MODULE.md`
- `docs/ADMIN_UI_MODULE.md`
- `docs/PHASE14_ROADMAP.md`
- `docs/PHASE15_ROADMAP.md`
- `docs/STATUS.md`

## 1. Objective

Run a maturity pass across the first-party module product layer shipped in
Phases 13-15 so Arlen closes the largest remaining product gaps relative to the
best parts of Rails, Laravel, Django, Phoenix, and Oban-style ecosystems.

Phase 16 does not add a new domain family. It deepens the modules Arlen now
already ships:

- `jobs`
- `notifications`
- `storage`
- `search`
- `ops`
- `admin-ui`

The target is a stronger default-first bar for real applications:

- durable state where runtime-only snapshots are no longer sufficient
- richer operator ergonomics and drilldowns
- better multi-surface parity between HTML, JSON, and automation use cases
- cleaner extension seams for apps and future vendor-specific add-ons

## 1.1 Why Phase 16 Exists

Phase 14 gave Arlen breadth across common product modules. Phase 15 gave `auth`
the first deliberate maturation pass with clear UI ownership modes, examples,
and confidence artifacts.

The remaining module layer still has known maturity gaps called out in the
current docs:

- `jobs` still has limited queue controls and no dedicated operator metadata
- `notifications` still uses runtime-managed inbox/outbox/preference state
- `storage` still uses runtime-managed catalog/session state and a minimal
  variant processor
- `search` still uses runtime-managed indexed documents with a simple query
  model
- `ops` is summary-oriented and intentionally shallow
- `admin-ui` is functional, but still lighter than the best backoffice products

Phase 16 addresses those gaps directly instead of widening the module catalog.

## 1.2 Reference Bar

Phase 16 uses competing frameworks as quality references, not as API
compatibility requirements:

- `jobs`: Active Job, Horizon, and Oban-style operator ergonomics
- `notifications`: Laravel-style multi-channel and durable notification flows
- `storage`: Active Storage and Laravel-style metadata, previews, and tokenized
  file access
- `search`: Scout-style indexing lifecycle and stronger query/result quality
- `ops`: Pulse and LiveDashboard-style drilldown and historical signal views
- `admin-ui`: Django admin-style filter/action/pagination productivity

Arlen should adopt the useful product ideas while preserving its own
Objective-C-native module contracts.

## 1.3 Sequencing

Execution order is intentional:

1. `jobs` first, because later module maturity depends on stronger queue and
   operator contracts
2. `notifications` and `storage` next, because both depend on durable
   background processing and state
3. `search` after that, because index syncing and reindex safety depend on the
   matured jobs and admin/resource substrate
4. `ops` after the module runtime surfaces are richer, so it can visualize real
   history rather than only snapshots
5. `admin-ui` polish last, because it should productize the improved resource
   surfaces rather than force earlier abstractions prematurely
6. docs/examples/confidence closeout at the end

## 2. Design Principles

- Keep Phase 16 module-first, not core-first.
- Preserve optionality:
  - every module remains installable and removable independently
  - no Phase 16 feature should require all modules to be present
- Prefer durable module-owned state when product maturity requires it.
- Keep one domain contract with multiple surfaces where appropriate:
  - HTML/EOC-first for default apps
  - JSON/OpenAPI for SPAs and automation
- Prefer explicit provider/hook contracts over hidden discovery.
- Keep local-development defaults strong:
  - built-in adapters must still work
  - vendor-specific engines remain additive
- Treat competing frameworks as product-bar references, not as a mandate to
  reproduce their class names or DSLs.
- Keep auth and admin protection aligned with the Phase 13/15 contracts rather
  than inventing one-off policy models per module.

## 3. Scope Summary

1. Phase 16A: jobs maturity pass.
2. Phase 16B: notifications durability and channel maturity.
3. Phase 16C: storage durability and media maturity.
4. Phase 16D: search engine and indexing maturity.
5. Phase 16E: ops drilldown and historical visibility.
6. Phase 16F: admin-ui productivity maturity.
7. Phase 16G: docs, examples, and `phase16-confidence`.

## 4. Scope Guardrails

- Do not move these products back into Arlen core.
- Do not introduce a default ORM or model-layer dependency.
- Do not require React/Vue/LiveView-style frontend bundles for module maturity.
- Do not create cloud-vendor lock-in in the first-party contract:
  - storage must still work with local/file adapters
  - search must still work with an in-tree default engine
  - notifications must still work without a SaaS provider
- Do not make `ops` a cluster control plane in this phase.
- Do not widen Phase 16 into billing, organizations, invitations, or other new
  product domains.
- Keep existing module route contracts stable unless a documented compatibility
  alias or migration path is provided.

## 5. Milestones

## 5.1 Phase 16A: Jobs Maturity Pass

Status: Complete (2026-03-10)

Deliverables:

- Extend job-definition metadata with richer operator-facing semantics:
  - max attempts
  - backoff strategy metadata
  - queue selection and queue priority metadata
  - tags/labels for operator grouping
  - stronger uniqueness/idempotency semantics
- Add module-owned operator metadata for:
  - job run history
  - failure history
  - queue state beyond the current `default`-only pause/resume model
- Expand queue operations to support more than one queue deterministically.
- Add richer worker/scheduler visibility for both HTML and JSON surfaces:
  - recent runs
  - failure counts
  - queue-level depth and paused/draining state
  - tag-aware inspection where available
- Keep the existing adapter-backed execution model, but productize the operator
  metadata needed for a serious queue dashboard.

Acceptance (required):

- queue pause/resume/replay contracts work for multiple named queues
- retry/backoff/tag metadata is deterministic and surfaced in JSON/OpenAPI
- operator history survives runtime restarts when module storage is enabled
- integration coverage proves notifications, storage, and search can all depend
  on the matured jobs contract without custom queue glue

## 5.2 Phase 16B: Notifications Durability + Channel Maturity

Status: Complete (2026-03-10)

Deliverables:

- Replace runtime-only inbox/outbox/preferences state with dedicated
  module-owned persistence.
- Add richer delivery-status tracking:
  - queued
  - delivered
  - failed
  - suppressed
- Introduce a stronger channel contract:
  - keep email and in-app as first-party defaults
  - add a first-party webhook channel
  - keep room for future SMS/chat vendor modules without hard-coding them now
- Add per-channel queue/routing and retry policy metadata.
- Wire realtime inbox fanout so in-app delivery can update active sessions.
- Expand preview/test-send/audit flows so the same notification contract drives:
  - preview
  - durable delivery
  - admin inspection
  - recipient preference evaluation

Acceptance (required):

- delivered inbox/outbox entries and preferences survive restarts
- preview and test-send reuse the same render/delivery contract as queued sends
- realtime in-app delivery updates are observable through the shipped runtime
- unsupported channels or policy violations fail closed before enqueue

## 5.3 Phase 16C: Storage Durability + Media Maturity

Status: Complete (2026-03-10)

Deliverables:

- Replace runtime-only object and upload-session catalogs with dedicated
  module-owned persistence.
- Add a richer analyzer/metadata pipeline for stored objects, including:
  - normalized content metadata
  - checksums
  - image/media dimensions where supported
  - previewability/variant capability flags
- Improve variant and preview processing:
  - explicit variant definitions and readiness states
  - real transform/representation hooks instead of copy-only behavior
  - preview support for images first, with extensible hooks for PDFs/video later
- Add stronger lifecycle support:
  - retention/cleanup jobs
  - object deletion audit
  - upload finalization and expiration cleanup
- Add capability-aware storage adapter metadata for:
  - temporary URL support
  - scoped/read-only behavior
  - mirror-style write replication where adapters opt in

Acceptance (required):

- object, upload-session, and variant state survives restarts
- analyzer output is deterministic and available in HTML/JSON/admin surfaces
- signed download and upload flows respect expiry and collection policy
- variant regeneration and failed-processing recovery are integration-tested

## 5.4 Phase 16D: Search Engine + Indexing Maturity

Status: Complete (2026-03-11)

Deliverables:

- Replace runtime-only indexed-document snapshots with dedicated module-owned
  index storage.
- Introduce a stronger search engine contract:
  - keep an in-tree default database-backed engine
  - allow future external engines through an explicit provider boundary
- Add incremental sync contracts for resource create/update/delete events.
- Add safer reindex lifecycle behavior:
  - full rebuilds
  - generation/version tracking
  - swap-style activation so rebuilds do not drop active query behavior
- Expand query/result quality:
  - deterministic filter and sort metadata
  - pagination contracts
  - weighted fields
  - snippets/highlights when supported by the current engine
- Strengthen admin/ops integration for reindex status, index generation, and
  failure visibility.

Acceptance (required):

- incremental sync and full reindex both work through the same job-backed
  contract
- filter/sort/pagination behavior fails closed on unsupported inputs
- search remains available while a full rebuild is running
- admin and ops surfaces expose index generation state and reindex failures

## 5.5 Phase 16E: Ops Drilldown + Historical Visibility

Status: Complete (2026-03-11)

Deliverables:

- Add module-owned historical snapshots for operational summaries so the ops
  dashboard can show recent history instead of only current state.
- Expand `/ops` and `/ops/api/...` with drilldown views for:
  - jobs
  - notifications
  - storage
  - search
- Add configurable card/widget seams so apps and modules can contribute
  operator-facing summaries without patching the core dashboard.
- Add stronger status shaping:
  - healthy
  - degraded
  - failing
  - informational
- Keep the ops module additive to lower-level endpoints rather than replacing
  them.

Acceptance (required):

- ops can display both current and recent historical state for shipped modules
- drilldown links/actions are deterministic and protected by the shared
  operator/admin policy
- card-provider contracts are documented and fail closed on malformed payloads
- ops remains useful even when only a subset of Phase 14 modules is installed

## 5.6 Phase 16F: Admin UI Productivity Maturity

Status: Complete (2026-03-11)

Deliverables:

- Add first-class bulk-action support for resource collections.
- Add export contracts for list results:
  - JSON
  - CSV
- Expand resource metadata for stronger list ergonomics:
  - pagination defaults
  - richer filter descriptors
  - date/range filters
  - default and optional sorts
- Add stronger form/update metadata so resources can describe:
  - typed fields
  - choices
  - relationship/autocomplete hooks where the provider can supply them
- Tighten module integration so `notifications`, `storage`, and `search`
  resources can expose richer shared admin actions without one-off templates.

Acceptance (required):

- a resource can expose bulk actions and exports without bespoke route wiring
- list/filter/sort/pagination metadata is stable across HTML and JSON surfaces
- typed field metadata and choice/autocomplete hooks are documented and
  regression-tested
- the shipped admin HTML becomes meaningfully more productive without requiring
  a frontend framework rewrite

## 5.7 Phase 16G: Docs + Examples + Confidence

Status: Complete (2026-03-11)

Deliverables:

- Update all affected module docs and the top-level module onboarding path.
- Add at least one canonical example app showing the matured module stack
  working together.
- Add `make phase16-confidence` with artifacts that cover:
  - jobs multi-queue/operator flows
  - notifications durable delivery and preferences
  - storage upload/analyzer/variant flows
  - search incremental sync and full reindex
  - ops drilldown/history
  - admin bulk actions/exports/filter ergonomics
- Add release-confidence summaries similar to earlier phase packs.

Acceptance (required):

- docs describe the new persistence and operator contracts clearly
- example coverage proves the matured module surfaces compose in one app
- `phase16-confidence` produces deterministic artifacts and clear skip/fail
  semantics for environment-sensitive checks

## 6. Completion Criteria

Phase 16 is complete when:

1. the core first-party module set no longer relies on runtime-only state for
   product-critical inbox, storage, search, and operator views
2. `jobs`, `notifications`, `storage`, and `search` expose a stronger product
   bar without breaking local-development defaults
3. `ops` can show historical and drilldown information rather than only a
   top-level summary
4. `admin-ui` can handle common bulk/filter/export workflows as a first-class
   product, not only as a thin metadata shell
5. the upgraded module stack is documented, example-backed, and covered by
   `phase16-confidence`

## 7. Non-Goals

- new first-party domains outside the existing module set
- a bundled SPA admin or operator frontend
- full ORM-driven admin scaffolding
- vendor-specific SaaS integrations as the default product path
- distributed cluster orchestration or auto-healing control planes
- replacing the current module provider model with global convention discovery

## 8. Expected Outcome

After Phase 16, Arlen should still feel like the same framework, but the
first-party module layer should look less like a promising baseline and more
like a deployable default product stack:

1. queues/operators feel credible for real workloads
2. notifications and storage have durable, inspectable lifecycle state
3. search supports safer indexing and better query/result ergonomics
4. ops becomes a useful day-two dashboard instead of only a status summary
5. admin-ui becomes a practical default backoffice for common cases

That is the next maturity bar after Phase 15.

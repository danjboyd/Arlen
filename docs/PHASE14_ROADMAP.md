# Arlen Phase 14 Roadmap

Status: Complete
Last updated: 2026-03-10

Related docs:
- `docs/PHASE13_ROADMAP.md`
- `docs/PHASE3_ROADMAP.md`
- `docs/PHASE7C_OBSERVABILITY_OPERABILITY.md`
- `docs/ECOSYSTEM_SERVICES.md`
- `docs/PHASE2_PHASE3_ROADMAP.md`
- `docs/GETTING_STARTED.md`

## 1. Objective

Add the next five high-value first-party modules on top of the Phase 13 module system:

- `jobs`
- `notifications`
- `storage`
- `ops`
- `search`

Phase 14 focuses on productizing service areas Arlen already has partial core substrate for:

- job queue and scheduler workflows
- mail and user/application notifications
- uploads, attachments, and media handling
- operational visibility and protected runtime dashboards
- search and indexing for app-owned resources

Phase 14 keeps the same boundary established in Phase 13:

- core Arlen owns low-level runtime and adapter contracts
- optional modules own default schema, routes, templates, assets, dashboards, and upgradeable product behavior

## 1.1 Entry Context

Phase 14 starts from the current tree reality:

1. Phase 3 already established plugin-first service adapters for:
   - jobs
   - cache
   - i18n
   - mail
   - attachments
2. Phase 3 follow-on also established:
   - optional worker runtime contracts for jobs
   - concrete mail and attachment adapters
   - realtime/pubsub substrate that notifications can reuse later
3. Phase 7C and later phases added the first observability/operability baseline:
   - request correlation and trace metadata
   - health/readiness JSON payloads
   - metrics exposure and deploy operability checks
4. Phase 13 now provides the missing product layer:
   - module manifests
   - module config and migrations
   - module assets/templates
   - module install/upgrade lifecycle
   - first-party `auth` and `admin-ui`
5. The next missing layer is not more core substrate; it is first-party products that make common app concerns deployable with minimal boilerplate.

## 1.2 Current Delivery State

- `14A` complete: first-party `jobs` module foundation shipped.
- `14B` complete: scheduler, queue operations, protected `/jobs` HTML, and `/jobs/api` JSON/OpenAPI surface shipped.
- `14C` complete: first-party `notifications` foundation on top of jobs + mail shipped.
- `14D` complete: notification inbox/outbox HTML, preview/test-send flows, preferences, and `admin-ui` resources shipped.
- `14E` complete: first-party `storage` collection/runtime foundation and signed token flows shipped.
- `14F` complete: direct-upload flows, variant jobs, storage-management HTML/JSON surfaces, and `admin-ui` storage resources shipped.
- `14G` complete: first-party `ops` module shipped with protected dashboard, JSON diagnostics, and OpenAPI summary surface.
- `14H` complete: first-party `search` module shipped with job-backed reindexing, admin auto-resource indexing, and ops/admin visibility.
- `14I` complete: Phase 14 docs, sample app, and `phase14-confidence` artifact gate shipped.

## 2. Design Principles

- Treat Phase 14 as module-first, not core-first:
  - prefer building on `ALNJobAdapter`, `ALNMailAdapter`, `ALNAttachmentAdapter`, realtime, metrics, and the Phase 13 module loader
  - only add new core contracts when a module cannot be made deterministic without them
- Keep each module installable, optional, and upgradeable.
- Prefer one domain contract with two surfaces where appropriate:
  - HTML/EOC-first out of the box
  - stable JSON surface for SPA/API consumers
- Preserve the Objective-C-native module style introduced in Phase 13:
  - protocol-based capabilities
  - plist-backed manifests
  - bundle-scoped templates/assets
  - deterministic override precedence
- Default-first matters:
  - local development should work with built-in/default adapters
  - production-grade adapters remain explicit and pluggable
- Avoid vendor lock-in in first-party contracts:
  - no Stripe-only billing-style coupling here
  - no Elasticsearch-only search contract
  - no cloud-storage-only upload contract
- Build dashboards and admin integration on shared module/resource contracts rather than one-off route trees.

## 3. Scope Summary

1. Phase 14A: jobs module foundation.
2. Phase 14B: jobs scheduler, worker UX, and queue operations surface.
3. Phase 14C: notifications module foundation.
4. Phase 14D: notifications channels, previews, preferences, and admin integration.
5. Phase 14E: storage module foundation.
6. Phase 14F: uploads, media variants, and storage-management UX.
7. Phase 14G: ops module foundation and protected runtime dashboard.
8. Phase 14H: search module foundation and admin/search integration.
9. Phase 14I: hardening, docs, sample app, and confidence artifacts.

Execution order is intentional:

- `jobs` first, because later modules depend on scheduled/background work
- `notifications` and `storage` next, because they are common app needs and depend on jobs for async delivery/processing
- `ops` after those, so the dashboard can introspect real module workloads
- `search` last, because it benefits from jobs for indexing and from admin integration for resource registration/inspection

## 4. Scope Guardrails

- Do not reopen the Phase 3 adapter abstractions unless a specific deterministic contract gap is discovered.
- Do not move these product surfaces back into Arlen core.
- Keep multi-tenant/org/billing/invitation products out of Phase 14.
- Keep vendor-specific integrations additive:
  - Search should work with database-backed indexing first
  - Storage should work with file/local adapters first
  - Notifications should work with in-memory/mail adapters first
- Protect privileged module UIs with auth contracts:
  - `jobs`, `ops`, and storage-management surfaces should require authenticated admin/operator access
- Prefer app-owned registration over hidden runtime discovery:
  - search indexes
  - notification channels
  - storage collections/policies
  - job definitions and schedules
- Ship sample HTML surfaces where they materially improve adoption, but keep JSON/OpenAPI surfaces available for SPA and automation use cases.

## 5. Milestones

## 5.1 Phase 14A: Jobs Module Foundation

Status: Complete

Deliverables:

- Add a first-party `jobs` module on top of `ALNJobAdapter` and `ALNJobWorker`.
- Introduce explicit job-definition registration for app/module code:
  - stable job identifier
  - payload schema/validation
  - retry policy metadata
  - queue/priority metadata
  - idempotency-key support
- Add module-owned config defaults for:
  - queue namespaces
  - retention windows
  - retry backoff policy
  - dead-letter behavior
  - worker/scheduler controls
- Add job serialization and validation contracts suitable for:
  - manual enqueue
  - scheduled enqueue
  - admin/operator replay
  - API-triggered enqueue
- Keep persistence adapter-backed in this slice; dedicated module-owned job metadata tables remain optional follow-on work if a deterministic gap appears later.

Delivered:

- vendored `modules/jobs/` with `ALNJobsJobDefinition`, `ALNJobsJobProvider`, and `ALNJobsScheduleProvider`
- deterministic config defaults, job metadata normalization, payload validation, and schedule normalization
- runtime APIs for enqueue, scheduler runs, worker runs, pending/leased/dead-letter inspection, and replay/pause/resume flows

Acceptance (required):

- `tests/unit/Phase14ATests.m`:
  - job-definition registration order is deterministic
  - invalid payloads fail before enqueue
  - retry/idempotency metadata is stable and introspectable
- `tests/integration/Phase14JobsNotificationsIntegrationTests.m`:
  - a module-installed app can register a job and enqueue it without manual queue wiring
  - jobs foundation composes cleanly with the notifications foundation in one application runtime

## 5.2 Phase 14B: Jobs Scheduler + Worker UX + Queue Operations

Status: Complete

Deliverables:

- Add a scheduler surface for cron-like and interval-like definitions.
- Add first-party worker lifecycle commands/workflows for module-installed apps:
  - run due jobs
  - inspect leased jobs
  - inspect dead-letter jobs
  - replay dead-letter jobs
  - pause/resume queues where supported
- Add a protected HTML jobs dashboard and a JSON surface:
  - queue depth
  - recent failures
  - lease age
  - run history
  - dead-letter replay controls
- Add OpenAPI output for the jobs JSON surface.
- Keep `jobs` aligned with the shared auth/admin contracts from Phase 13 so `admin-ui` embedding can remain additive rather than required for the module to function.

Delivered:

- cron-like and interval-like scheduler execution through the shared jobs runtime
- protected `/jobs` HTML dashboard plus `/jobs/api/...` JSON endpoints for queue/operator flows
- OpenAPI registration for the jobs JSON surface
- dead-letter replay, leased-job inspection, and default-queue pause/resume support

Acceptance (required):

- `tests/unit/Phase14BTests.m`:
  - schedule definitions normalize deterministically
  - replay/pause/resume contracts fail closed on unsupported adapters
- `tests/integration/Phase14JobsNotificationsIntegrationTests.m`:
  - scheduled and manual jobs execute through the same worker/runtime contract
  - queue-backed module behavior remains deterministic when jobs and notifications are installed together

## 5.3 Phase 14C: Notifications Module Foundation

Status: Complete

Deliverables:

- Add a first-party `notifications` module that uses:
  - `ALNMailAdapter` for email delivery
  - jobs for async delivery
  - optional realtime hooks for in-app delivery fanout
- Introduce explicit notification-definition registration:
  - notification identifier
  - supported channels
  - recipient resolution contract
  - template/context schema
  - delivery policy metadata
- Keep the 14C slice JSON-first and runtime-driven:
  - durable inbox/outbox persistence can layer on in 14D
  - richer template packs/previews can layer on in 14D
- Add config defaults for sender identity, queue selection, and retention.

Delivered:

- vendored `modules/notifications/` with `ALNNotificationDefinition` and `ALNNotificationProvider`
- async notification dispatch via the system `notifications.dispatch` job registered into the jobs module runtime
- `/notifications/api/...` routes for definitions, queueing, outbox inspection, and inbox inspection
- deterministic notification metadata normalization and requested-channel validation

Acceptance (required):

- `tests/unit/Phase14CTests.m`:
  - notification registration is deterministic
  - unsupported channel selections fail closed
  - template/context validation is deterministic
- `tests/integration/Phase14JobsNotificationsIntegrationTests.m`:
  - module-installed app can queue and deliver a first-party email notification
  - in-app inbox state is visible through the shared notification contract in the same runtime

## 5.4 Phase 14D: Notifications Channels + Previews + Preferences + Admin Integration

Status: Complete

Deliverables:

- Add default channel product flows:
  - email delivery
  - in-app inbox delivery
  - optional realtime fanout for live inbox refresh
- Add notification preview and test-send tooling for development and admin use.
- Add per-user preference hooks for channel enable/disable and digest-style policy later.
- Add protected HTML and JSON surfaces for:
  - inbox
  - outbox/delivery history
  - preview/test-send
  - per-user preferences
- Integrate notification history and preview into `admin-ui`.

Delivered:

- expanded the first-party `notifications` module with default email and in-app delivery product flows
- added preview and test-send runtime APIs that reuse the same definition/payload contract as actual delivery
- added per-recipient preference persistence plus the optional `ALNNotificationPreferenceHook` seam
- shipped protected HTML routes under `/notifications/...` for inbox, preferences, outbox, preview, and test-send flows
- shipped protected JSON routes under `/notifications/api/...` for definitions, inbox, queueing, preview, test-send, outbox, and preferences
- added `admin-ui` resources for notification outbox history and notification-definition inspection

Acceptance (required):

- `tests/unit/Phase14DTests.m`:
  - preview rendering and actual delivery share one template contract
  - preference rules are evaluated deterministically
- `tests/integration/Phase14NotificationsIntegrationTests.m`:
  - admin can preview and test-send a notification
  - authenticated user can inspect inbox state over HTML and JSON

## 5.5 Phase 14E: Storage Module Foundation

Status: Complete

Deliverables:

- Add a first-party `storage` module on top of `ALNAttachmentAdapter`.
- Introduce explicit storage-collection registration:
  - collection identifier
  - accepted content types
  - size limits
  - retention policy
  - visibility/access policy
  - variant generation rules where applicable
- Add module-owned metadata schema for stored objects, upload sessions, and policy evaluation.
- Add signed upload/download URL or token contracts suitable for browser and API clients.
- Add config defaults for local development roots, public/private collections, and cleanup windows.

Delivered:

- vendored `modules/storage/` with `ALNStorageCollectionDefinition` and `ALNStorageCollectionProvider` contracts on top of `ALNAttachmentAdapter`
- added deterministic collection metadata normalization for content-type limits, size limits, retention metadata, visibility, and variant definitions
- added runtime-managed object catalog, upload-session state, and signed upload/download token flows through `ALNSecurityPrimitives`
- shipped runtime APIs for collection registration, upload-session creation, direct object persistence, signed download-token issuance, object deletion, and dashboard summaries
- registered default `admin-ui` resource metadata so installed apps can browse storage objects without custom admin wiring

Acceptance (required):

- `tests/unit/Phase14ETests.m`:
  - collection registration and policy metadata are deterministic
  - invalid content-type/size requests fail before persistence
- `tests/integration/Phase14StorageIntegrationTests.m`:
  - module-installed app can register a collection and store/fetch an object without custom persistence code
  - signed URL/token flows fail closed when tampered or expired

## 5.6 Phase 14F: Uploads + Media Variants + Storage Management UX

Status: Complete

Deliverables:

- Add direct-upload flows for browser/SPAs using the shared storage contract.
- Add first-party management UX for:
  - upload status
  - object listing/search/filter
  - object detail and metadata
  - delete/replace
  - variant/preview visibility
- Add image/media variant support where the adapter or processor permits it:
  - thumbnails/previews
  - normalized metadata extraction
  - async variant generation via jobs
- Add HTML and JSON surfaces plus OpenAPI for upload and management flows.
- Integrate storage collections into `admin-ui` through shared resource metadata.

Delivered:

- added protected HTML storage-management routes under `/storage/...` for dashboard, collection listing, object detail, delete, and variant-regeneration flows
- added `/storage/api/...` JSON/OpenAPI routes for collections, object inspection, upload-session creation, browser-style direct upload, delete, variant regeneration, and download-token issuance
- added async variant generation through the shared jobs runtime via `storage.generate_variant`
- added signed download handling under `/storage/api/download/:token` so browser and API clients can fetch stored objects with token-based access
- integrated storage records into `admin-ui` with list/detail metadata plus `delete` and `regenerate_variants` actions

Acceptance (required):

- `tests/unit/Phase14FTests.m`:
  - variant definitions normalize deterministically
  - direct-upload session state rejects tamper/expiry deterministically
- `tests/integration/Phase14StorageIntegrationTests.m`:
  - browser-style direct upload works against the JSON contract
  - admin/operator storage management surface reflects upload and variant state accurately

## 5.7 Phase 14G: Ops Module Foundation + Protected Runtime Dashboard

Status: Complete

Deliverables:

- Add a first-party `ops` module that productizes existing observability/runtime diagnostics.
- Mount a protected `/ops` HTML surface and `/ops/api` JSON surface for:
  - health/readiness/live signals
  - metrics summaries
  - request/error trends
  - queue depth and recent failures
  - notification delivery health
  - storage utilization and recent processing errors
- Add auth policy defaults for operator/admin access and AAL2 requirements.
- Add OpenAPI output and machine-readable diagnostics for automation.
- Keep `ops` additive to existing low-level endpoints such as `/healthz`, `/readyz`, `/metrics`, and `/clusterz`.

Delivered:

- vendored `modules/ops/` with protected `/ops` HTML and `/ops/api/{summary,signals,metrics,openapi}` JSON/OpenAPI routes
- shared operator/admin + AAL2 guard behavior for both HTML and JSON surfaces
- dashboard summary composition for health/readiness/live, metrics, jobs, notifications, storage, optional search, and OpenAPI metadata

Acceptance (required):

- `tests/unit/Phase14GTests.m`:
  - ops summary payloads are deterministic and redacted appropriately
  - protected routes fail closed for missing role or missing step-up
- `tests/integration/Phase14OpsIntegrationTests.m`:
  - authenticated operator can access dashboard HTML and JSON
  - module surfaces reflect live jobs/notifications/storage state from the same runtime contracts

## 5.8 Phase 14H: Search Module Foundation + Admin/Search Integration

Status: Complete

Deliverables:

- Add a first-party `search` module with a database-first index/storage strategy.
- Introduce explicit searchable-resource registration:
  - resource identifier
  - indexed fields
  - filter/sort metadata
  - result rendering metadata
  - reindex policy
- Add job-backed indexing/reindexing workflows using the Phase 14 jobs module.
- Add HTML and JSON search surfaces:
  - general search endpoint
  - resource-scoped search
  - result snippets/highlights where feasible
  - reindex controls for operators/admins
- Integrate search with `admin-ui` resource metadata so admin resources can opt into indexing without separate duplicate registration when practical.

Delivered:

- vendored `modules/search/` with `ALNSearchResourceDefinition` and `ALNSearchResourceProvider`
- job-backed `search.reindex` execution through the shared jobs module runtime
- public search query routes, protected reindex routes, and generated OpenAPI exposure
- `admin-ui` auto-resource indexing plus shared `search_indexes` admin resource and ops summary integration

Acceptance (required):

- `tests/unit/Phase14HTests.m`:
  - searchable-resource metadata normalizes deterministically
  - query/filter parsing fails closed on unsupported fields/operators
- `tests/integration/Phase14SearchIntegrationTests.m`:
  - app can register a searchable resource and query it over JSON
  - reindex flows run through the same jobs contract and surface status in admin/ops views

## 5.9 Phase 14I: Hardening + Docs + Sample App + Confidence

Status: Complete

Deliverables:

- Add a sample app that installs:
  - `auth`
  - `admin-ui`
  - `jobs`
  - `notifications`
  - `storage`
  - `ops`
  - `search`
- Add docs for each new first-party module plus module-interaction guidance:
  - how notifications depend on jobs
  - how storage variants use jobs
  - how ops observes jobs/notifications/storage
  - how search uses jobs and admin metadata
- Add a `make phase14-confidence` gate and artifact pack under `build/release_confidence/phase14/`.
- Add release/docs/upgrade coverage for:
  - install
  - migrate
  - asset packaging
  - dashboard protection
  - JSON/OpenAPI contract generation

Delivered:

- `examples/phase14_modules_demo/` sample app installing `auth`, `admin-ui`, `jobs`, `notifications`, `storage`, `ops`, and `search`
- `docs/OPS_MODULE.md` and `docs/SEARCH_MODULE.md` plus updated bootstrap/reference docs
- `make phase14-confidence` and artifact generation under `build/release_confidence/phase14/`

Acceptance (required):

- `make build-tests` remains green with Phase 14 coverage enabled.
- `make phase14-confidence` produces deterministic artifacts for:
  - job enqueue/worker/scheduler flow
  - notification preview and delivery flow
  - upload/direct-upload plus variant flow
  - protected ops dashboard flow
  - search index and reindex flow
- Docs are updated in:
  - `README.md`
  - `docs/README.md`
  - `docs/GETTING_STARTED.md`
  - `docs/CLI_REFERENCE.md`

## 6. Exit Criteria

Phase 14 is complete when:

1. a new app can install all five Phase 14 modules through the Phase 13 module lifecycle
2. each module works with default-first local adapters and deterministic configuration
3. privileged HTML dashboards are protected by the auth/admin contracts already established in Phase 13
4. JSON/OpenAPI surfaces exist wherever SPA/automation use is expected
5. the sample app and confidence artifacts prove the modules operate together rather than as isolated demos

## 7. Explicit Non-Goals

- Billing/subscriptions in Phase 14.
- Organizations/teams/invitations in Phase 14.
- External search-engine-specific coupling as a baseline requirement.
- Cloud-vendor-specific upload pipelines as a baseline requirement.
- A bundled React/Vue frontend for any Phase 14 module.
- Replacing the existing Phase 3 service adapters with mandatory new core abstractions.

# Arlen Phase 27 Roadmap

Status: In progress (`27A-27D` delivered on 2026-04-01)
Last updated: 2026-04-01

Related docs:
- `docs/STATUS.md`
- `docs/SEARCH_MODULE.md`
- `docs/PHASE14_ROADMAP.md`
- `docs/PHASE16_ROADMAP.md`
- `docs/FEATURE_PARITY_MATRIX.md`
- `docs/MODULES.md`
- `docs/DOCUMENTATION_POLICY.md`

Reference inputs reviewed for this roadmap:
- `docs/SEARCH_MODULE.md`
- `modules/search/Sources/ALNSearchModule.h`
- `modules/search/Sources/ALNSearchModule.m`
- `tests/unit/Phase14HTests.m`
- `tests/unit/Phase16DTests.m`
- `tests/integration/Phase16ModuleIntegrationTests.m`
- `https://laravel.com/docs/12.x/scout`
- `https://github.com/ankane/searchkick`
- `https://github.com/Casecommons/pg_search`
- `https://docs.djangoproject.com/en/5.2/ref/contrib/postgres/search/`
- `https://docs.wagtail.org/en/stable/topics/search/indexing.html`
- `https://docs.wagtail.org/en/stable/topics/search/searching.html`
- `https://docs.wagtail.org/en/stable/topics/search/backends.html`
- `https://www.meilisearch.com/docs/getting_started/overview`

## 0. Progress Checkpoint (2026-04-01)

Arlen's first-party `search` module already has a strong framework-product
shape:

- explicit resource/provider/engine contracts
- durable module-owned index state
- job-backed full reindex and incremental sync
- HTML and JSON/OpenAPI routes
- shared admin and ops visibility
- fail-closed filter/sort behavior
- generation-aware rebuild activation and degraded-state handling

That puts Arlen ahead of many framework search packages on operational shape,
but not yet on retrieval depth.

The current default engine is still intentionally simple:

- snapshot-backed document arrays rather than database-native FTS or a search
  service
- substring scoring plus static field weights
- simple snippets/highlights
- no first-party typo tolerance, facets, autocomplete, synonyms, fuzzy search,
  query suggestions, promoted results, vector/hybrid search, or first-party
  external-engine adapters

Phase 27 exists to close that gap.

## 0.1 Delivered So Far (2026-04-01)

`27A-27D` are now shipped:

- `27A`: public query routes return shaped results by default, expose stable
  `resourceMetadata` / `engineCapabilities` / `pagination` envelopes, and
  support explicit per-resource public result shaping hooks.
- `27B`: resource metadata now distinguishes search/autocomplete/highlight/
  suggestion/result/facet fields, typed field metadata, query policies, query
  modes, and promotions; engine capability reporting is normalized and the
  search docs now match the supported operator surface.
- `27C`: Arlen ships a first-party `ALNPostgresSearchEngine` with PostgreSQL
  FTS/trigram ranking, configurable `textSearchConfiguration`, module-owned
  document storage, incremental sync, and degraded rebuild preservation.
- `27D`: the query contract now includes autocomplete, suggestions, facets, and
  promoted results in both HTML and JSON surfaces, with fail-closed query-mode
  validation.

Remaining scope starts at `27E`.

## 1. Objective

Make Arlen best-in-class for framework-owned search.

That does not mean rebuilding every dedicated search engine feature inside one
in-tree default engine. It means Arlen should offer the strongest combination
of:

- safe public search contracts
- explicit app-owned indexing and result-shaping contracts
- a first-party no-extra-service search path that is genuinely good
- first-party integrations with the search engines users actually adopt at
  scale
- excellent jobs/admin/ops/runtime visibility
- deterministic tests, confidence lanes, and upgradeable module behavior

Success looks like this:

- small and medium Arlen apps can get strong search quality from a first-party
  PostgreSQL-backed engine without adding new infrastructure
- larger apps can switch to a first-party Meilisearch or
  OpenSearch/Elasticsearch engine without changing their app-level search
  resource contracts
- public search APIs are safe by default and field exposure is explicit
- admin/operators can explain index state, rebuild history, engine
  capabilities, and recent failures without custom glue

## 1.1 Why Phase 27 Exists

The competitor landscape is consistent:

- `Laravel Scout` succeeds because it combines a simple app-facing contract,
  a no-extra-service baseline, and first-party external-engine adapters
- `Searchkick` succeeds because the search quality bar is high from day one:
  typo tolerance, synonyms, autocomplete, suggestions, aggregations, and
  zero-downtime indexing
- `pg_search` and Django Postgres search succeed because the database-backed
  baseline is real full-text search, not a toy substring engine
- `Wagtail` succeeds because search is a framework product with explicit
  indexed/filter/autocomplete fields, backend choice, editor-facing promoted
  results, and operational rebuild controls

Arlen already has the product/runtime/admin/ops side of that equation.
Phase 27 focuses on bringing the engine, contract, and user-facing query
surface up to the same standard.

## 1.2 Design Principles

- Keep resource registration explicit and app-owned.
- Separate indexed source records from public result payloads.
- Fail closed on unsupported fields, operators, and engine capabilities.
- Prefer a strong no-extra-service baseline before assuming an external search
  cluster.
- Ship first-party external engines for the engines people actually use.
- Keep engine capability reporting honest; do not pretend all engines support
  the same semantics.
- Preserve module-owned lifecycle state, jobs integration, admin drilldowns,
  and ops summaries across every engine.
- Treat auth/tenant scoping and public-safe field exposure as part of the
  search contract, not app-by-app afterthoughts.
- Preserve deterministic tests, fixtures, and confidence lanes.

## 2. Scope Summary

1. `27A`: search result shaping, safe public contracts, and resource policy
   boundaries.
2. `27B`: metadata contract expansion and engine-capability normalization.
3. `27C`: first-party PostgreSQL full-text/trigram engine.
4. `27D`: richer query contract: autocomplete, suggestions, facets, and
   promoted results.
5. `27E`: first-party Meilisearch engine.
6. `27F`: first-party OpenSearch/Elasticsearch engine.
7. `27G`: large-index lifecycle, bulk import, cursor pagination, and sync
   hardening.
8. `27H`: auth/tenant/soft-delete/policy-aware search semantics.
9. `27I`: admin, ops, and explainability maturity.
10. `27J`: app DX, generators, examples, and migration ergonomics.
11. `27K`: focused engine/query regression suites and fixture expansion.
12. `27L`: search confidence lanes, benchmark artifacts, and docs closeout.

## 2.1 Recommended Rollout Order

1. `27A`
2. `27B`
3. `27C`
4. `27D`
5. `27E`
6. `27F`
7. `27G`
8. `27H`
9. `27I`
10. `27J`
11. `27K`
12. `27L`

That order fixes the contract before widening the engine matrix, lands the
PostgreSQL baseline before external-engine integrations, and keeps testing and
confidence closeout aligned with the shipped semantics rather than bolted on
afterward.

## 3. Scope Guardrails

- Do not try to make the in-tree default engine compete feature-for-feature
  with every dedicated search service.
- Do not expose full raw indexed records on public search routes by default.
- Do not hard-couple the search module to `admin-ui`; auto-indexing remains
  additive.
- Do not erase engine differences behind misleading generic APIs.
- Do not require external search infrastructure for the common app path.
- Do not make PostgreSQL the only supported serious engine once the contract
  supports external backends cleanly.
- Do not add unbounded query DSL escape hatches to public routes without
  explicit capability and safety rules.
- Do not widen this phase into vector/AI search productization unless the
  engine seams and capability contracts are already ready for it.

## 4. Milestones

## 4.1 Phase 27A: Safe Result Shaping + Public Search Contract

Deliverables:

- Split search documents from API/HTML result presentation records.
- Add explicit per-resource result-field allowlists and optional private-only
  fields.
- Add resource-level public-query policy metadata:
  - public
  - authenticated
  - role-gated
  - app callback/predicate
- Add explicit result shaping hooks so apps can expose compact cards/rows
  instead of full records.
- Tighten JSON envelopes so resource metadata, engine info, pagination, and
  capability metadata are stable while record payloads stay explicitly shaped.

Acceptance (required):

- public search routes no longer expose raw `record` dictionaries by default
- resource authors can expose a minimal public shape without writing custom
  controllers
- search result fixtures cover public-safe, authenticated, and operator-only
  result variants

## 4.2 Phase 27B: Metadata Contract v2 + Engine Capability Normalization

Deliverables:

- Expand resource metadata to distinguish:
  - search fields
  - filter fields
  - facet fields
  - sort fields
  - autocomplete fields
  - highlight fields
  - suggestion/promoted-result fields
- Add typed field metadata so engines can treat strings, numbers, booleans,
  enums, dates, and timestamps honestly.
- Add engine capability reporting for:
  - full-text ranking
  - highlights
  - fuzzy matching
  - autocomplete
  - facets/aggregations
  - suggestions
  - promoted results
  - cursor pagination
  - soft-delete filters
  - tenant scoping
- Fix docs/code drift around supported operators and field types.

Acceptance (required):

- one normalized metadata contract can drive both PostgreSQL and external
  engines
- unsupported query features fail closed based on declared engine capability
- module docs and tests match the actual supported filter/sort/operator surface

## 4.3 Phase 27C: First-Party PostgreSQL FTS + Trigram Engine

Deliverables:

- Add a first-party PostgreSQL engine that uses real PostgreSQL full-text
  search and trigram similarity instead of in-memory substring scoring.
- Support:
  - weighted search vectors
  - rank ordering
  - configurable language dictionaries
  - highlighted snippets
  - phrase and boolean search modes where supported
  - trigram-backed fuzzy matching for typo tolerance
- Define deterministic indexing/storage strategy:
  - generated `tsvector` columns, materialized search tables, or another
    explicit module-owned contract
- Add rebuild/update flows that preserve the current generation/degraded-state
  lifecycle expectations.

Acceptance (required):

- PostgreSQL-backed search quality is materially better than the current
  default engine on ranking and typo tolerance
- the no-extra-service path remains fully first-party and documented
- integration tests cover reindex, incremental sync, highlights, fuzzy search,
  and degraded rebuild behavior against PostgreSQL

## 4.4 Phase 27D: Richer Query Contract

Deliverables:

- Add first-party support for:
  - autocomplete queries
  - query suggestions / did-you-mean
  - facets/aggregations
  - promoted/pinned results
  - phrase search
  - fuzzy search
- Add explicit per-resource query modes and defaults.
- Add machine-readable capability disclosure in query responses so clients can
  adapt without engine-specific assumptions.
- Add HTML and JSON surfaces for autocomplete and facet-driven search flows.

Acceptance (required):

- the JSON contract can express modern search UI needs without custom
  controller glue for every app
- capabilities are explicit rather than implied
- query-mode regressions are covered with fixture-backed tests

## 4.5 Phase 27E: First-Party Meilisearch Engine

Deliverables:

- Add a first-party Meilisearch engine adapter behind the shared
  `ALNSearchEngine` seam.
- Support:
  - filterable and sortable attribute configuration
  - typo tolerance
  - facets
  - autocomplete/search-as-you-type style flows where supported
  - synonyms and ranking-rule configuration surfaces
- Add lifecycle support for:
  - index creation and settings synchronization
  - queued bulk imports
  - update/delete syncing
  - reindex activation and error reporting mapped into Arlen dashboards

Acceptance (required):

- Arlen apps can switch from PostgreSQL/default search to Meilisearch through
  module config without redefining resource contracts
- engine-specific settings remain explicit and documented
- integration coverage uses a stubbed or optional live Meilisearch lane plus
  deterministic request/response fixtures

## 4.6 Phase 27F: First-Party OpenSearch / Elasticsearch Engine

Deliverables:

- Add a first-party OpenSearch/Elasticsearch engine adapter.
- Support:
  - field mappings
  - analyzers
  - synonym support
  - facets/aggregations
  - autocomplete helpers
  - fuzzy matching and relevance tuning hooks
- Add first-party index alias / zero-downtime rebuild guidance instead of
  app-owned ad hoc rollover logic.

Acceptance (required):

- Arlen's engine story covers both the easiest modern engine to adopt
  (Meilisearch) and the most common enterprise/search-heavy engine family
  (OpenSearch/Elasticsearch)
- index rollover/rebuild behavior is documented and visible in jobs/admin/ops
- engine-specific relevance and mapping configuration are explicit, not hidden

## 4.7 Phase 27G: Large-Index Lifecycle + Sync Hardening

Deliverables:

- Add bulk import orchestration and chunked worker flows for large datasets.
- Add cursor/search-after pagination for engines that support it, while
  preserving fail-closed fallback where they do not.
- Add bounded replay/recovery semantics for indexing failures.
- Add explicit sync policies for:
  - create/update/delete
  - soft delete
  - conditional indexing
  - pause/resume indexing
- Add richer progress and throughput reporting in jobs/admin/ops.

Acceptance (required):

- reindexing large resources no longer assumes small in-memory snapshots
- engines can report progress and recovery state through one shared module
  contract
- incremental sync semantics are deterministic across every supported engine

## 4.8 Phase 27H: Auth, Tenant, and Policy-Aware Search Semantics

Deliverables:

- Add first-class search scoping for:
  - tenant/account/org boundaries
  - role-based visibility
  - authenticated-only content
  - soft-deleted / archived content
- Add resource-level policy hooks that can shape both indexing eligibility and
  query-time visibility.
- Add explicit warnings/docs around search result consistency when app-level
  policies depend on dynamic runtime state.

Acceptance (required):

- apps can express secure multi-tenant and role-filtered search without
  duplicating custom controller logic per resource
- search indexes remain safe to expose through public routes when policy rules
  are configured correctly
- unit and integration tests cover tenant scoping, role scoping, and
  soft-delete visibility rules

## 4.9 Phase 27I: Admin, Ops, and Explainability Maturity

Deliverables:

- Expand admin and ops search surfaces with:
  - engine-specific capability summaries
  - index settings/mapping views
  - facet/autocomplete/promotion visibility
  - bulk-import and sync-progress reporting
  - recent query and failure diagnostics where safe
- Add explainability/debug surfaces for:
  - why a result matched
  - ranking score components where available
  - active query mode/capability fallback
- Add clearer degraded/failing/remediation guidance in dashboards.

Acceptance (required):

- operators can inspect search health and engine configuration without dropping
  to engine-native consoles for ordinary incidents
- resource drilldowns explain the active engine and current search contract
- regression coverage includes admin/ops JSON payload shape for the new data

## 4.10 Phase 27J: App DX, Generators, and Examples

Deliverables:

- Add generators/scaffolds for searchable resources, including:
  - resource definition skeleton
  - metadata contract examples
  - result shaping hooks
  - engine config examples
- Add example apps covering:
  - PostgreSQL-only search
  - faceted search UI
  - autocomplete/suggestions
  - Meilisearch/OpenSearch engine swaps
- Add migration guidance from the current simple engine to PostgreSQL or an
  external engine.

Acceptance (required):

- a new app can stand up a serious search resource without reverse-engineering
  module internals
- examples cover both the default path and an external-engine path
- docs make the engine tradeoffs clear up front

## 4.11 Phase 27K: Engine-Specific Regression Suites + Fixtures

Deliverables:

- Split search tests into focused families such as:
  - metadata normalization
  - result shaping and visibility
  - PostgreSQL FTS behavior
  - Meilisearch contract behavior
  - OpenSearch contract behavior
  - autocomplete/facet/promotion semantics
  - sync/rebuild/recovery regressions
- Add fixture packs for:
  - ranking expectations
  - highlight expectations
  - typo/fuzzy cases
  - suggestion/promoted-result cases
  - tenant/role visibility cases
- Add shared search test helpers analogous to the live/dataverse helper layers.

Acceptance (required):

- search quality and contract regressions are localized to focused suites
- engine adapters can be validated against one shared fixture vocabulary
- docs and examples are backed by executable coverage rather than smoke tests

## 4.12 Phase 27L: Confidence Lanes + Benchmarking + Docs Closeout

Deliverables:

- Add repo-native search confidence lanes, expected to include:
  - focused search unit bundle
  - PostgreSQL-backed integration bundle
  - optional live external-engine smoke lanes
  - search artifact pack under `build/release_confidence/phase27/`
- Add benchmark/characterization artifacts for:
  - ranking quality snapshots
  - highlight/suggestion/facet outputs
  - large-reindex throughput baselines
- Close out roadmap/docs/status surfaces, regenerate API docs, and update the
  search module guide.

Acceptance (required):

- Arlen can make a credible best-in-class claim about its framework-owned
  search posture with checked-in artifacts and reproducible confidence lanes
- search module docs accurately describe the shipped contract and the current
  engine matrix
- the phase closes with machine-readable artifacts, not just prose

## 5. Success Criteria

Phase 27 should be considered successful when all of the following are true:

1. Arlen's public search contract is safe by default and no longer leaks raw
   records unintentionally.
2. Arlen ships a strong no-extra-service PostgreSQL search path with real FTS
   quality.
3. Arlen ships first-party adapters for at least Meilisearch and
   OpenSearch/Elasticsearch.
4. Arlen search resources can express autocomplete, facets, suggestions, and
   promoted results without one-off controller code.
5. Admin and ops surfaces remain first-class across every engine.
6. Search-specific confidence lanes and characterization artifacts exist in the
   repo.

## 6. Verification Targets

When this phase is implemented, expected verification should include at least:

```bash
source tools/source_gnustep_env.sh
make build-tests
make test-unit
make phase27-search-tests
make phase27-confidence
make docs-api
bash tools/ci/run_docs_quality.sh
git diff --check
```

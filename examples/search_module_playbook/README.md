# Search Module Playbook

This example is the shortest app-owned path from a fresh Arlen app to a
serious search resource that can move between the default engine, PostgreSQL
FTS, Meilisearch, and OpenSearch without rewriting controllers.

## Bootstrap

From a fresh app root:

```bash
ARLEN_FRAMEWORK_ROOT=/path/to/Arlen ./build/arlen module add jobs --json
ARLEN_FRAMEWORK_ROOT=/path/to/Arlen ./build/arlen module add search --json
ARLEN_FRAMEWORK_ROOT=/path/to/Arlen ./build/arlen generate search Catalog --json
./build/arlen module doctor --json
./build/arlen module migrate --env development
```

The generator adds:

- `src/Search/CatalogSearchProvider.{h,m}`
- a public-safe `searchModulePublicResultForDocument:` hook
- `docs/search/catalog_search.md`
- `config/app.plist` registration under `searchModule.providers.classes`

## What To Edit First

Open `src/Search/CatalogSearchProvider.m` and replace the placeholder record
array plus metadata with your real app-owned fields:

- `identifierField`, `primaryField`, `summaryField`
- `indexedFields`, `searchFields`, `resultFields`
- typed `filters`, `facetFields`, and `sorts`
- `queryModes`, `queryPolicy`, and `pathTemplate`

## Engine Swap Path

Default engine:

- fastest setup
- best when you are still shaping results and filters
- simpler relevance than the stronger engines

PostgreSQL FTS/trigram:

- best no-extra-service path
- first engine to reach for when you want materially better ranking quality

Meilisearch:

- good fit for fast autocomplete/suggestion-heavy search
- first-party adapter honors the same resource contract and shaped results

OpenSearch / Elasticsearch:

- good fit when you want the broader query/explainability surface and cluster
  tooling
- first-party adapter keeps Arlen-owned result shaping, admin, and ops flows

## Suggested Validation

After you replace the placeholder documents with real records:

```bash
./build/arlen routes
./build/arlen boomhauer --port 3000
curl -i http://127.0.0.1:3000/search
curl -i "http://127.0.0.1:3000/search/api/resources/catalog/query?q=term"
```

Reindex after every engine change so the new engine descriptor and bulk-import
metrics show up under `/search/api/resources/catalog`.

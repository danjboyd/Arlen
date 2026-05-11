# SQL Builder Migration Guide (v2 String-Heavy to Phase 4 IR/Typed)

This guide documents migration from pre-Phase-4 string-heavy usage to Phase 4 patterns (IR-backed expression APIs, typed schema helpers, and builder execution diagnostics).

## 1. Migration Goals

- keep raw SQL first-class while reducing fragile string composition
- adopt identifier-bound expression templates (`{{token}}`) for injection-safe dynamic identifiers
- preserve deterministic parameter ordering and placeholder contracts
- move builder execution through `ALNPg executeBuilderQuery/executeBuilderCommand` when diagnostics/caching is useful

## 2. Before/After Patterns

## 2.1 Dynamic Select Expressions

Before:

```objc
[builder selectExpression:@"COALESCE(d.title, $1)" alias:@"display_title" parameters:@[ @"untitled" ]];
```

After:

```objc
[builder selectExpression:@"COALESCE({{title_col}}, $1)"
                    alias:@"display_title"
       identifierBindings:@{ @"title_col" : @"d.title" }
               parameters:@[ @"untitled" ]];
```

## 2.2 Dynamic Predicate Columns

Before:

```objc
[builder whereExpression:@"d.state_code = $1" parameters:@[ state ]];
```

After:

```objc
[builder whereExpression:@"{{state_col}} = $1"
      identifierBindings:@{ @"state_col" : @"d.state_code" }
              parameters:@[ state ]];
```

## 2.3 Expression-Aware Ordering with Cursor Tuples

```objc
[builder whereExpression:@"(COALESCE(d.manifest_order, 0), d.document_id) > ($1, $2)"
              parameters:@[ cursorOrder, cursorDocumentID ]];
[builder orderByExpression:@"COALESCE(d.manifest_order, $1)"
                descending:NO
                     nulls:@"LAST"
        identifierBindings:@{ @"manifest_col" : @"d.manifest_order" }
                parameters:@[ @0 ]];
[builder orderByField:@"d.document_id" descending:NO nulls:nil];
```

## 2.4 Lateral Joins

```objc
ALNSQLBuilder *latestEvent = [ALNSQLBuilder selectFrom:@"events" alias:@"e" columns:@[ @"e.event_id" ]];
[latestEvent whereExpression:@"e.docket_id = d.docket_id" parameters:nil];
[latestEvent orderByExpression:@"COALESCE(e.updated_at, e.created_at)" descending:YES nulls:@"LAST"];
[latestEvent limit:1];
[builder leftJoinLateralSubquery:latestEvent alias:@"le" onExpression:@"TRUE" parameters:nil];
```

## 2.5 PostgreSQL Upsert Expressions

```objc
[upsert onConflictColumns:@[ @"id" ]
      doUpdateAssignments:@{
        @"attempt_count" : @{
          @"expression" : @"\"queue_jobs\".\"attempt_count\" + $1",
          @"parameters" : @[ @1 ],
        },
        @"state" : @"EXCLUDED.state",
      }];
[upsert onConflictDoUpdateWhereExpression:@"\"queue_jobs\".\"state\" <> $1"
                               parameters:@[ @"done" ]];
```

## 3. Builder Execution Migration

If you want runtime cache/diagnostics behavior, migrate from:

```objc
NSDictionary *built = [builder build:&error];
NSArray *rows = [database executeQuery:built[@"sql"] parameters:built[@"parameters"] error:&error];
```

to:

```objc
database.preparedStatementReusePolicy = ALNPgPreparedStatementReusePolicyAuto;
database.builderCompilationCacheLimit = 128;
database.preparedStatementCacheLimit = 128;
database.queryDiagnosticsListener = ^(NSDictionary<NSString *, id> *event) {
  // compile/execute/result/error events
};

NSArray *rows = [database executeBuilderQuery:builder error:&error];
```

Defaults remain redaction-safe:

- `includeSQLInDiagnosticsEvents = NO`

## 4. Representative Upgrade Validation

A representative API migration flow (docket/document listing patterns with:

- identifier-bound expressions
- lateral joins
- tuple cursor predicates
- expression-aware ordering

is validated by:

- `tests/unit/Phase4ETests.m` (`testMigrationGuideRepresentativeFlowCompilesAndPreservesContracts`)

This ensures guide patterns compile deterministically and preserve placeholder/parameter contracts.

## 5. Transitional API Deprecation Policy (4A-4D)

Transitional API behavior introduced during 4A-4D follows this policy:

1. No hard removal in 4.x for currently documented builder/adapter APIs.
2. Transitional string-heavy expression entrypoints remain supported through at least two 4.x minor releases.
3. Any future removal requires:
   - deprecation notice in `README.md`, `docs/STATUS.md`, and this guide
   - migration replacement documented with before/after snippets
   - removal only at the next major release boundary

This policy extends the lifecycle in `docs/RELEASE_PROCESS.md`.


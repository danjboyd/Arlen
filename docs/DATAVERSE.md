# Dataverse Integration

This guide covers Arlen's Dataverse Web API/OData surface.

## 1. Scope

Dataverse support in Arlen is:

- compiled in
- runtime-inactive by default
- separate from `ALNDatabaseAdapter` and `ALNSQLBuilder`
- aimed at the Dataverse Web API, not Microsoft Graph

Phase `23A-23I` is now complete. The shipped surface includes:

- `ALNDataverseClient`
- `ALNDataverseQuery`
- `ALNDataverseMetadata`
- `ALNDataverseCodegen`
- `arlen dataverse-codegen`
- `ALNApplication`, `ALNContext`, and `ALNController` Dataverse helpers
- repo-native `phase23-dataverse-tests`, `phase23-live-smoke`, and
  `phase23-confidence` lanes
- checked-in Dataverse characterization/parity fixtures under
  `tests/fixtures/phase23/`

## 2. Config Shape

Minimal config in `config/app.plist`:

```plist
{
  dataverse = {
    serviceRootURL = "https://example.crm.dynamics.com/api/data/v9.2";
    tenantID = "00000000-0000-0000-0000-000000000000";
    clientID = "11111111-1111-1111-1111-111111111111";
    clientSecret = "replace-me";
    pageSize = 500;
    maxRetries = 2;
    timeout = 60;
  };
}
```

Named targets can live in either shape:

```plist
{
  dataverse = {
    serviceRootURL = "https://example.crm.dynamics.com/api/data/v9.2";
    tenantID = "00000000-0000-0000-0000-000000000000";
    clientID = "11111111-1111-1111-1111-111111111111";
    clientSecret = "replace-me";
    targets = {
      sales = {
        serviceRootURL = "https://sales.crm.dynamics.com/api/data/v9.2";
      };
    };
  };

  dataverseTargets = {
    support = {
      serviceRootURL = "https://support.crm.dynamics.com/api/data/v9.2";
    };
  };
}
```

Environment overrides are honored by both the runtime helper path and the CLI:

- `ARLEN_DATAVERSE_URL` or `ARLEN_DATAVERSE_SERVICE_ROOT`
- `ARLEN_DATAVERSE_TENANT_ID`
- `ARLEN_DATAVERSE_CLIENT_ID`
- `ARLEN_DATAVERSE_CLIENT_SECRET`
- `ARLEN_DATAVERSE_PAGE_SIZE`
- `ARLEN_DATAVERSE_MAX_RETRIES`
- `ARLEN_DATAVERSE_TIMEOUT`

Target-specific overrides append `_<TARGET>` in uppercase, for example
`ARLEN_DATAVERSE_URL_SALES`.

`ARLEN_DATAVERSE_URL` may be either the bare Dataverse environment URL
(`https://example.crm.dynamics.com`) or the explicit Web API service root
(`https://example.crm.dynamics.com/api/data/v9.2`). Arlen normalizes a bare
environment URL to `/api/data/v9.2` automatically. `ARLEN_DATAVERSE_SERVICE_ROOT`
can still be used when you want to be explicit.

## 3. Runtime Access

Create a target and client directly when you only need the ArlenData surface:

```objc
NSError *error = nil;
ALNDataverseTarget *target =
    [[ALNDataverseTarget alloc] initWithServiceRootURLString:@"https://example.crm.dynamics.com/api/data/v9.2"
                                                    tenantID:tenantID
                                                    clientID:clientID
                                                clientSecret:clientSecret
                                                   targetName:@"default"
                                              timeoutInterval:60.0
                                                   maxRetries:2
                                                     pageSize:500
                                                        error:&error];
ALNDataverseClient *client = [[ALNDataverseClient alloc] initWithTarget:target error:&error];
```

Inside a full Arlen app, prefer the lazy runtime helpers:

```objc
NSError *error = nil;
ALNDataverseClient *defaultClient = [app dataverseClient];
ALNDataverseClient *salesClient = [app dataverseClientNamed:@"sales" error:&error];
NSArray<NSString *> *targets = [app dataverseTargetNames];
```

Controllers and contexts expose the same named-client seam:

```objc
- (id)syncAccount:(ALNContext *)ctx {
  NSError *error = nil;
  ALNDataverseClient *client = [self dataverseClientNamed:@"sales" error:&error];
  if (client == nil) {
    [self setStatus:500];
    [self renderJSON:@{ @"error" : error.localizedDescription ?: @"Dataverse client unavailable" }
               error:NULL];
    return self.context.response;
  }

  ALNDataverseRecord *account =
      [client retrieveRecordInEntitySet:@"accounts"
                               recordID:@"00000000-0000-0000-0000-000000000010"
                           selectFields:@[ @"accountid", @"name" ]
                                 expand:nil
                 includeFormattedValues:YES
                                  error:&error];
  [self renderJSON:@{
    @"name" : account.values[@"name"] ?: @"",
    @"formatted_name" : account.formattedValues[@"name"] ?: @"",
  }
             error:NULL];
  return self.context.response;
}
```

If an app never calls these helpers, Dataverse stays dormant and does not add
startup work.

## 4. Queries and Writes

Use the OData builder for reads:

```objc
NSError *error = nil;
ALNDataverseQuery *query =
    [[[[ALNDataverseQuery queryWithEntitySetName:@"accounts" error:&error]
        queryBySettingSelectFields:@[ @"accountid", @"name", @"createdon" ]]
        queryBySettingPredicate:@{
          @"statecode" : @0,
          @"name" : @{ @"-startswith" : @"Acme" },
        }]
        queryBySettingOrderBy:@[ @{ @"-desc" : @"createdon" } ]];
ALNDataverseEntityPage *page = [client fetchPageForQuery:query error:&error];
NSArray<ALNDataverseRecord *> *records = page.records;
NSString *nextLink = page.nextLinkURLString;
```

Write helpers keep Dataverse-specific payload rules explicit:

```objc
NSError *error = nil;
NSDictionary *values = @{
  @"name" : @"Acme, Inc.",
  @"primarycontactid" :
      [ALNDataverseLookupBinding bindingWithEntitySetName:@"contacts"
                                                 recordID:@"00000000-0000-0000-0000-000000000020"
                                                    error:&error],
  @"statuscode" : [ALNDataverseChoiceValue valueWithIntegerValue:@1],
};
NSDictionary *created =
    [client createRecordInEntitySet:@"accounts" values:values returnRepresentation:YES error:&error];
```

Shipped helpers include:

- create, update, delete
- alternate-key upsert
- lookup binding serialization through `@odata.bind`
- choice/option-set coercion
- generic action/function invocation
- batch request execution

## 5. Metadata and Codegen

Generate typed helpers from a saved metadata payload:

```bash
/path/to/Arlen/bin/arlen dataverse-codegen \
  --input tests/fixtures/phase23/dataverse_entitydefinitions.json \
  --output-dir src/Generated \
  --manifest db/schema/dataverse.json \
  --prefix ALNDV \
  --force
```

Generate from live Dataverse metadata instead:

```bash
/path/to/Arlen/bin/arlen dataverse-codegen \
  --target sales \
  --entity account \
  --entity contact \
  --force
```

Generated artifacts default to:

- `src/Generated/ALNDVDataverseSchema.h`
- `src/Generated/ALNDVDataverseSchema.m`
- `db/schema/dataverse.json`

Generated helpers expose:

- logical names and entity-set names
- primary id/name attributes
- alternate keys
- singular lookup navigation maps for unambiguous lookup attributes
- `lookupNavigationTargetsMap` for all lookup attributes, including
  polymorphic lookups
- `navigation<Field>` helpers for unambiguous lookups and
  navigation-property-specific helpers such as `navigationCustomeridAccount`
  when Dataverse exposes multiple targets for one logical lookup attribute
- field constants
- choice enums and choice metadata

For polymorphic lookups, Arlen intentionally keeps the singular
`lookupNavigationMap` conservative. Ambiguous lookup attributes are omitted
from that map rather than collapsing multiple Dataverse navigation targets down
to one arbitrary value.

## 6. Example Path

See [examples/dataverse_reference/README.md](/home/danboyd/git/Arlen/examples/dataverse_reference/README.md)
for one recommended flow that covers:

- config for default and named targets
- controller-level client acquisition
- one read path
- one write path
- one metadata/codegen path

## 7. Reliability and Confidence

Dataverse request failures now carry structured error metadata through keys such
as:

- `ALNDataverseErrorRequestMethodKey`
- `ALNDataverseErrorRequestURLKey`
- `ALNDataverseErrorRequestHeadersKey`
- `ALNDataverseErrorTargetNameKey`
- `ALNDataverseErrorRetryAfterKey`
- `ALNDataverseErrorCorrelationIDKey`
- `ALNDataverseErrorDiagnosticsKey`

Use the focused confidence entrypoints for this surface:

```bash
source tools/source_gnustep_env.sh
make phase23-dataverse-tests
make phase23-live-smoke
make phase23-confidence
```

`make phase23-confidence` always runs the fixture-backed Dataverse suite and
the checked-in Perl parity accounting. It optionally runs:

- a live Dataverse smoke through `phase23-live-smoke`
- a live `dataverse-codegen` smoke

The checked-in characterization/parity fixtures are:

- `tests/fixtures/phase23/dataverse_query_cases.json`
- `tests/fixtures/phase23/dataverse_contract_snapshot.json`
- `tests/fixtures/phase23/dataverse_perl_parity_matrix.json`

The live smoke lane expects the normal `ARLEN_DATAVERSE_*` credentials plus:

- `ARLEN_PHASE23_DATAVERSE_TARGET`
- `ARLEN_PHASE23_DATAVERSE_ENTITY_SET`
- `ARLEN_PHASE23_DATAVERSE_ID_FIELD`
- `ARLEN_PHASE23_DATAVERSE_NAME_FIELD`
- `ARLEN_PHASE23_DATAVERSE_ALTKEY_FIELD`
- `ARLEN_PHASE23_DATAVERSE_FORMATTED_FIELD`
- `ARLEN_PHASE23_DATAVERSE_EXPECT_PAGING`
- `ARLEN_PHASE23_DATAVERSE_WRITE_ENABLED=1`

## 8. Current Boundaries

This surface still does not try to make Dataverse behave like SQL:

- no fake transaction abstraction
- no `ALNDatabaseAdapter` bridge
- no Microsoft Graph wrapper
- no FetchXML-first builder
- no TDS/SQL endpoint integration

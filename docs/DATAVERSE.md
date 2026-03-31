# Dataverse Integration

This guide covers Arlen's Dataverse Web API/OData surface.

## 1. Scope

Dataverse support in Arlen is:

- compiled in
- runtime-inactive by default
- separate from `ALNDatabaseAdapter` and `ALNSQLBuilder`
- aimed at the Dataverse Web API, not Microsoft Graph

The current delivered surface covers Phase `23A-23D`:

- `ALNDataverseClient`
- `ALNDataverseQuery`
- `ALNDataverseMetadata`
- `ALNDataverseCodegen`
- `arlen dataverse-codegen`

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

Environment overrides used by the CLI/codegen path:

- `ARLEN_DATAVERSE_URL` or `ARLEN_DATAVERSE_SERVICE_ROOT`
- `ARLEN_DATAVERSE_TENANT_ID`
- `ARLEN_DATAVERSE_CLIENT_ID`
- `ARLEN_DATAVERSE_CLIENT_SECRET`
- `ARLEN_DATAVERSE_PAGE_SIZE`
- `ARLEN_DATAVERSE_MAX_RETRIES`
- `ARLEN_DATAVERSE_TIMEOUT`

Target-specific overrides append `_<TARGET>` in uppercase, for example
`ARLEN_DATAVERSE_URL_SALES`.

## 3. Runtime Usage

Create a target and client directly:

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

Query records through the OData builder:

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

Write helpers keep Dataverse-specific shapes explicit:

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

Available write-path helpers include:

- create, update, delete
- alternate-key upsert
- lookup binding serialization through `@odata.bind`
- choice/option-set coercion
- generic action/function invocation
- batch request execution

## 4. Metadata and Codegen

Generate typed helpers from a checked-in or exported metadata payload:

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
  --env development \
  --target sales \
  --entity account \
  --entity contact \
  --force
```

Generated artifacts default to:

- `src/Generated/ALNDVDataverseSchema.h`
- `src/Generated/ALNDVDataverseSchema.m`
- `db/schema/dataverse.json`

Non-default targets get target-specific defaults for output dir, manifest, and
class prefix.

Generated helpers expose:

- logical names and entity-set names
- primary id/name attributes
- alternate keys
- lookup navigation maps
- field constants
- choice enums and choice metadata

## 5. Current Boundaries

This surface does not currently try to make Dataverse behave like SQL:

- no fake transaction abstraction
- no `ALNDatabaseAdapter` bridge
- no Microsoft Graph wrapper
- no FetchXML-first builder
- no TDS/SQL endpoint integration

Phase `23E-23G` remain for higher-level runtime ergonomics, deeper diagnostics,
confidence lanes, and broader doc/example closeout.

# Dataverse Reference

This reference flow shows the recommended Arlen Dataverse path after Phase 23.

## 1. Configure Targets

`config/app.plist`:

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
    targets = {
      sales = {
        serviceRootURL = "https://sales.crm.dynamics.com/api/data/v9.2";
      };
    };
  };
}
```

If an app never requests a Dataverse client, this config stays dormant.

## 2. Read Flow

Inside a controller:

```objc
- (id)accounts:(ALNContext *)ctx {
  NSError *error = nil;
  ALNDataverseClient *client = [self dataverseClientNamed:@"sales" error:&error];
  if (client == nil) {
    [self setStatus:500];
    [self renderJSON:@{ @"error" : error.localizedDescription ?: @"Dataverse unavailable" }
               error:NULL];
    return self.context.response;
  }

  ALNDataverseQuery *query =
      [[[[ALNDataverseQuery queryWithEntitySetName:@"accounts" error:&error]
          queryBySettingSelectFields:@[ @"accountid", @"name" ]]
          queryBySettingPredicate:@{ @"statecode" : @0 }]
          queryBySettingTop:@25];
  ALNDataverseEntityPage *page = [client fetchPageForQuery:query error:&error];
  NSMutableArray *rows = [NSMutableArray array];
  for (ALNDataverseRecord *record in page.records) {
    [rows addObject:@{
      @"accountid" : record.values[@"accountid"] ?: @"",
      @"name" : record.values[@"name"] ?: @"",
    }];
  }

  [self renderJSON:@{
    @"rows" : rows,
    @"next_link" : page.nextLinkURLString ?: [NSNull null],
  }
             error:NULL];
  return self.context.response;
}
```

## 3. Write Flow

```objc
- (id)createAccount:(ALNContext *)ctx {
  NSError *error = nil;
  ALNDataverseClient *client = [self dataverseClientNamed:@"sales" error:&error];
  NSDictionary *created = [client createRecordInEntitySet:@"accounts"
                                                   values:@{
                                                     @"name" : @"Acme, Inc.",
                                                     @"statuscode" : [ALNDataverseChoiceValue valueWithIntegerValue:@1],
                                                   }
                                      returnRepresentation:YES
                                                    error:&error];
  if (created == nil) {
    [self setStatus:500];
    [self renderJSON:@{ @"error" : error.localizedDescription ?: @"Dataverse write failed" }
               error:NULL];
    return self.context.response;
  }

  [self renderJSON:created error:NULL];
  return self.context.response;
}
```

For alternate keys, lookups, and actions/functions, keep using the dedicated
Dataverse helpers rather than forcing those cases through SQL-style abstractions.

## 4. Metadata + Codegen

Generate typed helpers from a live environment:

```bash
source tools/source_gnustep_env.sh
./build/arlen dataverse-codegen \
  --target sales \
  --entity account \
  --entity contact \
  --output-dir src/Generated/Dataverse \
  --manifest db/schema/dataverse_sales.json \
  --prefix ALNDVSales \
  --force
```

Or use a checked-in fixture while developing the app contract:

```bash
./build/arlen dataverse-codegen \
  --input tests/fixtures/phase23/dataverse_entitydefinitions.json \
  --output-dir src/Generated/Dataverse \
  --manifest db/schema/dataverse_fixture.json \
  --prefix ALNDVFixture \
  --force
```

## 5. Confidence Commands

```bash
source tools/source_gnustep_env.sh
make phase23-dataverse-tests
make phase23-confidence
```

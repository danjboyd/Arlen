#import <Foundation/Foundation.h>

#import "ArlenData/ArlenData.h"

static BOOL ALNDataExpectEqual(NSString *label,
                               NSString *actual,
                               NSString *expected) {
  if ((actual == nil && expected == nil) || [actual isEqualToString:expected]) {
    return YES;
  }
  fprintf(stderr,
          "[arlen-data-example] %s mismatch\nexpected: %s\nactual:   %s\n",
          [label UTF8String],
          [expected UTF8String],
          [actual UTF8String]);
  return NO;
}

int main(int argc, const char *argv[]) {
  (void)argc;
  (void)argv;

  @autoreleasepool {
    NSError *error = nil;

    ALNSQLBuilder *recentUsers = [ALNSQLBuilder selectFrom:@"events"
                                                   columns:@[ @"user_id" ]];
    [[recentUsers whereField:@"tenant_id" equals:@44]
        whereField:@"event_type"
          operator:@"="
             value:@"login"];
    [recentUsers groupByField:@"user_id"];

    ALNSQLBuilder *query = [ALNSQLBuilder selectFrom:@"users"
                                               alias:@"u"
                                             columns:@[ @"u.id", @"u.name" ]];
    [query withCTE:@"recent_users" builder:recentUsers];
    [query joinTable:@"recent_users"
               alias:@"ru"
         onLeftField:@"u.id"
            operator:@"="
        onRightField:@"ru.user_id"];
    [query whereAnyGroup:^(ALNSQLBuilder *group) {
      [group whereField:@"u.status" equals:@"active"];
      [group whereField:@"u.role" equals:@"admin"];
    }];
    [query orderByField:@"u.id" descending:NO];

    NSDictionary *built = [query build:&error];
    if (built == nil || error != nil) {
      fprintf(stderr,
              "[arlen-data-example] failed building CTE query: %s\n",
              [[error localizedDescription] UTF8String]);
      return 1;
    }

    NSString *expectedSQL =
        @"WITH \"recent_users\" AS (SELECT \"user_id\" FROM \"events\" WHERE \"tenant_id\" = $1 AND \"event_type\" = $2 GROUP BY \"user_id\") "
         "SELECT \"u\".\"id\", \"u\".\"name\" FROM \"users\" AS \"u\" INNER JOIN \"recent_users\" AS \"ru\" ON \"u\".\"id\" = \"ru\".\"user_id\" "
         "WHERE (\"u\".\"status\" = $3 OR \"u\".\"role\" = $4) ORDER BY \"u\".\"id\" ASC";
    if (!ALNDataExpectEqual(@"cte_sql", built[@"sql"], expectedSQL)) {
      return 1;
    }

    NSArray *expectedParams = @[ @44, @"login", @"active", @"admin" ];
    if (![built[@"parameters"] isEqual:expectedParams]) {
      fprintf(stderr,
              "[arlen-data-example] parameter mismatch\n");
      return 1;
    }

    ALNPostgresSQLBuilder *upsert =
        (ALNPostgresSQLBuilder *)[ALNPostgresSQLBuilder insertInto:@"users"
                                                             values:@{
                                                               @"name" : @"Peggy",
                                                               @"id" : @7,
                                                             }];
    [[upsert onConflictColumns:@[ @"id" ] doUpdateSetFields:@[ @"name" ]]
        returningField:@"id"];

    NSDictionary *upsertBuilt = [upsert build:&error];
    if (upsertBuilt == nil || error != nil) {
      fprintf(stderr,
              "[arlen-data-example] failed building upsert query: %s\n",
              [[error localizedDescription] UTF8String]);
      return 1;
    }

    NSString *expectedUpsertSQL =
        @"INSERT INTO \"users\" (\"id\", \"name\") VALUES ($1, $2) ON CONFLICT (\"id\") DO UPDATE SET \"name\" = EXCLUDED.\"name\" RETURNING \"id\"";
    if (!ALNDataExpectEqual(@"upsert_sql", upsertBuilt[@"sql"], expectedUpsertSQL)) {
      return 1;
    }

    NSArray *expectedUpsertParams = @[ @7, @"Peggy" ];
    if (![upsertBuilt[@"parameters"] isEqual:expectedUpsertParams]) {
      fprintf(stderr,
              "[arlen-data-example] upsert parameter mismatch\n");
      return 1;
    }

    printf("arlen-data example: ok\n");
  }

  return 0;
}

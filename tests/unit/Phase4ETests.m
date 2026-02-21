#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNPostgresSQLBuilder.h"
#import "ALNSQLBuilder.h"

@interface Phase4ETests : XCTestCase
@end

@implementation Phase4ETests

- (NSString *)fixturePath:(NSString *)name {
  NSString *root = [[NSFileManager defaultManager] currentDirectoryPath];
  return [root stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"tests/fixtures/sql_builder/%@", name ?: @""]];
}

- (NSDictionary *)loadConformanceMatrixFixture {
  NSString *path = [self fixturePath:@"phase4e_conformance_matrix.json"];
  NSData *data = [NSData dataWithContentsOfFile:path];
  XCTAssertNotNil(data);
  if (data == nil) {
    return @{};
  }

  NSError *error = nil;
  NSDictionary *payload =
      [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(payload);
  if (payload == nil) {
    return @{};
  }
  return payload;
}

- (NSArray<NSNumber *> *)placeholderNumbersFromSQL:(NSString *)sql {
  if ([sql length] == 0) {
    return @[];
  }
  NSError *regexError = nil;
  NSRegularExpression *regex =
      [NSRegularExpression regularExpressionWithPattern:@"\\$([0-9]+)"
                                                options:0
                                                  error:&regexError];
  XCTAssertNil(regexError);
  XCTAssertNotNil(regex);
  if (regex == nil) {
    return @[];
  }

  NSArray<NSTextCheckingResult *> *matches =
      [regex matchesInString:sql options:0 range:NSMakeRange(0, [sql length])];
  NSMutableArray<NSNumber *> *numbers = [NSMutableArray arrayWithCapacity:[matches count]];
  for (NSTextCheckingResult *match in matches) {
    NSRange range = [match rangeAtIndex:1];
    if (range.location == NSNotFound) {
      continue;
    }
    NSInteger value = [[sql substringWithRange:range] integerValue];
    [numbers addObject:@(value)];
  }
  return numbers;
}

- (void)assertPlaceholderContractForSQL:(NSString *)sql parameters:(NSArray *)parameters {
  NSArray<NSNumber *> *placeholders = [self placeholderNumbersFromSQL:(sql ?: @"")];
  NSUInteger parameterCount = [parameters count];

  if (parameterCount == 0) {
    XCTAssertEqual((NSUInteger)0, [placeholders count]);
    return;
  }

  NSInteger maxValue = 0;
  NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
  for (NSNumber *value in placeholders) {
    NSInteger index = [value integerValue];
    XCTAssertGreaterThanOrEqual(index, (NSInteger)1);
    XCTAssertLessThanOrEqual(index, (NSInteger)parameterCount);
    if (index > maxValue) {
      maxValue = index;
    }
    [seen addObject:@(index)];
  }

  XCTAssertEqual((NSInteger)parameterCount, maxValue);
  for (NSInteger idx = 1; idx <= (NSInteger)parameterCount; idx++) {
    XCTAssertTrue([seen containsObject:@(idx)]);
  }
}

- (uint32_t)nextSeed:(uint32_t *)seed {
  *seed = (*seed * 1664525u) + 1013904223u;
  return *seed;
}

- (NSUInteger)randomValueWithSeed:(uint32_t *)seed min:(NSUInteger)min max:(NSUInteger)max {
  if (max <= min) {
    return min;
  }
  uint32_t value = [self nextSeed:seed];
  NSUInteger span = (max - min) + 1;
  return min + (value % span);
}

- (NSString *)randomTokenWithSeed:(uint32_t *)seed prefix:(NSString *)prefix {
  uint32_t value = [self nextSeed:seed];
  return [NSString stringWithFormat:@"%@_%08x", prefix ?: @"tok", value];
}

- (NSArray<NSString *> *)shuffledKeys:(NSArray<NSString *> *)keys seed:(uint32_t *)seed {
  NSMutableArray<NSString *> *values = [NSMutableArray arrayWithArray:keys ?: @[]];
  for (NSInteger idx = (NSInteger)[values count] - 1; idx > 0; idx--) {
    NSUInteger swapIndex = [self randomValueWithSeed:seed min:0 max:(NSUInteger)idx];
    [values exchangeObjectAtIndex:(NSUInteger)idx withObjectAtIndex:swapIndex];
  }
  return [NSArray arrayWithArray:values];
}

- (NSDictionary<NSString *, NSDictionary *> *)buildConformanceScenarioResults:(NSError **)error {
  NSMutableDictionary<NSString *, NSDictionary *> *results = [NSMutableDictionary dictionary];

  ALNSQLBuilder *templateBuilder = [ALNSQLBuilder selectFrom:@"documents"
                                                       alias:@"d"
                                                     columns:@[ @"d.id" ]];
  [templateBuilder selectExpression:@"COALESCE({{title_col}}, $1)"
                              alias:@"display_title"
                 identifierBindings:@{ @"title_col" : @"d.title" }
                         parameters:@[ @"untitled" ]];
  [templateBuilder whereExpression:@"{{state_col}} = $1"
                identifierBindings:@{ @"state_col" : @"d.state_code" }
                        parameters:@[ @"TX" ]];
  [templateBuilder orderByExpression:@"COALESCE({{updated_col}}, {{created_col}})"
                          descending:NO
                               nulls:@"LAST"
                  identifierBindings:@{
                    @"updated_col" : @"d.updated_at",
                    @"created_col" : @"d.created_at",
                  }
                          parameters:nil];
  NSDictionary *templateBuilt = [templateBuilder build:error];
  if (templateBuilt == nil) {
    return nil;
  }
  results[@"template_select"] = @{
    @"sql" : templateBuilt[@"sql"] ?: @"",
    @"parameters" : templateBuilt[@"parameters"] ?: @[],
  };

  ALNSQLBuilder *active = [ALNSQLBuilder selectFrom:@"active_docs" columns:@[ @"doc_id" ]];
  [active whereField:@"state_code" equals:@"TX"];
  ALNSQLBuilder *archived = [ALNSQLBuilder selectFrom:@"archived_docs" columns:@[ @"doc_id" ]];
  [archived whereField:@"state_code" equals:@"TX"];
  ALNSQLBuilder *blocked = [ALNSQLBuilder selectFrom:@"blocked_docs" columns:@[ @"doc_id" ]];
  [blocked whereField:@"block_flag" equals:@1];
  [[active unionAllWith:archived] exceptWith:blocked];
  NSDictionary *setBuilt = [active build:error];
  if (setBuilt == nil) {
    return nil;
  }
  results[@"set_operation"] = @{
    @"sql" : setBuilt[@"sql"] ?: @"",
    @"parameters" : setBuilt[@"parameters"] ?: @[],
  };

  ALNSQLBuilder *orderingBuilder = [ALNSQLBuilder selectFrom:@"documents"
                                                        alias:@"d"
                                                      columns:@[ @"d.id" ]];
  [orderingBuilder orderByField:@"d.priority" descending:YES nulls:@"LAST"];
  [orderingBuilder orderByExpression:@"COALESCE({{updated_col}}, {{created_col}}, $1)"
                          descending:NO
                               nulls:@"FIRST"
                  identifierBindings:@{
                    @"updated_col" : @"d.updated_at",
                    @"created_col" : @"d.created_at",
                  }
                          parameters:@[ @"1970-01-01T00:00:00Z" ]];
  NSDictionary *orderingBuilt = [orderingBuilder build:error];
  if (orderingBuilt == nil) {
    return nil;
  }
  results[@"expression_ordering"] = @{
    @"sql" : orderingBuilt[@"sql"] ?: @"",
    @"parameters" : orderingBuilt[@"parameters"] ?: @[],
  };

  ALNSQLBuilder *latestEvent = [ALNSQLBuilder selectFrom:@"events"
                                                   alias:@"e"
                                                 columns:@[ @"e.event_id" ]];
  [latestEvent whereExpression:@"e.docket_id = d.id" parameters:nil];
  [latestEvent orderByExpression:@"COALESCE(e.updated_at, e.created_at)"
                      descending:YES
                           nulls:@"LAST"];
  [latestEvent limit:1];

  ALNSQLBuilder *lateralBuilder = [ALNSQLBuilder selectFrom:@"dockets"
                                                      alias:@"d"
                                                    columns:@[ @"d.id", @"d.state_code" ]];
  [lateralBuilder leftJoinLateralSubquery:latestEvent
                                    alias:@"le"
                             onExpression:@"TRUE"
                               parameters:nil];
  [lateralBuilder whereField:@"d.state_code" equals:@"TX"];
  [lateralBuilder orderByField:@"d.id" descending:NO nulls:nil];
  NSDictionary *lateralBuilt = [lateralBuilder build:error];
  if (lateralBuilt == nil) {
    return nil;
  }
  results[@"lateral_join"] = @{
    @"sql" : lateralBuilt[@"sql"] ?: @"",
    @"parameters" : lateralBuilt[@"parameters"] ?: @[],
  };

  ALNSQLBuilder *cursorBuilder = [ALNSQLBuilder selectFrom:@"documents"
                                                     alias:@"doc"
                                                   columns:@[ @"doc.document_id" ]];
  [cursorBuilder whereExpression:@"(COALESCE(doc.manifest_order, 0), doc.document_id) > ($1, $2)"
                      parameters:@[ @8, @"doc-002" ]];
  [cursorBuilder orderByExpression:@"COALESCE(doc.manifest_order, 0)"
                        descending:NO
                             nulls:@"LAST"];
  [cursorBuilder orderByField:@"doc.document_id" descending:NO nulls:nil];
  NSDictionary *cursorBuilt = [cursorBuilder build:error];
  if (cursorBuilt == nil) {
    return nil;
  }
  results[@"tuple_cursor"] = @{
    @"sql" : cursorBuilt[@"sql"] ?: @"",
    @"parameters" : cursorBuilt[@"parameters"] ?: @[],
  };

  ALNSQLBuilder *windowBuilder = [ALNSQLBuilder selectFrom:@"scores"
                                                      alias:@"s"
                                                    columns:@[ @"s.user_id" ]];
  [windowBuilder selectExpression:@"ROW_NUMBER() OVER {{win}}"
                            alias:@"row_num"
               identifierBindings:@{ @"win" : @"score_win" }
                       parameters:nil];
  [windowBuilder windowNamed:@"score_win"
                  expression:@"PARTITION BY {{team_col}} ORDER BY {{score_col}} DESC"
         identifierBindings:@{
           @"team_col" : @"s.team_id",
           @"score_col" : @"s.score",
         }
                  parameters:nil];
  [windowBuilder orderByField:@"s.user_id" descending:NO nulls:nil];
  NSDictionary *windowBuilt = [windowBuilder build:error];
  if (windowBuilt == nil) {
    return nil;
  }
  results[@"window_named"] = @{
    @"sql" : windowBuilt[@"sql"] ?: @"",
    @"parameters" : windowBuilt[@"parameters"] ?: @[],
  };

  ALNSQLBuilder *eventProbe = [ALNSQLBuilder selectFrom:@"events"
                                                  alias:@"e"
                                                columns:@[ @"e.user_id" ]];
  [eventProbe whereExpression:@"e.user_id = u.id" parameters:nil];
  ALNSQLBuilder *anyThreshold = [ALNSQLBuilder selectFrom:@"thresholds" columns:@[ @"value" ]];
  [anyThreshold whereField:@"category" equals:@"risk"];
  ALNSQLBuilder *allMinimum = [ALNSQLBuilder selectFrom:@"minima" columns:@[ @"min_score" ]];
  [allMinimum whereField:@"enabled" equals:@1];

  ALNSQLBuilder *predicateBuilder = [ALNSQLBuilder selectFrom:@"users"
                                                        alias:@"u"
                                                      columns:@[ @"u.id" ]];
  [predicateBuilder whereExistsSubquery:eventProbe];
  [predicateBuilder whereField:@"u.score" operator:@">=" anySubquery:anyThreshold];
  [predicateBuilder whereField:@"u.score" operator:@">=" allSubquery:allMinimum];
  [predicateBuilder orderByField:@"u.id" descending:NO nulls:nil];
  NSDictionary *predicateBuilt = [predicateBuilder build:error];
  if (predicateBuilt == nil) {
    return nil;
  }
  results[@"exists_any_all"] = @{
    @"sql" : predicateBuilt[@"sql"] ?: @"",
    @"parameters" : predicateBuilt[@"parameters"] ?: @[],
  };

  ALNSQLBuilder *lockBuilder = [ALNSQLBuilder selectFrom:@"queue_jobs"
                                                   alias:@"q"
                                                 columns:@[ @"q.id" ]];
  [lockBuilder whereField:@"q.state" equals:@"queued"];
  [lockBuilder orderByField:@"q.id" descending:NO nulls:nil];
  [lockBuilder limit:1];
  [lockBuilder forUpdateOfTables:@[ @"q" ]];
  [lockBuilder skipLocked];
  NSDictionary *lockBuilt = [lockBuilder build:error];
  if (lockBuilt == nil) {
    return nil;
  }
  results[@"locking_skip_locked"] = @{
    @"sql" : lockBuilt[@"sql"] ?: @"",
    @"parameters" : lockBuilt[@"parameters"] ?: @[],
  };

  ALNPostgresSQLBuilder *upsert =
      [ALNPostgresSQLBuilder insertInto:@"queue_jobs"
                                 values:@{
                                   @"attempt_count" : @0,
                                   @"id" : @9,
                                   @"state" : @"queued",
                                   @"updated_at" : @"2026-01-01T00:00:00Z",
                                 }];
  [upsert onConflictColumns:@[ @"id" ]
        doUpdateAssignments:@{
          @"attempt_count" : @{
            @"expression" : @"\"queue_jobs\".\"attempt_count\" + $1",
            @"parameters" : @[ @1 ],
          },
          @"state" : @"EXCLUDED.state",
          @"updated_at" : @{
            @"expression" : @"GREATEST(\"queue_jobs\".\"updated_at\", EXCLUDED.\"updated_at\", $1::text)",
            @"parameters" : @[ @"2026-01-02T00:00:00Z" ],
          },
        }];
  [upsert onConflictDoUpdateWhereExpression:@"\"queue_jobs\".\"state\" <> $1"
                                 parameters:@[ @"done" ]];
  [upsert returningField:@"id"];

  NSDictionary *upsertBuilt = [upsert build:error];
  if (upsertBuilt == nil) {
    return nil;
  }
  results[@"postgres_upsert_expression"] = @{
    @"sql" : upsertBuilt[@"sql"] ?: @"",
    @"parameters" : upsertBuilt[@"parameters"] ?: @[],
  };

  return results;
}

- (void)testConformanceMatrixMatchesExpectedSnapshots {
  NSDictionary *matrix = [self loadConformanceMatrixFixture];
  NSArray<NSDictionary *> *scenarios = [matrix[@"scenarios"] isKindOfClass:[NSArray class]]
                                            ? matrix[@"scenarios"]
                                            : @[];
  XCTAssertTrue([scenarios count] > 0);

  NSError *buildError = nil;
  NSDictionary<NSString *, NSDictionary *> *actual = [self buildConformanceScenarioResults:&buildError];
  XCTAssertNil(buildError);
  XCTAssertNotNil(actual);
  if (actual == nil) {
    return;
  }

  XCTAssertEqual((NSUInteger)[scenarios count], [actual count]);
  for (NSDictionary *scenario in scenarios) {
    NSString *scenarioID = [scenario[@"id"] isKindOfClass:[NSString class]] ? scenario[@"id"] : @"";
    XCTAssertTrue([scenarioID length] > 0);

    NSDictionary *expected = scenario;
    NSDictionary *observed = actual[scenarioID];
    XCTAssertNotNil(observed);
    if (observed == nil) {
      continue;
    }

    XCTAssertEqualObjects(expected[@"sql"], observed[@"sql"]);
    XCTAssertEqualObjects(expected[@"parameters"], observed[@"parameters"]);
    [self assertPlaceholderContractForSQL:observed[@"sql"] parameters:observed[@"parameters"]];
  }
}

- (void)testPropertyDeterministicParameterOrderingForInsertAndUpdate {
  uint32_t seed = 0x4e37u;
  NSArray<NSString *> *keys = @[ @"alpha", @"beta", @"gamma", @"delta" ];
  NSArray<NSString *> *sortedKeys = [keys sortedArrayUsingSelector:@selector(compare:)];

  NSMutableArray<NSString *> *quotedKeys = [NSMutableArray array];
  for (NSString *key in sortedKeys) {
    [quotedKeys addObject:[NSString stringWithFormat:@"\"%@\"", key]];
  }
  NSString *expectedInsertSQL =
      [NSString stringWithFormat:@"INSERT INTO \"kv_table\" (%@) VALUES ($1, $2, $3, $4)",
                                 [quotedKeys componentsJoinedByString:@", "]];
  NSString *expectedUpdateSQL =
      [NSString stringWithFormat:@"UPDATE \"kv_table\" SET \"alpha\" = $1, \"beta\" = $2, \"delta\" = $3, \"gamma\" = $4 WHERE \"id\" = $5"];

  for (NSUInteger iteration = 0; iteration < 140; iteration++) {
    NSArray<NSString *> *shuffled = [self shuffledKeys:keys seed:&seed];
    NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];
    for (NSString *key in shuffled) {
      values[key] = [self randomTokenWithSeed:&seed prefix:key];
    }

    NSMutableArray *expectedParams = [NSMutableArray arrayWithCapacity:[sortedKeys count]];
    for (NSString *key in sortedKeys) {
      [expectedParams addObject:values[key] ?: @""];
    }

    NSError *error = nil;
    NSDictionary *insertBuilt = [[ALNSQLBuilder insertInto:@"kv_table" values:values] build:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(insertBuilt);
    XCTAssertEqualObjects(expectedInsertSQL, insertBuilt[@"sql"]);
    XCTAssertEqualObjects(expectedParams, insertBuilt[@"parameters"]);
    [self assertPlaceholderContractForSQL:insertBuilt[@"sql"] parameters:insertBuilt[@"parameters"]];

    ALNSQLBuilder *update = [ALNSQLBuilder updateTable:@"kv_table" values:values];
    [update whereField:@"id" equals:@(iteration + 1)];
    NSDictionary *updateBuilt = [update build:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(updateBuilt);
    XCTAssertEqualObjects(expectedUpdateSQL, updateBuilt[@"sql"]);

    NSMutableArray *expectedUpdateParams = [NSMutableArray arrayWithArray:expectedParams];
    [expectedUpdateParams addObject:@(iteration + 1)];
    XCTAssertEqualObjects(expectedUpdateParams, updateBuilt[@"parameters"]);
    [self assertPlaceholderContractForSQL:updateBuilt[@"sql"] parameters:updateBuilt[@"parameters"]];
  }
}

- (void)testPropertyPlaceholderShiftingAcrossExpressionComposition {
  uint32_t seed = 0x7f9b33u;
  NSArray *nullsDirectives = @[ @"FIRST", @"LAST", [NSNull null] ];

  for (NSUInteger iteration = 0; iteration < 180; iteration++) {
    ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"documents"
                                                 alias:@"d"
                                               columns:@[ @"d.id" ]];

    NSUInteger selectExpressionCount = [self randomValueWithSeed:&seed min:1 max:3];
    for (NSUInteger index = 0; index < selectExpressionCount; index++) {
      NSUInteger paramCount = [self randomValueWithSeed:&seed min:1 max:3];
      NSMutableArray *params = [NSMutableArray arrayWithCapacity:paramCount];
      NSMutableString *expression =
          [NSMutableString stringWithFormat:@"COALESCE(d.sel_%lu, $1)", (unsigned long)index];
      [params addObject:[self randomTokenWithSeed:&seed prefix:@"s"]];
      if (paramCount >= 2) {
        [expression appendString:@" <> $2"];
        [params addObject:[self randomTokenWithSeed:&seed prefix:@"s"]];
      }
      if (paramCount >= 3) {
        [expression appendString:@" OR $3 = $3"];
        [params addObject:[self randomTokenWithSeed:&seed prefix:@"s"]];
      }

      [builder selectExpression:expression
                          alias:[NSString stringWithFormat:@"expr_%lu", (unsigned long)index]
                     parameters:params];
    }

    NSUInteger whereParamCount = [self randomValueWithSeed:&seed min:1 max:3];
    NSMutableArray *whereParams = [NSMutableArray arrayWithCapacity:whereParamCount];
    NSMutableString *whereExpression = [NSMutableString stringWithString:@"COALESCE(d.rank, $1) >= $1"];
    [whereParams addObject:@([self randomValueWithSeed:&seed min:0 max:99])];
    if (whereParamCount >= 2) {
      [whereExpression appendString:@" AND d.state_code <> $2"];
      [whereParams addObject:[self randomTokenWithSeed:&seed prefix:@"state"]];
    }
    if (whereParamCount >= 3) {
      [whereExpression appendString:@" AND $3 = $3"];
      [whereParams addObject:[self randomTokenWithSeed:&seed prefix:@"guard"]];
    }
    [builder whereExpression:whereExpression parameters:whereParams];

    id nullsValue = nullsDirectives[[self randomValueWithSeed:&seed min:0 max:2]];
    NSString *nulls = [nullsValue isKindOfClass:[NSString class]] ? nullsValue : nil;
    [builder orderByExpression:@"COALESCE(d.updated_at, d.created_at)"
                    descending:([self randomValueWithSeed:&seed min:0 max:1] == 1)
                         nulls:nulls];
    [builder orderByExpression:@"COALESCE(d.sort_rank, $1)"
                    descending:NO
                         nulls:nil
                    parameters:@[ @([self randomValueWithSeed:&seed min:0 max:5]) ]];

    NSError *error = nil;
    NSDictionary *built = [builder build:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(built);
    if (built == nil) {
      continue;
    }
    [self assertPlaceholderContractForSQL:built[@"sql"] parameters:built[@"parameters"]];
  }
}

- (void)testPropertyTuplePredicatesPreserveParameterOrder {
  uint32_t seed = 0x9911u;
  NSArray<NSString *> *states = @[ @"AL", @"TX", @"NY", @"WA" ];

  for (NSUInteger iteration = 0; iteration < 180; iteration++) {
    NSInteger lowerBound = (NSInteger)[self randomValueWithSeed:&seed min:0 max:500];
    NSString *documentID = [self randomTokenWithSeed:&seed prefix:@"doc"];
    NSString *state = states[[self randomValueWithSeed:&seed min:0 max:(NSUInteger)([states count] - 1)]];

    ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"documents"
                                                 alias:@"d"
                                               columns:@[ @"d.document_id", @"d.manifest_order" ]];
    [builder whereExpression:@"(COALESCE(d.manifest_order, 0), d.document_id) > ($1, $2)"
                  parameters:@[ @(lowerBound), documentID ]];
    [builder whereField:@"d.state_code" equals:state];
    [builder orderByExpression:@"COALESCE(d.manifest_order, 0)"
                    descending:NO
                         nulls:@"LAST"];
    [builder orderByField:@"d.document_id" descending:NO nulls:nil];

    NSError *error = nil;
    NSDictionary *built = [builder build:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(built);
    if (built == nil) {
      continue;
    }

    NSArray *expectedParams = @[ @(lowerBound), documentID, state ];
    XCTAssertEqualObjects(expectedParams, built[@"parameters"]);
    [self assertPlaceholderContractForSQL:built[@"sql"] parameters:built[@"parameters"]];
  }
}

- (void)testLongRunRegressionSuiteForNestedExpressionShapes {
  uint32_t seed = 0x20260220u;
  NSArray *states = @[ @"queued", @"running", @"done" ];

  for (NSUInteger iteration = 0; iteration < 260; iteration++) {
    ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"queue_jobs"
                                                 alias:@"q"
                                               columns:@[ @"q.id", @"q.state" ]];

    NSUInteger groupCount = [self randomValueWithSeed:&seed min:1 max:3];
    for (NSUInteger groupIndex = 0; groupIndex < groupCount; groupIndex++) {
      NSInteger minRank = (NSInteger)[self randomValueWithSeed:&seed min:0 max:50];
      NSString *state = states[[self randomValueWithSeed:&seed min:0 max:(NSUInteger)([states count] - 1)]];
      NSString *cursorID = [self randomTokenWithSeed:&seed prefix:@"cursor"];

      [builder whereAnyGroup:^(ALNSQLBuilder *group) {
        [group whereExpression:@"COALESCE(q.rank, $1) >= $2"
                    parameters:@[ @(minRank), @(minRank) ]];

        [group whereAllGroup:^(ALNSQLBuilder *nested) {
          [nested whereExpression:@"{{state_col}} = $1"
               identifierBindings:@{ @"state_col" : @"q.state" }
                       parameters:@[ state ]];
          [nested whereExpression:@"(COALESCE(q.manifest_order, 0), q.id) > ($1, $2)"
                       parameters:@[ @(minRank), cursorID ]];
        }];
      }];
    }

    [builder orderByExpression:@"COALESCE(q.rank, $1)"
                    descending:NO
                         nulls:nil
                    parameters:@[ @0 ]];
    [builder orderByField:@"q.id" descending:NO nulls:nil];
    [builder limit:[self randomValueWithSeed:&seed min:1 max:50]];

    NSError *error = nil;
    NSDictionary *built = [builder build:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(built);
    if (built == nil) {
      continue;
    }
    [self assertPlaceholderContractForSQL:built[@"sql"] parameters:built[@"parameters"]];
  }
}

- (void)testMigrationGuideRepresentativeFlowCompilesAndPreservesContracts {
  ALNSQLBuilder *latestEvent = [ALNSQLBuilder selectFrom:@"events"
                                                   alias:@"e"
                                                 columns:@[ @"e.event_id" ]];
  [latestEvent whereExpression:@"e.docket_id = d.docket_id" parameters:nil];
  [latestEvent orderByExpression:@"COALESCE(e.updated_at, e.created_at)"
                      descending:YES
                           nulls:@"LAST"];
  [latestEvent limit:1];

  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"documents"
                                               alias:@"d"
                                             columns:@[ @"d.document_id", @"d.state_code" ]];
  [builder selectExpression:@"COALESCE({{title_col}}, $1)"
                      alias:@"display_title"
         identifierBindings:@{ @"title_col" : @"d.title" }
                 parameters:@[ @"untitled" ]];
  [builder leftJoinLateralSubquery:latestEvent
                             alias:@"le"
                      onExpression:@"TRUE"
                        parameters:nil];
  [builder whereExpression:@"{{state_col}} = $1"
        identifierBindings:@{ @"state_col" : @"d.state_code" }
                parameters:@[ @"TX" ]];
  [builder whereExpression:@"(COALESCE(d.manifest_order, 0), d.document_id) > ($1, $2)"
                parameters:@[ @15, @"doc_000015" ]];
  [builder orderByExpression:@"COALESCE({{manifest_col}}, $1)"
                  descending:NO
                       nulls:@"LAST"
          identifierBindings:@{ @"manifest_col" : @"d.manifest_order" }
                  parameters:@[ @0 ]];
  [builder orderByField:@"d.document_id" descending:NO nulls:nil];
  [builder limit:25];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  if (built == nil) {
    return;
  }

  NSString *sql = built[@"sql"];
  XCTAssertTrue([sql containsString:@"LEFT JOIN LATERAL"]);
  XCTAssertTrue([sql containsString:@"COALESCE(\"d\".\"title\", $1)"]);
  XCTAssertTrue([sql containsString:@"(COALESCE(d.manifest_order, 0), d.document_id) > ($3, $4)"]);
  [self assertPlaceholderContractForSQL:sql parameters:built[@"parameters"]];
}

@end

#import <Foundation/Foundation.h>

#import "ALNDataverseMetadata.h"
#import "ArlenORM/ArlenORM.h"

static NSDictionary *ALNPhase26ORMPerfLoadJSON(NSString *path) {
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (data == nil) {
    return nil;
  }
  NSError *error = nil;
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

static NSTimeInterval ALNPhase26ORMPerfMeasure(NSUInteger iterations, BOOL (^block)(void)) {
  NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
  for (NSUInteger index = 0; index < iterations; index++) {
    if (block != nil && !block()) {
      return -1.0;
    }
  }
  return [NSDate timeIntervalSinceReferenceDate] - start;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    (void)argc;
    (void)argv;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *repoRoot = [fileManager currentDirectoryPath] ?: @".";
    NSString *sqlFixturePath =
        [repoRoot stringByAppendingPathComponent:@"tests/fixtures/phase26/orm_schema_metadata_contract.json"];
    NSString *dataverseFixturePath =
        [repoRoot stringByAppendingPathComponent:@"tests/fixtures/phase23/dataverse_entitydefinitions.json"];
    NSString *outputPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"ARLEN_PHASE26_PERF_OUTPUT"];
    if ([outputPath length] == 0) {
      outputPath = [repoRoot stringByAppendingPathComponent:@"build/release_confidence/phase26/perf/perf_smoke.json"];
    }

    NSDictionary *sqlFixture = ALNPhase26ORMPerfLoadJSON(sqlFixturePath);
    NSDictionary *dataverseFixture = ALNPhase26ORMPerfLoadJSON(dataverseFixturePath);
    if (sqlFixture == nil || dataverseFixture == nil) {
      fprintf(stderr, "phase26-orm-perf: failed to load fixture JSON\n");
      return 1;
    }

    NSError *error = nil;
    NSDictionary *dataverseNormalized =
        [ALNDataverseMetadata normalizedMetadataFromPayload:dataverseFixture error:&error];
    if (dataverseNormalized == nil || error != nil) {
      fprintf(stderr, "phase26-orm-perf: Dataverse metadata normalization failed: %s\n",
              [[error localizedDescription] UTF8String]);
      return 1;
    }

    NSDictionary *sqlMetadata = [sqlFixture[@"metadata"] isKindOfClass:[NSDictionary class]] ? sqlFixture[@"metadata"] : @{};

    const NSUInteger sqlIterations = 250;
    const NSUInteger snapshotIterations = 250;
    const NSUInteger dataverseIterations = 250;

    __block NSArray<ALNORMModelDescriptor *> *sqlDescriptors = nil;
    NSTimeInterval sqlSeconds = ALNPhase26ORMPerfMeasure(sqlIterations, ^BOOL {
      NSError *innerError = nil;
      sqlDescriptors = [ALNORMCodegen modelDescriptorsFromSchemaMetadata:sqlMetadata
                                                             classPrefix:@"ALNPerf"
                                                                   error:&innerError];
      return (sqlDescriptors != nil && innerError == nil);
    });
    if (sqlSeconds < 0.0) {
      fprintf(stderr, "phase26-orm-perf: SQL descriptor generation failed\n");
      return 1;
    }

    __block NSDictionary<NSString *, id> *snapshot = nil;
    NSTimeInterval snapshotSeconds = ALNPhase26ORMPerfMeasure(snapshotIterations, ^BOOL {
      snapshot = [ALNORMDescriptorSnapshot snapshotDocumentWithModelDescriptors:sqlDescriptors
                                                                 databaseTarget:@"postgresql"
                                                                          label:@"perf-smoke"];
      NSArray<NSDictionary<NSString *, id> *> *diagnostics = nil;
      NSError *innerError = nil;
      BOOL valid = [ALNORMSchemaDrift validateModelDescriptors:sqlDescriptors
                                       againstSnapshotDocument:snapshot
                                                   diagnostics:&diagnostics
                                                         error:&innerError];
      return valid && innerError == nil && [diagnostics count] == 0;
    });
    if (snapshotSeconds < 0.0) {
      fprintf(stderr, "phase26-orm-perf: descriptor snapshot validation failed\n");
      return 1;
    }

    __block NSArray<ALNORMDataverseModelDescriptor *> *dataverseDescriptors = nil;
    NSTimeInterval dataverseSeconds = ALNPhase26ORMPerfMeasure(dataverseIterations, ^BOOL {
      NSError *innerError = nil;
      dataverseDescriptors = [ALNORMDataverseCodegen modelDescriptorsFromMetadata:dataverseNormalized
                                                                       classPrefix:@"ALNPerfDV"
                                                                   dataverseTarget:@"crm"
                                                                             error:&innerError];
      return (dataverseDescriptors != nil && innerError == nil);
    });
    if (dataverseSeconds < 0.0) {
      fprintf(stderr, "phase26-orm-perf: Dataverse descriptor generation failed\n");
      return 1;
    }

    NSDictionary *payload = @{
      @"version" : @"phase26-orm-perf-v1",
      @"sql_iterations" : @(sqlIterations),
      @"snapshot_iterations" : @(snapshotIterations),
      @"dataverse_iterations" : @(dataverseIterations),
      @"sql_descriptor_count" : @([sqlDescriptors count]),
      @"dataverse_descriptor_count" : @([dataverseDescriptors count]),
      @"sql_codegen_ms" : @((long long)llround(sqlSeconds * 1000.0)),
      @"snapshot_validation_ms" : @((long long)llround(snapshotSeconds * 1000.0)),
      @"dataverse_codegen_ms" : @((long long)llround(dataverseSeconds * 1000.0)),
    };

    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:&error];
    if (json == nil || error != nil) {
      fprintf(stderr, "phase26-orm-perf: failed to encode output JSON\n");
      return 1;
    }
    NSString *outputDir = [outputPath stringByDeletingLastPathComponent];
    [fileManager createDirectoryAtPath:outputDir withIntermediateDirectories:YES attributes:nil error:NULL];
    if (![json writeToFile:outputPath atomically:YES]) {
      fprintf(stderr, "phase26-orm-perf: failed writing %s\n", [outputPath UTF8String]);
      return 1;
    }

    printf("phase26-orm-perf: wrote %s\n", [outputPath UTF8String]);
    return 0;
  }
}

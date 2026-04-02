#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNTestSupport.h"
#import "ArlenORM/ArlenORM.h"

static NSArray<ALNORMModelDescriptor *> *ALNORMMigrationDescriptors(void) {
  static NSArray<ALNORMModelDescriptor *> *descriptors = nil;
  if (descriptors == nil) {
    NSError *error = nil;
    NSDictionary *fixture =
        ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase26/orm_schema_metadata_contract.json", &error);
    NSDictionary *metadata = [fixture[@"metadata"] isKindOfClass:[NSDictionary class]] ? fixture[@"metadata"] : @{};
    descriptors = [ALNORMCodegen modelDescriptorsFromSchemaMetadata:metadata
                                                        classPrefix:@"ALNORMMigration"
                                                              error:&error];
  }
  return descriptors ?: @[];
}

@interface ORMMigrationTests : XCTestCase
@end

@implementation ORMMigrationTests

- (void)testDescriptorSnapshotsRoundTripDeterministically {
  NSArray<ALNORMModelDescriptor *> *descriptors = ALNORMMigrationDescriptors();
  NSDictionary<NSString *, id> *snapshot =
      [ALNORMDescriptorSnapshot snapshotDocumentWithModelDescriptors:descriptors
                                                      databaseTarget:@"postgresql"
                                                               label:@"phase26-history"];
  XCTAssertEqualObjects(snapshot[@"format"], [ALNORMDescriptorSnapshot formatVersion]);
  XCTAssertEqualObjects(snapshot[@"descriptor_count"], @([descriptors count]));

  NSError *error = nil;
  NSArray<ALNORMModelDescriptor *> *replayed =
      [ALNORMDescriptorSnapshot modelDescriptorsFromSnapshotDocument:snapshot error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)[descriptors count], [replayed count]);

  for (NSUInteger index = 0; index < [descriptors count]; index++) {
    XCTAssertEqualObjects([descriptors[index] dictionaryRepresentation],
                          [replayed[index] dictionaryRepresentation]);
  }
}

- (void)testSchemaDriftDiagnosticsFailClosedWhenDescriptorsChange {
  NSArray<ALNORMModelDescriptor *> *descriptors = ALNORMMigrationDescriptors();
  NSDictionary<NSString *, id> *snapshot =
      [ALNORMDescriptorSnapshot snapshotDocumentWithModelDescriptors:descriptors
                                                      databaseTarget:@"postgresql"
                                                               label:@"phase26-history"];

  ALNORMModelDescriptor *original = [descriptors firstObject];
  NSArray<ALNORMFieldDescriptor *> *trimmedFields =
      [[original fields] subarrayWithRange:NSMakeRange(0, MAX((NSUInteger)1, [original.fields count] - 1))];
  ALNORMModelDescriptor *changed =
      [[ALNORMModelDescriptor alloc] initWithClassName:original.className
                                            entityName:original.entityName
                                            schemaName:original.schemaName
                                             tableName:original.tableName
                                    qualifiedTableName:original.qualifiedTableName
                                          relationKind:original.relationKind
                                        databaseTarget:original.databaseTarget
                                              readOnly:original.isReadOnly
                                                fields:trimmedFields
                                  primaryKeyFieldNames:original.primaryKeyFieldNames
                              uniqueConstraintFieldSets:original.uniqueConstraintFieldSets
                                             relations:original.relations];

  NSMutableArray<ALNORMModelDescriptor *> *current = [NSMutableArray arrayWithArray:descriptors];
  current[0] = changed;

  NSArray<NSDictionary<NSString *, id> *> *diagnostics =
      [ALNORMSchemaDrift diagnosticsByComparingSnapshotDocument:snapshot toModelDescriptors:current];
  XCTAssertGreaterThan((NSUInteger)[diagnostics count], (NSUInteger)0);
  XCTAssertEqualObjects(diagnostics[0][@"kind"], @"entity_changed");
  XCTAssertEqualObjects(diagnostics[0][@"entity_name"], original.entityName);

  NSError *error = nil;
  NSArray<NSDictionary<NSString *, id> *> *validatedDiagnostics = nil;
  BOOL valid = [ALNORMSchemaDrift validateModelDescriptors:current
                                   againstSnapshotDocument:snapshot
                                               diagnostics:&validatedDiagnostics
                                                     error:&error];
  XCTAssertFalse(valid);
  XCTAssertNotNil(error);
  XCTAssertEqual(ALNORMErrorValidationFailed, error.code);
  XCTAssertEqualObjects(validatedDiagnostics, diagnostics);
}

@end

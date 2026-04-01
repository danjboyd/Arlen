#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNDataverseTestSupport.h"
#import "../shared/ALNTestSupport.h"
#import "ArlenORM/ArlenORM.h"

static NSArray<ALNORMModelDescriptor *> *ALNORMBackendParityDescriptors(void) {
  static NSArray<ALNORMModelDescriptor *> *descriptors = nil;
  if (descriptors == nil) {
    NSError *error = nil;
    NSDictionary *fixture =
        ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase26/orm_schema_metadata_contract.json", &error);
    descriptors = [ALNORMCodegen modelDescriptorsFromSchemaMetadata:fixture[@"metadata"]
                                                        classPrefix:@"ALNORMBackend"
                                                              error:&error];
  }
  return descriptors ?: @[];
}

static ALNORMModelDescriptor *ALNORMBackendParityDescriptorNamed(NSString *entityName) {
  for (ALNORMModelDescriptor *descriptor in ALNORMBackendParityDescriptors()) {
    if ([descriptor.entityName isEqualToString:entityName]) {
      return descriptor;
    }
  }
  return nil;
}

@interface ALNORMBackendUser : ALNORMModel
@end
@implementation ALNORMBackendUser
+ (ALNORMModelDescriptor *)modelDescriptor { return ALNORMBackendParityDescriptorNamed(@"public.users"); }
@end

@interface ORMBackendParityAdapter : NSObject <ALNDatabaseAdapter>
@property(nonatomic, copy) NSString *adapterNameValue;
@property(nonatomic, copy) NSDictionary<NSString *, id> *capabilities;
- (instancetype)initWithName:(NSString *)adapterName capabilities:(NSDictionary<NSString *, id> *)capabilities;
@end

@implementation ORMBackendParityAdapter
- (instancetype)initWithName:(NSString *)adapterName capabilities:(NSDictionary<NSString *,id> *)capabilities {
  self = [super init];
  if (self != nil) {
    _adapterNameValue = [adapterName copy] ?: @"postgresql";
    _capabilities = [capabilities copy] ?: @{};
  }
  return self;
}
- (NSString *)adapterName { return self.adapterNameValue ?: @"postgresql"; }
- (NSDictionary<NSString *,id> *)capabilityMetadata { return self.capabilities ?: @{}; }
- (id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  return (id<ALNDatabaseConnection>)self;
}
- (void)releaseAdapterConnection:(id<ALNDatabaseConnection>)connection {
  (void)connection;
}
- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  (void)sql;
  (void)parameters;
  if (error != NULL) {
    *error = nil;
  }
  return @[];
}
- (NSInteger)executeCommand:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  (void)sql;
  (void)parameters;
  if (error != NULL) {
    *error = nil;
  }
  return 0;
}
- (BOOL)withTransactionUsingBlock:(BOOL (^)(id<ALNDatabaseConnection>, NSError **))block error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  return (block != nil) ? block((id<ALNDatabaseConnection>)self, error) : YES;
}
@end

@interface ORMBackendParityTests : ALNDataverseTestCase
@end

@implementation ORMBackendParityTests

- (void)testSQLCapabilityMetadataIsExplicitForPostgresAndMSSQL {
  ORMBackendParityAdapter *postgres = [[ORMBackendParityAdapter alloc] initWithName:@"postgresql" capabilities:@{}];
  NSDictionary<NSString *, id> *postgresMeta = [ALNORMContext capabilityMetadataForAdapter:postgres];
  XCTAssertEqualObjects(postgresMeta[@"adapter_name"], @"postgresql");
  XCTAssertEqualObjects(postgresMeta[@"supports_schema_reflection"], @YES);
  XCTAssertEqualObjects(postgresMeta[@"supports_upsert"], @YES);
  XCTAssertEqualObjects(postgresMeta[@"supports_generated_models"], @YES);

  ORMBackendParityAdapter *mssql = [[ORMBackendParityAdapter alloc]
      initWithName:@"mssql"
      capabilities:@{
        @"supports_sql_runtime" : @YES,
        @"supports_schema_reflection" : @NO,
        @"supports_upsert" : @NO,
      }];
  NSDictionary<NSString *, id> *mssqlMeta = [ALNORMContext capabilityMetadataForAdapter:mssql];
  XCTAssertEqualObjects(mssqlMeta[@"adapter_name"], @"mssql");
  XCTAssertEqualObjects(mssqlMeta[@"supports_schema_reflection"], @NO);
  XCTAssertEqualObjects(mssqlMeta[@"supports_upsert"], @NO);
  XCTAssertTrue([mssqlMeta[@"boundary_note"] containsString:@"not yet available"] ||
                [mssqlMeta[@"boundary_note"] containsString:@"not yet"]);
}

- (void)testDataverseCapabilityMetadataStaysHonestAboutSupportBoundaries {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  NSDictionary<NSString *, id> *metadata = [ALNORMDataverseContext capabilityMetadataForClient:client];
  XCTAssertEqualObjects(metadata[@"adapter_name"], @"dataverse");
  XCTAssertEqualObjects(metadata[@"supports_sql_runtime"], @NO);
  XCTAssertEqualObjects(metadata[@"supports_dataverse_orm"], @YES);
  XCTAssertEqualObjects(metadata[@"supports_reverse_collections"], @YES);
  XCTAssertEqualObjects(metadata[@"supports_many_to_many"], @NO);
  XCTAssertEqualObjects(metadata[@"supports_transactions"], @NO);
}

- (void)testAdminResourceBridgeDerivesErgonomicDefaultsFromModelDescriptor {
  ALNORMAdminResource *resource = [ALNORMAdminResource resourceForModelClass:[ALNORMBackendUser class]];
  XCTAssertNotNil(resource);
  XCTAssertEqualObjects(resource.entityName, @"public.users");
  XCTAssertEqualObjects(resource.titleFieldName, @"displayName");
  XCTAssertTrue([resource.searchableFieldNames containsObject:@"email"]);
  XCTAssertTrue([resource.sortableFieldNames containsObject:@"displayName"]);
  XCTAssertFalse(resource.isReadOnly);

  NSDictionary<NSString *, id> *rendered = [resource dictionaryRepresentation];
  XCTAssertEqualObjects(rendered[@"resource_name"], @"users");
  XCTAssertEqualObjects(rendered[@"entity_name"], @"public.users");
}

@end

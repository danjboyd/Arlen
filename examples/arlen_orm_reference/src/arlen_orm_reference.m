#import <Foundation/Foundation.h>

#import "ALNDataverseMetadata.h"
#import "ArlenORM/ArlenORM.h"

static NSDictionary *ALNORMReferenceLoadJSON(NSString *path) {
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (data == nil) {
    return nil;
  }
  NSError *error = nil;
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    (void)argc;
    (void)argv;
    NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath] ?: @".";
    NSDictionary *sqlFixture =
        ALNORMReferenceLoadJSON([repoRoot stringByAppendingPathComponent:@"tests/fixtures/phase26/orm_schema_metadata_contract.json"]);
    NSDictionary *dvFixture =
        ALNORMReferenceLoadJSON([repoRoot stringByAppendingPathComponent:@"tests/fixtures/phase23/dataverse_entitydefinitions.json"]);

    NSError *error = nil;
    NSArray<ALNORMModelDescriptor *> *sqlDescriptors =
        [ALNORMCodegen modelDescriptorsFromSchemaMetadata:sqlFixture[@"metadata"]
                                              classPrefix:@"ALNReference"
                                                    error:&error];
    if (sqlDescriptors == nil || error != nil) {
      NSLog(@"SQL descriptor generation failed: %@", error);
      return 1;
    }

    NSDictionary *snapshot =
        [ALNORMDescriptorSnapshot snapshotDocumentWithModelDescriptors:sqlDescriptors
                                                        databaseTarget:@"postgresql"
                                                                 label:@"reference"];
    NSDictionary *sqlMeta = [ALNORMContext capabilityMetadataForAdapter:nil];

    NSDictionary *dvNormalized = [ALNDataverseMetadata normalizedMetadataFromPayload:dvFixture error:&error];
    NSArray<ALNORMDataverseModelDescriptor *> *dvDescriptors =
        [ALNORMDataverseCodegen modelDescriptorsFromMetadata:dvNormalized
                                                 classPrefix:@"ALNReferenceDV"
                                             dataverseTarget:@"crm"
                                                       error:&error];
    if (dvDescriptors == nil || error != nil) {
      NSLog(@"Dataverse descriptor generation failed: %@", error);
      return 1;
    }

    NSLog(@"Arlen ORM reference");
    NSLog(@"  SQL descriptors: %lu", (unsigned long)[sqlDescriptors count]);
    NSLog(@"  Snapshot format: %@", snapshot[@"format"]);
    NSLog(@"  SQL supports generated models: %@", [sqlMeta[@"supports_generated_models"] boolValue] ? @"yes" : @"no");
    NSLog(@"  Dataverse descriptors: %lu", (unsigned long)[dvDescriptors count]);
    NSLog(@"  Dataverse first entity: %@", [[dvDescriptors firstObject] logicalName] ?: @"");
    return 0;
  }
}

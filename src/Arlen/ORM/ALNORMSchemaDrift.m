#import "ALNORMSchemaDrift.h"

#import "ALNORMErrors.h"

static NSDictionary<NSString *, NSDictionary<NSString *, id> *> *ALNORMSchemaDriftIndexDescriptors(
    NSArray<ALNORMModelDescriptor *> *descriptors) {
  NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *indexed = [NSMutableDictionary dictionary];
  for (ALNORMModelDescriptor *descriptor in descriptors ?: @[]) {
    indexed[descriptor.entityName ?: @""] = [descriptor dictionaryRepresentation];
  }
  return [NSDictionary dictionaryWithDictionary:indexed];
}

static NSString *ALNORMSchemaDriftJSONString(id value) {
  NSError *error = nil;
  NSJSONWritingOptions options = 0;
#ifdef NSJSONWritingSortedKeys
  options |= NSJSONWritingSortedKeys;
#endif
  NSData *data = [NSJSONSerialization dataWithJSONObject:value ?: @{} options:options error:&error];
  if (data == nil || error != nil) {
    return @"";
  }
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

@implementation ALNORMSchemaDrift

+ (NSArray<NSDictionary<NSString *, id> *> *)diagnosticsByComparingSnapshotDocument:
                                               (NSDictionary<NSString *, id> *)snapshotDocument
                                                            toModelDescriptors:
                                                                (NSArray<ALNORMModelDescriptor *> *)descriptors {
  NSError *snapshotError = nil;
  NSArray<ALNORMModelDescriptor *> *snapshotDescriptors =
      [ALNORMDescriptorSnapshot modelDescriptorsFromSnapshotDocument:snapshotDocument error:&snapshotError];
  if (snapshotDescriptors == nil) {
    return @[
      @{
        @"kind" : @"invalid_snapshot",
        @"message" : snapshotError.localizedDescription ?: @"invalid snapshot",
      },
    ];
  }

  NSDictionary<NSString *, NSDictionary<NSString *, id> *> *snapshotIndex =
      ALNORMSchemaDriftIndexDescriptors(snapshotDescriptors);
  NSDictionary<NSString *, NSDictionary<NSString *, id> *> *currentIndex =
      ALNORMSchemaDriftIndexDescriptors(descriptors);
  NSMutableArray<NSDictionary<NSString *, id> *> *diagnostics = [NSMutableArray array];

  NSSet<NSString *> *allEntityNames =
      [NSSet setWithArray:[snapshotIndex.allKeys arrayByAddingObjectsFromArray:currentIndex.allKeys]];
  for (NSString *entityName in [[allEntityNames allObjects] sortedArrayUsingSelector:@selector(compare:)]) {
    NSDictionary<NSString *, id> *snapshotDescriptor = snapshotIndex[entityName];
    NSDictionary<NSString *, id> *currentDescriptor = currentIndex[entityName];
    if (snapshotDescriptor == nil) {
      [diagnostics addObject:@{
        @"kind" : @"entity_added",
        @"entity_name" : entityName ?: @"",
        @"message" : @"entity exists in current descriptors but not in the historical snapshot",
      }];
      continue;
    }
    if (currentDescriptor == nil) {
      [diagnostics addObject:@{
        @"kind" : @"entity_removed",
        @"entity_name" : entityName ?: @"",
        @"message" : @"entity exists in the historical snapshot but not in current descriptors",
      }];
      continue;
    }
    if (![ALNORMSchemaDriftJSONString(snapshotDescriptor) isEqualToString:ALNORMSchemaDriftJSONString(currentDescriptor)]) {
      [diagnostics addObject:@{
        @"kind" : @"entity_changed",
        @"entity_name" : entityName ?: @"",
        @"message" : @"entity descriptor diverged from the historical snapshot",
      }];
    }
  }
  return [NSArray arrayWithArray:diagnostics];
}

+ (BOOL)validateModelDescriptors:(NSArray<ALNORMModelDescriptor *> *)descriptors
          againstSnapshotDocument:(NSDictionary<NSString *, id> *)snapshotDocument
                      diagnostics:(NSArray<NSDictionary<NSString *, id> *> **)diagnostics
                            error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSArray<NSDictionary<NSString *, id> *> *resolvedDiagnostics =
      [self diagnosticsByComparingSnapshotDocument:snapshotDocument toModelDescriptors:descriptors];
  if (diagnostics != NULL) {
    *diagnostics = resolvedDiagnostics;
  }
  if ([resolvedDiagnostics count] == 0) {
    return YES;
  }
  if (error != NULL) {
    *error = ALNORMMakeError(ALNORMErrorValidationFailed,
                             @"schema/codegen drift detected against the historical descriptor snapshot",
                             @{
                               @"diagnostics" : resolvedDiagnostics,
                             });
  }
  return NO;
}

@end

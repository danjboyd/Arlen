#import "ALNORMWriteOptions.h"

@implementation ALNORMWriteOptions

+ (instancetype)options {
  return [[self alloc] init];
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _optimisticLockFieldName = @"";
    _createdAtFieldName = @"";
    _updatedAtFieldName = @"";
    _conflictFieldNames = @[];
    _saveRelatedRelationNames = @[];
    _overwriteAllFields = NO;
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  ALNORMWriteOptions *copy = [[[self class] allocWithZone:zone] init];
  copy.optimisticLockFieldName = self.optimisticLockFieldName ?: @"";
  copy.createdAtFieldName = self.createdAtFieldName ?: @"";
  copy.updatedAtFieldName = self.updatedAtFieldName ?: @"";
  copy.conflictFieldNames = [self.conflictFieldNames copy] ?: @[];
  copy.saveRelatedRelationNames = [self.saveRelatedRelationNames copy] ?: @[];
  copy.timestampValue = self.timestampValue;
  copy.overwriteAllFields = self.overwriteAllFields;
  return copy;
}

@end

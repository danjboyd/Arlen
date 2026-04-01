#import "ALNORMDataverseFieldDescriptor.h"

@implementation ALNORMDataverseFieldDescriptor

- (instancetype)init {
  return [self initWithLogicalName:@""
                        schemaName:@""
                       displayName:@""
                     attributeType:@"String"
                           readKey:@""
                          objcType:@"id"
                  runtimeClassName:@""
                          nullable:YES
                         primaryID:NO
                       primaryName:NO
                           logical:NO
                          readable:YES
                         creatable:YES
                        updateable:YES
                           targets:nil
                           choices:nil];
}

- (instancetype)initWithLogicalName:(NSString *)logicalName
                         schemaName:(NSString *)schemaName
                        displayName:(NSString *)displayName
                      attributeType:(NSString *)attributeType
                            readKey:(NSString *)readKey
                           objcType:(NSString *)objcType
                   runtimeClassName:(NSString *)runtimeClassName
                           nullable:(BOOL)nullable
                          primaryID:(BOOL)primaryID
                        primaryName:(BOOL)primaryName
                            logical:(BOOL)logical
                           readable:(BOOL)readable
                          creatable:(BOOL)creatable
                         updateable:(BOOL)updateable
                            targets:(NSArray<NSString *> *)targets
                            choices:(NSArray<NSDictionary<NSString *, id> *> *)choices {
  self = [super init];
  if (self != nil) {
    _logicalName = [logicalName copy] ?: @"";
    _schemaName = [schemaName copy] ?: @"";
    _displayName = [displayName copy] ?: @"";
    _attributeType = [attributeType copy] ?: @"String";
    _readKey = [readKey copy] ?: @"";
    _objcType = [objcType copy] ?: @"id";
    _runtimeClassName = [runtimeClassName copy] ?: @"";
    _nullable = nullable;
    _primaryID = primaryID;
    _primaryName = primaryName;
    _logical = logical;
    _readable = readable;
    _creatable = creatable;
    _updateable = updateable;
    _targets = [targets copy] ?: @[];
    _choices = [choices copy] ?: @[];
  }
  return self;
}

- (BOOL)isLookup {
  return [self.targets count] > 0;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
  return @{
    @"logical_name" : self.logicalName ?: @"",
    @"schema_name" : self.schemaName ?: @"",
    @"display_name" : self.displayName ?: @"",
    @"attribute_type" : self.attributeType ?: @"",
    @"read_key" : self.readKey ?: @"",
    @"objc_type" : self.objcType ?: @"",
    @"runtime_class_name" : self.runtimeClassName ?: @"",
    @"nullable" : @(self.isNullable),
    @"primary_id" : @(self.isPrimaryID),
    @"primary_name" : @(self.isPrimaryName),
    @"logical" : @(self.isLogical),
    @"readable" : @(self.isReadable),
    @"creatable" : @(self.isCreatable),
    @"updateable" : @(self.isUpdateable),
    @"targets" : self.targets ?: @[],
    @"choices" : self.choices ?: @[],
  };
}

@end

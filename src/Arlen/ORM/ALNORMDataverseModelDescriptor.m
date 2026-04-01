#import "ALNORMDataverseModelDescriptor.h"

@interface ALNORMDataverseModelDescriptor ()

@property(nonatomic, copy) NSDictionary<NSString *, ALNORMDataverseFieldDescriptor *> *fieldByName;
@property(nonatomic, copy) NSDictionary<NSString *, ALNORMDataverseFieldDescriptor *> *fieldByReadKey;
@property(nonatomic, copy) NSDictionary<NSString *, ALNORMDataverseRelationDescriptor *> *relationByName;

@end

@implementation ALNORMDataverseModelDescriptor

- (instancetype)init {
  return [self initWithClassName:@""
                     logicalName:@""
                   entitySetName:@""
              primaryIDAttribute:@""
            primaryNameAttribute:@""
                 dataverseTarget:nil
                        readOnly:NO
                          fields:@[]
           alternateKeyFieldSets:nil
                       relations:nil];
}

- (instancetype)initWithClassName:(NSString *)className
                      logicalName:(NSString *)logicalName
                    entitySetName:(NSString *)entitySetName
               primaryIDAttribute:(NSString *)primaryIDAttribute
             primaryNameAttribute:(NSString *)primaryNameAttribute
                  dataverseTarget:(NSString *)dataverseTarget
                         readOnly:(BOOL)readOnly
                           fields:(NSArray<ALNORMDataverseFieldDescriptor *> *)fields
            alternateKeyFieldSets:(NSArray<NSArray<NSString *> *> *)alternateKeyFieldSets
                        relations:(NSArray<ALNORMDataverseRelationDescriptor *> *)relations {
  self = [super init];
  if (self != nil) {
    _className = [className copy] ?: @"";
    _logicalName = [logicalName copy] ?: @"";
    _entitySetName = [entitySetName copy] ?: @"";
    _primaryIDAttribute = [primaryIDAttribute copy] ?: @"";
    _primaryNameAttribute = [primaryNameAttribute copy] ?: @"";
    _dataverseTarget = [dataverseTarget copy] ?: @"";
    _readOnly = readOnly;
    _fields = [fields copy] ?: @[];
    _alternateKeyFieldSets = [alternateKeyFieldSets copy] ?: @[];
    _relations = [relations copy] ?: @[];

    NSMutableDictionary *fieldByName = [NSMutableDictionary dictionary];
    NSMutableDictionary *fieldByReadKey = [NSMutableDictionary dictionary];
    for (ALNORMDataverseFieldDescriptor *field in _fields) {
      if ([field.logicalName length] > 0) {
        fieldByName[field.logicalName] = field;
      }
      if ([field.readKey length] > 0) {
        fieldByReadKey[field.readKey] = field;
      }
    }
    _fieldByName = [fieldByName copy];
    _fieldByReadKey = [fieldByReadKey copy];

    NSMutableDictionary *relationByName = [NSMutableDictionary dictionary];
    for (ALNORMDataverseRelationDescriptor *relation in _relations) {
      if ([relation.name length] > 0) {
        relationByName[relation.name] = relation;
      }
    }
    _relationByName = [relationByName copy];
  }
  return self;
}

- (ALNORMDataverseFieldDescriptor *)fieldNamed:(NSString *)fieldName {
  return self.fieldByName[fieldName ?: @""];
}

- (ALNORMDataverseFieldDescriptor *)fieldForReadKey:(NSString *)readKey {
  return self.fieldByReadKey[readKey ?: @""];
}

- (ALNORMDataverseRelationDescriptor *)relationNamed:(NSString *)relationName {
  return self.relationByName[relationName ?: @""];
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
  NSMutableArray *fields = [NSMutableArray array];
  for (ALNORMDataverseFieldDescriptor *field in self.fields ?: @[]) {
    [fields addObject:[field dictionaryRepresentation]];
  }
  NSMutableArray *relations = [NSMutableArray array];
  for (ALNORMDataverseRelationDescriptor *relation in self.relations ?: @[]) {
    [relations addObject:[relation dictionaryRepresentation]];
  }
  return @{
    @"class_name" : self.className ?: @"",
    @"logical_name" : self.logicalName ?: @"",
    @"entity_set_name" : self.entitySetName ?: @"",
    @"primary_id_attribute" : self.primaryIDAttribute ?: @"",
    @"primary_name_attribute" : self.primaryNameAttribute ?: @"",
    @"dataverse_target" : self.dataverseTarget ?: @"",
    @"read_only" : @(self.isReadOnly),
    @"fields" : fields,
    @"alternate_key_field_sets" : self.alternateKeyFieldSets ?: @[],
    @"relations" : relations,
  };
}

@end

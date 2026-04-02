#import "ALNORMModelDescriptor.h"

static NSArray<NSString *> *ALNORMModelDescriptorSortedFieldSet(NSArray<NSString *> *fieldNames) {
  NSArray *values = [fieldNames isKindOfClass:[NSArray class]] ? fieldNames : @[];
  return [values sortedArrayUsingSelector:@selector(compare:)];
}

@interface ALNORMModelDescriptor ()

@property(nonatomic, copy) NSDictionary<NSString *, ALNORMFieldDescriptor *> *fieldByName;
@property(nonatomic, copy) NSDictionary<NSString *, ALNORMFieldDescriptor *> *fieldByPropertyName;
@property(nonatomic, copy) NSDictionary<NSString *, ALNORMFieldDescriptor *> *fieldByColumnName;
@property(nonatomic, copy) NSDictionary<NSString *, ALNORMRelationDescriptor *> *relationByName;

@end

@implementation ALNORMModelDescriptor

- (instancetype)init {
  return [self initWithClassName:@""
                      entityName:@""
                      schemaName:@""
                       tableName:@""
              qualifiedTableName:@""
                    relationKind:@"table"
                  databaseTarget:nil
                        readOnly:NO
                          fields:@[]
            primaryKeyFieldNames:@[]
        uniqueConstraintFieldSets:@[]
                       relations:nil];
}

- (instancetype)initWithClassName:(NSString *)className
                       entityName:(NSString *)entityName
                       schemaName:(NSString *)schemaName
                        tableName:(NSString *)tableName
               qualifiedTableName:(NSString *)qualifiedTableName
                     relationKind:(NSString *)relationKind
                   databaseTarget:(NSString *)databaseTarget
                         readOnly:(BOOL)readOnly
                           fields:(NSArray<ALNORMFieldDescriptor *> *)fields
             primaryKeyFieldNames:(NSArray<NSString *> *)primaryKeyFieldNames
         uniqueConstraintFieldSets:(NSArray<NSArray<NSString *> *> *)uniqueConstraintFieldSets
                        relations:(NSArray<ALNORMRelationDescriptor *> *)relations {
  self = [super init];
  if (self != nil) {
    _className = [className copy] ?: @"";
    _entityName = [entityName copy] ?: @"";
    _schemaName = [schemaName copy] ?: @"";
    _tableName = [tableName copy] ?: @"";
    _qualifiedTableName = [qualifiedTableName copy] ?: @"";
    _relationKind = [relationKind copy] ?: @"table";
    _databaseTarget = [databaseTarget copy] ?: @"";
    _readOnly = readOnly;
    _fields = [fields copy] ?: @[];
    _primaryKeyFieldNames = [primaryKeyFieldNames copy] ?: @[];
    _uniqueConstraintFieldSets = [uniqueConstraintFieldSets copy] ?: @[];
    _relations = [relations copy] ?: @[];

    NSMutableDictionary *fieldByName = [NSMutableDictionary dictionary];
    NSMutableDictionary *fieldByPropertyName = [NSMutableDictionary dictionary];
    NSMutableDictionary *fieldByColumnName = [NSMutableDictionary dictionary];
    for (ALNORMFieldDescriptor *field in _fields) {
      if ([field.name length] > 0) {
        fieldByName[field.name] = field;
      }
      if ([field.propertyName length] > 0) {
        fieldByPropertyName[field.propertyName] = field;
      }
      if ([field.columnName length] > 0) {
        fieldByColumnName[field.columnName] = field;
      }
    }
    _fieldByName = [fieldByName copy];
    _fieldByPropertyName = [fieldByPropertyName copy];
    _fieldByColumnName = [fieldByColumnName copy];

    NSMutableDictionary *relationByName = [NSMutableDictionary dictionary];
    for (ALNORMRelationDescriptor *relation in _relations) {
      if ([relation.name length] > 0) {
        relationByName[relation.name] = relation;
      }
    }
    _relationByName = [relationByName copy];
  }
  return self;
}

- (ALNORMFieldDescriptor *)fieldNamed:(NSString *)fieldName {
  return self.fieldByName[fieldName ?: @""];
}

- (ALNORMFieldDescriptor *)fieldForPropertyName:(NSString *)propertyName {
  return self.fieldByPropertyName[propertyName ?: @""];
}

- (ALNORMFieldDescriptor *)fieldForColumnName:(NSString *)columnName {
  return self.fieldByColumnName[columnName ?: @""];
}

- (ALNORMRelationDescriptor *)relationNamed:(NSString *)relationName {
  return self.relationByName[relationName ?: @""];
}

- (NSArray<NSString *> *)allFieldNames {
  NSMutableArray *names = [NSMutableArray arrayWithCapacity:[self.fields count]];
  for (ALNORMFieldDescriptor *field in self.fields) {
    [names addObject:field.name ?: @""];
  }
  return names;
}

- (NSArray<NSString *> *)allColumnNames {
  NSMutableArray *names = [NSMutableArray arrayWithCapacity:[self.fields count]];
  for (ALNORMFieldDescriptor *field in self.fields) {
    [names addObject:field.columnName ?: @""];
  }
  return names;
}

- (NSArray<NSString *> *)allQualifiedColumnNames {
  NSMutableArray *names = [NSMutableArray arrayWithCapacity:[self.fields count]];
  for (ALNORMFieldDescriptor *field in self.fields) {
    [names addObject:[NSString stringWithFormat:@"%@.%@",
                                                  self.qualifiedTableName ?: self.tableName ?: @"",
                                                  field.columnName ?: @""]];
  }
  return names;
}

- (BOOL)hasUniqueConstraintForFieldSet:(NSArray<NSString *> *)fieldNames {
  NSArray<NSString *> *normalized = ALNORMModelDescriptorSortedFieldSet(fieldNames);
  if ([normalized count] == 0) {
    return NO;
  }
  for (NSArray<NSString *> *candidate in self.uniqueConstraintFieldSets) {
    if ([normalized isEqualToArray:ALNORMModelDescriptorSortedFieldSet(candidate)]) {
      return YES;
    }
  }
  return NO;
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
  NSMutableArray *fieldRepresentations = [NSMutableArray arrayWithCapacity:[self.fields count]];
  for (ALNORMFieldDescriptor *field in self.fields) {
    [fieldRepresentations addObject:[field dictionaryRepresentation]];
  }

  NSMutableArray *relationRepresentations = [NSMutableArray arrayWithCapacity:[self.relations count]];
  for (ALNORMRelationDescriptor *relation in self.relations) {
    [relationRepresentations addObject:[relation dictionaryRepresentation]];
  }

  return @{
    @"class_name" : self.className ?: @"",
    @"entity_name" : self.entityName ?: @"",
    @"schema_name" : self.schemaName ?: @"",
    @"table_name" : self.tableName ?: @"",
    @"qualified_table_name" : self.qualifiedTableName ?: @"",
    @"relation_kind" : self.relationKind ?: @"table",
    @"database_target" : self.databaseTarget ?: @"",
    @"read_only" : @(self.isReadOnly),
    @"fields" : fieldRepresentations,
    @"primary_key_field_names" : self.primaryKeyFieldNames ?: @[],
    @"unique_constraint_field_sets" : self.uniqueConstraintFieldSets ?: @[],
    @"relations" : relationRepresentations,
  };
}

@end

#import "ALNORMModel.h"

#import "ALNORMContext.h"
#import "ALNORMErrors.h"
#import "ALNORMFieldDescriptor.h"
#import "ALNORMQuery.h"
#import "ALNORMRepository.h"

static NSString *ALNORMModelStateFallbackName(ALNORMModelState state) {
  switch (state) {
    case ALNORMModelStateNew:
      return @"new";
    case ALNORMModelStateLoaded:
      return @"loaded";
    case ALNORMModelStateDirty:
      return @"dirty";
    case ALNORMModelStateDetached:
      return @"detached";
  }
  return @"new";
}

NSString *ALNORMModelStateName(ALNORMModelState state) {
  return ALNORMModelStateFallbackName(state);
}

@interface ALNORMModel ()

@property(nonatomic, strong, readwrite) ALNORMModelDescriptor *descriptor;
@property(nonatomic, assign, readwrite) ALNORMModelState state;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, id> *fieldValues;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, id> *relationValues;
@property(nonatomic, copy, readwrite) NSSet<NSString *> *dirtyFieldNames;
@property(nonatomic, copy) NSDictionary<NSString *, id> *cleanFieldValues;

@end

@implementation ALNORMModel

- (instancetype)init {
  ALNORMModelDescriptor *descriptor = [[self class] modelDescriptor];
  return [self initWithDescriptor:descriptor];
}

- (instancetype)initWithDescriptor:(ALNORMModelDescriptor *)descriptor {
  self = [super init];
  if (self != nil) {
    _descriptor = descriptor;
    _state = ALNORMModelStateNew;
    _fieldValues = @{};
    _relationValues = @{};
    _dirtyFieldNames = [NSSet set];
    _cleanFieldValues = @{};
  }
  return self;
}

+ (ALNORMModelDescriptor *)modelDescriptor {
  return nil;
}

+ (ALNORMQuery *)query {
  return [ALNORMQuery queryWithModelClass:self];
}

+ (ALNORMRepository *)repositoryWithContext:(ALNORMContext *)context {
  return [context repositoryForModelClass:self];
}

+ (instancetype)modelFromRow:(NSDictionary<NSString *,id> *)row
                       error:(NSError **)error {
  id model = [[self alloc] init];
  if (![model isKindOfClass:[ALNORMModel class]]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorUnsupportedModelClass,
                               @"model class must inherit from ALNORMModel",
                               @{
                                 @"class_name" : NSStringFromClass(self) ?: @"",
                               });
    }
    return nil;
  }
  if (![model applyRow:row error:error]) {
    return nil;
  }
  return model;
}

+ (NSArray<NSString *> *)allFieldNames {
  return [[self modelDescriptor] allFieldNames] ?: @[];
}

+ (NSArray<NSString *> *)allColumnNames {
  return [[self modelDescriptor] allColumnNames] ?: @[];
}

+ (NSArray<NSString *> *)allQualifiedColumnNames {
  return [[self modelDescriptor] allQualifiedColumnNames] ?: @[];
}

+ (NSString *)entityName {
  return [[self modelDescriptor] entityName] ?: @"";
}

- (ALNORMFieldDescriptor *)resolvedFieldDescriptorForName:(NSString *)fieldName {
  ALNORMFieldDescriptor *field = [self.descriptor fieldNamed:fieldName];
  if (field != nil) {
    return field;
  }
  field = [self.descriptor fieldForPropertyName:fieldName];
  if (field != nil) {
    return field;
  }
  return [self.descriptor fieldForColumnName:fieldName];
}

- (id)objectForFieldName:(NSString *)fieldName {
  ALNORMFieldDescriptor *field = [self resolvedFieldDescriptorForName:fieldName];
  if (field == nil) {
    return nil;
  }
  return self.fieldValues[field.name];
}

- (id)objectForPropertyName:(NSString *)propertyName {
  return [self objectForFieldName:propertyName];
}

- (id)objectForColumnName:(NSString *)columnName {
  return [self objectForFieldName:columnName];
}

- (BOOL)validateValue:(id)value
             forField:(ALNORMFieldDescriptor *)field
                error:(NSError **)error {
  if (value == [NSNull null]) {
    value = nil;
  }
  if (value == nil) {
    if (!field.isNullable) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorMissingField,
                                 @"field does not allow nil values",
                                 @{
                                   @"field_name" : field.name ?: @"",
                                   @"column_name" : field.columnName ?: @"",
                                 });
      }
      return NO;
    }
    return YES;
  }

  if ([field.runtimeClassName length] == 0) {
    return YES;
  }
  Class runtimeClass = NSClassFromString(field.runtimeClassName);
  if (runtimeClass != Nil && ![value isKindOfClass:runtimeClass]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidType,
                               @"field value has an unexpected runtime class",
                               @{
                                 @"field_name" : field.name ?: @"",
                                 @"expected_class" : field.runtimeClassName ?: @"",
                                 @"actual_class" : NSStringFromClass([value class]) ?: @"",
                               });
    }
    return NO;
  }
  return YES;
}

- (void)updateDirtyStateForFieldName:(NSString *)fieldName value:(id)value {
  NSMutableSet *dirty = [NSMutableSet setWithSet:self.dirtyFieldNames ?: [NSSet set]];
  id cleanValue = self.cleanFieldValues[fieldName];
  BOOL matchesClean = ((cleanValue == nil && value == nil) || [cleanValue isEqual:value]);
  if (self.state == ALNORMModelStateNew) {
    if (value != nil) {
      [dirty addObject:fieldName ?: @""];
    }
  } else if (matchesClean) {
    [dirty removeObject:fieldName ?: @""];
  } else {
    [dirty addObject:fieldName ?: @""];
  }
  self.dirtyFieldNames = dirty;

  if (self.state == ALNORMModelStateDetached) {
    return;
  }
  if (self.state == ALNORMModelStateNew) {
    return;
  }
  self.state = ([dirty count] > 0) ? ALNORMModelStateDirty : ALNORMModelStateLoaded;
}

- (BOOL)setObject:(id)value
     forFieldName:(NSString *)fieldName
            error:(NSError **)error {
  ALNORMFieldDescriptor *field = [self resolvedFieldDescriptorForName:fieldName];
  if (field == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"attempted to write an unknown field",
                               @{
                                 @"field_name" : fieldName ?: @"",
                                 @"entity_name" : self.descriptor.entityName ?: @"",
                               });
    }
    return NO;
  }
  if (self.descriptor.isReadOnly || field.isReadOnly) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorReadOnlyMutation,
                               @"attempted to mutate a read-only model field",
                               @{
                                 @"field_name" : field.name ?: @"",
                                 @"entity_name" : self.descriptor.entityName ?: @"",
                               });
    }
    return NO;
  }
  if (![self validateValue:value forField:field error:error]) {
    return NO;
  }

  NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:self.fieldValues ?: @{}];
  if (value == nil || value == [NSNull null]) {
    [updated removeObjectForKey:field.name ?: @""];
  } else {
    updated[field.name] = value;
  }
  self.fieldValues = updated;
  [self updateDirtyStateForFieldName:field.name value:(value == [NSNull null] ? nil : value)];
  return YES;
}

- (BOOL)setObject:(id)value
  forPropertyName:(NSString *)propertyName
            error:(NSError **)error {
  return [self setObject:value forFieldName:propertyName error:error];
}

- (BOOL)applyRow:(NSDictionary<NSString *,id> *)row
           error:(NSError **)error {
  if (![row isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"row materialization requires a dictionary",
                               nil);
    }
    return NO;
  }

  NSMutableDictionary *values = [NSMutableDictionary dictionary];
  for (ALNORMFieldDescriptor *field in self.descriptor.fields ?: @[]) {
    id rawValue = row[field.columnName];
    if (rawValue == nil) {
      rawValue = row[field.propertyName];
    }
    if (rawValue == nil) {
      rawValue = row[field.name];
    }
    if (rawValue == [NSNull null]) {
      rawValue = nil;
    }
    if (![self validateValue:rawValue forField:field error:error]) {
      return NO;
    }
    if (rawValue != nil) {
      values[field.name] = rawValue;
    }
  }

  self.fieldValues = values;
  self.cleanFieldValues = [values copy];
  self.dirtyFieldNames = [NSSet set];
  self.state = ALNORMModelStateLoaded;
  return YES;
}

- (void)markClean {
  self.cleanFieldValues = [self.fieldValues copy] ?: @{};
  self.dirtyFieldNames = [NSSet set];
  self.state = ALNORMModelStateLoaded;
}

- (void)markDetached {
  self.state = ALNORMModelStateDetached;
}

- (BOOL)setRelationObject:(id)value
          forRelationName:(NSString *)relationName
                    error:(NSError **)error {
  ALNORMRelationDescriptor *relation = [self.descriptor relationNamed:relationName];
  if (relation == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"attempted to write an unknown relation",
                               @{
                                 @"relation_name" : relationName ?: @"",
                                 @"entity_name" : self.descriptor.entityName ?: @"",
                               });
    }
    return NO;
  }
  if (self.descriptor.isReadOnly || relation.isReadOnly) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorReadOnlyMutation,
                               @"attempted to mutate a read-only relation",
                               @{
                                 @"relation_name" : relationName ?: @"",
                                 @"entity_name" : self.descriptor.entityName ?: @"",
                               });
    }
    return NO;
  }
  NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:self.relationValues ?: @{}];
  if (value == nil) {
    [updated removeObjectForKey:relationName ?: @""];
  } else {
    updated[relationName] = value;
  }
  self.relationValues = updated;
  return YES;
}

- (id)relationObjectForName:(NSString *)relationName {
  return self.relationValues[relationName ?: @""];
}

- (NSDictionary<NSString *,id> *)primaryKeyValues {
  NSMutableDictionary *values = [NSMutableDictionary dictionary];
  for (NSString *fieldName in self.descriptor.primaryKeyFieldNames ?: @[]) {
    id value = [self objectForFieldName:fieldName];
    if (value != nil) {
      values[fieldName] = value;
    }
  }
  return values;
}

- (NSDictionary<NSString *,id> *)changedFieldValues {
  NSMutableDictionary *values = [NSMutableDictionary dictionary];
  for (NSString *fieldName in self.dirtyFieldNames ?: [NSSet set]) {
    id value = [self objectForFieldName:fieldName];
    if (value != nil) {
      values[fieldName] = value;
    }
  }
  return values;
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
  return @{
    @"entity_name" : self.descriptor.entityName ?: @"",
    @"state" : ALNORMModelStateName(self.state),
    @"field_values" : self.fieldValues ?: @{},
    @"relation_values" : self.relationValues ?: @{},
    @"dirty_field_names" : [[self.dirtyFieldNames allObjects] sortedArrayUsingSelector:@selector(compare:)],
  };
}

@end

#import "ALNORMModel.h"

#import "ALNORMContext.h"
#import "ALNORMErrors.h"
#import "ALNORMFieldDescriptor.h"
#import "ALNORMRelationDescriptor.h"
#import "ALNORMRepository.h"
#import "ALNORMValueConverter.h"

NSString *const ALNORMStrictLoadingException = @"Arlen.ORM.StrictLoadingException";

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

static id ALNORMStoredValue(id value) {
  return (value == nil || value == [NSNull null]) ? [NSNull null] : value;
}

static id ALNORMPublicValue(id value) {
  return (value == [NSNull null]) ? nil : value;
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
@property(nonatomic, weak, readwrite) ALNORMContext *context;
@property(nonatomic, copy, readwrite) NSSet<NSString *> *loadedRelationNames;
@property(nonatomic, copy) NSDictionary<NSString *, id> *cleanFieldValues;
@property(nonatomic, copy) NSDictionary<NSString *, NSNumber *> *relationAccessStrategies;
@property(nonatomic, copy) NSDictionary<NSString *, NSArray<NSDictionary<NSString *, id> *> *> *relationPivotRows;

@end

@interface ALNORMContext (ALNORMModelRuntime)
- (NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConvertersForModelClass:(Class)modelClass;
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
    _loadedRelationNames = [NSSet set];
    _cleanFieldValues = @{};
    _relationAccessStrategies = @{};
    _relationPivotRows = @{};
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

+ (instancetype)modelFromRow:(NSDictionary<NSString *, id> *)row
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

- (nullable ALNORMFieldDescriptor *)resolvedFieldDescriptorForName:(NSString *)fieldName {
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

- (NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConverters {
  if (self.context == nil) {
    return @{};
  }
  return [self.context fieldConvertersForModelClass:[self class]] ?: @{};
}

- (nullable ALNORMValueConverter *)converterForField:(ALNORMFieldDescriptor *)field {
  NSDictionary<NSString *, ALNORMValueConverter *> *converters = [self fieldConverters];
  ALNORMValueConverter *converter = converters[field.name];
  if (converter != nil) {
    return converter;
  }
  converter = converters[field.propertyName];
  if (converter != nil) {
    return converter;
  }
  return converters[field.columnName];
}

- (BOOL)validateValue:(id)value
             forField:(ALNORMFieldDescriptor *)field
                error:(NSError **)error {
  id publicValue = ALNORMPublicValue(value);
  if (publicValue == nil) {
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
  if (runtimeClass != Nil && ![publicValue isKindOfClass:runtimeClass]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidType,
                               @"field value has an unexpected runtime class",
                               @{
                                 @"field_name" : field.name ?: @"",
                                 @"expected_class" : field.runtimeClassName ?: @"",
                                 @"actual_class" : NSStringFromClass([publicValue class]) ?: @"",
                               });
    }
    return NO;
  }
  return YES;
}

- (nullable id)decodedStoredValue:(id)value
                         forField:(ALNORMFieldDescriptor *)field
                            error:(NSError **)error {
  id rawValue = ALNORMPublicValue(value);
  ALNORMValueConverter *converter = [self converterForField:field];
  if (converter == nil) {
    return ALNORMStoredValue(rawValue);
  }

  id decoded = [converter decodeValue:rawValue error:error];
  if (decoded == nil && error != NULL && *error != nil) {
    return nil;
  }
  return ALNORMStoredValue(decoded);
}

- (void)updateDirtyStateForFieldName:(NSString *)fieldName storedValue:(id)storedValue {
  NSMutableSet *dirty = [NSMutableSet setWithSet:self.dirtyFieldNames ?: [NSSet set]];
  id canonicalValue = ALNORMStoredValue(storedValue);
  id cleanValue = self.cleanFieldValues[fieldName];
  BOOL matchesClean = ((cleanValue == nil && canonicalValue == [NSNull null]) ||
                       [cleanValue isEqual:canonicalValue]);
  if (self.state == ALNORMModelStateNew) {
    if (canonicalValue != [NSNull null]) {
      [dirty addObject:fieldName ?: @""];
    }
  } else if (matchesClean) {
    [dirty removeObject:fieldName ?: @""];
  } else {
    [dirty addObject:fieldName ?: @""];
  }
  self.dirtyFieldNames = dirty;

  if (self.state == ALNORMModelStateDetached || self.state == ALNORMModelStateNew) {
    return;
  }
  self.state = ([dirty count] > 0) ? ALNORMModelStateDirty : ALNORMModelStateLoaded;
}

- (nullable id)objectForFieldName:(NSString *)fieldName {
  ALNORMFieldDescriptor *field = [self resolvedFieldDescriptorForName:fieldName];
  if (field == nil) {
    return nil;
  }
  return ALNORMPublicValue(self.fieldValues[field.name]);
}

- (nullable id)objectForPropertyName:(NSString *)propertyName {
  return [self objectForFieldName:propertyName];
}

- (nullable id)objectForColumnName:(NSString *)columnName {
  return [self objectForFieldName:columnName];
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

  id storedValue = ALNORMStoredValue(value);
  if (![self validateValue:storedValue forField:field error:error]) {
    return NO;
  }

  NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:self.fieldValues ?: @{}];
  updated[field.name] = storedValue;
  self.fieldValues = updated;
  [self updateDirtyStateForFieldName:field.name storedValue:storedValue];
  return YES;
}

- (BOOL)setObject:(id)value
  forPropertyName:(NSString *)propertyName
            error:(NSError **)error {
  return [self setObject:value forFieldName:propertyName error:error];
}

- (BOOL)applyRow:(NSDictionary<NSString *, id> *)row
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
    id rawValue = nil;
    BOOL found = NO;

    rawValue = row[field.columnName];
    found = (rawValue != nil || [row objectForKey:field.columnName] != nil);
    if (!found) {
      rawValue = row[field.propertyName];
      found = (rawValue != nil || [row objectForKey:field.propertyName] != nil);
    }
    if (!found) {
      rawValue = row[field.name];
      found = (rawValue != nil || [row objectForKey:field.name] != nil);
    }
    if (!found) {
      continue;
    }

    NSError *decodeError = nil;
    id storedValue = [self decodedStoredValue:rawValue forField:field error:&decodeError];
    if (storedValue == nil && decodeError != nil) {
      if (error != NULL) {
        *error = decodeError;
      }
      return NO;
    }
    if (![self validateValue:storedValue forField:field error:error]) {
      return NO;
    }
    values[field.name] = storedValue ?: [NSNull null];
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
  self.context = nil;
}

- (void)attachToContext:(ALNORMContext *)context {
  self.context = context;
  if (context == nil) {
    if (self.state != ALNORMModelStateDetached) {
      self.state = ALNORMModelStateDetached;
    }
    return;
  }
  if (self.state == ALNORMModelStateDetached) {
    if ([self.dirtyFieldNames count] > 0) {
      self.state = ALNORMModelStateDirty;
    } else if ([self.cleanFieldValues count] > 0) {
      self.state = ALNORMModelStateLoaded;
    } else {
      self.state = ALNORMModelStateNew;
    }
  }
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
  return [self markRelationLoaded:relationName value:value pivotRows:nil error:error];
}

- (void)markRelationNamed:(NSString *)relationName
            accessStrategy:(ALNORMRelationLoadStrategy)accessStrategy {
  NSString *candidate = relationName ?: @"";
  NSMutableDictionary *updated =
      [NSMutableDictionary dictionaryWithDictionary:self.relationAccessStrategies ?: @{}];
  updated[candidate] = @(accessStrategy);
  self.relationAccessStrategies = updated;
}

- (BOOL)markRelationLoaded:(NSString *)relationName
                     value:(id)value
                pivotRows:(NSArray<NSDictionary<NSString *, id> *> *)pivotRows
                    error:(NSError **)error {
  ALNORMRelationDescriptor *relation = [self.descriptor relationNamed:relationName];
  if (relation == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"attempted to mark an unknown relation as loaded",
                               @{
                                 @"relation_name" : relationName ?: @"",
                                 @"entity_name" : self.descriptor.entityName ?: @"",
                               });
    }
    return NO;
  }

  NSMutableDictionary *relations = [NSMutableDictionary dictionaryWithDictionary:self.relationValues ?: @{}];
  relations[relationName ?: @""] = ALNORMStoredValue(value);
  self.relationValues = relations;

  NSMutableSet *loaded = [NSMutableSet setWithSet:self.loadedRelationNames ?: [NSSet set]];
  [loaded addObject:relationName ?: @""];
  self.loadedRelationNames = loaded;

  NSMutableDictionary *strategies =
      [NSMutableDictionary dictionaryWithDictionary:self.relationAccessStrategies ?: @{}];
  [strategies removeObjectForKey:relationName ?: @""];
  self.relationAccessStrategies = strategies;

  NSMutableDictionary *pivotValues =
      [NSMutableDictionary dictionaryWithDictionary:self.relationPivotRows ?: @{}];
  if ([pivotRows count] > 0) {
    pivotValues[relationName ?: @""] = [pivotRows copy];
  } else {
    [pivotValues removeObjectForKey:relationName ?: @""];
  }
  self.relationPivotRows = pivotValues;
  return YES;
}

- (BOOL)isRelationLoaded:(NSString *)relationName {
  return [self.loadedRelationNames containsObject:relationName ?: @""];
}

- (NSArray<NSDictionary<NSString *, id> *> *)pivotValueDictionariesForRelationName:(NSString *)relationName {
  return self.relationPivotRows[relationName ?: @""] ?: @[];
}

- (nullable id)relationObjectForName:(NSString *)relationName
                               error:(NSError **)error {
  NSString *candidate = relationName ?: @"";
  if ([self isRelationLoaded:candidate]) {
    return ALNORMPublicValue(self.relationValues[candidate]);
  }

  ALNORMRelationDescriptor *relation = [self.descriptor relationNamed:candidate];
  if (relation == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"attempted to access an unknown relation",
                               @{
                                 @"relation_name" : candidate,
                                 @"entity_name" : self.descriptor.entityName ?: @"",
                               });
    }
    return nil;
  }

  ALNORMRelationLoadStrategy strategy =
      (ALNORMRelationLoadStrategy)[self.relationAccessStrategies[candidate] integerValue];
  BOOL shouldRaise = (strategy == ALNORMRelationLoadStrategyRaiseOnAccess) ||
                     (strategy == ALNORMRelationLoadStrategyDefault &&
                      self.context != nil &&
                      self.context.defaultStrictLoadingEnabled);
  if (!shouldRaise) {
    return nil;
  }

  if (error != NULL) {
    *error = ALNORMMakeError(ALNORMErrorStrictLoadingViolation,
                             @"relation access requires an explicit preload",
                             @{
                               @"entity_name" : self.descriptor.entityName ?: @"",
                               @"relation_name" : candidate,
                               @"load_strategy" : ALNORMRelationLoadStrategyName(strategy),
                             });
  }
  return nil;
}

- (nullable id)relationObjectForName:(NSString *)relationName {
  NSError *error = nil;
  id value = [self relationObjectForName:relationName error:&error];
  if (error != nil) {
    @throw [NSException exceptionWithName:ALNORMStrictLoadingException
                                   reason:error.localizedDescription
                                 userInfo:error.userInfo];
  }
  return value;
}

- (NSDictionary<NSString *, id> *)primaryKeyValues {
  NSMutableDictionary *values = [NSMutableDictionary dictionary];
  for (NSString *fieldName in self.descriptor.primaryKeyFieldNames ?: @[]) {
    id value = [self objectForFieldName:fieldName];
    if (value != nil) {
      values[fieldName] = value;
    }
  }
  return values;
}

- (NSDictionary<NSString *, id> *)changedFieldValues {
  NSMutableDictionary *values = [NSMutableDictionary dictionary];
  for (NSString *fieldName in self.dirtyFieldNames ?: [NSSet set]) {
    id storedValue = self.fieldValues[fieldName];
    values[fieldName] = ALNORMPublicValue(storedValue) ?: [NSNull null];
  }
  return values;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
  NSMutableDictionary *publicFieldValues = [NSMutableDictionary dictionary];
  for (NSString *fieldName in self.fieldValues ?: @{}) {
    publicFieldValues[fieldName] = ALNORMPublicValue(self.fieldValues[fieldName]) ?: [NSNull null];
  }

  NSMutableDictionary *publicRelationValues = [NSMutableDictionary dictionary];
  for (NSString *relationName in self.relationValues ?: @{}) {
    publicRelationValues[relationName] =
        ALNORMPublicValue(self.relationValues[relationName]) ?: [NSNull null];
  }

  return @{
    @"entity_name" : self.descriptor.entityName ?: @"",
    @"state" : ALNORMModelStateName(self.state),
    @"field_values" : publicFieldValues,
    @"relation_values" : publicRelationValues,
    @"loaded_relation_names" :
        [[self.loadedRelationNames allObjects] sortedArrayUsingSelector:@selector(compare:)],
    @"dirty_field_names" :
        [[self.dirtyFieldNames allObjects] sortedArrayUsingSelector:@selector(compare:)],
  };
}

@end

#import "ALNORMChangeset.h"

#import "ALNORMContext.h"
#import "ALNORMErrors.h"
#import "ALNORMFieldDescriptor.h"
#import "ALNORMRelationDescriptor.h"

static id ALNORMChangesetStoredValue(id value) {
  return (value == nil || value == [NSNull null]) ? [NSNull null] : value;
}

static id ALNORMChangesetPublicValue(id value) {
  return (value == [NSNull null]) ? nil : value;
}

@interface ALNORMChangeset ()

@property(nonatomic, strong, readwrite) ALNORMModelDescriptor *descriptor;
@property(nonatomic, weak, readwrite) ALNORMModel *model;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, id> *values;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, NSArray<NSString *> *> *fieldErrors;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, ALNORMValueConverter *> *fieldConverters;
@property(nonatomic, copy, readwrite) NSSet<NSString *> *requiredFieldNames;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, ALNORMChangeset *> *nestedChangesets;

@end

@implementation ALNORMChangeset

+ (instancetype)changesetWithModel:(ALNORMModel *)model {
  NSDictionary<NSString *, ALNORMValueConverter *> *converters = @{};
  if (model.context != nil) {
    converters = [model.context fieldConvertersForModelClass:[model class]] ?: @{};
  }

  NSMutableArray<NSString *> *requiredFieldNames = [NSMutableArray array];
  for (ALNORMFieldDescriptor *field in model.descriptor.fields ?: @[]) {
    if (!field.isNullable && !field.isPrimaryKey && !field.hasDefaultValue && !field.isReadOnly) {
      [requiredFieldNames addObject:field.name ?: @""];
    }
  }

  return [[self alloc] initWithDescriptor:model.descriptor
                                    model:model
                           fieldConverters:converters
                        requiredFieldNames:requiredFieldNames];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
- (instancetype)init {
  return [self initWithDescriptor:nil
                            model:nil
                   fieldConverters:nil
                requiredFieldNames:nil];
}
#pragma clang diagnostic pop

- (instancetype)initWithDescriptor:(ALNORMModelDescriptor *)descriptor
                             model:(ALNORMModel *)model {
  return [self initWithDescriptor:descriptor
                            model:model
                   fieldConverters:nil
                requiredFieldNames:nil];
}

- (instancetype)initWithDescriptor:(ALNORMModelDescriptor *)descriptor
                             model:(ALNORMModel *)model
                    fieldConverters:(NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConverters
                 requiredFieldNames:(NSArray<NSString *> *)requiredFieldNames {
  self = [super init];
  if (self != nil) {
    _descriptor = descriptor;
    _model = model;
    _values = @{};
    _fieldErrors = @{};
    _fieldConverters = [fieldConverters copy] ?: @{};

    NSMutableSet *required = [NSMutableSet set];
    for (NSString *fieldName in requiredFieldNames ?: @[]) {
      ALNORMFieldDescriptor *field = [self resolvedFieldDescriptorForName:fieldName];
      if (field != nil) {
        [required addObject:field.name ?: @""];
      }
    }
    _requiredFieldNames = [required copy] ?: [NSSet set];
    _nestedChangesets = @{};
  }
  return self;
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

- (nullable ALNORMValueConverter *)converterForField:(ALNORMFieldDescriptor *)field {
  ALNORMValueConverter *converter = self.fieldConverters[field.name];
  if (converter != nil) {
    return converter;
  }
  converter = self.fieldConverters[field.propertyName];
  if (converter != nil) {
    return converter;
  }
  return self.fieldConverters[field.columnName];
}

- (BOOL)setObject:(id)value
     forFieldName:(NSString *)fieldName
            error:(NSError **)error {
  ALNORMFieldDescriptor *field = [self resolvedFieldDescriptorForName:fieldName];
  if (field == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"changeset references an unknown field",
                               @{
                                 @"field_name" : fieldName ?: @"",
                               });
    }
    return NO;
  }
  if (self.descriptor.isReadOnly || field.isReadOnly) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorReadOnlyMutation,
                               @"changeset does not allow mutations for a read-only field",
                               @{
                                 @"field_name" : field.name ?: @"",
                                 @"entity_name" : self.descriptor.entityName ?: @"",
                               });
    }
    return NO;
  }

  NSMutableDictionary *values = [NSMutableDictionary dictionaryWithDictionary:self.values ?: @{}];
  values[field.name] = ALNORMChangesetStoredValue(value);
  self.values = values;
  return YES;
}

- (BOOL)castInputValue:(id)value
          forFieldName:(NSString *)fieldName
                 error:(NSError **)error {
  ALNORMFieldDescriptor *field = [self resolvedFieldDescriptorForName:fieldName];
  if (field == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"changeset cannot cast an unknown field",
                               @{
                                 @"field_name" : fieldName ?: @"",
                               });
    }
    return NO;
  }

  ALNORMValueConverter *converter = [self converterForField:field];
  id castValue = value;
  if (converter != nil) {
    castValue = [converter decodeValue:value error:error];
    if (castValue == nil && error != NULL && *error != nil) {
      [self addError:([*error localizedDescription] ?: @"invalid value") forFieldName:field.name];
      return NO;
    }
  }
  return [self setObject:castValue forFieldName:field.name error:error];
}

- (BOOL)applyInputValues:(NSDictionary<NSString *, id> *)values
                   error:(NSError **)error {
  if (![values isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"changeset input must be a dictionary",
                               nil);
    }
    return NO;
  }

  for (NSString *fieldName in values) {
    if (![self castInputValue:values[fieldName] forFieldName:fieldName error:error]) {
      return NO;
    }
  }
  return YES;
}

- (id)objectForFieldName:(NSString *)fieldName {
  ALNORMFieldDescriptor *field = [self resolvedFieldDescriptorForName:fieldName];
  if (field == nil) {
    return nil;
  }
  if (self.values[field.name] != nil) {
    return ALNORMChangesetPublicValue(self.values[field.name]);
  }
  return [self.model objectForFieldName:field.name];
}

- (void)addError:(NSString *)message forFieldName:(NSString *)fieldName {
  NSString *key = [fieldName copy] ?: @"";
  NSArray *existing =
      [self.fieldErrors[key] isKindOfClass:[NSArray class]] ? self.fieldErrors[key] : @[];
  NSMutableDictionary *errors = [NSMutableDictionary dictionaryWithDictionary:self.fieldErrors ?: @{}];
  errors[key] = [existing arrayByAddingObject:message ?: @"invalid"];
  self.fieldErrors = errors;
}

- (BOOL)validateRequiredFields {
  for (NSString *fieldName in self.requiredFieldNames ?: [NSSet set]) {
    id value = [self objectForFieldName:fieldName];
    if (value == nil || value == [NSNull null]) {
      [self addError:@"is required" forFieldName:fieldName];
    }
  }
  return ![self hasErrors];
}

- (BOOL)validateFieldName:(NSString *)fieldName
               usingBlock:(ALNORMFieldValidationBlock)validationBlock {
  ALNORMFieldDescriptor *field = [self resolvedFieldDescriptorForName:fieldName];
  if (field == nil || validationBlock == nil) {
    if (field == nil) {
      [self addError:@"is not a known field" forFieldName:fieldName];
    }
    return NO;
  }

  NSError *validationError = nil;
  BOOL valid = validationBlock(field, [self objectForFieldName:field.name], &validationError);
  if (!valid) {
    [self addError:(validationError.localizedDescription ?: @"is invalid") forFieldName:field.name];
  }
  return valid;
}

- (BOOL)setNestedChangeset:(ALNORMChangeset *)changeset
            forRelationName:(NSString *)relationName
                     error:(NSError **)error {
  ALNORMRelationDescriptor *relation = [self.descriptor relationNamed:relationName];
  if (relation == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"changeset references an unknown relation",
                               @{
                                 @"relation_name" : relationName ?: @"",
                                 @"entity_name" : self.descriptor.entityName ?: @"",
                               });
    }
    return NO;
  }

  NSMutableDictionary *nested =
      [NSMutableDictionary dictionaryWithDictionary:self.nestedChangesets ?: @{}];
  nested[relation.name ?: @""] = changeset;
  self.nestedChangesets = nested;
  return YES;
}

- (ALNORMChangeset *)nestedChangesetForRelationName:(NSString *)relationName {
  ALNORMRelationDescriptor *relation = [self.descriptor relationNamed:relationName];
  return (relation != nil) ? self.nestedChangesets[relation.name] : nil;
}

- (BOOL)applyNestedChangesets:(NSError **)error {
  for (NSString *relationName in self.nestedChangesets ?: @{}) {
    ALNORMRelationDescriptor *relation = [self.descriptor relationNamed:relationName];
    ALNORMChangeset *nested = self.nestedChangesets[relationName];
    if (relation == nil || nested == nil) {
      continue;
    }
    if (relation.kind == ALNORMRelationKindHasMany ||
        relation.kind == ALNORMRelationKindManyToMany) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorValidationFailed,
                                 @"nested changesets currently support only to-one relations",
                                 @{
                                   @"relation_name" : relation.name ?: @"",
                                   @"entity_name" : self.descriptor.entityName ?: @"",
                                 });
      }
      return NO;
    }

    id relationValue = [self.model relationObjectForName:relation.name error:error];
    ALNORMModel *relatedModel = nil;
    if ([relationValue isKindOfClass:[ALNORMModel class]]) {
      relatedModel = relationValue;
    } else if ([nested.model isKindOfClass:[ALNORMModel class]]) {
      relatedModel = nested.model;
      if (![self.model setRelationObject:relatedModel forRelationName:relation.name error:error]) {
        return NO;
      }
    } else {
      Class targetClass = NSClassFromString(relation.targetClassName);
      if (targetClass == Nil || ![targetClass isSubclassOfClass:[ALNORMModel class]]) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorUnsupportedModelClass,
                                   @"nested changeset target class is unavailable",
                                   @{
                                     @"target_class_name" : relation.targetClassName ?: @"",
                                     @"relation_name" : relation.name ?: @"",
                                   });
        }
        return NO;
      }
      relatedModel = [[targetClass alloc] init];
      if (![self.model setRelationObject:relatedModel forRelationName:relation.name error:error]) {
        return NO;
      }
    }

    nested.model = relatedModel;
    if (![nested applyToModel:error]) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)applyToModel:(NSError **)error {
  if (self.model == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"changeset cannot apply without a target model",
                               nil);
    }
    return NO;
  }
  if (![self validateRequiredFields]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorValidationFailed,
                               @"changeset failed required-field validation",
                               @{
                                 @"field_errors" : self.fieldErrors ?: @{},
                               });
    }
    return NO;
  }

  for (NSString *fieldName in [self changedFieldNames]) {
    id value = ALNORMChangesetPublicValue(self.values[fieldName]);
    if (![self.model setObject:value forFieldName:fieldName error:error]) {
      return NO;
    }
  }

  if (![self applyNestedChangesets:error]) {
    return NO;
  }
  return YES;
}

- (NSDictionary<NSString *, id> *)encodedValues:(NSError **)error {
  if (![self validateRequiredFields]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorValidationFailed,
                               @"changeset failed validation before encoding",
                               @{
                                 @"field_errors" : self.fieldErrors ?: @{},
                               });
    }
    return nil;
  }

  NSMutableDictionary *encodedValues = [NSMutableDictionary dictionary];
  for (NSString *fieldName in [self changedFieldNames]) {
    ALNORMFieldDescriptor *field = [self resolvedFieldDescriptorForName:fieldName];
    if (field == nil) {
      continue;
    }

    id publicValue = ALNORMChangesetPublicValue(self.values[field.name]);
    ALNORMValueConverter *converter = [self converterForField:field];
    id encoded = publicValue;
    if (converter != nil) {
      encoded = [converter encodeValue:publicValue error:error];
      if (encoded == nil && error != NULL && *error != nil) {
        return nil;
      }
    }
    encodedValues[field.name] = (encoded != nil) ? encoded : [NSNull null];
  }
  return encodedValues;
}

- (BOOL)hasErrors {
  return [self.fieldErrors count] > 0;
}

- (NSArray<NSString *> *)changedFieldNames {
  return [[self.values allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

@end

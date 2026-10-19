#import "ALNORMDataverseChangeset.h"

#import "ALNORMErrors.h"

static id ALNORMDataverseChangesetStoredValue(id value) {
  return (value == nil || value == [NSNull null]) ? [NSNull null] : value;
}

@implementation ALNORMDataverseChangeset {
  NSDictionary<NSString *, id> *_values;
  NSDictionary<NSString *, NSArray<NSString *> *> *_fieldErrors;
}

@synthesize descriptor = _descriptor;
@synthesize model = _model;
@synthesize values = _values;
@synthesize fieldErrors = _fieldErrors;
@synthesize fieldConverters = _fieldConverters;
@synthesize requiredFieldNames = _requiredFieldNames;

+ (instancetype)changesetWithModel:(ALNORMDataverseModel *)model {
  return [[self alloc] initWithDescriptor:model.descriptor model:model fieldConverters:nil requiredFieldNames:nil];
}

- (instancetype)init {
  ALNORMDataverseModelDescriptor *descriptor =
      [[ALNORMDataverseModelDescriptor alloc] initWithClassName:@""
                                                    logicalName:@""
                                                  entitySetName:@""
                                             primaryIDAttribute:@""
                                           primaryNameAttribute:@""
                                                dataverseTarget:nil
                                                       readOnly:NO
                                                         fields:@[]
                                          alternateKeyFieldSets:@[]
                                                      relations:@[]];
  return [self initWithDescriptor:descriptor model:nil fieldConverters:nil requiredFieldNames:nil];
}

- (instancetype)initWithDescriptor:(ALNORMDataverseModelDescriptor *)descriptor
                             model:(ALNORMDataverseModel *)model
                    fieldConverters:(NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConverters
                 requiredFieldNames:(NSArray<NSString *> *)requiredFieldNames {
  self = [super init];
  if (self != nil) {
    _descriptor = descriptor;
    _model = model;
    _fieldConverters = [fieldConverters copy] ?: @{};
    if ([requiredFieldNames count] > 0) {
      _requiredFieldNames = [NSSet setWithArray:requiredFieldNames];
    } else {
      NSMutableSet<NSString *> *required = [NSMutableSet set];
      for (ALNORMDataverseFieldDescriptor *field in descriptor.fields ?: @[]) {
        if (!field.isNullable && !field.isLogical && (field.isCreatable || field.isUpdateable) && !field.isPrimaryID) {
          [required addObject:field.logicalName ?: @""];
        }
      }
      _requiredFieldNames = [required copy];
    }
    _values = @{};
    _fieldErrors = @{};
  }
  return self;
}

- (BOOL)castInputValue:(id)value forFieldName:(NSString *)fieldName error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  ALNORMDataverseFieldDescriptor *field = [self.descriptor fieldNamed:fieldName];
  if (field == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"Dataverse changeset references an unknown field",
                               @{
                                 @"field_name" : fieldName ?: @"",
                               });
    }
    return NO;
  }
  id castValue = value;
  ALNORMValueConverter *converter = self.fieldConverters[field.logicalName];
  if (converter != nil) {
    castValue = [converter decodeValue:value error:error];
    if (castValue == nil && error != NULL && *error != nil) {
      return NO;
    }
  }
  // Batch saves encode a changeset without applying it to the model, so the
  // persisted-ID rule is enforced here as well as in the model setter.
  if (self.model.isPersisted && [field.logicalName isEqualToString:self.descriptor.primaryIDAttribute ?: @""]) {
    id persistedID = [self.model persistedPrimaryIDValue];
    BOOL clearing = (castValue == nil || castValue == [NSNull null]);
    if (persistedID == nil ? !clearing : ![persistedID isEqual:castValue]) {
      [self addError:@"cannot change the primary ID of a persisted record" forFieldName:field.logicalName];
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorReadOnlyMutation,
                                 @"Dataverse changeset cannot change the primary ID of a persisted record",
                                 @{
                                   @"field_name" : field.logicalName ?: @"",
                                   @"entity_name" : self.descriptor.logicalName ?: @"",
                                 });
      }
      return NO;
    }
  }
  NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:self.values ?: @{}];
  updated[field.logicalName] = ALNORMDataverseChangesetStoredValue(castValue);
  _values = [updated copy];
  return YES;
}

- (BOOL)applyInputValues:(NSDictionary<NSString *, id> *)values
         permittedFields:(NSArray<NSString *> *)permittedFields
                   error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (![values isKindOfClass:[NSDictionary class]] || ![permittedFields isKindOfClass:[NSArray class]]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"Dataverse changeset input must be a dictionary and permitted fields an array",
                               nil);
    }
    return NO;
  }
  NSMutableSet<NSString *> *permitted = [NSMutableSet set];
  for (NSString *fieldName in permittedFields) {
    ALNORMDataverseFieldDescriptor *field =
        [fieldName isKindOfClass:[NSString class]] ? [self.descriptor fieldNamed:fieldName] : nil;
    if (field == nil) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                                 @"permitted fields name an unknown Dataverse field",
                                 @{
                                   @"field_name" : [fieldName isKindOfClass:[NSString class]] ? fieldName : @"",
                                 });
      }
      return NO;
    }
    [permitted addObject:field.logicalName];
  }
  // Input keys outside the permit list are dropped, like unknown form fields.
  for (NSString *inputName in values) {
    ALNORMDataverseFieldDescriptor *field = [self.descriptor fieldNamed:inputName];
    if (field == nil || ![permitted containsObject:field.logicalName]) {
      continue;
    }
    if (![self castInputValue:values[inputName] forFieldName:field.logicalName error:error]) {
      return NO;
    }
  }
  return [self validateRequiredFields];
}

- (BOOL)applyInputValues:(NSDictionary<NSString *,id> *)values error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  for (NSString *fieldName in values) {
    if (![self castInputValue:values[fieldName] forFieldName:fieldName error:error]) {
      return NO;
    }
  }
  return [self validateRequiredFields];
}

- (void)addError:(NSString *)message forFieldName:(NSString *)fieldName {
  NSMutableDictionary *errors = [NSMutableDictionary dictionaryWithDictionary:self.fieldErrors ?: @{}];
  NSArray<NSString *> *existing = errors[fieldName] ?: @[];
  errors[fieldName] = [existing arrayByAddingObject:[message copy] ?: @"validation failed"];
  _fieldErrors = [errors copy];
}

- (BOOL)validateRequiredFields {
  for (NSString *fieldName in self.requiredFieldNames ?: [NSSet set]) {
    id value = self.values[fieldName];
    if (value == nil || value == [NSNull null]) {
      [self addError:@"is required" forFieldName:fieldName];
    }
  }
  return ![self hasErrors];
}

- (BOOL)applyToModel:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if ([self hasErrors]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorValidationFailed,
                               @"Dataverse changeset has validation errors",
                               @{
                                 @"field_errors" : self.fieldErrors ?: @{},
                               });
    }
    return NO;
  }
  for (NSString *fieldName in self.values) {
    id value = self.values[fieldName];
    if (![self.model setObject:(value == [NSNull null] ? nil : value) forFieldName:fieldName error:error]) {
      return NO;
    }
  }
  return YES;
}

- (NSDictionary<NSString *, id> *)encodedValues:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if ([self hasErrors]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorValidationFailed,
                               @"Dataverse changeset has validation errors",
                               @{
                                 @"field_errors" : self.fieldErrors ?: @{},
                               });
    }
    return nil;
  }
  NSMutableDictionary *encoded = [NSMutableDictionary dictionary];
  for (NSString *fieldName in self.values) {
    id value = self.values[fieldName];
    ALNORMValueConverter *converter = self.fieldConverters[fieldName];
    id encodedValue = (value == [NSNull null]) ? nil : value;
    if (converter != nil) {
      encodedValue = [converter encodeValue:encodedValue error:error];
      if (encodedValue == nil && error != NULL && *error != nil) {
        return nil;
      }
    }
    encoded[fieldName] = encodedValue ?: [NSNull null];
  }
  return [NSDictionary dictionaryWithDictionary:encoded];
}

- (BOOL)hasErrors {
  return [self.fieldErrors count] > 0;
}

- (NSArray<NSString *> *)changedFieldNames {
  return [[self.values allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

@end

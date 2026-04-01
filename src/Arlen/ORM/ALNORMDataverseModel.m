#import "ALNORMDataverseModel.h"

#import "ALNORMDataverseContext.h"
#import "ALNORMDataverseRepository.h"
#import "ALNORMErrors.h"

static id ALNORMDataverseStoredValue(id value) {
  return (value == nil || value == [NSNull null]) ? [NSNull null] : value;
}

static id ALNORMDataversePublicValue(id value) {
  return (value == [NSNull null]) ? nil : value;
}

@implementation ALNORMDataverseModel {
  NSDictionary<NSString *, id> *_cleanFieldValues;
}

@synthesize descriptor = _descriptor;
@synthesize fieldValues = _fieldValues;
@synthesize relationValues = _relationValues;
@synthesize dirtyFieldNames = _dirtyFieldNames;
@synthesize loadedRelationNames = _loadedRelationNames;
@synthesize rawDictionary = _rawDictionary;
@synthesize etag = _etag;
@synthesize context = _context;
@synthesize persisted = _persisted;

- (instancetype)init {
  ALNORMDataverseModelDescriptor *descriptor = [[self class] dataverseModelDescriptor];
  return [self initWithDescriptor:descriptor];
}

- (instancetype)initWithDescriptor:(ALNORMDataverseModelDescriptor *)descriptor {
  self = [super init];
  if (self != nil) {
    _descriptor = descriptor;
    _fieldValues = @{};
    _relationValues = @{};
    _dirtyFieldNames = [NSSet set];
    _loadedRelationNames = [NSSet set];
    _rawDictionary = @{};
    _etag = @"";
    _persisted = NO;
    _cleanFieldValues = @{};
  }
  return self;
}

+ (ALNORMDataverseModelDescriptor *)dataverseModelDescriptor {
  return nil;
}

+ (ALNDataverseQuery *)query {
  ALNORMDataverseModelDescriptor *descriptor = [self dataverseModelDescriptor];
  NSError *error = nil;
  return [ALNDataverseQuery queryWithEntitySetName:descriptor.entitySetName error:&error];
}

+ (ALNORMDataverseRepository *)repositoryWithContext:(ALNORMDataverseContext *)context {
  return [context repositoryForModelClass:self];
}

+ (instancetype)modelFromRecord:(ALNDataverseRecord *)record error:(NSError **)error {
  ALNORMDataverseModel *model = [[self alloc] init];
  if (![model applyRecord:record error:error]) {
    return nil;
  }
  return (id)model;
}

- (nullable id)objectForFieldName:(NSString *)fieldName {
  ALNORMDataverseFieldDescriptor *field = [self.descriptor fieldNamed:fieldName];
  if (field == nil) {
    field = [self.descriptor fieldForReadKey:fieldName];
  }
  if (field == nil) {
    return nil;
  }
  return ALNORMDataversePublicValue(self.fieldValues[field.logicalName]);
}

- (BOOL)setObject:(id)value forFieldName:(NSString *)fieldName error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  ALNORMDataverseFieldDescriptor *field = [self.descriptor fieldNamed:fieldName];
  if (field == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"Dataverse model does not define the requested field",
                               @{
                                 @"field_name" : fieldName ?: @"",
                                 @"entity_name" : self.descriptor.logicalName ?: @"",
                               });
    }
    return NO;
  }
  if (self.descriptor.isReadOnly || (!field.isCreatable && !field.isUpdateable)) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorReadOnlyMutation,
                               @"Dataverse model field is read-only",
                               @{
                                 @"field_name" : field.logicalName ?: @"",
                                 @"entity_name" : self.descriptor.logicalName ?: @"",
                               });
    }
    return NO;
  }
  if ((value == nil || value == [NSNull null]) && !field.isNullable) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorMissingField,
                               @"Dataverse model field does not allow nil",
                               @{
                                 @"field_name" : field.logicalName ?: @"",
                               });
    }
    return NO;
  }

  NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:self.fieldValues ?: @{}];
  updated[field.logicalName] = ALNORMDataverseStoredValue(value);
  _fieldValues = [updated copy];

  NSMutableSet *dirty = [NSMutableSet setWithSet:self.dirtyFieldNames ?: [NSSet set]];
  id cleanValue = _cleanFieldValues[field.logicalName];
  id candidate = updated[field.logicalName];
  if ((cleanValue == nil && candidate == [NSNull null]) || [cleanValue isEqual:candidate]) {
    [dirty removeObject:field.logicalName ?: @""];
  } else {
    [dirty addObject:field.logicalName ?: @""];
  }
  _dirtyFieldNames = [dirty copy];
  return YES;
}

- (BOOL)applyRecord:(ALNDataverseRecord *)record error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (![record isKindOfClass:[ALNDataverseRecord class]]) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"Dataverse materialization requires a Dataverse record",
                               nil);
    }
    return NO;
  }

  NSMutableDictionary *values = [NSMutableDictionary dictionary];
  NSDictionary<NSString *, id> *recordValues = record.values ?: @{};
  for (ALNORMDataverseFieldDescriptor *field in self.descriptor.fields ?: @[]) {
    id value = recordValues[field.readKey];
    if (value == nil && ![field.readKey isEqualToString:field.logicalName]) {
      value = recordValues[field.logicalName];
    }
    if (value != nil) {
      values[field.logicalName] = ALNORMDataverseStoredValue(value);
    }
  }
  _fieldValues = [values copy];
  _cleanFieldValues = [values copy];
  _dirtyFieldNames = [NSSet set];
  _loadedRelationNames = [NSSet set];
  _relationValues = @{};
  _rawDictionary = record.rawDictionary ?: @{};
  _etag = [record.etag copy] ?: @"";
  _persisted = YES;
  return YES;
}

- (void)markClean {
  _cleanFieldValues = [self.fieldValues copy] ?: @{};
  _dirtyFieldNames = [NSSet set];
}

- (void)attachToContext:(ALNORMDataverseContext *)context {
  _context = context;
}

- (id)relationObjectForName:(NSString *)relationName {
  return ALNORMDataversePublicValue(self.relationValues[relationName ?: @""]);
}

- (BOOL)markRelationLoaded:(NSString *)relationName value:(id)value error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if ([self.descriptor relationNamed:relationName] == nil) {
    if (error != NULL) {
      *error = ALNORMMakeError(ALNORMErrorInvalidArgument,
                               @"Dataverse model relation is not defined",
                               @{
                                 @"relation_name" : relationName ?: @"",
                               });
    }
    return NO;
  }
  NSMutableDictionary *relations = [NSMutableDictionary dictionaryWithDictionary:self.relationValues ?: @{}];
  relations[relationName ?: @""] = ALNORMDataverseStoredValue(value);
  _relationValues = [relations copy];
  NSMutableSet *loaded = [NSMutableSet setWithSet:self.loadedRelationNames ?: [NSSet set]];
  [loaded addObject:relationName ?: @""];
  _loadedRelationNames = [loaded copy];
  return YES;
}

- (id)primaryIDValue {
  return [self objectForFieldName:self.descriptor.primaryIDAttribute];
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
  NSMutableDictionary *renderedValues = [NSMutableDictionary dictionary];
  for (NSString *fieldName in self.fieldValues) {
    renderedValues[fieldName] = ALNORMDataversePublicValue(self.fieldValues[fieldName]) ?: [NSNull null];
  }
  return @{
    @"descriptor" : [self.descriptor dictionaryRepresentation],
    @"persisted" : @(self.isPersisted),
    @"field_values" : renderedValues,
    @"dirty_field_names" : [[self.dirtyFieldNames allObjects] sortedArrayUsingSelector:@selector(compare:)],
    @"etag" : self.etag ?: @"",
  };
}

@end

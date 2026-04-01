#import "ALNORMChangeset.h"

#import "ALNORMErrors.h"
#import "ALNORMFieldDescriptor.h"

@interface ALNORMChangeset ()

@property(nonatomic, strong, readwrite) ALNORMModelDescriptor *descriptor;
@property(nonatomic, weak, readwrite) ALNORMModel *model;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, id> *values;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, NSArray<NSString *> *> *fieldErrors;

@end

@implementation ALNORMChangeset

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
- (instancetype)init {
  return [self initWithDescriptor:nil model:nil];
}
#pragma clang diagnostic pop

- (instancetype)initWithDescriptor:(ALNORMModelDescriptor *)descriptor
                             model:(ALNORMModel *)model {
  self = [super init];
  if (self != nil) {
    _descriptor = descriptor;
    _model = model;
    _values = @{};
    _fieldErrors = @{};
  }
  return self;
}

- (BOOL)setObject:(id)value
     forFieldName:(NSString *)fieldName
            error:(NSError **)error {
  ALNORMFieldDescriptor *field = [self.descriptor fieldNamed:fieldName] ?: [self.descriptor fieldForPropertyName:fieldName];
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
  if (value == nil || value == [NSNull null]) {
    [values removeObjectForKey:field.name ?: @""];
  } else {
    values[field.name] = value;
  }
  self.values = values;
  return YES;
}

- (id)objectForFieldName:(NSString *)fieldName {
  ALNORMFieldDescriptor *field = [self.descriptor fieldNamed:fieldName] ?: [self.descriptor fieldForPropertyName:fieldName];
  return (field != nil) ? self.values[field.name] : nil;
}

- (void)addError:(NSString *)message forFieldName:(NSString *)fieldName {
  NSString *key = [fieldName copy] ?: @"";
  NSArray *existing = [self.fieldErrors[key] isKindOfClass:[NSArray class]] ? self.fieldErrors[key] : @[];
  NSMutableDictionary *errors = [NSMutableDictionary dictionaryWithDictionary:self.fieldErrors ?: @{}];
  errors[key] = [existing arrayByAddingObject:message ?: @"invalid"];
  self.fieldErrors = errors;
}

- (BOOL)hasErrors {
  return [self.fieldErrors count] > 0;
}

- (NSArray<NSString *> *)changedFieldNames {
  return [[self.values allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

@end

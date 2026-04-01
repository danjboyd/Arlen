#import "ALNORMQuery.h"

#import "ALNORMErrors.h"
#import "ALNORMFieldDescriptor.h"
#import "ALNORMModel.h"

static NSString *ALNORMQueryTrimmedString(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL ALNORMQueryIdentifierIsSafe(NSString *value) {
  NSString *candidate = ALNORMQueryTrimmedString(value);
  if ([candidate length] == 0) {
    return NO;
  }
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_."];
  if ([[candidate stringByTrimmingCharactersInSet:allowed] length] > 0) {
    return NO;
  }
  NSArray *parts = [candidate componentsSeparatedByString:@"."];
  for (NSString *part in parts) {
    if ([part length] == 0) {
      return NO;
    }
    unichar first = [part characterAtIndex:0];
    if (![[NSCharacterSet letterCharacterSet] characterIsMember:first] && first != '_') {
      return NO;
    }
  }
  return YES;
}

@interface ALNORMQuery ()

@property(nonatomic, assign, readwrite) Class modelClass;
@property(nonatomic, strong, readwrite) ALNORMModelDescriptor *descriptor;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *selectedFieldNames;
@property(nonatomic, copy, readwrite) NSArray<NSDictionary<NSString *, id> *> *joins;
@property(nonatomic, copy, readwrite) NSArray<NSDictionary<NSString *, id> *> *predicates;
@property(nonatomic, copy, readwrite) NSArray<NSDictionary<NSString *, id> *> *orderings;
@property(nonatomic, assign, readwrite) BOOL hasLimit;
@property(nonatomic, assign, readwrite) NSUInteger limitValue;
@property(nonatomic, assign, readwrite) BOOL hasOffset;
@property(nonatomic, assign, readwrite) NSUInteger offsetValue;

@end

@implementation ALNORMQuery

+ (instancetype)queryWithModelClass:(Class)modelClass {
  if (modelClass == Nil || ![modelClass respondsToSelector:@selector(modelDescriptor)]) {
    return nil;
  }
  ALNORMModelDescriptor *descriptor = [modelClass modelDescriptor];
  if (![descriptor isKindOfClass:[ALNORMModelDescriptor class]]) {
    return nil;
  }
  return [[self alloc] initWithModelClass:modelClass descriptor:descriptor];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
- (instancetype)init {
  return [self initWithModelClass:Nil descriptor:nil];
}
#pragma clang diagnostic pop

- (instancetype)initWithModelClass:(Class)modelClass
                        descriptor:(ALNORMModelDescriptor *)descriptor {
  self = [super init];
  if (self != nil) {
    _modelClass = modelClass;
    _descriptor = descriptor;
    _selectedFieldNames = [descriptor allFieldNames];
    _joins = @[];
    _predicates = @[];
    _orderings = @[];
    _hasLimit = NO;
    _limitValue = 0;
    _hasOffset = NO;
    _offsetValue = 0;
  }
  return self;
}

- (ALNORMFieldDescriptor *)resolvedFieldDescriptorForName:(NSString *)fieldName {
  NSString *candidate = ALNORMQueryTrimmedString(fieldName);
  if ([candidate length] == 0) {
    return nil;
  }
  ALNORMFieldDescriptor *field = [self.descriptor fieldNamed:candidate];
  if (field != nil) {
    return field;
  }
  field = [self.descriptor fieldForPropertyName:candidate];
  if (field != nil) {
    return field;
  }
  return [self.descriptor fieldForColumnName:candidate];
}

- (NSString *)qualifiedFieldNameForDescriptor:(ALNORMFieldDescriptor *)field {
  if (field == nil) {
    return @"";
  }
  return [NSString stringWithFormat:@"%@.%@", self.descriptor.qualifiedTableName ?: @"", field.columnName ?: @""];
}

- (ALNORMQuery *)selectFields:(NSArray<NSString *> *)fieldNames {
  NSMutableArray *selected = [NSMutableArray array];
  for (id rawName in fieldNames ?: @[]) {
    if (![rawName isKindOfClass:[NSString class]]) {
      continue;
    }
    ALNORMFieldDescriptor *field = [self resolvedFieldDescriptorForName:rawName];
    if (field != nil) {
      [selected addObject:field.name ?: @""];
    }
  }
  self.selectedFieldNames = ([selected count] > 0) ? [selected copy] : [self.descriptor allFieldNames];
  return self;
}

- (ALNORMQuery *)selectProperties:(NSArray<NSString *> *)propertyNames {
  return [self selectFields:propertyNames];
}

- (ALNORMQuery *)whereField:(NSString *)fieldName equals:(id)value {
  return [self whereField:fieldName operator:@"=" value:value];
}

- (ALNORMQuery *)whereField:(NSString *)fieldName
                   operator:(NSString *)operatorName
                      value:(id)value {
  NSMutableArray *predicates = [NSMutableArray arrayWithArray:self.predicates ?: @[]];
  [predicates addObject:@{
    @"kind" : @"field",
    @"field_name" : ALNORMQueryTrimmedString(fieldName),
    @"operator" : ALNORMQueryTrimmedString(operatorName),
    @"value" : value ?: [NSNull null],
  }];
  self.predicates = predicates;
  return self;
}

- (ALNORMQuery *)whereFieldIn:(NSString *)fieldName values:(NSArray *)values {
  NSMutableArray *predicates = [NSMutableArray arrayWithArray:self.predicates ?: @[]];
  [predicates addObject:@{
    @"kind" : @"field_in",
    @"field_name" : ALNORMQueryTrimmedString(fieldName),
    @"values" : [values copy] ?: @[],
  }];
  self.predicates = predicates;
  return self;
}

- (ALNORMQuery *)whereFieldNotIn:(NSString *)fieldName values:(NSArray *)values {
  NSMutableArray *predicates = [NSMutableArray arrayWithArray:self.predicates ?: @[]];
  [predicates addObject:@{
    @"kind" : @"field_not_in",
    @"field_name" : ALNORMQueryTrimmedString(fieldName),
    @"values" : [values copy] ?: @[],
  }];
  self.predicates = predicates;
  return self;
}

- (ALNORMQuery *)whereQualifiedField:(NSString *)qualifiedField
                            operator:(NSString *)operatorName
                               value:(id)value {
  NSMutableArray *predicates = [NSMutableArray arrayWithArray:self.predicates ?: @[]];
  [predicates addObject:@{
    @"kind" : @"qualified_field",
    @"qualified_field" : ALNORMQueryTrimmedString(qualifiedField),
    @"operator" : ALNORMQueryTrimmedString(operatorName),
    @"value" : value ?: [NSNull null],
  }];
  self.predicates = predicates;
  return self;
}

- (ALNORMQuery *)whereExpression:(NSString *)expression parameters:(NSArray *)parameters {
  NSMutableArray *predicates = [NSMutableArray arrayWithArray:self.predicates ?: @[]];
  [predicates addObject:@{
    @"kind" : @"expression",
    @"expression" : [expression copy] ?: @"",
    @"parameters" : [parameters copy] ?: @[],
  }];
  self.predicates = predicates;
  return self;
}

- (ALNORMQuery *)whereField:(NSString *)fieldName inSubquery:(ALNSQLBuilder *)subquery {
  NSMutableArray *predicates = [NSMutableArray arrayWithArray:self.predicates ?: @[]];
  [predicates addObject:@{
    @"kind" : @"field_in_subquery",
    @"field_name" : ALNORMQueryTrimmedString(fieldName),
    @"subquery" : subquery ?: [NSNull null],
  }];
  self.predicates = predicates;
  return self;
}

- (ALNORMQuery *)joinTable:(NSString *)tableName
               onLeftField:(NSString *)leftField
                  operator:(NSString *)operatorName
              onRightField:(NSString *)rightField {
  NSMutableArray *joins = [NSMutableArray arrayWithArray:self.joins ?: @[]];
  [joins addObject:@{
    @"table_name" : ALNORMQueryTrimmedString(tableName),
    @"left_field" : ALNORMQueryTrimmedString(leftField),
    @"operator" : ALNORMQueryTrimmedString(operatorName),
    @"right_field" : ALNORMQueryTrimmedString(rightField),
  }];
  self.joins = joins;
  return self;
}

- (ALNORMQuery *)orderByField:(NSString *)fieldName descending:(BOOL)descending {
  NSMutableArray *orderings = [NSMutableArray arrayWithArray:self.orderings ?: @[]];
  [orderings addObject:@{
    @"field_name" : ALNORMQueryTrimmedString(fieldName),
    @"descending" : @(descending),
  }];
  self.orderings = orderings;
  return self;
}

- (ALNORMQuery *)limit:(NSUInteger)limit {
  self.hasLimit = YES;
  self.limitValue = limit;
  return self;
}

- (ALNORMQuery *)offset:(NSUInteger)offset {
  self.hasOffset = YES;
  self.offsetValue = offset;
  return self;
}

- (ALNORMQuery *)applyScope:(ALNORMQueryScope)scope {
  if (scope != nil) {
    scope(self);
  }
  return self;
}

- (ALNSQLBuilder *)selectBuilder:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }

  NSMutableArray *columns = [NSMutableArray array];
  for (NSString *fieldName in self.selectedFieldNames ?: @[]) {
    ALNORMFieldDescriptor *field = [self resolvedFieldDescriptorForName:fieldName];
    if (field == nil) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorQueryBuildFailed,
                                 @"query selects an unknown field",
                                 @{
                                   @"field_name" : fieldName ?: @"",
                                   @"entity_name" : self.descriptor.entityName ?: @"",
                                 });
      }
      return nil;
    }
    [columns addObject:[self qualifiedFieldNameForDescriptor:field]];
  }

  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:self.descriptor.qualifiedTableName
                                             columns:columns];
  for (NSDictionary *join in self.joins ?: @[]) {
    NSString *tableName = join[@"table_name"];
    NSString *leftField = join[@"left_field"];
    NSString *operatorName = join[@"operator"];
    NSString *rightField = join[@"right_field"];
    if (!ALNORMQueryIdentifierIsSafe(tableName) ||
        !ALNORMQueryIdentifierIsSafe(leftField) ||
        !ALNORMQueryIdentifierIsSafe(rightField)) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorQueryBuildFailed,
                                 @"query join contains an unsafe identifier",
                                 join);
      }
      return nil;
    }
    [builder joinTable:tableName
                 alias:nil
           onLeftField:leftField
              operator:operatorName
          onRightField:rightField];
  }

  for (NSDictionary *predicate in self.predicates ?: @[]) {
    NSString *kind = predicate[@"kind"];
    if ([kind isEqualToString:@"field"]) {
      ALNORMFieldDescriptor *field = [self resolvedFieldDescriptorForName:predicate[@"field_name"]];
      if (field == nil) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorQueryBuildFailed,
                                   @"query predicate references an unknown field",
                                   predicate);
        }
        return nil;
      }
      id value = predicate[@"value"];
      if (value == [NSNull null]) {
        value = nil;
      }
      [builder whereField:[self qualifiedFieldNameForDescriptor:field]
                 operator:predicate[@"operator"]
                    value:value];
      continue;
    }

    if ([kind isEqualToString:@"field_in"]) {
      ALNORMFieldDescriptor *field = [self resolvedFieldDescriptorForName:predicate[@"field_name"]];
      if (field == nil) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorQueryBuildFailed,
                                   @"query predicate references an unknown field",
                                   predicate);
        }
        return nil;
      }
      [builder whereFieldIn:[self qualifiedFieldNameForDescriptor:field]
                     values:predicate[@"values"] ?: @[]];
      continue;
    }

    if ([kind isEqualToString:@"field_not_in"]) {
      ALNORMFieldDescriptor *field = [self resolvedFieldDescriptorForName:predicate[@"field_name"]];
      if (field == nil) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorQueryBuildFailed,
                                   @"query predicate references an unknown field",
                                   predicate);
        }
        return nil;
      }
      [builder whereFieldNotIn:[self qualifiedFieldNameForDescriptor:field]
                        values:predicate[@"values"] ?: @[]];
      continue;
    }

    if ([kind isEqualToString:@"qualified_field"]) {
      NSString *qualifiedField = predicate[@"qualified_field"];
      if (!ALNORMQueryIdentifierIsSafe(qualifiedField)) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorQueryBuildFailed,
                                   @"query predicate contains an unsafe qualified field",
                                   predicate);
        }
        return nil;
      }
      id value = predicate[@"value"];
      if (value == [NSNull null]) {
        value = nil;
      }
      [builder whereField:qualifiedField
                 operator:predicate[@"operator"]
                    value:value];
      continue;
    }

    if ([kind isEqualToString:@"field_in_subquery"]) {
      ALNORMFieldDescriptor *field = [self resolvedFieldDescriptorForName:predicate[@"field_name"]];
      ALNSQLBuilder *subquery = predicate[@"subquery"];
      if (field == nil || ![subquery isKindOfClass:[ALNSQLBuilder class]]) {
        if (error != NULL) {
          *error = ALNORMMakeError(ALNORMErrorQueryBuildFailed,
                                   @"query subquery predicate is invalid",
                                   predicate);
        }
        return nil;
      }
      [builder whereField:[self qualifiedFieldNameForDescriptor:field] inSubquery:subquery];
      continue;
    }

    if ([kind isEqualToString:@"expression"]) {
      [builder whereExpression:predicate[@"expression"] parameters:predicate[@"parameters"]];
      continue;
    }
  }

  for (NSDictionary *ordering in self.orderings ?: @[]) {
    ALNORMFieldDescriptor *field = [self resolvedFieldDescriptorForName:ordering[@"field_name"]];
    if (field == nil) {
      if (error != NULL) {
        *error = ALNORMMakeError(ALNORMErrorQueryBuildFailed,
                                 @"query ordering references an unknown field",
                                 ordering);
      }
      return nil;
    }
    [builder orderByField:[self qualifiedFieldNameForDescriptor:field]
               descending:[ordering[@"descending"] boolValue]];
  }

  if (self.hasLimit) {
    [builder limit:self.limitValue];
  }
  if (self.hasOffset) {
    [builder offset:self.offsetValue];
  }
  return builder;
}

@end

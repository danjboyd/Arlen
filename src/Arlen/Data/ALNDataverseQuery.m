#import "ALNDataverseQuery.h"

#import <ctype.h>
#import <string.h>

NSString *const ALNDataverseQueryErrorDomain = @"Arlen.Data.Dataverse.Query.Error";

static NSString *ALNDataverseQueryTrimmedString(id value) {
  if ([value isKindOfClass:[NSString class]]) {
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [[value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  return @"";
}

static BOOL ALNDataverseQueryIdentifierIsSafe(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return NO;
  }
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
  if ([[value stringByTrimmingCharactersInSet:allowed] length] > 0) {
    return NO;
  }
  unichar first = [value characterAtIndex:0];
  return ([[NSCharacterSet letterCharacterSet] characterIsMember:first] || first == '_');
}

static BOOL ALNDataverseQueryLooksLikeGUID(NSString *value) {
  NSString *trimmed = ALNDataverseQueryTrimmedString(value);
  if ([trimmed length] != 36) {
    return NO;
  }
  for (NSUInteger idx = 0; idx < [trimmed length]; idx++) {
    unichar character = [trimmed characterAtIndex:idx];
    if (idx == 8 || idx == 13 || idx == 18 || idx == 23) {
      if (character != '-') {
        return NO;
      }
      continue;
    }
    if (!isxdigit((int)character)) {
      return NO;
    }
  }
  return YES;
}

static BOOL ALNDataverseQueryNumberLooksBoolean(NSNumber *number) {
  if (number == nil) {
    return NO;
  }
  const char *type = [number objCType];
  if (type == NULL) {
    return NO;
  }
  return (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, "B") == 0);
}

static NSString *ALNDataverseQueryEscapeStringLiteral(NSString *value) {
  return [ALNDataverseQueryTrimmedString(value) stringByReplacingOccurrencesOfString:@"'"
                                                                           withString:@"''"];
}

NSError *ALNDataverseQueryMakeError(ALNDataverseQueryErrorCode code,
                                    NSString *message,
                                    NSDictionary *userInfo) {
  NSMutableDictionary *details = [NSMutableDictionary dictionaryWithDictionary:userInfo ?: @{}];
  details[NSLocalizedDescriptionKey] = message ?: @"Dataverse query error";
  return [NSError errorWithDomain:ALNDataverseQueryErrorDomain code:code userInfo:details];
}

static NSString *ALNDataverseQueryLiteral(id value, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (value == nil || value == [NSNull null]) {
    return @"null";
  }
  if ([value isKindOfClass:[NSString class]]) {
    NSString *text = (NSString *)value;
    if (ALNDataverseQueryLooksLikeGUID(text)) {
      return text;
    }
    return [NSString stringWithFormat:@"'%@'", ALNDataverseQueryEscapeStringLiteral(text)];
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    if (ALNDataverseQueryNumberLooksBoolean((NSNumber *)value)) {
      return [(NSNumber *)value boolValue] ? @"true" : @"false";
    }
    return [(NSNumber *)value stringValue];
  }
  if ([value isKindOfClass:[NSUUID class]]) {
    return [(NSUUID *)value UUIDString];
  }
  if ([value isKindOfClass:[NSDate class]]) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      formatter = [[NSDateFormatter alloc] init];
      formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
      formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
      formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    });
    return [formatter stringFromDate:(NSDate *)value] ?: @"";
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [NSString stringWithFormat:@"'%@'",
                                      ALNDataverseQueryEscapeStringLiteral([value stringValue] ?: @"")];
  }
  if (error != NULL) {
    *error = ALNDataverseQueryMakeError(ALNDataverseQueryErrorUnsupportedPredicate,
                                        @"Dataverse filter contains an unsupported literal value",
                                        @{ @"value" : [value description] ?: @"" });
  }
  return nil;
}

static NSString *ALNDataverseQueryFieldIdentifier(NSString *field, NSError **error) {
  NSString *identifier = ALNDataverseQueryTrimmedString(field);
  if (!ALNDataverseQueryIdentifierIsSafe(identifier)) {
    if (error != NULL) {
      *error = ALNDataverseQueryMakeError(ALNDataverseQueryErrorInvalidArgument,
                                          @"Dataverse query identifier must match [A-Za-z_][A-Za-z0-9_]*",
                                          @{ @"identifier" : identifier ?: @"" });
    }
    return nil;
  }
  return identifier;
}

static NSString *ALNDataverseQueryLikeExpression(NSString *field,
                                                 NSString *value,
                                                 BOOL negate,
                                                 NSError **error) {
  NSString *identifier = ALNDataverseQueryFieldIdentifier(field, error);
  if ([identifier length] == 0) {
    return nil;
  }
  NSString *pattern = ALNDataverseQueryTrimmedString(value);
  NSString *lowerPattern = [[pattern lowercaseString] stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
  NSString *wrappedField = [NSString stringWithFormat:@"tolower(%@)", identifier];
  NSString *expression = nil;
  if ([pattern hasPrefix:@"%"] && [pattern hasSuffix:@"%"] && [pattern length] >= 2) {
    NSString *needle = [lowerPattern substringWithRange:NSMakeRange(1, [lowerPattern length] - 2)];
    expression = [NSString stringWithFormat:@"contains(%@,'%@')", wrappedField, needle];
  } else if ([pattern hasPrefix:@"%"] && [pattern length] >= 2) {
    NSString *needle = [lowerPattern substringFromIndex:1];
    expression = [NSString stringWithFormat:@"endswith(%@,'%@')", wrappedField, needle];
  } else if ([pattern hasSuffix:@"%"] && [pattern length] >= 2) {
    NSString *needle = [lowerPattern substringToIndex:([lowerPattern length] - 1)];
    expression = [NSString stringWithFormat:@"startswith(%@,'%@')", wrappedField, needle];
  } else {
    expression = [NSString stringWithFormat:@"contains(%@,'%@')", wrappedField, lowerPattern];
  }
  return negate ? [NSString stringWithFormat:@"not (%@)", expression] : expression;
}

static NSString *ALNDataverseQueryExpressionFromNode(id node, NSError **error);

static NSString *ALNDataverseQueryComparisonExpression(NSString *field,
                                                       NSString *operatorString,
                                                       id value,
                                                       NSError **error) {
  NSString *identifier = ALNDataverseQueryFieldIdentifier(field, error);
  if ([identifier length] == 0) {
    return nil;
  }

  NSString *normalizedOperator = [[ALNDataverseQueryTrimmedString(operatorString) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalizedOperator isEqualToString:@"=="]) {
    normalizedOperator = @"=";
  }
  if ([normalizedOperator isEqualToString:@"<>"]) {
    normalizedOperator = @"!=";
  }

  if ([normalizedOperator isEqualToString:@"-like"] || [normalizedOperator isEqualToString:@"like"]) {
    return ALNDataverseQueryLikeExpression(identifier, value, NO, error);
  }
  if ([normalizedOperator isEqualToString:@"-not_like"] || [normalizedOperator isEqualToString:@"not_like"]) {
    return ALNDataverseQueryLikeExpression(identifier, value, YES, error);
  }
  if ([normalizedOperator isEqualToString:@"-contains"]) {
    return [NSString stringWithFormat:@"contains(tolower(%@),'%@')",
                                      identifier,
                                      ALNDataverseQueryEscapeStringLiteral([[ALNDataverseQueryTrimmedString(value) lowercaseString]
                                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]])];
  }
  if ([normalizedOperator isEqualToString:@"-startswith"]) {
    return [NSString stringWithFormat:@"startswith(tolower(%@),'%@')",
                                      identifier,
                                      ALNDataverseQueryEscapeStringLiteral([[ALNDataverseQueryTrimmedString(value) lowercaseString]
                                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]])];
  }
  if ([normalizedOperator isEqualToString:@"-endswith"]) {
    return [NSString stringWithFormat:@"endswith(tolower(%@),'%@')",
                                      identifier,
                                      ALNDataverseQueryEscapeStringLiteral([[ALNDataverseQueryTrimmedString(value) lowercaseString]
                                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]])];
  }
  if ([normalizedOperator isEqualToString:@"-in"] || [normalizedOperator isEqualToString:@"-not_in"]) {
    NSArray *items = [value isKindOfClass:[NSArray class]] ? value : nil;
    if ([items count] == 0) {
      if (error != NULL) {
        *error = ALNDataverseQueryMakeError(ALNDataverseQueryErrorUnsupportedPredicate,
                                            @"Dataverse -in and -not_in require a non-empty array",
                                            @{ @"field" : identifier ?: @"" });
      }
      return nil;
    }
    NSMutableArray<NSString *> *comparisons = [NSMutableArray arrayWithCapacity:[items count]];
    for (id item in items) {
      NSError *literalError = nil;
      NSString *literal = ALNDataverseQueryLiteral(item, &literalError);
      if ([literal length] == 0 || literalError != nil) {
        if (error != NULL) {
          *error = literalError;
        }
        return nil;
      }
      [comparisons addObject:[NSString stringWithFormat:@"%@ eq %@", identifier, literal]];
    }
    NSString *joined = [comparisons componentsJoinedByString:@" or "];
    return [normalizedOperator isEqualToString:@"-not_in"]
               ? [NSString stringWithFormat:@"not (%@)", joined]
               : [NSString stringWithFormat:@"(%@)", joined];
  }

  NSString *odataOperator = nil;
  if ([normalizedOperator isEqualToString:@"="]) {
    odataOperator = @"eq";
  } else if ([normalizedOperator isEqualToString:@"!="]) {
    odataOperator = @"ne";
  } else if ([normalizedOperator isEqualToString:@"<"]) {
    odataOperator = @"lt";
  } else if ([normalizedOperator isEqualToString:@"<="]) {
    odataOperator = @"le";
  } else if ([normalizedOperator isEqualToString:@">"]) {
    odataOperator = @"gt";
  } else if ([normalizedOperator isEqualToString:@">="]) {
    odataOperator = @"ge";
  }

  if ([odataOperator length] == 0) {
    if (error != NULL) {
      *error = ALNDataverseQueryMakeError(ALNDataverseQueryErrorUnsupportedPredicate,
                                          @"Dataverse query operator is unsupported",
                                          @{
                                            @"field" : identifier ?: @"",
                                            @"operator" : operatorString ?: @"",
                                          });
    }
    return nil;
  }

  NSError *literalError = nil;
  NSString *literal = ALNDataverseQueryLiteral(value, &literalError);
  if ([literal length] == 0 || literalError != nil) {
    if (error != NULL) {
      *error = literalError;
    }
    return nil;
  }
  return [NSString stringWithFormat:@"%@ %@ %@", identifier, odataOperator, literal];
}

static NSString *ALNDataverseQueryFieldExpression(NSString *field, id value, NSError **error) {
  if ([value isKindOfClass:[NSDictionary class]]) {
    NSArray<NSString *> *keys = [[(NSDictionary *)value allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:[keys count]];
    for (NSString *operatorString in keys) {
      NSError *comparisonError = nil;
      NSString *expression =
          ALNDataverseQueryComparisonExpression(field, operatorString, value[operatorString], &comparisonError);
      if ([expression length] == 0 || comparisonError != nil) {
        if (error != NULL) {
          *error = comparisonError;
        }
        return nil;
      }
      [parts addObject:expression];
    }
    return ([parts count] == 1) ? parts[0] : [NSString stringWithFormat:@"(%@)", [parts componentsJoinedByString:@" and "]];
  }
  if ([value isKindOfClass:[NSArray class]]) {
    return ALNDataverseQueryComparisonExpression(field, @"-in", value, error);
  }
  if (value == nil || value == [NSNull null]) {
    return ALNDataverseQueryComparisonExpression(field, @"=", value, error);
  }
  return ALNDataverseQueryComparisonExpression(field, @"=", value, error);
}

static NSString *ALNDataverseQueryJoinExpressions(NSArray<NSString *> *parts, NSString *separator) {
  NSMutableArray<NSString *> *filtered = [NSMutableArray array];
  for (NSString *part in parts) {
    if ([ALNDataverseQueryTrimmedString(part) length] > 0) {
      [filtered addObject:part];
    }
  }
  if ([filtered count] == 0) {
    return @"";
  }
  if ([filtered count] == 1) {
    return filtered[0];
  }
  return [NSString stringWithFormat:@"(%@)", [filtered componentsJoinedByString:separator]];
}

static NSString *ALNDataverseQueryExpressionFromArray(NSArray *items, NSError **error) {
  NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:[items count]];
  for (id item in items) {
    NSError *childError = nil;
    NSString *child = ALNDataverseQueryExpressionFromNode(item, &childError);
    if ([child length] == 0 || childError != nil) {
      if (error != NULL) {
        *error = childError;
      }
      return nil;
    }
    [parts addObject:child];
  }
  return ALNDataverseQueryJoinExpressions(parts, @" and ");
}

static NSString *ALNDataverseQueryExpressionFromDictionary(NSDictionary *dictionary, NSError **error) {
  NSMutableArray<NSString *> *parts = [NSMutableArray array];

  NSArray<NSString *> *keys = [[dictionary allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in keys) {
    id value = dictionary[key];
    if ([key isEqualToString:@"-and"]) {
      NSArray *group = [value isKindOfClass:[NSArray class]] ? value : nil;
      if ([group count] == 0) {
        if (error != NULL) {
          *error = ALNDataverseQueryMakeError(ALNDataverseQueryErrorUnsupportedPredicate,
                                              @"Dataverse -and requires a non-empty array",
                                              nil);
        }
        return nil;
      }
      NSMutableArray<NSString *> *groupExpressions = [NSMutableArray arrayWithCapacity:[group count]];
      for (id entry in group) {
        NSError *groupError = nil;
        NSString *expression = ALNDataverseQueryExpressionFromNode(entry, &groupError);
        if ([expression length] == 0 || groupError != nil) {
          if (error != NULL) {
            *error = groupError;
          }
          return nil;
        }
        [groupExpressions addObject:expression];
      }
      [parts addObject:ALNDataverseQueryJoinExpressions(groupExpressions, @" and ")];
      continue;
    }
    if ([key isEqualToString:@"-or"]) {
      NSArray *group = [value isKindOfClass:[NSArray class]] ? value : nil;
      if ([group count] == 0) {
        if (error != NULL) {
          *error = ALNDataverseQueryMakeError(ALNDataverseQueryErrorUnsupportedPredicate,
                                              @"Dataverse -or requires a non-empty array",
                                              nil);
        }
        return nil;
      }
      NSMutableArray<NSString *> *groupExpressions = [NSMutableArray arrayWithCapacity:[group count]];
      for (id entry in group) {
        NSError *groupError = nil;
        NSString *expression = ALNDataverseQueryExpressionFromNode(entry, &groupError);
        if ([expression length] == 0 || groupError != nil) {
          if (error != NULL) {
            *error = groupError;
          }
          return nil;
        }
        [groupExpressions addObject:expression];
      }
      [parts addObject:ALNDataverseQueryJoinExpressions(groupExpressions, @" or ")];
      continue;
    }
    if ([key isEqualToString:@"-not"]) {
      NSError *groupError = nil;
      NSString *expression = ALNDataverseQueryExpressionFromNode(value, &groupError);
      if ([expression length] == 0 || groupError != nil) {
        if (error != NULL) {
          *error = groupError;
        }
        return nil;
      }
      [parts addObject:[NSString stringWithFormat:@"not (%@)", expression]];
      continue;
    }

    NSError *fieldError = nil;
    NSString *expression = ALNDataverseQueryFieldExpression(key, value, &fieldError);
    if ([expression length] == 0 || fieldError != nil) {
      if (error != NULL) {
        *error = fieldError;
      }
      return nil;
    }
    [parts addObject:expression];
  }

  return ALNDataverseQueryJoinExpressions(parts, @" and ");
}

static NSString *ALNDataverseQueryExpressionFromNode(id node, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (node == nil || node == [NSNull null]) {
    return @"";
  }
  if ([node isKindOfClass:[NSDictionary class]]) {
    return ALNDataverseQueryExpressionFromDictionary((NSDictionary *)node, error);
  }
  if ([node isKindOfClass:[NSArray class]]) {
    return ALNDataverseQueryExpressionFromArray((NSArray *)node, error);
  }
  if (error != NULL) {
    *error = ALNDataverseQueryMakeError(ALNDataverseQueryErrorUnsupportedPredicate,
                                        @"Dataverse predicates must be arrays or dictionaries",
                                        @{ @"node" : [node description] ?: @"" });
  }
  return nil;
}

static NSString *ALNDataverseQuerySelectList(NSArray<NSString *> *fields, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if ([fields count] == 0) {
    return @"";
  }
  NSMutableArray<NSString *> *normalized = [NSMutableArray arrayWithCapacity:[fields count]];
  for (NSString *field in fields) {
    NSString *identifier = ALNDataverseQueryFieldIdentifier(field, error);
    if ([identifier length] == 0) {
      return nil;
    }
    [normalized addObject:identifier];
  }
  return [normalized componentsJoinedByString:@","];
}

static NSString *ALNDataverseQueryOrderByString(id orderBy, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (orderBy == nil || orderBy == [NSNull null]) {
    return @"";
  }

  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  if ([orderBy isKindOfClass:[NSArray class]]) {
    for (id item in (NSArray *)orderBy) {
      if ([item isKindOfClass:[NSString class]]) {
        NSString *identifier = ALNDataverseQueryFieldIdentifier(item, error);
        if ([identifier length] == 0) {
          return nil;
        }
        [parts addObject:[NSString stringWithFormat:@"%@ asc", identifier]];
        continue;
      }
      if ([item isKindOfClass:[NSDictionary class]]) {
        if ([(NSDictionary *)item count] != 1) {
          if (error != NULL) {
            *error = ALNDataverseQueryMakeError(ALNDataverseQueryErrorInvalidArgument,
                                                @"Dataverse order_by array dictionary entries must contain exactly one key",
                                                nil);
          }
          return nil;
        }
        NSString *key = [[[item allKeys] sortedArrayUsingSelector:@selector(compare:)] firstObject];
        NSString *value = item[key];
        NSString *identifier = nil;
        NSString *direction = @"asc";
        if ([key isEqualToString:@"-desc"]) {
          identifier = ALNDataverseQueryFieldIdentifier(value, error);
          direction = @"desc";
        } else if ([key isEqualToString:@"-asc"]) {
          identifier = ALNDataverseQueryFieldIdentifier(value, error);
          direction = @"asc";
        } else {
          identifier = ALNDataverseQueryFieldIdentifier(key, error);
          direction = [[[ALNDataverseQueryTrimmedString(value) lowercaseString] isEqualToString:@"desc"] ? @"desc" : @"asc" copy];
        }
        if ([identifier length] == 0) {
          return nil;
        }
        [parts addObject:[NSString stringWithFormat:@"%@ %@", identifier, direction]];
        continue;
      }
      if (error != NULL) {
        *error = ALNDataverseQueryMakeError(ALNDataverseQueryErrorInvalidArgument,
                                            @"Dataverse order_by array items must be strings or dictionaries",
                                            nil);
      }
      return nil;
    }
    return [parts componentsJoinedByString:@","];
  }

  if ([orderBy isKindOfClass:[NSDictionary class]]) {
    NSArray<NSString *> *keys = [[(NSDictionary *)orderBy allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in keys) {
      NSString *identifier = ALNDataverseQueryFieldIdentifier(key, error);
      if ([identifier length] == 0) {
        return nil;
      }
      NSString *direction = [[[ALNDataverseQueryTrimmedString(orderBy[key]) lowercaseString] isEqualToString:@"desc"] ? @"desc" : @"asc" copy];
      [parts addObject:[NSString stringWithFormat:@"%@ %@", identifier, direction]];
    }
    return [parts componentsJoinedByString:@","];
  }

  if (error != NULL) {
    *error = ALNDataverseQueryMakeError(ALNDataverseQueryErrorInvalidArgument,
                                        @"Dataverse order_by specification must be an array or dictionary",
                                        nil);
  }
  return nil;
}

static NSString *ALNDataverseQueryExpandString(NSDictionary<NSString *, id> *expand, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (![expand isKindOfClass:[NSDictionary class]] || [expand count] == 0) {
    return @"";
  }

  NSArray<NSString *> *keys = [[expand allKeys] sortedArrayUsingSelector:@selector(compare:)];
  NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:[keys count]];
  for (NSString *navigationProperty in keys) {
    NSString *identifier = ALNDataverseQueryFieldIdentifier(navigationProperty, error);
    if ([identifier length] == 0) {
      return nil;
    }
    NSDictionary<NSString *, id> *config =
        [expand[navigationProperty] isKindOfClass:[NSDictionary class]] ? expand[navigationProperty] : nil;
    if (config == nil) {
      [parts addObject:identifier];
      continue;
    }
    NSMutableArray<NSString *> *ops = [NSMutableArray array];
    NSError *childError = nil;
    NSString *select = ALNDataverseQuerySelectList([config[@"select"] isKindOfClass:[NSArray class]] ? config[@"select"] : nil,
                                                   &childError);
    if (childError != nil) {
      if (error != NULL) {
        *error = childError;
      }
      return nil;
    }
    if ([select length] > 0) {
      [ops addObject:[NSString stringWithFormat:@"$select=%@", select]];
    }
    NSString *orderBy = ALNDataverseQueryOrderByString(config[@"order_by"], &childError);
    if (childError != nil) {
      if (error != NULL) {
        *error = childError;
      }
      return nil;
    }
    if ([orderBy length] > 0) {
      [ops addObject:[NSString stringWithFormat:@"$orderby=%@", orderBy]];
    }
    if ([config[@"top"] respondsToSelector:@selector(integerValue)]) {
      [ops addObject:[NSString stringWithFormat:@"$top=%ld", (long)[config[@"top"] integerValue]]];
    }
    if ([config[@"skip"] respondsToSelector:@selector(integerValue)]) {
      [ops addObject:[NSString stringWithFormat:@"$skip=%ld", (long)[config[@"skip"] integerValue]]];
    }
    if ([config[@"count"] respondsToSelector:@selector(boolValue)] && [config[@"count"] boolValue]) {
      [ops addObject:@"$count=true"];
    }
    NSString *innerExpand = ALNDataverseQueryExpandString(
        [config[@"expand"] isKindOfClass:[NSDictionary class]] ? config[@"expand"] : nil,
        &childError);
    if (childError != nil) {
      if (error != NULL) {
        *error = childError;
      }
      return nil;
    }
    if ([innerExpand length] > 0) {
      [ops addObject:[NSString stringWithFormat:@"$expand=%@", innerExpand]];
    }
    NSString *suffix = ([ops count] > 0) ? [NSString stringWithFormat:@"(%@)", [ops componentsJoinedByString:@";"]] : @"";
    [parts addObject:[identifier stringByAppendingString:suffix]];
  }
  return [parts componentsJoinedByString:@","];
}

@interface ALNDataverseQuery ()
@property(nonatomic, copy, readwrite) NSString *entitySetName;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *selectFields;
@property(nonatomic, strong, readwrite) id predicate;
@property(nonatomic, strong, readwrite) id orderBy;
@property(nonatomic, copy, readwrite) NSNumber *top;
@property(nonatomic, copy, readwrite) NSNumber *skip;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, id> *expand;
@property(nonatomic, assign, readwrite) BOOL includeCount;
@property(nonatomic, assign, readwrite) BOOL includeFormattedValues;
@end

@implementation ALNDataverseQuery

- (instancetype)init {
  [NSException raise:NSInvalidArgumentException format:@"Use -initWithEntitySetName:error:"];
  return nil;
}

+ (instancetype)queryWithEntitySetName:(NSString *)entitySetName error:(NSError **)error {
  return [[self alloc] initWithEntitySetName:entitySetName error:error];
}

+ (NSString *)filterStringFromPredicate:(id)predicate error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *expression = ALNDataverseQueryExpressionFromNode(predicate, error);
  if ([expression hasPrefix:@"("] && [expression hasSuffix:@")"] && [expression length] > 2) {
    return [expression substringWithRange:NSMakeRange(1, [expression length] - 2)];
  }
  return expression;
}

+ (NSString *)orderByStringFromSpec:(id)orderBy error:(NSError **)error {
  return ALNDataverseQueryOrderByString(orderBy, error);
}

+ (NSString *)expandStringFromSpec:(NSDictionary<NSString *, id> *)expand error:(NSError **)error {
  return ALNDataverseQueryExpandString(expand, error);
}

+ (NSDictionary<NSString *, NSString *> *)queryParametersWithSelectFields:(NSArray<NSString *> *)selectFields
                                                                    where:(id)predicate
                                                                  orderBy:(id)orderBy
                                                                      top:(NSNumber *)top
                                                                     skip:(NSNumber *)skip
                                                                countFlag:(BOOL)countFlag
                                                                   expand:(NSDictionary<NSString *, id> *)expand
                                                                    error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSMutableDictionary<NSString *, NSString *> *parameters = [NSMutableDictionary dictionary];
  NSError *childError = nil;
  NSString *selectList = ALNDataverseQuerySelectList(selectFields, &childError);
  if (childError != nil) {
    if (error != NULL) {
      *error = childError;
    }
    return nil;
  }
  if ([selectList length] > 0) {
    parameters[@"$select"] = selectList;
  }
  NSString *filter = [self filterStringFromPredicate:predicate error:&childError];
  if (childError != nil) {
    if (error != NULL) {
      *error = childError;
    }
    return nil;
  }
  if ([filter length] > 0) {
    parameters[@"$filter"] = filter;
  }
  NSString *orderString = [self orderByStringFromSpec:orderBy error:&childError];
  if (childError != nil) {
    if (error != NULL) {
      *error = childError;
    }
    return nil;
  }
  if ([orderString length] > 0) {
    parameters[@"$orderby"] = orderString;
  }
  if ([top respondsToSelector:@selector(integerValue)]) {
    parameters[@"$top"] = [NSString stringWithFormat:@"%ld", (long)[top integerValue]];
  }
  if ([skip respondsToSelector:@selector(integerValue)]) {
    parameters[@"$skip"] = [NSString stringWithFormat:@"%ld", (long)[skip integerValue]];
  }
  if (countFlag) {
    parameters[@"$count"] = @"true";
  }
  NSString *expandString = [self expandStringFromSpec:expand error:&childError];
  if (childError != nil) {
    if (error != NULL) {
      *error = childError;
    }
    return nil;
  }
  if ([expandString length] > 0) {
    parameters[@"$expand"] = expandString;
  }
  return [parameters copy];
}

- (instancetype)initWithEntitySetName:(NSString *)entitySetName error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSString *identifier = ALNDataverseQueryFieldIdentifier(entitySetName, error);
  if ([identifier length] == 0) {
    return nil;
  }
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _entitySetName = [identifier copy];
  _selectFields = @[];
  _includeFormattedValues = YES;
  _includeCount = NO;
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  NSError *error = nil;
  ALNDataverseQuery *copy = [[[self class] allocWithZone:zone] initWithEntitySetName:self.entitySetName
                                                                                error:&error];
  NSCAssert(copy != nil && error == nil, @"Dataverse query copy must succeed");
  copy.selectFields = self.selectFields;
  copy.predicate = self.predicate;
  copy.orderBy = self.orderBy;
  copy.top = self.top;
  copy.skip = self.skip;
  copy.expand = self.expand;
  copy.includeCount = self.includeCount;
  copy.includeFormattedValues = self.includeFormattedValues;
  return copy;
}

- (ALNDataverseQuery *)queryBySettingSelectFields:(NSArray<NSString *> *)selectFields {
  ALNDataverseQuery *copy = [self copy];
  copy.selectFields = [selectFields copy] ?: @[];
  return copy;
}

- (ALNDataverseQuery *)queryBySettingPredicate:(id)predicate {
  ALNDataverseQuery *copy = [self copy];
  copy.predicate = predicate;
  return copy;
}

- (ALNDataverseQuery *)queryBySettingOrderBy:(id)orderBy {
  ALNDataverseQuery *copy = [self copy];
  copy.orderBy = orderBy;
  return copy;
}

- (ALNDataverseQuery *)queryBySettingTop:(NSNumber *)top {
  ALNDataverseQuery *copy = [self copy];
  copy.top = [top copy];
  return copy;
}

- (ALNDataverseQuery *)queryBySettingSkip:(NSNumber *)skip {
  ALNDataverseQuery *copy = [self copy];
  copy.skip = [skip copy];
  return copy;
}

- (ALNDataverseQuery *)queryBySettingExpand:(NSDictionary<NSString *,id> *)expand {
  ALNDataverseQuery *copy = [self copy];
  copy.expand = [expand copy];
  return copy;
}

- (ALNDataverseQuery *)queryBySettingIncludeCount:(BOOL)includeCount {
  ALNDataverseQuery *copy = [self copy];
  copy.includeCount = includeCount;
  return copy;
}

- (ALNDataverseQuery *)queryBySettingIncludeFormattedValues:(BOOL)includeFormattedValues {
  ALNDataverseQuery *copy = [self copy];
  copy.includeFormattedValues = includeFormattedValues;
  return copy;
}

- (NSDictionary<NSString *, NSString *> *)queryParameters:(NSError **)error {
  return [[self class] queryParametersWithSelectFields:self.selectFields
                                                 where:self.predicate
                                               orderBy:self.orderBy
                                                   top:self.top
                                                  skip:self.skip
                                             countFlag:self.includeCount
                                                expand:self.expand
                                                 error:error];
}

@end

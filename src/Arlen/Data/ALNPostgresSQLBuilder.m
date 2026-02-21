#import "ALNPostgresSQLBuilder.h"

static BOOL ALNPostgresSQLBuilderIdentifierIsSafe(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return NO;
  }
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
  if ([[value stringByTrimmingCharactersInSet:allowed] length] > 0) {
    return NO;
  }
  unichar first = [value characterAtIndex:0];
  BOOL validStart = [[NSCharacterSet letterCharacterSet] characterIsMember:first] || first == '_';
  return validStart;
}

static NSString *ALNPostgresSQLBuilderQuoteIdentifier(NSString *value) {
  return [NSString stringWithFormat:@"\"%@\"", value ?: @""];
}

static NSString *ALNPostgresSQLBuilderTrimmedString(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *ALNPostgresSQLBuilderShiftPlaceholders(NSString *sql, NSUInteger offset) {
  if ([sql length] == 0 || offset == 0) {
    return sql ?: @"";
  }

  NSError *regexError = nil;
  NSRegularExpression *regex =
      [NSRegularExpression regularExpressionWithPattern:@"\\$([0-9]+)"
                                                options:0
                                                  error:&regexError];
  if (regex == nil || regexError != nil) {
    return sql;
  }

  NSArray *matches = [regex matchesInString:sql options:0 range:NSMakeRange(0, [sql length])];
  if ([matches count] == 0) {
    return sql;
  }

  NSMutableString *rewritten = [NSMutableString stringWithCapacity:[sql length] + 16];
  NSUInteger cursor = 0;
  for (NSTextCheckingResult *match in matches) {
    NSRange fullRange = [match rangeAtIndex:0];
    NSRange indexRange = [match rangeAtIndex:1];
    if (fullRange.location > cursor) {
      [rewritten appendString:[sql substringWithRange:NSMakeRange(cursor,
                                                                  fullRange.location - cursor)]];
    }
    NSInteger original = [[sql substringWithRange:indexRange] integerValue];
    NSInteger shifted = original + (NSInteger)offset;
    [rewritten appendFormat:@"$%ld", (long)shifted];
    cursor = NSMaxRange(fullRange);
  }

  if (cursor < [sql length]) {
    [rewritten appendString:[sql substringFromIndex:cursor]];
  }

  return rewritten;
}

typedef NS_ENUM(NSInteger, ALNPostgresSQLBuilderConflictMode) {
  ALNPostgresSQLBuilderConflictModeNone = 0,
  ALNPostgresSQLBuilderConflictModeDoNothing = 1,
  ALNPostgresSQLBuilderConflictModeDoUpdate = 2,
};

@interface ALNPostgresSQLBuilder ()

@property(nonatomic, assign) ALNPostgresSQLBuilderConflictMode conflictMode;
@property(nonatomic, copy) NSArray<NSString *> *conflictColumns;
@property(nonatomic, copy) NSArray<NSString *> *conflictUpdateFields;
@property(nonatomic, copy) NSDictionary<NSString *, id> *conflictUpdateAssignments;
@property(nonatomic, copy) NSString *conflictDoUpdateWhereExpression;
@property(nonatomic, copy) NSArray *conflictDoUpdateWhereParameters;

@end

@implementation ALNPostgresSQLBuilder

- (instancetype)init {
  self = [super init];
  if (self) {
    _conflictMode = ALNPostgresSQLBuilderConflictModeNone;
    _conflictColumns = @[];
    _conflictUpdateFields = @[];
    _conflictUpdateAssignments = @{};
    _conflictDoUpdateWhereExpression = @"";
    _conflictDoUpdateWhereParameters = @[];
  }
  return self;
}

- (instancetype)onConflictDoNothing {
  self.conflictMode = ALNPostgresSQLBuilderConflictModeDoNothing;
  self.conflictColumns = @[];
  self.conflictUpdateFields = @[];
  self.conflictUpdateAssignments = @{};
  self.conflictDoUpdateWhereExpression = @"";
  self.conflictDoUpdateWhereParameters = @[];
  return self;
}

- (instancetype)onConflictColumns:(NSArray<NSString *> *)columns
                doUpdateSetFields:(NSArray<NSString *> *)fields {
  self.conflictMode = ALNPostgresSQLBuilderConflictModeDoUpdate;
  self.conflictColumns = [columns copy] ?: @[];
  self.conflictUpdateFields = [fields copy] ?: @[];
  self.conflictUpdateAssignments = @{};
  return self;
}

- (instancetype)onConflictColumns:(NSArray<NSString *> *)columns
             doUpdateAssignments:(NSDictionary<NSString *,id> *)assignments {
  self.conflictMode = ALNPostgresSQLBuilderConflictModeDoUpdate;
  self.conflictColumns = [columns copy] ?: @[];
  self.conflictUpdateFields = @[];
  self.conflictUpdateAssignments = [assignments copy] ?: @{};
  return self;
}

- (instancetype)onConflictDoUpdateWhereExpression:(NSString *)expression
                                       parameters:(NSArray *)parameters {
  self.conflictDoUpdateWhereExpression = expression ?: @"";
  self.conflictDoUpdateWhereParameters = parameters ?: @[];
  return self;
}

- (nullable NSString *)compileConflictTarget:(NSError **)error {
  if ([self.conflictColumns count] == 0) {
    return @"";
  }

  NSMutableArray *columns = [NSMutableArray arrayWithCapacity:[self.conflictColumns count]];
  for (NSString *column in self.conflictColumns) {
    if (!ALNPostgresSQLBuilderIdentifierIsSafe(column)) {
      if (error != NULL) {
        *error = [NSError errorWithDomain:ALNSQLBuilderErrorDomain
                                     code:ALNSQLBuilderErrorInvalidIdentifier
                                 userInfo:@{
                                   NSLocalizedDescriptionKey : @"invalid conflict target column",
                                   @"identifier" : column ?: @"",
                                 }];
      }
      return nil;
    }
    [columns addObject:ALNPostgresSQLBuilderQuoteIdentifier(column)];
  }

  return [NSString stringWithFormat:@" (%@)", [columns componentsJoinedByString:@", "]];
}

- (nullable NSString *)compileTrustedExpression:(id)expressionValue
                                     parameters:(id)rawParameters
                                  intoParameters:(NSMutableArray *)parameters
                                         context:(NSString *)context
                                           error:(NSError **)error {
  NSString *expression = ALNPostgresSQLBuilderTrimmedString(expressionValue);
  if ([expression length] == 0) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNSQLBuilderErrorDomain
                                   code:ALNSQLBuilderErrorInvalidArgument
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"expression must not be empty",
                                 @"identifier" : context ?: @"",
                               }];
    }
    return nil;
  }

  NSArray *expressionParameters =
      [rawParameters isKindOfClass:[NSArray class]] ? rawParameters : @[];
  NSUInteger placeholderOffset = [parameters count];
  for (id value in expressionParameters) {
    [parameters addObject:value ?: [NSNull null]];
  }
  return ALNPostgresSQLBuilderShiftPlaceholders(expression, placeholderOffset);
}

- (nullable NSString *)compileConflictClauseWithParameters:(NSMutableArray *)parameters
                                                     error:(NSError **)error {
  if (self.conflictMode == ALNPostgresSQLBuilderConflictModeNone) {
    if ([ALNPostgresSQLBuilderTrimmedString(self.conflictDoUpdateWhereExpression) length] > 0) {
      if (error != NULL) {
        *error = [NSError errorWithDomain:ALNSQLBuilderErrorDomain
                                     code:ALNSQLBuilderErrorInvalidArgument
                                 userInfo:@{
                                   NSLocalizedDescriptionKey :
                                       @"ON CONFLICT DO UPDATE WHERE requires conflict update mode"
                                 }];
      }
      return nil;
    }
    return @"";
  }

  if (self.kind != ALNSQLBuilderKindInsert) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNSQLBuilderErrorDomain
                                   code:ALNSQLBuilderErrorInvalidArgument
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"ON CONFLICT is only valid for insert builders"
                               }];
    }
    return nil;
  }

  NSString *target = [self compileConflictTarget:error];
  if (target == nil) {
    return nil;
  }

  if (self.conflictMode == ALNPostgresSQLBuilderConflictModeDoNothing) {
    if ([ALNPostgresSQLBuilderTrimmedString(self.conflictDoUpdateWhereExpression) length] > 0) {
      if (error != NULL) {
        *error = [NSError errorWithDomain:ALNSQLBuilderErrorDomain
                                     code:ALNSQLBuilderErrorInvalidArgument
                                 userInfo:@{
                                   NSLocalizedDescriptionKey :
                                       @"ON CONFLICT DO UPDATE WHERE is invalid with DO NOTHING"
                                 }];
      }
      return nil;
    }
    return [NSString stringWithFormat:@" ON CONFLICT%@ DO NOTHING", target];
  }

  if ([self.conflictUpdateFields count] == 0 && [self.conflictUpdateAssignments count] == 0) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNSQLBuilderErrorDomain
                                   code:ALNSQLBuilderErrorInvalidArgument
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"conflict update requires at least one assignment"
                               }];
    }
    return nil;
  }

  NSMutableArray *assignments = [NSMutableArray array];
  for (NSString *field in self.conflictUpdateFields) {
    if (!ALNPostgresSQLBuilderIdentifierIsSafe(field)) {
      if (error != NULL) {
        *error = [NSError errorWithDomain:ALNSQLBuilderErrorDomain
                                     code:ALNSQLBuilderErrorInvalidIdentifier
                                 userInfo:@{
                                   NSLocalizedDescriptionKey : @"invalid conflict update field",
                                   @"identifier" : field ?: @"",
                                 }];
      }
      return nil;
    }
    NSString *quoted = ALNPostgresSQLBuilderQuoteIdentifier(field);
    [assignments addObject:[NSString stringWithFormat:@"%@ = EXCLUDED.%@", quoted, quoted]];
  }

  NSArray *assignmentFields = [[self.conflictUpdateAssignments allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *field in assignmentFields) {
    if (!ALNPostgresSQLBuilderIdentifierIsSafe(field)) {
      if (error != NULL) {
        *error = [NSError errorWithDomain:ALNSQLBuilderErrorDomain
                                     code:ALNSQLBuilderErrorInvalidIdentifier
                                 userInfo:@{
                                   NSLocalizedDescriptionKey : @"invalid conflict assignment field",
                                   @"identifier" : field ?: @"",
                                 }];
      }
      return nil;
    }

    id rawAssignment = self.conflictUpdateAssignments[field];
    NSString *expression = nil;
    NSArray *expressionParameters = @[];
    if ([rawAssignment isKindOfClass:[NSString class]]) {
      expression = rawAssignment;
    } else if ([rawAssignment isKindOfClass:[NSDictionary class]]) {
      NSDictionary *assignment = rawAssignment;
      expression = [assignment[@"expression"] isKindOfClass:[NSString class]]
                       ? assignment[@"expression"]
                       : nil;
      expressionParameters = [assignment[@"parameters"] isKindOfClass:[NSArray class]]
                                 ? assignment[@"parameters"]
                                 : @[];
    } else {
      if (error != NULL) {
        *error = [NSError errorWithDomain:ALNSQLBuilderErrorDomain
                                     code:ALNSQLBuilderErrorInvalidArgument
                                 userInfo:@{
                                   NSLocalizedDescriptionKey :
                                       @"conflict assignment value must be a string or expression dictionary",
                                   @"identifier" : field ?: @"",
                                 }];
      }
      return nil;
    }

    NSString *compiledExpression = [self compileTrustedExpression:expression
                                                       parameters:expressionParameters
                                                    intoParameters:parameters
                                                           context:field
                                                             error:error];
    if (compiledExpression == nil) {
      return nil;
    }

    NSString *quoted = ALNPostgresSQLBuilderQuoteIdentifier(field);
    [assignments addObject:[NSString stringWithFormat:@"%@ = %@", quoted, compiledExpression]];
  }

  NSString *clause = [NSString stringWithFormat:@" ON CONFLICT%@ DO UPDATE SET %@",
                                                target,
                                                [assignments componentsJoinedByString:@", "]];
  if ([ALNPostgresSQLBuilderTrimmedString(self.conflictDoUpdateWhereExpression) length] > 0) {
    NSString *whereExpression = [self compileTrustedExpression:self.conflictDoUpdateWhereExpression
                                                    parameters:self.conflictDoUpdateWhereParameters
                                                 intoParameters:parameters
                                                        context:@"on conflict do update where"
                                                          error:error];
    if (whereExpression == nil) {
      return nil;
    }
    clause = [clause stringByAppendingFormat:@" WHERE %@", whereExpression];
  }

  return clause;
}

- (NSDictionary *)build:(NSError **)error {
  NSDictionary *base = [super build:error];
  if (base == nil) {
    return nil;
  }

  NSString *sql = [base[@"sql"] isKindOfClass:[NSString class]] ? base[@"sql"] : @"";
  NSArray *baseParameters = [base[@"parameters"] isKindOfClass:[NSArray class]] ? base[@"parameters"] : @[];
  NSMutableArray *parameters = [NSMutableArray arrayWithArray:baseParameters];

  NSString *conflictClause = [self compileConflictClauseWithParameters:parameters error:error];
  if (conflictClause == nil) {
    return nil;
  }
  if ([conflictClause length] == 0) {
    return base;
  }

  NSRange returningRange = [sql rangeOfString:@" RETURNING " options:NSBackwardsSearch];
  NSString *rewritten = nil;
  if (returningRange.location != NSNotFound) {
    NSString *prefix = [sql substringToIndex:returningRange.location];
    NSString *suffix = [sql substringFromIndex:returningRange.location];
    rewritten = [NSString stringWithFormat:@"%@%@%@", prefix, conflictClause, suffix];
  } else {
    rewritten = [sql stringByAppendingString:conflictClause];
  }

  return @{
    @"sql" : rewritten ?: @"",
    @"parameters" : [NSArray arrayWithArray:parameters],
  };
}

@end

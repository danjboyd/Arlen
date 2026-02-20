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

typedef NS_ENUM(NSInteger, ALNPostgresSQLBuilderConflictMode) {
  ALNPostgresSQLBuilderConflictModeNone = 0,
  ALNPostgresSQLBuilderConflictModeDoNothing = 1,
  ALNPostgresSQLBuilderConflictModeDoUpdate = 2,
};

@interface ALNPostgresSQLBuilder ()

@property(nonatomic, assign) ALNPostgresSQLBuilderConflictMode conflictMode;
@property(nonatomic, copy) NSArray<NSString *> *conflictColumns;
@property(nonatomic, copy) NSArray<NSString *> *conflictUpdateFields;

@end

@implementation ALNPostgresSQLBuilder

- (instancetype)init {
  self = [super init];
  if (self) {
    _conflictMode = ALNPostgresSQLBuilderConflictModeNone;
    _conflictColumns = @[];
    _conflictUpdateFields = @[];
  }
  return self;
}

- (instancetype)onConflictDoNothing {
  self.conflictMode = ALNPostgresSQLBuilderConflictModeDoNothing;
  self.conflictColumns = @[];
  self.conflictUpdateFields = @[];
  return self;
}

- (instancetype)onConflictColumns:(NSArray<NSString *> *)columns
                doUpdateSetFields:(NSArray<NSString *> *)fields {
  self.conflictMode = ALNPostgresSQLBuilderConflictModeDoUpdate;
  self.conflictColumns = [columns copy] ?: @[];
  self.conflictUpdateFields = [fields copy] ?: @[];
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

- (nullable NSString *)compileConflictClause:(NSError **)error {
  if (self.conflictMode == ALNPostgresSQLBuilderConflictModeNone) {
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
    return [NSString stringWithFormat:@" ON CONFLICT%@ DO NOTHING", target];
  }

  if ([self.conflictUpdateFields count] == 0) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNSQLBuilderErrorDomain
                                   code:ALNSQLBuilderErrorInvalidArgument
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"onConflictColumns:doUpdateSetFields: requires at least one update field"
                               }];
    }
    return nil;
  }

  NSMutableArray *assignments = [NSMutableArray arrayWithCapacity:[self.conflictUpdateFields count]];
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

  return [NSString stringWithFormat:@" ON CONFLICT%@ DO UPDATE SET %@",
                                    target,
                                    [assignments componentsJoinedByString:@", "]];
}

- (NSDictionary *)build:(NSError **)error {
  NSDictionary *base = [super build:error];
  if (base == nil) {
    return nil;
  }

  NSString *conflictClause = [self compileConflictClause:error];
  if (conflictClause == nil) {
    return nil;
  }
  if ([conflictClause length] == 0) {
    return base;
  }

  NSString *sql = [base[@"sql"] isKindOfClass:[NSString class]] ? base[@"sql"] : @"";
  NSArray *parameters = [base[@"parameters"] isKindOfClass:[NSArray class]] ? base[@"parameters"] : @[];

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
    @"parameters" : parameters,
  };
}

@end

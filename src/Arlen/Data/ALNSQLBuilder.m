#import "ALNSQLBuilder.h"

NSString *const ALNSQLBuilderErrorDomain = @"Arlen.Data.SQLBuilder.Error";

static NSError *ALNSQLBuilderMakeError(ALNSQLBuilderErrorCode code,
                                       NSString *message,
                                       NSString *identifier) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"sql builder error";
  if ([identifier length] > 0) {
    userInfo[@"identifier"] = identifier;
  }
  return [NSError errorWithDomain:ALNSQLBuilderErrorDomain code:code userInfo:userInfo];
}

static NSString *ALNSQLBuilderNormalizeOperator(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  NSString *trimmed = [[value uppercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0) {
    return @"";
  }

  NSArray *parts = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSMutableArray *tokens = [NSMutableArray arrayWithCapacity:[parts count]];
  for (NSString *part in parts) {
    if ([part length] > 0) {
      [tokens addObject:part];
    }
  }
  return [tokens componentsJoinedByString:@" "];
}

static NSString *ALNSQLBuilderTrimmedString(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *ALNSQLBuilderNormalizeNullsDirective(NSString *value) {
  NSString *normalized = ALNSQLBuilderNormalizeOperator(value);
  if ([normalized isEqualToString:@"FIRST"] || [normalized isEqualToString:@"NULLS FIRST"]) {
    return @"NULLS FIRST";
  }
  if ([normalized isEqualToString:@"LAST"] || [normalized isEqualToString:@"NULLS LAST"]) {
    return @"NULLS LAST";
  }
  return @"";
}

static BOOL ALNSQLBuilderIdentifierIsSafe(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return NO;
  }
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_."];
  if ([[value stringByTrimmingCharactersInSet:allowed] length] > 0) {
    return NO;
  }
  NSArray *parts = [value componentsSeparatedByString:@"."];
  for (NSString *part in parts) {
    if ([part length] == 0) {
      return NO;
    }
    unichar first = [part characterAtIndex:0];
    BOOL validStart = [[NSCharacterSet letterCharacterSet] characterIsMember:first] || first == '_';
    if (!validStart) {
      return NO;
    }
  }
  return YES;
}

static BOOL ALNSQLBuilderAliasIsSafe(NSString *value) {
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

static NSString *ALNSQLBuilderQuoteIdentifier(NSString *value) {
  NSArray *parts = [value componentsSeparatedByString:@"."];
  NSMutableArray *quoted = [NSMutableArray arrayWithCapacity:[parts count]];
  for (NSString *part in parts) {
    [quoted addObject:[NSString stringWithFormat:@"\"%@\"", part]];
  }
  return [quoted componentsJoinedByString:@"."];
}

static NSString *ALNSQLBuilderQuoteIdentifierOrWildcard(NSString *value) {
  if ([value isEqualToString:@"*"]) {
    return @"*";
  }
  if ([value hasSuffix:@".*"]) {
    NSString *prefix = [value substringToIndex:([value length] - 2)];
    if (ALNSQLBuilderIdentifierIsSafe(prefix)) {
      return [NSString stringWithFormat:@"%@.*", ALNSQLBuilderQuoteIdentifier(prefix)];
    }
  }
  if (ALNSQLBuilderIdentifierIsSafe(value)) {
    return ALNSQLBuilderQuoteIdentifier(value);
  }
  return nil;
}

static NSString *ALNSQLBuilderBuildTableReference(NSString *tableName,
                                                  NSString *alias,
                                                  NSError **error) {
  if (!ALNSQLBuilderIdentifierIsSafe(tableName)) {
    if (error != NULL) {
      *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                      @"invalid table name",
                                      tableName);
    }
    return nil;
  }
  NSString *quotedTable = ALNSQLBuilderQuoteIdentifier(tableName);
  if ([alias length] == 0) {
    return quotedTable;
  }
  if (!ALNSQLBuilderAliasIsSafe(alias)) {
    if (error != NULL) {
      *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                      @"invalid table alias",
                                      alias);
    }
    return nil;
  }
  return [NSString stringWithFormat:@"%@ AS \"%@\"", quotedTable, alias];
}

static NSArray *ALNSQLBuilderSortedDictionaryKeys(NSDictionary *dictionary) {
  NSArray *keys = [dictionary allKeys];
  return [keys sortedArrayUsingSelector:@selector(compare:)];
}

static NSString *ALNSQLBuilderShiftPlaceholders(NSString *sql, NSUInteger offset) {
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

static BOOL ALNSQLBuilderExpressionTokenIsSafe(NSString *value) {
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

static NSRegularExpression *ALNSQLBuilderPlaceholderRegex(void) {
  static NSRegularExpression *regex = nil;
  if (regex == nil) {
    regex = [NSRegularExpression regularExpressionWithPattern:@"\\$([0-9]+)"
                                                      options:0
                                                        error:nil];
  }
  return regex;
}

static NSRegularExpression *ALNSQLBuilderIdentifierTokenRegex(void) {
  static NSRegularExpression *regex = nil;
  if (regex == nil) {
    regex = [NSRegularExpression regularExpressionWithPattern:@"\\{\\{([A-Za-z_][A-Za-z0-9_]*)\\}\\}"
                                                      options:0
                                                        error:nil];
  }
  return regex;
}

static NSDictionary *ALNSQLBuilderMakeExpressionIR(NSString *expression,
                                                   NSArray *parameters,
                                                   NSDictionary *identifierBindings) {
  return @{
    @"kind" : @"trusted-template-v1",
    @"template" : expression ?: @"",
    @"parameters" : parameters ?: @[],
    @"identifierBindings" : identifierBindings ?: @{},
  };
}

static NSSet *ALNSQLBuilderAllowedComparisonOperators(void) {
  static NSSet *operators = nil;
  if (operators == nil) {
    operators = [NSSet setWithArray:@[
      @"=",
      @"!=",
      @"<>",
      @">",
      @"<",
      @">=",
      @"<=",
      @"LIKE",
      @"ILIKE",
      @"NOT LIKE",
      @"NOT ILIKE",
      @"IS DISTINCT FROM",
      @"IS NOT DISTINCT FROM",
    ]];
  }
  return operators;
}

static NSSet *ALNSQLBuilderAllowedJoinOperators(void) {
  static NSSet *operators = nil;
  if (operators == nil) {
    operators = [NSSet setWithArray:@[
      @"=",
      @"!=",
      @"<>",
      @">",
      @"<",
      @">=",
      @"<=",
    ]];
  }
  return operators;
}

@interface ALNSQLBuilder ()

@property(nonatomic, assign, readwrite) ALNSQLBuilderKind kind;
@property(nonatomic, copy, readwrite) NSString *tableName;
@property(nonatomic, copy) NSString *tableAlias;
@property(nonatomic, copy) NSArray *selectColumns;
@property(nonatomic, copy) NSDictionary *values;
@property(nonatomic, strong) NSMutableArray *whereClauses;
@property(nonatomic, strong) NSMutableArray *havingClauses;
@property(nonatomic, strong) NSMutableArray *orderByClauses;
@property(nonatomic, strong) NSMutableArray *joins;
@property(nonatomic, strong) NSMutableArray *groupByFields;
@property(nonatomic, strong) NSMutableArray *ctes;
@property(nonatomic, strong) NSMutableArray *returningColumns;
@property(nonatomic, assign) NSUInteger limitValue;
@property(nonatomic, assign) NSUInteger offsetValue;
@property(nonatomic, assign) BOOL hasLimit;
@property(nonatomic, assign) BOOL hasOffset;

@end

@implementation ALNSQLBuilder

+ (instancetype)selectFrom:(NSString *)tableName
                   columns:(NSArray<NSString *> *)columns {
  return [self selectFrom:tableName alias:nil columns:columns];
}

+ (instancetype)selectFrom:(NSString *)tableName
                     alias:(NSString *)alias
                   columns:(NSArray<NSString *> *)columns {
  ALNSQLBuilder *builder = [[self alloc] init];
  builder.kind = ALNSQLBuilderKindSelect;
  builder.tableName = [tableName copy] ?: @"";
  builder.tableAlias = [alias copy] ?: @"";
  builder.selectColumns = ([columns count] > 0) ? [columns copy] : @[ @"*" ];
  return builder;
}

+ (instancetype)insertInto:(NSString *)tableName
                    values:(NSDictionary<NSString *,id> *)values {
  ALNSQLBuilder *builder = [[self alloc] init];
  builder.kind = ALNSQLBuilderKindInsert;
  builder.tableName = [tableName copy] ?: @"";
  builder.values = [values copy] ?: @{};
  return builder;
}

+ (instancetype)updateTable:(NSString *)tableName
                     values:(NSDictionary<NSString *,id> *)values {
  ALNSQLBuilder *builder = [[self alloc] init];
  builder.kind = ALNSQLBuilderKindUpdate;
  builder.tableName = [tableName copy] ?: @"";
  builder.values = [values copy] ?: @{};
  return builder;
}

+ (instancetype)deleteFrom:(NSString *)tableName {
  ALNSQLBuilder *builder = [[self alloc] init];
  builder.kind = ALNSQLBuilderKindDelete;
  builder.tableName = [tableName copy] ?: @"";
  return builder;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _tableAlias = @"";
    _selectColumns = @[ @"*" ];
    _values = @{};
    _whereClauses = [NSMutableArray array];
    _havingClauses = [NSMutableArray array];
    _orderByClauses = [NSMutableArray array];
    _joins = [NSMutableArray array];
    _groupByFields = [NSMutableArray array];
    _ctes = [NSMutableArray array];
    _returningColumns = [NSMutableArray array];
    _hasLimit = NO;
    _hasOffset = NO;
  }
  return self;
}

- (instancetype)fromAlias:(NSString *)alias {
  self.tableAlias = [alias copy] ?: @"";
  return self;
}

- (instancetype)selectExpression:(NSString *)expression alias:(NSString *)alias {
  return [self selectExpression:expression
                          alias:alias
             identifierBindings:nil
                     parameters:nil];
}

- (instancetype)selectExpression:(NSString *)expression
                           alias:(NSString *)alias
                      parameters:(NSArray *)parameters {
  return [self selectExpression:expression
                          alias:alias
             identifierBindings:nil
                     parameters:parameters];
}

- (instancetype)selectExpression:(NSString *)expression
                           alias:(NSString *)alias
              identifierBindings:(NSDictionary<NSString *, NSString *> *)identifierBindings
                      parameters:(NSArray *)parameters {
  NSMutableArray *columns = [NSMutableArray arrayWithArray:self.selectColumns ?: @[]];
  [columns addObject:@{
    @"kind" : @"expression",
    @"expressionIR" : ALNSQLBuilderMakeExpressionIR(expression, parameters, identifierBindings),
    @"alias" : alias ?: @"",
  }];
  self.selectColumns = [NSArray arrayWithArray:columns];
  return self;
}

- (instancetype)whereField:(NSString *)field equals:(id)value {
  return [self whereField:field operator:@"=" value:value];
}

- (instancetype)whereField:(NSString *)field
                  operator:(NSString *)operatorName
                     value:(id)value {
  NSString *normalized = ALNSQLBuilderNormalizeOperator(operatorName ?: @"=");
  [self.whereClauses addObject:@{
    @"field" : field ?: @"",
    @"operator" : ([normalized length] > 0 ? normalized : @"="),
    @"value" : value ?: [NSNull null],
    @"kind" : @"operator"
  }];
  return self;
}

- (instancetype)whereExpression:(NSString *)expression
                     parameters:(NSArray *)parameters {
  return [self whereExpression:expression
            identifierBindings:nil
                    parameters:parameters];
}

- (instancetype)whereExpression:(NSString *)expression
             identifierBindings:(NSDictionary<NSString *, NSString *> *)identifierBindings
                     parameters:(NSArray *)parameters {
  [self.whereClauses addObject:@{
    @"kind" : @"expression",
    @"expressionIR" : ALNSQLBuilderMakeExpressionIR(expression, parameters, identifierBindings),
  }];
  return self;
}

- (instancetype)whereFieldIn:(NSString *)field
                      values:(NSArray *)values {
  [self.whereClauses addObject:@{
    @"field" : field ?: @"",
    @"values" : values ?: @[],
    @"kind" : @"in"
  }];
  return self;
}

- (instancetype)whereFieldNotIn:(NSString *)field
                         values:(NSArray *)values {
  [self.whereClauses addObject:@{
    @"field" : field ?: @"",
    @"values" : values ?: @[],
    @"kind" : @"not-in"
  }];
  return self;
}

- (instancetype)whereField:(NSString *)field
              betweenLower:(id)lower
                     upper:(id)upper {
  [self.whereClauses addObject:@{
    @"field" : field ?: @"",
    @"lower" : lower ?: [NSNull null],
    @"upper" : upper ?: [NSNull null],
    @"kind" : @"between"
  }];
  return self;
}

- (instancetype)whereField:(NSString *)field
           notBetweenLower:(id)lower
                     upper:(id)upper {
  [self.whereClauses addObject:@{
    @"field" : field ?: @"",
    @"lower" : lower ?: [NSNull null],
    @"upper" : upper ?: [NSNull null],
    @"kind" : @"not-between"
  }];
  return self;
}

- (instancetype)whereField:(NSString *)field
                inSubquery:(ALNSQLBuilder *)subquery {
  [self.whereClauses addObject:@{
    @"field" : field ?: @"",
    @"query" : subquery ?: [NSNull null],
    @"kind" : @"subquery-in"
  }];
  return self;
}

- (instancetype)whereField:(NSString *)field
             notInSubquery:(ALNSQLBuilder *)subquery {
  [self.whereClauses addObject:@{
    @"field" : field ?: @"",
    @"query" : subquery ?: [NSNull null],
    @"kind" : @"subquery-not-in"
  }];
  return self;
}

- (instancetype)whereAnyGroup:(ALNSQLBuilderGroupBlock)groupBlock {
  ALNSQLBuilder *groupBuilder = [[ALNSQLBuilder alloc] init];
  if (groupBlock != nil) {
    groupBlock(groupBuilder);
  }
  if ([groupBuilder.whereClauses count] == 0) {
    return self;
  }
  [self.whereClauses addObject:@{
    @"kind" : @"group",
    @"conjunction" : @"OR",
    @"clauses" : [NSArray arrayWithArray:groupBuilder.whereClauses]
  }];
  return self;
}

- (instancetype)whereAllGroup:(ALNSQLBuilderGroupBlock)groupBlock {
  ALNSQLBuilder *groupBuilder = [[ALNSQLBuilder alloc] init];
  if (groupBlock != nil) {
    groupBlock(groupBuilder);
  }
  if ([groupBuilder.whereClauses count] == 0) {
    return self;
  }
  [self.whereClauses addObject:@{
    @"kind" : @"group",
    @"conjunction" : @"AND",
    @"clauses" : [NSArray arrayWithArray:groupBuilder.whereClauses]
  }];
  return self;
}

- (instancetype)joinTable:(NSString *)tableName
                    alias:(NSString *)alias
              onLeftField:(NSString *)leftField
                 operator:(NSString *)operatorName
             onRightField:(NSString *)rightField {
  NSString *normalized = ALNSQLBuilderNormalizeOperator(operatorName ?: @"=");
  [self.joins addObject:@{
    @"kind" : @"table",
    @"type" : @"INNER",
    @"table" : tableName ?: @"",
    @"alias" : alias ?: @"",
    @"left" : leftField ?: @"",
    @"operator" : ([normalized length] > 0 ? normalized : @"="),
    @"right" : rightField ?: @"",
    @"lateral" : @(NO),
  }];
  return self;
}

- (instancetype)leftJoinTable:(NSString *)tableName
                        alias:(NSString *)alias
                  onLeftField:(NSString *)leftField
                     operator:(NSString *)operatorName
                 onRightField:(NSString *)rightField {
  NSString *normalized = ALNSQLBuilderNormalizeOperator(operatorName ?: @"=");
  [self.joins addObject:@{
    @"kind" : @"table",
    @"type" : @"LEFT",
    @"table" : tableName ?: @"",
    @"alias" : alias ?: @"",
    @"left" : leftField ?: @"",
    @"operator" : ([normalized length] > 0 ? normalized : @"="),
    @"right" : rightField ?: @"",
    @"lateral" : @(NO),
  }];
  return self;
}

- (instancetype)rightJoinTable:(NSString *)tableName
                         alias:(NSString *)alias
                   onLeftField:(NSString *)leftField
                      operator:(NSString *)operatorName
                  onRightField:(NSString *)rightField {
  NSString *normalized = ALNSQLBuilderNormalizeOperator(operatorName ?: @"=");
  [self.joins addObject:@{
    @"kind" : @"table",
    @"type" : @"RIGHT",
    @"table" : tableName ?: @"",
    @"alias" : alias ?: @"",
    @"left" : leftField ?: @"",
    @"operator" : ([normalized length] > 0 ? normalized : @"="),
    @"right" : rightField ?: @"",
    @"lateral" : @(NO),
  }];
  return self;
}

- (instancetype)joinSubquery:(ALNSQLBuilder *)subquery
                       alias:(NSString *)alias
                onExpression:(NSString *)expression
                  parameters:(NSArray *)parameters {
  return [self joinSubquery:subquery
                      alias:alias
               onExpression:expression
         identifierBindings:nil
                 parameters:parameters];
}

- (instancetype)joinSubquery:(ALNSQLBuilder *)subquery
                       alias:(NSString *)alias
                onExpression:(NSString *)expression
          identifierBindings:(NSDictionary<NSString *, NSString *> *)identifierBindings
                  parameters:(NSArray *)parameters {
  [self.joins addObject:@{
    @"kind" : @"subquery",
    @"query" : subquery ?: [NSNull null],
    @"alias" : alias ?: @"",
    @"onExpressionIR" : ALNSQLBuilderMakeExpressionIR(expression, parameters, identifierBindings),
    @"type" : @"INNER",
    @"lateral" : @(NO),
  }];
  return self;
}

- (instancetype)leftJoinSubquery:(ALNSQLBuilder *)subquery
                           alias:(NSString *)alias
                    onExpression:(NSString *)expression
                      parameters:(NSArray *)parameters {
  return [self leftJoinSubquery:subquery
                          alias:alias
                   onExpression:expression
             identifierBindings:nil
                     parameters:parameters];
}

- (instancetype)leftJoinSubquery:(ALNSQLBuilder *)subquery
                           alias:(NSString *)alias
                    onExpression:(NSString *)expression
              identifierBindings:(NSDictionary<NSString *, NSString *> *)identifierBindings
                      parameters:(NSArray *)parameters {
  [self.joins addObject:@{
    @"kind" : @"subquery",
    @"query" : subquery ?: [NSNull null],
    @"alias" : alias ?: @"",
    @"onExpressionIR" : ALNSQLBuilderMakeExpressionIR(expression, parameters, identifierBindings),
    @"type" : @"LEFT",
    @"lateral" : @(NO),
  }];
  return self;
}

- (instancetype)rightJoinSubquery:(ALNSQLBuilder *)subquery
                            alias:(NSString *)alias
                     onExpression:(NSString *)expression
                       parameters:(NSArray *)parameters {
  return [self rightJoinSubquery:subquery
                           alias:alias
                    onExpression:expression
              identifierBindings:nil
                      parameters:parameters];
}

- (instancetype)rightJoinSubquery:(ALNSQLBuilder *)subquery
                            alias:(NSString *)alias
                     onExpression:(NSString *)expression
               identifierBindings:(NSDictionary<NSString *, NSString *> *)identifierBindings
                       parameters:(NSArray *)parameters {
  [self.joins addObject:@{
    @"kind" : @"subquery",
    @"query" : subquery ?: [NSNull null],
    @"alias" : alias ?: @"",
    @"onExpressionIR" : ALNSQLBuilderMakeExpressionIR(expression, parameters, identifierBindings),
    @"type" : @"RIGHT",
    @"lateral" : @(NO),
  }];
  return self;
}

- (instancetype)joinLateralSubquery:(ALNSQLBuilder *)subquery
                              alias:(NSString *)alias
                       onExpression:(NSString *)expression
                         parameters:(NSArray *)parameters {
  return [self joinLateralSubquery:subquery
                             alias:alias
                      onExpression:expression
                identifierBindings:nil
                        parameters:parameters];
}

- (instancetype)joinLateralSubquery:(ALNSQLBuilder *)subquery
                              alias:(NSString *)alias
                       onExpression:(NSString *)expression
                 identifierBindings:(NSDictionary<NSString *, NSString *> *)identifierBindings
                         parameters:(NSArray *)parameters {
  [self.joins addObject:@{
    @"kind" : @"subquery",
    @"query" : subquery ?: [NSNull null],
    @"alias" : alias ?: @"",
    @"onExpressionIR" : ALNSQLBuilderMakeExpressionIR(expression, parameters, identifierBindings),
    @"type" : @"INNER",
    @"lateral" : @(YES),
  }];
  return self;
}

- (instancetype)leftJoinLateralSubquery:(ALNSQLBuilder *)subquery
                                  alias:(NSString *)alias
                           onExpression:(NSString *)expression
                             parameters:(NSArray *)parameters {
  return [self leftJoinLateralSubquery:subquery
                                 alias:alias
                          onExpression:expression
                    identifierBindings:nil
                            parameters:parameters];
}

- (instancetype)leftJoinLateralSubquery:(ALNSQLBuilder *)subquery
                                  alias:(NSString *)alias
                           onExpression:(NSString *)expression
                     identifierBindings:(NSDictionary<NSString *, NSString *> *)identifierBindings
                             parameters:(NSArray *)parameters {
  [self.joins addObject:@{
    @"kind" : @"subquery",
    @"query" : subquery ?: [NSNull null],
    @"alias" : alias ?: @"",
    @"onExpressionIR" : ALNSQLBuilderMakeExpressionIR(expression, parameters, identifierBindings),
    @"type" : @"LEFT",
    @"lateral" : @(YES),
  }];
  return self;
}

- (instancetype)rightJoinLateralSubquery:(ALNSQLBuilder *)subquery
                                   alias:(NSString *)alias
                            onExpression:(NSString *)expression
                              parameters:(NSArray *)parameters {
  return [self rightJoinLateralSubquery:subquery
                                  alias:alias
                           onExpression:expression
                     identifierBindings:nil
                             parameters:parameters];
}

- (instancetype)rightJoinLateralSubquery:(ALNSQLBuilder *)subquery
                                   alias:(NSString *)alias
                            onExpression:(NSString *)expression
                      identifierBindings:(NSDictionary<NSString *, NSString *> *)identifierBindings
                              parameters:(NSArray *)parameters {
  [self.joins addObject:@{
    @"kind" : @"subquery",
    @"query" : subquery ?: [NSNull null],
    @"alias" : alias ?: @"",
    @"onExpressionIR" : ALNSQLBuilderMakeExpressionIR(expression, parameters, identifierBindings),
    @"type" : @"RIGHT",
    @"lateral" : @(YES),
  }];
  return self;
}

- (instancetype)groupByField:(NSString *)field {
  if ([field length] > 0) {
    [self.groupByFields addObject:[field copy]];
  }
  return self;
}

- (instancetype)groupByFields:(NSArray<NSString *> *)fields {
  for (NSString *field in fields ?: @[]) {
    [self groupByField:field];
  }
  return self;
}

- (instancetype)havingField:(NSString *)field equals:(id)value {
  return [self havingField:field operator:@"=" value:value];
}

- (instancetype)havingField:(NSString *)field
                   operator:(NSString *)operatorName
                      value:(id)value {
  NSString *normalized = ALNSQLBuilderNormalizeOperator(operatorName ?: @"=");
  [self.havingClauses addObject:@{
    @"field" : field ?: @"",
    @"operator" : ([normalized length] > 0 ? normalized : @"="),
    @"value" : value ?: [NSNull null],
    @"kind" : @"operator"
  }];
  return self;
}

- (instancetype)havingExpression:(NSString *)expression
                      parameters:(NSArray *)parameters {
  return [self havingExpression:expression
             identifierBindings:nil
                     parameters:parameters];
}

- (instancetype)havingExpression:(NSString *)expression
              identifierBindings:(NSDictionary<NSString *, NSString *> *)identifierBindings
                      parameters:(NSArray *)parameters {
  [self.havingClauses addObject:@{
    @"kind" : @"expression",
    @"expressionIR" : ALNSQLBuilderMakeExpressionIR(expression, parameters, identifierBindings),
  }];
  return self;
}

- (instancetype)havingAnyGroup:(ALNSQLBuilderGroupBlock)groupBlock {
  ALNSQLBuilder *groupBuilder = [[ALNSQLBuilder alloc] init];
  if (groupBlock != nil) {
    groupBlock(groupBuilder);
  }
  if ([groupBuilder.havingClauses count] == 0) {
    return self;
  }
  [self.havingClauses addObject:@{
    @"kind" : @"group",
    @"conjunction" : @"OR",
    @"clauses" : [NSArray arrayWithArray:groupBuilder.havingClauses]
  }];
  return self;
}

- (instancetype)havingAllGroup:(ALNSQLBuilderGroupBlock)groupBlock {
  ALNSQLBuilder *groupBuilder = [[ALNSQLBuilder alloc] init];
  if (groupBlock != nil) {
    groupBlock(groupBuilder);
  }
  if ([groupBuilder.havingClauses count] == 0) {
    return self;
  }
  [self.havingClauses addObject:@{
    @"kind" : @"group",
    @"conjunction" : @"AND",
    @"clauses" : [NSArray arrayWithArray:groupBuilder.havingClauses]
  }];
  return self;
}

- (instancetype)withCTE:(NSString *)name builder:(ALNSQLBuilder *)builder {
  [self.ctes addObject:@{
    @"name" : name ?: @"",
    @"query" : builder ?: [NSNull null],
    @"recursive" : @(NO)
  }];
  return self;
}

- (instancetype)withRecursiveCTE:(NSString *)name
                         builder:(ALNSQLBuilder *)builder {
  [self.ctes addObject:@{
    @"name" : name ?: @"",
    @"query" : builder ?: [NSNull null],
    @"recursive" : @(YES)
  }];
  return self;
}

- (instancetype)orderByField:(NSString *)field descending:(BOOL)descending {
  return [self orderByField:field descending:descending nulls:nil];
}

- (instancetype)orderByField:(NSString *)field
                  descending:(BOOL)descending
                       nulls:(NSString *)nullsDirective {
  [self.orderByClauses addObject:@{
    @"kind" : @"field",
    @"field" : field ?: @"",
    @"descending" : @(descending),
    @"nulls" : nullsDirective ?: @"",
  }];
  return self;
}

- (instancetype)orderByExpression:(NSString *)expression
                       descending:(BOOL)descending
                            nulls:(NSString *)nullsDirective {
  return [self orderByExpression:expression
                      descending:descending
                           nulls:nullsDirective
               identifierBindings:nil
                       parameters:nil];
}

- (instancetype)orderByExpression:(NSString *)expression
                       descending:(BOOL)descending
                            nulls:(NSString *)nullsDirective
                       parameters:(NSArray *)parameters {
  return [self orderByExpression:expression
                      descending:descending
                           nulls:nullsDirective
              identifierBindings:nil
                      parameters:parameters];
}

- (instancetype)orderByExpression:(NSString *)expression
                       descending:(BOOL)descending
                            nulls:(NSString *)nullsDirective
               identifierBindings:(NSDictionary<NSString *, NSString *> *)identifierBindings
                       parameters:(NSArray *)parameters {
  [self.orderByClauses addObject:@{
    @"kind" : @"expression",
    @"expressionIR" : ALNSQLBuilderMakeExpressionIR(expression, parameters, identifierBindings),
    @"descending" : @(descending),
    @"nulls" : nullsDirective ?: @"",
  }];
  return self;
}

- (instancetype)limit:(NSUInteger)limit {
  self.limitValue = limit;
  self.hasLimit = YES;
  return self;
}

- (instancetype)offset:(NSUInteger)offset {
  self.offsetValue = offset;
  self.hasOffset = YES;
  return self;
}

- (instancetype)returningField:(NSString *)field {
  if ([field length] > 0) {
    [self.returningColumns addObject:[field copy]];
  }
  return self;
}

- (instancetype)returningFields:(NSArray<NSString *> *)fields {
  for (NSString *field in fields ?: @[]) {
    [self returningField:field];
  }
  return self;
}

- (BOOL)validateTableName:(NSError **)error {
  if (!ALNSQLBuilderIdentifierIsSafe(self.tableName)) {
    if (error != NULL) {
      *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                      @"invalid table name",
                                      self.tableName);
    }
    return NO;
  }
  if ([self.tableAlias length] > 0 && !ALNSQLBuilderAliasIsSafe(self.tableAlias)) {
    if (error != NULL) {
      *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                      @"invalid table alias",
                                      self.tableAlias);
    }
    return NO;
  }
  return YES;
}

- (nullable NSString *)compileTrustedExpression:(id)expressionValue
                                     parameters:(id)rawParameters
                                  intoParameters:(NSMutableArray *)parameters
                                         context:(NSString *)context
                                           error:(NSError **)error {
  return [self compileTrustedExpression:expressionValue
                             parameters:rawParameters
                     identifierBindings:nil
                          intoParameters:parameters
                                 context:context
                                   error:error];
}

- (nullable NSString *)compileTrustedExpression:(id)expressionValue
                                     parameters:(id)rawParameters
                             identifierBindings:(id)rawIdentifierBindings
                                  intoParameters:(NSMutableArray *)parameters
                                         context:(NSString *)context
                                           error:(NSError **)error {
  NSString *expression = ALNSQLBuilderTrimmedString(expressionValue);
  if ([expression length] == 0) {
    if (error != NULL) {
      *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                      @"expression must not be empty",
                                      context);
    }
    return nil;
  }

  NSDictionary *identifierBindings = @{};
  if (rawIdentifierBindings != nil &&
      rawIdentifierBindings != (id)[NSNull null]) {
    if (![rawIdentifierBindings isKindOfClass:[NSDictionary class]]) {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                        @"expression identifier bindings must be a dictionary",
                                        context);
      }
      return nil;
    }
    identifierBindings = rawIdentifierBindings;
  }
  NSRegularExpression *identifierTokenRegex = ALNSQLBuilderIdentifierTokenRegex();
  NSArray *identifierTokenMatches =
      [identifierTokenRegex matchesInString:expression options:0 range:NSMakeRange(0, [expression length])];

  NSString *resolvedExpression = expression;
  if ([identifierTokenMatches count] > 0) {
    NSMutableDictionary *resolvedBindings = [NSMutableDictionary dictionary];
    for (id rawTokenName in identifierBindings) {
      if (![rawTokenName isKindOfClass:[NSString class]] ||
          !ALNSQLBuilderExpressionTokenIsSafe(rawTokenName)) {
        if (error != NULL) {
          *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                          @"invalid identifier token name",
                                          [rawTokenName description]);
        }
        return nil;
      }
      NSString *identifier = [identifierBindings[rawTokenName] isKindOfClass:[NSString class]]
                                 ? identifierBindings[rawTokenName]
                                 : @"";
      NSString *quotedIdentifier = ALNSQLBuilderQuoteIdentifierOrWildcard(identifier);
      if (quotedIdentifier == nil || [quotedIdentifier length] == 0) {
        if (error != NULL) {
          *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                          @"invalid identifier binding",
                                          identifier);
        }
        return nil;
      }
      resolvedBindings[rawTokenName] = quotedIdentifier;
    }

    NSMutableString *rewritten = [NSMutableString stringWithCapacity:[expression length] + 32];
    NSMutableSet *usedTokens = [NSMutableSet set];
    NSUInteger cursor = 0;
    for (NSTextCheckingResult *match in identifierTokenMatches) {
      NSRange fullRange = [match rangeAtIndex:0];
      NSRange tokenRange = [match rangeAtIndex:1];
      if (fullRange.location > cursor) {
        [rewritten appendString:[expression substringWithRange:NSMakeRange(cursor,
                                                                           fullRange.location - cursor)]];
      }
      NSString *token = [expression substringWithRange:tokenRange];
      NSString *replacement = resolvedBindings[token];
      if ([replacement length] == 0) {
        if (error != NULL) {
          *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                          @"missing identifier binding for token",
                                          token);
        }
        return nil;
      }
      [rewritten appendString:replacement];
      [usedTokens addObject:token];
      cursor = NSMaxRange(fullRange);
    }
    if (cursor < [expression length]) {
      [rewritten appendString:[expression substringFromIndex:cursor]];
    }

    for (NSString *token in resolvedBindings) {
      if (![usedTokens containsObject:token]) {
        if (error != NULL) {
          *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                          @"unused identifier binding token",
                                          token);
        }
        return nil;
      }
    }
    resolvedExpression = [NSString stringWithString:rewritten];
  } else if ([identifierBindings count] > 0) {
    if (error != NULL) {
      *error = ALNSQLBuilderMakeError(
          ALNSQLBuilderErrorInvalidArgument,
          @"identifier bindings were provided but expression has no {{token}} placeholders",
          context);
    }
    return nil;
  }

  NSArray *expressionParameters = @[];
  if (rawParameters != nil &&
      rawParameters != (id)[NSNull null]) {
    if (![rawParameters isKindOfClass:[NSArray class]]) {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                        @"expression parameters must be an array",
                                        context);
      }
      return nil;
    }
    expressionParameters = rawParameters;
  }
  NSRegularExpression *placeholderRegex = ALNSQLBuilderPlaceholderRegex();
  NSArray *placeholderMatches =
      [placeholderRegex matchesInString:resolvedExpression
                                options:0
                                  range:NSMakeRange(0, [resolvedExpression length])];
  if ([placeholderMatches count] == 0 && [expressionParameters count] > 0) {
    if (error != NULL) {
      *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                      @"expression parameters require placeholders",
                                      context);
    }
    return nil;
  }
  if ([placeholderMatches count] > 0 && [expressionParameters count] == 0) {
    if (error != NULL) {
      *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                      @"expression placeholders require parameter values",
                                      context);
    }
    return nil;
  }

  NSMutableSet *seenPlaceholderIndexes = [NSMutableSet set];
  for (NSTextCheckingResult *match in placeholderMatches) {
    NSRange indexRange = [match rangeAtIndex:1];
    NSInteger placeholderIndex = [[resolvedExpression substringWithRange:indexRange] integerValue];
    if (placeholderIndex < 1 || placeholderIndex > (NSInteger)[expressionParameters count]) {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                        @"expression placeholder index exceeds provided parameters",
                                        context);
      }
      return nil;
    }
    [seenPlaceholderIndexes addObject:@(placeholderIndex)];
  }

  for (NSUInteger idx = 1; idx <= [expressionParameters count]; idx++) {
    if (![seenPlaceholderIndexes containsObject:@(idx)]) {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                        @"expression parameters must map to placeholders $1..$N",
                                        context);
      }
      return nil;
    }
  }

  NSUInteger placeholderOffset = [parameters count];
  for (id value in expressionParameters) {
    [parameters addObject:value ?: [NSNull null]];
  }
  return ALNSQLBuilderShiftPlaceholders(resolvedExpression, placeholderOffset);
}

- (nullable NSString *)compileExpressionIR:(id)rawExpressionIR
                            intoParameters:(NSMutableArray *)parameters
                                   context:(NSString *)context
                                     error:(NSError **)error {
  if (![rawExpressionIR isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                      @"expression IR entry must be a dictionary",
                                      context);
    }
    return nil;
  }

  NSDictionary *expressionIR = rawExpressionIR;
  NSString *kind = [expressionIR[@"kind"] isKindOfClass:[NSString class]] ? expressionIR[@"kind"] : @"";
  if ([kind length] > 0 && ![kind isEqualToString:@"trusted-template-v1"]) {
    if (error != NULL) {
      *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorCompileFailed,
                                      @"unsupported expression IR kind",
                                      kind);
    }
    return nil;
  }

  id templateValue = expressionIR[@"template"];
  if (templateValue == nil) {
    templateValue = expressionIR[@"expression"];
  }
  if (![templateValue isKindOfClass:[NSString class]]) {
    if (error != NULL) {
      *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                      @"expression IR template must be a string",
                                      context);
    }
    return nil;
  }

  id parametersValue = expressionIR[@"parameters"];
  if (parametersValue != nil &&
      parametersValue != (id)[NSNull null] &&
      ![parametersValue isKindOfClass:[NSArray class]]) {
    if (error != NULL) {
      *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                      @"expression IR parameters must be an array",
                                      context);
    }
    return nil;
  }

  id identifierBindingsValue = expressionIR[@"identifierBindings"];
  if (identifierBindingsValue != nil &&
      identifierBindingsValue != (id)[NSNull null] &&
      ![identifierBindingsValue isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                      @"expression IR identifierBindings must be a dictionary",
                                      context);
    }
    return nil;
  }

  return [self compileTrustedExpression:templateValue
                             parameters:parametersValue
                     identifierBindings:identifierBindingsValue
                          intoParameters:parameters
                                 context:context
                                   error:error];
}

- (nullable NSString *)compileColumnsWithParameters:(NSMutableArray *)parameters
                                              error:(NSError **)error {
  NSMutableArray *columns = [NSMutableArray array];
  for (id value in self.selectColumns ?: @[]) {
    if ([value isKindOfClass:[NSDictionary class]]) {
      NSString *kind = [value[@"kind"] isKindOfClass:[NSString class]] ? value[@"kind"] : @"";
      if (![kind isEqualToString:@"expression"]) {
        if (error != NULL) {
          *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                          @"unsupported select column entry",
                                          kind);
        }
        return nil;
      }

      id expressionIR = value[@"expressionIR"];
      NSString *expression = nil;
      if (expressionIR != nil) {
        expression = [self compileExpressionIR:expressionIR
                                intoParameters:parameters
                                       context:@"select"
                                         error:error];
      } else {
        expression = [self compileTrustedExpression:value[@"expression"]
                                         parameters:value[@"parameters"]
                                 identifierBindings:value[@"identifierBindings"]
                                      intoParameters:parameters
                                             context:@"select"
                                               error:error];
      }
      if (expression == nil) {
        return nil;
      }

      NSString *alias = [value[@"alias"] isKindOfClass:[NSString class]] ? value[@"alias"] : @"";
      if ([alias length] > 0) {
        if (!ALNSQLBuilderAliasIsSafe(alias)) {
          if (error != NULL) {
            *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                            @"invalid select alias",
                                            alias);
          }
          return nil;
        }
        [columns addObject:[NSString stringWithFormat:@"%@ AS \"%@\"", expression, alias]];
      } else {
        [columns addObject:expression];
      }
      continue;
    }

    if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
      continue;
    }
    NSString *column = ALNSQLBuilderQuoteIdentifierOrWildcard(value);
    if (column == nil) {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                        @"invalid select column",
                                        value);
      }
      return nil;
    }
    [columns addObject:column];
  }
  if ([columns count] == 0) {
    [columns addObject:@"*"];
  }
  return [columns componentsJoinedByString:@", "];
}

- (nullable NSString *)compileReturningColumns:(NSError **)error {
  if ([self.returningColumns count] == 0) {
    return @"";
  }

  NSMutableArray *columns = [NSMutableArray arrayWithCapacity:[self.returningColumns count]];
  for (id value in self.returningColumns) {
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
      continue;
    }
    NSString *column = ALNSQLBuilderQuoteIdentifierOrWildcard(value);
    if (column == nil) {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                        @"invalid returning field",
                                        value);
      }
      return nil;
    }
    [columns addObject:column];
  }

  if ([columns count] == 0) {
    return @"";
  }
  return [NSString stringWithFormat:@" RETURNING %@",
                                    [columns componentsJoinedByString:@", "]];
}

- (nullable NSString *)compileSubquery:(ALNSQLBuilder *)subquery
                             parameters:(NSMutableArray *)parameters
                                  error:(NSError **)error {
  if (![subquery isKindOfClass:[ALNSQLBuilder class]]) {
    if (error != NULL) {
      *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                      @"subquery must be an ALNSQLBuilder",
                                      self.tableName);
    }
    return nil;
  }

  NSError *subqueryError = nil;
  NSDictionary *built = [subquery build:&subqueryError];
  if (built == nil) {
    if (error != NULL) {
      *error = subqueryError ?: ALNSQLBuilderMakeError(ALNSQLBuilderErrorCompileFailed,
                                                       @"subquery compile failed",
                                                       self.tableName);
    }
    return nil;
  }

  NSString *sql = [built[@"sql"] isKindOfClass:[NSString class]] ? built[@"sql"] : @"";
  NSArray *subqueryParams = [built[@"parameters"] isKindOfClass:[NSArray class]]
                                ? built[@"parameters"]
                                : @[];

  NSString *shiftedSQL = ALNSQLBuilderShiftPlaceholders(sql, [parameters count]);
  for (id value in subqueryParams) {
    [parameters addObject:value ?: [NSNull null]];
  }
  return shiftedSQL;
}

- (nullable NSString *)compilePredicateClauses:(NSArray *)clauses
                                    parameters:(NSMutableArray *)parameters
                                     joinToken:(NSString *)joinToken
                                         error:(NSError **)error {
  if ([clauses count] == 0) {
    return @"";
  }

  NSMutableArray *fragments = [NSMutableArray arrayWithCapacity:[clauses count]];

  for (NSDictionary *clause in clauses) {
    NSString *kind = [clause[@"kind"] isKindOfClass:[NSString class]] ? clause[@"kind"] : @"";
    NSString *field = [clause[@"field"] isKindOfClass:[NSString class]] ? clause[@"field"] : @"";

    if ([kind isEqualToString:@"group"]) {
      NSString *conjunction = [clause[@"conjunction"] isKindOfClass:[NSString class]]
                                  ? ALNSQLBuilderNormalizeOperator(clause[@"conjunction"])
                                  : @"AND";
      if (![conjunction isEqualToString:@"OR"]) {
        conjunction = @"AND";
      }
      NSArray *childClauses = [clause[@"clauses"] isKindOfClass:[NSArray class]]
                                  ? clause[@"clauses"]
                                  : @[];
      NSString *groupSQL = [self compilePredicateClauses:childClauses
                                              parameters:parameters
                                               joinToken:conjunction
                                                   error:error];
      if (groupSQL == nil) {
        return nil;
      }
      if ([groupSQL length] > 0) {
        [fragments addObject:[NSString stringWithFormat:@"(%@)", groupSQL]];
      }
      continue;
    }

    if ([kind isEqualToString:@"expression"]) {
      id expressionIR = clause[@"expressionIR"];
      NSString *compiledExpression = nil;
      if (expressionIR != nil) {
        compiledExpression = [self compileExpressionIR:expressionIR
                                        intoParameters:parameters
                                               context:@"where/having"
                                                 error:error];
      } else {
        compiledExpression = [self compileTrustedExpression:clause[@"expression"]
                                                 parameters:clause[@"parameters"]
                                         identifierBindings:clause[@"identifierBindings"]
                                              intoParameters:parameters
                                                     context:@"where/having"
                                                       error:error];
      }
      if (compiledExpression == nil) {
        return nil;
      }
      [fragments addObject:[NSString stringWithFormat:@"(%@)", compiledExpression]];
      continue;
    }

    if (!ALNSQLBuilderIdentifierIsSafe(field)) {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                        @"invalid predicate field",
                                        field);
      }
      return nil;
    }

    NSString *quotedField = ALNSQLBuilderQuoteIdentifier(field);

    if ([kind isEqualToString:@"in"] || [kind isEqualToString:@"not-in"]) {
      NSArray *values = [clause[@"values"] isKindOfClass:[NSArray class]] ? clause[@"values"] : @[];
      BOOL negated = [kind isEqualToString:@"not-in"];
      if ([values count] == 0) {
        [fragments addObject:(negated ? @"1=1" : @"1=0")];
        continue;
      }
      NSMutableArray *placeholders = [NSMutableArray arrayWithCapacity:[values count]];
      for (id value in values) {
        [parameters addObject:value ?: [NSNull null]];
        [placeholders addObject:[NSString stringWithFormat:@"$%lu", (unsigned long)[parameters count]]];
      }
      [fragments addObject:[NSString stringWithFormat:@"%@ %@ (%@)",
                                                       quotedField,
                                                       negated ? @"NOT IN" : @"IN",
                                                       [placeholders componentsJoinedByString:@", "]]];
      continue;
    }

    if ([kind isEqualToString:@"between"] || [kind isEqualToString:@"not-between"]) {
      id lower = clause[@"lower"];
      id upper = clause[@"upper"];
      if (lower == nil || lower == [NSNull null] || upper == nil || upper == [NSNull null]) {
        if (error != NULL) {
          *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                          @"between predicates require non-null lower and upper bounds",
                                          field);
        }
        return nil;
      }

      [parameters addObject:lower];
      NSString *first = [NSString stringWithFormat:@"$%lu", (unsigned long)[parameters count]];
      [parameters addObject:upper];
      NSString *second = [NSString stringWithFormat:@"$%lu", (unsigned long)[parameters count]];
      NSString *operatorName = [kind isEqualToString:@"not-between"] ? @"NOT BETWEEN" : @"BETWEEN";
      [fragments addObject:[NSString stringWithFormat:@"%@ %@ %@ AND %@",
                                                       quotedField,
                                                       operatorName,
                                                       first,
                                                       second]];
      continue;
    }

    if ([kind isEqualToString:@"subquery-in"] || [kind isEqualToString:@"subquery-not-in"]) {
      ALNSQLBuilder *subquery = [clause[@"query"] isKindOfClass:[ALNSQLBuilder class]]
                                    ? clause[@"query"]
                                    : nil;
      NSString *subquerySQL = [self compileSubquery:subquery parameters:parameters error:error];
      if (subquerySQL == nil) {
        return nil;
      }
      [fragments addObject:[NSString stringWithFormat:@"%@ %@ (%@)",
                                                       quotedField,
                                                       [kind isEqualToString:@"subquery-not-in"] ? @"NOT IN" : @"IN",
                                                       subquerySQL]];
      continue;
    }

    NSString *operatorName = [clause[@"operator"] isKindOfClass:[NSString class]]
                                 ? ALNSQLBuilderNormalizeOperator(clause[@"operator"])
                                 : @"=";
    if (![ALNSQLBuilderAllowedComparisonOperators() containsObject:operatorName]) {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorUnsupportedOperator,
                                        @"unsupported where/having operator",
                                        operatorName);
      }
      return nil;
    }

    id value = clause[@"value"];
    if (value == nil || value == [NSNull null]) {
      if ([operatorName isEqualToString:@"="]) {
        [fragments addObject:[NSString stringWithFormat:@"%@ IS NULL", quotedField]];
      } else if ([operatorName isEqualToString:@"!="] || [operatorName isEqualToString:@"<>"]) {
        [fragments addObject:[NSString stringWithFormat:@"%@ IS NOT NULL", quotedField]];
      } else if ([operatorName isEqualToString:@"IS DISTINCT FROM"] ||
                 [operatorName isEqualToString:@"IS NOT DISTINCT FROM"]) {
        [fragments addObject:[NSString stringWithFormat:@"%@ %@ NULL", quotedField, operatorName]];
      } else {
        if (error != NULL) {
          *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                          @"NULL values only support '=', '!=', '<>', and DISTINCT operators",
                                          field);
        }
        return nil;
      }
      continue;
    }

    [parameters addObject:value];
    NSString *placeholder = [NSString stringWithFormat:@"$%lu", (unsigned long)[parameters count]];
    [fragments addObject:[NSString stringWithFormat:@"%@ %@ %@", quotedField, operatorName, placeholder]];
  }

  if ([fragments count] == 0) {
    return @"";
  }
  NSString *normalizedJoin = [ALNSQLBuilderNormalizeOperator(joinToken) isEqualToString:@"OR"]
                                ? @" OR "
                                : @" AND ";
  return [fragments componentsJoinedByString:normalizedJoin];
}

- (BOOL)appendWhereClauseSQLTo:(NSMutableString *)sql
                    parameters:(NSMutableArray *)parameters
                         error:(NSError **)error {
  if ([self.whereClauses count] == 0) {
    return YES;
  }

  NSString *whereSQL = [self compilePredicateClauses:self.whereClauses
                                          parameters:parameters
                                           joinToken:@"AND"
                                               error:error];
  if (whereSQL == nil) {
    return NO;
  }
  if ([whereSQL length] > 0) {
    [sql appendFormat:@" WHERE %@", whereSQL];
  }
  return YES;
}

- (BOOL)appendGroupBySQLTo:(NSMutableString *)sql error:(NSError **)error {
  if ([self.groupByFields count] == 0) {
    return YES;
  }

  NSMutableArray *fields = [NSMutableArray arrayWithCapacity:[self.groupByFields count]];
  for (NSString *field in self.groupByFields) {
    NSString *quoted = ALNSQLBuilderQuoteIdentifierOrWildcard(field);
    if (quoted == nil || [quoted isEqualToString:@"*"]) {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                        @"invalid group by field",
                                        field);
      }
      return NO;
    }
    [fields addObject:quoted];
  }

  if ([fields count] > 0) {
    [sql appendFormat:@" GROUP BY %@", [fields componentsJoinedByString:@", "]];
  }
  return YES;
}

- (BOOL)appendHavingClauseSQLTo:(NSMutableString *)sql
                     parameters:(NSMutableArray *)parameters
                          error:(NSError **)error {
  if ([self.havingClauses count] == 0) {
    return YES;
  }

  NSString *havingSQL = [self compilePredicateClauses:self.havingClauses
                                           parameters:parameters
                                            joinToken:@"AND"
                                                error:error];
  if (havingSQL == nil) {
    return NO;
  }
  if ([havingSQL length] > 0) {
    [sql appendFormat:@" HAVING %@", havingSQL];
  }
  return YES;
}

- (BOOL)appendOrderBySQLTo:(NSMutableString *)sql
                 parameters:(NSMutableArray *)parameters
                      error:(NSError **)error {
  if ([self.orderByClauses count] == 0) {
    return YES;
  }

  NSMutableArray *fragments = [NSMutableArray arrayWithCapacity:[self.orderByClauses count]];
  for (NSDictionary *entry in self.orderByClauses) {
    NSString *kind = [entry[@"kind"] isKindOfClass:[NSString class]] ? entry[@"kind"] : @"field";
    NSString *orderTarget = nil;
    if ([kind isEqualToString:@"expression"]) {
      id expressionIR = entry[@"expressionIR"];
      if (expressionIR != nil) {
        orderTarget = [self compileExpressionIR:expressionIR
                                 intoParameters:parameters
                                        context:@"order by"
                                          error:error];
      } else {
        orderTarget = [self compileTrustedExpression:entry[@"expression"]
                                          parameters:entry[@"parameters"]
                                  identifierBindings:entry[@"identifierBindings"]
                                       intoParameters:parameters
                                              context:@"order by"
                                                error:error];
      }
      if (orderTarget == nil) {
        return NO;
      }
    } else {
      NSString *field = [entry[@"field"] isKindOfClass:[NSString class]] ? entry[@"field"] : @"";
      NSString *quotedField = ALNSQLBuilderQuoteIdentifierOrWildcard(field);
      if (quotedField == nil || [quotedField isEqualToString:@"*"]) {
        if (error != NULL) {
          *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                          @"invalid order field",
                                          field);
        }
        return NO;
      }
      orderTarget = quotedField;
    }

    BOOL descending = [entry[@"descending"] boolValue];
    NSString *nulls = ALNSQLBuilderNormalizeNullsDirective(entry[@"nulls"]);
    NSMutableString *fragment = [NSMutableString stringWithFormat:@"%@ %@",
                                                         orderTarget,
                                                         descending ? @"DESC" : @"ASC"];
    if ([nulls length] > 0) {
      [fragment appendFormat:@" %@", nulls];
    }
    [fragments addObject:[NSString stringWithString:fragment]];
  }

  if ([fragments count] > 0) {
    [sql appendFormat:@" ORDER BY %@", [fragments componentsJoinedByString:@", "]];
  }
  return YES;
}

- (BOOL)appendJoinSQLTo:(NSMutableString *)sql
             parameters:(NSMutableArray *)parameters
                  error:(NSError **)error {
  if ([self.joins count] == 0) {
    return YES;
  }

  for (NSDictionary *join in self.joins) {
    NSString *joinType = [join[@"type"] isKindOfClass:[NSString class]]
                             ? ALNSQLBuilderNormalizeOperator(join[@"type"])
                             : @"INNER";
    if (![joinType isEqualToString:@"LEFT"] &&
        ![joinType isEqualToString:@"RIGHT"] &&
        ![joinType isEqualToString:@"INNER"]) {
      joinType = @"INNER";
    }
    BOOL lateral = [join[@"lateral"] boolValue];
    NSString *joinKind = [join[@"kind"] isKindOfClass:[NSString class]] ? join[@"kind"] : @"table";
    if ([joinKind isEqualToString:@"subquery"]) {
      ALNSQLBuilder *subquery = [join[@"query"] isKindOfClass:[ALNSQLBuilder class]]
                                    ? join[@"query"]
                                    : nil;
      NSString *subquerySQL = [self compileSubquery:subquery parameters:parameters error:error];
      if (subquerySQL == nil) {
        return NO;
      }

      NSString *alias = [join[@"alias"] isKindOfClass:[NSString class]] ? join[@"alias"] : @"";
      if (!ALNSQLBuilderAliasIsSafe(alias)) {
        if (error != NULL) {
          *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                          @"invalid join alias",
                                          alias);
        }
        return NO;
      }

      id onExpressionIR = join[@"onExpressionIR"];
      NSString *onExpression = nil;
      if (onExpressionIR != nil) {
        onExpression = [self compileExpressionIR:onExpressionIR
                                  intoParameters:parameters
                                         context:@"join on"
                                           error:error];
      } else {
        onExpression = [self compileTrustedExpression:join[@"onExpression"]
                                           parameters:join[@"onParameters"]
                                   identifierBindings:join[@"onIdentifierBindings"]
                                        intoParameters:parameters
                                               context:@"join on"
                                                 error:error];
      }
      if (onExpression == nil) {
        return NO;
      }

      [sql appendFormat:@" %@ JOIN %@(%@) AS \"%@\" ON %@",
                        joinType,
                        lateral ? @"LATERAL " : @"",
                        subquerySQL,
                        alias,
                        onExpression];
      continue;
    }

    NSString *table = [join[@"table"] isKindOfClass:[NSString class]] ? join[@"table"] : @"";
    NSString *alias = [join[@"alias"] isKindOfClass:[NSString class]] ? join[@"alias"] : @"";
    NSString *tableReference = ALNSQLBuilderBuildTableReference(table, alias, error);
    if (tableReference == nil) {
      return NO;
    }

    NSString *left = [join[@"left"] isKindOfClass:[NSString class]] ? join[@"left"] : @"";
    NSString *right = [join[@"right"] isKindOfClass:[NSString class]] ? join[@"right"] : @"";
    if (!ALNSQLBuilderIdentifierIsSafe(left) || !ALNSQLBuilderIdentifierIsSafe(right)) {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                        @"invalid join field",
                                        (!ALNSQLBuilderIdentifierIsSafe(left) ? left : right));
      }
      return NO;
    }

    NSString *operatorName = [join[@"operator"] isKindOfClass:[NSString class]]
                                 ? ALNSQLBuilderNormalizeOperator(join[@"operator"])
                                 : @"=";
    if (![ALNSQLBuilderAllowedJoinOperators() containsObject:operatorName]) {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorUnsupportedOperator,
                                        @"unsupported join operator",
                                        operatorName);
      }
      return NO;
    }

    [sql appendFormat:@" %@ JOIN %@ ON %@ %@ %@",
                      joinType,
                      tableReference,
                      ALNSQLBuilderQuoteIdentifier(left),
                      operatorName,
                      ALNSQLBuilderQuoteIdentifier(right)];
  }
  return YES;
}

- (BOOL)appendCTESQLTo:(NSMutableString *)sql
            parameters:(NSMutableArray *)parameters
                 error:(NSError **)error {
  if ([self.ctes count] == 0) {
    return YES;
  }

  NSMutableArray *fragments = [NSMutableArray arrayWithCapacity:[self.ctes count]];
  BOOL hasRecursive = NO;

  for (NSDictionary *entry in self.ctes) {
    NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : @"";
    ALNSQLBuilder *builder = [entry[@"query"] isKindOfClass:[ALNSQLBuilder class]]
                                 ? entry[@"query"]
                                 : nil;
    BOOL recursive = [entry[@"recursive"] boolValue];

    if (!ALNSQLBuilderAliasIsSafe(name)) {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                        @"invalid CTE name",
                                        name);
      }
      return NO;
    }

    NSString *subquerySQL = [self compileSubquery:builder parameters:parameters error:error];
    if (subquerySQL == nil) {
      return NO;
    }

    [fragments addObject:[NSString stringWithFormat:@"\"%@\" AS (%@)",
                                                     name,
                                                     subquerySQL]];
    hasRecursive = hasRecursive || recursive;
  }

  if ([fragments count] > 0) {
    [sql appendFormat:@"%@%@ ",
                      hasRecursive ? @"WITH RECURSIVE " : @"WITH ",
                      [fragments componentsJoinedByString:@", "]];
  }
  return YES;
}

- (nullable NSDictionary *)build:(NSError **)error {
  if (![self validateTableName:error]) {
    return nil;
  }

  NSMutableArray *parameters = [NSMutableArray array];
  NSMutableString *sql = [NSMutableString string];

  if (![self appendCTESQLTo:sql parameters:parameters error:error]) {
    return nil;
  }

  NSString *tableReference = ALNSQLBuilderBuildTableReference(self.tableName,
                                                              self.tableAlias,
                                                              error);
  if (tableReference == nil) {
    return nil;
  }

  NSString *returningClause = [self compileReturningColumns:error];
  if (returningClause == nil) {
    return nil;
  }

  switch (self.kind) {
    case ALNSQLBuilderKindSelect: {
      if ([returningClause length] > 0) {
        if (error != NULL) {
          *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                          @"RETURNING is only supported for insert/update/delete builders",
                                          self.tableName);
        }
        return nil;
      }

      NSString *columns = [self compileColumnsWithParameters:parameters error:error];
      if (columns == nil) {
        return nil;
      }
      [sql appendFormat:@"SELECT %@ FROM %@", columns, tableReference];
      if (![self appendJoinSQLTo:sql parameters:parameters error:error]) {
        return nil;
      }
      if (![self appendWhereClauseSQLTo:sql parameters:parameters error:error]) {
        return nil;
      }
      if (![self appendGroupBySQLTo:sql error:error]) {
        return nil;
      }
      if (![self appendHavingClauseSQLTo:sql parameters:parameters error:error]) {
        return nil;
      }
      if (![self appendOrderBySQLTo:sql parameters:parameters error:error]) {
        return nil;
      }
      if (self.hasLimit) {
        [sql appendFormat:@" LIMIT %lu", (unsigned long)self.limitValue];
      }
      if (self.hasOffset) {
        [sql appendFormat:@" OFFSET %lu", (unsigned long)self.offsetValue];
      }
      break;
    }
    case ALNSQLBuilderKindInsert: {
      if ([self.values count] == 0) {
        if (error != NULL) {
          *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                          @"insert requires at least one value",
                                          self.tableName);
        }
        return nil;
      }
      NSArray *keys = ALNSQLBuilderSortedDictionaryKeys(self.values);
      NSMutableArray *quotedColumns = [NSMutableArray arrayWithCapacity:[keys count]];
      NSMutableArray *placeholders = [NSMutableArray arrayWithCapacity:[keys count]];
      for (NSString *key in keys) {
        if (!ALNSQLBuilderIdentifierIsSafe(key)) {
          if (error != NULL) {
            *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                            @"invalid insert field",
                                            key);
          }
          return nil;
        }
        [quotedColumns addObject:ALNSQLBuilderQuoteIdentifier(key)];
        [parameters addObject:self.values[key] ?: [NSNull null]];
        [placeholders addObject:[NSString stringWithFormat:@"$%lu", (unsigned long)[parameters count]]];
      }
      [sql appendFormat:@"INSERT INTO %@ (%@) VALUES (%@)",
                        tableReference,
                        [quotedColumns componentsJoinedByString:@", "],
                        [placeholders componentsJoinedByString:@", "]];
      if ([returningClause length] > 0) {
        [sql appendString:returningClause];
      }
      break;
    }
    case ALNSQLBuilderKindUpdate: {
      if ([self.values count] == 0) {
        if (error != NULL) {
          *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidArgument,
                                          @"update requires at least one value",
                                          self.tableName);
        }
        return nil;
      }
      NSArray *keys = ALNSQLBuilderSortedDictionaryKeys(self.values);
      NSMutableArray *assignments = [NSMutableArray arrayWithCapacity:[keys count]];
      for (NSString *key in keys) {
        if (!ALNSQLBuilderIdentifierIsSafe(key)) {
          if (error != NULL) {
            *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorInvalidIdentifier,
                                            @"invalid update field",
                                            key);
          }
          return nil;
        }
        [parameters addObject:self.values[key] ?: [NSNull null]];
        NSString *placeholder = [NSString stringWithFormat:@"$%lu", (unsigned long)[parameters count]];
        [assignments addObject:[NSString stringWithFormat:@"%@ = %@",
                                                          ALNSQLBuilderQuoteIdentifier(key),
                                                          placeholder]];
      }
      [sql appendFormat:@"UPDATE %@ SET %@", tableReference, [assignments componentsJoinedByString:@", "]];
      if (![self appendWhereClauseSQLTo:sql parameters:parameters error:error]) {
        return nil;
      }
      if ([returningClause length] > 0) {
        [sql appendString:returningClause];
      }
      break;
    }
    case ALNSQLBuilderKindDelete: {
      [sql appendFormat:@"DELETE FROM %@", tableReference];
      if (![self appendWhereClauseSQLTo:sql parameters:parameters error:error]) {
        return nil;
      }
      if ([returningClause length] > 0) {
        [sql appendString:returningClause];
      }
      break;
    }
    default: {
      if (error != NULL) {
        *error = ALNSQLBuilderMakeError(ALNSQLBuilderErrorCompileFailed,
                                        @"unknown builder kind",
                                        self.tableName);
      }
      return nil;
    }
  }

  return @{
    @"sql" : [NSString stringWithString:sql],
    @"parameters" : [NSArray arrayWithArray:parameters]
  };
}

- (NSString *)buildSQL:(NSError **)error {
  NSDictionary *built = [self build:error];
  return [built[@"sql"] isKindOfClass:[NSString class]] ? built[@"sql"] : nil;
}

- (NSArray *)buildParameters:(NSError **)error {
  NSDictionary *built = [self build:error];
  return [built[@"parameters"] isKindOfClass:[NSArray class]] ? built[@"parameters"] : @[];
}

@end

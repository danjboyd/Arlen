#import "ALNMigrationRunner.h"

NSString *const ALNMigrationRunnerErrorDomain = @"Arlen.Data.MigrationRunner.Error";
NSString *const ALNMigrationRunnerDefaultDatabaseTarget = @"default";

typedef NS_ENUM(NSUInteger, ALNMigrationSQLScanState) {
  ALNMigrationSQLScanStateDefault = 0,
  ALNMigrationSQLScanStateSingleQuote = 1,
  ALNMigrationSQLScanStateDoubleQuote = 2,
  ALNMigrationSQLScanStateLineComment = 3,
  ALNMigrationSQLScanStateBlockComment = 4,
  ALNMigrationSQLScanStateDollarQuote = 5,
};

static NSError *ALNMigrationError(NSString *message, NSString *detail) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"migration error";
  if ([detail length] > 0) {
    userInfo[@"detail"] = detail;
  }
  return [NSError errorWithDomain:ALNMigrationRunnerErrorDomain code:1 userInfo:userInfo];
}

static NSString *ALNMigrationComposedDetail(NSError *error) {
  if (![error isKindOfClass:[NSError class]]) {
    return nil;
  }

  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  NSString *localized = [error localizedDescription];
  if ([localized length] > 0) {
    [parts addObject:localized];
  }

  NSString *detail =
      [error.userInfo[@"detail"] isKindOfClass:[NSString class]] ? error.userInfo[@"detail"] : @"";
  if ([detail length] > 0 && ![detail isEqualToString:localized]) {
    [parts addObject:detail];
  }

  if ([parts count] == 0) {
    return nil;
  }
  return [parts componentsJoinedByString:@": "];
}

static BOOL ALNMigrationIsIdentifierStart(unichar character) {
  return ([[NSCharacterSet letterCharacterSet] characterIsMember:character] || character == '_');
}

static BOOL ALNMigrationIsIdentifierBody(unichar character) {
  return ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:character] || character == '_');
}

static NSString *ALNMigrationDollarQuoteTagAtIndex(NSString *sql,
                                                   NSUInteger index,
                                                   NSUInteger *tagLength) {
  NSUInteger length = [sql length];
  if (index >= length || [sql characterAtIndex:index] != '$') {
    return nil;
  }

  NSUInteger cursor = index + 1;
  if (cursor < length && [sql characterAtIndex:cursor] == '$') {
    if (tagLength != NULL) {
      *tagLength = 2;
    }
    return @"$$";
  }

  if (cursor >= length || !ALNMigrationIsIdentifierStart([sql characterAtIndex:cursor])) {
    return nil;
  }

  while (cursor < length) {
    unichar character = [sql characterAtIndex:cursor];
    if (character == '$') {
      NSUInteger lengthValue = (cursor - index) + 1;
      if (tagLength != NULL) {
        *tagLength = lengthValue;
      }
      return [sql substringWithRange:NSMakeRange(index, lengthValue)];
    }
    if (!ALNMigrationIsIdentifierBody(character)) {
      return nil;
    }
    cursor += 1;
  }

  return nil;
}

static NSString *ALNMigrationNextIdentifierToken(NSString *statement, NSUInteger *cursor) {
  if (![statement isKindOfClass:[NSString class]]) {
    return nil;
  }

  NSUInteger index = (cursor != NULL) ? *cursor : 0;
  NSUInteger length = [statement length];
  while (index < length) {
    unichar character = [statement characterAtIndex:index];
    if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:character]) {
      index += 1;
      continue;
    }
    if (character == '-' && (index + 1) < length && [statement characterAtIndex:(index + 1)] == '-') {
      index += 2;
      while (index < length) {
        unichar lineCharacter = [statement characterAtIndex:index];
        index += 1;
        if (lineCharacter == '\n') {
          break;
        }
      }
      continue;
    }
    if (character == '/' && (index + 1) < length && [statement characterAtIndex:(index + 1)] == '*') {
      NSUInteger depth = 1;
      index += 2;
      while (index < length && depth > 0) {
        unichar blockCharacter = [statement characterAtIndex:index];
        if (blockCharacter == '/' && (index + 1) < length &&
            [statement characterAtIndex:(index + 1)] == '*') {
          depth += 1;
          index += 2;
          continue;
        }
        if (blockCharacter == '*' && (index + 1) < length &&
            [statement characterAtIndex:(index + 1)] == '/') {
          depth -= 1;
          index += 2;
          continue;
        }
        index += 1;
      }
      continue;
    }
    break;
  }

  if (cursor != NULL) {
    *cursor = index;
  }
  if (index >= length) {
    return nil;
  }

  unichar firstCharacter = [statement characterAtIndex:index];
  if (!ALNMigrationIsIdentifierStart(firstCharacter)) {
    return nil;
  }

  NSUInteger start = index;
  index += 1;
  while (index < length && ALNMigrationIsIdentifierBody([statement characterAtIndex:index])) {
    index += 1;
  }

  if (cursor != NULL) {
    *cursor = index;
  }
  return [[statement substringWithRange:NSMakeRange(start, index - start)] uppercaseString];
}

static NSArray<NSString *> *ALNMigrationTopLevelStatements(NSString *sql) {
  if (![sql isKindOfClass:[NSString class]] || [sql length] == 0) {
    return @[];
  }

  NSMutableArray<NSString *> *statements = [NSMutableArray array];
  NSMutableString *current = [NSMutableString string];
  ALNMigrationSQLScanState state = ALNMigrationSQLScanStateDefault;
  NSUInteger blockCommentDepth = 0;
  NSString *dollarTag = nil;
  NSUInteger index = 0;
  NSUInteger length = [sql length];

  while (index < length) {
    if (state == ALNMigrationSQLScanStateDollarQuote) {
      NSUInteger tagLength = [dollarTag length];
      if (tagLength > 0 && (index + tagLength) <= length &&
          [[sql substringWithRange:NSMakeRange(index, tagLength)] isEqualToString:dollarTag]) {
        [current appendString:dollarTag];
        index += tagLength;
        state = ALNMigrationSQLScanStateDefault;
        dollarTag = nil;
        continue;
      }
      [current appendFormat:@"%C", [sql characterAtIndex:index]];
      index += 1;
      continue;
    }

    unichar character = [sql characterAtIndex:index];
    if (state == ALNMigrationSQLScanStateDefault) {
      if (character == ';') {
        NSUInteger cursor = 0;
        if ([ALNMigrationNextIdentifierToken(current, &cursor) length] > 0) {
          [statements addObject:[NSString stringWithString:current]];
        }
        [current setString:@""];
        index += 1;
        continue;
      }
      if (character == '-' && (index + 1) < length && [sql characterAtIndex:(index + 1)] == '-') {
        [current appendString:@"--"];
        index += 2;
        state = ALNMigrationSQLScanStateLineComment;
        continue;
      }
      if (character == '/' && (index + 1) < length && [sql characterAtIndex:(index + 1)] == '*') {
        [current appendString:@"/*"];
        index += 2;
        blockCommentDepth = 1;
        state = ALNMigrationSQLScanStateBlockComment;
        continue;
      }
      if (character == '\'') {
        [current appendString:@"'"];
        index += 1;
        state = ALNMigrationSQLScanStateSingleQuote;
        continue;
      }
      if (character == '"') {
        [current appendString:@"\""];
        index += 1;
        state = ALNMigrationSQLScanStateDoubleQuote;
        continue;
      }
      NSUInteger tagLength = 0;
      NSString *tag = ALNMigrationDollarQuoteTagAtIndex(sql, index, &tagLength);
      if ([tag length] > 0) {
        [current appendString:tag];
        index += tagLength;
        state = ALNMigrationSQLScanStateDollarQuote;
        dollarTag = tag;
        continue;
      }
      [current appendFormat:@"%C", character];
      index += 1;
      continue;
    }

    if (state == ALNMigrationSQLScanStateSingleQuote) {
      [current appendFormat:@"%C", character];
      index += 1;
      if (character == '\'') {
        if (index < length && [sql characterAtIndex:index] == '\'') {
          [current appendString:@"'"];
          index += 1;
        } else {
          state = ALNMigrationSQLScanStateDefault;
        }
      }
      continue;
    }

    if (state == ALNMigrationSQLScanStateDoubleQuote) {
      [current appendFormat:@"%C", character];
      index += 1;
      if (character == '"') {
        if (index < length && [sql characterAtIndex:index] == '"') {
          [current appendString:@"\""];
          index += 1;
        } else {
          state = ALNMigrationSQLScanStateDefault;
        }
      }
      continue;
    }

    if (state == ALNMigrationSQLScanStateLineComment) {
      [current appendFormat:@"%C", character];
      index += 1;
      if (character == '\n') {
        state = ALNMigrationSQLScanStateDefault;
      }
      continue;
    }

    [current appendFormat:@"%C", character];
    if (character == '/' && (index + 1) < length && [sql characterAtIndex:(index + 1)] == '*') {
      [current appendString:@"*"];
      index += 2;
      blockCommentDepth += 1;
      continue;
    }
    if (character == '*' && (index + 1) < length && [sql characterAtIndex:(index + 1)] == '/') {
      [current appendString:@"/"];
      index += 2;
      if (blockCommentDepth > 0) {
        blockCommentDepth -= 1;
      }
      if (blockCommentDepth == 0) {
        state = ALNMigrationSQLScanStateDefault;
      }
      continue;
    }
    index += 1;
  }

  NSUInteger cursor = 0;
  if ([ALNMigrationNextIdentifierToken(current, &cursor) length] > 0) {
    [statements addObject:[NSString stringWithString:current]];
  }
  return statements;
}

static NSString *ALNMigrationForbiddenTransactionControlToken(NSString *statement) {
  NSUInteger cursor = 0;
  NSString *firstToken = ALNMigrationNextIdentifierToken(statement, &cursor);
  if ([firstToken length] == 0) {
    return nil;
  }

  NSSet *forbiddenTokens = [NSSet setWithArray:@[
    @"ABORT",
    @"BEGIN",
    @"COMMIT",
    @"END",
    @"RELEASE",
    @"ROLLBACK",
    @"SAVEPOINT",
  ]];
  if ([forbiddenTokens containsObject:firstToken]) {
    return firstToken;
  }

  if ([firstToken isEqualToString:@"START"]) {
    NSString *secondToken = ALNMigrationNextIdentifierToken(statement, &cursor);
    if ([secondToken isEqualToString:@"TRANSACTION"] || [secondToken isEqualToString:@"WORK"]) {
      return [NSString stringWithFormat:@"%@ %@", firstToken, secondToken];
    }
  }
  if ([firstToken isEqualToString:@"SAVE"]) {
    NSString *secondToken = ALNMigrationNextIdentifierToken(statement, &cursor);
    if ([secondToken isEqualToString:@"TRAN"] || [secondToken isEqualToString:@"TRANSACTION"]) {
      return [NSString stringWithFormat:@"%@ %@", firstToken, secondToken];
    }
  }
  return nil;
}

static id<ALNSQLDialect> ALNMigrationDialectForDatabase(id<ALNDatabaseAdapter> database,
                                                        NSError **error) {
  if (database != nil && [database respondsToSelector:@selector(sqlDialect)]) {
    id<ALNSQLDialect> dialect = [database sqlDialect];
    if (dialect != nil) {
      return dialect;
    }
  }

  if (error != NULL) {
    *error = ALNMigrationError(
        @"database adapter does not expose a SQL dialect",
        @"implement ALNDatabaseAdapter -sqlDialect to enable generic migration workflows");
  }
  return nil;
}

static NSString *ALNMigrationNormalizeSQLForDialect(NSString *sql, id<ALNSQLDialect> dialect) {
  NSString *dialectName =
      [dialect respondsToSelector:@selector(dialectName)] ? [dialect dialectName] : @"";
  if (![dialectName isEqualToString:@"mssql"]) {
    return sql ?: @"";
  }

  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  NSArray<NSString *> *rawLines =
      [(sql ?: @"") componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  for (NSString *line in rawLines) {
    NSString *normalizedLine = line ?: @"";
    NSString *candidate = [normalizedLine stringByTrimmingCharactersInSet:
                                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSRange commentRange = [candidate rangeOfString:@"--"];
    if (commentRange.location != NSNotFound) {
      candidate = [[candidate substringToIndex:commentRange.location]
          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }

    NSArray<NSString *> *rawTokens =
        [candidate componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray<NSString *> *tokens = [NSMutableArray arrayWithCapacity:[rawTokens count]];
    for (NSString *token in rawTokens) {
      if ([token length] > 0) {
        [tokens addObject:token];
      }
    }

    BOOL isGoBatchSeparator = NO;
    if ([tokens count] == 1) {
      isGoBatchSeparator = [[tokens[0] uppercaseString] isEqualToString:@"GO"];
    } else if ([tokens count] == 2) {
      NSString *command = [tokens[0] uppercaseString];
      NSString *repeatCount = tokens[1];
      NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
      isGoBatchSeparator = [command isEqualToString:@"GO"] &&
                           [repeatCount length] > 0 &&
                           [[repeatCount stringByTrimmingCharactersInSet:digits] length] == 0;
    }

    if (isGoBatchSeparator) {
      [lines addObject:@";"];
    } else {
      [lines addObject:normalizedLine];
    }
  }
  return [lines componentsJoinedByString:@"\n"];
}

static NSArray<NSString *> *ALNMigrationStatementsForDialect(NSString *sql,
                                                             id<ALNSQLDialect> dialect) {
  return ALNMigrationTopLevelStatements(ALNMigrationNormalizeSQLForDialect(sql, dialect));
}

static NSError *ALNMigrationApplyError(NSString *migrationPath, NSError *underlyingError) {
  NSString *name = [[migrationPath lastPathComponent] length] > 0 ? [migrationPath lastPathComponent]
                                                                  : (migrationPath ?: @"migration");
  NSString *message = [NSString stringWithFormat:@"failed applying migration %@", name];
  NSString *detail = ALNMigrationComposedDetail(underlyingError);
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message;
  if ([detail length] > 0) {
    userInfo[@"detail"] = detail;
  }
  userInfo[@"path"] = migrationPath ?: @"";
  if (underlyingError != nil) {
    userInfo[NSUnderlyingErrorKey] = underlyingError;
  }
  return [NSError errorWithDomain:ALNMigrationRunnerErrorDomain code:1 userInfo:userInfo];
}

static NSError *ALNMigrationValidationError(NSString *migrationPath,
                                            NSString *message,
                                            NSString *detail) {
  return ALNMigrationApplyError(migrationPath, ALNMigrationError(message, detail));
}

@implementation ALNMigrationRunner

+ (NSString *)normalizedDatabaseTarget:(NSString *)databaseTarget {
  NSString *normalized =
      [databaseTarget isKindOfClass:[NSString class]]
          ? [[databaseTarget stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                lowercaseString]
          : @"";
  if ([normalized length] == 0) {
    return ALNMigrationRunnerDefaultDatabaseTarget;
  }
  return normalized;
}

+ (BOOL)isSafeDatabaseTarget:(NSString *)databaseTarget {
  if (![databaseTarget isKindOfClass:[NSString class]] || [databaseTarget length] == 0) {
    return NO;
  }
  if ([databaseTarget length] > 32) {
    return NO;
  }
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"];
  if ([[databaseTarget stringByTrimmingCharactersInSet:allowed] length] > 0) {
    return NO;
  }
  unichar first = [databaseTarget characterAtIndex:0];
  return ([[NSCharacterSet letterCharacterSet] characterIsMember:first] || first == '_');
}

+ (nullable NSString *)migrationsTableNameForDatabaseTarget:(NSString *)databaseTarget
                                                     error:(NSError **)error {
  NSString *normalized = [self normalizedDatabaseTarget:databaseTarget];
  if (![self isSafeDatabaseTarget:normalized]) {
    if (error != NULL) {
      *error = ALNMigrationError(
          @"database target must match [a-z][a-z0-9_]* and be <= 32 characters", normalized);
    }
    return nil;
  }
  if ([normalized isEqualToString:ALNMigrationRunnerDefaultDatabaseTarget]) {
    return @"arlen_schema_migrations";
  }
  return [NSString stringWithFormat:@"arlen_schema_migrations__%@", normalized];
}

+ (NSArray<NSString *> *)migrationFilesAtPath:(NSString *)migrationsPath
                                        error:(NSError **)error {
  if ([migrationsPath length] == 0) {
    if (error != NULL) {
      *error = ALNMigrationError(@"migrations path is required", nil);
    }
    return nil;
  }

  BOOL isDirectory = NO;
  if (![[NSFileManager defaultManager] fileExistsAtPath:migrationsPath isDirectory:&isDirectory] ||
      !isDirectory) {
    if (error != NULL) {
      *error = ALNMigrationError(@"migrations directory not found", migrationsPath);
    }
    return nil;
  }

  NSError *contentsError = nil;
  NSArray *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:migrationsPath
                                                                          error:&contentsError];
  if (entries == nil) {
    if (error != NULL) {
      *error = contentsError;
    }
    return nil;
  }

  NSMutableArray *files = [NSMutableArray array];
  for (NSString *entry in entries) {
    if (![[entry pathExtension] isEqualToString:@"sql"]) {
      continue;
    }
    NSString *fullPath = [migrationsPath stringByAppendingPathComponent:entry];
    BOOL childDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&childDirectory] &&
        !childDirectory) {
      [files addObject:fullPath];
    }
  }

  [files sortUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
    return [[left lastPathComponent] compare:[right lastPathComponent]];
  }];

  return files;
}

+ (NSString *)versionForMigrationFile:(NSString *)filePath {
  return [self versionForMigrationFile:filePath versionNamespace:nil];
}

+ (NSString *)versionForMigrationFile:(NSString *)filePath
                     versionNamespace:(NSString *)versionNamespace {
  NSString *name = [[filePath lastPathComponent] stringByDeletingPathExtension];
  NSString *trimmedNamespace =
      [versionNamespace stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmedNamespace length] == 0) {
    return [name copy] ?: @"";
  }
  return [NSString stringWithFormat:@"%@::%@", trimmedNamespace, name ?: @""];
}

+ (BOOL)ensureMigrationsTableWithDatabase:(id<ALNDatabaseAdapter>)database
                                  dialect:(id<ALNSQLDialect>)dialect
                                tableName:(NSString *)tableName
                                    error:(NSError **)error {
  NSString *sql = [dialect migrationStateTableCreateSQLForTableName:tableName error:error];
  if ([sql length] == 0) {
    return NO;
  }
  NSInteger affected = [database executeCommand:sql parameters:@[] error:error];
  return (affected >= 0);
}

+ (nullable NSSet *)appliedVersionSetWithDatabase:(id<ALNDatabaseAdapter>)database
                                          dialect:(id<ALNSQLDialect>)dialect
                                        tableName:(NSString *)tableName
                                            error:(NSError **)error {
  NSString *sql = [dialect migrationVersionsSelectSQLForTableName:tableName error:error];
  if ([sql length] == 0) {
    return nil;
  }
  NSArray *rows = [database executeQuery:sql parameters:@[] error:error];
  if (rows == nil) {
    return nil;
  }

  NSMutableSet *versions = [NSMutableSet setWithCapacity:[rows count]];
  for (NSDictionary *row in rows) {
    NSString *version = row[@"version"];
    if ([version isKindOfClass:[NSString class]] && [version length] > 0) {
      [versions addObject:version];
    }
  }
  return versions;
}

+ (NSArray<NSString *> *)pendingMigrationFilesAtPath:(NSString *)migrationsPath
                                             database:(id<ALNDatabaseAdapter>)database
                                       databaseTarget:(NSString *)databaseTarget
                                    versionNamespace:(NSString *)versionNamespace
                                               error:(NSError **)error {
  NSArray *allMigrations = [self migrationFilesAtPath:migrationsPath error:error];
  if (allMigrations == nil) {
    return nil;
  }

  NSString *tableName = [self migrationsTableNameForDatabaseTarget:databaseTarget error:error];
  if ([tableName length] == 0) {
    return nil;
  }

  id<ALNSQLDialect> dialect = ALNMigrationDialectForDatabase(database, error);
  if (dialect == nil) {
    return nil;
  }

  if (![self ensureMigrationsTableWithDatabase:database
                                       dialect:dialect
                                     tableName:tableName
                                         error:error]) {
    return nil;
  }

  NSSet *applied = [self appliedVersionSetWithDatabase:database
                                               dialect:dialect
                                             tableName:tableName
                                                 error:error];
  if (applied == nil) {
    return nil;
  }

  NSMutableArray *pending = [NSMutableArray array];
  for (NSString *file in allMigrations) {
    NSString *version = [self versionForMigrationFile:file versionNamespace:versionNamespace];
    if (![applied containsObject:version]) {
      [pending addObject:file];
    }
  }
  return pending;
}

+ (NSArray<NSString *> *)pendingMigrationFilesAtPath:(NSString *)migrationsPath
                                             database:(id<ALNDatabaseAdapter>)database
                                       databaseTarget:(NSString *)databaseTarget
                                                error:(NSError **)error {
  return [self pendingMigrationFilesAtPath:migrationsPath
                                  database:database
                            databaseTarget:databaseTarget
                         versionNamespace:nil
                                     error:error];
}

+ (BOOL)validateMigrationSQL:(NSString *)sql
                migrationPath:(NSString *)migrationPath
                     dialect:(id<ALNSQLDialect>)dialect
                        error:(NSError **)error {
  NSArray<NSString *> *statements = ALNMigrationStatementsForDialect(sql, dialect);
  if ([statements count] == 0) {
    if (error != NULL) {
      *error = ALNMigrationValidationError(migrationPath,
                                           @"migration file does not contain executable SQL",
                                           nil);
    }
    return NO;
  }

  for (NSString *statement in statements) {
    NSString *forbiddenToken = ALNMigrationForbiddenTransactionControlToken(statement);
    if ([forbiddenToken length] == 0) {
      continue;
    }
    if (error != NULL) {
      NSString *detail = [NSString stringWithFormat:
                                        @"top-level transaction control statement detected: %@",
                                        forbiddenToken];
      *error = ALNMigrationValidationError(
          migrationPath,
          @"migration file must not include top-level transaction control statements",
          detail);
    }
    return NO;
  }

  return YES;
}

+ (BOOL)applyMigrationsAtPath:(NSString *)migrationsPath
                     database:(id<ALNDatabaseAdapter>)database
               databaseTarget:(NSString *)databaseTarget
             versionNamespace:(NSString *)versionNamespace
                       dryRun:(BOOL)dryRun
                 appliedFiles:(NSArray<NSString *> **)appliedFiles
                        error:(NSError **)error {
  NSArray *pending = [self pendingMigrationFilesAtPath:migrationsPath
                                              database:database
                                        databaseTarget:databaseTarget
                                      versionNamespace:versionNamespace
                                                 error:error];
  if (pending == nil) {
    return NO;
  }

  NSString *tableName = [self migrationsTableNameForDatabaseTarget:databaseTarget error:error];
  if ([tableName length] == 0) {
    return NO;
  }

  id<ALNSQLDialect> dialect = ALNMigrationDialectForDatabase(database, error);
  if (dialect == nil) {
    return NO;
  }

  if (dryRun) {
    if (appliedFiles != NULL) {
      *appliedFiles = pending;
    }
    return YES;
  }

  NSMutableArray *applied = [NSMutableArray array];
  NSString *insertSQL = [dialect migrationVersionInsertSQLForTableName:tableName error:error];
  if ([insertSQL length] == 0) {
    return NO;
  }
  for (NSString *migrationPath in pending) {
    NSError *readError = nil;
    NSString *sql = [NSString stringWithContentsOfFile:migrationPath
                                              encoding:NSUTF8StringEncoding
                                                 error:&readError];
    if (sql == nil) {
      if (error != NULL) {
        *error = readError ?: ALNMigrationError(@"failed reading migration file", migrationPath);
      }
      return NO;
    }
    if (![self validateMigrationSQL:sql migrationPath:migrationPath dialect:dialect error:error]) {
      return NO;
    }

    NSString *version = [self versionForMigrationFile:migrationPath
                                     versionNamespace:versionNamespace];
    NSArray<NSString *> *statements = ALNMigrationStatementsForDialect(sql, dialect);
    NSError *transactionError = nil;
    BOOL appliedOK = [database withTransactionUsingBlock:^BOOL(id<ALNDatabaseConnection> connection,
                                                               NSError **blockError) {
      for (NSString *statement in statements) {
        NSInteger executed = [connection executeCommand:statement parameters:@[] error:blockError];
        if (executed < 0) {
          return NO;
        }
      }

      NSInteger inserted =
          [connection executeCommand:insertSQL parameters:@[ version ] error:blockError];
      if (inserted < 0) {
        return NO;
      }
      return YES;
    } error:&transactionError];

    if (!appliedOK) {
      if (error != NULL) {
        *error = ALNMigrationApplyError(migrationPath, transactionError);
      }
      return NO;
    }
    [applied addObject:migrationPath];
  }

  if (appliedFiles != NULL) {
    *appliedFiles = applied;
  }
  return YES;
}

+ (BOOL)applyMigrationsAtPath:(NSString *)migrationsPath
                     database:(id<ALNDatabaseAdapter>)database
               databaseTarget:(NSString *)databaseTarget
                       dryRun:(BOOL)dryRun
                 appliedFiles:(NSArray<NSString *> **)appliedFiles
                        error:(NSError **)error {
  return [self applyMigrationsAtPath:migrationsPath
                            database:database
                      databaseTarget:databaseTarget
                   versionNamespace:nil
                              dryRun:dryRun
                        appliedFiles:appliedFiles
                               error:error];
}

+ (nullable NSArray<NSString *> *)pendingMigrationFilesAtPath:(NSString *)migrationsPath
                                                      database:(id<ALNDatabaseAdapter>)database
                                                         error:(NSError **)error {
  return [self pendingMigrationFilesAtPath:migrationsPath
                                  database:database
                            databaseTarget:ALNMigrationRunnerDefaultDatabaseTarget
                                     error:error];
}

+ (BOOL)applyMigrationsAtPath:(NSString *)migrationsPath
                     database:(id<ALNDatabaseAdapter>)database
                       dryRun:(BOOL)dryRun
                 appliedFiles:(NSArray<NSString *> **)appliedFiles
                        error:(NSError **)error {
  return [self applyMigrationsAtPath:migrationsPath
                            database:database
                      databaseTarget:ALNMigrationRunnerDefaultDatabaseTarget
                              dryRun:dryRun
                        appliedFiles:appliedFiles
                               error:error];
}

@end

#import "ALNEOCTranspiler.h"

#import "ALNEOCRuntime.h"

typedef NS_ENUM(NSUInteger, ALNEOCTokenType) {
  ALNEOCTokenTypeText = 0,
  ALNEOCTokenTypeCode = 1,
  ALNEOCTokenTypeEscapedExpression = 2,
  ALNEOCTokenTypeRawExpression = 3,
  ALNEOCTokenTypeDirective = 4,
};

typedef NS_ENUM(NSUInteger, ALNEOCDirectiveKind) {
  ALNEOCDirectiveKindUnknown = 0,
  ALNEOCDirectiveKindLayout = 1,
  ALNEOCDirectiveKindRequires = 2,
  ALNEOCDirectiveKindYield = 3,
  ALNEOCDirectiveKindSlot = 4,
  ALNEOCDirectiveKindEndSlot = 5,
  ALNEOCDirectiveKindInclude = 6,
  ALNEOCDirectiveKindRender = 7,
};

static NSString *const ALNEOCTokenTypeKey = @"type";
static NSString *const ALNEOCTokenContentKey = @"content";
static NSString *const ALNEOCTokenLineKey = @"line";
static NSString *const ALNEOCTokenColumnKey = @"column";

static NSString *const ALNEOCDirectiveKindKey = @"kind";
static NSString *const ALNEOCDirectivePathKey = @"path";
static NSString *const ALNEOCDirectiveLocalsExpressionKey = @"locals_expression";
static NSString *const ALNEOCDirectiveCollectionExpressionKey = @"collection_expression";
static NSString *const ALNEOCDirectiveItemLocalNameKey = @"item_local_name";
static NSString *const ALNEOCDirectiveEmptyPathKey = @"empty_path";
static NSString *const ALNEOCDirectiveSlotNameKey = @"slot_name";
static NSString *const ALNEOCDirectiveRequiredLocalsKey = @"required_locals";
static NSString *const ALNEOCInternalDependencySitesKey = @"_dependency_sites";
static NSString *const ALNEOCInternalFilledSlotSitesKey = @"_filled_slot_sites";

NSString *const ALNEOCLintDiagnosticLevelKey = @"level";
NSString *const ALNEOCLintDiagnosticCodeKey = @"code";
NSString *const ALNEOCLintDiagnosticMessageKey = @"message";
NSString *const ALNEOCLintDiagnosticPathKey = @"path";
NSString *const ALNEOCLintDiagnosticLineKey = @"line";
NSString *const ALNEOCLintDiagnosticColumnKey = @"column";
NSString *const ALNEOCTemplateMetadataLayoutPathKey = @"layout_path";
NSString *const ALNEOCTemplateMetadataRequiredLocalsKey = @"required_locals";
NSString *const ALNEOCTemplateMetadataYieldSlotsKey = @"yield_slots";
NSString *const ALNEOCTemplateMetadataFilledSlotsKey = @"filled_slots";
NSString *const ALNEOCTemplateMetadataStaticDependenciesKey = @"static_dependencies";

@interface ALNEOCTranspiler ()

- (nullable NSArray *)tokensForTemplateString:(NSString *)templateText
                                  logicalPath:(NSString *)logicalPath
                                        error:(NSError *_Nullable *_Nullable)error;
- (BOOL)isSigilIdentifierStart:(unichar)character;
- (BOOL)isSigilIdentifierBody:(unichar)character;
- (nullable NSString *)rewriteSigilLocalsInContent:(NSString *)content
                                       logicalPath:(NSString *)logicalPath
                                          fromLine:(NSUInteger)line
                                            column:(NSUInteger)column
                                             error:(NSError *_Nullable *_Nullable)error;
- (NSArray<NSDictionary *> *)lintDiagnosticsForTokens:(NSArray *)tokens
                                           logicalPath:(NSString *)logicalPath;
- (nullable NSDictionary *)templateMetadataForTokens:(NSArray *)tokens
                                          logicalPath:(NSString *)logicalPath
                                                error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)parseDirectiveToken:(NSDictionary *)token
                                   logicalPath:(NSString *)logicalPath
                                         error:(NSError *_Nullable *_Nullable)error;
- (void)appendIncludeLintDiagnosticsForToken:(NSDictionary *)token
                                  logicalPath:(NSString *)logicalPath
                                  diagnostics:(NSMutableArray<NSDictionary *> *)diagnostics;
- (BOOL)isGuardedIncludeCallInContent:(NSString *)content atLocation:(NSUInteger)location;
- (BOOL)isWhitespaceCharacter:(unichar)character;
- (NSUInteger)skipWhitespaceInString:(NSString *)value fromIndex:(NSUInteger)index;
- (nullable NSString *)parseQuotedDirectiveStringFromContent:(NSString *)content
                                                       index:(NSUInteger *)index
                                                 logicalPath:(NSString *)logicalPath
                                                        line:(NSUInteger)line
                                                      column:(NSUInteger)column
                                                       error:(NSError *_Nullable *_Nullable)error;
- (nullable NSString *)parseDirectiveIdentifierFromContent:(NSString *)content
                                                     index:(NSUInteger *)index
                                               logicalPath:(NSString *)logicalPath
                                                      line:(NSUInteger)line
                                                    column:(NSUInteger)column
                                                     error:(NSError *_Nullable *_Nullable)error;
- (NSUInteger)topLevelKeywordLocation:(NSString *)keyword
                            inContent:(NSString *)content
                            fromIndex:(NSUInteger)index;
- (NSString *)normalizedDirectiveTemplateReference:(NSString *)value;
- (nullable NSDictionary *)directiveErrorWithMessage:(NSString *)message
                                         logicalPath:(NSString *)logicalPath
                                                line:(NSUInteger)line
                                              column:(NSUInteger)column
                                               error:(NSError *_Nullable *_Nullable)error;
- (void)advanceLine:(NSUInteger *)line
             column:(NSUInteger *)column
      forCharacter:(unichar)character;
- (void)advanceLine:(NSUInteger *)line
             column:(NSUInteger *)column
          forString:(NSString *)value;

@end

@implementation ALNEOCTranspiler

- (NSString *)symbolNameForLogicalPath:(NSString *)logicalPath {
  NSMutableString *symbol = [NSMutableString stringWithString:@"ALNEOCRender_"];
  NSUInteger length = [logicalPath length];
  for (NSUInteger idx = 0; idx < length; idx++) {
    unichar ch = [logicalPath characterAtIndex:idx];
    BOOL isAlphaNum = ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
                       (ch >= '0' && ch <= '9'));
    if (isAlphaNum) {
      [symbol appendFormat:@"%C", ch];
    } else {
      [symbol appendString:@"_"];
    }
  }
  return symbol;
}

- (NSString *)logicalPathForTemplatePath:(NSString *)templatePath
                             templateRoot:(NSString *)templateRoot {
  return [self logicalPathForTemplatePath:templatePath
                              templateRoot:templateRoot
                             logicalPrefix:nil];
}

- (NSString *)logicalPathForTemplatePath:(NSString *)templatePath
                             templateRoot:(NSString *)templateRoot
                            logicalPrefix:(NSString *)logicalPrefix {
  NSString *fullTemplate =
      [ALNEOCCanonicalTemplatePath([templatePath stringByStandardizingPath]) copy];
  NSString *resolved = nil;
  if (templateRoot == nil || [templateRoot length] == 0) {
    resolved = [templatePath lastPathComponent];
  } else {
    NSString *fullRoot =
        [ALNEOCCanonicalTemplatePath([templateRoot stringByStandardizingPath]) copy];
    NSString *rootWithSlash =
        [fullRoot hasSuffix:@"/"] ? fullRoot : [fullRoot stringByAppendingString:@"/"];
    if (![fullTemplate hasPrefix:rootWithSlash]) {
      resolved = [templatePath lastPathComponent];
    } else {
      NSString *relative = [fullTemplate substringFromIndex:[rootWithSlash length]];
      resolved = ALNEOCCanonicalTemplatePath(relative);
    }
  }

  NSString *prefix = [(logicalPrefix ?: @"")
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([prefix length] == 0) {
    return resolved;
  }
  prefix = ALNEOCCanonicalTemplatePath(prefix);
  if ([resolved length] == 0) {
    return prefix;
  }
  return [NSString stringWithFormat:@"%@/%@", prefix, resolved];
}

- (NSArray<NSDictionary *> *)lintDiagnosticsForTemplateString:(NSString *)templateText
                                                   logicalPath:(NSString *)logicalPath
                                                         error:(NSError **)error {
  NSArray *tokens = [self tokensForTemplateString:templateText
                                      logicalPath:logicalPath
                                            error:error];
  if (tokens == nil) {
    return nil;
  }
  return [self lintDiagnosticsForTokens:tokens logicalPath:logicalPath];
}

- (NSDictionary *)templateMetadataForTemplateString:(NSString *)templateText
                                        logicalPath:(NSString *)logicalPath
                                              error:(NSError **)error {
  NSArray *tokens = [self tokensForTemplateString:templateText
                                      logicalPath:logicalPath
                                            error:error];
  if (tokens == nil) {
    return nil;
  }
  return [self templateMetadataForTokens:tokens logicalPath:logicalPath error:error];
}

- (NSString *)transpiledSourceForTemplateString:(NSString *)templateText
                                    logicalPath:(NSString *)logicalPath
                                          error:(NSError **)error {
  NSArray *tokens = [self tokensForTemplateString:templateText
                                      logicalPath:logicalPath
                                            error:error];
  if (tokens == nil) {
    return nil;
  }
  NSDictionary *metadata = [self templateMetadataForTokens:tokens
                                               logicalPath:logicalPath
                                                     error:error];
  if (metadata == nil) {
    return nil;
  }

  NSString *symbol = [self symbolNameForLogicalPath:logicalPath];
  NSString *escapedPath = [logicalPath stringByReplacingOccurrencesOfString:@"\\"
                                                                  withString:@"\\\\"];
  escapedPath =
      [escapedPath stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
  NSString *layoutPath = [metadata[ALNEOCTemplateMetadataLayoutPathKey] isKindOfClass:[NSString class]]
                             ? metadata[ALNEOCTemplateMetadataLayoutPathKey]
                             : @"";
  NSString *escapedLayoutPath = [layoutPath stringByReplacingOccurrencesOfString:@"\\"
                                                                      withString:@"\\\\"];
  escapedLayoutPath =
      [escapedLayoutPath stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
  NSString *registrationSymbol =
      [NSString stringWithFormat:@"ALNEOCAutoRegister_%@", symbol];

  NSMutableString *source = [NSMutableString string];
  NSMutableArray<NSDictionary *> *slotStack = [NSMutableArray array];
  NSUInteger slotCounter = 0;

  [source appendString:@"#import <Foundation/Foundation.h>\n"];
  [source appendString:@"#import \"ALNEOCRuntime.h\"\n\n"];
  [source appendFormat:@"NSString *%@(id ctx, NSError **error) {\n", symbol];
  [source appendString:@"  NSMutableString *out = [NSMutableString string];\n"];
  [source appendString:@"  if (out == nil) {\n"];
  [source appendString:@"    if (error != NULL) {\n"];
  [source appendFormat:
              @"      *error = [NSError errorWithDomain:@\"%@\" code:%ld "
               "userInfo:@{NSLocalizedDescriptionKey: @\"Unable to allocate render "
               "buffer\"}];\n",
              ALNEOCErrorDomain, (long)ALNEOCErrorTemplateExecutionFailed];
  [source appendString:@"    }\n"];
  [source appendString:@"    return nil;\n"];
  [source appendString:@"  }\n"];
  [source appendString:@"\n"];

  for (NSDictionary *token in tokens) {
    NSUInteger line = [token[ALNEOCTokenLineKey] unsignedIntegerValue];
    NSUInteger column = [token[ALNEOCTokenColumnKey] unsignedIntegerValue];
    NSUInteger type = [token[ALNEOCTokenTypeKey] unsignedIntegerValue];
    NSString *content = token[ALNEOCTokenContentKey];
    NSString *rewrittenContent = nil;

    [source appendFormat:@"#line %lu \"%@\"\n", (unsigned long)line, escapedPath];
    switch (type) {
    case ALNEOCTokenTypeText: {
      if ([content length] == 0) {
        [source appendString:@"\n"];
        break;
      }
      NSMutableString *literal = [NSMutableString string];
      NSUInteger length = [content length];
      for (NSUInteger idx = 0; idx < length; idx++) {
        unichar ch = [content characterAtIndex:idx];
        switch (ch) {
        case '\\':
          [literal appendString:@"\\\\"];
          break;
        case '"':
          [literal appendString:@"\\\""];
          break;
        case '\n':
          [literal appendString:@"\\n"];
          break;
        case '\r':
          [literal appendString:@"\\r"];
          break;
        case '\t':
          [literal appendString:@"\\t"];
          break;
        default:
          [literal appendFormat:@"%C", ch];
          break;
        }
      }
      [source appendFormat:@"ALNEOCAppendRaw(out, @\"%@\");\n\n", literal];
      break;
    }
    case ALNEOCTokenTypeCode:
      rewrittenContent = [self rewriteSigilLocalsInContent:content
                                                logicalPath:logicalPath
                                                   fromLine:line
                                                     column:column
                                                      error:error];
      if (rewrittenContent == nil) {
        return nil;
      }
      [source appendString:rewrittenContent];
      [source appendString:@"\n\n"];
      break;
    case ALNEOCTokenTypeEscapedExpression:
      rewrittenContent = [self rewriteSigilLocalsInContent:content
                                                logicalPath:logicalPath
                                                   fromLine:line
                                                     column:column
                                                      error:error];
      if (rewrittenContent == nil) {
        return nil;
      }
      [source appendFormat:
                  @"if (!ALNEOCAppendEscapedChecked(out, (%@), @\"%@\", %lu, %lu, "
                   "error)) { return nil; }\n\n",
                  rewrittenContent, escapedPath, (unsigned long)line,
                  (unsigned long)column];
      break;
    case ALNEOCTokenTypeRawExpression:
      rewrittenContent = [self rewriteSigilLocalsInContent:content
                                                logicalPath:logicalPath
                                                   fromLine:line
                                                     column:column
                                                      error:error];
      if (rewrittenContent == nil) {
        return nil;
      }
      [source appendFormat:
                  @"if (!ALNEOCAppendRawChecked(out, (%@), @\"%@\", %lu, %lu, "
                   "error)) { return nil; }\n\n",
                  rewrittenContent, escapedPath, (unsigned long)line,
                  (unsigned long)column];
      break;
    case ALNEOCTokenTypeDirective: {
      NSDictionary *directive =
          [self parseDirectiveToken:token logicalPath:logicalPath error:error];
      if (directive == nil) {
        return nil;
      }
      NSUInteger kind = [directive[ALNEOCDirectiveKindKey] unsignedIntegerValue];
      switch (kind) {
      case ALNEOCDirectiveKindLayout:
        [source appendString:@"\n"];
        break;
      case ALNEOCDirectiveKindRequires: {
        NSArray<NSString *> *requiredLocals = directive[ALNEOCDirectiveRequiredLocalsKey];
        NSMutableArray<NSString *> *escapedLocals = [NSMutableArray array];
        for (NSString *name in requiredLocals ?: @[]) {
          NSString *escapedLocal =
              [name stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
          [escapedLocals addObject:[NSString stringWithFormat:@"@\"%@\"", escapedLocal]];
        }
        NSString *localArray = [escapedLocals count] > 0
                                   ? [NSString stringWithFormat:@"@[ %@ ]",
                                                              [escapedLocals componentsJoinedByString:@", "]]
                                   : @"@[]";
        [source appendFormat:
                    @"if (!ALNEOCEnsureRequiredLocals(ctx, %@, @\"%@\", %lu, %lu, "
                     "error)) { return nil; }\n\n",
                    localArray,
                    escapedPath,
                    (unsigned long)line,
                    (unsigned long)column];
        break;
      }
      case ALNEOCDirectiveKindYield: {
        NSString *slotName = directive[ALNEOCDirectiveSlotNameKey] ?: @"content";
        NSString *escapedSlot =
            [slotName stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        [source appendFormat:
                    @"if (!ALNEOCAppendYield(out, ctx, @\"%@\", @\"%@\", %lu, %lu, "
                     "error)) { return nil; }\n\n",
                    escapedSlot,
                    escapedPath,
                    (unsigned long)line,
                    (unsigned long)column];
        break;
      }
      case ALNEOCDirectiveKindSlot: {
        slotCounter += 1;
        NSString *slotName = directive[ALNEOCDirectiveSlotNameKey] ?: @"";
        NSString *bufferName =
            [NSString stringWithFormat:@"ALNEOCSlotBuffer_%lu", (unsigned long)slotCounter];
        NSString *previousOutName =
            [NSString stringWithFormat:@"ALNEOCPreviousOut_%lu", (unsigned long)slotCounter];
        [slotStack addObject:@{
          ALNEOCDirectiveSlotNameKey : slotName,
          @"buffer_name" : bufferName,
          @"previous_out_name" : previousOutName,
          ALNEOCTokenLineKey : @(line),
          ALNEOCTokenColumnKey : @(column)
        }];
        [source appendFormat:@"NSMutableString *%@ = [NSMutableString string];\n", bufferName];
        [source appendString:[NSString stringWithFormat:@"if (%@ == nil) { return nil; }\n",
                                                        bufferName]];
        [source appendFormat:@"NSMutableString *%@ = out;\n", previousOutName];
        [source appendFormat:@"out = %@;\n\n", bufferName];
        break;
      }
      case ALNEOCDirectiveKindEndSlot: {
        NSDictionary *slotContext = [slotStack lastObject];
        if (slotContext == nil) {
          if (error != NULL) {
            *error = [NSError
                errorWithDomain:ALNEOCErrorDomain
                           code:ALNEOCErrorTranspilerSyntax
                       userInfo:@{
                         NSLocalizedDescriptionKey : @"Unexpected endslot directive",
                         ALNEOCErrorLineKey : @(line),
                         ALNEOCErrorColumnKey : @(column),
                         ALNEOCErrorPathKey : logicalPath ?: @""
                       }];
          }
          return nil;
        }
        [slotStack removeLastObject];
        NSString *slotName = slotContext[ALNEOCDirectiveSlotNameKey] ?: @"";
        NSString *bufferName = slotContext[@"buffer_name"] ?: @"";
        NSString *previousOutName = slotContext[@"previous_out_name"] ?: @"";
        NSString *escapedSlot =
            [slotName stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        [source appendFormat:@"out = %@;\n", previousOutName];
        [source appendFormat:
                    @"if (!ALNEOCSetSlot(ctx, @\"%@\", %@, @\"%@\", %lu, %lu, "
                     "error)) { return nil; }\n\n",
                    escapedSlot,
                    bufferName,
                    escapedPath,
                    (unsigned long)line,
                    (unsigned long)column];
        break;
      }
      case ALNEOCDirectiveKindInclude: {
        NSString *path = directive[ALNEOCDirectivePathKey] ?: @"";
        NSString *escapedDirectivePath =
            [path stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        NSString *localsExpression = directive[ALNEOCDirectiveLocalsExpressionKey];
        NSString *rewrittenLocals = @"nil";
        if ([localsExpression length] > 0) {
          rewrittenLocals = [self rewriteSigilLocalsInContent:localsExpression
                                                  logicalPath:logicalPath
                                                     fromLine:line
                                                       column:column
                                                        error:error];
          if (rewrittenLocals == nil) {
            return nil;
          }
        }
        [source appendFormat:
                    @"if (!ALNEOCIncludeWithLocals(out, ctx, @\"%@\", (%@), @\"%@\", "
                     "%lu, %lu, error)) { return nil; }\n\n",
                    escapedDirectivePath,
                    rewrittenLocals,
                    escapedPath,
                    (unsigned long)line,
                    (unsigned long)column];
        break;
      }
      case ALNEOCDirectiveKindRender: {
        NSString *path = directive[ALNEOCDirectivePathKey] ?: @"";
        NSString *escapedDirectivePath =
            [path stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        NSString *emptyPath = directive[ALNEOCDirectiveEmptyPathKey] ?: @"";
        NSString *escapedEmptyPath =
            [emptyPath stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        NSString *collectionExpression =
            directive[ALNEOCDirectiveCollectionExpressionKey] ?: @"";
        NSString *itemLocalName = directive[ALNEOCDirectiveItemLocalNameKey] ?: @"";
        NSString *escapedItemLocal =
            [itemLocalName stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        NSString *rewrittenCollection = [self rewriteSigilLocalsInContent:collectionExpression
                                                              logicalPath:logicalPath
                                                                 fromLine:line
                                                                   column:column
                                                                    error:error];
        if (rewrittenCollection == nil) {
          return nil;
        }
        NSString *localsExpression = directive[ALNEOCDirectiveLocalsExpressionKey];
        NSString *rewrittenLocals = @"nil";
        if ([localsExpression length] > 0) {
          rewrittenLocals = [self rewriteSigilLocalsInContent:localsExpression
                                                  logicalPath:logicalPath
                                                     fromLine:line
                                                       column:column
                                                        error:error];
          if (rewrittenLocals == nil) {
            return nil;
          }
        }
        [source appendFormat:
                    @"if (!ALNEOCRenderCollection(out, ctx, @\"%@\", (%@), @\"%@\", "
                     "@\"%@\", (%@), @\"%@\", %lu, %lu, error)) { return nil; }\n\n",
                    escapedDirectivePath,
                    rewrittenCollection,
                    escapedItemLocal,
                    escapedEmptyPath,
                    rewrittenLocals,
                    escapedPath,
                    (unsigned long)line,
                    (unsigned long)column];
        break;
      }
      default:
        break;
      }
      break;
    }
    default:
      break;
    }
  }

  if ([slotStack count] > 0) {
    NSDictionary *slotContext = [slotStack lastObject];
    NSUInteger slotLine = [slotContext[ALNEOCTokenLineKey] unsignedIntegerValue];
    NSUInteger slotColumn = [slotContext[ALNEOCTokenColumnKey] unsignedIntegerValue];
    if (error != NULL) {
      *error = [NSError
          errorWithDomain:ALNEOCErrorDomain
                     code:ALNEOCErrorTranspilerSyntax
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Unclosed slot directive",
                   ALNEOCErrorLineKey : @(slotLine),
                   ALNEOCErrorColumnKey : @(slotColumn),
                   ALNEOCErrorPathKey : logicalPath ?: @""
                 }];
    }
    return nil;
  }

  [source appendString:@"  return [NSString stringWithString:out];\n"];
  [source appendString:@"}\n\n"];
  [source appendString:@"__attribute__((constructor))\n"];
  [source appendFormat:@"static void %@ (void) {\n", registrationSymbol];
  [source appendFormat:@"  ALNEOCRegisterTemplate(@\"%@\", &%@);\n", escapedPath, symbol];
  if ([escapedLayoutPath length] > 0) {
    [source appendFormat:@"  ALNEOCRegisterTemplateLayout(@\"%@\", @\"%@\");\n",
                         escapedPath,
                         escapedLayoutPath];
  }
  [source appendString:@"}\n"];
  return source;
}

- (BOOL)transpileTemplateAtPath:(NSString *)templatePath
                   templateRoot:(NSString *)templateRoot
                     outputPath:(NSString *)outputPath
                          error:(NSError **)error {
  return [self transpileTemplateAtPath:templatePath
                          templateRoot:templateRoot
                         logicalPrefix:nil
                            outputPath:outputPath
                                 error:error];
}

- (BOOL)transpileTemplateAtPath:(NSString *)templatePath
                   templateRoot:(NSString *)templateRoot
                  logicalPrefix:(NSString *)logicalPrefix
                     outputPath:(NSString *)outputPath
                          error:(NSError **)error {
  NSError *readError = nil;
  NSString *template = [NSString stringWithContentsOfFile:templatePath
                                                 encoding:NSUTF8StringEncoding
                                                    error:&readError];
  if (template == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNEOCErrorDomain
                                   code:ALNEOCErrorFileIO
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                   [NSString stringWithFormat:@"Unable to read template: %@",
                                                              templatePath],
                                 NSUnderlyingErrorKey : readError ?: [NSNull null],
                                 ALNEOCErrorPathKey : templatePath
                               }];
    }
    return NO;
  }

  NSString *logicalPath =
      [self logicalPathForTemplatePath:templatePath
                           templateRoot:templateRoot
                          logicalPrefix:logicalPrefix];
  NSString *generated = [self transpiledSourceForTemplateString:template
                                                    logicalPath:logicalPath
                                                          error:error];
  if (generated == nil) {
    return NO;
  }

  NSString *directory = [outputPath stringByDeletingLastPathComponent];
  if ([directory length] > 0) {
    NSError *mkdirError = nil;
    BOOL created = [[NSFileManager defaultManager]
        createDirectoryAtPath:directory
   withIntermediateDirectories:YES
                    attributes:nil
                         error:&mkdirError];
    if (!created) {
      if (error != NULL) {
        *error = [NSError errorWithDomain:ALNEOCErrorDomain
                                     code:ALNEOCErrorFileIO
                                 userInfo:@{
                                   NSLocalizedDescriptionKey :
                                     [NSString stringWithFormat:
                                                   @"Unable to create output "
                                                    "directory: %@",
                                                   directory],
                                   NSUnderlyingErrorKey : mkdirError ?: [NSNull null],
                                   ALNEOCErrorPathKey : directory
                                 }];
      }
      return NO;
    }
  }

  NSError *writeError = nil;
  BOOL wrote = [generated writeToFile:outputPath
                           atomically:YES
                             encoding:NSUTF8StringEncoding
                                error:&writeError];
  if (!wrote) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNEOCErrorDomain
                                   code:ALNEOCErrorFileIO
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                   [NSString stringWithFormat:@"Unable to write output: %@",
                                                              outputPath],
                                 NSUnderlyingErrorKey : writeError ?: [NSNull null],
                                 ALNEOCErrorPathKey : outputPath
                               }];
    }
    return NO;
  }
  return YES;
}

- (NSArray *)tokensForTemplateString:(NSString *)templateText
                         logicalPath:(NSString *)logicalPath
                               error:(NSError **)error {
  NSMutableArray *tokens = [NSMutableArray array];

  NSUInteger index = 0;
  NSUInteger line = 1;
  NSUInteger column = 1;
  NSUInteger length = [templateText length];

  while (index < length) {
    NSRange searchRange = NSMakeRange(index, length - index);
    NSRange openTag = [templateText rangeOfString:@"<%" options:0 range:searchRange];

    if (openTag.location == NSNotFound) {
      NSString *tail = [templateText substringFromIndex:index];
      if ([tail length] > 0) {
        [tokens addObject:@{
          ALNEOCTokenTypeKey : @(ALNEOCTokenTypeText),
          ALNEOCTokenContentKey : tail,
          ALNEOCTokenLineKey : @(line),
          ALNEOCTokenColumnKey : @(column)
        }];
      }
      [self advanceLine:&line column:&column forString:tail];
      index = length;
      break;
    }

    if (openTag.location > index) {
      NSString *textChunk =
          [templateText substringWithRange:NSMakeRange(index, openTag.location - index)];
      [tokens addObject:@{
        ALNEOCTokenTypeKey : @(ALNEOCTokenTypeText),
        ALNEOCTokenContentKey : textChunk,
        ALNEOCTokenLineKey : @(line),
        ALNEOCTokenColumnKey : @(column)
      }];
      [self advanceLine:&line column:&column forString:textChunk];
      index = openTag.location;
    }

    NSUInteger tagStartLine = line;
    NSUInteger tagStartColumn = column;

    [self advanceLine:&line column:&column forString:@"<%"];
    index += 2;

    if (index >= length) {
      if (error != NULL) {
        *error = [NSError
            errorWithDomain:ALNEOCErrorDomain
                       code:ALNEOCErrorTranspilerSyntax
                   userInfo:@{
                     NSLocalizedDescriptionKey : @"Unclosed EOC tag",
                     ALNEOCErrorLineKey : @(tagStartLine),
                     ALNEOCErrorColumnKey : @(tagStartColumn),
                     ALNEOCErrorPathKey : logicalPath ?: @""
                   }];
      }
      return nil;
    }

    ALNEOCTokenType tokenType = ALNEOCTokenTypeCode;
    unichar kind = [templateText characterAtIndex:index];
    if (kind == '=') {
      if (index + 1 < length && [templateText characterAtIndex:index + 1] == '=') {
        tokenType = ALNEOCTokenTypeRawExpression;
        [self advanceLine:&line column:&column forString:@"=="];
        index += 2;
      } else {
        tokenType = ALNEOCTokenTypeEscapedExpression;
        [self advanceLine:&line column:&column forString:@"="];
        index += 1;
      }
    } else if (kind == '#') {
      tokenType = NSNotFound;
      [self advanceLine:&line column:&column forString:@"#"];
      index += 1;
    } else if (kind == '@') {
      tokenType = ALNEOCTokenTypeDirective;
      [self advanceLine:&line column:&column forString:@"@"];
      index += 1;
    }

    NSUInteger contentStart = index;
    NSUInteger contentLine = line;
    NSUInteger contentColumn = column;

    BOOL foundClose = NO;
    NSUInteger closeIndex = index;
    while (closeIndex + 1 < length) {
      unichar current = [templateText characterAtIndex:closeIndex];
      unichar next = [templateText characterAtIndex:closeIndex + 1];
      if (current == '%' && next == '>') {
        foundClose = YES;
        break;
      }
      [self advanceLine:&line column:&column forCharacter:current];
      closeIndex += 1;
    }

    if (!foundClose) {
      if (error != NULL) {
        *error = [NSError
            errorWithDomain:ALNEOCErrorDomain
                       code:ALNEOCErrorTranspilerSyntax
                   userInfo:@{
                     NSLocalizedDescriptionKey : @"Unclosed EOC tag",
                     ALNEOCErrorLineKey : @(tagStartLine),
                     ALNEOCErrorColumnKey : @(tagStartColumn),
                     ALNEOCErrorPathKey : logicalPath ?: @""
                   }];
      }
      return nil;
    }

    NSString *content = [templateText
        substringWithRange:NSMakeRange(contentStart, closeIndex - contentStart)];

    if (tokenType != NSNotFound) {
      if (tokenType == ALNEOCTokenTypeEscapedExpression ||
          tokenType == ALNEOCTokenTypeRawExpression) {
        content =
            [content stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([content length] == 0) {
          if (error != NULL) {
            *error = [NSError
                errorWithDomain:ALNEOCErrorDomain
                           code:ALNEOCErrorTranspilerSyntax
                       userInfo:@{
                         NSLocalizedDescriptionKey : @"Expression tag cannot be empty",
                         ALNEOCErrorLineKey : @(contentLine),
                         ALNEOCErrorColumnKey : @(contentColumn),
                         ALNEOCErrorPathKey : logicalPath ?: @""
                       }];
          }
          return nil;
        }
      }

      [tokens addObject:@{
        ALNEOCTokenTypeKey : @(tokenType),
        ALNEOCTokenContentKey : content ?: @"",
        ALNEOCTokenLineKey : @(contentLine),
        ALNEOCTokenColumnKey : @(contentColumn)
      }];
    }

    [self advanceLine:&line column:&column forString:@"%>"];
    index = closeIndex + 2;
  }

  return tokens;
}

- (NSArray<NSDictionary *> *)lintDiagnosticsForTokens:(NSArray *)tokens
                                           logicalPath:(NSString *)logicalPath {
  NSMutableArray<NSDictionary *> *diagnostics = [NSMutableArray array];

  for (NSDictionary *token in tokens) {
    NSUInteger type = [token[ALNEOCTokenTypeKey] unsignedIntegerValue];
    if (type != ALNEOCTokenTypeCode) {
      continue;
    }
    [self appendIncludeLintDiagnosticsForToken:token
                                   logicalPath:logicalPath
                                   diagnostics:diagnostics];
  }

  return [NSArray arrayWithArray:diagnostics];
}

- (NSDictionary *)templateMetadataForTokens:(NSArray *)tokens
                                logicalPath:(NSString *)logicalPath
                                      error:(NSError **)error {
  NSMutableSet<NSString *> *requiredLocals = [NSMutableSet set];
  NSMutableSet<NSString *> *yieldSlots = [NSMutableSet set];
  NSMutableSet<NSString *> *filledSlots = [NSMutableSet set];
  NSMutableSet<NSString *> *dependencies = [NSMutableSet set];
  NSMutableArray<NSDictionary *> *dependencySites = [NSMutableArray array];
  NSMutableArray<NSDictionary *> *filledSlotSites = [NSMutableArray array];
  NSString *layoutPath = nil;

  for (NSDictionary *token in tokens) {
    NSUInteger type = [token[ALNEOCTokenTypeKey] unsignedIntegerValue];
    if (type != ALNEOCTokenTypeDirective) {
      continue;
    }

    NSDictionary *directive = [self parseDirectiveToken:token
                                            logicalPath:logicalPath
                                                  error:error];
    if (directive == nil) {
      return nil;
    }

    NSUInteger kind = [directive[ALNEOCDirectiveKindKey] unsignedIntegerValue];
    NSUInteger line = [token[ALNEOCTokenLineKey] unsignedIntegerValue];
    NSUInteger column = [token[ALNEOCTokenColumnKey] unsignedIntegerValue];
    switch (kind) {
    case ALNEOCDirectiveKindLayout: {
      NSString *candidate = directive[ALNEOCDirectivePathKey];
      if ([layoutPath length] > 0 && ![layoutPath isEqualToString:candidate]) {
        [self directiveErrorWithMessage:@"Multiple layout directives are not allowed"
                            logicalPath:logicalPath
                                   line:line
                                 column:column
                                  error:error];
        return nil;
      }
      layoutPath = candidate;
      if ([candidate length] > 0) {
        [dependencies addObject:candidate];
        [dependencySites addObject:@{
          @"path" : candidate,
          @"kind" : @"layout",
          ALNEOCTokenLineKey : @(line),
          ALNEOCTokenColumnKey : @(column)
        }];
      }
      break;
    }
    case ALNEOCDirectiveKindRequires:
      [requiredLocals addObjectsFromArray:directive[ALNEOCDirectiveRequiredLocalsKey] ?: @[]];
      break;
    case ALNEOCDirectiveKindYield: {
      NSString *slot = directive[ALNEOCDirectiveSlotNameKey] ?: @"content";
      if ([slot length] > 0) {
        [yieldSlots addObject:slot];
      }
      break;
    }
    case ALNEOCDirectiveKindSlot: {
      NSString *slot = directive[ALNEOCDirectiveSlotNameKey] ?: @"";
      if ([slot length] > 0) {
        [filledSlots addObject:slot];
        [filledSlotSites addObject:@{
          @"slot_name" : slot,
          ALNEOCTokenLineKey : @(line),
          ALNEOCTokenColumnKey : @(column)
        }];
      }
      break;
    }
    case ALNEOCDirectiveKindInclude: {
      NSString *path = directive[ALNEOCDirectivePathKey] ?: @"";
      if ([path length] > 0) {
        [dependencies addObject:path];
        [dependencySites addObject:@{
          @"path" : path,
          @"kind" : @"include",
          ALNEOCTokenLineKey : @(line),
          ALNEOCTokenColumnKey : @(column)
        }];
      }
      break;
    }
    case ALNEOCDirectiveKindRender: {
      NSString *path = directive[ALNEOCDirectivePathKey] ?: @"";
      NSString *emptyPath = directive[ALNEOCDirectiveEmptyPathKey] ?: @"";
      if ([path length] > 0) {
        [dependencies addObject:path];
        [dependencySites addObject:@{
          @"path" : path,
          @"kind" : @"render",
          ALNEOCTokenLineKey : @(line),
          ALNEOCTokenColumnKey : @(column)
        }];
      }
      if ([emptyPath length] > 0) {
        [dependencies addObject:emptyPath];
        [dependencySites addObject:@{
          @"path" : emptyPath,
          @"kind" : @"render_empty",
          ALNEOCTokenLineKey : @(line),
          ALNEOCTokenColumnKey : @(column)
        }];
      }
      break;
    }
    default:
      break;
    }
  }

  NSArray *sortedRequiredLocals =
      [[requiredLocals allObjects] sortedArrayUsingSelector:@selector(compare:)];
  NSArray *sortedYieldSlots =
      [[yieldSlots allObjects] sortedArrayUsingSelector:@selector(compare:)];
  NSArray *sortedFilledSlots =
      [[filledSlots allObjects] sortedArrayUsingSelector:@selector(compare:)];
  NSArray *sortedDependencies =
      [[dependencies allObjects] sortedArrayUsingSelector:@selector(compare:)];

  NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
  if ([layoutPath length] > 0) {
    metadata[ALNEOCTemplateMetadataLayoutPathKey] = layoutPath;
  }
  metadata[ALNEOCTemplateMetadataRequiredLocalsKey] = sortedRequiredLocals ?: @[];
  metadata[ALNEOCTemplateMetadataYieldSlotsKey] = sortedYieldSlots ?: @[];
  metadata[ALNEOCTemplateMetadataFilledSlotsKey] = sortedFilledSlots ?: @[];
  metadata[ALNEOCTemplateMetadataStaticDependenciesKey] = sortedDependencies ?: @[];
  metadata[ALNEOCInternalDependencySitesKey] = dependencySites ?: @[];
  metadata[ALNEOCInternalFilledSlotSitesKey] = filledSlotSites ?: @[];
  return [NSDictionary dictionaryWithDictionary:metadata];
}

- (NSDictionary *)parseDirectiveToken:(NSDictionary *)token
                          logicalPath:(NSString *)logicalPath
                                error:(NSError **)error {
  NSString *content = [token[ALNEOCTokenContentKey] isKindOfClass:[NSString class]]
                          ? token[ALNEOCTokenContentKey]
                          : @"";
  NSUInteger line = [token[ALNEOCTokenLineKey] unsignedIntegerValue];
  NSUInteger column = [token[ALNEOCTokenColumnKey] unsignedIntegerValue];
  NSUInteger index = [self skipWhitespaceInString:content fromIndex:0];
  NSUInteger contentLength = [content length];

  if (index >= contentLength) {
    [self directiveErrorWithMessage:@"Empty EOC directive"
                        logicalPath:logicalPath
                               line:line
                             column:column
                              error:error];
    return nil;
  }

  NSUInteger nameStart = index;
  while (index < contentLength &&
         [self isSigilIdentifierBody:[content characterAtIndex:index]]) {
    index += 1;
  }
  if (nameStart == index) {
    [self directiveErrorWithMessage:@"Invalid EOC directive"
                        logicalPath:logicalPath
                               line:line
                             column:column
                              error:error];
    return nil;
  }

  NSString *name = [[content substringWithRange:NSMakeRange(nameStart, index - nameStart)]
      lowercaseString];

  if ([name isEqualToString:@"layout"]) {
    index = [self skipWhitespaceInString:content fromIndex:index];
    NSString *path = [self parseQuotedDirectiveStringFromContent:content
                                                           index:&index
                                                     logicalPath:logicalPath
                                                            line:line
                                                          column:column
                                                           error:error];
    if (path == nil) {
      return nil;
    }
    index = [self skipWhitespaceInString:content fromIndex:index];
    if (index != contentLength) {
      [self directiveErrorWithMessage:@"Unexpected content after layout directive"
                          logicalPath:logicalPath
                                 line:line
                               column:column
                                error:error];
      return nil;
    }
    return @{
      ALNEOCDirectiveKindKey : @(ALNEOCDirectiveKindLayout),
      ALNEOCDirectivePathKey : [self normalizedDirectiveTemplateReference:path]
    };
  }

  if ([name isEqualToString:@"requires"]) {
    NSMutableArray<NSString *> *locals = [NSMutableArray array];
    while (YES) {
      index = [self skipWhitespaceInString:content fromIndex:index];
      NSString *identifier = [self parseDirectiveIdentifierFromContent:content
                                                                 index:&index
                                                           logicalPath:logicalPath
                                                                  line:line
                                                                column:column
                                                                 error:error];
      if (identifier == nil) {
        return nil;
      }
      [locals addObject:identifier];
      index = [self skipWhitespaceInString:content fromIndex:index];
      if (index >= contentLength) {
        break;
      }
      if ([content characterAtIndex:index] != ',') {
        [self directiveErrorWithMessage:@"Expected ',' between required locals"
                            logicalPath:logicalPath
                                   line:line
                                 column:column
                                  error:error];
        return nil;
      }
      index += 1;
    }
    return @{
      ALNEOCDirectiveKindKey : @(ALNEOCDirectiveKindRequires),
      ALNEOCDirectiveRequiredLocalsKey : locals
    };
  }

  if ([name isEqualToString:@"yield"]) {
    index = [self skipWhitespaceInString:content fromIndex:index];
    NSString *slot = @"content";
    if (index < contentLength) {
      slot = [self parseQuotedDirectiveStringFromContent:content
                                                   index:&index
                                             logicalPath:logicalPath
                                                    line:line
                                                  column:column
                                                   error:error];
      if (slot == nil) {
        return nil;
      }
      index = [self skipWhitespaceInString:content fromIndex:index];
      if (index != contentLength) {
        [self directiveErrorWithMessage:@"Unexpected content after yield directive"
                            logicalPath:logicalPath
                                   line:line
                                 column:column
                                  error:error];
        return nil;
      }
    }
    return @{
      ALNEOCDirectiveKindKey : @(ALNEOCDirectiveKindYield),
      ALNEOCDirectiveSlotNameKey : slot ?: @"content"
    };
  }

  if ([name isEqualToString:@"slot"]) {
    index = [self skipWhitespaceInString:content fromIndex:index];
    NSString *slot = [self parseQuotedDirectiveStringFromContent:content
                                                           index:&index
                                                     logicalPath:logicalPath
                                                            line:line
                                                          column:column
                                                           error:error];
    if (slot == nil) {
      return nil;
    }
    index = [self skipWhitespaceInString:content fromIndex:index];
    if (index != contentLength) {
      [self directiveErrorWithMessage:@"Unexpected content after slot directive"
                          logicalPath:logicalPath
                                 line:line
                               column:column
                                error:error];
      return nil;
    }
    return @{
      ALNEOCDirectiveKindKey : @(ALNEOCDirectiveKindSlot),
      ALNEOCDirectiveSlotNameKey : slot
    };
  }

  if ([name isEqualToString:@"endslot"]) {
    index = [self skipWhitespaceInString:content fromIndex:index];
    if (index != contentLength) {
      [self directiveErrorWithMessage:@"Unexpected content after endslot directive"
                          logicalPath:logicalPath
                                 line:line
                               column:column
                                error:error];
      return nil;
    }
    return @{
      ALNEOCDirectiveKindKey : @(ALNEOCDirectiveKindEndSlot),
    };
  }

  if ([name isEqualToString:@"include"]) {
    index = [self skipWhitespaceInString:content fromIndex:index];
    NSString *path = [self parseQuotedDirectiveStringFromContent:content
                                                           index:&index
                                                     logicalPath:logicalPath
                                                            line:line
                                                          column:column
                                                           error:error];
    if (path == nil) {
      return nil;
    }

    index = [self skipWhitespaceInString:content fromIndex:index];
    NSString *localsExpression = nil;
    if (index < contentLength) {
      if ((contentLength - index) < (NSUInteger)4 ||
          ![[content substringWithRange:NSMakeRange(index, 4)] isEqualToString:@"with"]) {
        [self directiveErrorWithMessage:@"Expected 'with' in include directive"
                            logicalPath:logicalPath
                                   line:line
                                 column:column
                                  error:error];
        return nil;
      }
      index += 4;
      index = [self skipWhitespaceInString:content fromIndex:index];
      localsExpression =
          [[content substringFromIndex:index]
              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([localsExpression length] == 0) {
        [self directiveErrorWithMessage:@"Include directive 'with' expression cannot be empty"
                            logicalPath:logicalPath
                                   line:line
                                 column:column
                                  error:error];
        return nil;
      }
    }

    return @{
      ALNEOCDirectiveKindKey : @(ALNEOCDirectiveKindInclude),
      ALNEOCDirectivePathKey : [self normalizedDirectiveTemplateReference:path],
      ALNEOCDirectiveLocalsExpressionKey : localsExpression ?: @""
    };
  }

  if ([name isEqualToString:@"render"]) {
    index = [self skipWhitespaceInString:content fromIndex:index];
    NSString *path = [self parseQuotedDirectiveStringFromContent:content
                                                           index:&index
                                                     logicalPath:logicalPath
                                                            line:line
                                                          column:column
                                                           error:error];
    if (path == nil) {
      return nil;
    }

    index = [self skipWhitespaceInString:content fromIndex:index];
    if ((contentLength - index) < (NSUInteger)11 ||
        ![[content substringWithRange:NSMakeRange(index, 11)] isEqualToString:@"collection:"]) {
      [self directiveErrorWithMessage:@"Render directive requires collection:<expr>"
                          logicalPath:logicalPath
                                 line:line
                               column:column
                                error:error];
      return nil;
    }
    index += 11;

    NSUInteger asLocation = [self topLevelKeywordLocation:@"as:"
                                                inContent:content
                                                fromIndex:index];
    if (asLocation == NSNotFound) {
      [self directiveErrorWithMessage:@"Render directive requires as:\"item\""
                          logicalPath:logicalPath
                                 line:line
                               column:column
                                error:error];
      return nil;
    }

    NSString *collectionExpression =
        [[content substringWithRange:NSMakeRange(index, asLocation - index)]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([collectionExpression length] == 0) {
      [self directiveErrorWithMessage:@"Render directive collection expression cannot be empty"
                          logicalPath:logicalPath
                                 line:line
                               column:column
                                error:error];
      return nil;
    }

    index = asLocation + 3;
    index = [self skipWhitespaceInString:content fromIndex:index];
    NSString *itemLocalName = [self parseQuotedDirectiveStringFromContent:content
                                                                    index:&index
                                                              logicalPath:logicalPath
                                                                     line:line
                                                                   column:column
                                                                    error:error];
    if (itemLocalName == nil) {
      return nil;
    }

    NSString *emptyPath = @"";
    NSString *localsExpression = @"";
    while (YES) {
      index = [self skipWhitespaceInString:content fromIndex:index];
      if (index >= contentLength) {
        break;
      }
      if ((contentLength - index) >= (NSUInteger)6 &&
          [[content substringWithRange:NSMakeRange(index, 6)] isEqualToString:@"empty:"]) {
        index += 6;
        index = [self skipWhitespaceInString:content fromIndex:index];
        NSString *parsedEmptyPath =
            [self parseQuotedDirectiveStringFromContent:content
                                                  index:&index
                                            logicalPath:logicalPath
                                                   line:line
                                                 column:column
                                                  error:error];
        if (parsedEmptyPath == nil) {
          return nil;
        }
        emptyPath = [self normalizedDirectiveTemplateReference:parsedEmptyPath];
        continue;
      }

      if ((contentLength - index) >= (NSUInteger)4 &&
          [[content substringWithRange:NSMakeRange(index, 4)] isEqualToString:@"with"]) {
        index += 4;
        index = [self skipWhitespaceInString:content fromIndex:index];
        localsExpression =
            [[content substringFromIndex:index]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([localsExpression length] == 0) {
          [self directiveErrorWithMessage:@"Render directive 'with' expression cannot be empty"
                              logicalPath:logicalPath
                                     line:line
                                   column:column
                                    error:error];
          return nil;
        }
        index = contentLength;
        break;
      }

      [self directiveErrorWithMessage:@"Unexpected render directive argument"
                          logicalPath:logicalPath
                                 line:line
                               column:column
                                error:error];
      return nil;
    }

    return @{
      ALNEOCDirectiveKindKey : @(ALNEOCDirectiveKindRender),
      ALNEOCDirectivePathKey : [self normalizedDirectiveTemplateReference:path],
      ALNEOCDirectiveCollectionExpressionKey : collectionExpression,
      ALNEOCDirectiveItemLocalNameKey : itemLocalName,
      ALNEOCDirectiveEmptyPathKey : emptyPath ?: @"",
      ALNEOCDirectiveLocalsExpressionKey : localsExpression ?: @""
    };
  }

  [self directiveErrorWithMessage:@"Unknown EOC directive"
                      logicalPath:logicalPath
                             line:line
                           column:column
                            error:error];
  return nil;
}

- (void)appendIncludeLintDiagnosticsForToken:(NSDictionary *)token
                                  logicalPath:(NSString *)logicalPath
                                  diagnostics:(NSMutableArray<NSDictionary *> *)diagnostics {
  NSString *content = [token[ALNEOCTokenContentKey] isKindOfClass:[NSString class]]
                          ? token[ALNEOCTokenContentKey]
                          : @"";
  if ([content length] == 0) {
    return;
  }

  NSUInteger tokenLine = [token[ALNEOCTokenLineKey] unsignedIntegerValue];
  NSUInteger tokenColumn = [token[ALNEOCTokenColumnKey] unsignedIntegerValue];
  NSRange searchRange = NSMakeRange(0, [content length]);

  while (searchRange.location < [content length]) {
    NSRange match = [content rangeOfString:@"ALNEOCInclude("
                                   options:0
                                     range:searchRange];
    if (match.location == NSNotFound) {
      break;
    }

    if (![self isGuardedIncludeCallInContent:content atLocation:match.location]) {
      NSUInteger line = tokenLine;
      NSUInteger column = tokenColumn;
      if (match.location > 0) {
        NSString *prefix = [content substringToIndex:match.location];
        [self advanceLine:&line column:&column forString:prefix];
      }

      [diagnostics addObject:@{
        ALNEOCLintDiagnosticLevelKey : @"warning",
        ALNEOCLintDiagnosticCodeKey : @"unguarded_include",
        ALNEOCLintDiagnosticMessageKey :
            @"ALNEOCInclude return value should be checked; wrap include call in "
             @"if (!ALNEOCInclude(...)) { return nil; }",
        ALNEOCLintDiagnosticPathKey : logicalPath ?: @"",
        ALNEOCLintDiagnosticLineKey : @(line),
        ALNEOCLintDiagnosticColumnKey : @(column)
      }];
    }

    NSUInteger nextLocation = match.location + match.length;
    if (nextLocation >= [content length]) {
      break;
    }
    searchRange = NSMakeRange(nextLocation, [content length] - nextLocation);
  }
}

- (BOOL)isGuardedIncludeCallInContent:(NSString *)content atLocation:(NSUInteger)location {
  if ([content length] == 0 || location == 0 || location > [content length]) {
    return NO;
  }

  NSInteger scan = (NSInteger)location - 1;
  while (scan >= 0 &&
         [self isWhitespaceCharacter:[content characterAtIndex:(NSUInteger)scan]]) {
    scan -= 1;
  }

  BOOL hasInnerWrapper = NO;
  if (scan >= 0 && [content characterAtIndex:(NSUInteger)scan] == '(') {
    hasInnerWrapper = YES;
    scan -= 1;
    while (scan >= 0 &&
           [self isWhitespaceCharacter:[content characterAtIndex:(NSUInteger)scan]]) {
      scan -= 1;
    }
  }

  if (scan < 0 || [content characterAtIndex:(NSUInteger)scan] != '!') {
    return NO;
  }
  scan -= 1;

  while (scan >= 0 &&
         [self isWhitespaceCharacter:[content characterAtIndex:(NSUInteger)scan]]) {
    scan -= 1;
  }
  if (scan < 0 || [content characterAtIndex:(NSUInteger)scan] != '(') {
    return NO;
  }

  if (hasInnerWrapper) {
    // Covered pattern: if (!(ALNEOCInclude(...))).
  }
  scan -= 1;

  while (scan >= 0 &&
         [self isWhitespaceCharacter:[content characterAtIndex:(NSUInteger)scan]]) {
    scan -= 1;
  }
  if (scan < 1) {
    return NO;
  }
  if ([content characterAtIndex:(NSUInteger)(scan - 1)] != 'i' ||
      [content characterAtIndex:(NSUInteger)scan] != 'f') {
    return NO;
  }

  NSInteger beforeIndex = scan - 2;
  if (beforeIndex >= 0 &&
      [self isSigilIdentifierBody:[content characterAtIndex:(NSUInteger)beforeIndex]]) {
    return NO;
  }

  NSUInteger afterIndex = (NSUInteger)scan + 1;
  if (afterIndex < [content length] &&
      [self isSigilIdentifierBody:[content characterAtIndex:afterIndex]]) {
    return NO;
  }

  return YES;
}

- (BOOL)isWhitespaceCharacter:(unichar)character {
  switch (character) {
  case ' ':
  case '\t':
  case '\n':
  case '\r':
  case '\f':
  case '\v':
    return YES;
  default:
    return NO;
  }
}

- (NSUInteger)skipWhitespaceInString:(NSString *)value fromIndex:(NSUInteger)index {
  NSUInteger cursor = index;
  NSUInteger length = [value length];
  while (cursor < length && [self isWhitespaceCharacter:[value characterAtIndex:cursor]]) {
    cursor += 1;
  }
  return cursor;
}

- (NSString *)parseQuotedDirectiveStringFromContent:(NSString *)content
                                              index:(NSUInteger *)index
                                        logicalPath:(NSString *)logicalPath
                                               line:(NSUInteger)line
                                             column:(NSUInteger)column
                                              error:(NSError **)error {
  NSUInteger cursor = [self skipWhitespaceInString:content fromIndex:*index];
  if (cursor >= [content length] || [content characterAtIndex:cursor] != '"') {
    [self directiveErrorWithMessage:@"Expected quoted string in EOC directive"
                        logicalPath:logicalPath
                               line:line
                             column:column
                              error:error];
    return nil;
  }
  cursor += 1;
  NSMutableString *value = [NSMutableString string];
  while (cursor < [content length]) {
    unichar current = [content characterAtIndex:cursor];
    if (current == '\\') {
      cursor += 1;
      if (cursor >= [content length]) {
        [self directiveErrorWithMessage:@"Unterminated quoted string in EOC directive"
                            logicalPath:logicalPath
                                   line:line
                                 column:column
                                  error:error];
        return nil;
      }
      [value appendFormat:@"%C", [content characterAtIndex:cursor]];
      cursor += 1;
      continue;
    }
    if (current == '"') {
      cursor += 1;
      *index = cursor;
      return value;
    }
    [value appendFormat:@"%C", current];
    cursor += 1;
  }

  [self directiveErrorWithMessage:@"Unterminated quoted string in EOC directive"
                      logicalPath:logicalPath
                             line:line
                           column:column
                            error:error];
  return nil;
}

- (NSString *)parseDirectiveIdentifierFromContent:(NSString *)content
                                            index:(NSUInteger *)index
                                      logicalPath:(NSString *)logicalPath
                                             line:(NSUInteger)line
                                           column:(NSUInteger)column
                                            error:(NSError **)error {
  NSUInteger cursor = [self skipWhitespaceInString:content fromIndex:*index];
  if (cursor >= [content length] ||
      ![self isSigilIdentifierStart:[content characterAtIndex:cursor]]) {
    [self directiveErrorWithMessage:@"Expected identifier in EOC directive"
                        logicalPath:logicalPath
                               line:line
                             column:column
                              error:error];
    return nil;
  }

  NSUInteger start = cursor;
  while (cursor < [content length] &&
         [self isSigilIdentifierBody:[content characterAtIndex:cursor]]) {
    cursor += 1;
  }
  *index = cursor;
  return [content substringWithRange:NSMakeRange(start, cursor - start)];
}

- (NSUInteger)topLevelKeywordLocation:(NSString *)keyword
                            inContent:(NSString *)content
                            fromIndex:(NSUInteger)index {
  typedef NS_ENUM(NSUInteger, ALNEOCDirectiveParseState) {
    ALNEOCDirectiveParseStateNormal = 0,
    ALNEOCDirectiveParseStateSingleQuote = 1,
    ALNEOCDirectiveParseStateDoubleQuote = 2,
    ALNEOCDirectiveParseStateLineComment = 3,
    ALNEOCDirectiveParseStateBlockComment = 4,
  };

  ALNEOCDirectiveParseState state = ALNEOCDirectiveParseStateNormal;
  NSUInteger length = [content length];
  NSUInteger parenDepth = 0;
  NSUInteger bracketDepth = 0;
  NSUInteger braceDepth = 0;

  for (NSUInteger cursor = index; cursor < length; cursor++) {
    unichar current = [content characterAtIndex:cursor];

    if (state == ALNEOCDirectiveParseStateLineComment) {
      if (current == '\n') {
        state = ALNEOCDirectiveParseStateNormal;
      }
      continue;
    }
    if (state == ALNEOCDirectiveParseStateBlockComment) {
      if (current == '*' && (cursor + 1) < length &&
          [content characterAtIndex:cursor + 1] == '/') {
        cursor += 1;
        state = ALNEOCDirectiveParseStateNormal;
      }
      continue;
    }
    if (state == ALNEOCDirectiveParseStateSingleQuote ||
        state == ALNEOCDirectiveParseStateDoubleQuote) {
      if (current == '\\') {
        cursor += 1;
        continue;
      }
      if ((state == ALNEOCDirectiveParseStateSingleQuote && current == '\'') ||
          (state == ALNEOCDirectiveParseStateDoubleQuote && current == '"')) {
        state = ALNEOCDirectiveParseStateNormal;
      }
      continue;
    }

    if (current == '/' && (cursor + 1) < length) {
      unichar next = [content characterAtIndex:cursor + 1];
      if (next == '/') {
        cursor += 1;
        state = ALNEOCDirectiveParseStateLineComment;
        continue;
      }
      if (next == '*') {
        cursor += 1;
        state = ALNEOCDirectiveParseStateBlockComment;
        continue;
      }
    }

    if (current == '\'') {
      state = ALNEOCDirectiveParseStateSingleQuote;
      continue;
    }
    if (current == '"') {
      state = ALNEOCDirectiveParseStateDoubleQuote;
      continue;
    }

    switch (current) {
    case '(':
      parenDepth += 1;
      break;
    case ')':
      if (parenDepth > 0) {
        parenDepth -= 1;
      }
      break;
    case '[':
      bracketDepth += 1;
      break;
    case ']':
      if (bracketDepth > 0) {
        bracketDepth -= 1;
      }
      break;
    case '{':
      braceDepth += 1;
      break;
    case '}':
      if (braceDepth > 0) {
        braceDepth -= 1;
      }
      break;
    default:
      break;
    }

    if (parenDepth != 0 || bracketDepth != 0 || braceDepth != 0) {
      continue;
    }

    if ((cursor + [keyword length]) <= length &&
        [[content substringWithRange:NSMakeRange(cursor, [keyword length])]
            isEqualToString:keyword]) {
      NSInteger beforeIndex = (NSInteger)cursor - 1;
      if (beforeIndex >= 0 &&
          ![self isWhitespaceCharacter:[content characterAtIndex:(NSUInteger)beforeIndex]]) {
        continue;
      }
      return cursor;
    }
  }

  return NSNotFound;
}

- (NSString *)normalizedDirectiveTemplateReference:(NSString *)value {
  return ALNEOCNormalizeTemplateReference(value ?: @"");
}

- (NSDictionary *)directiveErrorWithMessage:(NSString *)message
                                logicalPath:(NSString *)logicalPath
                                       line:(NSUInteger)line
                                     column:(NSUInteger)column
                                      error:(NSError **)error {
  if (error != NULL) {
    *error = [NSError errorWithDomain:ALNEOCErrorDomain
                                 code:ALNEOCErrorTranspilerSyntax
                             userInfo:@{
                               NSLocalizedDescriptionKey : message ?: @"Invalid EOC directive",
                               ALNEOCErrorLineKey : @(line),
                               ALNEOCErrorColumnKey : @(column),
                               ALNEOCErrorPathKey : logicalPath ?: @""
                             }];
  }
  return nil;
}

- (BOOL)isSigilIdentifierStart:(unichar)character {
  if ((character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') || character == '_') {
    return YES;
  }
  return NO;
}

- (BOOL)isSigilIdentifierBody:(unichar)character {
  if ([self isSigilIdentifierStart:character] ||
      (character >= '0' && character <= '9')) {
    return YES;
  }
  return NO;
}

- (NSString *)rewriteSigilLocalsInContent:(NSString *)content
                              logicalPath:(NSString *)logicalPath
                                 fromLine:(NSUInteger)line
                                   column:(NSUInteger)column
                                    error:(NSError **)error {
  if ([content length] == 0) {
    return content ?: @"";
  }

  typedef NS_ENUM(NSUInteger, ALNEOCRewriteState) {
    ALNEOCRewriteStateNormal = 0,
    ALNEOCRewriteStateSingleQuote = 1,
    ALNEOCRewriteStateDoubleQuote = 2,
    ALNEOCRewriteStateLineComment = 3,
    ALNEOCRewriteStateBlockComment = 4,
  };

  NSString *escapedPath = [logicalPath stringByReplacingOccurrencesOfString:@"\\"
                                                                  withString:@"\\\\"];
  escapedPath =
      [escapedPath stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];

  NSMutableString *rewritten = [NSMutableString stringWithCapacity:[content length]];
  ALNEOCRewriteState state = ALNEOCRewriteStateNormal;
  NSUInteger index = 0;
  NSUInteger length = [content length];
  NSUInteger cursorLine = line;
  NSUInteger cursorColumn = column;

  while (index < length) {
    unichar current = [content characterAtIndex:index];

    if (state == ALNEOCRewriteStateLineComment) {
      [rewritten appendFormat:@"%C", current];
      [self advanceLine:&cursorLine column:&cursorColumn forCharacter:current];
      index += 1;
      if (current == '\n') {
        state = ALNEOCRewriteStateNormal;
      }
      continue;
    }

    if (state == ALNEOCRewriteStateBlockComment) {
      if (current == '*' && (index + 1) < length &&
          [content characterAtIndex:index + 1] == '/') {
        [rewritten appendString:@"*/"];
        [self advanceLine:&cursorLine column:&cursorColumn forString:@"*/"];
        index += 2;
        state = ALNEOCRewriteStateNormal;
        continue;
      }
      [rewritten appendFormat:@"%C", current];
      [self advanceLine:&cursorLine column:&cursorColumn forCharacter:current];
      index += 1;
      continue;
    }

    if (state == ALNEOCRewriteStateSingleQuote ||
        state == ALNEOCRewriteStateDoubleQuote) {
      [rewritten appendFormat:@"%C", current];
      [self advanceLine:&cursorLine column:&cursorColumn forCharacter:current];
      index += 1;

      if (current == '\\' && index < length) {
        unichar escaped = [content characterAtIndex:index];
        [rewritten appendFormat:@"%C", escaped];
        [self advanceLine:&cursorLine column:&cursorColumn forCharacter:escaped];
        index += 1;
        continue;
      }

      if ((state == ALNEOCRewriteStateSingleQuote && current == '\'') ||
          (state == ALNEOCRewriteStateDoubleQuote && current == '"')) {
        state = ALNEOCRewriteStateNormal;
      }
      continue;
    }

    if (current == '/' && (index + 1) < length) {
      unichar next = [content characterAtIndex:index + 1];
      if (next == '/') {
        [rewritten appendString:@"//"];
        [self advanceLine:&cursorLine column:&cursorColumn forString:@"//"];
        index += 2;
        state = ALNEOCRewriteStateLineComment;
        continue;
      }
      if (next == '*') {
        [rewritten appendString:@"/*"];
        [self advanceLine:&cursorLine column:&cursorColumn forString:@"/*"];
        index += 2;
        state = ALNEOCRewriteStateBlockComment;
        continue;
      }
    }

    if (current == '\'') {
      [rewritten appendString:@"'"];
      [self advanceLine:&cursorLine column:&cursorColumn forCharacter:current];
      index += 1;
      state = ALNEOCRewriteStateSingleQuote;
      continue;
    }

    if (current == '"') {
      [rewritten appendString:@"\""];
      [self advanceLine:&cursorLine column:&cursorColumn forCharacter:current];
      index += 1;
      state = ALNEOCRewriteStateDoubleQuote;
      continue;
    }

    if (current == '$') {
      if ((index + 1) >= length) {
        if (error != NULL) {
          *error = [NSError
              errorWithDomain:ALNEOCErrorDomain
                         code:ALNEOCErrorTranspilerSyntax
                     userInfo:@{
                       NSLocalizedDescriptionKey : @"Invalid sigil local",
                       ALNEOCErrorLineKey : @(cursorLine),
                       ALNEOCErrorColumnKey : @(cursorColumn),
                       ALNEOCErrorPathKey : logicalPath ?: @""
                     }];
        }
        return nil;
      }

      unichar next = [content characterAtIndex:index + 1];
      if (![self isSigilIdentifierStart:next]) {
        if (error != NULL) {
          *error = [NSError
              errorWithDomain:ALNEOCErrorDomain
                         code:ALNEOCErrorTranspilerSyntax
                     userInfo:@{
                       NSLocalizedDescriptionKey : @"Invalid sigil local",
                       ALNEOCErrorLineKey : @(cursorLine),
                       ALNEOCErrorColumnKey : @(cursorColumn),
                       ALNEOCErrorPathKey : logicalPath ?: @""
                     }];
        }
        return nil;
      }

      NSUInteger localLine = cursorLine;
      NSUInteger localColumn = cursorColumn;
      NSUInteger nameStart = index + 1;
      NSUInteger scan = nameStart;
      while (scan < length &&
             [self isSigilIdentifierBody:[content characterAtIndex:scan]]) {
        scan += 1;
      }

      while (scan < length && [content characterAtIndex:scan] == '.') {
        if ((scan + 1) >= length ||
            ![self isSigilIdentifierStart:[content characterAtIndex:scan + 1]]) {
          if (error != NULL) {
            *error = [NSError
                errorWithDomain:ALNEOCErrorDomain
                           code:ALNEOCErrorTranspilerSyntax
                       userInfo:@{
                         NSLocalizedDescriptionKey : @"Invalid sigil local",
                         ALNEOCErrorLineKey : @(cursorLine),
                         ALNEOCErrorColumnKey : @(cursorColumn),
                         ALNEOCErrorPathKey : logicalPath ?: @""
                       }];
          }
          return nil;
        }
        scan += 1;
        while (scan < length &&
               [self isSigilIdentifierBody:[content characterAtIndex:scan]]) {
          scan += 1;
        }
      }

      NSString *name =
          [content substringWithRange:NSMakeRange(nameStart, scan - nameStart)];
      NSString *escapedName =
          [name stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
      if ([name containsString:@"."]) {
        [rewritten appendFormat:
                      @"ALNEOCLocalPath(ctx, @\"%@\", @\"%@\", %lu, %lu, error)",
                      escapedName, escapedPath, (unsigned long)localLine,
                      (unsigned long)localColumn];
      } else {
        [rewritten appendFormat:@"ALNEOCLocal(ctx, @\"%@\", @\"%@\", %lu, %lu, error)",
                                escapedName, escapedPath, (unsigned long)localLine,
                                (unsigned long)localColumn];
      }

      for (NSUInteger consumed = index; consumed < scan; consumed++) {
        [self advanceLine:&cursorLine
                   column:&cursorColumn
            forCharacter:[content characterAtIndex:consumed]];
      }
      index = scan;
      continue;
    }

    [rewritten appendFormat:@"%C", current];
    [self advanceLine:&cursorLine column:&cursorColumn forCharacter:current];
    index += 1;
  }

  return rewritten;
}

- (void)advanceLine:(NSUInteger *)line
             column:(NSUInteger *)column
      forCharacter:(unichar)character {
  if (character == '\n') {
    *line += 1;
    *column = 1;
  } else {
    *column += 1;
  }
}

- (void)advanceLine:(NSUInteger *)line
             column:(NSUInteger *)column
          forString:(NSString *)value {
  NSUInteger length = [value length];
  for (NSUInteger idx = 0; idx < length; idx++) {
    [self advanceLine:line column:column forCharacter:[value characterAtIndex:idx]];
  }
}

@end

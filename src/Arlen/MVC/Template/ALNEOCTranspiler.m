#import "ALNEOCTranspiler.h"

#import "ALNEOCRuntime.h"

typedef NS_ENUM(NSUInteger, ALNEOCTokenType) {
  ALNEOCTokenTypeText = 0,
  ALNEOCTokenTypeCode = 1,
  ALNEOCTokenTypeEscapedExpression = 2,
  ALNEOCTokenTypeRawExpression = 3,
};

static NSString *const ALNEOCTokenTypeKey = @"type";
static NSString *const ALNEOCTokenContentKey = @"content";
static NSString *const ALNEOCTokenLineKey = @"line";
static NSString *const ALNEOCTokenColumnKey = @"column";

@interface ALNEOCTranspiler ()

- (nullable NSArray *)tokensForTemplateString:(NSString *)templateText
                                   logicalPath:(NSString *)logicalPath
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
  NSString *fullTemplate =
      [ALNEOCCanonicalTemplatePath([templatePath stringByStandardizingPath]) copy];
  if (templateRoot == nil || [templateRoot length] == 0) {
    return [templatePath lastPathComponent];
  }

  NSString *fullRoot =
      [ALNEOCCanonicalTemplatePath([templateRoot stringByStandardizingPath]) copy];
  NSString *rootWithSlash =
      [fullRoot hasSuffix:@"/"] ? fullRoot : [fullRoot stringByAppendingString:@"/"];
  if (![fullTemplate hasPrefix:rootWithSlash]) {
    return [templatePath lastPathComponent];
  }

  NSString *relative = [fullTemplate substringFromIndex:[rootWithSlash length]];
  return ALNEOCCanonicalTemplatePath(relative);
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

  NSString *symbol = [self symbolNameForLogicalPath:logicalPath];
  NSString *escapedPath = [logicalPath stringByReplacingOccurrencesOfString:@"\\"
                                                                  withString:@"\\\\"];
  escapedPath =
      [escapedPath stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];

  NSMutableString *source = [NSMutableString string];
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
    NSUInteger type = [token[ALNEOCTokenTypeKey] unsignedIntegerValue];
    NSString *content = token[ALNEOCTokenContentKey];

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
      [source appendString:content];
      [source appendString:@"\n\n"];
      break;
    case ALNEOCTokenTypeEscapedExpression:
      [source appendFormat:@"ALNEOCAppendEscaped(out, (%@));\n\n", content];
      break;
    case ALNEOCTokenTypeRawExpression:
      [source appendFormat:@"ALNEOCAppendRaw(out, (%@));\n\n", content];
      break;
    default:
      break;
    }
  }

  [source appendString:@"  return [NSString stringWithString:out];\n"];
  [source appendString:@"}\n"];
  return source;
}

- (BOOL)transpileTemplateAtPath:(NSString *)templatePath
                   templateRoot:(NSString *)templateRoot
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
      [self logicalPathForTemplatePath:templatePath templateRoot:templateRoot];
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

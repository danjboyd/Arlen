#import <Foundation/Foundation.h>
#import <openssl/sha.h>

#import "ALNEOCRuntime.h"
#import "ALNEOCTranspiler.h"

#ifndef NSJSONWritingSortedKeys
#define NSJSONWritingSortedKeys 0
#endif

static NSString *const ALNEOCInternalDependencySitesKey = @"_dependency_sites";
static NSString *const ALNEOCInternalFilledSlotSitesKey = @"_filled_slot_sites";
static NSString *const ALNEOCMetadataLineKey = @"line";
static NSString *const ALNEOCMetadataColumnKey = @"column";
static NSString *const ALNEOCManifestVersion = @"phase19-eocc-manifest-v1";

static void PrintUsage(void) {
  fprintf(stderr,
          "Usage:\n"
          "  eocc --template-root <dir> --output-dir <dir> "
          "[--manifest <file>] [--registry-out <file>] [--logical-prefix <prefix>] "
          "<template1.html.eoc> [template2 ...]\n");
}

static BOOL EnsureDirectory(NSString *path, NSError **error) {
  if ([path length] == 0) {
    return YES;
  }
  return [[NSFileManager defaultManager] createDirectoryAtPath:path
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:error];
}

static NSString *JoinPath(NSString *base, NSString *suffix) {
  if ([suffix hasPrefix:@"/"]) {
    suffix = [suffix substringFromIndex:1];
  }
  return [base stringByAppendingPathComponent:suffix];
}

static NSString *RegistryIdentifierComponent(NSString *value) {
  NSString *candidate = [value isKindOfClass:[NSString class]] ? value : @"";
  NSMutableString *identifier = [NSMutableString string];
  for (NSUInteger idx = 0; idx < [candidate length]; idx++) {
    unichar ch = [candidate characterAtIndex:idx];
    BOOL alnum = ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
                  (ch >= '0' && ch <= '9'));
    [identifier appendString:alnum ? [NSString stringWithCharacters:&ch length:1] : @"_"];
  }
  while ([identifier containsString:@"__"]) {
    [identifier replaceOccurrencesOfString:@"__"
                                withString:@"_"
                                   options:0
                                     range:NSMakeRange(0, [identifier length])];
  }
  if ([identifier length] == 0) {
    [identifier appendString:@"registry"];
  }
  unichar first = [identifier characterAtIndex:0];
  if (first >= '0' && first <= '9') {
    [identifier insertString:@"r_" atIndex:0];
  }
  return identifier;
}

static NSString *RegistrySymbolSuffix(NSString *registryOut, NSString *logicalPrefix) {
  NSString *seed = ([logicalPrefix length] > 0) ? logicalPrefix : [registryOut lastPathComponent];
  return RegistryIdentifierComponent(seed);
}

static NSString *RegistrySource(NSArray *entries, NSString *symbolSuffix) {
  NSString *registerSymbol =
      [NSString stringWithFormat:@"ALNEOCRegisterBuiltInTemplates_%@", RegistryIdentifierComponent(symbolSuffix)];
  NSString *constructorSymbol =
      [NSString stringWithFormat:@"ALNEOCAutoRegisterBuiltInTemplates_%@", RegistryIdentifierComponent(symbolSuffix)];
  NSMutableString *source = [NSMutableString string];
  [source appendString:@"#import <Foundation/Foundation.h>\n"];
  [source appendString:@"#import \"ALNEOCRuntime.h\"\n\n"];

  for (NSDictionary *entry in entries) {
    [source appendFormat:@"extern NSString *%@(id ctx, NSError **error);\n",
                         entry[@"symbol"]];
  }

  [source appendFormat:@"\nvoid %@ (void) {\n", registerSymbol];
  [source appendString:@"  static BOOL didRegister = NO;\n"];
  [source appendString:@"  if (didRegister) {\n"];
  [source appendString:@"    return;\n"];
  [source appendString:@"  }\n"];
  [source appendString:@"  didRegister = YES;\n"];
  for (NSDictionary *entry in entries) {
    [source appendFormat:@"  ALNEOCRegisterTemplate(@\"%@\", &%@);\n",
                         entry[@"logicalPath"], entry[@"symbol"]];
    NSString *layoutPath = [entry[@"layoutPath"] isKindOfClass:[NSString class]]
                               ? entry[@"layoutPath"]
                               : @"";
    if ([layoutPath length] > 0) {
      [source appendFormat:@"  ALNEOCRegisterTemplateLayout(@\"%@\", @\"%@\");\n",
                           entry[@"logicalPath"], layoutPath];
    }
  }
  [source appendString:@"}\n\n"];
  [source appendString:@"__attribute__((constructor))\n"];
  [source appendFormat:@"static void %@ (void) {\n", constructorSymbol];
  [source appendFormat:@"  %@();\n", registerSymbol];
  [source appendString:@"}\n"];
  return source;
}

static NSString *TemplateHash(NSString *templateText) {
  NSData *data = [templateText dataUsingEncoding:NSUTF8StringEncoding];
  unsigned char digest[SHA256_DIGEST_LENGTH];
  SHA256(data.bytes, (unsigned long)data.length, digest);
  NSMutableString *hash = [NSMutableString stringWithCapacity:SHA256_DIGEST_LENGTH * 2];
  for (NSUInteger idx = 0; idx < SHA256_DIGEST_LENGTH; idx++) {
    [hash appendFormat:@"%02x", digest[idx]];
  }
  return hash;
}

static BOOL WriteJSONDocument(NSDictionary *document, NSString *path, NSError **error) {
  NSString *directory = [path stringByDeletingLastPathComponent];
  if ([directory length] > 0) {
    if (!EnsureDirectory(directory, error)) {
      return NO;
    }
  }
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:document
                                                     options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                       error:error];
  if (jsonData == nil) {
    return NO;
  }
  return [jsonData writeToFile:path options:NSDataWritingAtomic error:error];
}

static NSDictionary *LoadManifestDocument(NSString *path, NSError **error) {
  if ([path length] == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
    return nil;
  }
  NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
  if (data == nil) {
    return nil;
  }
  id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
  if (![parsed isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNEOCErrorDomain
                                   code:ALNEOCErrorFileIO
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     [NSString stringWithFormat:@"Invalid manifest JSON at %@", path ?: @""],
                                 ALNEOCErrorPathKey : path ?: @""
                               }];
    }
    return nil;
  }
  NSDictionary *document = parsed;
  NSString *version = [document[@"version"] isKindOfClass:[NSString class]] ? document[@"version"] : @"";
  if ([version length] > 0 && ![version isEqualToString:ALNEOCManifestVersion]) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNEOCErrorDomain
                                   code:ALNEOCErrorFileIO
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     [NSString stringWithFormat:@"Unsupported manifest version at %@", path ?: @""],
                                 ALNEOCErrorPathKey : path ?: @""
                               }];
    }
    return nil;
  }
  return document;
}

static NSDictionary<NSString *, NSDictionary *> *ManifestEntriesByTemplatePath(NSDictionary *document) {
  NSArray *entries = [document[@"entries"] isKindOfClass:[NSArray class]] ? document[@"entries"] : @[];
  NSMutableDictionary<NSString *, NSDictionary *> *entriesByTemplatePath = [NSMutableDictionary dictionary];
  for (NSDictionary *entry in entries) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *templatePath = [entry[@"template_path"] isKindOfClass:[NSString class]] ? entry[@"template_path"] : @"";
    if ([templatePath length] == 0) {
      continue;
    }
    entriesByTemplatePath[templatePath] = entry;
  }
  return entriesByTemplatePath;
}

static NSArray<NSDictionary *> *SortedManifestEntries(NSArray<NSDictionary *> *entries) {
  return [entries sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    NSString *leftLogical = [left[@"logical_path"] isKindOfClass:[NSString class]] ? left[@"logical_path"] : @"";
    NSString *rightLogical = [right[@"logical_path"] isKindOfClass:[NSString class]] ? right[@"logical_path"] : @"";
    NSComparisonResult logicalCompare = [leftLogical compare:rightLogical];
    if (logicalCompare != NSOrderedSame) {
      return logicalCompare;
    }
    NSString *leftTemplate = [left[@"template_path"] isKindOfClass:[NSString class]] ? left[@"template_path"] : @"";
    NSString *rightTemplate = [right[@"template_path"] isKindOfClass:[NSString class]] ? right[@"template_path"] : @"";
    return [leftTemplate compare:rightTemplate];
  }];
}

static void PrintErrorWithLocation(NSError *error) {
  fprintf(stderr, "eocc: %s\n", [[error localizedDescription] UTF8String]);
  NSNumber *line = error.userInfo[ALNEOCErrorLineKey];
  NSNumber *column = error.userInfo[ALNEOCErrorColumnKey];
  NSString *path = error.userInfo[ALNEOCErrorPathKey];
  if (line != nil || column != nil || path != nil) {
    NSString *safePath = (path != nil) ? path : @"";
    NSString *safeLine = (line != nil) ? [line stringValue] : @"";
    NSString *safeColumn = (column != nil) ? [column stringValue] : @"";
    fprintf(stderr, "eocc: location path=%s line=%s column=%s\n",
            [safePath UTF8String], [safeLine UTF8String], [safeColumn UTF8String]);
  }
}

static void PrintLintDiagnostic(NSDictionary *diagnostic, NSString *fallbackPath) {
  NSString *path = [diagnostic[ALNEOCLintDiagnosticPathKey] isKindOfClass:[NSString class]]
                       ? diagnostic[ALNEOCLintDiagnosticPathKey]
                       : fallbackPath;
  NSString *line = [diagnostic[ALNEOCLintDiagnosticLineKey] respondsToSelector:@selector(stringValue)]
                       ? [diagnostic[ALNEOCLintDiagnosticLineKey] stringValue]
                       : @"";
  NSString *column =
      [diagnostic[ALNEOCLintDiagnosticColumnKey] respondsToSelector:@selector(stringValue)]
          ? [diagnostic[ALNEOCLintDiagnosticColumnKey] stringValue]
          : @"";
  NSString *code = [diagnostic[ALNEOCLintDiagnosticCodeKey] isKindOfClass:[NSString class]]
                       ? diagnostic[ALNEOCLintDiagnosticCodeKey]
                       : @"lint";
  NSString *message = [diagnostic[ALNEOCLintDiagnosticMessageKey] isKindOfClass:[NSString class]]
                          ? diagnostic[ALNEOCLintDiagnosticMessageKey]
                          : @"template lint warning";
  fprintf(stderr, "eocc: warning path=%s line=%s column=%s code=%s message=%s\n",
          [path UTF8String], [line UTF8String], [column UTF8String], [code UTF8String],
          [message UTF8String]);
}

static NSDictionary *DependencySiteForPath(NSDictionary *metadata, NSString *dependencyPath) {
  NSArray *sites = [metadata[ALNEOCInternalDependencySitesKey] isKindOfClass:[NSArray class]]
                       ? metadata[ALNEOCInternalDependencySitesKey]
                       : @[];
  for (NSDictionary *site in sites) {
    NSString *path = [site[@"path"] isKindOfClass:[NSString class]] ? site[@"path"] : @"";
    if ([path isEqualToString:(dependencyPath ?: @"")]) {
      return site;
    }
  }
  return nil;
}

static NSDictionary *FilledSlotSiteForName(NSDictionary *metadata, NSString *slotName) {
  NSArray *sites = [metadata[ALNEOCInternalFilledSlotSitesKey] isKindOfClass:[NSArray class]]
                       ? metadata[ALNEOCInternalFilledSlotSitesKey]
                       : @[];
  for (NSDictionary *site in sites) {
    NSString *current = [site[@"slot_name"] isKindOfClass:[NSString class]] ? site[@"slot_name"] : @"";
    if ([current isEqualToString:(slotName ?: @"")]) {
      return site;
    }
  }
  return nil;
}

static NSError *ValidationError(NSString *message,
                                NSString *logicalPath,
                                NSNumber *line,
                                NSNumber *column) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"Template validation failed";
  if ([logicalPath length] > 0) {
    userInfo[ALNEOCErrorPathKey] = logicalPath;
  }
  if (line != nil) {
    userInfo[ALNEOCErrorLineKey] = line;
  }
  if (column != nil) {
    userInfo[ALNEOCErrorColumnKey] = column;
  }
  return [NSError errorWithDomain:ALNEOCErrorDomain
                             code:ALNEOCErrorTranspilerSyntax
                         userInfo:userInfo];
}

static BOOL ValidateUnknownDependencies(NSDictionary *entriesByPath, NSError **error) {
  for (NSString *logicalPath in entriesByPath) {
    NSDictionary *entry = entriesByPath[logicalPath];
    NSDictionary *metadata = [entry[@"metadata"] isKindOfClass:[NSDictionary class]] ? entry[@"metadata"] : @{};
    NSArray *dependencies =
        [metadata[ALNEOCTemplateMetadataStaticDependenciesKey] isKindOfClass:[NSArray class]]
            ? metadata[ALNEOCTemplateMetadataStaticDependenciesKey]
            : @[];
    for (NSString *dependency in dependencies) {
      if (entriesByPath[dependency] != nil) {
        continue;
      }
      NSDictionary *site = DependencySiteForPath(metadata, dependency);
      NSNumber *line = [site[ALNEOCMetadataLineKey] isKindOfClass:[NSNumber class]]
                           ? site[ALNEOCMetadataLineKey]
                           : nil;
      NSNumber *column = [site[ALNEOCMetadataColumnKey] isKindOfClass:[NSNumber class]]
                             ? site[ALNEOCMetadataColumnKey]
                             : nil;
      NSString *kind = [site[@"kind"] isKindOfClass:[NSString class]] ? site[@"kind"] : @"dependency";
      NSString *message =
          [NSString stringWithFormat:@"Unknown static EOC %@: %@", kind, dependency];
      if (error != NULL) {
        *error = ValidationError(message, logicalPath, line, column);
      }
      return NO;
    }
  }
  return YES;
}

static BOOL DetectDependencyCycle(NSString *logicalPath,
                                  NSDictionary *entriesByPath,
                                  NSMutableSet<NSString *> *visiting,
                                  NSMutableSet<NSString *> *visited,
                                  NSMutableArray<NSString *> *stack,
                                  NSError **error) {
  if ([visited containsObject:logicalPath]) {
    return YES;
  }
  if ([visiting containsObject:logicalPath]) {
    return YES;
  }

  [visiting addObject:logicalPath];
  [stack addObject:logicalPath];

  NSDictionary *entry = entriesByPath[logicalPath];
  NSDictionary *metadata = [entry[@"metadata"] isKindOfClass:[NSDictionary class]] ? entry[@"metadata"] : @{};
  NSArray *dependencies =
      [metadata[ALNEOCTemplateMetadataStaticDependenciesKey] isKindOfClass:[NSArray class]]
          ? metadata[ALNEOCTemplateMetadataStaticDependenciesKey]
          : @[];

  for (NSString *dependency in dependencies) {
    if (entriesByPath[dependency] == nil) {
      continue;
    }
    if ([visiting containsObject:dependency]) {
      NSMutableArray<NSString *> *cycle = [NSMutableArray array];
      NSUInteger startIndex = [stack indexOfObject:dependency];
      if (startIndex == NSNotFound) {
        [cycle addObject:logicalPath];
      } else {
        [cycle addObjectsFromArray:[stack subarrayWithRange:NSMakeRange(startIndex, [stack count] - startIndex)]];
      }
      [cycle addObject:dependency];

      NSDictionary *site = DependencySiteForPath(metadata, dependency);
      NSNumber *line = [site[ALNEOCMetadataLineKey] isKindOfClass:[NSNumber class]]
                           ? site[ALNEOCMetadataLineKey]
                           : nil;
      NSNumber *column = [site[ALNEOCMetadataColumnKey] isKindOfClass:[NSNumber class]]
                             ? site[ALNEOCMetadataColumnKey]
                             : nil;
      NSString *message = [NSString
          stringWithFormat:@"Static EOC composition cycle detected: %@",
                           [cycle componentsJoinedByString:@" -> "]];
      if (error != NULL) {
        *error = ValidationError(message, logicalPath, line, column);
      }
      return NO;
    }
    if (!DetectDependencyCycle(dependency, entriesByPath, visiting, visited, stack, error)) {
      return NO;
    }
  }

  [stack removeLastObject];
  [visiting removeObject:logicalPath];
  [visited addObject:logicalPath];
  return YES;
}

static BOOL ValidateNoCompositionCycles(NSDictionary *entriesByPath, NSError **error) {
  NSMutableSet<NSString *> *visiting = [NSMutableSet set];
  NSMutableSet<NSString *> *visited = [NSMutableSet set];
  NSMutableArray<NSString *> *stack = [NSMutableArray array];

  NSArray<NSString *> *sortedPaths =
      [[entriesByPath allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *logicalPath in sortedPaths) {
    if (!DetectDependencyCycle(logicalPath,
                               entriesByPath,
                               visiting,
                               visited,
                               stack,
                               error)) {
      return NO;
    }
  }
  return YES;
}

static NSArray<NSDictionary *> *CrossTemplateWarnings(NSDictionary *entriesByPath) {
  NSMutableArray<NSDictionary *> *warnings = [NSMutableArray array];
  NSArray<NSString *> *sortedPaths =
      [[entriesByPath allKeys] sortedArrayUsingSelector:@selector(compare:)];

  for (NSString *logicalPath in sortedPaths) {
    NSDictionary *entry = entriesByPath[logicalPath];
    NSDictionary *metadata = [entry[@"metadata"] isKindOfClass:[NSDictionary class]] ? entry[@"metadata"] : @{};
    NSArray *filledSlots = [metadata[ALNEOCTemplateMetadataFilledSlotsKey] isKindOfClass:[NSArray class]]
                               ? metadata[ALNEOCTemplateMetadataFilledSlotsKey]
                               : @[];
    if ([filledSlots count] == 0) {
      continue;
    }

    NSString *layoutPath = [metadata[ALNEOCTemplateMetadataLayoutPathKey] isKindOfClass:[NSString class]]
                               ? metadata[ALNEOCTemplateMetadataLayoutPathKey]
                               : @"";
    if ([layoutPath length] == 0) {
      for (NSString *slot in filledSlots) {
        NSDictionary *site = FilledSlotSiteForName(metadata, slot);
        [warnings addObject:@{
          ALNEOCLintDiagnosticLevelKey : @"warning",
          ALNEOCLintDiagnosticCodeKey : @"slot_without_layout",
          ALNEOCLintDiagnosticMessageKey :
              [NSString stringWithFormat:
                            @"Slot \"%@\" is filled but template has no static layout",
                            slot],
          ALNEOCLintDiagnosticPathKey : logicalPath,
          ALNEOCLintDiagnosticLineKey : site[ALNEOCMetadataLineKey] ?: @1,
          ALNEOCLintDiagnosticColumnKey : site[ALNEOCMetadataColumnKey] ?: @1
        }];
      }
      continue;
    }

    NSDictionary *layoutEntry = entriesByPath[layoutPath];
    NSDictionary *layoutMetadata =
        [layoutEntry[@"metadata"] isKindOfClass:[NSDictionary class]] ? layoutEntry[@"metadata"] : @{};
    NSSet *yieldSlots =
        [NSSet setWithArray:[layoutMetadata[ALNEOCTemplateMetadataYieldSlotsKey] isKindOfClass:[NSArray class]]
                              ? layoutMetadata[ALNEOCTemplateMetadataYieldSlotsKey]
                              : @[]];
    for (NSString *slot in filledSlots) {
      if ([yieldSlots containsObject:slot]) {
        continue;
      }
      NSDictionary *site = FilledSlotSiteForName(metadata, slot);
      [warnings addObject:@{
        ALNEOCLintDiagnosticLevelKey : @"warning",
        ALNEOCLintDiagnosticCodeKey : @"unused_slot_fill",
        ALNEOCLintDiagnosticMessageKey :
            [NSString stringWithFormat:
                          @"Slot \"%@\" is never yielded by layout %@",
                          slot,
                          layoutPath],
        ALNEOCLintDiagnosticPathKey : logicalPath,
        ALNEOCLintDiagnosticLineKey : site[ALNEOCMetadataLineKey] ?: @1,
        ALNEOCLintDiagnosticColumnKey : site[ALNEOCMetadataColumnKey] ?: @1
      }];
    }
  }

  return warnings;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSString *templateRoot = nil;
    NSString *outputDir = nil;
    NSString *manifestPath = nil;
    NSString *registryOut = nil;
    NSString *logicalPrefix = nil;
    NSMutableArray *templatePaths = [NSMutableArray array];

    for (int idx = 1; idx < argc; idx++) {
      NSString *arg = [NSString stringWithUTF8String:argv[idx]];
      if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
        PrintUsage();
        return 0;
      } else if ([arg isEqualToString:@"--template-root"]) {
        if (idx + 1 >= argc) {
          PrintUsage();
          return 2;
        }
        templateRoot = [NSString stringWithUTF8String:argv[++idx]];
      } else if ([arg isEqualToString:@"--output-dir"]) {
        if (idx + 1 >= argc) {
          PrintUsage();
          return 2;
        }
        outputDir = [NSString stringWithUTF8String:argv[++idx]];
      } else if ([arg isEqualToString:@"--manifest"]) {
        if (idx + 1 >= argc) {
          PrintUsage();
          return 2;
        }
        manifestPath = [NSString stringWithUTF8String:argv[++idx]];
      } else if ([arg isEqualToString:@"--registry-out"]) {
        if (idx + 1 >= argc) {
          PrintUsage();
          return 2;
        }
        registryOut = [NSString stringWithUTF8String:argv[++idx]];
      } else if ([arg isEqualToString:@"--logical-prefix"]) {
        if (idx + 1 >= argc) {
          PrintUsage();
          return 2;
        }
        logicalPrefix = [NSString stringWithUTF8String:argv[++idx]];
      } else {
        [templatePaths addObject:arg];
      }
    }

    if ([templateRoot length] == 0 || [outputDir length] == 0 ||
        [templatePaths count] == 0) {
      PrintUsage();
      return 2;
    }

    ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSDictionary *> *entriesByPath = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *currentTemplatePaths = [NSMutableSet set];
    NSMutableSet<NSString *> *changedTemplatePaths = [NSMutableSet set];
    NSUInteger transpiledCount = 0;
    NSUInteger reusedCount = 0;
    NSUInteger removedCount = 0;

    NSDictionary *cachedManifest = nil;
    NSDictionary<NSString *, NSDictionary *> *cachedEntriesByTemplatePath = @{};
    if ([manifestPath length] > 0) {
      NSError *manifestError = nil;
      cachedManifest = LoadManifestDocument(manifestPath, &manifestError);
      if (manifestError != nil) {
        PrintErrorWithLocation(manifestError);
        return 1;
      }
      if (cachedManifest != nil) {
        cachedEntriesByTemplatePath = ManifestEntriesByTemplatePath(cachedManifest);
      }
    }

    NSError *createError = nil;
    if (!EnsureDirectory(outputDir, &createError)) {
      fprintf(stderr, "eocc: unable to create output directory: %s\n",
              [[createError localizedDescription] UTF8String]);
      return 1;
    }

    for (NSString *templatePath in templatePaths) {
      [currentTemplatePaths addObject:templatePath];
      NSString *logicalPath =
          [transpiler logicalPathForTemplatePath:templatePath
                                     templateRoot:templateRoot
                                    logicalPrefix:logicalPrefix];
      NSString *outFile = JoinPath(outputDir, [logicalPath stringByAppendingString:@".m"]);

      NSError *readError = nil;
      NSString *templateText = [NSString stringWithContentsOfFile:templatePath
                                                         encoding:NSUTF8StringEncoding
                                                            error:&readError];
      if (templateText == nil) {
        NSError *error = [NSError errorWithDomain:ALNEOCErrorDomain
                                             code:ALNEOCErrorFileIO
                                         userInfo:@{
                                           NSLocalizedDescriptionKey :
                                               [NSString stringWithFormat:@"Unable to read template: %@",
                                                                          templatePath],
                                           NSUnderlyingErrorKey : readError ?: [NSNull null],
                                           ALNEOCErrorPathKey : templatePath
                                         }];
        PrintErrorWithLocation(error);
        return 1;
      }

      NSString *templateHash = TemplateHash(templateText);
      NSDictionary *cachedEntry = cachedEntriesByTemplatePath[templatePath];
      BOOL canReuse = NO;
      NSDictionary *metadata = nil;
      NSArray<NSDictionary *> *diagnostics = nil;
      if (cachedEntry != nil &&
          [cachedEntry[@"logical_path"] isKindOfClass:[NSString class]] &&
          [cachedEntry[@"logical_path"] isEqualToString:logicalPath] &&
          [cachedEntry[@"template_hash"] isKindOfClass:[NSString class]] &&
          [cachedEntry[@"template_hash"] isEqualToString:templateHash] &&
          [cachedEntry[@"output_path"] isKindOfClass:[NSString class]] &&
          [cachedEntry[@"output_path"] isEqualToString:outFile] &&
          [[NSFileManager defaultManager] fileExistsAtPath:outFile] &&
          [cachedEntry[@"metadata"] isKindOfClass:[NSDictionary class]] &&
          [cachedEntry[@"diagnostics"] isKindOfClass:[NSArray class]]) {
        canReuse = YES;
        metadata = cachedEntry[@"metadata"];
        diagnostics = cachedEntry[@"diagnostics"];
        reusedCount += 1;
      } else {
        NSError *metadataError = nil;
        metadata = [transpiler templateMetadataForTemplateString:templateText
                                                     logicalPath:logicalPath
                                                           error:&metadataError];
        if (metadata == nil) {
          PrintErrorWithLocation(metadataError);
          return 1;
        }

        NSError *lintError = nil;
        diagnostics = [transpiler lintDiagnosticsForTemplateString:templateText
                                                       logicalPath:logicalPath
                                                             error:&lintError];
        if (diagnostics == nil && lintError != nil) {
          PrintErrorWithLocation(lintError);
          return 1;
        }
        [changedTemplatePaths addObject:templatePath];
      }

      NSDictionary *entry = @{
        @"templatePath" : templatePath,
        @"logicalPath" : logicalPath,
        @"outputPath" : outFile,
        @"templateHash" : templateHash,
        @"dirty" : @(!canReuse),
        @"templateText" : templateText,
        @"metadata" : metadata ?: @{},
        @"diagnostics" : diagnostics ?: @[]
      };
      [entries addObject:entry];
      entriesByPath[logicalPath] = entry;
    }

    NSError *validationError = nil;
    if (!ValidateUnknownDependencies(entriesByPath, &validationError) ||
        !ValidateNoCompositionCycles(entriesByPath, &validationError)) {
      PrintErrorWithLocation(validationError);
      return 1;
    }

    NSArray<NSDictionary *> *crossWarnings = CrossTemplateWarnings(entriesByPath);

    NSMutableArray *registryEntries = [NSMutableArray array];
    for (NSDictionary *entry in entries) {
      NSString *templatePath = entry[@"templatePath"];
      NSString *logicalPath = entry[@"logicalPath"];
      NSString *outFile = entry[@"outputPath"];

      if ([entry[@"dirty"] boolValue]) {
        NSError *transpileError = nil;
        BOOL ok = [transpiler transpileTemplateAtPath:templatePath
                                         templateRoot:templateRoot
                                        logicalPrefix:logicalPrefix
                                           outputPath:outFile
                                                error:&transpileError];
        if (!ok) {
          PrintErrorWithLocation(transpileError);
          return 1;
        }
        transpiledCount += 1;
        for (NSDictionary *diagnostic in entry[@"diagnostics"] ?: @[]) {
          PrintLintDiagnostic(diagnostic, logicalPath);
        }
      }

      NSString *layoutPath =
          [entry[@"metadata"][ALNEOCTemplateMetadataLayoutPathKey] isKindOfClass:[NSString class]]
              ? entry[@"metadata"][ALNEOCTemplateMetadataLayoutPathKey]
              : @"";
      [registryEntries addObject:@{
        @"logicalPath" : logicalPath,
        @"symbol" : [transpiler symbolNameForLogicalPath:logicalPath],
        @"layoutPath" : layoutPath ?: @""
      }];
    }

    NSArray *cachedEntries = [cachedManifest[@"entries"] isKindOfClass:[NSArray class]]
                                 ? cachedManifest[@"entries"]
                                 : @[];
    for (NSDictionary *cachedEntry in cachedEntries) {
      if (![cachedEntry isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      NSString *cachedTemplatePath =
          [cachedEntry[@"template_path"] isKindOfClass:[NSString class]] ? cachedEntry[@"template_path"] : @"";
      if ([cachedTemplatePath length] == 0 || [currentTemplatePaths containsObject:cachedTemplatePath]) {
        continue;
      }
      NSString *staleOutput =
          [cachedEntry[@"output_path"] isKindOfClass:[NSString class]] ? cachedEntry[@"output_path"] : @"";
      if ([staleOutput length] == 0) {
        NSString *staleLogicalPath =
            [cachedEntry[@"logical_path"] isKindOfClass:[NSString class]] ? cachedEntry[@"logical_path"] : @"";
        if ([staleLogicalPath length] > 0) {
          staleOutput = JoinPath(outputDir, [staleLogicalPath stringByAppendingString:@".m"]);
        }
      }
      if ([staleOutput length] > 0 &&
          [[NSFileManager defaultManager] fileExistsAtPath:staleOutput] &&
          [[NSFileManager defaultManager] removeItemAtPath:staleOutput error:nil]) {
        removedCount += 1;
      }
    }

    for (NSDictionary *warning in crossWarnings) {
      NSString *fallbackPath =
          [warning[ALNEOCLintDiagnosticPathKey] isKindOfClass:[NSString class]]
              ? warning[ALNEOCLintDiagnosticPathKey]
              : @"";
      NSString *warningPath =
          [warning[ALNEOCLintDiagnosticPathKey] isKindOfClass:[NSString class]]
              ? warning[ALNEOCLintDiagnosticPathKey]
              : @"";
      NSDictionary *warningEntry = entriesByPath[warningPath];
      NSString *warningTemplatePath =
          [warningEntry[@"templatePath"] isKindOfClass:[NSString class]] ? warningEntry[@"templatePath"] : @"";
      if ([manifestPath length] == 0 || [changedTemplatePaths containsObject:warningTemplatePath]) {
        PrintLintDiagnostic(warning, fallbackPath);
      }
    }

    if ([registryOut length] == 0 && [manifestPath length] == 0) {
      registryOut = [outputDir stringByAppendingPathComponent:@"EOCRegistry.m"];
    }

    if ([registryOut length] > 0) {
      NSString *registryDir = [registryOut stringByDeletingLastPathComponent];
      NSError *registryDirError = nil;
      if (!EnsureDirectory(registryDir, &registryDirError)) {
        fprintf(stderr, "eocc: unable to create registry directory: %s\n",
                [[registryDirError localizedDescription] UTF8String]);
        return 1;
      }

      NSString *registrySource = RegistrySource(registryEntries,
                                               RegistrySymbolSuffix(registryOut, logicalPrefix));
      NSError *writeError = nil;
      BOOL wrote = [registrySource writeToFile:registryOut
                                    atomically:YES
                                      encoding:NSUTF8StringEncoding
                                         error:&writeError];
      if (!wrote) {
        fprintf(stderr, "eocc: unable to write registry source: %s\n",
                [[writeError localizedDescription] UTF8String]);
        return 1;
      }
    } else if ([manifestPath length] > 0) {
      NSString *defaultRegistry = [outputDir stringByAppendingPathComponent:@"EOCRegistry.m"];
      if ([[NSFileManager defaultManager] fileExistsAtPath:defaultRegistry] &&
          [[NSFileManager defaultManager] removeItemAtPath:defaultRegistry error:nil]) {
        removedCount += 1;
      }
    }

    if ([manifestPath length] > 0) {
      NSMutableArray<NSDictionary *> *manifestEntries = [NSMutableArray array];
      for (NSDictionary *entry in entries) {
        [manifestEntries addObject:@{
          @"template_path" : entry[@"templatePath"] ?: @"",
          @"logical_path" : entry[@"logicalPath"] ?: @"",
          @"output_path" : entry[@"outputPath"] ?: @"",
          @"template_hash" : entry[@"templateHash"] ?: @"",
          @"metadata" : entry[@"metadata"] ?: @{},
          @"diagnostics" : entry[@"diagnostics"] ?: @[]
        }];
      }
      NSDictionary *manifestDocument = @{
        @"version" : ALNEOCManifestVersion,
        @"template_root" : templateRoot ?: @"",
        @"logical_prefix" : logicalPrefix ?: @"",
        @"entries" : SortedManifestEntries(manifestEntries)
      };
      NSError *manifestWriteError = nil;
      if (!WriteJSONDocument(manifestDocument, manifestPath, &manifestWriteError)) {
        fprintf(stderr, "eocc: unable to write manifest: %s\n",
                [[manifestWriteError localizedDescription] UTF8String]);
        return 1;
      }
      fprintf(stdout,
              "eocc: transpiled %lu templates (reused %lu, removed %lu)\n",
              (unsigned long)transpiledCount,
              (unsigned long)reusedCount,
              (unsigned long)removedCount);
    } else {
      fprintf(stdout, "eocc: transpiled %lu templates\n",
              (unsigned long)[templatePaths count]);
    }
    return 0;
  }
}

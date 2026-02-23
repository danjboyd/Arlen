#import <Foundation/Foundation.h>

#import "ALNEOCRuntime.h"
#import "ALNEOCTranspiler.h"

static void PrintUsage(void) {
  fprintf(stderr,
          "Usage:\n"
          "  eocc --template-root <dir> --output-dir <dir> "
          "[--registry-out <file>] <template1.html.eoc> [template2 ...]\n");
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

static NSString *RegistrySource(NSArray *entries) {
  NSMutableString *source = [NSMutableString string];
  [source appendString:@"#import <Foundation/Foundation.h>\n"];
  [source appendString:@"#import \"ALNEOCRuntime.h\"\n\n"];

  for (NSDictionary *entry in entries) {
    [source appendFormat:@"extern NSString *%@(id ctx, NSError **error);\n",
                         entry[@"symbol"]];
  }

  [source appendString:@"\nvoid ALNEOCRegisterBuiltInTemplates(void) {\n"];
  [source appendString:@"  static BOOL didRegister = NO;\n"];
  [source appendString:@"  if (didRegister) {\n"];
  [source appendString:@"    return;\n"];
  [source appendString:@"  }\n"];
  [source appendString:@"  didRegister = YES;\n"];
  for (NSDictionary *entry in entries) {
    [source appendFormat:@"  ALNEOCRegisterTemplate(@\"%@\", &%@);\n",
                         entry[@"logicalPath"], entry[@"symbol"]];
  }
  [source appendString:@"}\n\n"];
  [source appendString:@"__attribute__((constructor))\n"];
  [source appendString:@"static void ALNEOCAutoRegisterBuiltInTemplates(void) {\n"];
  [source appendString:@"  ALNEOCRegisterBuiltInTemplates();\n"];
  [source appendString:@"}\n"];
  return source;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSString *templateRoot = nil;
    NSString *outputDir = nil;
    NSString *registryOut = nil;
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
      } else if ([arg isEqualToString:@"--registry-out"]) {
        if (idx + 1 >= argc) {
          PrintUsage();
          return 2;
        }
        registryOut = [NSString stringWithUTF8String:argv[++idx]];
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
    NSMutableArray *registryEntries = [NSMutableArray array];

    NSError *createError = nil;
    if (!EnsureDirectory(outputDir, &createError)) {
      fprintf(stderr, "eocc: unable to create output directory: %s\n",
              [[createError localizedDescription] UTF8String]);
      return 1;
    }

    for (NSString *templatePath in templatePaths) {
      NSString *logicalPath =
          [transpiler logicalPathForTemplatePath:templatePath templateRoot:templateRoot];
      NSString *outFile = JoinPath(outputDir, [logicalPath stringByAppendingString:@".m"]);

      NSError *transpileError = nil;
      BOOL ok = [transpiler transpileTemplateAtPath:templatePath
                                       templateRoot:templateRoot
                                         outputPath:outFile
                                              error:&transpileError];
      if (!ok) {
        fprintf(stderr, "eocc: %s\n",
                [[transpileError localizedDescription] UTF8String]);
        NSNumber *line = transpileError.userInfo[ALNEOCErrorLineKey];
        NSNumber *column = transpileError.userInfo[ALNEOCErrorColumnKey];
        NSString *path = transpileError.userInfo[ALNEOCErrorPathKey];
        if (line != nil || column != nil || path != nil) {
          NSString *safePath = (path != nil) ? path : @"";
          NSString *safeLine = (line != nil) ? [line stringValue] : @"";
          NSString *safeColumn =
              (column != nil) ? [column stringValue] : @"";
          fprintf(stderr, "eocc: location path=%s line=%s column=%s\n",
                  [safePath UTF8String], [safeLine UTF8String],
                  [safeColumn UTF8String]);
        }
        return 1;
      }

      NSString *templateText = [NSString stringWithContentsOfFile:templatePath
                                                         encoding:NSUTF8StringEncoding
                                                            error:nil];
      if (templateText != nil) {
        NSArray<NSDictionary *> *diagnostics =
            [transpiler lintDiagnosticsForTemplateString:templateText
                                             logicalPath:logicalPath
                                                   error:nil];
        for (NSDictionary *diagnostic in diagnostics ?: @[]) {
          NSString *path = [diagnostic[ALNEOCLintDiagnosticPathKey] isKindOfClass:[NSString class]]
                               ? diagnostic[ALNEOCLintDiagnosticPathKey]
                               : logicalPath;
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
          fprintf(stderr,
                  "eocc: warning path=%s line=%s column=%s code=%s message=%s\n",
                  [path UTF8String], [line UTF8String], [column UTF8String],
                  [code UTF8String], [message UTF8String]);
        }
      } else {
        fprintf(stderr, "eocc: warning unable to lint template: %s\n",
                [templatePath UTF8String]);
      }

      [registryEntries addObject:@{
        @"logicalPath" : logicalPath,
        @"symbol" : [transpiler symbolNameForLogicalPath:logicalPath]
      }];
    }

    if ([registryOut length] == 0) {
      registryOut = [outputDir stringByAppendingPathComponent:@"EOCRegistry.m"];
    }

    NSString *registryDir = [registryOut stringByDeletingLastPathComponent];
    NSError *registryDirError = nil;
    if (!EnsureDirectory(registryDir, &registryDirError)) {
      fprintf(stderr, "eocc: unable to create registry directory: %s\n",
              [[registryDirError localizedDescription] UTF8String]);
      return 1;
    }

    NSString *registrySource = RegistrySource(registryEntries);
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

    fprintf(stdout, "eocc: transpiled %lu templates\n",
            (unsigned long)[templatePaths count]);
    return 0;
  }
}

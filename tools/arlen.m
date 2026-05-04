#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdlib.h>

#import "ALNDataCompat.h"
#import "ALNConfig.h"
#import "ALNDataverseClient.h"
#import "ALNDataverseCodegen.h"
#import "ALNDataverseMetadata.h"
#import "ALNGDL2Adapter.h"
#import "ALNDatabaseInspector.h"
#import "ALNJSONSerialization.h"
#import "ALNMSSQL.h"
#import "ALNModuleSystem.h"
#import "ALNMigrationRunner.h"
#import "ALNPg.h"
#import "Arlen/ORM/ALNORMTypeScriptCodegen.h"
#import "ALNSchemaCodegen.h"

static void PrintUsage(void) {
  fprintf(stderr,
          "Usage: arlen <command> [options]\n"
          "\n"
          "Commands:\n"
          "  new <AppName> [--full|--lite] [--force] [--json]\n"
          "  generate <controller|endpoint|model|migration|test|plugin|frontend|search> <Name> [options] [--json]\n"
          "  boomhauer [server args...]\n"
          "  jobs worker [worker args...]\n"
          "  propane [manager args...]\n"
          "  deploy <list|dryrun|init|push|releases|release|status|rollback|doctor|logs|target sample> [target] [options]\n"
          "  completion <bash|powershell>\n"
          "  migrate [--env <name>] [--database <target>] [--dsn <connection_string>] [--dry-run]\n"
          "  module <add|remove|list|doctor|migrate|assets|upgrade|eject> [options]\n"
          "  schema-codegen [--env <name>] [--database <target>] [--dsn <connection_string>] [--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] [--typed-contracts] [--force]\n"
          "  dataverse-codegen [--input <metadata.json>] [--env <name>] [--target <name>] [--service-root <url>] [--tenant-id <id>] [--client-id <id>] [--client-secret <secret>] [--entity <logical_name>] [--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] [--force]\n"
          "  typed-sql-codegen [--input-dir <path>] [--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] [--force]\n"
          "  typescript-codegen [--orm-input <path>] [--openapi-input <path>] [--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] [--database <target>] [--package-name <name>] [--target <models|validators|query|client|react|meta|all>] [--force]\n"
          "  routes\n"
          "  test [--unit|--integration|--all]\n"
          "  perf\n"
          "  check [--dry-run] [--json]\n"
          "  build [--dry-run] [--json]\n"
          "  config [--env <name>] [--json]\n"
          "  doctor [--env <name>] [--json]\n");
}

static void PrintNewUsage(void) {
  fprintf(stdout, "Usage: arlen new <AppName> [--full|--lite] [--force] [--json]\n");
}

static void PrintGenerateUsage(void) {
  fprintf(stdout,
          "Usage: arlen generate <controller|endpoint|model|migration|test|plugin|frontend|search> <Name> [options] [--json]\n"
          "\n"
          "Generator options (controller/endpoint):\n"
          "  --route <path>\n"
          "  --method <HTTP>\n"
          "  --action <name>\n"
          "  --template [<logical_template>]\n"
          "  --api\n"
          "\n"
          "Generator options (plugin):\n"
          "  --preset <generic|redis-cache|queue-jobs|smtp-mail>\n"
          "\n"
          "Generator options (frontend):\n"
          "  --preset <vanilla-spa|progressive-mpa>\n"
          "\n"
          "Generator behavior (search):\n"
          "  requires vendored `jobs` and `search` modules\n"
          "  scaffolds a searchable resource/provider under src/Search/\n"
          "  registers the provider in config/app.plist\n"
          "  adds migration and engine-swap notes under docs/search/\n"
          "\n"
          "Machine-readable output:\n"
          "  --json\n");
}

static void PrintBuildUsage(void) {
  fprintf(stdout, "Usage: arlen build [--dry-run] [--json]\n");
}

static void PrintDeployUsage(void) {
  fprintf(stdout,
          "Usage: arlen deploy <list|dryrun|init|push|releases|release|status|rollback|doctor|logs|target sample> [target] [options]\n"
          "\n"
          "Subcommands:\n"
          "  list                  List configured targets from config/deploy.plist\n"
          "  dryrun                Validate deploy inputs and emit a dry-run release payload\n"
          "  init                  Generate deterministic host bootstrap artifacts for a named target\n"
          "  push                  Build a local immutable release artifact under releases/\n"
          "  releases              List release artifacts available to activate\n"
          "  release               Ensure a release exists, migrate if needed, and activate it\n"
          "  status                Show active/previous release state and optional runtime health\n"
          "  rollback              Activate a previous release and optionally verify health\n"
          "  doctor                Validate release layout, config, and optional runtime health\n"
          "  logs                  Show active release log pointers or stream runtime logs\n"
          "  target sample         Print or write a commented config/deploy.plist.example\n"
          "  plan                  Deprecated alias for dryrun\n"
          "\n"
          "Shared options:\n"
          "  [target]              Named deploy target from config/deploy.plist\n"
          "  --app-root <path>\n"
          "  --framework-root <path>\n"
          "  --releases-dir <path>\n"
          "  --release-id <id>\n"
          "  --service <name>      systemd unit for runtime state/log actions\n"
          "  --base-url <url>      Base URL for probe validation\n"
          "  --target-profile <profile>\n"
          "  --runtime-strategy <system|managed|bundled>\n"
          "  --runtime-restart-command <shell>\n"
          "  --runtime-reload-command <shell>\n"
          "  --health-startup-timeout <seconds>\n"
          "  --health-startup-interval <seconds>\n"
          "  --database-mode <external|host_local|embedded>\n"
          "  --database-adapter <name>\n"
          "  --database-target <name>\n"
          "  --require-env-key <NAME>\n"
          "  --allow-remote-rebuild\n"
          "  --remote-build-check-command <shell>\n"
          "  --certification-manifest <path>\n"
          "  --json-performance-manifest <path>\n"
          "  --allow-missing-certification\n"
          "  --skip-release-certification\n"
          "  --dev                  Non-RC app iteration deploy; waive release certification\n"
          "  --json\n"
          "\n"
          "Release-only options:\n"
          "  --env <name>          Migration environment (default: production)\n"
          "  --skip-migrate        Skip migration step during activation\n"
          "  --runtime-action <reload|restart|none>\n"
          "\n"
          "Rollback options:\n"
          "  --runtime-action <reload|restart|none>\n"
          "\n"
          "Logs options:\n"
          "  --lines <count>       Number of log lines to show (default: 200)\n"
          "  --follow              Follow log output\n"
          "  --file <path>         Tail a log file when journald is not desired\n");
}

static void PrintCompletionUsage(void) {
  fprintf(stdout,
          "Usage: arlen completion <bash|powershell|candidates> [options]\n"
          "\n"
          "Subcommands:\n"
          "  bash                  Generate bash completion script to stdout\n"
          "  powershell            Generate PowerShell completion script to stdout\n"
          "  candidates <kind>     Internal read-only completion candidates\n");
}

static void PrintJobsUsage(void) {
  fprintf(stdout,
          "Usage: arlen jobs worker [worker args...]\n"
          "\n"
          "Delegates to framework bin/jobs-worker with ARLEN_APP_ROOT and ARLEN_FRAMEWORK_ROOT resolved.\n");
}

static void PrintCheckUsage(void) {
  fprintf(stdout, "Usage: arlen check [--dry-run] [--json]\n");
}

static void PrintModuleUsage(void) {
  fprintf(stdout,
          "Usage: arlen module <subcommand> [options]\n"
          "\n"
          "Subcommands:\n"
          "  add <name> [--source <path>] [--force] [--json]\n"
          "  remove <name> [--keep-files] [--json]\n"
          "  list [--json]\n"
          "  doctor [--env <name>] [--json]\n"
          "  migrate [--env <name>] [--database <target>] [--dsn <connection_string>] [--dry-run] [--json]\n"
          "  assets [--output-dir <path>] [--json]\n"
          "  eject auth-ui [--force] [--json]\n"
          "  upgrade <name> --source <path> [--force] [--json]\n");
}

static NSString *AgentContractVersion(void) {
  return @"phase7g-agent-dx-contracts-v1";
}

static BOOL ArgsContainFlag(NSArray *args, NSString *flag) {
  for (NSString *arg in args ?: @[]) {
    if ([arg isEqualToString:flag]) {
      return YES;
    }
  }
  return NO;
}

static NSString *ResolvePathFromRoot(NSString *root, NSString *rawPath);

static NSString *RelativePathFromRoot(NSString *root, NSString *path) {
  NSString *standardRoot = [[root ?: @"" stringByStandardizingPath] copy];
  NSString *standardPath = [[path ?: @"" stringByStandardizingPath] copy];
  if ([standardRoot length] == 0 || [standardPath length] == 0) {
    return @"";
  }

  if ([standardPath isEqualToString:standardRoot]) {
    return @"";
  }

  NSString *prefix = [standardRoot hasSuffix:@"/"] ? standardRoot : [standardRoot stringByAppendingString:@"/"];
  if (![standardPath hasPrefix:prefix]) {
    return @"";
  }
  return [standardPath substringFromIndex:[prefix length]];
}

static NSArray<NSString *> *SortedFileListAtRoot(NSString *root) {
  NSMutableArray<NSString *> *files = [NSMutableArray array];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:root];
  for (NSString *relativePath in enumerator) {
    NSString *absolutePath = [root stringByAppendingPathComponent:relativePath];
    BOOL isDirectory = NO;
    if ([fm fileExistsAtPath:absolutePath isDirectory:&isDirectory] && !isDirectory) {
      [files addObject:relativePath];
    }
  }
  return [files sortedArrayUsingSelector:@selector(compare:)];
}

static NSArray<NSString *> *SortedUniqueStrings(NSArray<NSString *> *values) {
  NSArray<NSString *> *sorted = [values ?: @[] sortedArrayUsingSelector:@selector(compare:)];
  NSMutableArray<NSString *> *unique = [NSMutableArray arrayWithCapacity:[sorted count]];
  NSString *last = nil;
  for (NSString *value in sorted) {
    if (![value isKindOfClass:[NSString class]]) {
      continue;
    }
    if (last == nil || ![last isEqualToString:value]) {
      [unique addObject:value];
      last = value;
    }
  }
  return unique;
}

static NSJSONWritingOptions StableJSONWritingOptions(void) {
  NSJSONWritingOptions options = NSJSONWritingPrettyPrinted;
#ifdef NSJSONWritingSortedKeys
  options |= NSJSONWritingSortedKeys;
#endif
  return options;
}

static BOOL PrintJSONPayload(FILE *stream, NSDictionary *payload) {
  NSError *error = nil;
  NSData *json = [ALNJSONSerialization dataWithJSONObject:payload ?: @{}
                                                   options:StableJSONWritingOptions()
                                                     error:&error];
  if (json == nil) {
    fprintf(stderr, "arlen: failed to render JSON output: %s\n",
            [[error localizedDescription] UTF8String]);
    return NO;
  }
  NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"{}";
  fprintf(stream, "%s\n", [text UTF8String]);
  return YES;
}

static int EmitMachineError(NSString *command,
                            NSString *workflow,
                            NSString *errorCode,
                            NSString *message,
                            NSString *fixitAction,
                            NSString *fixitExample,
                            int exitCode) {
  NSMutableDictionary *errorObject = [NSMutableDictionary dictionary];
  errorObject[@"code"] = errorCode ?: @"unknown_error";
  errorObject[@"message"] = message ?: @"";

  NSMutableDictionary *fixit = [NSMutableDictionary dictionary];
  if ([fixitAction length] > 0) {
    fixit[@"action"] = fixitAction;
  }
  if ([fixitExample length] > 0) {
    fixit[@"example"] = fixitExample;
  }
  if ([fixit count] > 0) {
    errorObject[@"fixit"] = fixit;
  }

  NSDictionary *payload = @{
    @"version" : AgentContractVersion(),
    @"command" : command ?: @"",
    @"workflow" : workflow ?: @"",
    @"status" : @"error",
    @"error" : errorObject,
    @"exit_code" : @(exitCode),
  };
  PrintJSONPayload(stdout, payload);
  return exitCode;
}

static void AppendRelativePath(NSMutableArray<NSString *> *paths, NSString *root, NSString *absolutePath) {
  NSString *relative = RelativePathFromRoot(root, absolutePath);
  if ([relative length] > 0) {
    [paths addObject:relative];
  }
}

static NSString *ShellQuote(NSString *value) {
  NSString *escaped = [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\"'\"'"];
  return [NSString stringWithFormat:@"'%@'", escaped];
}

static NSString *Trimmed(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSDictionary *JSONDictionaryFromString(NSString *value) {
  NSString *trimmed = Trimmed(value);
  if ([trimmed length] > 0 && ![trimmed hasPrefix:@"{"]) {
    NSRange start = [trimmed rangeOfString:@"{"];
    NSRange end = [trimmed rangeOfString:@"}" options:NSBackwardsSearch];
    if (start.location != NSNotFound && end.location != NSNotFound && end.location >= start.location) {
      trimmed = [trimmed substringWithRange:NSMakeRange(start.location, end.location - start.location + 1)];
    }
  }
  NSData *data = [[trimmed ?: @"" copy] dataUsingEncoding:NSUTF8StringEncoding];
  if ([data length] == 0) {
    return nil;
  }
  NSError *error = nil;
  id parsed = [ALNJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (![parsed isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  return parsed;
}

static NSDictionary *JSONDictionaryFromFile(NSString *path) {
  NSData *data = [NSData dataWithContentsOfFile:path ?: @""];
  if ([data length] == 0) {
    return nil;
  }
  NSError *error = nil;
  id parsed = [ALNJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (![parsed isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  return parsed;
}

static NSString *RunShellCaptureCommand(NSString *command, int *exitCode);
static NSString *EnvValue(const char *name);
static BOOL PathExists(NSString *path, BOOL *isDirectory);
static NSString *NormalizeDatabaseTarget(NSString *rawValue);
static BOOL DatabaseTargetIsValid(NSString *target);
static NSString *DatabaseConnectionStringFromEnvironmentForTarget(NSString *databaseTarget);
static NSString *DatabaseConnectionStringFromConfigForTarget(NSDictionary *config, NSString *databaseTarget);
static NSString *DatabaseAdapterNameFromConfigForTarget(NSDictionary *config, NSString *databaseTarget);
static NSDictionary *Phase39StateContractFromConfig(NSDictionary *config);
static NSArray<NSDictionary *> *Phase39MultiWorkerStateWarnings(NSDictionary *config,
                                                                NSString *environment,
                                                                NSString *databaseMode,
                                                                NSString *databaseTarget);
static void PrintDeployWarnings(NSArray<NSDictionary *> *warnings);

static NSString *DefaultGNUstepScriptPath(void) {
  if (PathExists(@"/clang64/share/GNUstep/Makefiles/GNUstep.sh", NULL)) {
    return @"/clang64/share/GNUstep/Makefiles/GNUstep.sh";
  }
  return @"/usr/GNUstep/System/Library/Makefiles/GNUstep.sh";
}

static NSString *GNUstepScriptPathFromMakefilesPath(NSString *makefilesPath) {
  NSString *trimmed = Trimmed(makefilesPath);
  if ([trimmed length] == 0) {
    return @"";
  }
  return [trimmed stringByAppendingPathComponent:@"GNUstep.sh"];
}

static NSString *ResolveGNUstepScriptPath(void) {
  NSString *direct = Trimmed(EnvValue("GNUSTEP_SH"));
  if ([direct length] > 0 && PathExists(direct, NULL)) {
    return [direct stringByStandardizingPath];
  }

  NSString *makefilesFromEnv = Trimmed(EnvValue("GNUSTEP_MAKEFILES"));
  NSString *fromEnv = GNUstepScriptPathFromMakefilesPath(makefilesFromEnv);
  if ([fromEnv length] > 0 && PathExists(fromEnv, NULL)) {
    return [fromEnv stringByStandardizingPath];
  }

  int configCode = 0;
  NSString *makefilesFromConfig =
      Trimmed(RunShellCaptureCommand(@"command -v gnustep-config >/dev/null 2>&1 && gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null",
                                     &configCode));
  NSString *fromConfig = GNUstepScriptPathFromMakefilesPath(makefilesFromConfig);
  if (configCode == 0 && [fromConfig length] > 0 && PathExists(fromConfig, NULL)) {
    return [fromConfig stringByStandardizingPath];
  }

  NSString *fallback = DefaultGNUstepScriptPath();
  if (PathExists(fallback, NULL)) {
    return fallback;
  }

  if ([direct length] > 0) {
    return [direct stringByStandardizingPath];
  }
  if ([fromEnv length] > 0) {
    return [fromEnv stringByStandardizingPath];
  }
  if ([fromConfig length] > 0) {
    return [fromConfig stringByStandardizingPath];
  }
  return fallback;
}

static NSString *TaskCapturePath(NSString *prefix) {
  NSString *name = [NSString stringWithFormat:@"%@-%@.log",
                                              prefix ?: @"arlen-task",
                                              [[NSProcessInfo processInfo] globallyUniqueString]];
  return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

static void CloseFileHandleQuietly(NSFileHandle *handle) {
  if (handle == nil) {
    return;
  }
  @try {
    [handle closeFile];
  } @catch (NSException *exception) {
    (void)exception;
  }
}

static NSString *RunShellCaptureCommand(NSString *command, int *exitCode) {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  task.arguments = @[ @"-lc", command ?: @"" ];
  NSString *stdoutPath = TaskCapturePath(@"arlen-shell-stdout");
  NSString *stderrPath = TaskCapturePath(@"arlen-shell-stderr");
  [[NSFileManager defaultManager] createFileAtPath:stdoutPath contents:nil attributes:nil];
  [[NSFileManager defaultManager] createFileAtPath:stderrPath contents:nil attributes:nil];
  NSFileHandle *stdoutWrite = [NSFileHandle fileHandleForWritingAtPath:stdoutPath];
  NSFileHandle *stderrWrite = [NSFileHandle fileHandleForWritingAtPath:stderrPath];
  task.standardOutput = stdoutWrite;
  task.standardError = stderrWrite;
  @try {
    [task launch];
    [task waitUntilExit];
  } @catch (NSException *exception) {
    CloseFileHandleQuietly(stdoutWrite);
    CloseFileHandleQuietly(stderrWrite);
    [[NSFileManager defaultManager] removeItemAtPath:stdoutPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:stderrPath error:nil];
    if (exitCode != NULL) {
      *exitCode = 127;
    }
    return [NSString stringWithFormat:@"failed launching shell command: %@",
                                      [exception reason] ?: [exception name] ?: @"unknown error"];
  }

  if (exitCode != NULL) {
    *exitCode = task.terminationStatus;
  }
  CloseFileHandleQuietly(stdoutWrite);
  CloseFileHandleQuietly(stderrWrite);
  NSData *stdoutData = [NSData dataWithContentsOfFile:stdoutPath] ?: [NSData data];
  NSData *stderrData = [NSData dataWithContentsOfFile:stderrPath] ?: [NSData data];
  [[NSFileManager defaultManager] removeItemAtPath:stdoutPath error:nil];
  [[NSFileManager defaultManager] removeItemAtPath:stderrPath error:nil];
  NSString *stdoutText = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding] ?: @"";
  NSString *stderrText = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"";
  return [stdoutText stringByAppendingString:stderrText];
}

static int RunShellCommand(NSString *command) {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  task.arguments = @[ @"-lc", command ];
  task.standardInput = [NSFileHandle fileHandleWithStandardInput];
  task.standardOutput = [NSFileHandle fileHandleWithStandardOutput];
  task.standardError = [NSFileHandle fileHandleWithStandardError];
  [task launch];
  [task waitUntilExit];
  return task.terminationStatus;
}

static NSString *TaskCommandDescription(NSString *launchPath, NSArray<NSString *> *arguments) {
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  [parts addObject:ShellQuote(launchPath ?: @"")];
  for (NSString *argument in arguments ?: @[]) {
    [parts addObject:ShellQuote(argument ?: @"")];
  }
  return [parts componentsJoinedByString:@" "];
}

static NSString *RunTaskCapture(NSString *launchPath, NSArray<NSString *> *arguments, int *exitCode) {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = launchPath ?: @"/usr/bin/env";
  task.arguments = arguments ?: @[];
  NSString *capturePath = TaskCapturePath(@"arlen-task-capture");
  [[NSFileManager defaultManager] createFileAtPath:capturePath contents:nil attributes:nil];
  NSFileHandle *captureWrite = [NSFileHandle fileHandleForWritingAtPath:capturePath];
  task.standardOutput = captureWrite;
  task.standardError = captureWrite;
  @try {
    [task launch];
    [task waitUntilExit];
  } @catch (NSException *exception) {
    [captureWrite closeFile];
    [[NSFileManager defaultManager] removeItemAtPath:capturePath error:nil];
    if (exitCode != NULL) {
      *exitCode = 127;
    }
    return [NSString stringWithFormat:@"failed launching %@: %@",
                                      TaskCommandDescription(launchPath, arguments),
                                      [exception reason] ?: [exception name] ?: @"unknown error"];
  }

  if (exitCode != NULL) {
    *exitCode = task.terminationStatus;
  }
  [captureWrite closeFile];
  NSData *capturedData = [NSData dataWithContentsOfFile:capturePath] ?: [NSData data];
  [[NSFileManager defaultManager] removeItemAtPath:capturePath error:nil];
  return [[NSString alloc] initWithData:capturedData encoding:NSUTF8StringEncoding] ?: @"";
}

static NSString *EnvValue(const char *name) {
  const char *value = getenv(name);
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

static BOOL PathExists(NSString *path, BOOL *isDirectory) {
  return [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:isDirectory];
}

static BOOL DirectoryContainsSQLFiles(NSString *path) {
  BOOL isDirectory = NO;
  if (!PathExists(path, &isDirectory) || !isDirectory) {
    return NO;
  }

  NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:path];
  for (NSString *relativePath in enumerator) {
    if ([[[relativePath pathExtension] lowercaseString] isEqualToString:@"sql"]) {
      return YES;
    }
  }
  return NO;
}

static void AppendShellOption(NSMutableString *command, NSString *flag, NSString *value) {
  if ([flag length] == 0 || [value length] == 0) {
    return;
  }
  [command appendFormat:@" %@ %@", flag, ShellQuote(value)];
}

static NSDictionary *DictionaryFromReleaseEnvFile(NSString *path) {
  NSString *contents = [NSString stringWithContentsOfFile:path
                                                 encoding:NSUTF8StringEncoding
                                                    error:NULL];
  if ([contents length] == 0) {
    return @{};
  }

  NSMutableDictionary *values = [NSMutableDictionary dictionary];
  NSArray *lines = [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  for (NSString *line in lines) {
    NSString *trimmed = Trimmed(line);
    if ([trimmed length] == 0 || [trimmed hasPrefix:@"#"]) {
      continue;
    }
    NSRange equalsRange = [trimmed rangeOfString:@"="];
    if (equalsRange.location == NSNotFound) {
      continue;
    }
    NSString *key = Trimmed([trimmed substringToIndex:equalsRange.location]);
    NSString *value = [trimmed substringFromIndex:(equalsRange.location + 1)];
    if ([key length] > 0) {
      values[key] = value ?: @"";
    }
  }
  return values;
}

static NSString *ResolveSymlinkDestination(NSString *path) {
  int exitCode = 0;
  NSString *resolved =
      Trimmed(RunShellCaptureCommand([NSString stringWithFormat:@"readlink -f %@ 2>/dev/null", ShellQuote(path)],
                                     &exitCode));
  return (exitCode == 0 && [resolved length] > 0) ? [resolved stringByStandardizingPath] : nil;
}

static NSString *ResolveExecutablePath(NSString *path) {
  if ([path length] == 0) {
    return nil;
  }

  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *standardPath = [path stringByStandardizingPath];
  if ([fm isExecutableFileAtPath:standardPath]) {
    return standardPath;
  }
  if (![[standardPath lowercaseString] hasSuffix:@".exe"]) {
    NSString *windowsCandidate = [standardPath stringByAppendingString:@".exe"];
    if ([fm isExecutableFileAtPath:windowsCandidate]) {
      return windowsCandidate;
    }
  }
  return nil;
}

static BOOL IsAbsoluteDeployPath(NSString *path) {
  NSString *value = path ?: @"";
  if ([value hasPrefix:@"/"] || [value hasPrefix:@"\\\\"]) {
    return YES;
  }
  if ([value length] >= 3) {
    unichar drive = [value characterAtIndex:0];
    unichar colon = [value characterAtIndex:1];
    unichar slash = [value characterAtIndex:2];
    if (((drive >= 'A' && drive <= 'Z') || (drive >= 'a' && drive <= 'z')) && colon == ':' &&
        (slash == '/' || slash == '\\')) {
      return YES;
    }
  }
  return NO;
}

static NSString *ResolveReleaseManifestPath(NSString *releaseDir, NSString *path, NSString *fallbackRelativePath) {
  NSString *candidate = [Trimmed(path) length] > 0 ? Trimmed(path) : Trimmed(fallbackRelativePath);
  if ([candidate length] == 0) {
    return nil;
  }
  if (IsAbsoluteDeployPath(candidate) || [releaseDir length] == 0) {
    return [candidate stringByStandardizingPath];
  }
  return [[releaseDir stringByAppendingPathComponent:candidate] stringByStandardizingPath];
}

static NSDictionary *ResolvedManifestPathsForRelease(NSDictionary *manifest, NSString *releaseDir) {
  NSDictionary *paths = [manifest[@"paths"] isKindOfClass:[NSDictionary class]] ? manifest[@"paths"] : @{};
  return @{
    @"app_root" : ResolveReleaseManifestPath(releaseDir, paths[@"app_root"], @"app") ?: @"",
    @"framework_root" : ResolveReleaseManifestPath(releaseDir, paths[@"framework_root"], @"framework") ?: @"",
    @"runtime_binary" :
        ResolveReleaseManifestPath(releaseDir, paths[@"runtime_binary"], @"app/.boomhauer/build/boomhauer-app") ?: @"",
    @"migrations_dir" :
        ResolveReleaseManifestPath(releaseDir, paths[@"migrations_dir"], @"app/db/migrations") ?: @"",
    @"boomhauer" : ResolveReleaseManifestPath(releaseDir, paths[@"boomhauer"], @"framework/build/boomhauer") ?: @"",
    @"propane" : ResolveReleaseManifestPath(releaseDir, paths[@"propane"], @"framework/bin/propane") ?: @"",
    @"jobs_worker" :
        ResolveReleaseManifestPath(releaseDir, paths[@"jobs_worker"], @"framework/bin/jobs-worker") ?: @"",
    @"arlen" : ResolveReleaseManifestPath(releaseDir, paths[@"arlen"], @"framework/build/arlen") ?: @"",
    @"operability_probe_helper" : ResolveReleaseManifestPath(releaseDir,
                                                              paths[@"operability_probe_helper"],
                                                              @"framework/tools/deploy/validate_operability.sh") ?: @"",
    @"release_env" : ResolveReleaseManifestPath(releaseDir, paths[@"release_env"], @"metadata/release.env") ?: @"",
  };
}

static NSArray<NSString *> *SortedReleaseDirectories(NSString *releasesDir) {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:releasesDir error:NULL] ?: @[];
  NSMutableArray<NSString *> *releaseIDs = [NSMutableArray array];
  for (NSString *entry in children) {
    if ([entry isEqualToString:@"current"] || [entry isEqualToString:@"latest-built"]) {
      continue;
    }
    NSString *candidate = [releasesDir stringByAppendingPathComponent:entry];
    BOOL isDirectory = NO;
    if ([fm fileExistsAtPath:candidate isDirectory:&isDirectory] && isDirectory) {
      [releaseIDs addObject:entry];
    }
  }
  return [releaseIDs sortedArrayUsingSelector:@selector(compare:)];
}

static NSString *ReleaseIDForDirectory(NSString *releaseDir) {
  return [[releaseDir stringByStandardizingPath] lastPathComponent];
}

static NSString *CurrentReleaseDirectoryAtReleasesDir(NSString *releasesDir) {
  NSString *currentPath = [releasesDir stringByAppendingPathComponent:@"current"];
  NSString *resolved = ResolveSymlinkDestination(currentPath);
  if ([resolved length] > 0) {
    return resolved;
  }
  BOOL isDirectory = NO;
  if (PathExists(currentPath, &isDirectory) && isDirectory) {
    return [currentPath stringByStandardizingPath];
  }
  return nil;
}

static NSString *PreviousReleaseIDAtReleasesDir(NSString *releasesDir, NSString *currentReleaseID) {
  NSArray<NSString *> *sortedReleaseIDs = SortedReleaseDirectories(releasesDir);
  for (NSInteger idx = (NSInteger)[sortedReleaseIDs count] - 1; idx >= 0; idx--) {
    NSString *candidate = sortedReleaseIDs[(NSUInteger)idx];
    if ([candidate isEqualToString:currentReleaseID ?: @""]) {
      continue;
    }
    return candidate;
  }
  return nil;
}

static NSString *ServiceRuntimeState(NSString *serviceName, NSString **capturedOutput) {
  if ([serviceName length] == 0) {
    if (capturedOutput != NULL) {
      *capturedOutput = @"";
    }
    return @"not_requested";
  }
  int commandCode = 0;
  NSString *systemctlPath =
      Trimmed(RunShellCaptureCommand(@"command -v systemctl 2>/dev/null", &commandCode));
  if (commandCode != 0 || [systemctlPath length] == 0) {
    if (capturedOutput != NULL) {
      *capturedOutput = @"systemctl not available";
    }
    return @"unavailable";
  }

  int exitCode = 0;
  NSString *output = Trimmed(RunShellCaptureCommand([NSString stringWithFormat:@"systemctl is-active %@ 2>&1",
                                                                              ShellQuote(serviceName)],
                                                   &exitCode));
  if (capturedOutput != NULL) {
    *capturedOutput = output ?: @"";
  }
  if ([output length] == 0) {
    return (exitCode == 0) ? @"active" : @"unknown";
  }
  return output;
}

static NSString *ServiceMainPID(NSString *serviceName, NSString **capturedOutput) {
  if ([serviceName length] == 0) {
    if (capturedOutput != NULL) {
      *capturedOutput = @"";
    }
    return nil;
  }
  int exitCode = 0;
  NSString *output = Trimmed(RunShellCaptureCommand([NSString stringWithFormat:@"systemctl show %@ -p MainPID --value 2>&1",
                                                                              ShellQuote(serviceName)],
                                                   &exitCode));
  if (capturedOutput != NULL) {
    *capturedOutput = output ?: @"";
  }
  if (exitCode != 0 || [output length] == 0 || [output isEqualToString:@"0"]) {
    return nil;
  }
  return output;
}

static NSDictionary *EnvironmentDictionaryFromEnvironData(NSData *data) {
  if ([data length] == 0) {
    return @{};
  }

  NSMutableDictionary *environment = [NSMutableDictionary dictionary];
  const char *bytes = data.bytes;
  NSUInteger length = data.length;
  NSUInteger start = 0;
  for (NSUInteger idx = 0; idx <= length; idx++) {
    BOOL atEnd = (idx == length);
    if (!atEnd && bytes[idx] != '\0') {
      continue;
    }
    if (idx > start) {
      NSData *entryData = [NSData dataWithBytes:bytes + start length:(idx - start)];
      NSString *entry = [[NSString alloc] initWithData:entryData encoding:NSUTF8StringEncoding];
      NSRange separator = [entry rangeOfString:@"="];
      if ([entry length] > 0 && separator.location != NSNotFound && separator.location > 0) {
        NSString *key = [entry substringToIndex:separator.location];
        NSString *value = [entry substringFromIndex:(separator.location + 1)];
        environment[key] = value ?: @"";
      }
    }
    start = idx + 1;
  }
  return environment;
}

static NSDictionary *EnvironmentDictionaryForPID(NSString *pid, NSString **capturedOutput) {
  NSString *trimmedPID = Trimmed(pid);
  if ([trimmedPID length] == 0) {
    if (capturedOutput != NULL) {
      *capturedOutput = @"service has no main pid";
    }
    return @{};
  }

  NSString *environPath = [NSString stringWithFormat:@"/proc/%@/environ", trimmedPID];
  NSData *data = [NSData dataWithContentsOfFile:environPath];
  if ([data length] == 0) {
    if (capturedOutput != NULL) {
      *capturedOutput = [NSString stringWithFormat:@"unable to read %@" , environPath];
    }
    return @{};
  }
  if (capturedOutput != NULL) {
    *capturedOutput = [NSString stringWithFormat:@"loaded environment from pid %@", trimmedPID];
  }
  return EnvironmentDictionaryFromEnvironData(data);
}

static NSDictionary *ServiceEnvironmentForService(NSString *serviceName, NSString **capturedOutput) {
  NSString *mainPIDOutput = nil;
  NSString *mainPID = ServiceMainPID(serviceName, &mainPIDOutput);
  if ([mainPID length] == 0) {
    if (capturedOutput != NULL) {
      *capturedOutput = mainPIDOutput ?: @"service has no main pid";
    }
    return @{};
  }
  return EnvironmentDictionaryForPID(mainPID, capturedOutput);
}

static NSString *ExpandedRuntimeCommandTemplate(NSString *commandTemplate,
                                                NSString *action,
                                                NSString *serviceName) {
  NSString *command = Trimmed(commandTemplate);
  if ([command length] == 0) {
    return @"";
  }
  command = [command stringByReplacingOccurrencesOfString:@"{action}" withString:action ?: @""];
  command = [command stringByReplacingOccurrencesOfString:@"{service}" withString:ShellQuote(serviceName ?: @"")];
  return command;
}

static NSString *RuntimeCommandForAction(NSString *action,
                                         NSString *serviceName,
                                         NSString *restartCommand,
                                         NSString *reloadCommand) {
  NSString *normalizedAction = [Trimmed(action) lowercaseString];
  if ([normalizedAction isEqualToString:@"restart"]) {
    NSString *custom = ExpandedRuntimeCommandTemplate(restartCommand, @"restart", serviceName);
    return [custom length] > 0 ? custom : [NSString stringWithFormat:@"systemctl restart %@", ShellQuote(serviceName)];
  }
  NSString *custom = ExpandedRuntimeCommandTemplate(reloadCommand, @"reload", serviceName);
  return [custom length] > 0 ? custom : [NSString stringWithFormat:@"systemctl reload %@", ShellQuote(serviceName)];
}

static NSArray<NSString *> *NormalizedRequiredEnvironmentKeys(NSArray *keys) {
  NSMutableArray<NSString *> *normalized = [NSMutableArray array];
  NSMutableSet<NSString *> *seen = [NSMutableSet set];
  for (id entry in keys ?: @[]) {
    if (![entry isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *key = Trimmed(entry);
    if ([key length] == 0 || [seen containsObject:key]) {
      continue;
    }
    [seen addObject:key];
    [normalized addObject:key];
  }
  return normalized;
}

static BOOL EnvironmentDictionaryContainsNonEmptyValueForKey(NSDictionary *environment, NSString *key) {
  if (![key isKindOfClass:[NSString class]] || [key length] == 0) {
    return NO;
  }
  NSString *value = [environment[key] isKindOfClass:[NSString class]] ? environment[key] : nil;
  return [Trimmed(value) length] > 0;
}

static NSDictionary *DatabaseContractFromManifest(NSDictionary *manifest, NSDictionary *config) {
  NSDictionary *database = [manifest[@"database"] isKindOfClass:[NSDictionary class]] ? manifest[@"database"] : @{};
  NSDictionary *configuration = [manifest[@"configuration"] isKindOfClass:[NSDictionary class]] ? manifest[@"configuration"] : @{};
  NSString *target = [database[@"target"] isKindOfClass:[NSString class]] ? Trimmed(database[@"target"]) : @"";
  if ([target length] == 0) {
    target = @"default";
  }
  NSString *adapter = [database[@"adapter"] isKindOfClass:[NSString class]] ? Trimmed(database[@"adapter"]) : @"";
  if ([adapter length] == 0 && [config isKindOfClass:[NSDictionary class]]) {
    adapter = DatabaseAdapterNameFromConfigForTarget(config, target);
  }
  return @{
    @"schema" : [database[@"schema"] isKindOfClass:[NSString class]] ? database[@"schema"] : @"phase32-database-contract-v1",
    @"mode" : [database[@"mode"] isKindOfClass:[NSString class]] ? Trimmed(database[@"mode"]) : @"",
    @"adapter" : adapter ?: @"",
    @"target" : target ?: @"default",
    @"required_environment_keys" : NormalizedRequiredEnvironmentKeys(configuration[@"required_environment_keys"]),
  };
}

static NSDictionary *Phase39StateContractFromConfig(NSDictionary *config) {
  NSDictionary *state = [config[@"state"] isKindOfClass:[NSDictionary class]] ? config[@"state"] : @{};
  NSString *mode = [state[@"mode"] isKindOfClass:[NSString class]] ? Trimmed([state[@"mode"] lowercaseString]) : @"";
  NSString *target = [state[@"target"] isKindOfClass:[NSString class]] ? Trimmed(state[@"target"]) : @"";
  if ([target length] == 0) {
    target = @"default";
  }
  return @{
    @"schema" : @"phase39-state-contract-v1",
    @"durable" : @([state[@"durable"] respondsToSelector:@selector(boolValue)] && [state[@"durable"] boolValue]),
    @"mode" : mode ?: @"",
    @"target" : target ?: @"default",
  };
}

static BOOL Phase39ConfigDeclaresDurableState(NSDictionary *config,
                                              NSString *databaseMode,
                                              NSString *databaseTarget) {
  if (![config isKindOfClass:[NSDictionary class]]) {
    return NO;
  }

  NSDictionary *state = Phase39StateContractFromConfig(config);
  if ([state[@"durable"] boolValue]) {
    return YES;
  }

  if ([Trimmed(databaseMode) length] > 0) {
    return YES;
  }

  NSString *target = [Trimmed(databaseTarget) length] > 0 ? Trimmed(databaseTarget) : @"default";
  if ([DatabaseConnectionStringFromEnvironmentForTarget(target) length] > 0 ||
      [DatabaseConnectionStringFromConfigForTarget(config, target) length] > 0) {
    return YES;
  }

  return NO;
}

static NSArray<NSDictionary *> *Phase39MultiWorkerStateWarnings(NSDictionary *config,
                                                                NSString *environment,
                                                                NSString *databaseMode,
                                                                NSString *databaseTarget) {
  if (![[Trimmed(environment) lowercaseString] isEqualToString:@"production"] ||
      ![config isKindOfClass:[NSDictionary class]]) {
    return @[];
  }

  NSDictionary *propaneAccessories =
      [config[@"propaneAccessories"] isKindOfClass:[NSDictionary class]] ? config[@"propaneAccessories"] : @{};
  NSInteger workerCount = [propaneAccessories[@"workerCount"] respondsToSelector:@selector(integerValue)]
                               ? [propaneAccessories[@"workerCount"] integerValue]
                               : 4;
  if (workerCount <= 1 ||
      Phase39ConfigDeclaresDurableState(config, databaseMode, databaseTarget)) {
    return @[];
  }

  return @[
    @{
      @"id" : @"multi_worker_state",
      @"status" : @"warn",
      @"message" : [NSString stringWithFormat:@"production uses %ld propane workers without a declared durable state signal",
                                               (long)workerCount],
      @"hint" : @"Each propane worker has isolated process-local memory. Declare state.durable=YES with a durable mode/target, or declare a database deploy contract for app-owned request-spanning state.",
      @"worker_count" : @(workerCount),
    }
  ];
}

static void PrintDeployWarnings(NSArray<NSDictionary *> *warnings) {
  for (NSDictionary *warning in warnings ?: @[]) {
    NSString *message = [warning[@"message"] isKindOfClass:[NSString class]] ? warning[@"message"] : @"";
    NSString *hint = [warning[@"hint"] isKindOfClass:[NSString class]] ? warning[@"hint"] : @"";
    if ([message length] > 0) {
      fprintf(stderr, "arlen deploy: warning [%s] %s\n",
              [[warning[@"id"] description] UTF8String], [message UTF8String]);
    }
    if ([hint length] > 0) {
      fprintf(stderr, "arlen deploy: hint: %s\n", [hint UTF8String]);
    }
  }
}

static NSDictionary *RunHostLocalDatabaseProbe(NSString *adapter, NSString *connectionString) {
  NSString *normalizedAdapter = [[Trimmed(adapter) lowercaseString] copy];
  NSString *dsn = Trimmed(connectionString);
  if ([normalizedAdapter length] == 0) {
    return @{
      @"status" : @"warn",
      @"message" : @"host-local database contract declared without an adapter",
      @"hint" : @"Declare --database-adapter or configure database.adapter in app config.",
    };
  }

  if ([normalizedAdapter isEqualToString:@"postgresql"] || [normalizedAdapter isEqualToString:@"gdl2"]) {
    int commandCode = 0;
    NSString *pgIsReady = Trimmed(RunShellCaptureCommand(@"command -v pg_isready 2>/dev/null", &commandCode));
    if (commandCode == 0 && [pgIsReady length] > 0) {
      NSString *command = [dsn length] > 0
                              ? [NSString stringWithFormat:@"pg_isready -q -d %@", ShellQuote(dsn)]
                              : @"pg_isready -q";
      int exitCode = 0;
      NSString *output = RunShellCaptureCommand(command, &exitCode);
      return @{
        @"status" : (exitCode == 0) ? @"pass" : @"fail",
        @"message" : (exitCode == 0) ? @"host-local PostgreSQL probe succeeded"
                                     : @"host-local PostgreSQL probe failed",
        @"hint" : (exitCode == 0)
                      ? @""
                      : ([output length] > 0 ? output : @"Install/start PostgreSQL on the target host or change database.mode."),
      };
    }

    NSString *serviceOutput = nil;
    NSString *serviceState = ServiceRuntimeState(@"postgresql", &serviceOutput);
    if ([serviceState isEqualToString:@"active"]) {
      return @{
        @"status" : @"pass",
        @"message" : @"host-local PostgreSQL service is active",
        @"hint" : @"",
      };
    }
    return @{
      @"status" : @"fail",
      @"message" : @"host-local PostgreSQL contract is declared but no usable local service was detected",
      @"hint" : [serviceOutput length] > 0 ? serviceOutput : @"Install/start PostgreSQL or declare database.mode=external.",
    };
  }

  return @{
    @"status" : @"warn",
    @"message" : [NSString stringWithFormat:@"no host-local probe is implemented for adapter %@", normalizedAdapter ?: @""],
    @"hint" : @"Add adapter-specific host readiness validation before relying on host_local deployment for this database.",
  };
}

static NSDictionary *HealthContractFromManifest(NSDictionary *manifest) {
  NSDictionary *contract = [manifest[@"health_contract"] isKindOfClass:[NSDictionary class]]
                               ? manifest[@"health_contract"]
                               : nil;
  return contract ?: @{
    @"health_path" : @"/healthz",
    @"readiness_path" : @"/readyz",
    @"expected_ok_body" : @"ok",
  };
}

static NSDictionary *MigrationInventoryFromManifest(NSDictionary *manifest) {
  NSDictionary *inventory = [manifest[@"migration_inventory"] isKindOfClass:[NSDictionary class]]
                                ? manifest[@"migration_inventory"]
                                : nil;
  if (inventory != nil) {
    return inventory;
  }
  return @{
    @"count" : @0,
    @"files" : @[],
  };
}

static NSString *CurrentDeployArchitecture(void) {
#if defined(__aarch64__) || defined(__arm64__)
  return @"arm64";
#elif defined(__x86_64__) || defined(_M_X64) || defined(__amd64__)
  return @"x86_64";
#else
  return @"unknown";
#endif
}

static NSString *CurrentDeployPlatformProfile(void) {
  NSString *arch = CurrentDeployArchitecture();
#if defined(__APPLE__)
  return [NSString stringWithFormat:@"macos-%@-apple-foundation", arch ?: @"unknown"];
#elif defined(_WIN32)
  NSString *msystem = [[Trimmed(EnvValue("MSYSTEM")) uppercaseString] copy];
  NSString *variant = [msystem isEqualToString:@"CLANG64"] ? @"clang64" : @"msvc";
  return [NSString stringWithFormat:@"windows-%@-gnustep-%@", arch ?: @"unknown", variant];
#elif defined(__linux__)
  return [NSString stringWithFormat:@"linux-%@-gnustep-clang", arch ?: @"unknown"];
#else
  return [NSString stringWithFormat:@"unknown-%@-unknown", arch ?: @"unknown"];
#endif
}

static NSString *RuntimeFamilyForDeployProfile(NSString *profile) {
  NSString *value = Trimmed(profile);
  if ([value rangeOfString:@"apple-foundation"].location != NSNotFound) {
    return @"apple-foundation";
  }
  if ([value rangeOfString:@"gnustep"].location != NSNotFound) {
    return @"gnustep";
  }
  return @"unknown";
}

static NSDictionary *AssessDeployCompatibility(NSString *localProfile,
                                               NSString *targetProfile,
                                               BOOL allowRemoteRebuild) {
  NSString *resolvedLocal = [Trimmed(localProfile) length] > 0 ? Trimmed(localProfile) : CurrentDeployPlatformProfile();
  NSString *resolvedTarget = [Trimmed(targetProfile) length] > 0 ? Trimmed(targetProfile) : resolvedLocal;
  NSString *localFamily = RuntimeFamilyForDeployProfile(resolvedLocal);
  NSString *targetFamily = RuntimeFamilyForDeployProfile(resolvedTarget);
  BOOL remoteRebuildRequired = ![resolvedLocal isEqualToString:resolvedTarget];
  NSString *supportLevel = @"supported";
  NSString *reason = @"same_profile";

  if (remoteRebuildRequired) {
    if (!allowRemoteRebuild) {
      supportLevel = @"unsupported";
      reason = @"profile_mismatch_requires_remote_rebuild_opt_in";
    } else if (![localFamily isEqualToString:targetFamily]) {
      supportLevel = @"unsupported";
      reason = @"cross_runtime_family_remote_rebuild_not_supported";
    } else if ([localFamily isEqualToString:@"apple-foundation"]) {
      supportLevel = @"unsupported";
      reason = @"apple_cross_profile_remote_rebuild_not_supported";
    } else if ([localFamily isEqualToString:@"gnustep"]) {
      supportLevel = @"experimental";
      reason = @"gnustep_cross_profile_remote_rebuild";
    } else {
      supportLevel = @"unsupported";
      reason = @"profile_mismatch_not_supported";
    }
  }

  return @{
    @"schema" : @"phase32-deploy-target-v1",
    @"local_profile" : resolvedLocal ?: @"",
    @"target_profile" : resolvedTarget ?: @"",
    @"support_level" : supportLevel,
    @"compatibility_reason" : reason,
    @"allow_remote_rebuild" : @(allowRemoteRebuild),
    @"remote_rebuild_required" : @(remoteRebuildRequired),
    @"local_runtime_family" : localFamily ?: @"unknown",
    @"target_runtime_family" : targetFamily ?: @"unknown",
  };
}

static NSDictionary *DeploymentMetadataFromManifest(NSDictionary *manifest, BOOL allowRemoteRebuildFallback) {
  NSDictionary *deployment = [manifest[@"deployment"] isKindOfClass:[NSDictionary class]] ? manifest[@"deployment"] : nil;
  NSString *localProfile = [deployment[@"local_profile"] isKindOfClass:[NSString class]] ? deployment[@"local_profile"] : CurrentDeployPlatformProfile();
  NSString *targetProfile = [deployment[@"target_profile"] isKindOfClass:[NSString class]] ? deployment[@"target_profile"] : localProfile;
  BOOL allowRemoteRebuild = [deployment[@"allow_remote_rebuild"] respondsToSelector:@selector(boolValue)]
                                ? [deployment[@"allow_remote_rebuild"] boolValue]
                                : allowRemoteRebuildFallback;
  NSMutableDictionary *resolved = [AssessDeployCompatibility(localProfile, targetProfile, allowRemoteRebuild) mutableCopy];
  NSString *runtimeStrategy =
      [deployment[@"runtime_strategy"] isKindOfClass:[NSString class]] ? deployment[@"runtime_strategy"] : @"system";
  resolved[@"runtime_strategy"] = runtimeStrategy ?: @"system";
  resolved[@"manifest_version"] = [manifest[@"version"] isKindOfClass:[NSString class]] ? manifest[@"version"] : @"";
  if ([deployment[@"schema"] isKindOfClass:[NSString class]]) {
    resolved[@"schema"] = deployment[@"schema"];
  }
  return resolved;
}

static NSDictionary *PropaneHandoffFromManifest(NSDictionary *manifest, NSString *releaseDir) {
  NSDictionary *handoff = [manifest[@"propane_handoff"] isKindOfClass:[NSDictionary class]] ? manifest[@"propane_handoff"] : nil;
  NSDictionary *paths = ResolvedManifestPathsForRelease(manifest, releaseDir);
  NSString *managerBinary =
      [handoff[@"manager_binary"] isKindOfClass:[NSString class]]
          ? ResolveReleaseManifestPath(releaseDir, handoff[@"manager_binary"], paths[@"propane"])
          : ([paths[@"propane"] isKindOfClass:[NSString class]] ? paths[@"propane"] : @"");
  NSString *jobsWorkerBinary =
      [handoff[@"jobs_worker_binary"] isKindOfClass:[NSString class]]
          ? ResolveReleaseManifestPath(releaseDir, handoff[@"jobs_worker_binary"], paths[@"jobs_worker"])
          : ([paths[@"jobs_worker"] isKindOfClass:[NSString class]] ? paths[@"jobs_worker"] : @"");
  NSString *releaseEnvPath =
      [handoff[@"release_env_path"] isKindOfClass:[NSString class]]
          ? ResolveReleaseManifestPath(releaseDir, handoff[@"release_env_path"], paths[@"release_env"])
          : ([paths[@"release_env"] isKindOfClass:[NSString class]] ? paths[@"release_env"] : @"");
  return @{
    @"schema" : [handoff[@"schema"] isKindOfClass:[NSString class]] ? handoff[@"schema"] : @"phase32-propane-handoff-v1",
    @"manager" : @"propane",
    @"manager_binary" : managerBinary ?: @"",
    @"jobs_worker_binary" : jobsWorkerBinary ?: @"",
    @"release_env_path" : releaseEnvPath ?: @"",
    @"accessories_config_key" :
        [handoff[@"accessories_config_key"] isKindOfClass:[NSString class]] ? handoff[@"accessories_config_key"] : @"propaneAccessories",
    @"runtime_action_default" :
        [handoff[@"runtime_action_default"] isKindOfClass:[NSString class]] ? handoff[@"runtime_action_default"] : @"reload",
    @"activation_environment_keys" :
        [handoff[@"activation_environment_keys"] isKindOfClass:[NSArray class]] ? handoff[@"activation_environment_keys"] : @[ @"ARLEN_APP_ROOT", @"ARLEN_FRAMEWORK_ROOT", @"ARLEN_RELEASE_MANIFEST" ],
    @"ownership" : [handoff[@"ownership"] isKindOfClass:[NSDictionary class]] ? handoff[@"ownership"] : @{
      @"deploy" : @"release packaging and activation",
      @"propane" : @"process supervision and propane accessories",
    },
  };
}

static NSDictionary *ResolvedReleaseEnvForMetadata(NSDictionary *manifest, NSDictionary *releaseEnv, NSString *releaseDir) {
  NSMutableDictionary *resolved = [NSMutableDictionary dictionary];
  if ([releaseEnv isKindOfClass:[NSDictionary class]]) {
    [resolved addEntriesFromDictionary:releaseEnv];
  }
  NSDictionary *paths = ResolvedManifestPathsForRelease(manifest, releaseDir);
  NSDictionary *deployment = DeploymentMetadataFromManifest(manifest, NO);
  NSDictionary *databaseContract = DatabaseContractFromManifest(manifest, nil);
  NSDictionary *handoff = PropaneHandoffFromManifest(manifest, releaseDir);
  NSDictionary *certification =
      [manifest[@"certification"] isKindOfClass:[NSDictionary class]] ? manifest[@"certification"] : @{};
  NSDictionary *jsonPerformance =
      [manifest[@"json_performance"] isKindOfClass:[NSDictionary class]] ? manifest[@"json_performance"] : @{};

  resolved[@"RELEASE_ID"] = [manifest[@"release_id"] isKindOfClass:[NSString class]] ? manifest[@"release_id"] : ReleaseIDForDirectory(releaseDir);
  resolved[@"RELEASE_CREATED_UTC"] =
      [manifest[@"created_utc"] isKindOfClass:[NSString class]] ? manifest[@"created_utc"] : @"";
  resolved[@"ARLEN_RELEASE_ENV_LAYOUT"] = @"target-absolute";
  resolved[@"ARLEN_RELEASE_ROOT"] = releaseDir ?: @"";
  resolved[@"ARLEN_APP_ROOT"] = paths[@"app_root"] ?: @"";
  resolved[@"ARLEN_FRAMEWORK_ROOT"] = paths[@"framework_root"] ?: @"";
  resolved[@"ARLEN_RELEASE_MANIFEST"] = [releaseDir stringByAppendingPathComponent:@"metadata/manifest.json"] ?: @"";
  resolved[@"ARLEN_RELEASE_RUNTIME_BINARY"] = paths[@"runtime_binary"] ?: @"";
  resolved[@"ARLEN_RELEASE_FRAMEWORK_BOOMHAUER"] = paths[@"boomhauer"] ?: @"";
  resolved[@"ARLEN_RELEASE_ARLEN_BINARY"] = paths[@"arlen"] ?: @"";
  resolved[@"ARLEN_RELEASE_PROPANE"] = paths[@"propane"] ?: @"";
  resolved[@"ARLEN_RELEASE_JOBS_WORKER"] = paths[@"jobs_worker"] ?: @"";
  resolved[@"ARLEN_RELEASE_OPERABILITY_PROBE_HELPER"] = paths[@"operability_probe_helper"] ?: @"";
  resolved[@"ARLEN_RELEASE_CERTIFICATION_STATUS"] =
      [certification[@"status"] isKindOfClass:[NSString class]] ? certification[@"status"] : @"unknown";
  resolved[@"ARLEN_RELEASE_CERTIFICATION_MANIFEST"] =
      ResolveReleaseManifestPath(releaseDir, certification[@"manifest_path"], @"metadata/certification/manifest.json") ?: @"";
  resolved[@"ARLEN_JSON_PERFORMANCE_STATUS"] =
      [jsonPerformance[@"status"] isKindOfClass:[NSString class]] ? jsonPerformance[@"status"] : @"unknown";
  resolved[@"ARLEN_JSON_PERFORMANCE_MANIFEST"] =
      ResolveReleaseManifestPath(releaseDir, jsonPerformance[@"manifest_path"], @"metadata/json_performance/manifest.json") ?: @"";
  resolved[@"ARLEN_DEPLOY_LOCAL_PROFILE"] = deployment[@"local_profile"] ?: @"";
  resolved[@"ARLEN_DEPLOY_TARGET_PROFILE"] = deployment[@"target_profile"] ?: @"";
  resolved[@"ARLEN_DEPLOY_RUNTIME_STRATEGY"] = deployment[@"runtime_strategy"] ?: @"system";
  resolved[@"ARLEN_DEPLOY_SUPPORT_LEVEL"] = deployment[@"support_level"] ?: @"supported";
  resolved[@"ARLEN_DEPLOY_COMPATIBILITY_REASON"] = deployment[@"compatibility_reason"] ?: @"same_profile";
  resolved[@"ARLEN_DEPLOY_ALLOW_REMOTE_REBUILD"] =
      [deployment[@"allow_remote_rebuild"] boolValue] ? @"1" : @"0";
  resolved[@"ARLEN_DEPLOY_REMOTE_REBUILD_REQUIRED"] =
      [deployment[@"remote_rebuild_required"] boolValue] ? @"1" : @"0";
  resolved[@"ARLEN_DEPLOY_DATABASE_MODE"] = databaseContract[@"mode"] ?: @"";
  resolved[@"ARLEN_DEPLOY_DATABASE_ADAPTER"] = databaseContract[@"adapter"] ?: @"";
  resolved[@"ARLEN_DEPLOY_DATABASE_TARGET"] = databaseContract[@"target"] ?: @"default";
  resolved[@"ARLEN_DEPLOY_PROPANE_MANAGER_BINARY"] = handoff[@"manager_binary"] ?: @"";
  resolved[@"ARLEN_DEPLOY_PROPANE_ACCESSORIES_CONFIG_KEY"] = handoff[@"accessories_config_key"] ?: @"propaneAccessories";
  resolved[@"ARLEN_DEPLOY_PROPANE_RUNTIME_ACTION_DEFAULT"] = handoff[@"runtime_action_default"] ?: @"reload";
  resolved[@"ARLEN_DEPLOY_PROPANE_JOB_WORKER_BINARY"] = handoff[@"jobs_worker_binary"] ?: @"";
  return resolved;
}

static NSDictionary *RunRemoteBuildCheck(NSString *command) {
  NSString *trimmedCommand = Trimmed(command);
  if ([trimmedCommand length] == 0) {
    return @{
      @"status" : @"missing",
      @"captured_output" : @"",
      @"exit_code" : @1,
    };
  }

  int exitCode = 0;
  NSString *output = RunShellCaptureCommand(trimmedCommand, &exitCode);
  return @{
    @"status" : (exitCode == 0) ? @"ok" : @"error",
    @"command" : trimmedCommand ?: @"",
    @"captured_output" : output ?: @"",
    @"exit_code" : @(exitCode),
  };
}

static NSDictionary *RunDeployHealthProbe(NSString *frameworkRoot, NSString *helperPath, NSString *baseURL) {
  if ([baseURL length] == 0) {
    return @{
      @"status" : @"skipped",
      @"reason" : @"base_url_not_provided",
    };
  }

  NSString *scriptPath = [helperPath length] > 0 ? [helperPath stringByStandardizingPath] : nil;
  if ([scriptPath length] == 0) {
    scriptPath = [[frameworkRoot stringByAppendingPathComponent:@"tools/deploy/validate_operability.sh"]
        stringByStandardizingPath];
  }
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:scriptPath]) {
    return @{
      @"status" : @"error",
      @"base_url" : baseURL ?: @"",
      @"captured_output" :
          [NSString stringWithFormat:@"operability helper missing or not executable: %@", scriptPath],
      @"exit_code" : @127,
    };
  }
  int exitCode = 0;
  NSString *command = [NSString stringWithFormat:@"%@ --base-url %@", ShellQuote(scriptPath), ShellQuote(baseURL)];
  NSString *output = RunShellCaptureCommand(command, &exitCode);
  return @{
    @"status" : (exitCode == 0) ? @"ok" : @"error",
    @"base_url" : baseURL ?: @"",
    @"captured_output" : output ?: @"",
    @"exit_code" : @(exitCode),
  };
}

static NSDictionary *RunReleaseHealthProbeWithRetry(NSString *baseURL,
                                                    NSTimeInterval timeoutSeconds,
                                                    NSTimeInterval intervalSeconds) {
  NSString *trimmedBaseURL = [baseURL hasSuffix:@"/"] ? [baseURL substringToIndex:[baseURL length] - 1] : baseURL;
  NSString *healthURL = [trimmedBaseURL stringByAppendingString:@"/healthz"];
  NSTimeInterval timeout = timeoutSeconds > 0 ? timeoutSeconds : 30.0;
  NSTimeInterval interval = intervalSeconds > 0 ? intervalSeconds : 1.0;
  if (interval > timeout) {
    interval = timeout;
  }
  NSTimeInterval attemptTimeout = interval;
  if (attemptTimeout < 1.0) {
    attemptTimeout = 1.0;
  }
  if (attemptTimeout > 5.0) {
    attemptTimeout = 5.0;
  }
  NSString *healthCommand =
      [NSString stringWithFormat:@"curl --max-time %.3f -fsS %@", attemptTimeout, ShellQuote(healthURL)];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
  int exitCode = 1;
  NSString *output = @"";
  NSInteger attempts = 0;

  while (YES) {
    attempts += 1;
    output = RunShellCaptureCommand(healthCommand, &exitCode);
    NSString *trimmedOutput = Trimmed(output);
    if (exitCode == 0 && [trimmedOutput isEqualToString:@"ok"]) {
      return @{
        @"status" : @"ok",
        @"base_url" : baseURL ?: @"",
        @"health_path" : @"/healthz",
        @"command" : healthCommand ?: @"",
        @"captured_output" : output ?: @"",
        @"exit_code" : @(exitCode),
        @"attempts" : @(attempts),
        @"timeout_seconds" : @(timeout),
        @"interval_seconds" : @(interval),
      };
    }
    if ([[NSDate date] compare:deadline] != NSOrderedAscending) {
      break;
    }
    usleep((useconds_t)(interval * 1000000.0));
  }

  return @{
    @"status" : @"error",
    @"base_url" : baseURL ?: @"",
    @"health_path" : @"/healthz",
    @"command" : healthCommand ?: @"",
    @"captured_output" : output ?: @"",
    @"exit_code" : @(exitCode == 0 ? 1 : exitCode),
    @"attempts" : @(attempts),
    @"timeout_seconds" : @(timeout),
    @"interval_seconds" : @(interval),
  };
}

static NSDictionary *LoadReleaseMetadataAtDirectory(NSString *releaseDir) {
  NSString *manifestPath = [releaseDir stringByAppendingPathComponent:@"metadata/manifest.json"];
  NSString *releaseEnvPath = [releaseDir stringByAppendingPathComponent:@"metadata/release.env"];
  NSDictionary *manifest = JSONDictionaryFromFile(manifestPath) ?: @{};
  NSDictionary *releaseEnv = ResolvedReleaseEnvForMetadata(manifest, DictionaryFromReleaseEnvFile(releaseEnvPath), releaseDir);
  return @{
    @"manifest_path" : manifestPath ?: @"",
    @"release_env_path" : releaseEnvPath ?: @"",
    @"manifest" : manifest,
    @"release_env" : releaseEnv ?: @{},
  };
}

static NSDictionary *PlistDictionaryFromFile(NSString *path, NSError **error) {
  NSData *data = ALNDataReadFromFile(path, 0, error);
  if (data == nil) {
    return nil;
  }

  NSPropertyListFormat format = NSPropertyListOpenStepFormat;
  id parsed = [NSPropertyListSerialization propertyListWithData:data
                                                        options:NSPropertyListImmutable
                                                         format:&format
                                                          error:error];
  if (![parsed isKindOfClass:[NSDictionary class]]) {
    if (error != NULL && *error == nil) {
      *error = [NSError errorWithDomain:@"Arlen.Error"
                                   code:41
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     [NSString stringWithFormat:@"deploy config must be a dictionary: %@", path ?: @""]
                               }];
    }
    return nil;
  }
  return parsed;
}

static NSArray<NSString *> *StringArrayFromValue(id value) {
  if (![value isKindOfClass:[NSArray class]]) {
    return @[];
  }

  NSMutableArray<NSString *> *strings = [NSMutableArray array];
  for (id entry in (NSArray *)value) {
    if (![entry isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *trimmed = Trimmed(entry);
    if ([trimmed length] == 0) {
      continue;
    }
    [strings addObject:trimmed];
  }
  return SortedUniqueStrings(strings);
}

static NSArray<NSString *> *OrderedStringArrayFromValue(id value) {
  if (![value isKindOfClass:[NSArray class]]) {
    return @[];
  }

  NSMutableArray<NSString *> *strings = [NSMutableArray array];
  for (id entry in (NSArray *)value) {
    if (![entry isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *trimmed = Trimmed(entry);
    if ([trimmed length] == 0) {
      continue;
    }
    [strings addObject:trimmed];
  }
  return strings;
}

static NSString *StringValueForDeployKey(NSDictionary *dictionary, NSString *key) {
  id value = dictionary[key];
  return [value isKindOfClass:[NSString class]] ? Trimmed(value) : @"";
}

static NSString *SystemdUnitFilenameForServiceName(NSString *serviceName) {
  NSString *trimmed = Trimmed(serviceName);
  if ([trimmed length] == 0) {
    return @"arlen.service";
  }
  return [trimmed hasSuffix:@".service"] ? trimmed : [trimmed stringByAppendingString:@".service"];
}

static NSString *DeployConfigPathAtAppRoot(NSString *appRoot) {
  return [[appRoot stringByAppendingPathComponent:@"config/deploy.plist"] stringByStandardizingPath];
}

static BOOL BoolValueForDeployKey(id value, BOOL defaultValue) {
  if ([value respondsToSelector:@selector(boolValue)]) {
    return [value boolValue];
  }
  if ([value isKindOfClass:[NSString class]]) {
    NSString *normalized = [[Trimmed(value) lowercaseString] copy];
    if ([normalized isEqualToString:@"yes"] || [normalized isEqualToString:@"true"] ||
        [normalized isEqualToString:@"1"] || [normalized isEqualToString:@"on"]) {
      return YES;
    }
    if ([normalized isEqualToString:@"no"] || [normalized isEqualToString:@"false"] ||
        [normalized isEqualToString:@"0"] || [normalized isEqualToString:@"off"]) {
      return NO;
    }
  }
  return defaultValue;
}

static NSTimeInterval TimeIntervalValueForDeployKey(id value, NSTimeInterval defaultValue) {
  if ([value respondsToSelector:@selector(doubleValue)]) {
    NSTimeInterval parsed = [value doubleValue];
    return parsed > 0 ? parsed : defaultValue;
  }
  if ([value isKindOfClass:[NSString class]]) {
    NSTimeInterval parsed = [Trimmed(value) doubleValue];
    return parsed > 0 ? parsed : defaultValue;
  }
  return defaultValue;
}

static BOOL SetExecutablePermissions(NSString *path, NSError **error) {
  return [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions : @0755 }
                                          ofItemAtPath:path
                                                 error:error];
}

static NSDictionary *DeployTargetPayload(NSDictionary *target) {
  if (![target isKindOfClass:[NSDictionary class]]) {
    return @{};
  }
  return @{
    @"schema" : @"phase32-deploy-targets-v1",
    @"name" : StringValueForDeployKey(target, @"name"),
    @"config_path" : StringValueForDeployKey(target, @"config_path"),
    @"release_path" : StringValueForDeployKey(target, @"release_path"),
    @"releases_dir" : StringValueForDeployKey(target, @"releases_dir"),
    @"profile" : StringValueForDeployKey(target, @"profile"),
    @"runtime_strategy" : StringValueForDeployKey(target, @"runtime_strategy"),
    @"runtime_action" : StringValueForDeployKey(target, @"runtime_action"),
    @"environment" : StringValueForDeployKey(target, @"environment"),
    @"service" : StringValueForDeployKey(target, @"service"),
    @"base_url" : StringValueForDeployKey(target, @"base_url"),
    @"env_file" : StringValueForDeployKey(target, @"env_file"),
    @"remote_enabled" : @([target[@"remote_enabled"] boolValue]),
    @"ssh_host" : StringValueForDeployKey(target, @"ssh_host"),
    @"runtime" : @{
      @"family" : RuntimeFamilyForDeployProfile(StringValueForDeployKey(target, @"profile")),
      @"gnustep_script" : StringValueForDeployKey(target, @"gnustep_script"),
      @"requires_env_wrapper" : @([target[@"requires_env_wrapper"] boolValue]),
      @"propane_wrapper" : StringValueForDeployKey(target, @"propane_wrapper"),
      @"jobs_worker_wrapper" : StringValueForDeployKey(target, @"jobs_worker_wrapper"),
    },
    @"database" : @{
      @"mode" : StringValueForDeployKey(target, @"database_mode"),
      @"adapter" : StringValueForDeployKey(target, @"database_adapter"),
      @"target" : StringValueForDeployKey(target, @"database_target"),
    },
    @"configuration" : @{
      @"required_environment_keys" :
          [target[@"required_environment_keys"] isKindOfClass:[NSArray class]] ? target[@"required_environment_keys"] : @[],
    },
  };
}

static NSString *DeployTargetSamplePlist(NSString *targetName, NSString *sshHost) {
  NSString *name = [Trimmed(targetName) length] > 0 ? Trimmed(targetName) : @"production";
  NSString *host = [Trimmed(sshHost) length] > 0 ? Trimmed(sshHost) : @"deploy@app.example.com";
  return [NSString stringWithFormat:
      @"/*\n"
       "  Arlen deploy target sample.\n"
       "\n"
       "  Copy this file to config/deploy.plist, edit the placeholders, then run:\n"
       "    arlen deploy list\n"
       "    arlen deploy dryrun %@\n"
       "    arlen deploy init %@\n"
       "    arlen deploy doctor %@\n"
       "    arlen deploy push %@\n"
       "\n"
       "  OpenStep plist comments are supported by GNUstep property-list parsing.\n"
       "*/\n"
       "{\n"
       "  deployment = {\n"
       "    /* Schema marker for Arlen's named deploy target contract. */\n"
       "    schema = \"phase32-deploy-targets-v1\";\n"
       "\n"
       "    targets = {\n"
       "      %@ = {\n"
       "        /* Human-readable host label shown in deploy list output. */\n"
       "        host = \"app.example.com\";\n"
       "\n"
       "        /* Target release root. Arlen creates releases/, shared/, logs/, and tmp/ under this path. */\n"
       "        releasePath = \"/srv/arlen/app\";\n"
       "\n"
       "        /* Keep this aligned with the host GNUstep/clang runtime family. */\n"
       "        profile = \"linux-x86_64-gnustep-clang\";\n"
       "\n"
       "        /* system = host already has runtime; managed/bundled are reserved for stricter runtime control. */\n"
       "        runtimeStrategy = \"system\";\n"
       "\n"
       "        /* Use none until the service unit exists; restart is common after systemd setup. */\n"
       "        runtimeAction = \"none\";\n"
       "\n"
       "        /* App config environment used for release activation and migrations. */\n"
       "        environment = \"production\";\n"
       "\n"
       "        /* Optional systemd unit name for status/log/reload integration. */\n"
       "        service = \"arlen@app\";\n"
       "\n"
       "        /* Optional health probe base URL for release/status/doctor. */\n"
       "        baseURL = \"http://127.0.0.1:3000\";\n"
       "\n"
       "        database = {\n"
       "          /* external, host_local, or embedded. */\n"
       "          mode = \"host_local\";\n"
       "          adapter = \"postgresql\";\n"
       "          target = \"default\";\n"
       "        };\n"
       "\n"
       "        configuration = {\n"
       "          /* Target env file materialized by deploy init samples and runtime wrappers. */\n"
       "          envFile = \"/etc/arlen/app.env\";\n"
       "          requiredEnvironmentKeys = (\"ARLEN_DATABASE_URL\", \"ARLEN_SESSION_SECRET\");\n"
       "        };\n"
       "\n"
       "        runtime = {\n"
       "          /* GNUstep environment script on the target host. */\n"
       "          gnustepScript = \"/usr/GNUstep/System/Library/Makefiles/GNUstep.sh\";\n"
       "          requiresEnvWrapper = YES;\n"
       "        };\n"
       "\n"
       "        init = {\n"
       "          runtimeUser = \"arlen\";\n"
       "          runtimeGroup = \"arlen\";\n"
       "        };\n"
       "\n"
       "        transport = {\n"
       "          /* Remove transport for local-only targets. With transport present, push/release use SSH. */\n"
       "          sshHost = \"%@\";\n"
       "          sshCommand = \"ssh\";\n"
       "          sshOptions = (\"-oBatchMode=yes\");\n"
       "        };\n"
       "      };\n"
       "    };\n"
       "  };\n"
       "}\n",
      name, name, name, name, name, host];
}

static NSDictionary *LoadDeployTargetNamed(NSString *appRoot, NSString *targetName, NSError **error) {
  NSString *configPath = DeployConfigPathAtAppRoot(appRoot);
  if (!PathExists(configPath, NULL)) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Arlen.Error"
                                   code:42
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     [NSString stringWithFormat:@"missing deploy target config: %@", configPath ?: @""]
                               }];
    }
    return nil;
  }

  NSDictionary *root = PlistDictionaryFromFile(configPath, error);
  if (root == nil) {
    return nil;
  }

  NSDictionary *deployment = [root[@"deployment"] isKindOfClass:[NSDictionary class]] ? root[@"deployment"] : root;
  NSDictionary *targets = [deployment[@"targets"] isKindOfClass:[NSDictionary class]] ? deployment[@"targets"] : nil;
  NSDictionary *rawTarget = [targets[targetName] isKindOfClass:[NSDictionary class]] ? targets[targetName] : nil;
  if (targets == nil || rawTarget == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Arlen.Error"
                                   code:43
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     [NSString stringWithFormat:@"unknown deploy target '%@' in %@", targetName ?: @"",
                                                                configPath ?: @""]
                               }];
    }
    return nil;
  }

  NSDictionary *transport = [rawTarget[@"transport"] isKindOfClass:[NSDictionary class]] ? rawTarget[@"transport"] : @{};
  NSDictionary *database = [rawTarget[@"database"] isKindOfClass:[NSDictionary class]] ? rawTarget[@"database"] : @{};
  NSDictionary *configuration =
      [rawTarget[@"configuration"] isKindOfClass:[NSDictionary class]] ? rawTarget[@"configuration"] : @{};
  NSDictionary *init = [rawTarget[@"init"] isKindOfClass:[NSDictionary class]] ? rawTarget[@"init"] : @{};
  NSDictionary *runtime = [rawTarget[@"runtime"] isKindOfClass:[NSDictionary class]] ? rawTarget[@"runtime"] : @{};

  NSString *releasePath = StringValueForDeployKey(rawTarget, @"releasePath");
  if ([releasePath length] == 0) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Arlen.Error"
                                   code:44
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     [NSString stringWithFormat:@"deploy target '%@' is missing releasePath", targetName ?: @""]
                               }];
    }
    return nil;
  }

  NSString *serviceName = StringValueForDeployKey(rawTarget, @"service");
  if ([serviceName length] == 0) {
    serviceName = [NSString stringWithFormat:@"arlen@%@", targetName ?: @"app"];
  }

  NSString *envFile = StringValueForDeployKey(configuration, @"envFile");
  if ([envFile length] == 0) {
    envFile = [NSString stringWithFormat:@"/etc/arlen/%@.env", targetName ?: @"app"];
  }

  NSString *generatedDir =
      [[appRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"build/deploy/targets/%@", targetName ?: @"default"]]
          stringByStandardizingPath];
  NSString *releasesDir = [StringValueForDeployKey(rawTarget, @"releasesDir") length] > 0
                              ? StringValueForDeployKey(rawTarget, @"releasesDir")
                              : [releasePath stringByAppendingPathComponent:@"releases"];
  NSString *profile = StringValueForDeployKey(rawTarget, @"profile");
  NSString *runtimeFamily = RuntimeFamilyForDeployProfile(profile);
  BOOL targetUsesGNUstep = [runtimeFamily isEqualToString:@"gnustep"];
  NSString *gnustepScript = StringValueForDeployKey(runtime, @"gnustepScript");
  if ([gnustepScript length] == 0 && targetUsesGNUstep) {
    gnustepScript = DefaultGNUstepScriptPath();
  }
  BOOL requiresEnvWrapper =
      BoolValueForDeployKey(runtime[@"requiresEnvWrapper"], targetUsesGNUstep);
  NSString *binDir = [[generatedDir stringByAppendingPathComponent:@"bin"] stringByStandardizingPath];

  return @{
    @"schema" : @"phase32-deploy-targets-v1",
    @"name" : targetName ?: @"",
    @"config_path" : configPath ?: @"",
    @"host" : StringValueForDeployKey(rawTarget, @"host"),
    @"release_path" : releasePath ?: @"",
    @"releases_dir" : [releasesDir stringByStandardizingPath],
    @"shared_dir" : [[releasePath stringByAppendingPathComponent:@"shared"] stringByStandardizingPath],
    @"logs_dir" : [[releasePath stringByAppendingPathComponent:@"logs"] stringByStandardizingPath],
    @"tmp_dir" : [[releasePath stringByAppendingPathComponent:@"tmp"] stringByStandardizingPath],
    @"local_staging_releases_dir" : [[generatedDir stringByAppendingPathComponent:@"local-releases"] stringByStandardizingPath],
    @"generated_dir" : generatedDir ?: @"",
    @"profile" : profile ?: @"",
    @"runtime_family" : runtimeFamily ?: @"unknown",
    @"runtime_strategy" : StringValueForDeployKey(rawTarget, @"runtimeStrategy"),
    @"runtime_action" : StringValueForDeployKey(rawTarget, @"runtimeAction"),
    @"runtime_restart_command" : StringValueForDeployKey(rawTarget, @"runtimeRestartCommand"),
    @"runtime_reload_command" : StringValueForDeployKey(rawTarget, @"runtimeReloadCommand"),
    @"health_startup_timeout_seconds" : @(TimeIntervalValueForDeployKey(rawTarget[@"healthStartupTimeoutSeconds"], 30.0)),
    @"health_startup_interval_seconds" : @(TimeIntervalValueForDeployKey(rawTarget[@"healthStartupIntervalSeconds"], 1.0)),
    @"environment" : StringValueForDeployKey(rawTarget, @"environment"),
    @"service" : serviceName ?: @"",
    @"base_url" : StringValueForDeployKey(rawTarget, @"baseURL"),
    @"database_mode" : StringValueForDeployKey(database, @"mode"),
    @"database_adapter" : StringValueForDeployKey(database, @"adapter"),
    @"database_target" : [StringValueForDeployKey(database, @"target") length] > 0 ? StringValueForDeployKey(database, @"target") : @"default",
    @"required_environment_keys" : StringArrayFromValue(configuration[@"requiredEnvironmentKeys"]),
    @"env_file" : envFile ?: @"",
    @"runtime_user" : [StringValueForDeployKey(init, @"runtimeUser") length] > 0 ? StringValueForDeployKey(init, @"runtimeUser") : @"arlen",
    @"runtime_group" : [StringValueForDeployKey(init, @"runtimeGroup") length] > 0 ? StringValueForDeployKey(init, @"runtimeGroup") : @"arlen",
    @"gnustep_script" : gnustepScript ?: @"",
    @"requires_env_wrapper" : @(requiresEnvWrapper),
    @"propane_wrapper" : [binDir stringByAppendingPathComponent:@"propane-wrapper"],
    @"jobs_worker_wrapper" : [binDir stringByAppendingPathComponent:@"jobs-worker-wrapper"],
    @"ssh_host" : StringValueForDeployKey(transport, @"sshHost"),
    @"ssh_command" : [StringValueForDeployKey(transport, @"sshCommand") length] > 0 ? StringValueForDeployKey(transport, @"sshCommand") : @"ssh",
    @"ssh_options" : OrderedStringArrayFromValue(transport[@"sshOptions"]),
    @"remote_tmp_dir" : [StringValueForDeployKey(transport, @"remoteTmpDir") length] > 0 ? StringValueForDeployKey(transport, @"remoteTmpDir") : @"/tmp",
    @"remote_enabled" : @([StringValueForDeployKey(transport, @"sshHost") length] > 0),
    @"systemd_unit_filename" : SystemdUnitFilenameForServiceName(serviceName),
  };
}

static NSArray<NSDictionary *> *LoadDeployTargets(NSString *appRoot, NSString **configPathOut, NSError **error) {
  NSString *configPath = DeployConfigPathAtAppRoot(appRoot);
  if (configPathOut != NULL) {
    *configPathOut = configPath;
  }
  if (!PathExists(configPath, NULL)) {
    return @[];
  }

  NSDictionary *root = PlistDictionaryFromFile(configPath, error);
  if (root == nil) {
    return nil;
  }
  NSDictionary *deployment = [root[@"deployment"] isKindOfClass:[NSDictionary class]] ? root[@"deployment"] : root;
  NSDictionary *targets = [deployment[@"targets"] isKindOfClass:[NSDictionary class]] ? deployment[@"targets"] : nil;
  if (targets == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Arlen.Error"
                                   code:45
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     [NSString stringWithFormat:@"deploy target config is missing targets: %@", configPath ?: @""]
                               }];
    }
    return nil;
  }

  NSMutableArray<NSDictionary *> *resolvedTargets = [NSMutableArray array];
  NSArray<NSString *> *targetNames = [[targets allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *targetName in targetNames) {
    NSError *targetError = nil;
    NSDictionary *target = LoadDeployTargetNamed(appRoot, targetName, &targetError);
    if (target == nil) {
      if (error != NULL) {
        *error = targetError;
      }
      return nil;
    }
    [resolvedTargets addObject:target];
  }
  return resolvedTargets;
}

static NSArray<NSDictionary *> *DeployTargetPayloads(NSArray<NSDictionary *> *targets) {
  NSMutableArray<NSDictionary *> *payloads = [NSMutableArray array];
  for (NSDictionary *target in targets ?: @[]) {
    [payloads addObject:DeployTargetPayload(target)];
  }
  return payloads;
}

static NSArray<NSString *> *MissingInitializedDeployTargetPaths(NSDictionary *target) {
  NSMutableArray<NSString *> *missing = [NSMutableArray array];
  NSArray<NSString *> *requiredPaths = @[
    StringValueForDeployKey(target, @"release_path"),
    StringValueForDeployKey(target, @"releases_dir"),
    StringValueForDeployKey(target, @"shared_dir"),
    StringValueForDeployKey(target, @"logs_dir"),
    StringValueForDeployKey(target, @"tmp_dir"),
    StringValueForDeployKey(target, @"generated_dir"),
    StringValueForDeployKey(target, @"propane_wrapper"),
    StringValueForDeployKey(target, @"jobs_worker_wrapper"),
    [[StringValueForDeployKey(target, @"generated_dir") stringByAppendingPathComponent:@"systemd"]
        stringByAppendingPathComponent:StringValueForDeployKey(target, @"systemd_unit_filename")],
  ];
  for (NSString *path in requiredPaths) {
    if ([path length] > 0 && !PathExists(path, NULL)) {
      [missing addObject:path];
    }
  }
  return missing;
}

static BOOL DeployTargetIsInitialized(NSDictionary *target, NSArray<NSString *> **missingPathsOut) {
  NSArray<NSString *> *missing = MissingInitializedDeployTargetPaths(target);
  if (missingPathsOut != NULL) {
    *missingPathsOut = missing;
  }
  return [missing count] == 0;
}

static NSString *RenderedSystemdUnitForTarget(NSDictionary *target, NSString *frameworkRoot) {
  NSString *templatePath = [frameworkRoot stringByAppendingPathComponent:@"tools/deploy/systemd/arlen@.service"];
  NSString *template = [NSString stringWithContentsOfFile:templatePath encoding:NSUTF8StringEncoding error:NULL];
  if ([template length] == 0) {
    template = @"[Unit]\nDescription=Arlen site %i\n\n[Service]\nType=simple\nUser=arlen\nGroup=arlen\nWorkingDirectory=/srv/arlen/%i/releases/current/app\nEnvironment=ARLEN_APP_ROOT=/srv/arlen/%i/releases/current/app\nEnvironment=ARLEN_FRAMEWORK_ROOT=/srv/arlen/%i/releases/current/framework\nEnvironmentFile=-/etc/arlen/%i.env\nExecStart=/srv/arlen/%i/releases/current/framework/bin/propane --env production\nExecReload=/bin/kill -HUP $MAINPID\nRestart=always\n\n[Install]\nWantedBy=multi-user.target\n";
  }

  NSString *targetName = StringValueForDeployKey(target, @"name");
  NSString *releasePath = StringValueForDeployKey(target, @"release_path");
  NSString *envFile = StringValueForDeployKey(target, @"env_file");
  NSString *runtimeUser = StringValueForDeployKey(target, @"runtime_user");
  NSString *runtimeGroup = StringValueForDeployKey(target, @"runtime_group");
  NSString *environment = [StringValueForDeployKey(target, @"environment") length] > 0 ? StringValueForDeployKey(target, @"environment") : @"production";
  NSString *serviceName = StringValueForDeployKey(target, @"service");
  NSString *execStart =
      [target[@"requires_env_wrapper"] boolValue]
          ? (StringValueForDeployKey(target, @"propane_wrapper") ?: @"")
          : [[[releasePath stringByAppendingPathComponent:@"releases/current/framework/bin/propane"] stringByStandardizingPath]
                stringByAppendingFormat:@" --env %@", environment ?: @"production"];

  NSString *content = [template copy];
  content = [content stringByReplacingOccurrencesOfString:@"Description=Arlen site %i"
                                               withString:[NSString stringWithFormat:@"Description=Arlen site %@", targetName ?: @"app"]];
  content = [content stringByReplacingOccurrencesOfString:@"ExecStart=/srv/arlen/%i/releases/current/framework/bin/propane --env production"
                                               withString:[NSString stringWithFormat:@"ExecStart=%@", execStart ?: @""]];
  content = [content stringByReplacingOccurrencesOfString:@"/srv/arlen/%i" withString:releasePath ?: @"/srv/arlen/app"];
  content = [content stringByReplacingOccurrencesOfString:@"/etc/arlen/%i.env" withString:envFile ?: @"/etc/arlen/app.env"];
  content = [content stringByReplacingOccurrencesOfString:@"User=arlen" withString:[NSString stringWithFormat:@"User=%@", runtimeUser ?: @"arlen"]];
  content = [content stringByReplacingOccurrencesOfString:@"Group=arlen" withString:[NSString stringWithFormat:@"Group=%@", runtimeGroup ?: @"arlen"]];
  content = [content stringByReplacingOccurrencesOfString:@"SyslogIdentifier=arlen-%i"
                                               withString:[NSString stringWithFormat:@"SyslogIdentifier=%@",
                                                                             [serviceName stringByReplacingOccurrencesOfString:@".service" withString:@""]]];
  return content;
}

static NSString *RenderedGNUstepWrapperForTarget(NSDictionary *target, NSString *toolName) {
  NSString *gnustepScript = StringValueForDeployKey(target, @"gnustep_script");
  NSString *releasePath = StringValueForDeployKey(target, @"release_path");
  NSString *environment = [StringValueForDeployKey(target, @"environment") length] > 0 ? StringValueForDeployKey(target, @"environment") : @"production";
  BOOL requiresWrapper = [target[@"requires_env_wrapper"] boolValue];
  NSString *binaryPath = nil;
  if ([toolName isEqualToString:@"propane"]) {
    binaryPath = [[releasePath stringByAppendingPathComponent:@"releases/current/framework/bin/propane"] stringByStandardizingPath];
  } else {
    binaryPath = [[releasePath stringByAppendingPathComponent:@"releases/current/framework/bin/jobs-worker"] stringByStandardizingPath];
  }
  NSString *argumentSuffix = [toolName isEqualToString:@"propane"] ? [NSString stringWithFormat:@" --env %@", environment ?: @"production"] : @"";
  if (!requiresWrapper || [gnustepScript length] == 0) {
    return [NSString stringWithFormat:
        @"#!/usr/bin/env bash\n"
         "set -euo pipefail\n"
         "exec %@%@ \"$@\"\n",
        ShellQuote(binaryPath ?: @""), argumentSuffix ?: @""];
  }
  return [NSString stringWithFormat:
      @"#!/usr/bin/env bash\n"
       "set -euo pipefail\n"
       "GNUSTEP_SCRIPT=%@\n"
       "if [ ! -f \"$GNUSTEP_SCRIPT\" ]; then\n"
       "  echo \"missing GNUstep.sh: $GNUSTEP_SCRIPT\" >&2\n"
       "  exit 1\n"
       "fi\n"
       "set +u\n"
       "source \"$GNUSTEP_SCRIPT\"\n"
       "set -u\n"
       "exec %@%@ \"$@\"\n",
      ShellQuote(gnustepScript ?: @""), ShellQuote(binaryPath ?: @""), argumentSuffix ?: @""];
}

static NSString *RenderedEnvExampleForTarget(NSDictionary *target, NSString *frameworkRoot) {
  NSString *templatePath = [frameworkRoot stringByAppendingPathComponent:@"tools/deploy/systemd/site.env.example"];
  NSString *template = [NSString stringWithContentsOfFile:templatePath encoding:NSUTF8StringEncoding error:NULL];
  if ([template length] == 0) {
    template = @"ARLEN_HOST=127.0.0.1\nARLEN_PORT=3000\nARLEN_DATABASE_URL=postgres://app:CHANGE_ME@127.0.0.1/app_production\nARLEN_SESSION_SECRET=replace-with-32-plus-character-secret\n";
  }

  NSString *targetName = StringValueForDeployKey(target, @"name");
  NSString *releasePath = StringValueForDeployKey(target, @"release_path");
  NSMutableString *content =
      [[template stringByReplacingOccurrencesOfString:@"/srv/arlen/<site>" withString:releasePath ?: @"/srv/arlen/app"] mutableCopy];
  [content appendString:
               @"\n# Do not pin ARLEN_APP_ROOT or ARLEN_FRAMEWORK_ROOT here.\n"
                "# Release activation owns those paths.\n"];
  for (NSString *requiredKey in [target[@"required_environment_keys"] isKindOfClass:[NSArray class]]
                                   ? target[@"required_environment_keys"]
                                   : @[]) {
    if ([content rangeOfString:[NSString stringWithFormat:@"%@=", requiredKey]].location == NSNotFound) {
      [content appendFormat:@"%@=CHANGE_ME_%@\n", requiredKey, [targetName uppercaseString]];
    }
  }
  return content;
}

static NSString *RenderedInitReadmeForTarget(NSDictionary *target) {
  NSString *serviceFile = StringValueForDeployKey(target, @"systemd_unit_filename");
  NSString *generatedDir = StringValueForDeployKey(target, @"generated_dir");
  NSString *envFile = StringValueForDeployKey(target, @"env_file");
  NSString *runtimeFamily = StringValueForDeployKey(target, @"runtime_family");
  NSString *gnustepScript = StringValueForDeployKey(target, @"gnustep_script");
  BOOL requiresWrapper = [target[@"requires_env_wrapper"] boolValue];
  return [NSString stringWithFormat:
      @"Arlen deploy init generated deterministic host artifacts for target %@.\n\n"
       "Created host layout:\n"
       "- %@\n"
       "- %@\n"
       "- %@\n"
       "- %@\n\n"
       "Generated artifacts:\n"
       "- %@/systemd/%@\n"
       "- %@/env/%@.env.example\n"
       "- %@/bin/propane-wrapper\n"
       "- %@/bin/jobs-worker-wrapper\n\n"
       "Runtime contract:\n"
       "- runtime family: %@\n"
       "- GNUstep script: %@\n"
       "- requires env wrapper: %@\n\n"
       "Operator follow-up still required:\n"
       "- create the runtime user/group if your host does not already provide them\n"
       "- install the systemd unit under /etc/systemd/system/\n"
       "- install the generated wrappers on GNUstep-backed hosts when runtime env sourcing is required\n"
       "- copy the env example to %@ and populate secret values\n"
       "- reload systemd and enable/start the service\n",
      StringValueForDeployKey(target, @"name"),
      StringValueForDeployKey(target, @"release_path"),
      StringValueForDeployKey(target, @"releases_dir"),
      StringValueForDeployKey(target, @"shared_dir"),
      StringValueForDeployKey(target, @"logs_dir"),
      generatedDir, serviceFile, generatedDir, StringValueForDeployKey(target, @"name"),
      generatedDir, generatedDir, runtimeFamily ?: @"unknown", gnustepScript ?: @"",
      requiresWrapper ? @"yes" : @"no", envFile];
}

static NSArray<NSString *> *SSHArgumentsForTarget(NSDictionary *target, NSString *remoteScript) {
  NSMutableArray<NSString *> *arguments = [NSMutableArray array];
  [arguments addObject:StringValueForDeployKey(target, @"ssh_command") ?: @"ssh"];
  for (NSString *option in [target[@"ssh_options"] isKindOfClass:[NSArray class]] ? target[@"ssh_options"] : @[]) {
    [arguments addObject:option ?: @""];
  }
  [arguments addObject:StringValueForDeployKey(target, @"ssh_host") ?: @""];
  NSString *remoteCommand = [NSString stringWithFormat:@"bash -lc %@",
                                                       ShellQuote(remoteScript ?: @"true")];
  [arguments addObject:remoteCommand];
  return arguments;
}

static NSDictionary *RunSSHCommandForTarget(NSDictionary *target, NSString *remoteScript) {
  NSArray<NSString *> *arguments = SSHArgumentsForTarget(target, remoteScript);
  int exitCode = 0;
  NSString *capturedOutput = RunTaskCapture(@"/usr/bin/env", arguments, &exitCode);
  return @{
    @"status" : (exitCode == 0) ? @"ok" : @"error",
    @"command" : TaskCommandDescription(@"/usr/bin/env", arguments),
    @"captured_output" : capturedOutput ?: @"",
    @"exit_code" : @(exitCode),
  };
}

static NSDictionary *ReleaseInventoryItem(NSString *releaseID,
                                          NSString *releaseDir,
                                          NSString *state,
                                          NSString *source,
                                          BOOL allowRemoteRebuild) {
  NSString *manifestPath = [releaseDir length] > 0 ? [releaseDir stringByAppendingPathComponent:@"metadata/manifest.json"] : @"";
  NSDictionary *manifest = [manifestPath length] > 0 ? (JSONDictionaryFromFile(manifestPath) ?: @{}) : @{};
  return @{
    @"id" : releaseID ?: @"",
    @"state" : state ?: @"available",
    @"source" : source ?: @"local",
    @"path" : releaseDir ?: @"",
    @"manifest_path" : manifestPath ?: @"",
    @"manifest_version" : manifest[@"version"] ?: @"",
    @"deployment" : DeploymentMetadataFromManifest(manifest, allowRemoteRebuild),
    @"propane_handoff" : PropaneHandoffFromManifest(manifest, releaseDir),
  };
}

static NSArray<NSDictionary *> *LocalReleaseInventory(NSString *releasesDir,
                                                       NSString *activeReleaseID,
                                                       NSString *previousReleaseID,
                                                       BOOL allowRemoteRebuild) {
  NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
  for (NSString *releaseID in SortedReleaseDirectories(releasesDir)) {
    NSString *state = [releaseID isEqualToString:activeReleaseID ?: @""] ? @"active"
                    : [releaseID isEqualToString:previousReleaseID ?: @""] ? @"previous"
                    : @"available";
    NSString *releaseDir = [releasesDir stringByAppendingPathComponent:releaseID];
    [items addObject:ReleaseInventoryItem(releaseID, releaseDir, state, @"local", allowRemoteRebuild)];
  }
  return items;
}

static NSDictionary *RemoteReleaseInventory(NSDictionary *target) {
  NSString *remoteReleasesDir = StringValueForDeployKey(target, @"releases_dir");
  NSString *remoteScript = [NSString stringWithFormat:
      @"set -euo pipefail\n"
       "releases_dir=%@\n"
       "active=\"\"\n"
       "if [ -e \"$releases_dir/current\" ]; then active=$(readlink -f \"$releases_dir/current\" 2>/dev/null || true); fi\n"
       "if [ -d \"$releases_dir\" ]; then\n"
       "  for d in \"$releases_dir\"/*; do\n"
       "    [ -d \"$d\" ] || continue\n"
       "    id=$(basename \"$d\")\n"
       "    [ \"$id\" = \"current\" ] && continue\n"
       "    [ \"$id\" = \"latest-built\" ] && continue\n"
       "    state=\"available\"\n"
       "    resolved=$(readlink -f \"$d\" 2>/dev/null || printf '%%s' \"$d\")\n"
       "    if [ -n \"$active\" ] && [ \"$resolved\" = \"$active\" ]; then state=\"active\"; fi\n"
       "    printf 'ARLEN_RELEASE\\t%%s\\t%%s\\t%%s\\t' \"$id\" \"$state\" \"$d\"\n"
       "    if [ -f \"$d/metadata/manifest.json\" ]; then tr -d '\\n' < \"$d/metadata/manifest.json\"; fi\n"
       "    printf '\\n'\n"
       "  done\n"
       "fi",
      ShellQuote(remoteReleasesDir)];
  NSDictionary *result = RunSSHCommandForTarget(target, remoteScript);
  if (![[result[@"status"] description] isEqualToString:@"ok"]) {
    return @{
      @"status" : @"error",
      @"releases" : @[],
      @"remote_execution" : result ?: @{},
    };
  }

  NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
  NSArray<NSString *> *lines = [result[@"captured_output"] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  for (NSString *line in lines) {
    if (![line hasPrefix:@"ARLEN_RELEASE\t"]) {
      continue;
    }
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@"\t"];
    if ([parts count] < 4) {
      continue;
    }
    NSString *releaseID = parts[1];
    NSString *state = parts[2];
    NSString *path = parts[3];
    NSString *manifestText = ([parts count] > 4) ? parts[4] : @"";
    NSDictionary *manifest = [manifestText length] > 0 ? (JSONDictionaryFromString(manifestText) ?: @{}) : @{};
    [items addObject:@{
      @"id" : releaseID ?: @"",
      @"state" : state ?: @"available",
      @"source" : @"remote",
      @"path" : path ?: @"",
      @"manifest_path" : [path length] > 0 ? [path stringByAppendingPathComponent:@"metadata/manifest.json"] : @"",
      @"manifest_version" : manifest[@"version"] ?: @"",
      @"deployment" : DeploymentMetadataFromManifest(manifest, NO),
      @"propane_handoff" : PropaneHandoffFromManifest(manifest, path),
    }];
  }
  [items sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES] ]];
  return @{
    @"status" : @"ok",
    @"releases" : items ?: @[],
    @"remote_execution" : result ?: @{},
  };
}

static NSDictionary *UploadReleaseToRemoteTarget(NSDictionary *target, NSString *localReleasesDir, NSString *releaseID) {
  NSString *remoteReleasesDir = StringValueForDeployKey(target, @"releases_dir");
  NSString *remoteReleaseDir = [remoteReleasesDir stringByAppendingPathComponent:releaseID ?: @""];
  NSString *remoteScript = [NSString stringWithFormat:@"mkdir -p %@ && rm -rf %@ && tar -C %@ -xf -",
                                                      ShellQuote(remoteReleasesDir),
                                                      ShellQuote(remoteReleaseDir),
                                                      ShellQuote(remoteReleasesDir)];
  NSArray<NSString *> *tarArguments = @[ @"tar", @"-C", localReleasesDir ?: @"", @"-cf", @"-", releaseID ?: @"" ];
  NSArray<NSString *> *sshArguments = SSHArgumentsForTarget(target, remoteScript);
  NSString *command = [NSString stringWithFormat:@"%@ | %@",
                                                 TaskCommandDescription(@"/usr/bin/env", tarArguments),
                                                 TaskCommandDescription(@"/usr/bin/env", sshArguments)];
  int exitCode = 0;
  NSMutableString *capturedOutput = [NSMutableString string];
  NSString *capturePath = TaskCapturePath(@"arlen-deploy-upload");
  [[NSFileManager defaultManager] createFileAtPath:capturePath contents:nil attributes:nil];
  NSTask *tarTask = [[NSTask alloc] init];
  NSTask *sshTask = [[NSTask alloc] init];
  tarTask.launchPath = @"/usr/bin/env";
  tarTask.arguments = tarArguments;
  sshTask.launchPath = @"/usr/bin/env";
  sshTask.arguments = sshArguments;
  NSPipe *streamPipe = [NSPipe pipe];
  NSFileHandle *streamRead = [streamPipe fileHandleForReading];
  NSFileHandle *streamWrite = [streamPipe fileHandleForWriting];
  NSFileHandle *captureWrite = [NSFileHandle fileHandleForWritingAtPath:capturePath];
  tarTask.standardOutput = streamWrite;
  tarTask.standardError = captureWrite;
  sshTask.standardInput = streamRead;
  sshTask.standardOutput = captureWrite;
  sshTask.standardError = captureWrite;
  @try {
    [sshTask launch];
    [tarTask launch];
    CloseFileHandleQuietly(streamWrite);
    CloseFileHandleQuietly(streamRead);
    while ([tarTask isRunning] || [sshTask isRunning]) {
      if (![sshTask isRunning] && [tarTask isRunning]) {
        [tarTask terminate];
      }
      [NSThread sleepForTimeInterval:0.05];
    }
    int tarExitCode = tarTask.terminationStatus;
    int sshExitCode = sshTask.terminationStatus;
    exitCode = (tarExitCode == 0) ? sshExitCode : tarExitCode;
  } @catch (NSException *exception) {
    if ([tarTask isRunning]) {
      [tarTask terminate];
    }
    if ([sshTask isRunning]) {
      [sshTask terminate];
    }
    exitCode = 127;
    [capturedOutput appendFormat:@"failed launching %@: %@",
                                 command ?: @"deploy upload transport",
                                 [exception reason] ?: [exception name] ?: @"unknown error"];
  }
  CloseFileHandleQuietly(streamWrite);
  CloseFileHandleQuietly(streamRead);
  CloseFileHandleQuietly(captureWrite);
  NSData *capturedData = [NSData dataWithContentsOfFile:capturePath] ?: [NSData data];
  [[NSFileManager defaultManager] removeItemAtPath:capturePath error:nil];
  NSString *capturedText = [[NSString alloc] initWithData:capturedData encoding:NSUTF8StringEncoding] ?: @"";
  [capturedOutput appendString:capturedText];
  return @{
    @"status" : (exitCode == 0) ? @"ok" : @"error",
    @"command" : command ?: @"",
    @"remote_release_dir" : remoteReleaseDir ?: @"",
    @"captured_output" : capturedOutput ?: @"",
    @"exit_code" : @(exitCode),
  };
}

static NSArray<NSDictionary *> *DeployDoctorChecksForTargetHost(NSDictionary *target,
                                                                NSInteger *passCount,
                                                                NSInteger *warnCount,
                                                                NSInteger *failCount) {
  NSMutableArray<NSDictionary *> *checks = [NSMutableArray array];
  __block NSInteger localPass = 0;
  __block NSInteger localWarn = 0;
  __block NSInteger localFail = 0;
  NSFileManager *fm = [NSFileManager defaultManager];

  void (^addCheck)(NSString *, NSString *, NSString *, NSString *) =
      ^(NSString *checkID, NSString *status, NSString *message, NSString *hint) {
        [checks addObject:@{
          @"id" : checkID ?: @"",
          @"status" : status ?: @"warn",
          @"message" : message ?: @"",
          @"hint" : hint ?: @"",
        }];
        if ([status isEqualToString:@"pass"]) {
          localPass += 1;
        } else if ([status isEqualToString:@"fail"]) {
          localFail += 1;
        } else {
          localWarn += 1;
        }
      };

  NSArray<NSDictionary *> *directories = @[
    @{ @"id" : @"target_release_path", @"path" : StringValueForDeployKey(target, @"release_path") ?: @"" },
    @{ @"id" : @"target_releases_dir", @"path" : StringValueForDeployKey(target, @"releases_dir") ?: @"" },
    @{ @"id" : @"target_shared_dir", @"path" : StringValueForDeployKey(target, @"shared_dir") ?: @"" },
    @{ @"id" : @"target_logs_dir", @"path" : StringValueForDeployKey(target, @"logs_dir") ?: @"" },
    @{ @"id" : @"target_tmp_dir", @"path" : StringValueForDeployKey(target, @"tmp_dir") ?: @"" },
  ];
  for (NSDictionary *entry in directories) {
    BOOL isDirectory = NO;
    NSString *path = entry[@"path"];
    NSString *status = ([path length] > 0 && [fm fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) ? @"pass" : @"fail";
    addCheck(entry[@"id"], status,
             [NSString stringWithFormat:@"%@ %@", [status isEqualToString:@"pass"] ? @"directory present:" : @"directory missing:",
                                        path ?: @""],
             @"Run `arlen deploy init <target>` on the target host to create the expected layout.");
  }

  NSString *generatedDir = StringValueForDeployKey(target, @"generated_dir");
  NSString *systemdUnit = [generatedDir stringByAppendingPathComponent:[NSString stringWithFormat:@"systemd/%@",
                                                                 StringValueForDeployKey(target, @"systemd_unit_filename")]];
  NSString *envExample =
      [generatedDir stringByAppendingPathComponent:[NSString stringWithFormat:@"env/%@.env.example",
                                                                 StringValueForDeployKey(target, @"name")]];
  addCheck(@"target_systemd_unit",
           [fm fileExistsAtPath:systemdUnit] ? @"pass" : @"fail",
           [NSString stringWithFormat:@"%@ %@", [fm fileExistsAtPath:systemdUnit] ? @"generated systemd unit:" : @"generated systemd unit missing:",
                                      systemdUnit],
           @"Run `arlen deploy init <target>` to generate the host artifacts.");
  addCheck(@"target_env_example",
           [fm fileExistsAtPath:envExample] ? @"pass" : @"fail",
           [NSString stringWithFormat:@"%@ %@", [fm fileExistsAtPath:envExample] ? @"generated env example:" : @"generated env example missing:",
                                      envExample],
           @"Run `arlen deploy init <target>` to generate the env template.");

  NSString *runtimeFamily = StringValueForDeployKey(target, @"runtime_family");
  if ([runtimeFamily isEqualToString:@"gnustep"]) {
    NSString *gnustepScript = StringValueForDeployKey(target, @"gnustep_script");
    addCheck(@"target_gnustep_script",
             ([gnustepScript length] > 0 && [fm fileExistsAtPath:gnustepScript]) ? @"pass" : @"fail",
             [NSString stringWithFormat:@"%@ %@", ([gnustepScript length] > 0 && [fm fileExistsAtPath:gnustepScript]) ? @"GNUstep script present:" : @"GNUstep script missing:",
                                        gnustepScript ?: @""],
             @"Install the supported clang-built GNUstep stack or point runtime.gnustepScript at the active GNUstep.sh.");
    if ([gnustepScript length] > 0 && [fm fileExistsAtPath:gnustepScript]) {
      int exitCode = 0;
      NSString *captured = RunShellCaptureCommand([NSString stringWithFormat:@"set +u; source %@ >/dev/null 2>&1; set -u; gnustep-config --objc-flags",
                                                                              ShellQuote(gnustepScript)], &exitCode);
      addCheck(@"target_gnustep_config",
               (exitCode == 0) ? @"pass" : @"fail",
               (exitCode == 0) ? @"gnustep-config works after sourcing GNUstep.sh"
                               : @"gnustep-config failed after sourcing GNUstep.sh",
               (exitCode == 0) ? @""
                               : (Trimmed(captured) ?: @"Verify the target GNUstep environment and gnustep-config installation."));
    }
    BOOL requiresWrapper = [target[@"requires_env_wrapper"] boolValue];
    NSString *propaneWrapper = StringValueForDeployKey(target, @"propane_wrapper");
    NSString *jobsWrapper = StringValueForDeployKey(target, @"jobs_worker_wrapper");
    if (requiresWrapper) {
      addCheck(@"target_runtime_wrapper",
               ([fm isExecutableFileAtPath:propaneWrapper] && [fm isExecutableFileAtPath:jobsWrapper]) ? @"pass" : @"fail",
               ([fm isExecutableFileAtPath:propaneWrapper] && [fm isExecutableFileAtPath:jobsWrapper])
                   ? @"GNUstep runtime wrappers generated"
                   : @"GNUstep runtime wrappers missing",
               @"Run `arlen deploy init <target>` and install the generated wrappers on the target host.");
    } else {
      addCheck(@"target_runtime_wrapper", @"warn",
               @"runtime wrapper disabled for this target",
               @"Only disable wrappers when packaged binaries run correctly without sourcing GNUstep.sh.");
    }
    NSString *runtimeStrategy = StringValueForDeployKey(target, @"runtime_strategy");
    addCheck(@"target_runtime_strategy_readiness",
             [runtimeStrategy isEqualToString:@"managed"] ? @"warn" : @"pass",
             [runtimeStrategy isEqualToString:@"managed"]
                 ? @"runtimeStrategy=managed declared, but Arlen does not yet provision the GNUstep runtime automatically"
                 : [NSString stringWithFormat:@"runtimeStrategy=%@ expects the host runtime to be ready before deploy", runtimeStrategy ?: @"system"],
             @"`arlen deploy` validates the host/runtime contract but does not install the GNUstep runtime yet.");
  }

  int systemctlCode = 0;
  NSString *systemctlPath = Trimmed(RunShellCaptureCommand(@"command -v systemctl 2>/dev/null", &systemctlCode));
  addCheck(@"target_systemd",
           (systemctlCode == 0 && [systemctlPath length] > 0) ? @"pass" : @"warn",
           (systemctlCode == 0 && [systemctlPath length] > 0) ? [NSString stringWithFormat:@"systemd available: %@", systemctlPath]
                                                               : @"systemd not detected on this host",
           @"The Debian-first host contract assumes systemd for production service management.");

  if (passCount != NULL) {
    *passCount = localPass;
  }
  if (warnCount != NULL) {
    *warnCount = localWarn;
  }
  if (failCount != NULL) {
    *failCount = localFail;
  }
  return checks;
}

static NSArray<NSDictionary *> *DeployDoctorChecksForRelease(NSString *releaseDir,
                                                             NSString *environment,
                                                             NSString *serviceName,
                                                             NSString *baseURL,
                                                             NSString *remoteBuildCheckCommand,
                                                             NSInteger *passCount,
                                                             NSInteger *warnCount,
                                                             NSInteger *failCount) {
  NSMutableArray<NSDictionary *> *checks = [NSMutableArray array];
  __block NSInteger localPass = 0;
  __block NSInteger localWarn = 0;
  __block NSInteger localFail = 0;
  NSFileManager *fm = [NSFileManager defaultManager];

  void (^addCheck)(NSString *, NSString *, NSString *, NSString *) =
      ^(NSString *checkID, NSString *status, NSString *message, NSString *hint) {
        [checks addObject:@{
          @"id" : checkID ?: @"",
          @"status" : status ?: @"warn",
          @"message" : message ?: @"",
          @"hint" : hint ?: @"",
        }];
        if ([status isEqualToString:@"pass"]) {
          localPass += 1;
        } else if ([status isEqualToString:@"fail"]) {
          localFail += 1;
        } else {
          localWarn += 1;
        }
      };

  BOOL isDirectory = NO;
  if ([releaseDir length] > 0 && [fm fileExistsAtPath:releaseDir isDirectory:&isDirectory] && isDirectory) {
    addCheck(@"release_dir", @"pass", [NSString stringWithFormat:@"active release: %@", releaseDir], @"");
  } else {
    addCheck(@"release_dir", @"fail", @"active release directory is missing",
             @"Build or activate a release before running deploy doctor.");
    if (passCount != NULL) {
      *passCount = localPass;
    }
    if (warnCount != NULL) {
      *warnCount = localWarn;
    }
    if (failCount != NULL) {
      *failCount = localFail;
    }
    return checks;
  }

  NSDictionary *metadata = LoadReleaseMetadataAtDirectory(releaseDir);
  NSString *manifestPath = metadata[@"manifest_path"];
  NSDictionary *manifest = [metadata[@"manifest"] isKindOfClass:[NSDictionary class]] ? metadata[@"manifest"] : @{};
  NSDictionary *releaseEnv = [metadata[@"release_env"] isKindOfClass:[NSDictionary class]] ? metadata[@"release_env"] : @{};
  if ([manifest count] > 0) {
    addCheck(@"manifest", @"pass", [NSString stringWithFormat:@"release manifest present: %@", manifestPath], @"");
  } else {
    addCheck(@"manifest", @"fail", [NSString stringWithFormat:@"release manifest missing or invalid: %@", manifestPath],
             @"Rebuild the release artifact with `arlen deploy push`.");
  }

  NSString *releaseEnvPath = metadata[@"release_env_path"];
  if ([fm fileExistsAtPath:releaseEnvPath]) {
    addCheck(@"release_env", @"pass", [NSString stringWithFormat:@"release env present: %@", releaseEnvPath], @"");
  } else {
    addCheck(@"release_env", @"warn", [NSString stringWithFormat:@"release env missing: %@", releaseEnvPath],
             @"Rebuild the release artifact if metadata files are incomplete.");
  }

  NSDictionary *deployment = DeploymentMetadataFromManifest(manifest, NO);
  NSDictionary *propaneHandoff = PropaneHandoffFromManifest(manifest, releaseDir);
  NSString *supportLevel = [deployment[@"support_level"] isKindOfClass:[NSString class]] ? deployment[@"support_level"] : @"supported";
  NSString *runtimeStrategy = [deployment[@"runtime_strategy"] isKindOfClass:[NSString class]] ? deployment[@"runtime_strategy"] : @"system";
  NSString *localProfile = [deployment[@"local_profile"] isKindOfClass:[NSString class]] ? deployment[@"local_profile"] : @"";
  NSString *targetProfile = [deployment[@"target_profile"] isKindOfClass:[NSString class]] ? deployment[@"target_profile"] : @"";
  NSString *compatibilityReason =
      [deployment[@"compatibility_reason"] isKindOfClass:[NSString class]] ? deployment[@"compatibility_reason"] : @"same_profile";
  NSString *compatibilityStatus = [supportLevel isEqualToString:@"supported"] ? @"pass"
                                 : [supportLevel isEqualToString:@"experimental"] ? @"warn"
                                 : @"fail";
  addCheck(@"deployment_profile",
           @"pass",
           [NSString stringWithFormat:@"deployment local=%@ target=%@", localProfile ?: @"", targetProfile ?: @""],
           @"");
  addCheck(@"runtime_strategy",
           [@[ @"system", @"managed", @"bundled" ] containsObject:runtimeStrategy] ? @"pass" : @"fail",
           [NSString stringWithFormat:@"runtime strategy: %@", runtimeStrategy ?: @"system"],
           @"Use system, managed, or bundled in the deploy target configuration.");
  NSString *propaneManagerBinary =
      [propaneHandoff[@"manager_binary"] isKindOfClass:[NSString class]] ? propaneHandoff[@"manager_binary"] : @"";
  NSString *propaneJobsWorkerBinary =
      [propaneHandoff[@"jobs_worker_binary"] isKindOfClass:[NSString class]] ? propaneHandoff[@"jobs_worker_binary"] : @"";
  addCheck(@"propane_handoff",
           ([propaneManagerBinary length] > 0 && [propaneJobsWorkerBinary length] > 0) ? @"pass" : @"warn",
           [NSString stringWithFormat:@"propane handoff manager=%@ accessories=%@",
                                      [propaneHandoff[@"manager"] description] ?: @"propane",
                                      [propaneHandoff[@"accessories_config_key"] description] ?: @"propaneAccessories"],
           @"Packaged release metadata should identify the `propane` manager binary, jobs worker binary, and propane accessories key.");
  addCheck(@"compatibility",
           compatibilityStatus,
           [NSString stringWithFormat:@"deployment compatibility %@ (%@)", supportLevel ?: @"supported",
                                      compatibilityReason ?: @"same_profile"],
           [supportLevel isEqualToString:@"unsupported"]
               ? @"Deploy to the same platform profile, or opt into a supported remote rebuild path."
               : [supportLevel isEqualToString:@"experimental"]
                     ? @"Remote rebuild is best-effort; validate the target build chain before activation."
                     : @"");
  if ([deployment[@"remote_rebuild_required"] boolValue]) {
    NSDictionary *remoteBuildCheck = RunRemoteBuildCheck(remoteBuildCheckCommand);
    NSString *remoteStatus = [remoteBuildCheck[@"status"] isEqualToString:@"ok"] ? @"pass"
                           : [remoteBuildCheck[@"status"] isEqualToString:@"missing"] ? @"fail"
                                                                                       : @"fail";
    addCheck(@"remote_build_check",
             remoteStatus,
             [remoteBuildCheck[@"status"] isEqualToString:@"ok"]
                 ? @"remote rebuild validation command completed successfully"
                 : [remoteBuildCheck[@"status"] isEqualToString:@"missing"]
                       ? @"remote rebuild validation command not provided"
                       : @"remote rebuild validation command failed",
             [remoteBuildCheck[@"status"] isEqualToString:@"missing"]
                 ? @"Pass --remote-build-check-command to validate the target build chain."
                 : (remoteBuildCheck[@"captured_output"] ?: @""));
  }

  NSDictionary *paths = ResolvedManifestPathsForRelease(manifest, releaseDir);
  NSDictionary *currentProcessEnvironment = [[NSProcessInfo processInfo] environment] ?: @{};
  NSString *serviceEnvironmentDetail = nil;
  NSDictionary *serviceEnvironment =
      [serviceName length] > 0 ? ServiceEnvironmentForService(serviceName, &serviceEnvironmentDetail) : @{};
  NSArray<NSDictionary *> *requiredPaths = @[
    @{ @"id" : @"app_root", @"path" : paths[@"app_root"] ?: [releaseDir stringByAppendingPathComponent:@"app"] },
    @{ @"id" : @"framework_root", @"path" : paths[@"framework_root"] ?: [releaseDir stringByAppendingPathComponent:@"framework"] },
    @{ @"id" : @"runtime_binary", @"path" : paths[@"runtime_binary"] ?: @"" },
    @{ @"id" : @"boomhauer", @"path" : paths[@"boomhauer"] ?: @"" },
    @{ @"id" : @"propane", @"path" : paths[@"propane"] ?: @"" },
    @{ @"id" : @"jobs_worker", @"path" : paths[@"jobs_worker"] ?: @"" },
    @{ @"id" : @"arlen", @"path" : paths[@"arlen"] ?: @"" },
    @{ @"id" : @"operability_probe_helper", @"path" : paths[@"operability_probe_helper"] ?: @"" },
  ];
  for (NSDictionary *entry in requiredPaths) {
    NSString *checkID = entry[@"id"];
    NSString *path = entry[@"path"];
    NSString *resolvedPath = nil;
    if ([checkID isEqualToString:@"runtime_binary"] || [checkID isEqualToString:@"boomhauer"] ||
        [checkID isEqualToString:@"arlen"]) {
      resolvedPath = ResolveExecutablePath(path);
    } else if ([path length] > 0 && [fm fileExistsAtPath:path]) {
      resolvedPath = [path stringByStandardizingPath];
    }

    if ([resolvedPath length] > 0) {
      addCheck(checkID, @"pass", [NSString stringWithFormat:@"%@ present: %@", checkID, resolvedPath], @"");
    } else {
      addCheck(checkID, @"fail", [NSString stringWithFormat:@"%@ missing: %@", checkID, path ?: @""],
               @"Rebuild the release artifact so runtime files are packaged again.");
    }
  }

  NSString *appRoot = [paths[@"app_root"] isKindOfClass:[NSString class]] ? paths[@"app_root"] : nil;
  if ([appRoot length] > 0) {
    NSError *configError = nil;
    NSDictionary *config = [ALNConfig loadConfigAtRoot:appRoot environment:environment ?: @"production" error:&configError];
    if (config != nil) {
      addCheck(@"config", @"pass",
               [NSString stringWithFormat:@"app config loads for %@ environment", environment ?: @"production"], @"");
      NSDictionary *databaseContract = DatabaseContractFromManifest(manifest, config);
      NSArray<NSDictionary *> *stateWarnings =
          Phase39MultiWorkerStateWarnings(config,
                                          environment ?: @"production",
                                          [databaseContract[@"mode"] isKindOfClass:[NSString class]]
                                              ? databaseContract[@"mode"]
                                              : @"",
                                          [databaseContract[@"target"] isKindOfClass:[NSString class]]
                                              ? databaseContract[@"target"]
                                              : @"default");
      if ([stateWarnings count] == 0) {
        NSDictionary *stateContract = Phase39StateContractFromConfig(config);
        addCheck(@"multi_worker_state", @"pass",
                 [NSString stringWithFormat:@"state contract durable=%@ mode=%@ target=%@",
                                            [stateContract[@"durable"] boolValue] ? @"YES" : @"NO",
                                            stateContract[@"mode"] ?: @"",
                                            stateContract[@"target"] ?: @"default"],
                 @"Production multi-worker state warnings are quiet when state is explicitly durable, a database contract is declared, a database URL is configured, or workerCount <= 1.");
      } else {
        NSDictionary *warning = stateWarnings[0];
        addCheck(@"multi_worker_state",
                 @"warn",
                 [warning[@"message"] description] ?: @"production multi-worker state contract is missing",
                 [warning[@"hint"] description] ?: @"Declare durable state before production multi-worker deployment.");
      }
      NSArray<NSString *> *requiredEnvironmentKeys =
          [databaseContract[@"required_environment_keys"] isKindOfClass:[NSArray class]]
              ? databaseContract[@"required_environment_keys"]
              : @[];
      if ([requiredEnvironmentKeys count] > 0) {
        NSMutableArray<NSString *> *missingKeys = [NSMutableArray array];
        for (NSString *key in requiredEnvironmentKeys) {
          BOOL presentInProcess = EnvironmentDictionaryContainsNonEmptyValueForKey(currentProcessEnvironment, key);
          BOOL presentInService = EnvironmentDictionaryContainsNonEmptyValueForKey(serviceEnvironment, key);
          if (!presentInProcess && !presentInService) {
            [missingKeys addObject:key];
          }
        }
        if ([missingKeys count] == 0) {
          addCheck(@"required_env_keys", @"pass",
                   [NSString stringWithFormat:@"required environment keys present: %@",
                                              [requiredEnvironmentKeys componentsJoinedByString:@", "]],
                   @"Values remain redacted by design.");
        } else {
          addCheck(@"required_env_keys", @"fail",
                   [NSString stringWithFormat:@"required environment keys missing: %@",
                                              [missingKeys componentsJoinedByString:@", "]],
                   @"Provide the missing keys through host/service environment injection without baking secret values into the release.");
        }
      } else {
        addCheck(@"required_env_keys", @"warn", @"no required environment keys declared in deploy metadata",
                 @"Use --require-env-key to record secret/config expectations without storing values.");
      }

      NSString *databaseTarget =
          [databaseContract[@"target"] isKindOfClass:[NSString class]] ? databaseContract[@"target"] : @"default";
      NSString *connectionString = DatabaseConnectionStringFromEnvironmentForTarget(databaseTarget);
      if ([connectionString length] == 0) {
        connectionString = DatabaseConnectionStringFromConfigForTarget(config, databaseTarget);
      }
      if ([connectionString length] > 0) {
        addCheck(@"database_url", @"pass", @"database connection string resolved", @"");
      } else {
        addCheck(@"database_url", @"warn", @"database connection string is empty",
                 @"Set ARLEN_DATABASE_URL or configure database.connectionString before release.");
      }
      NSString *databaseMode =
          [databaseContract[@"mode"] isKindOfClass:[NSString class]] ? databaseContract[@"mode"] : @"";
      NSString *databaseAdapter =
          [databaseContract[@"adapter"] isKindOfClass:[NSString class]] ? databaseContract[@"adapter"] : @"";
      if ([databaseMode length] == 0) {
        addCheck(@"database_contract", @"warn", @"no explicit database deployment contract declared",
                 @"Declare --database-mode so deploy doctor does not have to guess production database topology.");
      } else {
        addCheck(@"database_contract", @"pass",
                 [NSString stringWithFormat:@"database contract mode=%@ adapter=%@ target=%@",
                                            databaseMode ?: @"", databaseAdapter ?: @"",
                                            databaseTarget ?: @"default"],
                 @"");
        if ([databaseMode isEqualToString:@"host_local"]) {
          NSDictionary *probe = RunHostLocalDatabaseProbe(databaseAdapter, connectionString);
          addCheck(@"database_host_local",
                   [probe[@"status"] description] ?: @"warn",
                   [probe[@"message"] description] ?: @"host-local database probe unavailable",
                   [probe[@"hint"] description] ?: @"");
        } else if ([databaseMode isEqualToString:@"external"]) {
          addCheck(@"database_mode_validation",
                   [connectionString length] > 0 ? @"pass" : @"fail",
                   [connectionString length] > 0 ? @"external database contract declared; config is present"
                                                : @"external database contract declared but no connection string resolved",
                   [connectionString length] > 0
                       ? @"Doctor does not require a local database install for database.mode=external."
                       : @"Provide the external database DSN through config or host-managed environment.");
        } else if ([databaseMode isEqualToString:@"embedded"]) {
          addCheck(@"database_mode_validation",
                   [connectionString length] > 0 ? @"pass" : @"warn",
                   [connectionString length] > 0 ? @"embedded database contract declared"
                                                : @"embedded database contract declared without an explicit connection string",
                   @"Validate file/runtime prerequisites for the embedded database path on the target host.");
        }
      }
    } else {
      addCheck(@"config", @"fail", configError.localizedDescription ?: @"failed to load app config",
               @"Run `arlen config --env production` from the active release app root.");
    }
  }

  if ([serviceName length] > 0) {
    NSString *serviceOutput = nil;
    NSString *serviceState = ServiceRuntimeState(serviceName, &serviceOutput);
    NSString *status = [serviceState isEqualToString:@"active"] ? @"pass"
                       : [serviceState isEqualToString:@"unavailable"] ? @"warn"
                       : @"warn";
      addCheck(@"service", status,
             [NSString stringWithFormat:@"service %@ state: %@", serviceName, serviceState],
             [serviceOutput length] > 0 ? serviceOutput : @"");
    NSString *expectedAppRoot = [releaseEnv[@"ARLEN_APP_ROOT"] isKindOfClass:[NSString class]] ? releaseEnv[@"ARLEN_APP_ROOT"] : @"";
    NSString *expectedFrameworkRoot =
        [releaseEnv[@"ARLEN_FRAMEWORK_ROOT"] isKindOfClass:[NSString class]] ? releaseEnv[@"ARLEN_FRAMEWORK_ROOT"] : @"";
    if ([serviceState isEqualToString:@"active"]) {
      NSString *liveAppRoot =
          [serviceEnvironment[@"ARLEN_APP_ROOT"] isKindOfClass:[NSString class]] ? serviceEnvironment[@"ARLEN_APP_ROOT"] : @"";
      NSString *liveFrameworkRoot =
          [serviceEnvironment[@"ARLEN_FRAMEWORK_ROOT"] isKindOfClass:[NSString class]] ? serviceEnvironment[@"ARLEN_FRAMEWORK_ROOT"] : @"";
      if ([liveAppRoot length] == 0 || [liveFrameworkRoot length] == 0) {
        addCheck(@"runtime_root_conflict", @"warn",
                 @"service is active but effective runtime-root environment could not be fully verified",
                 [serviceEnvironmentDetail length] > 0 ? serviceEnvironmentDetail
                                                       : @"Ensure the service inherits activation-owned runtime roots.");
      } else {
        NSString *resolvedLiveAppRoot = ResolveSymlinkDestination(liveAppRoot) ?: [liveAppRoot stringByStandardizingPath];
        NSString *resolvedLiveFrameworkRoot =
            ResolveSymlinkDestination(liveFrameworkRoot) ?: [liveFrameworkRoot stringByStandardizingPath];
        NSString *resolvedExpectedAppRoot =
            ResolveSymlinkDestination(expectedAppRoot) ?: [expectedAppRoot stringByStandardizingPath];
        NSString *resolvedExpectedFrameworkRoot =
            ResolveSymlinkDestination(expectedFrameworkRoot) ?: [expectedFrameworkRoot stringByStandardizingPath];
        BOOL literalRootsMatch = [liveAppRoot isEqualToString:expectedAppRoot] &&
                                 [liveFrameworkRoot isEqualToString:expectedFrameworkRoot];
        BOOL resolvedRootsMatch = [resolvedLiveAppRoot isEqualToString:resolvedExpectedAppRoot] &&
                                  [resolvedLiveFrameworkRoot isEqualToString:resolvedExpectedFrameworkRoot];
        if (!resolvedRootsMatch) {
          addCheck(@"runtime_root_conflict", @"fail",
                   [NSString stringWithFormat:@"service runtime roots differ from the activated release (app=%@ framework=%@)",
                                              liveAppRoot ?: @"", liveFrameworkRoot ?: @""],
                   @"The service may still be serving an older release. Restart the configured runtime non-interactively or roll back current.");
        } else if (!literalRootsMatch) {
          addCheck(@"runtime_root_conflict", @"pass",
                   @"service runtime roots resolve to the activated release through releases/current",
                   @"Literal paths differ, but their resolved targets match the active release.");
        } else {
          addCheck(@"runtime_root_conflict", @"pass",
                   @"service runtime roots match the activated release",
                   @"");
        }
      }
    } else {
      addCheck(@"runtime_root_conflict", @"warn",
               @"runtime-root conflict check skipped because the service is not active",
               @"Start the service and rerun deploy doctor to verify effective ARLEN_APP_ROOT / ARLEN_FRAMEWORK_ROOT values.");
    }
  }

  if ([baseURL length] > 0) {
    NSString *probeFrameworkRoot =
        [[([paths[@"framework_root"] isKindOfClass:[NSString class]] ? paths[@"framework_root"]
                                                                    : [releaseDir stringByAppendingPathComponent:@"framework"])
            stringByStandardizingPath] copy];
    NSString *probeHelper =
        [paths[@"operability_probe_helper"] isKindOfClass:[NSString class]] ? paths[@"operability_probe_helper"] : nil;
    NSDictionary *probe = RunDeployHealthProbe(probeFrameworkRoot, probeHelper, baseURL);
    NSString *probeStatus = [probe[@"status"] isEqualToString:@"ok"] ? @"pass" : @"fail";
    addCheck(@"operability", probeStatus,
             [NSString stringWithFormat:@"operability probe %@ for %@", probe[@"status"] ?: @"", baseURL],
             probe[@"captured_output"] ?: @"");
  } else {
    addCheck(@"operability", @"warn", @"base URL not provided; live operability probe skipped",
             @"Pass --base-url http://127.0.0.1:3000 to validate health/readiness/metrics contracts.");
  }

  if (passCount != NULL) {
    *passCount = localPass;
  }
  if (warnCount != NULL) {
    *warnCount = localWarn;
  }
  if (failCount != NULL) {
    *failCount = localFail;
  }
  return checks;
}

static BOOL IsFrameworkRoot(NSString *path) {
  BOOL isDirectory = NO;
  if (!PathExists(path, &isDirectory) || !isDirectory) {
    return NO;
  }

  NSString *makefile = [path stringByAppendingPathComponent:@"GNUmakefile"];
  NSString *tool = [path stringByAppendingPathComponent:@"tools/boomhauer.m"];
  NSString *runtime = [path stringByAppendingPathComponent:@"src/Arlen/ArlenServer.h"];
  if (PathExists(makefile, NULL) && PathExists(tool, NULL) && PathExists(runtime, NULL)) {
    return YES;
  }

  // ARLEN-BUG-016: packaged `arlen` must recognize `releases/<id>/framework`
  // as a valid framework root, not just a source checkout.
  NSString *packagedArlen = ResolveExecutablePath([path stringByAppendingPathComponent:@"build/arlen"]);
  NSString *packagedPropane = [path stringByAppendingPathComponent:@"bin/propane"];
  NSString *packagedActivate = [path stringByAppendingPathComponent:@"tools/deploy/activate_release.sh"];
  NSString *packagedRollback = [path stringByAppendingPathComponent:@"tools/deploy/rollback_release.sh"];
  NSString *packagedWriteEnv = [path stringByAppendingPathComponent:@"tools/deploy/write_release_env.py"];
  return ([packagedArlen length] > 0) && PathExists(packagedPropane, NULL) && PathExists(packagedActivate, NULL) &&
         PathExists(packagedRollback, NULL) && PathExists(packagedWriteEnv, NULL);
}

static NSString *FindFrameworkRoot(NSString *startPath) {
  if ([startPath length] == 0) {
    return nil;
  }

  NSString *candidate = [startPath stringByStandardizingPath];
  while ([candidate length] > 1) {
    if (IsFrameworkRoot(candidate)) {
      return candidate;
    }
    NSString *parent = [candidate stringByDeletingLastPathComponent];
    if ([parent isEqualToString:candidate]) {
      break;
    }
    candidate = parent;
  }

  return IsFrameworkRoot(candidate) ? candidate : nil;
}

static NSString *FrameworkRootFromExecutablePath(void) {
  NSArray *arguments = [[NSProcessInfo processInfo] arguments];
  if ([arguments count] == 0) {
    return nil;
  }

  NSString *invocation = arguments[0];
  NSString *resolved = invocation;
  if (![resolved hasPrefix:@"/"]) {
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    resolved = [cwd stringByAppendingPathComponent:resolved];
  }
  resolved = [resolved stringByStandardizingPath];

  NSString *buildDir = [resolved stringByDeletingLastPathComponent];
  NSString *candidate = [buildDir stringByDeletingLastPathComponent];
  if (IsFrameworkRoot(candidate)) {
    return candidate;
  }
  return nil;
}

static NSString *BoomhauerBuildCommand(NSString *frameworkRoot) {
  return [NSString stringWithFormat:@"cd %@ && make boomhauer", ShellQuote(frameworkRoot)];
}

static NSString *BoomhauerLaunchCommand(NSArray *serverArgs, NSString *frameworkRoot, NSString *appRoot) {
  NSMutableArray *parts = [NSMutableArray array];
  for (NSString *arg in serverArgs ?: @[]) {
    [parts addObject:ShellQuote(arg)];
  }
  NSString *suffix = ([parts count] > 0) ? [NSString stringWithFormat:@" %@", [parts componentsJoinedByString:@" "]] : @"";
  return [NSString stringWithFormat:@"cd %@ && ARLEN_APP_ROOT=%@ ./build/boomhauer%@",
                                    ShellQuote(frameworkRoot), ShellQuote(appRoot), suffix];
}

static BOOL WriteTextFile(NSString *path, NSString *content, BOOL force, NSError **error) {
  NSFileManager *fm = [NSFileManager defaultManager];
  if (content == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Arlen.Error"
                                   code:17
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                   [NSString stringWithFormat:@"No content generated for %@", path ?: @""]
                               }];
    }
    return NO;
  }
  if ([fm fileExistsAtPath:path] && !force) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Arlen.Error"
                                   code:2
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                   [NSString stringWithFormat:@"File exists: %@", path]
                               }];
    }
    return NO;
  }

  NSString *dir = [path stringByDeletingLastPathComponent];
  if ([dir length] > 0) {
    BOOL ok = [fm createDirectoryAtPath:dir
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:error];
    if (!ok) {
      return NO;
    }
  }
  return [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

static NSPropertyListFormat WritablePlistFormat(void) {
#if defined(__APPLE__)
  return NSPropertyListXMLFormat_v1_0;
#else
  return NSPropertyListOpenStepFormat;
#endif
}

static BOOL AddPluginClassToAppConfig(NSString *root, NSString *pluginClassName, NSError **error) {
  if ([pluginClassName length] == 0) {
    return YES;
  }

  NSString *configPath = [root stringByAppendingPathComponent:@"config/app.plist"];
  NSData *data = ALNDataReadFromFile(configPath, 0, error);
  if (data == nil) {
    return NO;
  }

  NSPropertyListFormat format = NSPropertyListOpenStepFormat;
  id parsed = [NSPropertyListSerialization propertyListWithData:data
                                                        options:NSPropertyListMutableContainersAndLeaves
                                                         format:&format
                                                          error:error];
  if (![parsed isKindOfClass:[NSMutableDictionary class]]) {
    if (error != NULL && *error == nil) {
      *error = [NSError errorWithDomain:@"Arlen.Error"
                                   code:13
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"config/app.plist must be a dictionary"
                               }];
    }
    return NO;
  }

  NSMutableDictionary *config = parsed;
  NSMutableDictionary *plugins = [config[@"plugins"] isKindOfClass:[NSMutableDictionary class]]
                                     ? config[@"plugins"]
                                     : [NSMutableDictionary dictionaryWithDictionary:
                                           ([config[@"plugins"] isKindOfClass:[NSDictionary class]] ? config[@"plugins"] : @{})];
  NSMutableArray *classes = [plugins[@"classes"] isKindOfClass:[NSMutableArray class]]
                                ? plugins[@"classes"]
                                : [NSMutableArray arrayWithArray:
                                      ([plugins[@"classes"] isKindOfClass:[NSArray class]] ? plugins[@"classes"] : @[])];

  if (![classes containsObject:pluginClassName]) {
    [classes addObject:pluginClassName];
  }
  plugins[@"classes"] = classes;
  config[@"plugins"] = plugins;

  NSData *serialized = [NSPropertyListSerialization dataWithPropertyList:config
                                                                   format:WritablePlistFormat()
                                                                  options:0
                                                                    error:error];
  if (serialized == nil) {
    return NO;
  }
  return [serialized writeToFile:configPath options:NSDataWritingAtomic error:error];
}

static BOOL AddSearchProviderClassToAppConfig(NSString *root,
                                              NSString *providerClassName,
                                              NSError **error) {
  if ([providerClassName length] == 0) {
    return YES;
  }

  NSString *configPath = [root stringByAppendingPathComponent:@"config/app.plist"];
  NSData *data = ALNDataReadFromFile(configPath, 0, error);
  if (data == nil) {
    return NO;
  }

  NSPropertyListFormat format = NSPropertyListOpenStepFormat;
  id parsed = [NSPropertyListSerialization propertyListWithData:data
                                                        options:NSPropertyListMutableContainersAndLeaves
                                                         format:&format
                                                          error:error];
  if (![parsed isKindOfClass:[NSMutableDictionary class]]) {
    if (error != NULL && *error == nil) {
      *error = [NSError errorWithDomain:@"Arlen.Error"
                                   code:13
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"config/app.plist must be a dictionary"
                               }];
    }
    return NO;
  }

  NSMutableDictionary *config = parsed;
  NSMutableDictionary *searchModule = [config[@"searchModule"] isKindOfClass:[NSMutableDictionary class]]
                                          ? config[@"searchModule"]
                                          : [NSMutableDictionary dictionaryWithDictionary:
                                                ([config[@"searchModule"] isKindOfClass:[NSDictionary class]]
                                                     ? config[@"searchModule"]
                                                     : @{})];
  NSMutableDictionary *providers = [searchModule[@"providers"] isKindOfClass:[NSMutableDictionary class]]
                                       ? searchModule[@"providers"]
                                       : [NSMutableDictionary dictionaryWithDictionary:
                                             ([searchModule[@"providers"] isKindOfClass:[NSDictionary class]]
                                                  ? searchModule[@"providers"]
                                                  : @{})];
  NSMutableArray *classes = [providers[@"classes"] isKindOfClass:[NSMutableArray class]]
                                ? providers[@"classes"]
                                : [NSMutableArray arrayWithArray:
                                      ([providers[@"classes"] isKindOfClass:[NSArray class]]
                                           ? providers[@"classes"]
                                           : @[])];
  if (![classes containsObject:providerClassName]) {
    [classes addObject:providerClassName];
  }
  providers[@"classes"] = classes;
  searchModule[@"providers"] = providers;
  config[@"searchModule"] = searchModule;

  NSData *serialized = [NSPropertyListSerialization dataWithPropertyList:config
                                                                   format:WritablePlistFormat()
                                                                  options:0
                                                                    error:error];
  if (serialized == nil) {
    return NO;
  }
  return [serialized writeToFile:configPath options:NSDataWritingAtomic error:error];
}

static BOOL RemoveItemIfExists(NSString *path, NSError **error) {
  if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
    return YES;
  }
  return [[NSFileManager defaultManager] removeItemAtPath:path error:error];
}

static BOOL CopyDirectoryTree(NSString *sourcePath, NSString *destinationPath, NSError **error) {
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:sourcePath]) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Arlen.Error"
                                   code:14
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     [NSString stringWithFormat:@"source path not found: %@", sourcePath ?: @""]
                               }];
    }
    return NO;
  }
  NSString *destinationParent = [destinationPath stringByDeletingLastPathComponent];
  if ([destinationParent length] > 0 &&
      ![fm createDirectoryAtPath:destinationParent
      withIntermediateDirectories:YES
                       attributes:nil
                            error:error]) {
    return NO;
  }
  [fm removeItemAtPath:destinationPath error:nil];
  return [fm copyItemAtPath:sourcePath toPath:destinationPath error:error];
}

static NSMutableArray<NSDictionary *> *MutableModuleLockEntriesAtAppRoot(NSString *appRoot, NSError **error) {
  NSDictionary *document = [ALNModuleSystem modulesLockDocumentAtAppRoot:appRoot error:error];
  if (document == nil) {
    return nil;
  }
  NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
  for (NSDictionary *entry in ([document[@"modules"] isKindOfClass:[NSArray class]] ? document[@"modules"] : @[])) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    [entries addObject:[NSDictionary dictionaryWithDictionary:entry]];
  }
  return entries;
}

static BOOL WriteModuleLockEntriesAtAppRoot(NSString *appRoot,
                                            NSArray<NSDictionary *> *entries,
                                            NSError **error) {
  return [ALNModuleSystem writeModulesLockDocument:@{ @"modules" : entries ?: @[] }
                                           appRoot:appRoot
                                             error:error];
}

static NSInteger ModuleLockEntryIndex(NSArray<NSDictionary *> *entries, NSString *identifier) {
  for (NSUInteger idx = 0; idx < [entries count]; idx++) {
    NSDictionary *entry = entries[idx];
    if ([[entry[@"identifier"] description] isEqualToString:(identifier ?: @"")]) {
      return (NSInteger)idx;
    }
  }
  return -1;
}

static BOOL IsModuleInstalledAtAppRoot(NSString *appRoot, NSString *identifier, NSError **error) {
  NSMutableArray<NSDictionary *> *entries = MutableModuleLockEntriesAtAppRoot(appRoot, error);
  if (entries == nil) {
    return NO;
  }
  return (ModuleLockEntryIndex(entries, identifier) >= 0);
}

static NSDictionary *ModuleLockEntryForDefinition(ALNModuleDefinition *definition, NSString *relativePath) {
  return @{
    @"identifier" : definition.identifier ?: @"",
    @"path" : relativePath ?: [NSString stringWithFormat:@"modules/%@", definition.identifier ?: @""],
    @"version" : definition.version ?: @"",
    @"enabled" : @(YES),
  };
}

static NSString *ResolveModuleSourcePath(NSString *appRoot,
                                         NSString *frameworkRoot,
                                         NSString *name,
                                         NSString *sourceOption) {
  NSString *candidate = Trimmed(sourceOption);
  if ([candidate length] > 0) {
    return ResolvePathFromRoot(appRoot, candidate);
  }

  NSString *nameAsPath = ResolvePathFromRoot(appRoot, name);
  BOOL isDirectory = NO;
  if ([[NSFileManager defaultManager] fileExistsAtPath:nameAsPath isDirectory:&isDirectory] && isDirectory) {
    return nameAsPath;
  }

  NSString *frameworkCandidate =
      [[frameworkRoot stringByAppendingPathComponent:@"modules"] stringByAppendingPathComponent:name ?: @""];
  if ([[NSFileManager defaultManager] fileExistsAtPath:frameworkCandidate isDirectory:&isDirectory] && isDirectory) {
    return [frameworkCandidate stringByStandardizingPath];
  }
  return nil;
}

static NSDictionary *ModuleJSONDictionary(ALNModuleDefinition *definition, NSString *installPath, NSString *status) {
  NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:[definition dictionaryRepresentation]];
  if ([installPath length] > 0) {
    payload[@"installPath"] = installPath;
  }
  if ([status length] > 0) {
    payload[@"status"] = status;
  }
  return payload;
}

static NSDictionary *LoadRawConfigForModuleCommand(NSString *appRoot, NSString *environment, NSError **error) {
  return [ALNConfig loadConfigAtRoot:appRoot environment:environment includeModules:NO error:error];
}

static NSString *ReadUTF8File(NSString *path, NSError **error) {
  NSData *data = ALNDataReadFromFile(path, 0, error);
  if (data == nil) {
    return nil;
  }
  NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (content == nil && error != NULL) {
    *error = [NSError errorWithDomain:@"Arlen.Error"
                                 code:15
                             userInfo:@{
                               NSLocalizedDescriptionKey :
                                   [NSString stringWithFormat:@"failed decoding UTF-8 file: %@", path ?: @""]
                             }];
  }
  return content;
}

static BOOL CopyUTF8TextFile(NSString *sourcePath,
                             NSString *destinationPath,
                             BOOL force,
                             NSString **status,
                             NSError **error) {
  BOOL existed = [[NSFileManager defaultManager] fileExistsAtPath:destinationPath];
  NSString *content = ReadUTF8File(sourcePath, error);
  if (content == nil) {
    return NO;
  }
  if (!WriteTextFile(destinationPath, content, force, error)) {
    return NO;
  }
  if (status != NULL) {
    *status = existed ? @"updated" : @"created";
  }
  return YES;
}

static BOOL ConfigureGeneratedAuthUIAtAppRoot(NSString *appRoot,
                                              NSString *layoutName,
                                              NSString *pagePrefix,
                                              NSError **error) {
  NSString *configPath = [appRoot stringByAppendingPathComponent:@"config/app.plist"];
  NSData *data = ALNDataReadFromFile(configPath, 0, error);
  if (data == nil) {
    return NO;
  }

  NSPropertyListFormat format = NSPropertyListOpenStepFormat;
  id parsed = [NSPropertyListSerialization propertyListWithData:data
                                                        options:NSPropertyListMutableContainersAndLeaves
                                                         format:&format
                                                          error:error];
  if (![parsed isKindOfClass:[NSMutableDictionary class]]) {
    if (error != NULL && *error == nil) {
      *error = [NSError errorWithDomain:@"Arlen.Error"
                                   code:16
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"config/app.plist must be a dictionary"
                               }];
    }
    return NO;
  }

  NSMutableDictionary *config = parsed;
  NSMutableDictionary *authModule = [config[@"authModule"] isKindOfClass:[NSMutableDictionary class]]
                                        ? config[@"authModule"]
                                        : [NSMutableDictionary dictionaryWithDictionary:
                                              ([config[@"authModule"] isKindOfClass:[NSDictionary class]] ? config[@"authModule"] : @{})];
  NSMutableDictionary *ui = [authModule[@"ui"] isKindOfClass:[NSMutableDictionary class]]
                                ? authModule[@"ui"]
                                : [NSMutableDictionary dictionaryWithDictionary:
                                      ([authModule[@"ui"] isKindOfClass:[NSDictionary class]] ? authModule[@"ui"] : @{})];
  ui[@"mode"] = @"generated-app-ui";
  ui[@"layout"] = [Trimmed(layoutName) length] > 0 ? Trimmed(layoutName) : @"layouts/auth_generated";
  ui[@"generatedPagePrefix"] = [Trimmed(pagePrefix) length] > 0 ? Trimmed(pagePrefix) : @"auth";
  authModule[@"ui"] = ui;
  config[@"authModule"] = authModule;

  NSData *serialized = [NSPropertyListSerialization dataWithPropertyList:config
                                                                   format:WritablePlistFormat()
                                                                  options:0
                                                                    error:error];
  if (serialized == nil) {
    return NO;
  }
  return [serialized writeToFile:configPath options:NSDataWritingAtomic error:error];
}

static NSString *DefaultFullAppLayoutTemplate(void) {
  return @"<!doctype html>\n"
          "<html lang=\"en\">\n"
          "  <head>\n"
          "    <meta charset=\"utf-8\">\n"
          "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
          "    <title><%= $title %></title>\n"
          "  </head>\n"
          "  <body>\n"
          "    <header>\n"
          "      <p>Generated by Arlen</p>\n"
          "      <%@ include \"partials/_nav\" %>\n"
          "    </header>\n"
          "    <main>\n"
          "      <%@ yield %>\n"
          "    </main>\n"
          "  </body>\n"
          "</html>\n";
}

static NSString *DefaultFullAppNavPartialTemplate(void) {
  return @"<nav>\n"
          "  <a href=\"/\">Home</a>\n"
          "  <a href=\"/static/health.txt\">Health</a>\n"
          "</nav>\n";
}

static NSString *DefaultFullAppFeaturePartialTemplate(void) {
  return @"<%@ requires item %>\n"
          "<li><%= $item %></li>\n";
}

static NSString *DefaultFullAppIndexTemplate(void) {
  return @"<%@ layout \"layouts/main\" %>\n"
          "<section>\n"
          "  <h1><%= $title %></h1>\n"
          "  <p>Composition-first pages can keep layout and partial structure in EOC.</p>\n"
          "  <ul>\n"
          "    <%@ render \"partials/_feature\" collection:$items as:\"item\" %>\n"
          "  </ul>\n"
          "</section>\n";
}

static BOOL TemplateLogicalPathSupportsDefaultLayout(NSString *templateLogical) {
  NSString *logical = Trimmed(templateLogical);
  if ([logical length] == 0) {
    return NO;
  }
  if ([logical hasPrefix:@"layouts/"] || [logical hasPrefix:@"partials/"]) {
    return NO;
  }
  return YES;
}

static BOOL AppHasDefaultLayoutTemplate(NSString *root) {
  NSString *path = [root stringByAppendingPathComponent:@"templates/layouts/main.html.eoc"];
  return PathExists(path, NULL);
}

static NSString *GeneratedHTMLTemplateScaffold(NSString *root, NSString *templateLogical) {
  if (AppHasDefaultLayoutTemplate(root) &&
      TemplateLogicalPathSupportsDefaultLayout(templateLogical)) {
    return @"<%@ layout \"layouts/main\" %>\n"
            "<section>\n"
            "  <h1><%= $title %></h1>\n"
            "</section>\n";
  }
  return @"<h1><%= $title %></h1>\n";
}

static BOOL ScaffoldFullApp(NSString *root, BOOL force, NSError **error) {
  NSArray *directories = @[
    @"config/environments",
    @"db/migrations",
    @"public",
    @"src/Controllers",
    @"src/Models",
    @"src/Plugins",
    @"templates",
    @"templates/layouts",
    @"templates/partials",
    @"tests",
  ];

  for (NSString *dir in directories) {
    NSString *path = [root stringByAppendingPathComponent:dir];
    BOOL ok = [[NSFileManager defaultManager] createDirectoryAtPath:path
                                         withIntermediateDirectories:YES
                                                          attributes:nil
                                                               error:error];
    if (!ok) {
      return NO;
    }
  }

  BOOL ok = YES;
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"config/app.plist"],
                           @"{\n"
                            "  host = \"127.0.0.1\";\n"
                            "  port = 3000;\n"
                            "  logFormat = \"text\";\n"
                            "  serveStatic = YES;\n"
                            "  staticAllowExtensions = (\"css\", \"js\", \"json\", \"txt\", \"html\", \"htm\", \"svg\", \"png\", \"jpg\", \"jpeg\", \"gif\", \"ico\", \"webp\", \"woff\", \"woff2\", \"map\", \"xml\");\n"
                            "  listenBacklog = 128;\n"
                            "  connectionTimeoutSeconds = 30;\n"
                            "  enableReusePort = NO;\n"
                            "  requestLimits = {\n"
                            "    maxRequestLineBytes = 4096;\n"
                            "    maxHeaderBytes = 32768;\n"
                            "    maxBodyBytes = 1048576;\n"
                            "  };\n"
                            "  database = {\n"
                            "    connectionString = \"\";\n"
                            "    adapter = \"postgresql\";\n"
                            "    poolSize = 8;\n"
                            "  };\n"
                            "  state = {\n"
                            "    durable = NO;\n"
                            "    mode = \"\";\n"
                            "    target = \"default\";\n"
                            "  };\n"
                            "  session = {\n"
                            "    enabled = NO;\n"
                            "    secret = \"\";\n"
                            "    cookieName = \"arlen_session\";\n"
                            "    maxAgeSeconds = 1209600;\n"
                            "    secure = NO;\n"
                            "    sameSite = \"Lax\";\n"
                            "  };\n"
                            "  csrf = {\n"
                            "    enabled = NO;\n"
                            "    headerName = \"x-csrf-token\";\n"
                            "    queryParamName = \"csrf_token\";\n"
                            "  };\n"
                            "  rateLimit = {\n"
                            "    enabled = NO;\n"
                            "    requests = 120;\n"
                            "    windowSeconds = 60;\n"
                            "  };\n"
                            "  securityHeaders = {\n"
                            "    enabled = YES;\n"
                            "    contentSecurityPolicy = \"default-src 'self'\";\n"
                            "  };\n"
                            "  auth = {\n"
                            "    enabled = NO;\n"
                            "    bearerSecret = \"\";\n"
                            "    issuer = \"\";\n"
                            "    audience = \"\";\n"
                            "  };\n"
                            "  openapi = {\n"
                            "    enabled = YES;\n"
                            "    docsUIEnabled = YES;\n"
                            "    docsUIStyle = \"interactive\";\n"
                            "    title = \"Arlen API\";\n"
                            "    version = \"0.1.0\";\n"
                            "    description = \"Generated by Arlen\";\n"
                            "  };\n"
                            "  compatibility = {\n"
                            "    pageStateEnabled = NO;\n"
                            "  };\n"
                            "  apiHelpers = {\n"
                            "    responseEnvelopeEnabled = NO;\n"
                            "  };\n"
                            "  plugins = {\n"
                            "    classes = ();\n"
                            "  };\n"
                            "  propaneAccessories = {\n"
                            "    workerCount = 4;\n"
                            "    gracefulShutdownSeconds = 10;\n"
                            "    respawnDelayMs = 250;\n"
                            "    reloadOverlapSeconds = 1;\n"
                            "  };\n"
                            "}\n",
                           force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"config/environments/development.plist"],
                           @"{\n  logFormat = \"text\";\n}\n", force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"config/environments/test.plist"],
                           @"{\n  logFormat = \"json\";\n}\n", force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"config/environments/production.plist"],
                           @"{\n  logFormat = \"json\";\n}\n", force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"config/deploy.plist.example"],
                           DeployTargetSamplePlist(@"production", nil), force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"templates/layouts/main.html.eoc"],
                           DefaultFullAppLayoutTemplate(), force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"templates/partials/_nav.html.eoc"],
                           DefaultFullAppNavPartialTemplate(), force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"templates/partials/_feature.html.eoc"],
                           DefaultFullAppFeaturePartialTemplate(), force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"templates/index.html.eoc"],
                           DefaultFullAppIndexTemplate(), force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"src/Controllers/HomeController.h"],
                           @"#import \"ALNController.h\"\n\n"
                            "@interface HomeController : ALNController\n"
                            "@end\n",
                           force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"src/Controllers/HomeController.m"],
                           @"#import \"HomeController.h\"\n"
                            "#import \"ALNContext.h\"\n\n"
                            "@implementation HomeController\n\n"
                            "- (id)index:(ALNContext *)ctx {\n"
                            "  (void)ctx;\n"
                            "  [self stashValues:@{\n"
                            "    @\"title\" : @\"Welcome to Arlen\",\n"
                            "    @\"items\" : @[\n"
                            "      @\"template-owned layouts\",\n"
                            "      @\"partials with explicit locals\",\n"
                            "      @\"collection rendering\"\n"
                            "    ],\n"
                            "  }];\n"
                            "  NSError *error = nil;\n"
                            "  if (![self renderTemplate:@\"index\" error:&error]) {\n"
                            "    [self setStatus:500];\n"
                            "    [self renderText:[NSString stringWithFormat:@\"render failed: %@\",\n"
                            "                                                error.localizedDescription ?: @\"unknown\"]];\n"
                            "  }\n"
                            "  return nil;\n"
                            "}\n\n"
                            "@end\n",
                           force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"src/main.m"],
                           @"#import <Foundation/Foundation.h>\n"
                            "#import \"ArlenServer.h\"\n"
                            "#import \"Controllers/HomeController.h\"\n\n"
                            "static void RegisterRoutes(ALNApplication *app) {\n"
                            "  [app registerRouteMethod:@\"GET\"\n"
                            "                      path:@\"/\"\n"
                            "                      name:@\"home\"\n"
                            "           controllerClass:[HomeController class]\n"
                            "                    action:@\"index\"];\n"
                            "}\n\n"
                            "int main(int argc, const char *argv[]) {\n"
                            "  @autoreleasepool {\n"
                            "    return ALNRunAppMain(argc, argv, &RegisterRoutes);\n"
                            "  }\n"
                            "}\n",
                           force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"README.md"],
                           @"# New Arlen App\n\n"
                            "Generated by arlen in full mode.\n\n"
                            "## Run\n\n"
                            "From this app directory:\n\n"
                            "- `arlen boomhauer --port 3000` (if `arlen` is on PATH)\n"
                            "- or `/path/to/Arlen/bin/arlen boomhauer --port 3000`\n\n"
                            "- `src/main.m` starts an app with default settings.\n"
                            "- `src/Controllers/HomeController.m` handles `/`.\n"
                            "- `templates/layouts/main.html.eoc` owns the default app shell.\n"
                            "- `templates/partials/_nav.html.eoc` and `templates/partials/_feature.html.eoc` show composition-first partials.\n"
                            "- `templates/index.html.eoc` renders the home page through `<%@ layout \"layouts/main\" %>`.\n\n"
                            "## Deploy\n\n"
                            "Start from the commented sample target:\n\n"
                            "```sh\n"
                            "cp config/deploy.plist.example config/deploy.plist\n"
                            "$EDITOR config/deploy.plist\n"
                            "arlen deploy list\n"
                            "arlen deploy dryrun production\n"
                            "arlen deploy init production\n"
                            "arlen deploy doctor production\n"
                            "arlen deploy push production\n"
                            "```\n",
                           force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"public/health.txt"],
                           @"ok\n", force, error);
  return ok;
}

static BOOL ScaffoldLiteApp(NSString *root, BOOL force, NSError **error) {
  NSArray *directories = @[
    @"config/environments",
    @"db/migrations",
    @"public",
    @"templates",
  ];
  for (NSString *dir in directories) {
    NSString *path = [root stringByAppendingPathComponent:dir];
    BOOL ok = [[NSFileManager defaultManager] createDirectoryAtPath:path
                                         withIntermediateDirectories:YES
                                                          attributes:nil
                                                               error:error];
    if (!ok) {
      return NO;
    }
  }

  BOOL ok = YES;
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"config/app.plist"],
                           @"{\n  host = \"127.0.0.1\";\n  port = 3000;\n  serveStatic = YES;\n  staticAllowExtensions = (\"css\", \"js\", \"json\", \"txt\", \"html\", \"htm\", \"svg\", \"png\", \"jpg\", \"jpeg\", \"gif\", \"ico\", \"webp\", \"woff\", \"woff2\", \"map\", \"xml\");\n  listenBacklog = 128;\n  connectionTimeoutSeconds = 30;\n  database = {\n    connectionString = \"\";\n    adapter = \"postgresql\";\n    poolSize = 8;\n  };\n  session = {\n    enabled = NO;\n    secret = \"\";\n    cookieName = \"arlen_session\";\n    maxAgeSeconds = 1209600;\n    secure = NO;\n    sameSite = \"Lax\";\n  };\n  csrf = {\n    enabled = NO;\n    headerName = \"x-csrf-token\";\n    queryParamName = \"csrf_token\";\n  };\n  rateLimit = {\n    enabled = NO;\n    requests = 120;\n    windowSeconds = 60;\n  };\n  securityHeaders = {\n    enabled = YES;\n    contentSecurityPolicy = \"default-src 'self'\";\n  };\n  auth = {\n    enabled = NO;\n    bearerSecret = \"\";\n    issuer = \"\";\n    audience = \"\";\n  };\n  openapi = {\n    enabled = YES;\n    docsUIEnabled = YES;\n    docsUIStyle = \"interactive\";\n    title = \"Arlen API\";\n    version = \"0.1.0\";\n    description = \"Generated by Arlen\";\n  };\n  compatibility = {\n    pageStateEnabled = NO;\n  };\n  apiHelpers = {\n    responseEnvelopeEnabled = NO;\n  };\n  plugins = {\n    classes = ();\n  };\n  propaneAccessories = {\n    workerCount = 4;\n    gracefulShutdownSeconds = 10;\n    respawnDelayMs = 250;\n    reloadOverlapSeconds = 1;\n  };\n}\n",
                           force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"config/deploy.plist.example"],
                           DeployTargetSamplePlist(@"production", nil), force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"app_lite.m"],
                           @"#import <Foundation/Foundation.h>\n"
                            "#import \"ArlenServer.h\"\n\n"
                            "@interface LiteController : ALNController\n"
                            "@end\n\n"
                            "@implementation LiteController\n\n"
                            "- (id)index:(ALNContext *)ctx {\n"
                            "  (void)ctx;\n"
                            "  [self renderText:@\"hello from lite mode\\n\"];\n"
                            "  return nil;\n"
                            "}\n\n"
                            "@end\n\n"
                            "static void RegisterRoutes(ALNApplication *app) {\n"
                            "  [app registerRouteMethod:@\"GET\"\n"
                            "                      path:@\"/\"\n"
                            "                      name:@\"home\"\n"
                            "           controllerClass:[LiteController class]\n"
                            "                    action:@\"index\"];\n"
                            "}\n\n"
                            "int main(int argc, const char *argv[]) {\n"
                            "  @autoreleasepool {\n"
                            "    return ALNRunAppMain(argc, argv, &RegisterRoutes);\n"
                            "  }\n"
                            "}\n",
                           force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"templates/index.html.eoc"],
                           @"<h1>Lite App</h1>\n", force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"README.md"],
                           @"# New Arlen Lite App\n\n"
                            "Generated by arlen in lite mode.\n\n"
                            "## Run\n\n"
                            "From this app directory:\n\n"
                            "- `arlen boomhauer --port 3000` (if `arlen` is on PATH)\n"
                            "- or `/path/to/Arlen/bin/arlen boomhauer --port 3000`\n\n"
                            "- `app_lite.m` includes a single-file controller + server setup.\n"
                            "- You can split this into full mode structure later.\n\n"
                            "## Deploy\n\n"
                            "Start from the commented sample target:\n\n"
                            "```sh\n"
                            "cp config/deploy.plist.example config/deploy.plist\n"
                            "$EDITOR config/deploy.plist\n"
                            "arlen deploy list\n"
                            "arlen deploy dryrun production\n"
                            "arlen deploy init production\n"
                            "arlen deploy doctor production\n"
                            "arlen deploy push production\n"
                            "```\n",
                           force, error);
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"public/health.txt"],
                           @"ok\n", force, error);
  return ok;
}

static int CommandNew(NSArray *args) {
  BOOL asJSON = ArgsContainFlag(args, @"--json");
  if ([args count] == 0) {
    if (asJSON) {
      return EmitMachineError(@"new", @"scaffold", @"missing_app_name",
                              @"arlen new: missing AppName",
                              @"Provide an app name after `arlen new`.",
                              @"arlen new DemoApp --full --json", 2);
    }
    fprintf(stderr, "arlen new: missing AppName\n");
    PrintNewUsage();
    return 2;
  }
  if ([args count] == 1 && ([args[0] isEqualToString:@"--help"] || [args[0] isEqualToString:@"-h"])) {
    PrintNewUsage();
    return 0;
  }
  NSString *appName = args[0];
  if ([appName hasPrefix:@"-"]) {
    if (asJSON) {
      return EmitMachineError(@"new", @"scaffold", @"missing_app_name",
                              @"arlen new: missing AppName",
                              @"Provide an app name after `arlen new`.",
                              @"arlen new DemoApp --full --json", 2);
    }
    fprintf(stderr, "arlen new: missing AppName\n");
    PrintNewUsage();
    return 2;
  }
  BOOL lite = NO;
  BOOL force = NO;

  for (NSUInteger idx = 1; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--lite"]) {
      lite = YES;
    } else if ([arg isEqualToString:@"--full"]) {
      lite = NO;
    } else if ([arg isEqualToString:@"--force"]) {
      force = YES;
    } else if ([arg isEqualToString:@"--json"]) {
      asJSON = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      PrintNewUsage();
      return 0;
    } else {
      if (asJSON) {
        return EmitMachineError(
            @"new", @"scaffold", @"unknown_option",
            [NSString stringWithFormat:@"arlen new: unknown option %@", arg ?: @""],
            @"Use only --full/--lite/--force/--json with `arlen new`.",
            @"arlen new DemoApp --full --json", 2);
      }
      fprintf(stderr, "arlen new: unknown option %s\n", [arg UTF8String]);
      PrintNewUsage();
      return 2;
    }
  }

  NSString *root =
      [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:appName];
  NSError *error = nil;
  BOOL ok = lite ? ScaffoldLiteApp(root, force, &error) : ScaffoldFullApp(root, force, &error);
  if (!ok) {
    if (asJSON) {
      NSString *message = [NSString stringWithFormat:@"arlen new: %@",
                                                     error.localizedDescription ?: @"scaffold failed"];
      NSString *fixitAction = @"Choose a new app directory or use --force to overwrite allowed files.";
      NSString *fixitExample = [NSString stringWithFormat:@"arlen new %@ --%@ --force --json", appName,
                                                          lite ? @"lite" : @"full"];
      return EmitMachineError(@"new", @"scaffold", @"scaffold_failed",
                              message, fixitAction, fixitExample, 1);
    }
    fprintf(stderr, "arlen new: %s\n", [[error localizedDescription] UTF8String]);
    return 1;
  }

  if (asJSON) {
    NSArray<NSString *> *createdFiles = SortedFileListAtRoot(root);
    NSDictionary *payload = @{
      @"version" : AgentContractVersion(),
      @"command" : @"new",
      @"workflow" : @"scaffold",
      @"status" : @"ok",
      @"mode" : lite ? @"lite" : @"full",
      @"app_name" : appName ?: @"",
      @"app_root" : [root stringByStandardizingPath],
      @"created_files" : createdFiles ?: @[],
    };
    PrintJSONPayload(stdout, payload);
    return 0;
  }

  fprintf(stdout, "Created %s app at %s\n", lite ? "lite" : "full", [root UTF8String]);
  return 0;
}

static NSString *CapitalizeFirst(NSString *name) {
  if ([name length] == 0) {
    return @"";
  }
  NSString *first = [[name substringToIndex:1] uppercaseString];
  NSString *rest = [name substringFromIndex:1];
  return [first stringByAppendingString:rest];
}

static NSString *LowercaseFirst(NSString *name) {
  if ([name length] == 0) {
    return @"";
  }
  NSString *first = [[name substringToIndex:1] lowercaseString];
  NSString *rest = [name substringFromIndex:1];
  return [first stringByAppendingString:rest];
}

static NSString *TrimControllerSuffix(NSString *name) {
  if ([name hasSuffix:@"Controller"] && [name length] > [@"Controller" length]) {
    return [name substringToIndex:[name length] - [@"Controller" length]];
  }
  return name;
}

static NSString *SanitizeRouteName(NSString *value) {
  NSMutableString *out = [NSMutableString string];
  for (NSUInteger idx = 0; idx < [value length]; idx++) {
    unichar ch = [value characterAtIndex:idx];
    BOOL alphaNum = ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
                     (ch >= '0' && ch <= '9'));
    unichar emitted = alphaNum ? ch : (unichar)'_';
    [out appendFormat:@"%C", emitted];
  }
  NSString *lower = [[out lowercaseString] copy];
  while ([lower containsString:@"__"]) {
    lower = [lower stringByReplacingOccurrencesOfString:@"__" withString:@"_"];
  }
  return lower;
}

static NSString *NormalizedTemplateLogicalName(NSString *templateOption,
                                               NSString *controllerBase,
                                               NSString *actionName) {
  NSString *logical = [templateOption copy];
  if ([logical length] == 0) {
    logical = [NSString stringWithFormat:@"%@/%@",
                                         [LowercaseFirst(controllerBase) lowercaseString],
                                         actionName ?: @"index"];
  }
  while ([logical hasPrefix:@"/"]) {
    logical = [logical substringFromIndex:1];
  }
  if ([logical hasSuffix:@".html.eoc"]) {
    logical = [logical substringToIndex:[logical length] - [@".html.eoc" length]];
  }
  return logical;
}

static BOOL InsertRouteIntoRegisterRoutes(NSString *filePath, NSString *routeLine, NSError **error) {
  NSString *content = [NSString stringWithContentsOfFile:filePath
                                                encoding:NSUTF8StringEncoding
                                                   error:error];
  if (content == nil) {
    return NO;
  }
  if ([content containsString:routeLine]) {
    return YES;
  }

  NSRange signature =
      [content rangeOfString:@"static void RegisterRoutes(ALNApplication *app)"];
  if (signature.location != NSNotFound) {
    NSRange openBraceSearch =
        NSMakeRange(signature.location, [content length] - signature.location);
    NSRange openBrace = [content rangeOfString:@"{" options:0 range:openBraceSearch];
    if (openBrace.location != NSNotFound) {
      NSInteger depth = 0;
      for (NSUInteger idx = openBrace.location; idx < [content length]; idx++) {
        unichar ch = [content characterAtIndex:idx];
        if (ch == '{') {
          depth += 1;
        } else if (ch == '}') {
          depth -= 1;
          if (depth == 0) {
            NSString *updated =
                [content stringByReplacingCharactersInRange:NSMakeRange(idx, 0)
                                                 withString:[NSString stringWithFormat:@"\n%@\n", routeLine]];
            return [updated writeToFile:filePath
                             atomically:YES
                               encoding:NSUTF8StringEncoding
                                  error:error];
          }
        }
      }
    }
  }

  NSRange legacyInsertPoint = [content rangeOfString:@"ALNHTTPServer *server"];
  if (legacyInsertPoint.location == NSNotFound) {
    legacyInsertPoint = [content rangeOfString:@"return ALNRunAppMain"];
  }
  if (legacyInsertPoint.location == NSNotFound) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Arlen.Error"
                                   code:9
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     [NSString stringWithFormat:@"Unable to locate route insertion point in %@",
                                                                filePath]
                               }];
    }
    return NO;
  }

  NSString *updated = [content stringByReplacingCharactersInRange:NSMakeRange(legacyInsertPoint.location, 0)
                                                        withString:[NSString stringWithFormat:@"%@\n", routeLine]];
  return [updated writeToFile:filePath
                   atomically:YES
                     encoding:NSUTF8StringEncoding
                        error:error];
}

static BOOL InsertControllerImportIfMissing(NSString *filePath,
                                            NSString *controllerBase,
                                            NSError **error) {
  NSString *content = [NSString stringWithContentsOfFile:filePath
                                                encoding:NSUTF8StringEncoding
                                                   error:error];
  if (content == nil) {
    return NO;
  }

  NSString *importLine =
      [NSString stringWithFormat:@"#import \"Controllers/%@Controller.h\"", controllerBase ?: @""];
  if ([content containsString:importLine]) {
    return YES;
  }

  NSMutableArray<NSString *> *lines =
      [[content componentsSeparatedByString:@"\n"] mutableCopy];
  NSUInteger insertIndex = 0;
  for (NSUInteger idx = 0; idx < [lines count]; idx++) {
    if ([lines[idx] hasPrefix:@"#import "]) {
      insertIndex = idx + 1;
    }
  }
  [lines insertObject:importLine atIndex:insertIndex];

  NSString *updated = [lines componentsJoinedByString:@"\n"];
  if (![updated hasSuffix:@"\n"]) {
    updated = [updated stringByAppendingString:@"\n"];
  }
  return [updated writeToFile:filePath
                   atomically:YES
                     encoding:NSUTF8StringEncoding
                        error:error];
}

static BOOL WireGeneratedRoute(NSString *root,
                               NSString *method,
                               NSString *routePath,
                               NSString *controllerBase,
                               NSString *actionName,
                               NSString **modifiedFilePath,
                               NSError **error) {
  NSString *mainPath = [root stringByAppendingPathComponent:@"src/main.m"];
  NSString *litePath = [root stringByAppendingPathComponent:@"app_lite.m"];
  NSString *target = nil;
  if ([[NSFileManager defaultManager] fileExistsAtPath:mainPath]) {
    target = mainPath;
  } else if ([[NSFileManager defaultManager] fileExistsAtPath:litePath]) {
    target = litePath;
  } else {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Arlen.Error"
                                   code:10
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Could not find src/main.m or app_lite.m for route wiring"
                               }];
    }
    return NO;
  }

  if (!InsertControllerImportIfMissing(target, controllerBase, error)) {
    return NO;
  }

  NSString *routeName =
      SanitizeRouteName([NSString stringWithFormat:@"%@_%@", [controllerBase lowercaseString], [actionName lowercaseString]]);
  NSString *line = [NSString stringWithFormat:
                                 @"  [app registerRouteMethod:@\"%@\" path:@\"%@\" name:@\"%@\" "
                                  "controllerClass:[%@Controller class] action:@\"%@\"];",
                                 [method uppercaseString], routePath, routeName, controllerBase,
                                 actionName];
  BOOL ok = InsertRouteIntoRegisterRoutes(target, line, error);
  if (ok && modifiedFilePath != NULL) {
    *modifiedFilePath = target;
  }
  return ok;
}

static BOOL IsSupportedPluginPreset(NSString *preset) {
  NSString *normalized = [[preset lowercaseString] copy];
  return [normalized isEqualToString:@"generic"] || [normalized isEqualToString:@"redis-cache"] ||
         [normalized isEqualToString:@"queue-jobs"] || [normalized isEqualToString:@"smtp-mail"];
}

static NSString *PluginImplementationForPreset(NSString *pluginName,
                                               NSString *logicalName,
                                               NSString *preset) {
  NSString *normalized = [[preset lowercaseString] copy];
  if ([normalized isEqualToString:@"redis-cache"]) {
    return [NSString stringWithFormat:
                         @"#import \"%@.h\"\n"
                          "#import <stdlib.h>\n\n"
                          "@implementation %@\n\n"
                          "- (NSString *)pluginName {\n"
                          "  return @\"%@\";\n"
                          "}\n\n"
                          "- (BOOL)registerWithApplication:(ALNApplication *)application\n"
                          "                             error:(NSError **)error {\n"
                          "  (void)error;\n"
                          "  const char *rawRedisURL = getenv(\"ARLEN_REDIS_URL\");\n"
                          "  NSString *redisURL = (rawRedisURL != NULL) ? [NSString stringWithUTF8String:rawRedisURL] : @\"\";\n"
                          "  if ([redisURL length] == 0) {\n"
                          "    [application setCacheAdapter:[[ALNInMemoryCacheAdapter alloc] initWithAdapterName:@\"redis_cache_fallback\"]];\n"
                          "    return YES;\n"
                          "  }\n\n"
                          "  NSError *redisError = nil;\n"
                          "  ALNRedisCacheAdapter *redis = [[ALNRedisCacheAdapter alloc] initWithURLString:redisURL\n"
                          "                                                                     namespace:@\"arlen:cache\"\n"
                          "                                                                   adapterName:@\"redis_cache\"\n"
                          "                                                                         error:&redisError];\n"
                          "  if (redis == nil) {\n"
                          "    if (error != NULL) {\n"
                          "      *error = redisError;\n"
                          "    }\n"
                          "    return NO;\n"
                          "  }\n"
                          "  [application setCacheAdapter:redis];\n"
                          "  return YES;\n"
                          "}\n\n"
                          "- (void)applicationDidStart:(ALNApplication *)application {\n"
                          "  (void)application;\n"
                          "}\n\n"
                          "- (void)applicationWillStop:(ALNApplication *)application {\n"
                          "  (void)application;\n"
                          "}\n\n"
                          "@end\n",
                         pluginName, pluginName, logicalName];
  }

  if ([normalized isEqualToString:@"queue-jobs"]) {
    return [NSString stringWithFormat:
                         @"#import \"%@.h\"\n"
                          "#import <stdlib.h>\n\n"
                          "@interface %@QueueRuntime : NSObject <ALNJobWorkerRuntime>\n"
                          "@end\n\n"
                          "@implementation %@QueueRuntime\n\n"
                          "- (ALNJobWorkerDisposition)handleJob:(ALNJobEnvelope *)job\n"
                          "                               error:(NSError **)error {\n"
                          "  (void)error;\n"
                          "  // Template hook: dispatch by job.name and payload.\n"
                          "  return ([job.name length] > 0) ? ALNJobWorkerDispositionAcknowledge\n"
                          "                                 : ALNJobWorkerDispositionRetry;\n"
                          "}\n\n"
                          "@end\n\n"
                          "@interface %@ ()\n"
                          "@property(nonatomic, strong) ALNJobWorker *worker;\n"
                          "@property(nonatomic, strong) id<ALNJobWorkerRuntime> runtime;\n"
                          "@property(nonatomic, strong) NSTimer *workerTimer;\n"
                          "@end\n\n"
                          "@implementation %@\n\n"
                          "- (NSString *)pluginName {\n"
                          "  return @\"%@\";\n"
                          "}\n\n"
                          "- (BOOL)registerWithApplication:(ALNApplication *)application\n"
                          "                             error:(NSError **)error {\n"
                          "  (void)error;\n"
                          "  const char *rawStorage = getenv(\"ARLEN_JOB_STORAGE_PATH\");\n"
                          "  NSString *storagePath = (rawStorage != NULL) ? [NSString stringWithUTF8String:rawStorage] : @\"\";\n"
                          "  if ([storagePath length] == 0) {\n"
                          "    storagePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@\"arlen-jobs/state.plist\"];\n"
                          "  }\n"
                          "  NSError *jobsError = nil;\n"
                          "  ALNFileJobAdapter *fileJobs = [[ALNFileJobAdapter alloc] initWithStoragePath:storagePath\n"
                          "                                                               adapterName:@\"queue_jobs_file\"\n"
                          "                                                                     error:&jobsError];\n"
                          "  if (fileJobs == nil) {\n"
                          "    [application setJobsAdapter:[[ALNInMemoryJobAdapter alloc] initWithAdapterName:@\"queue_jobs_fallback\"]];\n"
                          "  } else {\n"
                          "    [application setJobsAdapter:fileJobs];\n"
                          "  }\n"
                          "  self.worker = [[ALNJobWorker alloc] initWithJobsAdapter:application.jobsAdapter];\n"
                          "  self.worker.maxJobsPerRun = 100;\n"
                          "  const char *rawDelay = getenv(\"ARLEN_JOB_WORKER_RETRY_DELAY_SECONDS\");\n"
                          "  double retryDelay = (rawDelay != NULL) ? atof(rawDelay) : 5.0;\n"
                          "  self.worker.retryDelaySeconds = (retryDelay >= 0.0) ? retryDelay : 5.0;\n"
                          "  self.runtime = [[%@QueueRuntime alloc] init];\n"
                          "  return YES;\n"
                          "}\n\n"
                          "- (void)applicationDidStart:(ALNApplication *)application {\n"
                          "  (void)application;\n"
                          "  const char *rawInterval = getenv(\"ARLEN_JOB_WORKER_INTERVAL_SECONDS\");\n"
                          "  double interval = (rawInterval != NULL) ? atof(rawInterval) : 1.0;\n"
                          "  if (interval <= 0.0) {\n"
                          "    interval = 1.0;\n"
                          "  }\n"
                          "  self.workerTimer = [NSTimer scheduledTimerWithTimeInterval:interval\n"
                          "                                                    target:self\n"
                          "                                                  selector:@selector(runWorkerTick:)\n"
                          "                                                  userInfo:nil\n"
                          "                                                   repeats:YES];\n"
                          "}\n\n"
                          "- (void)runWorkerTick:(NSTimer *)timer {\n"
                          "  (void)timer;\n"
                          "  if (self.worker == nil || self.runtime == nil) {\n"
                          "    return;\n"
                          "  }\n"
                          "  NSError *workerError = nil;\n"
                          "  (void)[self.worker runDueJobsAt:[NSDate date] runtime:self.runtime error:&workerError];\n"
                          "  (void)workerError;\n"
                          "}\n\n"
                          "- (void)applicationWillStop:(ALNApplication *)application {\n"
                          "  (void)application;\n"
                          "  [self.workerTimer invalidate];\n"
                          "  self.workerTimer = nil;\n"
                          "}\n\n"
                          "@end\n",
                         pluginName, pluginName, pluginName, pluginName, pluginName, logicalName, pluginName];
  }

  if ([normalized isEqualToString:@"smtp-mail"]) {
    return [NSString stringWithFormat:
                         @"#import \"%@.h\"\n"
                          "#import <stdlib.h>\n\n"
                          "@implementation %@\n\n"
                          "- (NSString *)pluginName {\n"
                          "  return @\"%@\";\n"
                          "}\n\n"
                          "- (BOOL)registerWithApplication:(ALNApplication *)application\n"
                          "                             error:(NSError **)error {\n"
                          "  (void)error;\n"
                          "  const char *rawHost = getenv(\"ARLEN_SMTP_HOST\");\n"
                          "  NSString *smtpHost = (rawHost != NULL) ? [NSString stringWithUTF8String:rawHost] : @\"\";\n"
                          "  const char *rawPort = getenv(\"ARLEN_SMTP_PORT\");\n"
                          "  NSInteger smtpPort = (rawPort != NULL) ? atoi(rawPort) : 587;\n"
                          "  (void)smtpPort;\n"
                          "  const char *rawStorage = getenv(\"ARLEN_MAIL_STORAGE_DIR\");\n"
                          "  NSString *storageDir = (rawStorage != NULL) ? [NSString stringWithUTF8String:rawStorage] : @\"\";\n"
                          "  if ([storageDir length] == 0) {\n"
                          "    storageDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@\"arlen-mail\"];\n"
                          "  }\n"
                          "  NSError *mailError = nil;\n"
                          "  ALNFileMailAdapter *fileMail = [[ALNFileMailAdapter alloc] initWithStorageDirectory:storageDir\n"
                          "                                                                   adapterName:@\"file_mail_template\"\n"
                          "                                                                         error:&mailError];\n"
                          "  if (fileMail == nil) {\n"
                          "    [application setMailAdapter:[[ALNInMemoryMailAdapter alloc] initWithAdapterName:@\"smtp_mail_fallback\"]];\n"
                          "    return YES;\n"
                          "  }\n\n"
                          "  // Template hook: if smtpHost is configured, replace file-backed delivery with SMTP adapter wiring.\n"
                          "  (void)smtpHost;\n"
                          "  [application setMailAdapter:fileMail];\n"
                          "  return YES;\n"
                          "}\n\n"
                          "- (void)applicationDidStart:(ALNApplication *)application {\n"
                          "  (void)application;\n"
                          "}\n\n"
                          "- (void)applicationWillStop:(ALNApplication *)application {\n"
                          "  (void)application;\n"
                          "}\n\n"
                          "@end\n",
                         pluginName, pluginName, logicalName];
  }

  return [NSString stringWithFormat:
                       @"#import \"%@.h\"\n\n"
                        "@implementation %@\n\n"
                        "- (NSString *)pluginName {\n"
                        "  return @\"%@\";\n"
                        "}\n\n"
                        "- (BOOL)registerWithApplication:(ALNApplication *)application\n"
                        "                             error:(NSError **)error {\n"
                        "  (void)application;\n"
                        "  (void)error;\n"
                        "  return YES;\n"
                        "}\n\n"
                        "- (void)applicationDidStart:(ALNApplication *)application {\n"
                        "  (void)application;\n"
                        "}\n\n"
                        "- (void)applicationWillStop:(ALNApplication *)application {\n"
                        "  (void)application;\n"
                        "}\n\n"
                        "@end\n",
                       pluginName, pluginName, logicalName];
}

static BOOL IsSupportedFrontendPreset(NSString *preset) {
  NSString *normalized = [[preset lowercaseString] copy];
  return [normalized isEqualToString:@"vanilla-spa"] ||
         [normalized isEqualToString:@"progressive-mpa"];
}

static NSString *NormalizedFrontendSlug(NSString *name) {
  NSString *slug = SanitizeRouteName(name ?: @"");
  while ([slug hasPrefix:@"_"]) {
    slug = [slug substringFromIndex:1];
  }
  while ([slug hasSuffix:@"_"] && [slug length] > 0) {
    slug = [slug substringToIndex:[slug length] - 1];
  }
  if ([slug length] == 0) {
    return @"frontend_app";
  }
  return slug;
}

static NSDictionary<NSString *, NSString *> *FrontendStarterFilesForPreset(NSString *preset,
                                                                            NSString *slug,
                                                                            NSString *displayName) {
  NSString *normalizedPreset = [[preset lowercaseString] copy];
  NSString *safeSlug = [NormalizedFrontendSlug(slug) copy];
  NSString *safeDisplayName = [displayName length] > 0 ? displayName : @"Frontend Starter";
  NSString *basePath = [NSString stringWithFormat:@"public/frontend/%@", safeSlug];
  NSString *manifestTemplate =
      @"{\n"
       "  \"starter\": \"%@\",\n"
       "  \"version\": \"phase7f-starter-v1\",\n"
       "  \"slug\": \"%@\",\n"
       "  \"generated_layout\": \"public/frontend/%@/\",\n"
       "  \"api_examples\": [\n"
       "    \"/healthz?format=json\",\n"
       "    \"/metrics\"\n"
       "  ]\n"
       "}\n";
  NSString *manifest =
      [NSString stringWithFormat:manifestTemplate, normalizedPreset, safeSlug, safeSlug];

  NSString *readmeTemplate =
      @"# %@\n\n"
       "Starter preset: `%@`\n"
       "Version: `phase7f-starter-v1`\n\n"
       "This starter is generated by `arlen generate frontend`.\n\n"
       "## What It Demonstrates\n\n"
       "- static assets under `public/frontend/%@/`\n"
       "- API consumption from built-in Arlen JSON probes (`/healthz?format=json`)\n"
       "- deployment packaging compatibility via `tools/deploy/build_release.sh` (copies `public/`)\n\n"
       "## Upgrade Guidance\n\n"
       "1. Compare this folder against the latest starter templates from the framework release.\n"
       "2. Review `starter_manifest.json` version changes before merging updates.\n"
       "3. Re-run integration smoke checks after updates (`make test-integration`).\n";
  NSString *readme =
      [NSString stringWithFormat:readmeTemplate, safeDisplayName, normalizedPreset, safeSlug];

  if ([normalizedPreset isEqualToString:@"progressive-mpa"]) {
    NSString *index = [NSString stringWithFormat:
                                    @"<!doctype html>\n"
                                     "<html lang=\"en\">\n"
                                     "  <head>\n"
                                     "    <meta charset=\"utf-8\">\n"
                                     "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
                                     "    <title>%@</title>\n"
                                     "    <link rel=\"stylesheet\" href=\"./styles.css\">\n"
                                     "  </head>\n"
                                     "  <body>\n"
                                     "    <main class=\"shell\">\n"
                                     "      <h1>%@</h1>\n"
                                     "      <p class=\"lede\">Progressive MPA starter with static-first HTML and opt-in JS enhancement.</p>\n"
                                     "      <section class=\"panel\">\n"
                                     "        <h2>Health Check</h2>\n"
                                     "        <form id=\"health-form\" action=\"/healthz\" method=\"get\">\n"
                                     "          <input type=\"hidden\" name=\"format\" value=\"json\">\n"
                                     "          <button type=\"submit\">Load Health JSON</button>\n"
                                     "        </form>\n"
                                     "        <p id=\"health-summary\">Submit the form to fetch the API signal.</p>\n"
                                     "        <pre id=\"health-payload\">{}</pre>\n"
                                     "      </section>\n"
                                     "      <section class=\"panel\">\n"
                                     "        <h2>Deployment Notes</h2>\n"
                                     "        <p>Files in this directory are copied into release artifacts automatically via `public/` packaging.</p>\n"
                                     "      </section>\n"
                                     "    </main>\n"
                                     "    <script src=\"./app.js\"></script>\n"
                                     "  </body>\n"
                                     "</html>\n",
                                    safeDisplayName, safeDisplayName];

    NSString *js =
        @"(function () {\n"
         "  const form = document.getElementById(\"health-form\");\n"
         "  const summary = document.getElementById(\"health-summary\");\n"
         "  const payload = document.getElementById(\"health-payload\");\n"
         "  if (!form || !summary || !payload) {\n"
         "    return;\n"
         "  }\n"
         "\n"
         "  async function loadHealth() {\n"
         "    const response = await fetch(\"/healthz?format=json\", {\n"
         "      headers: { Accept: \"application/json\" },\n"
         "    });\n"
         "    const json = await response.json();\n"
         "    const status = (json && json.status) || \"unknown\";\n"
         "    summary.textContent = `status: ${status}`;\n"
         "    payload.textContent = JSON.stringify(json, null, 2);\n"
         "  }\n"
         "\n"
         "  form.addEventListener(\"submit\", function (event) {\n"
         "    event.preventDefault();\n"
         "    loadHealth().catch(function (err) {\n"
         "      summary.textContent = `request failed: ${err && err.message ? err.message : \"unknown\"}`;\n"
         "    });\n"
         "  });\n"
         "})();\n";

    NSString *css =
        @"body {\n"
         "  margin: 0;\n"
         "  font-family: \"Helvetica Neue\", Helvetica, Arial, sans-serif;\n"
         "  background: #f5f7fb;\n"
         "  color: #152033;\n"
         "}\n"
         "\n"
         ".shell {\n"
         "  max-width: 860px;\n"
         "  margin: 0 auto;\n"
         "  padding: 2rem 1.25rem 3rem;\n"
         "}\n"
         "\n"
         ".lede {\n"
         "  color: #45556f;\n"
         "}\n"
         "\n"
         ".panel {\n"
         "  background: #ffffff;\n"
         "  border: 1px solid #d7deeb;\n"
         "  border-radius: 12px;\n"
         "  padding: 1rem;\n"
         "  margin-top: 1rem;\n"
         "}\n"
         "\n"
         "button {\n"
         "  background: #1f5ad1;\n"
         "  color: white;\n"
         "  border: none;\n"
         "  border-radius: 8px;\n"
         "  padding: 0.55rem 0.85rem;\n"
         "}\n"
         "\n"
         "pre {\n"
         "  background: #0f1729;\n"
         "  color: #d8e4ff;\n"
         "  padding: 0.75rem;\n"
         "  border-radius: 8px;\n"
         "  overflow: auto;\n"
         "}\n";

    return @{
      [NSString stringWithFormat:@"%@/index.html", basePath] : index,
      [NSString stringWithFormat:@"%@/app.js", basePath] : js,
      [NSString stringWithFormat:@"%@/styles.css", basePath] : css,
      [NSString stringWithFormat:@"%@/starter_manifest.json", basePath] : manifest,
      [NSString stringWithFormat:@"%@/README.md", basePath] : readme,
    };
  }

  NSString *index = [NSString stringWithFormat:
                                  @"<!doctype html>\n"
                                   "<html lang=\"en\">\n"
                                   "  <head>\n"
                                   "    <meta charset=\"utf-8\">\n"
                                   "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
                                   "    <title>%@</title>\n"
                                   "    <link rel=\"stylesheet\" href=\"./styles.css\">\n"
                                   "  </head>\n"
                                   "  <body>\n"
                                   "    <main class=\"shell\">\n"
                                   "      <h1>%@</h1>\n"
                                   "      <p class=\"lede\">Vanilla SPA starter for Arlen static assets and JSON API consumption.</p>\n"
                                   "      <section class=\"panel\">\n"
                                   "        <h2>Health Signal</h2>\n"
                                   "        <p id=\"health-summary\">Loading...</p>\n"
                                   "        <pre id=\"health-payload\">{}</pre>\n"
                                   "        <button id=\"refresh-health\" type=\"button\">Refresh Health</button>\n"
                                   "      </section>\n"
                                   "      <section class=\"panel\">\n"
                                   "        <h2>Metrics Preview</h2>\n"
                                   "        <pre id=\"metrics-preview\">Loading...</pre>\n"
                                   "      </section>\n"
                                   "    </main>\n"
                                   "    <script src=\"./app.js\"></script>\n"
                                   "  </body>\n"
                                   "</html>\n",
                                  safeDisplayName, safeDisplayName];

  NSString *js =
      @"(function () {\n"
       "  const healthSummary = document.getElementById(\"health-summary\");\n"
       "  const healthPayload = document.getElementById(\"health-payload\");\n"
       "  const metricsPreview = document.getElementById(\"metrics-preview\");\n"
       "  const refreshButton = document.getElementById(\"refresh-health\");\n"
       "\n"
       "  async function loadHealth() {\n"
       "    const response = await fetch(\"/healthz?format=json\", {\n"
       "      headers: { Accept: \"application/json\" },\n"
       "    });\n"
       "    const payload = await response.json();\n"
       "    const status = payload && payload.status ? payload.status : \"unknown\";\n"
       "    healthSummary.textContent = `status: ${status}`;\n"
       "    healthPayload.textContent = JSON.stringify(payload, null, 2);\n"
       "  }\n"
       "\n"
       "  async function loadMetrics() {\n"
       "    const response = await fetch(\"/metrics\");\n"
       "    const text = await response.text();\n"
       "    metricsPreview.textContent = text.split(\"\\n\").slice(0, 8).join(\"\\n\");\n"
       "  }\n"
       "\n"
       "  async function refresh() {\n"
       "    try {\n"
       "      await Promise.all([loadHealth(), loadMetrics()]);\n"
       "    } catch (err) {\n"
       "      const message = err && err.message ? err.message : \"unknown\";\n"
       "      if (healthSummary) {\n"
       "        healthSummary.textContent = `request failed: ${message}`;\n"
       "      }\n"
       "      if (metricsPreview) {\n"
       "        metricsPreview.textContent = `request failed: ${message}`;\n"
       "      }\n"
       "    }\n"
       "  }\n"
       "\n"
       "  if (refreshButton) {\n"
       "    refreshButton.addEventListener(\"click\", refresh);\n"
       "  }\n"
       "  refresh();\n"
       "})();\n";

  NSString *css =
      @"body {\n"
       "  margin: 0;\n"
       "  font-family: \"Avenir Next\", \"Segoe UI\", Helvetica, Arial, sans-serif;\n"
       "  color: #10243d;\n"
       "  background: linear-gradient(180deg, #eff4ff 0%, #f9fbff 100%);\n"
       "}\n"
       "\n"
       ".shell {\n"
       "  max-width: 900px;\n"
       "  margin: 0 auto;\n"
       "  padding: 2.25rem 1.25rem 3rem;\n"
       "}\n"
       "\n"
       ".lede {\n"
       "  color: #435979;\n"
       "}\n"
       "\n"
       ".panel {\n"
       "  background: white;\n"
       "  border: 1px solid #dce4f3;\n"
       "  border-radius: 14px;\n"
       "  box-shadow: 0 8px 28px rgba(19, 35, 63, 0.08);\n"
       "  padding: 1rem;\n"
       "  margin-top: 1rem;\n"
       "}\n"
       "\n"
       "button {\n"
       "  background: #1e4fc4;\n"
       "  color: #fff;\n"
       "  border: none;\n"
       "  border-radius: 8px;\n"
       "  padding: 0.55rem 0.9rem;\n"
       "}\n"
       "\n"
       "pre {\n"
       "  background: #0f1729;\n"
       "  color: #d9e6ff;\n"
       "  padding: 0.75rem;\n"
       "  border-radius: 10px;\n"
       "  overflow-x: auto;\n"
       "  min-height: 4rem;\n"
       "}\n";

  return @{
    [NSString stringWithFormat:@"%@/index.html", basePath] : index,
    [NSString stringWithFormat:@"%@/app.js", basePath] : js,
    [NSString stringWithFormat:@"%@/styles.css", basePath] : css,
    [NSString stringWithFormat:@"%@/starter_manifest.json", basePath] : manifest,
    [NSString stringWithFormat:@"%@/README.md", basePath] : readme,
  };
}

static NSString *TrimSearchProviderSuffix(NSString *name) {
  if ([name hasSuffix:@"SearchProvider"] && [name length] > [@"SearchProvider" length]) {
    return [name substringToIndex:[name length] - [@"SearchProvider" length]];
  }
  return name;
}

static NSString *NormalizedSearchResourceSlug(NSString *name) {
  NSString *slug = SanitizeRouteName(name ?: @"");
  while ([slug hasPrefix:@"_"]) {
    slug = [slug substringFromIndex:1];
  }
  while ([slug hasSuffix:@"_"] && [slug length] > 0) {
    slug = [slug substringToIndex:[slug length] - 1];
  }
  if ([slug length] == 0) {
    return @"search_resource";
  }
  return slug;
}

static NSString *GeneratedSearchProviderHeader(NSString *providerClassName) {
  return [NSString stringWithFormat:
                       @"#import <Foundation/Foundation.h>\n"
                        "#import \"ALNSearchModule.h\"\n\n"
                        "@interface %@ : NSObject <ALNSearchResourceProvider>\n"
                        "@end\n",
                       providerClassName ?: @"GeneratedSearchProvider"];
}

static NSString *GeneratedSearchProviderImplementation(NSString *providerClassName,
                                                       NSString *resourceBaseName,
                                                       NSString *resourceSlug) {
  NSString *resourceClassName = [NSString stringWithFormat:@"%@SearchResource", resourceBaseName ?: @"Generated"];
  NSString *label = [resourceBaseName length] > 0 ? resourceBaseName : @"Generated";
  NSString *summary = [NSString stringWithFormat:@"%@ results for app-owned search.", label];
  NSString *pathTemplate = [NSString stringWithFormat:@"/%@/:identifier", resourceSlug ?: @"search_resource"];
  NSString *sampleIdentifier = [NSString stringWithFormat:@"%@-100", resourceSlug ?: @"search_resource"];
  return [NSString stringWithFormat:
                       @"#import \"%@.h\"\n\n"
                        "@interface %@ : NSObject <ALNSearchResourceDefinition>\n"
                        "@end\n\n"
                        "@implementation %@\n\n"
                        "- (NSString *)searchModuleResourceIdentifier {\n"
                        "  return @\"%@\";\n"
                        "}\n\n"
                        "- (NSDictionary *)searchModuleResourceMetadata {\n"
                        "  return @{\n"
                        "    @\"label\" : @\"%@\",\n"
                        "    @\"summary\" : @\"%@\",\n"
                        "    @\"identifierField\" : @\"id\",\n"
                        "    @\"primaryField\" : @\"title\",\n"
                        "    @\"summaryField\" : @\"summary\",\n"
                        "    @\"indexedFields\" : @[ @\"id\", @\"title\", @\"summary\", @\"status\", @\"updated_at\" ],\n"
                        "    @\"searchFields\" : @[ @\"title\", @\"summary\" ],\n"
                        "    @\"autocompleteFields\" : @[ @\"title\" ],\n"
                        "    @\"suggestionFields\" : @[ @\"title\", @\"summary\" ],\n"
                        "    @\"highlightFields\" : @[ @\"title\", @\"summary\" ],\n"
                        "    @\"resultFields\" : @[ @\"id\", @\"title\", @\"status\", @\"updated_at\" ],\n"
                        "    @\"facetFields\" : @[\n"
                        "      @{ @\"name\" : @\"status\", @\"label\" : @\"Status\", @\"type\" : @\"string\", @\"choices\" : @[ @\"draft\", @\"published\" ] }\n"
                        "    ],\n"
                        "    @\"fieldTypes\" : @{\n"
                        "      @\"id\" : @\"string\",\n"
                        "      @\"title\" : @\"string\",\n"
                        "      @\"summary\" : @\"string\",\n"
                        "      @\"status\" : @\"string\",\n"
                        "      @\"updated_at\" : @\"timestamp\",\n"
                        "    },\n"
                        "    @\"filters\" : @[\n"
                        "      @{ @\"name\" : @\"status\", @\"type\" : @\"string\", @\"operators\" : @[ @\"eq\", @\"in\" ], @\"choices\" : @[ @\"draft\", @\"published\" ] }\n"
                        "    ],\n"
                        "    @\"sorts\" : @[\n"
                        "      @{ @\"name\" : @\"updated_at\", @\"type\" : @\"timestamp\", @\"direction\" : @\"desc\", @\"default\" : @YES },\n"
                        "      @{ @\"name\" : @\"title\", @\"type\" : @\"string\" },\n"
                        "    ],\n"
                        "    @\"queryModes\" : @[ @\"search\", @\"phrase\", @\"fuzzy\", @\"autocomplete\" ],\n"
                        "    @\"queryPolicy\" : @\"public\",\n"
                        "    @\"pagination\" : @{ @\"defaultLimit\" : @10, @\"maxLimit\" : @50, @\"cursorField\" : @\"id\" },\n"
                        "    @\"pathTemplate\" : @\"%@\",\n"
                        "  };\n"
                        "}\n\n"
                        "- (NSArray<NSDictionary *> *)searchModuleDocumentsForRuntime:(ALNSearchModuleRuntime *)runtime\n"
                        "                                                       error:(NSError **)error {\n"
                        "  (void)runtime;\n"
                        "  (void)error;\n"
                        "  return @[\n"
                        "    @{\n"
                        "      @\"id\" : @\"%@\",\n"
                        "      @\"title\" : @\"Replace Me\",\n"
                        "      @\"summary\" : @\"Swap this placeholder data for real app-owned records.\",\n"
                        "      @\"status\" : @\"published\",\n"
                        "      @\"updated_at\" : @\"2026-04-01T00:00:00Z\",\n"
                        "    },\n"
                        "  ];\n"
                        "}\n\n"
                        "- (NSDictionary *)searchModulePublicResultForDocument:(NSDictionary *)document\n"
                        "                                              metadata:(NSDictionary *)metadata\n"
                        "                                               runtime:(ALNSearchModuleRuntime *)runtime\n"
                        "                                                 error:(NSError **)error {\n"
                        "  (void)metadata;\n"
                        "  (void)runtime;\n"
                        "  (void)error;\n"
                        "  NSDictionary *record = [document[@\"record\"] isKindOfClass:[NSDictionary class]] ? document[@\"record\"] : @{};\n"
                        "  return @{\n"
                        "    @\"fields\" : @{\n"
                        "      @\"id\" : record[@\"id\"] ?: @\"\",\n"
                        "      @\"status\" : record[@\"status\"] ?: @\"\",\n"
                        "      @\"updated_at\" : record[@\"updated_at\"] ?: @\"\",\n"
                        "    },\n"
                        "    @\"badge\" : [record[@\"status\"] isEqual:@\"published\"] ? @\"ready\" : @\"draft\",\n"
                        "  };\n"
                        "}\n\n"
                        "@end\n\n"
                        "@implementation %@\n\n"
                        "- (NSArray<id<ALNSearchResourceDefinition>> *)searchModuleResourcesForRuntime:(ALNSearchModuleRuntime *)runtime\n"
                        "                                                                           error:(NSError **)error {\n"
                        "  (void)runtime;\n"
                        "  (void)error;\n"
                        "  return @[ [[%@ alloc] init] ];\n"
                        "}\n\n"
                        "@end\n",
                       providerClassName ?: @"GeneratedSearchProvider",
                       resourceClassName,
                       resourceClassName,
                       resourceSlug ?: @"search_resource",
                       label,
                       summary,
                       pathTemplate,
                       sampleIdentifier,
                       providerClassName ?: @"GeneratedSearchProvider",
                       resourceClassName];
}

static NSString *GeneratedSearchGuide(NSString *providerClassName,
                                      NSString *resourceSlug,
                                      NSString *resourceLabel) {
  return [NSString stringWithFormat:
                       @"# %@ Search Scaffold\n\n"
                        "Generated by `arlen generate search %@`.\n\n"
                        "## What Was Added\n\n"
                        "- `src/Search/%@.h`\n"
                        "- `src/Search/%@.m`\n"
                        "- `config/app.plist` registration under `searchModule.providers.classes`\n"
                        "- this guide\n\n"
                        "## Resource Contract Checklist\n\n"
                        "Update the generated provider/resource with your real fields:\n\n"
                        "- `identifierField`, `primaryField`, and `summaryField`\n"
                        "- `indexedFields`, `searchFields`, and `resultFields`\n"
                        "- typed `filters`, `facetFields`, and `sorts`\n"
                        "- `queryPolicy`, `queryModes`, and `pathTemplate`\n"
                        "- `searchModulePublicResultForDocument:` for public-safe shaping\n\n"
                        "## Engine Config Examples\n\n"
                        "Default engine:\n\n"
                        "```plist\n"
                        "searchModule = {\n"
                        "  providers = {\n"
                        "    classes = ( \"%@\" );\n"
                        "  };\n"
                        "};\n"
                        "```\n\n"
                        "PostgreSQL FTS/trigram:\n\n"
                        "```plist\n"
                        "searchModule = {\n"
                        "  engineClass = \"ALNPostgresSearchEngine\";\n"
                        "  providers = {\n"
                        "    classes = ( \"%@\" );\n"
                        "  };\n"
                        "  engine = {\n"
                        "    postgres = {\n"
                        "      tableName = \"%@_documents\";\n"
                        "      textSearchConfiguration = \"simple\";\n"
                        "      maxConnections = 2;\n"
                        "    };\n"
                        "  };\n"
                        "};\n"
                        "```\n\n"
                        "Meilisearch:\n\n"
                        "```plist\n"
                        "searchModule = {\n"
                        "  engineClass = \"ALNMeilisearchSearchEngine\";\n"
                        "  providers = {\n"
                        "    classes = ( \"%@\" );\n"
                        "  };\n"
                        "  engine = {\n"
                        "    meilisearch = {\n"
                        "      serviceURL = \"http://127.0.0.1:7700\";\n"
                        "      apiKey = \"change-me\";\n"
                        "      indexPrefix = \"myapp\";\n"
                        "      liveRequestsEnabled = NO;\n"
                        "    };\n"
                        "  };\n"
                        "};\n"
                        "```\n\n"
                        "OpenSearch / Elasticsearch:\n\n"
                        "```plist\n"
                        "searchModule = {\n"
                        "  engineClass = \"ALNOpenSearchSearchEngine\";\n"
                        "  providers = {\n"
                        "    classes = ( \"%@\" );\n"
                        "  };\n"
                        "  engine = {\n"
                        "    opensearch = {\n"
                        "      serviceURL = \"http://127.0.0.1:9200\";\n"
                        "      apiKey = \"change-me\";\n"
                        "      indexPrefix = \"myapp\";\n"
                        "      liveRequestsEnabled = NO;\n"
                        "    };\n"
                        "  };\n"
                        "};\n"
                        "```\n\n"
                        "## Migration Path\n\n"
                        "1. Start with the default engine while you finalize result shaping, filters, and faceting.\n"
                        "2. Move to `ALNPostgresSearchEngine` when you want better ranking quality without adding new infrastructure.\n"
                        "3. Move to Meilisearch or OpenSearch when you need external-engine relevance, cursor pagination, or service-owned scaling.\n"
                        "4. Keep the resource contract stable so routes, result shaping, and public-safe fields do not change during the engine swap.\n"
                        "5. Reindex after every engine change and verify `/search/api/resources/%@` plus `/search/api/resources/%@/query`.\n\n"
                        "## Suggested Next Commands\n\n"
                        "```bash\n"
                        "./build/arlen module add jobs\n"
                        "./build/arlen module add search\n"
                        "./build/arlen module doctor --json\n"
                        "./build/arlen module migrate --env development\n"
                        "./build/arlen routes\n"
                        "```\n",
                       resourceLabel ?: @"Generated",
                       resourceLabel ?: @"Generated",
                       providerClassName ?: @"GeneratedSearchProvider",
                       providerClassName ?: @"GeneratedSearchProvider",
                       providerClassName ?: @"GeneratedSearchProvider",
                       providerClassName ?: @"GeneratedSearchProvider",
                       resourceSlug ?: @"search_resource",
                       providerClassName ?: @"GeneratedSearchProvider",
                       providerClassName ?: @"GeneratedSearchProvider",
                       resourceSlug ?: @"search_resource",
                       resourceSlug ?: @"search_resource"];
}

static int CommandGenerate(NSArray *args) {
  BOOL asJSON = ArgsContainFlag(args, @"--json");
  if ([args count] == 1 &&
      ([args[0] isEqualToString:@"--help"] || [args[0] isEqualToString:@"-h"])) {
    PrintGenerateUsage();
    return 0;
  }
  if ([args count] < 2) {
    if (asJSON) {
      return EmitMachineError(@"generate", @"scaffold", @"missing_type_or_name",
                              @"arlen generate: expected type and Name",
                              @"Provide generator type and Name before options.",
                              @"arlen generate controller Home --json", 2);
    }
    fprintf(stderr, "arlen generate: expected type and Name\n");
    PrintGenerateUsage();
    return 2;
  }
  if ([args count] == 2 &&
      ([args[1] isEqualToString:@"--help"] || [args[1] isEqualToString:@"-h"])) {
    PrintGenerateUsage();
    return 0;
  }

  NSString *type = [args[0] lowercaseString];
  NSString *name = CapitalizeFirst(args[1]);
  NSString *controllerBase = TrimControllerSuffix(name);
  NSString *method = @"GET";
  NSString *routePath = nil;
  NSString *actionName = @"index";
  NSString *templateOption = nil;
  BOOL templateRequested = NO;
  BOOL apiMode = NO;
  NSString *presetOption = @"";
  BOOL presetExplicit = NO;
  NSMutableArray<NSString *> *generatedFiles = [NSMutableArray array];
  NSMutableArray<NSString *> *modifiedFiles = [NSMutableArray array];

  for (NSUInteger idx = 2; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--route"]) {
      if (idx + 1 >= [args count]) {
        if (asJSON) {
          return EmitMachineError(@"generate", @"scaffold", @"missing_route_value",
                                  @"arlen generate: --route requires a value",
                                  @"Provide a route path after --route.",
                                  @"arlen generate endpoint UsersShow --route /users/:id --json", 2);
        }
        fprintf(stderr, "arlen generate: --route requires a value\n");
        return 2;
      }
      routePath = args[++idx];
      if (![routePath hasPrefix:@"/"]) {
        routePath = [@"/" stringByAppendingString:routePath];
      }
    } else if ([arg isEqualToString:@"--method"]) {
      if (idx + 1 >= [args count]) {
        if (asJSON) {
          return EmitMachineError(@"generate", @"scaffold", @"missing_method_value",
                                  @"arlen generate: --method requires a value",
                                  @"Provide an HTTP method after --method.",
                                  @"arlen generate endpoint UsersShow --method GET --route /users/:id --json", 2);
        }
        fprintf(stderr, "arlen generate: --method requires a value\n");
        return 2;
      }
      method = [args[++idx] uppercaseString];
    } else if ([arg isEqualToString:@"--action"]) {
      if (idx + 1 >= [args count]) {
        if (asJSON) {
          return EmitMachineError(@"generate", @"scaffold", @"missing_action_value",
                                  @"arlen generate: --action requires a value",
                                  @"Provide an action name after --action.",
                                  @"arlen generate controller Home --action index --json", 2);
        }
        fprintf(stderr, "arlen generate: --action requires a value\n");
        return 2;
      }
      actionName = args[++idx];
    } else if ([arg isEqualToString:@"--template"]) {
      templateRequested = YES;
      if ((idx + 1) < [args count] && ![args[idx + 1] hasPrefix:@"--"]) {
        templateOption = args[++idx];
      }
    } else if ([arg isEqualToString:@"--api"]) {
      apiMode = YES;
    } else if ([arg isEqualToString:@"--preset"]) {
      if (idx + 1 >= [args count]) {
        if (asJSON) {
          return EmitMachineError(@"generate", @"scaffold", @"missing_preset_value",
                                  @"arlen generate: --preset requires a value",
                                  @"Provide a preset value after --preset.",
                                  @"arlen generate plugin Cache --preset redis-cache --json", 2);
        }
        fprintf(stderr, "arlen generate: --preset requires a value\n");
        return 2;
      }
      presetOption = [[args[++idx] lowercaseString] copy];
      presetExplicit = YES;
    } else if ([arg isEqualToString:@"--json"]) {
      asJSON = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      PrintGenerateUsage();
      return 0;
    } else {
      if (asJSON) {
        return EmitMachineError(@"generate", @"scaffold", @"unknown_option",
                                [NSString stringWithFormat:@"arlen generate: unknown option %@", arg ?: @""],
                                @"Remove unsupported options and rerun with documented generator flags.",
                                @"arlen generate controller Home --route / --json", 2);
      }
      fprintf(stderr, "arlen generate: unknown option %s\n", [arg UTF8String]);
      return 2;
    }
  }

  if ([type isEqualToString:@"endpoint"] && [routePath length] == 0) {
    if (asJSON) {
      return EmitMachineError(@"generate", @"scaffold", @"missing_route",
                              @"arlen generate endpoint: --route is required",
                              @"Endpoint generation requires an explicit route.",
                              @"arlen generate endpoint UsersShow --route /users/:id --json", 2);
    }
    fprintf(stderr, "arlen generate endpoint: --route is required\n");
    return 2;
  }
  if (!presetExplicit) {
    if ([type isEqualToString:@"plugin"]) {
      presetOption = @"generic";
    } else if ([type isEqualToString:@"frontend"]) {
      presetOption = @"vanilla-spa";
    }
  }
  if (presetExplicit && ![type isEqualToString:@"plugin"] && ![type isEqualToString:@"frontend"]) {
    if (asJSON) {
      return EmitMachineError(@"generate", @"scaffold", @"preset_invalid_for_generator",
                              @"arlen generate: --preset is only valid for plugin/frontend generators",
                              @"Use --preset only with plugin or frontend generators.",
                              @"arlen generate frontend Dashboard --preset vanilla-spa --json", 2);
    }
    fprintf(stderr, "arlen generate: --preset is only valid for plugin/frontend generators\n");
    return 2;
  }
  if ([type isEqualToString:@"plugin"] && !IsSupportedPluginPreset(presetOption)) {
    if (asJSON) {
      return EmitMachineError(@"generate", @"scaffold", @"unsupported_plugin_preset",
                              [NSString stringWithFormat:@"arlen generate plugin: unsupported --preset %@",
                                                         presetOption ?: @""],
                              @"Use one of: generic, redis-cache, queue-jobs, smtp-mail.",
                              @"arlen generate plugin Cache --preset redis-cache --json", 2);
    }
    fprintf(stderr, "arlen generate plugin: unsupported --preset %s\n", [presetOption UTF8String]);
    return 2;
  }
  if ([type isEqualToString:@"frontend"] && !IsSupportedFrontendPreset(presetOption)) {
    if (asJSON) {
      return EmitMachineError(@"generate", @"scaffold", @"unsupported_frontend_preset",
                              [NSString stringWithFormat:@"arlen generate frontend: unsupported --preset %@",
                                                         presetOption ?: @""],
                              @"Use one of: vanilla-spa, progressive-mpa.",
                              @"arlen generate frontend Dashboard --preset vanilla-spa --json", 2);
    }
    fprintf(stderr, "arlen generate frontend: unsupported --preset %s\n", [presetOption UTF8String]);
    return 2;
  }

  NSString *root = [[NSFileManager defaultManager] currentDirectoryPath];
  NSError *error = nil;
  BOOL ok = NO;

  if ([type isEqualToString:@"controller"] || [type isEqualToString:@"endpoint"]) {
    BOOL createTemplate = templateRequested || ([type isEqualToString:@"endpoint"] && !apiMode);
    NSString *templateLogical = createTemplate
                                    ? NormalizedTemplateLogicalName(templateOption, controllerBase, actionName)
                                    : nil;

    NSString *headerPath =
        [root stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"src/Controllers/%@Controller.h", controllerBase]];
    NSString *implPath =
        [root stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"src/Controllers/%@Controller.m", controllerBase]];
    NSString *header = [NSString stringWithFormat:
                                     @"#import \"ALNController.h\"\n\n"
                                      "@interface %@Controller : ALNController\n@end\n",
                                     controllerBase];

    NSString *actionBody = nil;
    if (apiMode) {
      actionBody = [NSString
          stringWithFormat:
              @"- (id)%@:(ALNContext *)ctx {\n"
               "  return @{ @\"ok\" : @(YES), @\"route\" : ctx.request.path ?: @\"\" };\n"
               "}\n",
              actionName];
    } else if (createTemplate) {
      actionBody = [NSString
          stringWithFormat:
              @"- (id)%@:(ALNContext *)ctx {\n"
               "  (void)ctx;\n"
               "  [self stashValue:@\"%@ %@\" forKey:@\"title\"];\n"
               "  NSError *error = nil;\n"
               "  if (![self renderTemplate:@\"%@\" error:&error]) {\n"
               "    [self setStatus:500];\n"
               "    [self renderText:[NSString stringWithFormat:@\"render failed: %%@\", "
               "error.localizedDescription ?: @\"unknown\"]];\n"
               "  }\n"
               "  return nil;\n"
               "}\n",
              actionName, controllerBase, actionName, templateLogical];
    } else {
      actionBody = [NSString
          stringWithFormat:
              @"- (id)%@:(ALNContext *)ctx {\n"
               "  (void)ctx;\n"
               "  [self renderText:@\"%@ %@\\n\"];\n"
               "  return nil;\n"
               "}\n",
              actionName, controllerBase, actionName];
    }

    NSString *requestImport = apiMode ? @"#import \"ALNRequest.h\"\n" : @"";
    NSString *impl = [NSString stringWithFormat:
                                   @"#import \"%@Controller.h\"\n"
                                    "#import \"ALNContext.h\"\n"
                                    "%@\n"
                                    "@implementation %@Controller\n\n"
                                    "%@\n"
                                    "@end\n",
                                   controllerBase, requestImport, controllerBase, actionBody];

    ok = WriteTextFile(headerPath, header, NO, &error);
    if (ok) {
      AppendRelativePath(generatedFiles, root, headerPath);
    }
    if (ok) {
      ok = WriteTextFile(implPath, impl, NO, &error);
      if (ok) {
        AppendRelativePath(generatedFiles, root, implPath);
      }
    }

    if (ok && createTemplate) {
      if ([templateLogical containsString:@".."]) {
        ok = NO;
        error = [NSError errorWithDomain:@"Arlen.Error"
                                    code:12
                                userInfo:@{
                                  NSLocalizedDescriptionKey : @"template path must not contain '..'"
                                }];
      } else {
        NSString *templatePath =
            [root stringByAppendingPathComponent:[NSString stringWithFormat:@"templates/%@.html.eoc",
                                                                            templateLogical]];
        ok = WriteTextFile(templatePath,
                           GeneratedHTMLTemplateScaffold(root, templateLogical),
                           NO,
                           &error);
        if (ok) {
          AppendRelativePath(generatedFiles, root, templatePath);
        }
      }
    }

    if (ok && [routePath length] > 0) {
      NSString *modifiedRouteFile = nil;
      ok = WireGeneratedRoute(root, method, routePath, controllerBase, actionName, &modifiedRouteFile, &error);
      if (ok) {
        AppendRelativePath(modifiedFiles, root, modifiedRouteFile);
      }
    }
  } else if ([type isEqualToString:@"model"]) {
    NSString *headerPath =
        [root stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"src/Models/%@Repository.h", name]];
    NSString *implPath =
        [root stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"src/Models/%@Repository.m", name]];
    ok = WriteTextFile(headerPath,
                       [NSString stringWithFormat:
                                     @"#import <Foundation/Foundation.h>\n\n"
                                      "@interface %@Repository : NSObject\n@end\n",
                                     name],
                       NO, &error);
    if (ok) {
      AppendRelativePath(generatedFiles, root, headerPath);
    }
    if (ok) {
      ok = WriteTextFile(implPath,
                         [NSString stringWithFormat:@"#import \"%@Repository.h\"\n\n@implementation %@Repository\n@end\n",
                                                     name, name],
                         NO, &error);
      if (ok) {
        AppendRelativePath(generatedFiles, root, implPath);
      }
    }
  } else if ([type isEqualToString:@"migration"]) {
    NSString *timestamp =
        [NSString stringWithFormat:@"%lld", (long long)[[NSDate date] timeIntervalSince1970]];
    NSString *path =
        [root stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"db/migrations/%@_%@.sql", timestamp,
                                             [name lowercaseString]]];
    ok = WriteTextFile(path, @"-- migration\n", NO, &error);
    if (ok) {
      AppendRelativePath(generatedFiles, root, path);
    }
  } else if ([type isEqualToString:@"test"]) {
    NSString *path =
        [root stringByAppendingPathComponent:[NSString stringWithFormat:@"tests/%@Tests.m", name]];
    NSString *content = [NSString stringWithFormat:
                                      @"#import <XCTest/XCTest.h>\n\n"
                                       "@interface %@Tests : XCTestCase\n@end\n\n"
                                       "@implementation %@Tests\n"
                                       "- (void)testPlaceholder {\n"
                                       "  XCTAssertTrue(YES);\n"
                                       "}\n@end\n",
                                      name, name];
    ok = WriteTextFile(path, content, NO, &error);
    if (ok) {
      AppendRelativePath(generatedFiles, root, path);
    }
  } else if ([type isEqualToString:@"plugin"]) {
    NSString *pluginName = [name hasSuffix:@"Plugin"] ? name : [name stringByAppendingString:@"Plugin"];
    NSString *pluginBase = [pluginName hasSuffix:@"Plugin"] && [pluginName length] > [@"Plugin" length]
                               ? [pluginName substringToIndex:[pluginName length] - [@"Plugin" length]]
                               : pluginName;
    NSString *headerPath =
        [root stringByAppendingPathComponent:[NSString stringWithFormat:@"src/Plugins/%@.h", pluginName]];
    NSString *implPath =
        [root stringByAppendingPathComponent:[NSString stringWithFormat:@"src/Plugins/%@.m", pluginName]];
    NSString *logicalName = [[pluginBase lowercaseString] copy];

    NSString *header = [NSString stringWithFormat:
                                     @"#import <Foundation/Foundation.h>\n"
                                      "#import \"ArlenServer.h\"\n\n"
                                      "@interface %@ : NSObject <ALNPlugin, ALNLifecycleHook>\n"
                                      "@end\n",
                                     pluginName];
    NSString *impl = PluginImplementationForPreset(pluginName, logicalName, presetOption);

    ok = WriteTextFile(headerPath, header, NO, &error);
    if (ok) {
      AppendRelativePath(generatedFiles, root, headerPath);
    }
    if (ok) {
      ok = WriteTextFile(implPath, impl, NO, &error);
      if (ok) {
        AppendRelativePath(generatedFiles, root, implPath);
      }
    }
    if (ok) {
      ok = AddPluginClassToAppConfig(root, pluginName, &error);
      if (ok) {
        AppendRelativePath(modifiedFiles, root, [root stringByAppendingPathComponent:@"config/app.plist"]);
      }
    }
  } else if ([type isEqualToString:@"frontend"]) {
    NSString *slug = NormalizedFrontendSlug(name);
    NSDictionary<NSString *, NSString *> *files =
        FrontendStarterFilesForPreset(presetOption, slug, name);
    ok = YES;
    NSArray<NSString *> *paths = [[files allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *relativePath in paths) {
      NSString *content = [files[relativePath] isKindOfClass:[NSString class]] ? files[relativePath] : @"";
      NSString *absolutePath = [root stringByAppendingPathComponent:relativePath];
      if (!WriteTextFile(absolutePath, content, NO, &error)) {
        ok = NO;
        break;
      }
      AppendRelativePath(generatedFiles, root, absolutePath);
    }
  } else if ([type isEqualToString:@"search"]) {
    ok = YES;
    NSError *readinessError = nil;
    BOOL jobsInstalled = IsModuleInstalledAtAppRoot(root, @"jobs", &readinessError);
    if (readinessError != nil) {
      ok = NO;
      error = readinessError;
    } else if (!jobsInstalled) {
      ok = NO;
      error = [NSError errorWithDomain:@"Arlen.Error"
                                  code:15
                              userInfo:@{
                                NSLocalizedDescriptionKey :
                                    @"arlen generate search requires the vendored jobs module; run `arlen module add jobs` first"
                              }];
    }

    BOOL searchInstalled = NO;
    if (ok) {
      readinessError = nil;
      searchInstalled = IsModuleInstalledAtAppRoot(root, @"search", &readinessError);
      if (readinessError != nil) {
        ok = NO;
        error = readinessError;
      } else if (!searchInstalled) {
        ok = NO;
        error = [NSError errorWithDomain:@"Arlen.Error"
                                    code:16
                                userInfo:@{
                                  NSLocalizedDescriptionKey :
                                      @"arlen generate search requires the vendored search module; run `arlen module add search` first"
                                }];
      }
    }

    NSString *providerClassName = [name hasSuffix:@"SearchProvider"] ? name : [name stringByAppendingString:@"SearchProvider"];
    NSString *resourceBaseName = TrimSearchProviderSuffix(providerClassName);
    NSString *resourceSlug = NormalizedSearchResourceSlug(resourceBaseName);
    NSString *headerPath =
        [root stringByAppendingPathComponent:[NSString stringWithFormat:@"src/Search/%@.h", providerClassName]];
    NSString *implPath =
        [root stringByAppendingPathComponent:[NSString stringWithFormat:@"src/Search/%@.m", providerClassName]];
    NSString *guidePath =
        [root stringByAppendingPathComponent:[NSString stringWithFormat:@"docs/search/%@_search.md", resourceSlug]];

    if (ok) {
      ok = WriteTextFile(headerPath, GeneratedSearchProviderHeader(providerClassName), NO, &error);
      if (ok) {
        AppendRelativePath(generatedFiles, root, headerPath);
      }
    }
    if (ok) {
      ok = WriteTextFile(implPath,
                         GeneratedSearchProviderImplementation(providerClassName, resourceBaseName, resourceSlug),
                         NO,
                         &error);
      if (ok) {
        AppendRelativePath(generatedFiles, root, implPath);
      }
    }
    if (ok) {
      ok = WriteTextFile(guidePath,
                         GeneratedSearchGuide(providerClassName, resourceSlug, resourceBaseName),
                         NO,
                         &error);
      if (ok) {
        AppendRelativePath(generatedFiles, root, guidePath);
      }
    }
    if (ok) {
      ok = AddSearchProviderClassToAppConfig(root, providerClassName, &error);
      if (ok) {
        AppendRelativePath(modifiedFiles, root, [root stringByAppendingPathComponent:@"config/app.plist"]);
      }
    }
  } else {
    if (asJSON) {
      return EmitMachineError(@"generate", @"scaffold", @"unknown_generator_type",
                              [NSString stringWithFormat:@"arlen generate: unknown type %@", type ?: @""],
                              @"Use one of: controller, endpoint, model, migration, test, plugin, frontend, search.",
                              @"arlen generate controller Home --json", 2);
    }
    fprintf(stderr, "arlen generate: unknown type %s\n", [type UTF8String]);
    return 2;
  }

  if (!ok) {
    if (asJSON) {
      NSString *message = [NSString stringWithFormat:@"arlen generate: %@",
                                                     error.localizedDescription ?: @"generation failed"];
      NSString *fixitAction = @"Update generator inputs or remove conflicting files before retrying.";
      NSString *fixitExample = [NSString stringWithFormat:@"arlen generate %@ %@ --json",
                                                          type ?: @"controller", name ?: @"Home"];
      if ([error.localizedDescription containsString:@"File exists:"]) {
        fixitAction = @"Remove or rename existing files, or choose a different artifact name.";
      }
      return EmitMachineError(@"generate", @"scaffold", @"generation_failed",
                              message, fixitAction, fixitExample, 1);
    }
    fprintf(stderr, "arlen generate: %s\n", [[error localizedDescription] UTF8String]);
    return 1;
  }

  if (asJSON) {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"version"] = AgentContractVersion();
    payload[@"command"] = @"generate";
    payload[@"workflow"] = @"scaffold";
    payload[@"status"] = @"ok";
    payload[@"generator"] = type ?: @"";
    payload[@"name"] = name ?: @"";
    payload[@"app_root"] = [root stringByStandardizingPath];
    if ([routePath length] > 0) {
      payload[@"route"] = routePath;
    }
    if ([presetOption length] > 0 &&
        ([type isEqualToString:@"plugin"] || [type isEqualToString:@"frontend"])) {
      payload[@"preset"] = presetOption;
    }
    payload[@"generated_files"] = SortedUniqueStrings(generatedFiles);
    payload[@"modified_files"] = SortedUniqueStrings(modifiedFiles);
    PrintJSONPayload(stdout, payload);
    return 0;
  }

  fprintf(stdout, "Generated %s %s\n", [type UTF8String], [name UTF8String]);
  return 0;
}

static NSString *ResolveFrameworkRootForCommandDetailed(NSString *commandName,
                                                        BOOL emitErrors,
                                                        NSString **errorMessage) {
  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *override = EnvValue("ARLEN_FRAMEWORK_ROOT");
  if ([override length] > 0) {
    NSString *candidate = [override hasPrefix:@"/"]
                              ? [override stringByStandardizingPath]
                              : [[appRoot stringByAppendingPathComponent:override] stringByStandardizingPath];
    if (IsFrameworkRoot(candidate)) {
      return candidate;
    }
    NSString *message =
        [NSString stringWithFormat:@"arlen %@: ARLEN_FRAMEWORK_ROOT does not point to a valid Arlen root: %@",
                                   commandName ?: @"", candidate ?: @""];
    if (errorMessage != NULL) {
      *errorMessage = message;
    }
    if (emitErrors) {
      fprintf(stderr, "%s\n", [message UTF8String]);
    }
    return nil;
  }

  NSString *frameworkRoot = FindFrameworkRoot(appRoot);
  if ([frameworkRoot length] == 0) {
    frameworkRoot = FrameworkRootFromExecutablePath();
  }
  if ([frameworkRoot length] == 0) {
    NSString *message = [NSString stringWithFormat:@"arlen %@: could not locate Arlen framework root from %@",
                                                   commandName ?: @"", appRoot ?: @""];
    if (errorMessage != NULL) {
      *errorMessage = message;
    }
    if (emitErrors) {
      fprintf(stderr, "%s\n", [message UTF8String]);
    }
    return nil;
  }
  return frameworkRoot;
}

static NSString *ResolveFrameworkRootForCommand(NSString *commandName) {
  return ResolveFrameworkRootForCommandDetailed(commandName, YES, NULL);
}

static int CommandBoomhauer(NSArray *args) {
  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *frameworkRoot = ResolveFrameworkRootForCommand(@"boomhauer");
  if ([frameworkRoot length] == 0) {
    return 1;
  }

  NSMutableArray *quoted = [NSMutableArray array];
  for (NSString *arg in args ?: @[]) {
    [quoted addObject:ShellQuote(arg)];
  }
  NSString *suffix =
      ([quoted count] > 0) ? [NSString stringWithFormat:@" %@", [quoted componentsJoinedByString:@" "]] : @"";

  NSString *command = [NSString stringWithFormat:@"cd %@ && ARLEN_APP_ROOT=%@ ARLEN_FRAMEWORK_ROOT=%@ ./bin/boomhauer%@",
                                                 ShellQuote(frameworkRoot), ShellQuote(appRoot),
                                                 ShellQuote(frameworkRoot), suffix];
  return RunShellCommand(command);
}

static int CommandPropane(NSArray *args) {
  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *frameworkRoot = ResolveFrameworkRootForCommand(@"propane");
  if ([frameworkRoot length] == 0) {
    return 1;
  }

  NSMutableArray *quoted = [NSMutableArray array];
  for (NSString *arg in args ?: @[]) {
    [quoted addObject:ShellQuote(arg)];
  }
  NSString *suffix = ([quoted count] > 0) ? [NSString stringWithFormat:@" %@", [quoted componentsJoinedByString:@" "]] : @"";

  NSString *command = [NSString
      stringWithFormat:@"cd %@ && ARLEN_APP_ROOT=%@ ARLEN_FRAMEWORK_ROOT=%@ ./bin/propane%@",
                       ShellQuote(frameworkRoot), ShellQuote(appRoot), ShellQuote(frameworkRoot), suffix];
  return RunShellCommand(command);
}

static int CommandJobs(NSArray *args) {
  if ([args count] == 0) {
    PrintJobsUsage();
    return 2;
  }

  NSString *subcommand = args[0];
  NSArray *subArgs = ([args count] > 1) ? [args subarrayWithRange:NSMakeRange(1, [args count] - 1)] : @[];
  if (![subcommand isEqualToString:@"worker"]) {
    PrintJobsUsage();
    return 2;
  }

  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *frameworkRoot = ResolveFrameworkRootForCommand(@"jobs");
  if ([frameworkRoot length] == 0) {
    return 1;
  }

  NSMutableArray *quoted = [NSMutableArray array];
  for (NSString *arg in subArgs ?: @[]) {
    [quoted addObject:ShellQuote(arg)];
  }
  NSString *suffix = ([quoted count] > 0) ? [NSString stringWithFormat:@" %@", [quoted componentsJoinedByString:@" "]] : @"";

  NSString *command =
      [NSString stringWithFormat:@"cd %@ && ARLEN_APP_ROOT=%@ ARLEN_FRAMEWORK_ROOT=%@ ./bin/jobs-worker%@",
                                 ShellQuote(frameworkRoot), ShellQuote(appRoot), ShellQuote(frameworkRoot), suffix];
  return RunShellCommand(command);
}

static int CommandRoutes(void) {
  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *frameworkRoot = ResolveFrameworkRootForCommand(@"routes");
  if ([frameworkRoot length] == 0) {
    return 1;
  }
  NSString *command = [NSString stringWithFormat:@"%@ && %@",
                                                 BoomhauerBuildCommand(frameworkRoot),
                                                 BoomhauerLaunchCommand(@[ @"--print-routes" ],
                                                                        frameworkRoot, appRoot)];
  return RunShellCommand(command);
}

static int CommandTest(NSArray *args) {
  NSString *frameworkRoot = ResolveFrameworkRootForCommand(@"test");
  if ([frameworkRoot length] == 0) {
    return 1;
  }
  if ([args count] == 0 || [args containsObject:@"--all"]) {
    return RunShellCommand([NSString stringWithFormat:@"cd %@ && make test", ShellQuote(frameworkRoot)]);
  }
  if ([args containsObject:@"--unit"]) {
    return RunShellCommand([NSString stringWithFormat:@"cd %@ && make test-unit", ShellQuote(frameworkRoot)]);
  }
  if ([args containsObject:@"--integration"]) {
    return RunShellCommand([NSString stringWithFormat:@"cd %@ && make test-integration", ShellQuote(frameworkRoot)]);
  }
  fprintf(stderr, "arlen test: unsupported options\n");
  return 2;
}

static int CommandPerf(void) {
  NSString *frameworkRoot = ResolveFrameworkRootForCommand(@"perf");
  if ([frameworkRoot length] == 0) {
    return 1;
  }
  return RunShellCommand([NSString stringWithFormat:@"cd %@ && make perf", ShellQuote(frameworkRoot)]);
}

static int CommandDeployTargetSample(NSArray *args) {
  BOOL asJSON = ArgsContainFlag(args, @"--json");
  BOOL writeFile = NO;
  BOOL force = NO;
  NSString *targetName = @"production";
  NSString *sshHost = nil;
  NSString *outputPath = nil;
  NSString *appRoot = [[[NSFileManager defaultManager] currentDirectoryPath] stringByStandardizingPath];

  for (NSUInteger idx = 0; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--write"]) {
      writeFile = YES;
    } else if ([arg isEqualToString:@"--force"]) {
      force = YES;
    } else if ([arg isEqualToString:@"--json"]) {
      asJSON = YES;
    } else if ([arg isEqualToString:@"--target"]) {
      if (idx + 1 >= [args count]) {
        return EmitMachineError(@"deploy", @"deploy.target.sample", @"missing_option_value",
                                @"arlen deploy target sample: --target requires a value",
                                @"Pass a target name after --target.",
                                @"arlen deploy target sample --target production", 2);
      }
      targetName = Trimmed(args[++idx]);
    } else if ([arg isEqualToString:@"--ssh-host"]) {
      if (idx + 1 >= [args count]) {
        return EmitMachineError(@"deploy", @"deploy.target.sample", @"missing_option_value",
                                @"arlen deploy target sample: --ssh-host requires a value",
                                @"Pass an SSH host after --ssh-host.",
                                @"arlen deploy target sample --ssh-host deploy@app.example.com", 2);
      }
      sshHost = args[++idx];
    } else if ([arg isEqualToString:@"--output"]) {
      if (idx + 1 >= [args count]) {
        return EmitMachineError(@"deploy", @"deploy.target.sample", @"missing_option_value",
                                @"arlen deploy target sample: --output requires a value",
                                @"Pass an output path after --output.",
                                @"arlen deploy target sample --write --output config/deploy.plist.example", 2);
      }
      outputPath = args[++idx];
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      fprintf(stdout,
              "Usage: arlen deploy target sample [--write] [--force] [--target <name>] [--ssh-host <host>] [--json]\n");
      return 0;
    } else {
      return asJSON ? EmitMachineError(@"deploy", @"deploy.target.sample", @"unknown_option",
                                       [NSString stringWithFormat:@"unknown option %@", arg ?: @""],
                                       @"Use supported options for `arlen deploy target sample`.",
                                       @"arlen deploy target sample --write --json", 2)
                    : 2;
    }
  }

  if ([targetName length] == 0) {
    targetName = @"production";
  }
  NSString *sample = DeployTargetSamplePlist(targetName, sshHost);
  NSString *resolvedOutput = [outputPath length] > 0
      ? [ResolvePathFromRoot(appRoot, outputPath) stringByStandardizingPath]
      : [[appRoot stringByAppendingPathComponent:@"config/deploy.plist.example"] stringByStandardizingPath];

  if (writeFile) {
    NSError *error = nil;
    if (!WriteTextFile(resolvedOutput, sample, force, &error)) {
      return asJSON ? EmitMachineError(@"deploy", @"deploy.target.sample", @"deploy_sample_write_failed",
                                       error.localizedDescription ?: @"failed writing deploy target sample",
                                       @"Use --force to overwrite an existing sample or choose another output path.",
                                       @"arlen deploy target sample --write --force --json", 1)
                    : 1;
    }
    if (asJSON) {
      NSDictionary *payload = @{
        @"version" : AgentContractVersion(),
        @"command" : @"deploy",
        @"workflow" : @"deploy.target.sample",
        @"subcommand" : @"target sample",
        @"status" : @"ok",
        @"target_name" : targetName ?: @"production",
        @"path" : resolvedOutput ?: @"",
        @"written" : @YES,
      };
      PrintJSONPayload(stdout, payload);
      return 0;
    }
    fprintf(stdout, "Wrote deploy target sample to %s\n", [resolvedOutput UTF8String]);
    return 0;
  }

  if (asJSON) {
    NSDictionary *payload = @{
      @"version" : AgentContractVersion(),
      @"command" : @"deploy",
      @"workflow" : @"deploy.target.sample",
      @"subcommand" : @"target sample",
      @"status" : @"ok",
      @"target_name" : targetName ?: @"production",
      @"path" : resolvedOutput ?: @"",
      @"written" : @NO,
      @"sample" : sample ?: @"",
    };
    PrintJSONPayload(stdout, payload);
    return 0;
  }
  fprintf(stdout, "%s", [sample UTF8String]);
  return 0;
}

static int CommandDeploy(NSArray *args) {
  BOOL rootJSON = [args containsObject:@"--json"];
  if ([args count] == 0 || [[args[0] description] hasPrefix:@"--"]) {
    NSString *appRoot = [[[NSFileManager defaultManager] currentDirectoryPath] stringByStandardizingPath];
    NSString *configPath = nil;
    NSError *targetError = nil;
    NSArray *targets = LoadDeployTargets(appRoot, &configPath, &targetError);
    if (rootJSON) {
      NSDictionary *payload = @{
        @"version" : AgentContractVersion(),
        @"command" : @"deploy",
        @"workflow" : @"deploy.help",
        @"subcommand" : @"help",
        @"status" : (targets == nil) ? @"error" : @"ok",
        @"target_config_path" : configPath ?: @"",
        @"target_count" : @([targets count]),
        @"targets" : DeployTargetPayloads(targets ?: @[]),
        @"next_actions" : ([targets count] > 0)
            ? @[ @"arlen deploy list", @"arlen deploy dryrun <target>", @"arlen deploy push <target>" ]
            : @[ @"Copy config/deploy.plist.example to config/deploy.plist, or run arlen deploy target sample --write." ],
        @"error" : (targets == nil)
            ? @{
                @"code" : @"deploy_targets_invalid",
                @"message" : targetError.localizedDescription ?: @"failed to load deploy targets",
                @"fixit" : @{
                  @"action" : @"Fix config/deploy.plist and rerun arlen deploy list.",
                  @"example" : @"arlen deploy list --json",
                }
              }
            : @{},
      };
      PrintJSONPayload(stdout, payload);
      return (targets == nil) ? 1 : 0;
    }
    PrintDeployUsage();
    if (targets == nil) {
      fprintf(stderr, "\narlen deploy: failed to load deploy targets: %s\n",
              [(targetError.localizedDescription ?: @"unknown error") UTF8String]);
      return 1;
    }
    if ([targets count] > 0) {
      fprintf(stdout, "\nConfigured targets: %lu. Run `arlen deploy list` to inspect them.\n",
              (unsigned long)[targets count]);
    } else {
      fprintf(stdout, "\nNo deploy targets configured. Copy config/deploy.plist.example to config/deploy.plist, or run `arlen deploy target sample --write`.\n");
    }
    return 0;
  }

  if ([args[0] isEqualToString:@"target"]) {
    if ([args count] >= 2 && [args[1] isEqualToString:@"sample"]) {
      NSArray *sampleArgs = ([args count] > 2) ? [args subarrayWithRange:NSMakeRange(2, [args count] - 2)] : @[];
      return CommandDeployTargetSample(sampleArgs);
    }
    fprintf(stderr, "arlen deploy target: expected sample\n");
    PrintDeployUsage();
    return 2;
  }

  NSString *subcommand = args[0];
  if ([subcommand isEqualToString:@"--help"] || [subcommand isEqualToString:@"-h"]) {
    PrintDeployUsage();
    return 0;
  }
  BOOL usedPlanAlias = [subcommand isEqualToString:@"plan"];
  if (usedPlanAlias) {
    subcommand = @"dryrun";
  }
  if (![@[ @"list", @"dryrun", @"init", @"push", @"releases", @"release", @"status", @"rollback", @"doctor", @"logs" ] containsObject:subcommand]) {
    fprintf(stderr, "arlen deploy: unknown subcommand %s\n", [subcommand UTF8String]);
    PrintDeployUsage();
    return 2;
  }

  NSString *appRoot = [[[NSFileManager defaultManager] currentDirectoryPath] stringByStandardizingPath];
  NSString *frameworkRootOverride = nil;
  NSString *releasesDir = nil;
  NSString *releaseID = nil;
  NSString *certificationManifest = nil;
  NSString *jsonPerformanceManifest = nil;
  NSString *environment = @"production";
  NSString *baseURL = nil;
  NSString *targetProfile = nil;
  NSString *runtimeStrategy = @"system";
  NSString *databaseMode = nil;
  NSString *databaseAdapter = nil;
  NSString *databaseTarget = @"default";
  NSMutableArray<NSString *> *requiredEnvironmentKeys = [NSMutableArray array];
  NSString *remoteBuildCheckCommand = nil;
  NSString *serviceName = nil;
  NSString *runtimeAction = @"reload";
  NSString *runtimeRestartCommand = nil;
  NSString *runtimeReloadCommand = nil;
  NSTimeInterval healthStartupTimeoutSeconds = 30.0;
  NSTimeInterval healthStartupIntervalSeconds = 1.0;
  NSString *logFilePath = nil;
  BOOL allowMissingCertification = NO;
  BOOL allowRemoteRebuild = NO;
  BOOL asJSON = NO;
  BOOL skipMigrate = NO;
  BOOL followLogs = NO;
  BOOL releasesDirExplicit = NO;
  BOOL environmentExplicit = NO;
  BOOL baseURLExplicit = NO;
  BOOL targetProfileExplicit = NO;
  BOOL runtimeStrategyExplicit = NO;
  BOOL databaseModeExplicit = NO;
  BOOL databaseAdapterExplicit = NO;
  BOOL databaseTargetExplicit = NO;
  BOOL serviceNameExplicit = NO;
  BOOL runtimeActionExplicit = NO;
  BOOL runtimeRestartCommandExplicit = NO;
  BOOL runtimeReloadCommandExplicit = NO;
  BOOL healthStartupTimeoutExplicit = NO;
  BOOL healthStartupIntervalExplicit = NO;
  NSInteger logLines = 200;
  NSString *targetName = nil;

  NSArray *subArgs = ([args count] > 1) ? [args subarrayWithRange:NSMakeRange(1, [args count] - 1)] : @[];
  for (NSUInteger idx = 0; idx < [subArgs count]; idx++) {
    NSString *arg = subArgs[idx];
    if ([arg isEqualToString:@"--app-root"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --app-root requires a value",
                                  @"Pass the app root path after --app-root.",
                                  @"arlen deploy dryrun --app-root /path/to/app --json", 2);
        }
        fprintf(stderr, "arlen deploy: --app-root requires a value\n");
        return 2;
      }
      appRoot = [ResolvePathFromRoot([[NSFileManager defaultManager] currentDirectoryPath], subArgs[++idx])
                    stringByStandardizingPath];
    } else if ([arg isEqualToString:@"--framework-root"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --framework-root requires a value",
                                  @"Pass the framework root path after --framework-root.",
                                  @"arlen deploy dryrun --framework-root /path/to/Arlen --json", 2);
        }
        fprintf(stderr, "arlen deploy: --framework-root requires a value\n");
        return 2;
      }
      frameworkRootOverride =
          [ResolvePathFromRoot([[NSFileManager defaultManager] currentDirectoryPath], subArgs[++idx])
              stringByStandardizingPath];
    } else if ([arg isEqualToString:@"--releases-dir"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --releases-dir requires a value",
                                  @"Pass the releases directory after --releases-dir.",
                                  @"arlen deploy push --releases-dir /srv/app/releases --json", 2);
        }
        fprintf(stderr, "arlen deploy: --releases-dir requires a value\n");
        return 2;
      }
      releasesDir = [ResolvePathFromRoot([[NSFileManager defaultManager] currentDirectoryPath], subArgs[++idx])
                        stringByStandardizingPath];
      releasesDirExplicit = YES;
    } else if ([arg isEqualToString:@"--release-id"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --release-id requires a value",
                                  @"Pass a release identifier after --release-id.",
                                  @"arlen deploy push --release-id rel-20260407 --json", 2);
        }
        fprintf(stderr, "arlen deploy: --release-id requires a value\n");
        return 2;
      }
      releaseID = subArgs[++idx];
    } else if ([arg isEqualToString:@"--certification-manifest"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value",
                                  @"arlen deploy: --certification-manifest requires a value",
                                  @"Pass the certification manifest path after --certification-manifest.",
                                  @"arlen deploy dryrun --certification-manifest build/release_confidence/phase9j/manifest.json --json",
                                  2);
        }
        fprintf(stderr, "arlen deploy: --certification-manifest requires a value\n");
        return 2;
      }
      certificationManifest =
          [ResolvePathFromRoot([[NSFileManager defaultManager] currentDirectoryPath], subArgs[++idx])
              stringByStandardizingPath];
    } else if ([arg isEqualToString:@"--json-performance-manifest"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value",
                                  @"arlen deploy: --json-performance-manifest requires a value",
                                  @"Pass the JSON performance manifest path after --json-performance-manifest.",
                                  @"arlen deploy dryrun --json-performance-manifest build/release_confidence/phase10e/manifest.json --json",
                                  2);
        }
        fprintf(stderr, "arlen deploy: --json-performance-manifest requires a value\n");
        return 2;
      }
      jsonPerformanceManifest =
          [ResolvePathFromRoot([[NSFileManager defaultManager] currentDirectoryPath], subArgs[++idx])
              stringByStandardizingPath];
    } else if ([arg isEqualToString:@"--env"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --env requires a value",
                                  @"Pass the runtime environment after --env.",
                                  @"arlen deploy release --env production --json", 2);
        }
        fprintf(stderr, "arlen deploy: --env requires a value\n");
        return 2;
      }
      environment = subArgs[++idx];
      environmentExplicit = YES;
    } else if ([arg isEqualToString:@"--base-url"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --base-url requires a value",
                                  @"Pass the probe base URL after --base-url.",
                                  @"arlen deploy release --base-url http://127.0.0.1:3000 --json", 2);
        }
        fprintf(stderr, "arlen deploy: --base-url requires a value\n");
        return 2;
      }
      baseURL = subArgs[++idx];
      baseURLExplicit = YES;
    } else if ([arg isEqualToString:@"--target-profile"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --target-profile requires a value",
                                  @"Pass the deployment target profile after --target-profile.",
                                  @"arlen deploy dryrun --target-profile linux-x86_64-gnustep-clang --json", 2);
        }
        fprintf(stderr, "arlen deploy: --target-profile requires a value\n");
        return 2;
      }
      targetProfile = Trimmed(subArgs[++idx]);
      targetProfileExplicit = YES;
    } else if ([arg isEqualToString:@"--runtime-strategy"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --runtime-strategy requires a value",
                                  @"Use system, managed, or bundled.",
                                  @"arlen deploy dryrun --runtime-strategy managed --json", 2);
        }
        fprintf(stderr, "arlen deploy: --runtime-strategy requires a value\n");
        return 2;
      }
      runtimeStrategy = [Trimmed(subArgs[++idx]) lowercaseString];
      runtimeStrategyExplicit = YES;
    } else if ([arg isEqualToString:@"--database-mode"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --database-mode requires a value",
                                  @"Use external, host_local, or embedded.",
                                  @"arlen deploy dryrun --database-mode external --json", 2);
        }
        fprintf(stderr, "arlen deploy: --database-mode requires a value\n");
        return 2;
      }
      databaseMode = [Trimmed(subArgs[++idx]) lowercaseString];
      databaseModeExplicit = YES;
    } else if ([arg isEqualToString:@"--database-adapter"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --database-adapter requires a value",
                                  @"Pass the declared database adapter name.",
                                  @"arlen deploy dryrun --database-adapter postgresql --json", 2);
        }
        fprintf(stderr, "arlen deploy: --database-adapter requires a value\n");
        return 2;
      }
      databaseAdapter = [Trimmed(subArgs[++idx]) lowercaseString];
      databaseAdapterExplicit = YES;
    } else if ([arg isEqualToString:@"--database-target"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --database-target requires a value",
                                  @"Pass the declared database target name.",
                                  @"arlen deploy dryrun --database-target default --json", 2);
        }
        fprintf(stderr, "arlen deploy: --database-target requires a value\n");
        return 2;
      }
      databaseTarget = NormalizeDatabaseTarget(subArgs[++idx]);
      databaseTargetExplicit = YES;
      if (!DatabaseTargetIsValid(databaseTarget)) {
        return asJSON ? EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                         @"invalid_database_target",
                                         @"invalid --database-target; expected [a-z][a-z0-9_]* up to 32 characters",
                                         @"Use a safe database target identifier.",
                                         @"arlen deploy dryrun --database-target default --json", 2)
                      : 2;
      }
    } else if ([arg isEqualToString:@"--require-env-key"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --require-env-key requires a value",
                                  @"Pass the required environment key name after --require-env-key.",
                                  @"arlen deploy dryrun --require-env-key ARLEN_DATABASE_URL --json", 2);
        }
        fprintf(stderr, "arlen deploy: --require-env-key requires a value\n");
        return 2;
      }
      NSString *requiredKey = Trimmed(subArgs[++idx]);
      if ([requiredKey length] == 0) {
        return asJSON ? EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                         @"invalid_required_env_key",
                                         @"invalid --require-env-key; expected a non-empty environment key",
                                         @"Pass the exact environment variable name to record.",
                                         @"arlen deploy dryrun --require-env-key ARLEN_DATABASE_URL --json", 2)
                      : 2;
      }
      if (![requiredEnvironmentKeys containsObject:requiredKey]) {
        [requiredEnvironmentKeys addObject:requiredKey];
      }
    } else if ([arg isEqualToString:@"--remote-build-check-command"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --remote-build-check-command requires a value",
                                  @"Pass a shell command that validates the target build chain.",
                                  @"arlen deploy doctor --remote-build-check-command 'ssh app1 true' --json", 2);
        }
        fprintf(stderr, "arlen deploy: --remote-build-check-command requires a value\n");
        return 2;
      }
      remoteBuildCheckCommand = subArgs[++idx];
    } else if ([arg isEqualToString:@"--service"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --service requires a value",
                                  @"Pass the systemd unit name after --service.",
                                  @"arlen deploy status --service arlen@myapp --json", 2);
        }
        fprintf(stderr, "arlen deploy: --service requires a value\n");
        return 2;
      }
      serviceName = subArgs[++idx];
      serviceNameExplicit = YES;
    } else if ([arg isEqualToString:@"--runtime-action"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --runtime-action requires a value",
                                  @"Use reload, restart, or none.",
                                  @"arlen deploy rollback --runtime-action restart --json", 2);
        }
        fprintf(stderr, "arlen deploy: --runtime-action requires a value\n");
        return 2;
      }
      runtimeAction = [subArgs[++idx] lowercaseString];
      runtimeActionExplicit = YES;
    } else if ([arg isEqualToString:@"--runtime-restart-command"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --runtime-restart-command requires a value",
                                  @"Pass the non-interactive restart command.",
                                  @"arlen deploy release --runtime-restart-command 'sudo -n systemctl restart arlen@myapp' --json", 2);
        }
        fprintf(stderr, "arlen deploy: --runtime-restart-command requires a value\n");
        return 2;
      }
      runtimeRestartCommand = subArgs[++idx];
      runtimeRestartCommandExplicit = YES;
    } else if ([arg isEqualToString:@"--runtime-reload-command"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --runtime-reload-command requires a value",
                                  @"Pass the non-interactive reload command.",
                                  @"arlen deploy release --runtime-reload-command 'sudo -n systemctl reload arlen@myapp' --json", 2);
        }
        fprintf(stderr, "arlen deploy: --runtime-reload-command requires a value\n");
        return 2;
      }
      runtimeReloadCommand = subArgs[++idx];
      runtimeReloadCommandExplicit = YES;
    } else if ([arg isEqualToString:@"--health-startup-timeout"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --health-startup-timeout requires a value",
                                  @"Pass the maximum health startup wait in seconds.",
                                  @"arlen deploy release --health-startup-timeout 30 --json", 2);
        }
        fprintf(stderr, "arlen deploy: --health-startup-timeout requires a value\n");
        return 2;
      }
      healthStartupTimeoutSeconds = TimeIntervalValueForDeployKey(subArgs[++idx], 30.0);
      healthStartupTimeoutExplicit = YES;
    } else if ([arg isEqualToString:@"--health-startup-interval"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --health-startup-interval requires a value",
                                  @"Pass the health startup polling interval in seconds.",
                                  @"arlen deploy release --health-startup-interval 1 --json", 2);
        }
        fprintf(stderr, "arlen deploy: --health-startup-interval requires a value\n");
        return 2;
      }
      healthStartupIntervalSeconds = TimeIntervalValueForDeployKey(subArgs[++idx], 1.0);
      healthStartupIntervalExplicit = YES;
    } else if ([arg isEqualToString:@"--lines"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --lines requires a value",
                                  @"Pass the number of lines to show after --lines.",
                                  @"arlen deploy logs --lines 200 --json", 2);
        }
        fprintf(stderr, "arlen deploy: --lines requires a value\n");
        return 2;
      }
      logLines = [[subArgs[++idx] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] integerValue];
      if (logLines <= 0) {
        logLines = 200;
      }
    } else if ([arg isEqualToString:@"--follow"]) {
      followLogs = YES;
    } else if ([arg isEqualToString:@"--file"]) {
      if (idx + 1 >= [subArgs count]) {
        if (asJSON) {
          return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                  @"missing_option_value", @"arlen deploy: --file requires a value",
                                  @"Pass the log file path after --file.",
                                  @"arlen deploy logs --file /var/log/arlen/app.log --json", 2);
        }
        fprintf(stderr, "arlen deploy: --file requires a value\n");
        return 2;
      }
      logFilePath = [ResolvePathFromRoot([[NSFileManager defaultManager] currentDirectoryPath], subArgs[++idx])
                        stringByStandardizingPath];
    } else if ([arg isEqualToString:@"--allow-missing-certification"] ||
               [arg isEqualToString:@"--skip-release-certification"] ||
               [arg isEqualToString:@"--dev"]) {
      allowMissingCertification = YES;
    } else if ([arg isEqualToString:@"--allow-remote-rebuild"]) {
      allowRemoteRebuild = YES;
    } else if ([arg isEqualToString:@"--json"]) {
      asJSON = YES;
    } else if ([arg isEqualToString:@"--skip-migrate"]) {
      skipMigrate = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      PrintDeployUsage();
      return 0;
    } else if (![arg hasPrefix:@"--"] && [targetName length] == 0) {
      targetName = Trimmed(arg);
    } else {
      if (asJSON) {
        return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                @"unknown_option",
                                [NSString stringWithFormat:@"arlen deploy: unknown option %@", arg ?: @""],
                                @"Use `arlen deploy --help` to review supported options.",
                                @"arlen deploy --help", 2);
      }
      fprintf(stderr, "arlen deploy: unknown option %s\n", [arg UTF8String]);
      PrintDeployUsage();
      return 2;
    }
  }

  if ([subcommand isEqualToString:@"list"]) {
    NSString *configPath = nil;
    NSError *targetError = nil;
    NSArray *targets = LoadDeployTargets(appRoot, &configPath, &targetError);
    if (targets == nil) {
      return asJSON ? EmitMachineError(@"deploy", @"deploy.list",
                                       @"deploy_targets_invalid",
                                       targetError.localizedDescription ?: @"failed to load deploy targets",
                                       @"Fix config/deploy.plist and rerun arlen deploy list.",
                                       @"arlen deploy list --json", 1)
                    : 1;
    }
    if (asJSON) {
      NSDictionary *payload = @{
        @"version" : AgentContractVersion(),
        @"command" : @"deploy",
        @"workflow" : @"deploy.list",
        @"subcommand" : @"list",
        @"status" : @"ok",
        @"target_config_path" : configPath ?: @"",
        @"target_count" : @([targets count]),
        @"targets" : DeployTargetPayloads(targets),
      };
      PrintJSONPayload(stdout, payload);
      return 0;
    }
    if ([targets count] == 0) {
      fprintf(stdout, "No deploy targets configured at %s\n", [configPath UTF8String]);
      return 0;
    }
    fprintf(stdout, "Deploy targets from %s\n", [configPath UTF8String]);
    for (NSDictionary *target in targets) {
      NSString *transport = [target[@"remote_enabled"] boolValue] ? @"ssh" : @"local";
      fprintf(stdout, "- %s profile=%s runtime=%s transport=%s releases=%s\n",
              [StringValueForDeployKey(target, @"name") UTF8String],
              [StringValueForDeployKey(target, @"profile") UTF8String],
              [StringValueForDeployKey(target, @"runtime_strategy") UTF8String],
              [transport UTF8String],
              [StringValueForDeployKey(target, @"releases_dir") UTF8String]);
    }
    return 0;
  }

  NSString *resolveError = nil;
  NSString *frameworkRoot = nil;
  if ([frameworkRootOverride length] > 0) {
    frameworkRoot = frameworkRootOverride;
  } else {
    frameworkRoot = ResolveFrameworkRootForCommandDetailed(@"deploy", !asJSON, &resolveError);
  }
  if ([frameworkRoot length] == 0) {
    if (asJSON) {
      return EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                              @"framework_root_unresolved",
                              resolveError ?: @"failed to resolve framework root",
                              @"Set ARLEN_FRAMEWORK_ROOT or pass --framework-root.",
                              @"ARLEN_FRAMEWORK_ROOT=/path/to/Arlen arlen deploy dryrun --json", 1);
    }
    return 1;
  }

  NSDictionary *resolvedTarget = nil;
  BOOL remoteTargetEnabled = NO;
  NSString *remoteReleasesDir = nil;
  if ([targetName length] > 0) {
    NSError *targetError = nil;
    resolvedTarget = LoadDeployTargetNamed(appRoot, targetName, &targetError);
    if (resolvedTarget == nil) {
      return asJSON ? EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand],
                                       @"deploy_target_unresolved",
                                       targetError.localizedDescription ?: @"failed to load deploy target",
                                       @"Add config/deploy.plist with the named target, or pass raw deploy flags instead.",
                                       @"arlen deploy dryrun --target-profile linux-x86_64-gnustep-clang --json", 1)
                    : 1;
    }

    if (!targetProfileExplicit && [StringValueForDeployKey(resolvedTarget, @"profile") length] > 0) {
      targetProfile = StringValueForDeployKey(resolvedTarget, @"profile");
    }
    if (!runtimeStrategyExplicit && [StringValueForDeployKey(resolvedTarget, @"runtime_strategy") length] > 0) {
      runtimeStrategy = StringValueForDeployKey(resolvedTarget, @"runtime_strategy");
    }
    if (!databaseModeExplicit && [StringValueForDeployKey(resolvedTarget, @"database_mode") length] > 0) {
      databaseMode = StringValueForDeployKey(resolvedTarget, @"database_mode");
    }
    if (!databaseAdapterExplicit && [StringValueForDeployKey(resolvedTarget, @"database_adapter") length] > 0) {
      databaseAdapter = StringValueForDeployKey(resolvedTarget, @"database_adapter");
    }
    if (!databaseTargetExplicit && [StringValueForDeployKey(resolvedTarget, @"database_target") length] > 0) {
      databaseTarget = NormalizeDatabaseTarget(StringValueForDeployKey(resolvedTarget, @"database_target"));
    }
    if (!environmentExplicit && [StringValueForDeployKey(resolvedTarget, @"environment") length] > 0) {
      environment = StringValueForDeployKey(resolvedTarget, @"environment");
    }
    if (!baseURLExplicit && [StringValueForDeployKey(resolvedTarget, @"base_url") length] > 0) {
      baseURL = StringValueForDeployKey(resolvedTarget, @"base_url");
    }
    if (!serviceNameExplicit && [StringValueForDeployKey(resolvedTarget, @"service") length] > 0) {
      serviceName = StringValueForDeployKey(resolvedTarget, @"service");
    }
    if (!runtimeActionExplicit && [StringValueForDeployKey(resolvedTarget, @"runtime_action") length] > 0) {
      runtimeAction = StringValueForDeployKey(resolvedTarget, @"runtime_action");
    }
    if (!runtimeRestartCommandExplicit &&
        [StringValueForDeployKey(resolvedTarget, @"runtime_restart_command") length] > 0) {
      runtimeRestartCommand = StringValueForDeployKey(resolvedTarget, @"runtime_restart_command");
    }
    if (!runtimeReloadCommandExplicit &&
        [StringValueForDeployKey(resolvedTarget, @"runtime_reload_command") length] > 0) {
      runtimeReloadCommand = StringValueForDeployKey(resolvedTarget, @"runtime_reload_command");
    }
    if (!healthStartupTimeoutExplicit &&
        [resolvedTarget[@"health_startup_timeout_seconds"] respondsToSelector:@selector(doubleValue)]) {
      healthStartupTimeoutSeconds =
          TimeIntervalValueForDeployKey(resolvedTarget[@"health_startup_timeout_seconds"], healthStartupTimeoutSeconds);
    }
    if (!healthStartupIntervalExplicit &&
        [resolvedTarget[@"health_startup_interval_seconds"] respondsToSelector:@selector(doubleValue)]) {
      healthStartupIntervalSeconds =
          TimeIntervalValueForDeployKey(resolvedTarget[@"health_startup_interval_seconds"], healthStartupIntervalSeconds);
    }

    for (NSString *requiredKey in [resolvedTarget[@"required_environment_keys"] isKindOfClass:[NSArray class]]
                                     ? resolvedTarget[@"required_environment_keys"]
                                     : @[]) {
      if (![requiredEnvironmentKeys containsObject:requiredKey]) {
        [requiredEnvironmentKeys addObject:requiredKey];
      }
    }

    remoteTargetEnabled = [resolvedTarget[@"remote_enabled"] boolValue];
    remoteReleasesDir = StringValueForDeployKey(resolvedTarget, @"releases_dir");
    if (!releasesDirExplicit) {
      releasesDir = remoteTargetEnabled ? StringValueForDeployKey(resolvedTarget, @"local_staging_releases_dir")
                                        : remoteReleasesDir;
    }
  }

  if ([releasesDir length] == 0) {
    releasesDir = [[appRoot stringByAppendingPathComponent:@"releases"] stringByStandardizingPath];
  }
  if ([releaseID length] == 0 &&
      [@[ @"dryrun", @"push", @"release" ] containsObject:subcommand]) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    formatter.dateFormat = @"yyyyMMdd'T'HHmmss'Z'";
    releaseID = [formatter stringFromDate:[NSDate date]];
  }

  if ([runtimeAction length] > 0 &&
      ![@[ @"reload", @"restart", @"none" ] containsObject:runtimeAction]) {
    return asJSON ? EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand], @"invalid_runtime_action",
                                     @"invalid --runtime-action; expected reload, restart, or none",
                                     @"Use reload, restart, or none.",
                                     @"arlen deploy rollback --runtime-action restart --json", 2)
                  : 2;
  }
  if ([runtimeStrategy length] > 0 &&
      ![@[ @"system", @"managed", @"bundled" ] containsObject:runtimeStrategy]) {
    return asJSON ? EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand], @"invalid_runtime_strategy",
                                     @"invalid --runtime-strategy; expected system, managed, or bundled",
                                     @"Use system, managed, or bundled.",
                                     @"arlen deploy dryrun --runtime-strategy managed --json", 2)
                  : 2;
  }
  if ([databaseMode length] > 0 &&
      ![@[ @"external", @"host_local", @"embedded" ] containsObject:databaseMode]) {
    return asJSON ? EmitMachineError(@"deploy", [NSString stringWithFormat:@"deploy.%@", subcommand], @"invalid_database_mode",
                                     @"invalid --database-mode; expected external, host_local, or embedded",
                                     @"Use external, host_local, or embedded.",
                                     @"arlen deploy dryrun --database-mode external --json", 2)
                  : 2;
  }

  if (remoteTargetEnabled && [@[ @"push", @"release" ] containsObject:subcommand]) {
    NSArray<NSString *> *missingInitPaths = nil;
    if (!DeployTargetIsInitialized(resolvedTarget, &missingInitPaths)) {
      if (asJSON) {
        NSDictionary *payload = @{
          @"version" : AgentContractVersion(),
          @"command" : @"deploy",
          @"workflow" : [NSString stringWithFormat:@"deploy.%@", subcommand],
          @"subcommand" : subcommand ?: @"",
          @"status" : @"error",
          @"target" : DeployTargetPayload(resolvedTarget),
          @"missing_paths" : missingInitPaths ?: @[],
          @"error" : @{
            @"code" : @"deploy_target_not_initialized",
            @"message" : @"remote deploy target has not been initialized",
            @"fixit" : @{
              @"action" : @"Run deploy init for the target before remote push or release.",
              @"example" : [NSString stringWithFormat:@"arlen deploy init %@ --json", targetName ?: @"production"],
            }
          },
          @"exit_code" : @1,
        };
        PrintJSONPayload(stdout, payload);
        return 1;
      }
      fprintf(stderr, "arlen deploy: target %s is not initialized; run `arlen deploy init %s` first\n",
              [(targetName ?: @"") UTF8String], [(targetName ?: @"") UTF8String]);
      return 1;
    }
  }

  if ([subcommand isEqualToString:@"init"]) {
    if ([targetName length] == 0 || resolvedTarget == nil) {
      return asJSON ? EmitMachineError(@"deploy", @"deploy.init", @"deploy_init_target_required",
                                       @"arlen deploy init requires a named target from config/deploy.plist",
                                       @"Run `arlen deploy init <target>` for a checked-in deployment target.",
                                       @"arlen deploy init production --json", 2)
                    : 2;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *createdDirectories = [NSMutableArray array];
    NSMutableArray<NSString *> *writtenFiles = [NSMutableArray array];
    NSArray<NSString *> *directories = @[
      StringValueForDeployKey(resolvedTarget, @"release_path"),
      StringValueForDeployKey(resolvedTarget, @"releases_dir"),
      StringValueForDeployKey(resolvedTarget, @"shared_dir"),
      StringValueForDeployKey(resolvedTarget, @"logs_dir"),
      StringValueForDeployKey(resolvedTarget, @"tmp_dir"),
      [StringValueForDeployKey(resolvedTarget, @"generated_dir") stringByAppendingPathComponent:@"bin"],
      [StringValueForDeployKey(resolvedTarget, @"generated_dir") stringByAppendingPathComponent:@"systemd"],
      [StringValueForDeployKey(resolvedTarget, @"generated_dir") stringByAppendingPathComponent:@"env"],
    ];
    for (NSString *directory in directories) {
      if ([directory length] == 0) {
        continue;
      }
      if ([fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL]) {
        [createdDirectories addObject:directory];
      }
    }

    NSString *generatedDir = StringValueForDeployKey(resolvedTarget, @"generated_dir");
    NSString *systemdPath =
        [[generatedDir stringByAppendingPathComponent:@"systemd"] stringByAppendingPathComponent:StringValueForDeployKey(resolvedTarget, @"systemd_unit_filename")];
    NSString *envExamplePath =
        [[[generatedDir stringByAppendingPathComponent:@"env"] stringByAppendingPathComponent:StringValueForDeployKey(resolvedTarget, @"name")] stringByAppendingString:@".env.example"];
    NSString *propaneWrapperPath = StringValueForDeployKey(resolvedTarget, @"propane_wrapper");
    NSString *jobsWorkerWrapperPath = StringValueForDeployKey(resolvedTarget, @"jobs_worker_wrapper");
    NSString *readmePath = [generatedDir stringByAppendingPathComponent:@"README.txt"];

    NSError *writeError = nil;
    if (!WriteTextFile(systemdPath, RenderedSystemdUnitForTarget(resolvedTarget, frameworkRoot), YES, &writeError)) {
      return asJSON ? EmitMachineError(@"deploy", @"deploy.init", @"deploy_init_write_failed",
                                       writeError.localizedDescription ?: @"failed writing generated systemd unit",
                                       @"Verify the target output directory is writable and rerun deploy init.",
                                       @"arlen deploy init production --json", 1)
                    : 1;
    }
    [writtenFiles addObject:systemdPath];
    writeError = nil;
    if (!WriteTextFile(envExamplePath, RenderedEnvExampleForTarget(resolvedTarget, frameworkRoot), YES, &writeError)) {
      return asJSON ? EmitMachineError(@"deploy", @"deploy.init", @"deploy_init_write_failed",
                                       writeError.localizedDescription ?: @"failed writing generated env example",
                                       @"Verify the target output directory is writable and rerun deploy init.",
                                       @"arlen deploy init production --json", 1)
                    : 1;
    }
    [writtenFiles addObject:envExamplePath];
    writeError = nil;
    if (!WriteTextFile(propaneWrapperPath, RenderedGNUstepWrapperForTarget(resolvedTarget, @"propane"), YES, &writeError)) {
      return asJSON ? EmitMachineError(@"deploy", @"deploy.init", @"deploy_init_write_failed",
                                       writeError.localizedDescription ?: @"failed writing propane wrapper",
                                       @"Verify the target output directory is writable and rerun deploy init.",
                                       @"arlen deploy init production --json", 1)
                    : 1;
    }
    SetExecutablePermissions(propaneWrapperPath, NULL);
    [writtenFiles addObject:propaneWrapperPath];
    writeError = nil;
    if (!WriteTextFile(jobsWorkerWrapperPath, RenderedGNUstepWrapperForTarget(resolvedTarget, @"jobs-worker"), YES, &writeError)) {
      return asJSON ? EmitMachineError(@"deploy", @"deploy.init", @"deploy_init_write_failed",
                                       writeError.localizedDescription ?: @"failed writing jobs-worker wrapper",
                                       @"Verify the target output directory is writable and rerun deploy init.",
                                       @"arlen deploy init production --json", 1)
                    : 1;
    }
    SetExecutablePermissions(jobsWorkerWrapperPath, NULL);
    [writtenFiles addObject:jobsWorkerWrapperPath];
    writeError = nil;
    if (!WriteTextFile(readmePath, RenderedInitReadmeForTarget(resolvedTarget), YES, &writeError)) {
      return asJSON ? EmitMachineError(@"deploy", @"deploy.init", @"deploy_init_write_failed",
                                       writeError.localizedDescription ?: @"failed writing deploy init README",
                                       @"Verify the target output directory is writable and rerun deploy init.",
                                       @"arlen deploy init production --json", 1)
                    : 1;
    }
    [writtenFiles addObject:readmePath];

    if (asJSON) {
      NSDictionary *payload = @{
        @"version" : AgentContractVersion(),
        @"command" : @"deploy",
        @"workflow" : @"deploy.init",
        @"subcommand" : @"init",
        @"status" : @"ok",
        @"target" : DeployTargetPayload(resolvedTarget),
        @"created_directories" : createdDirectories ?: @[],
        @"written_files" : writtenFiles ?: @[],
      };
      PrintJSONPayload(stdout, payload);
      return 0;
    }

    fprintf(stdout, "Initialized deploy target %s\n", [targetName UTF8String]);
    fprintf(stdout, "Generated artifacts under %s\n", [generatedDir UTF8String]);
    return 0;
  }

  NSString *workflow = [NSString stringWithFormat:@"deploy.%@", subcommand];
  NSString *scriptRoot = [frameworkRoot stringByAppendingPathComponent:@"tools/deploy"];
  NSString *releaseDir = [releaseID length] > 0 ? [releasesDir stringByAppendingPathComponent:releaseID] : @"";
  NSString *manifestPath =
      [releaseID length] > 0 ? [releaseDir stringByAppendingPathComponent:@"metadata/manifest.json"] : @"";
  NSString *currentReleaseDir = CurrentReleaseDirectoryAtReleasesDir(releasesDir);
  NSString *currentReleaseID = [currentReleaseDir length] > 0 ? ReleaseIDForDirectory(currentReleaseDir) : nil;
  NSString *currentManifestPath =
      [currentReleaseDir length] > 0 ? [currentReleaseDir stringByAppendingPathComponent:@"metadata/manifest.json"] : nil;
  NSDictionary *currentManifest = [currentManifestPath length] > 0 ? (JSONDictionaryFromFile(currentManifestPath) ?: @{}) : @{};
  NSDictionary *currentHealthContract = HealthContractFromManifest(currentManifest);
  NSDictionary *currentMigrationInventory = MigrationInventoryFromManifest(currentManifest);
  NSDictionary *currentDeployment = DeploymentMetadataFromManifest(currentManifest, allowRemoteRebuild);
  NSString *previousReleaseID = PreviousReleaseIDAtReleasesDir(releasesDir, currentReleaseID);
  NSDictionary *requestedDeployment = AssessDeployCompatibility(CurrentDeployPlatformProfile(), targetProfile, allowRemoteRebuild);
  NSError *loadedConfigError = nil;
  NSDictionary *loadedConfig = [ALNConfig loadConfigAtRoot:appRoot
                                               environment:environment ?: @"production"
                                                     error:&loadedConfigError];
  NSArray<NSDictionary *> *multiWorkerStateWarnings =
      Phase39MultiWorkerStateWarnings(loadedConfig, environment, databaseMode, databaseTarget);
  NSDictionary *stateContract = Phase39StateContractFromConfig(loadedConfig ?: @{});

  NSMutableString *buildCommand =
      [NSMutableString stringWithFormat:@"%@/build_release.sh", ShellQuote(scriptRoot)];
  AppendShellOption(buildCommand, @"--app-root", appRoot);
  AppendShellOption(buildCommand, @"--framework-root", frameworkRoot);
  AppendShellOption(buildCommand, @"--releases-dir", releasesDir);
  if ([releaseID length] > 0) {
    AppendShellOption(buildCommand, @"--release-id", releaseID);
  }
  AppendShellOption(buildCommand, @"--certification-manifest", certificationManifest);
  AppendShellOption(buildCommand, @"--json-performance-manifest", jsonPerformanceManifest);
  AppendShellOption(buildCommand, @"--target-profile", [requestedDeployment[@"target_profile"] isKindOfClass:[NSString class]] ? requestedDeployment[@"target_profile"] : targetProfile);
  AppendShellOption(buildCommand, @"--runtime-strategy", runtimeStrategy);
  AppendShellOption(buildCommand, @"--database-mode", databaseMode);
  AppendShellOption(buildCommand, @"--database-adapter", databaseAdapter);
  AppendShellOption(buildCommand, @"--database-target", databaseTarget);
  for (NSString *requiredKey in requiredEnvironmentKeys) {
    AppendShellOption(buildCommand, @"--require-env-key", requiredKey);
  }
  if (allowMissingCertification) {
    [buildCommand appendString:@" --allow-missing-certification"];
  }
  if (allowRemoteRebuild) {
    [buildCommand appendString:@" --allow-remote-rebuild"];
  }

  if (remoteTargetEnabled && ![subcommand isEqualToString:@"dryrun"] && ![subcommand isEqualToString:@"releases"]) {
    NSDictionary *localBuildPayload = nil;
    if ([subcommand isEqualToString:@"push"] || [subcommand isEqualToString:@"release"]) {
      BOOL releaseDirIsDirectory = NO;
      BOOL stagedReleaseExists = [subcommand isEqualToString:@"release"] &&
                                 [releaseDir length] > 0 &&
                                 PathExists(releaseDir, &releaseDirIsDirectory) &&
                                 releaseDirIsDirectory;
      if (stagedReleaseExists) {
        localBuildPayload = @{
          @"status" : @"reused",
          @"release_id" : releaseID ?: @"",
          @"release_dir" : releaseDir ?: @"",
        };
      } else {
        NSMutableString *pushCommand = [buildCommand mutableCopy];
        [pushCommand appendString:asJSON ? @" --json" : @""];
        int pushExitCode = 0;
        NSString *pushOutput = RunShellCaptureCommand(pushCommand, &pushExitCode);
        if (pushExitCode != 0) {
          if (asJSON) {
            NSDictionary *payload = JSONDictionaryFromString(pushOutput);
            if (payload != nil) {
              NSMutableDictionary *wrapped = [payload mutableCopy];
              wrapped[@"target"] = DeployTargetPayload(resolvedTarget);
              PrintJSONPayload(stdout, wrapped);
              return pushExitCode;
            }
            return EmitMachineError(@"deploy", workflow, @"deploy_target_push_failed",
                                    @"failed to build the local release artifact for the named target",
                                    @"Inspect the underlying deploy push failure and rerun after the local artifact builds cleanly.",
                                    @"arlen deploy push production --json", pushExitCode ?: 1);
          }
          if ([pushOutput length] > 0) {
            fprintf(stderr, "%s", [pushOutput UTF8String]);
          }
          return pushExitCode ?: 1;
        }
        if (asJSON) {
          localBuildPayload = JSONDictionaryFromString(pushOutput) ?: @{};
        }
      }
    }

    NSDictionary *transportStep = nil;
    if ([subcommand isEqualToString:@"push"] || [subcommand isEqualToString:@"release"]) {
      transportStep = UploadReleaseToRemoteTarget(resolvedTarget, releasesDir, releaseID);
      if (![[transportStep[@"status"] description] isEqualToString:@"ok"]) {
        if (asJSON) {
          NSDictionary *payload = @{
            @"version" : AgentContractVersion(),
            @"command" : @"deploy",
            @"workflow" : workflow,
            @"subcommand" : subcommand,
            @"status" : @"error",
            @"target" : DeployTargetPayload(resolvedTarget),
            @"release_id" : releaseID ?: @"",
            @"local_releases_dir" : releasesDir ?: @"",
            @"remote_releases_dir" : remoteReleasesDir ?: @"",
            @"transport" : transportStep ?: @{},
            @"build_release" : localBuildPayload ?: @{},
            @"error" : @{
              @"code" : @"deploy_target_transport_failed",
              @"message" : @"failed to upload the prepared release artifact to the remote target",
              @"fixit" : @{
                @"action" : @"Verify SSH access, remote path permissions, and retry the target deploy.",
                @"example" : @"arlen deploy push production --json",
              }
            },
            @"exit_code" : @([transportStep[@"exit_code"] integerValue] > 0 ? [transportStep[@"exit_code"] integerValue] : 1),
          };
          PrintJSONPayload(stdout, payload);
        }
        return ([transportStep[@"exit_code"] integerValue] > 0) ? [transportStep[@"exit_code"] integerValue] : 1;
      }

      if ([subcommand isEqualToString:@"push"]) {
        NSDictionary *manifest = JSONDictionaryFromFile(manifestPath) ?: @{};
        if (asJSON) {
          NSDictionary *payload = @{
            @"version" : AgentContractVersion(),
            @"command" : @"deploy",
            @"workflow" : workflow,
            @"subcommand" : subcommand,
            @"status" : @"ok",
            @"target" : DeployTargetPayload(resolvedTarget),
            @"release_id" : releaseID ?: @"",
            @"local_releases_dir" : releasesDir ?: @"",
            @"remote_releases_dir" : remoteReleasesDir ?: @"",
            @"remote_release_dir" : transportStep[@"remote_release_dir"] ?: @"",
            @"manifest_path" : manifestPath ?: @"",
            @"manifest_version" : manifest[@"version"] ?: @"phase32-deploy-manifest-v1",
            @"deployment" : DeploymentMetadataFromManifest(manifest, allowRemoteRebuild),
            @"propane_handoff" : PropaneHandoffFromManifest(manifest, releaseDir),
            @"state" : Phase39StateContractFromConfig(loadedConfig ?: @{}),
            @"warnings" : multiWorkerStateWarnings ?: @[],
            @"transport" : transportStep ?: @{},
            @"manifest" : manifest ?: @{},
            @"build_release" : localBuildPayload ?: @{},
          };
          PrintJSONPayload(stdout, payload);
          return 0;
        }
        fprintf(stdout, "Uploaded release %s to %s\n", [releaseID UTF8String], [remoteReleasesDir UTF8String]);
        return 0;
      }
    }

    NSString *remoteBaseDir =
        ([subcommand isEqualToString:@"release"] && [releaseID length] > 0)
            ? [remoteReleasesDir stringByAppendingPathComponent:releaseID]
            : [remoteReleasesDir stringByAppendingPathComponent:@"current"];
    NSString *remoteAppRoot = [remoteBaseDir stringByAppendingPathComponent:@"app"];
    NSString *remoteFrameworkRoot = [remoteBaseDir stringByAppendingPathComponent:@"framework"];
    NSString *remoteBinary = [remoteFrameworkRoot stringByAppendingPathComponent:@"build/arlen"];

    NSMutableString *remoteDelegate =
        [NSMutableString stringWithFormat:@"set -euo pipefail && if [ ! -x %@ ]; then echo 'remote packaged arlen missing at %@' >&2; exit 1; fi && cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ deploy %@",
                                           ShellQuote(remoteBinary), remoteBinary, ShellQuote(remoteAppRoot),
                                           ShellQuote(remoteFrameworkRoot), ShellQuote(remoteBinary),
                                           subcommand];
    AppendShellOption(remoteDelegate, @"--app-root", remoteAppRoot);
    AppendShellOption(remoteDelegate, @"--releases-dir", remoteReleasesDir);
    if ([subcommand isEqualToString:@"release"] && [releaseID length] > 0) {
      AppendShellOption(remoteDelegate, @"--release-id", releaseID);
      AppendShellOption(remoteDelegate, @"--env", environment);
      if (skipMigrate) {
        [remoteDelegate appendString:@" --skip-migrate"];
      }
    }
    if ([serviceName length] > 0) {
      AppendShellOption(remoteDelegate, @"--service", serviceName);
    }
    if ([runtimeAction length] > 0 &&
        [@[ @"release", @"rollback" ] containsObject:subcommand]) {
      AppendShellOption(remoteDelegate, @"--runtime-action", runtimeAction);
    }
    if ([runtimeRestartCommand length] > 0 &&
        [@[ @"release", @"rollback" ] containsObject:subcommand]) {
      AppendShellOption(remoteDelegate, @"--runtime-restart-command", runtimeRestartCommand);
    }
    if ([runtimeReloadCommand length] > 0 &&
        [@[ @"release", @"rollback" ] containsObject:subcommand]) {
      AppendShellOption(remoteDelegate, @"--runtime-reload-command", runtimeReloadCommand);
    }
    if ([subcommand isEqualToString:@"release"]) {
      AppendShellOption(remoteDelegate, @"--health-startup-timeout",
                        [NSString stringWithFormat:@"%.3f", healthStartupTimeoutSeconds]);
      AppendShellOption(remoteDelegate, @"--health-startup-interval",
                        [NSString stringWithFormat:@"%.3f", healthStartupIntervalSeconds]);
    }
    if ([baseURL length] > 0 &&
        [@[ @"release", @"status", @"doctor", @"rollback" ] containsObject:subcommand]) {
      AppendShellOption(remoteDelegate, @"--base-url", baseURL);
    }
    if ([remoteBuildCheckCommand length] > 0 &&
        [@[ @"release", @"doctor" ] containsObject:subcommand]) {
      AppendShellOption(remoteDelegate, @"--remote-build-check-command", remoteBuildCheckCommand);
    }
    if ([subcommand isEqualToString:@"logs"]) {
      if (logLines > 0) {
        AppendShellOption(remoteDelegate, @"--lines", [NSString stringWithFormat:@"%ld", (long)logLines]);
      }
      if (followLogs) {
        [remoteDelegate appendString:@" --follow"];
      }
      if ([logFilePath length] > 0) {
        AppendShellOption(remoteDelegate, @"--file", logFilePath);
      }
    }
    if (asJSON) {
      [remoteDelegate appendString:@" --json"];
    }

    NSDictionary *remoteResult = RunSSHCommandForTarget(resolvedTarget, remoteDelegate);
    if (asJSON) {
      NSDictionary *remotePayload = JSONDictionaryFromString(remoteResult[@"captured_output"]);
      if ([remotePayload isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *wrapped = [remotePayload mutableCopy];
        wrapped[@"target"] = DeployTargetPayload(resolvedTarget);
        if (transportStep != nil) {
          wrapped[@"transport"] = transportStep;
        }
        PrintJSONPayload(stdout, wrapped);
        return [remoteResult[@"exit_code"] integerValue];
      }

      NSDictionary *payload = @{
        @"version" : AgentContractVersion(),
        @"command" : @"deploy",
        @"workflow" : workflow,
        @"subcommand" : subcommand,
        @"status" : ([remoteResult[@"exit_code"] integerValue] == 0) ? @"ok" : @"error",
        @"target" : DeployTargetPayload(resolvedTarget),
        @"release_id" : releaseID ?: @"",
        @"remote_releases_dir" : remoteReleasesDir ?: @"",
        @"transport" : transportStep ?: @{},
        @"remote_execution" : remoteResult ?: @{},
        @"exit_code" : @([remoteResult[@"exit_code"] integerValue]),
      };
      PrintJSONPayload(stdout, payload);
      return [remoteResult[@"exit_code"] integerValue];
    }

    if ([remoteResult[@"captured_output"] length] > 0) {
      fprintf(([remoteResult[@"exit_code"] integerValue] == 0) ? stdout : stderr, "%s",
              [remoteResult[@"captured_output"] UTF8String]);
    }
    return [remoteResult[@"exit_code"] integerValue];
  }

  if ([subcommand isEqualToString:@"dryrun"]) {
    NSMutableString *dryrunCommand = [buildCommand mutableCopy];
    [dryrunCommand appendString:@" --dry-run"];
    if (asJSON) {
      [dryrunCommand appendString:@" --json"];
      int exitCode = 0;
      NSString *capturedOutput = RunShellCaptureCommand(dryrunCommand, &exitCode);
      NSDictionary *buildPayload = JSONDictionaryFromString(capturedOutput);
      if (exitCode != 0 || buildPayload == nil) {
        return EmitMachineError(@"deploy", workflow, @"deploy_dryrun_failed",
                                @"arlen deploy dryrun failed",
                                @"Inspect the underlying build_release output and fix the first reported issue.",
                                @"arlen deploy dryrun --json --skip-release-certification", exitCode ?: 1);
      }
      NSMutableDictionary *payload = [@{
        @"version" : AgentContractVersion(),
        @"command" : @"deploy",
        @"workflow" : workflow,
        @"subcommand" : subcommand,
        @"status" : @"planned",
        @"target" : DeployTargetPayload(resolvedTarget),
        @"app_root" : appRoot ?: @"",
        @"framework_root" : frameworkRoot ?: @"",
        @"releases_dir" : releasesDir ?: @"",
        @"release_id" : releaseID ?: @"",
        @"release_dir" : releaseDir ?: @"",
        @"manifest_path" : manifestPath ?: @"",
        @"manifest_version" : @"phase32-deploy-manifest-v1",
        @"deployment" : requestedDeployment ?: @{},
        @"state" : stateContract ?: @{},
        @"warnings" : multiWorkerStateWarnings ?: @[],
        @"build_release" : buildPayload ?: @{},
      } mutableCopy];
      if (usedPlanAlias) {
        payload[@"deprecated_alias"] = @"plan";
      }
      PrintJSONPayload(stdout, payload);
      return 0;
    }

    if (usedPlanAlias) {
      fprintf(stderr, "arlen deploy plan is deprecated; use arlen deploy dryrun instead.\n");
    }
    PrintDeployWarnings(multiWorkerStateWarnings);
    return RunShellCommand(dryrunCommand);
  }

  if ([subcommand isEqualToString:@"releases"]) {
    NSArray *releaseItems = @[];
    NSString *inventorySource = remoteTargetEnabled ? @"remote" : @"local";
    NSDictionary *remoteExecution = @{};
    NSString *activeReleaseID = currentReleaseID ?: @"";
    NSString *priorReleaseID = previousReleaseID ?: @"";
    if (remoteTargetEnabled) {
      NSDictionary *remoteInventory = RemoteReleaseInventory(resolvedTarget);
      remoteExecution = remoteInventory[@"remote_execution"] ?: @{};
      if (![[remoteInventory[@"status"] description] isEqualToString:@"ok"]) {
        if (asJSON) {
          NSDictionary *payload = @{
            @"version" : AgentContractVersion(),
            @"command" : @"deploy",
            @"workflow" : workflow,
            @"subcommand" : subcommand,
            @"status" : @"error",
            @"target" : DeployTargetPayload(resolvedTarget),
            @"source" : inventorySource,
            @"remote_releases_dir" : remoteReleasesDir ?: @"",
            @"remote_execution" : remoteExecution ?: @{},
            @"error" : @{
              @"code" : @"deploy_releases_remote_failed",
              @"message" : @"failed to list remote releases for the target",
              @"fixit" : @{
                @"action" : @"Verify SSH access and the target release path.",
                @"example" : @"arlen deploy releases production --json",
              }
            },
          };
          PrintJSONPayload(stdout, payload);
        }
        return [remoteExecution[@"exit_code"] integerValue] > 0 ? [remoteExecution[@"exit_code"] integerValue] : 1;
      }
      releaseItems = [remoteInventory[@"releases"] isKindOfClass:[NSArray class]] ? remoteInventory[@"releases"] : @[];
      activeReleaseID = @"";
      for (NSDictionary *item in releaseItems) {
        if ([[item[@"state"] description] isEqualToString:@"active"]) {
          activeReleaseID = [item[@"id"] description];
          break;
        }
      }
      priorReleaseID = @"";
    } else {
      releaseItems = LocalReleaseInventory(releasesDir, currentReleaseID, previousReleaseID, allowRemoteRebuild);
    }

    if (asJSON) {
      NSDictionary *payload = @{
        @"version" : AgentContractVersion(),
        @"command" : @"deploy",
        @"workflow" : workflow,
        @"subcommand" : subcommand,
        @"status" : @"ok",
        @"target" : DeployTargetPayload(resolvedTarget),
        @"source" : inventorySource,
        @"releases_dir" : releasesDir ?: @"",
        @"remote_releases_dir" : remoteReleasesDir ?: @"",
        @"active_release_id" : activeReleaseID ?: @"",
        @"previous_release_id" : priorReleaseID ?: @"",
        @"release_count" : @([releaseItems count]),
        @"releases" : releaseItems ?: @[],
        @"remote_execution" : remoteExecution ?: @{},
      };
      PrintJSONPayload(stdout, payload);
      return 0;
    }

    fprintf(stdout, "Available releases (%s): %lu\n", [inventorySource UTF8String], (unsigned long)[releaseItems count]);
    for (NSDictionary *item in releaseItems) {
      fprintf(stdout, "- %s [%s] %s\n",
              [[item[@"id"] description] UTF8String],
              [[item[@"state"] description] UTF8String],
              [[item[@"path"] description] UTF8String]);
    }
    return 0;
  }

  if ([subcommand isEqualToString:@"push"]) {
    if (!asJSON) {
      PrintDeployWarnings(multiWorkerStateWarnings);
    }
    if (asJSON) {
      NSMutableString *pushCommand = [buildCommand mutableCopy];
      [pushCommand appendString:@" --json"];
      int exitCode = 0;
      NSString *capturedOutput = RunShellCaptureCommand(pushCommand, &exitCode);
      NSDictionary *buildPayload = JSONDictionaryFromString(capturedOutput);
      if (exitCode != 0 || buildPayload == nil) {
        return EmitMachineError(@"deploy", workflow, @"deploy_push_failed",
                                @"arlen deploy push failed",
                                @"Inspect the underlying build_release output and fix the first reported issue.",
                                @"arlen deploy push --json --skip-release-certification", exitCode ?: 1);
      }
      NSDictionary *manifest = JSONDictionaryFromFile(manifestPath) ?: @{};
      NSDictionary *payload = @{
        @"version" : AgentContractVersion(),
        @"command" : @"deploy",
        @"workflow" : workflow,
        @"subcommand" : subcommand,
        @"status" : @"ok",
        @"target" : DeployTargetPayload(resolvedTarget),
        @"app_root" : appRoot ?: @"",
        @"framework_root" : frameworkRoot ?: @"",
        @"releases_dir" : releasesDir ?: @"",
        @"release_id" : releaseID ?: @"",
        @"release_dir" : releaseDir ?: @"",
        @"manifest_path" : manifestPath ?: @"",
        @"manifest_version" : manifest[@"version"] ?: @"phase32-deploy-manifest-v1",
        @"deployment" : DeploymentMetadataFromManifest(manifest, allowRemoteRebuild),
        @"propane_handoff" : PropaneHandoffFromManifest(manifest, releaseDir),
        @"state" : stateContract ?: @{},
        @"warnings" : multiWorkerStateWarnings ?: @[],
        @"manifest" : manifest,
        @"build_release" : buildPayload ?: @{},
      };
      PrintJSONPayload(stdout, payload);
      return 0;
    }

    return RunShellCommand(buildCommand);
  }

  if ([subcommand isEqualToString:@"status"]) {
    NSString *serviceOutput = nil;
    NSString *serviceState = ServiceRuntimeState(serviceName, &serviceOutput);
    NSDictionary *currentPaths = ResolvedManifestPathsForRelease(currentManifest, currentReleaseDir);
    NSString *previousReleaseDir = [previousReleaseID length] > 0 ? [releasesDir stringByAppendingPathComponent:previousReleaseID] : nil;
    NSString *previousManifestPath =
        [previousReleaseDir length] > 0 ? [previousReleaseDir stringByAppendingPathComponent:@"metadata/manifest.json"] : nil;
    NSDictionary *previousManifest = [previousManifestPath length] > 0 ? (JSONDictionaryFromFile(previousManifestPath) ?: @{}) : @{};
    NSString *currentProbeHelper =
        [currentPaths[@"operability_probe_helper"] isKindOfClass:[NSString class]] ? currentPaths[@"operability_probe_helper"] : nil;
    NSString *probeFrameworkRoot = [currentReleaseDir length] > 0 ? [[currentReleaseDir stringByAppendingPathComponent:@"framework"] stringByStandardizingPath]
                                                                  : frameworkRoot;
    NSDictionary *healthProbe = [baseURL length] > 0 ? RunDeployHealthProbe(probeFrameworkRoot, currentProbeHelper, baseURL)
                                                     : @{ @"status" : @"skipped", @"reason" : @"base_url_not_provided" };
    if (asJSON) {
      NSDictionary *payload = @{
        @"version" : AgentContractVersion(),
        @"command" : @"deploy",
        @"workflow" : workflow,
        @"subcommand" : subcommand,
        @"status" : ([currentReleaseDir length] > 0) ? @"ok" : @"warn",
        @"releases_dir" : releasesDir ?: @"",
        @"active_release_id" : currentReleaseID ?: @"",
        @"active_release_dir" : currentReleaseDir ?: @"",
        @"previous_release_id" : previousReleaseID ?: @"",
        @"previous_release_dir" : previousReleaseDir ?: @"",
        @"manifest_path" : currentManifestPath ?: @"",
        @"manifest" : currentManifest ?: @{},
        @"deployment" : currentDeployment ?: @{},
        @"propane_handoff" : PropaneHandoffFromManifest(currentManifest, currentReleaseDir),
        @"health_contract" : currentHealthContract ?: @{},
        @"migration_inventory" : currentMigrationInventory ?: @{},
        @"rollback_candidate" : @{
          @"release_id" : previousReleaseID ?: @"",
          @"release_dir" : previousReleaseDir ?: @"",
          @"manifest_path" : previousManifestPath ?: @"",
          @"deployment" : DeploymentMetadataFromManifest(previousManifest, NO),
          @"propane_handoff" : PropaneHandoffFromManifest(previousManifest, previousReleaseDir),
        },
        @"service" : @{
          @"name" : serviceName ?: @"",
          @"state" : serviceState ?: @"not_requested",
          @"detail" : serviceOutput ?: @"",
        },
        @"health_probe" : healthProbe ?: @{},
      };
      PrintJSONPayload(stdout, payload);
      return ([currentReleaseDir length] > 0) ? 0 : 1;
    }

    fprintf(stdout, "Active release: %s\n", [(currentReleaseID ?: @"(none)") UTF8String]);
    fprintf(stdout, "Previous release: %s\n", [(previousReleaseID ?: @"(none)") UTF8String]);
    fprintf(stdout, "Release dir: %s\n", [(currentReleaseDir ?: @"(none)") UTF8String]);
    fprintf(stdout, "Profile: %s -> %s\n",
            [([currentDeployment[@"local_profile"] description] ?: @"(unknown)") UTF8String],
            [([currentDeployment[@"target_profile"] description] ?: @"(unknown)") UTF8String]);
    fprintf(stdout, "Service state: %s\n", [(serviceState ?: @"not_requested") UTF8String]);
    fprintf(stdout, "Migration count: %s\n",
            [(([[currentMigrationInventory[@"count"] description] length] > 0)
                   ? [currentMigrationInventory[@"count"] description]
                   : @"0") UTF8String]);
    if ([baseURL length] > 0) {
      fprintf(stdout, "Health probe: %s\n", [([healthProbe[@"status"] description] ?: @"error") UTF8String]);
    }
    return ([currentReleaseDir length] > 0) ? 0 : 1;
  }

  if ([subcommand isEqualToString:@"rollback"]) {
    NSString *rollbackTargetID = [releaseID length] > 0 ? releaseID : previousReleaseID;
    if ([rollbackTargetID length] == 0) {
      return asJSON ? EmitMachineError(@"deploy", workflow, @"rollback_target_missing",
                                       @"no rollback target is available",
                                       @"Build at least two releases or pass --release-id explicitly.",
                                       @"arlen deploy rollback --release-id rel-previous --json", 1)
                    : 1;
    }

    NSMutableArray *warnings = [NSMutableArray array];
    if ([currentMigrationInventory[@"count"] respondsToSelector:@selector(integerValue)] &&
        [currentMigrationInventory[@"count"] integerValue] > 0) {
      [warnings addObject:@"active release packages migrations; Arlen cannot determine whether they are reversible"];
    }

    NSString *rollbackCommand =
        [NSString stringWithFormat:@"%@/rollback_release.sh --releases-dir %@ --release-id %@",
                                   ShellQuote(scriptRoot), ShellQuote(releasesDir), ShellQuote(rollbackTargetID)];
    int rollbackExitCode = 0;
    NSString *rollbackOutput = RunShellCaptureCommand(rollbackCommand, &rollbackExitCode);
    if (rollbackExitCode != 0) {
      if (!asJSON && [rollbackOutput length] > 0) {
        fprintf(stderr, "%s", [rollbackOutput UTF8String]);
      }
      return asJSON ? EmitMachineError(@"deploy", workflow, @"deploy_rollback_failed",
                                       @"rollback activation failed",
                                       @"Inspect the rollback_release output and verify the target release exists.",
                                       @"arlen deploy rollback --release-id rel-previous --json", rollbackExitCode)
                    : rollbackExitCode;
    }

    NSMutableArray *steps = [NSMutableArray array];
    [steps addObject:@{ @"id" : @"rollback", @"status" : @"ok", @"target_release_id" : rollbackTargetID ?: @"" }];

    NSString *runtimeState = @"not_requested";
    NSString *runtimeDetail = @"";
    NSString *runtimeActionUsed = @"none";
    if ([serviceName length] > 0 && ![runtimeAction isEqualToString:@"none"]) {
      NSString *systemctlVerb = [runtimeAction isEqualToString:@"restart"] ? @"restart" : @"reload";
      NSString *runtimeCommand = RuntimeCommandForAction(systemctlVerb, serviceName, runtimeRestartCommand, runtimeReloadCommand);
      int runtimeExitCode = 0;
      NSString *runtimeOutput = RunShellCaptureCommand(runtimeCommand, &runtimeExitCode);
      if (runtimeExitCode != 0 && [runtimeAction isEqualToString:@"reload"]) {
        runtimeCommand = RuntimeCommandForAction(@"restart", serviceName, runtimeRestartCommand, runtimeReloadCommand);
        runtimeOutput = RunShellCaptureCommand(runtimeCommand, &runtimeExitCode);
        if (runtimeExitCode == 0) {
          systemctlVerb = @"restart";
        }
      }
      runtimeActionUsed = systemctlVerb;
      runtimeDetail = runtimeOutput ?: @"";
      runtimeState = (runtimeExitCode == 0) ? @"ok" : @"error";
      [steps addObject:@{
        @"id" : @"runtime",
        @"status" : runtimeState,
        @"action" : runtimeActionUsed ?: @"",
        @"service" : serviceName ?: @"",
        @"captured_output" : runtimeDetail ?: @"",
      }];
      if (runtimeExitCode != 0) {
        if (!asJSON && [runtimeDetail length] > 0) {
          fprintf(stderr, "%s", [runtimeDetail UTF8String]);
        }
        if (asJSON) {
          NSDictionary *payload = @{
            @"version" : AgentContractVersion(),
            @"command" : @"deploy",
            @"workflow" : workflow,
            @"subcommand" : subcommand,
            @"status" : @"error",
            @"target_release_id" : rollbackTargetID ?: @"",
            @"steps" : steps ?: @[],
            @"warnings" : warnings ?: @[],
            @"error" : @{
              @"code" : @"deploy_rollback_runtime_failed",
              @"message" : @"rollback switched releases but runtime reload/restart failed",
              @"fixit" : @{
                @"action" : @"Inspect service logs and rerun with --runtime-action restart if needed.",
                @"example" : @"arlen deploy rollback --service arlen@myapp --runtime-action restart --json",
              }
            },
            @"exit_code" : @(runtimeExitCode),
          };
          PrintJSONPayload(stdout, payload);
        }
        return runtimeExitCode;
      }
    } else {
      [steps addObject:@{
        @"id" : @"runtime",
        @"status" : @"skipped",
        @"action" : @"none",
      }];
    }

    NSString *activeDirAfterRollback = CurrentReleaseDirectoryAtReleasesDir(releasesDir);
    NSDictionary *activeManifestAfterRollback =
        [activeDirAfterRollback length] > 0
            ? (JSONDictionaryFromFile([activeDirAfterRollback stringByAppendingPathComponent:@"metadata/manifest.json"]) ?: @{})
            : @{};
    NSDictionary *activeDeploymentAfterRollback = DeploymentMetadataFromManifest(activeManifestAfterRollback, NO);
    NSDictionary *activePathsAfterRollback =
        ResolvedManifestPathsForRelease(activeManifestAfterRollback, activeDirAfterRollback);
    NSString *probeHelperAfterRollback =
        [activePathsAfterRollback[@"operability_probe_helper"] isKindOfClass:[NSString class]]
            ? activePathsAfterRollback[@"operability_probe_helper"]
            : nil;
    NSString *probeFrameworkRootAfterRollback =
        [activeDirAfterRollback length] > 0 ? [[activeDirAfterRollback stringByAppendingPathComponent:@"framework"] stringByStandardizingPath]
                                            : frameworkRoot;
    NSDictionary *healthProbe = [baseURL length] > 0
                                    ? RunDeployHealthProbe(probeFrameworkRootAfterRollback, probeHelperAfterRollback, baseURL)
                                    : @{ @"status" : @"skipped", @"reason" : @"base_url_not_provided" };
    [steps addObject:@{
      @"id" : @"health",
      @"status" : healthProbe[@"status"] ?: @"skipped",
      @"base_url" : baseURL ?: @"",
      @"captured_output" : healthProbe[@"captured_output"] ?: @"",
    }];
    if ([[healthProbe[@"status"] description] isEqualToString:@"error"]) {
      if (asJSON) {
        NSDictionary *payload = @{
          @"version" : AgentContractVersion(),
          @"command" : @"deploy",
          @"workflow" : workflow,
          @"subcommand" : subcommand,
          @"status" : @"error",
          @"target_release_id" : rollbackTargetID ?: @"",
          @"steps" : steps ?: @[],
          @"warnings" : warnings ?: @[],
          @"error" : @{
            @"code" : @"deploy_rollback_health_failed",
            @"message" : @"rollback completed but health validation failed",
            @"fixit" : @{
              @"action" : @"Inspect runtime logs and verify the rollback target responds on the expected base URL.",
              @"example" : @"arlen deploy logs --service arlen@myapp",
            }
          },
          @"exit_code" : @([healthProbe[@"exit_code"] integerValue] == 0 ? 1 : [healthProbe[@"exit_code"] integerValue]),
        };
        PrintJSONPayload(stdout, payload);
      }
      return ([healthProbe[@"exit_code"] integerValue] == 0) ? 1 : [healthProbe[@"exit_code"] integerValue];
    }
    if (asJSON) {
      NSDictionary *payload = @{
        @"version" : AgentContractVersion(),
        @"command" : @"deploy",
        @"workflow" : workflow,
        @"subcommand" : subcommand,
        @"status" : @"ok",
        @"target_release_id" : rollbackTargetID ?: @"",
        @"active_release_id" : [activeDirAfterRollback length] > 0 ? ReleaseIDForDirectory(activeDirAfterRollback) : @"",
        @"active_release_dir" : activeDirAfterRollback ?: @"",
        @"deployment" : activeDeploymentAfterRollback ?: @{},
        @"propane_handoff" : PropaneHandoffFromManifest(activeManifestAfterRollback, activeDirAfterRollback),
        @"rollback_source" : @{
          @"release_id" : currentReleaseID ?: @"",
          @"release_dir" : currentReleaseDir ?: @"",
          @"deployment" : currentDeployment ?: @{},
          @"propane_handoff" : PropaneHandoffFromManifest(currentManifest, currentReleaseDir),
        },
        @"manifest" : activeManifestAfterRollback ?: @{},
        @"warnings" : warnings ?: @[],
        @"steps" : steps ?: @[],
      };
      PrintJSONPayload(stdout, payload);
      return 0;
    }

    fprintf(stdout, "Rollback activated: %s\n", [rollbackTargetID UTF8String]);
    return 0;
  }

  if ([subcommand isEqualToString:@"doctor"]) {
    NSInteger passCount = 0;
    NSInteger warnCount = 0;
    NSInteger failCount = 0;
    NSMutableArray *checks = [NSMutableArray array];
    BOOL currentReleaseIsDirectory = NO;
    BOOL currentReleaseLooksUsable =
        ([currentReleaseDir length] > 0 && PathExists(currentReleaseDir, &currentReleaseIsDirectory) &&
         currentReleaseIsDirectory &&
         PathExists([currentReleaseDir stringByAppendingPathComponent:@"metadata/manifest.json"], NULL));
    if (currentReleaseLooksUsable) {
      NSInteger releasePass = 0;
      NSInteger releaseWarn = 0;
      NSInteger releaseFail = 0;
      NSArray *releaseChecks = DeployDoctorChecksForRelease(currentReleaseDir, environment, serviceName, baseURL,
                                                            remoteBuildCheckCommand,
                                                            &releasePass, &releaseWarn, &releaseFail);
      [checks addObjectsFromArray:releaseChecks ?: @[]];
      passCount += releasePass;
      warnCount += releaseWarn;
      failCount += releaseFail;
    }
    if (resolvedTarget != nil && !remoteTargetEnabled) {
      NSInteger targetPass = 0;
      NSInteger targetWarn = 0;
      NSInteger targetFail = 0;
      NSArray *targetChecks = DeployDoctorChecksForTargetHost(resolvedTarget, &targetPass, &targetWarn, &targetFail);
      [checks addObjectsFromArray:targetChecks ?: @[]];
      passCount += targetPass;
      warnCount += targetWarn;
      failCount += targetFail;
    }
    if ([checks count] == 0) {
      [checks addObject:@{
        @"id" : @"release_dir",
        @"status" : @"fail",
        @"message" : @"active release directory is missing",
        @"hint" : @"Build or activate a release before running deploy doctor, or pass a named target for host-readiness checks.",
      }];
      failCount += 1;
    }
    NSString *status = (failCount > 0) ? @"fail" : (warnCount > 0 ? @"warn" : @"ok");
    if (asJSON) {
      NSDictionary *payload = @{
        @"version" : AgentContractVersion(),
        @"command" : @"deploy",
        @"workflow" : workflow,
        @"subcommand" : subcommand,
        @"status" : status,
        @"active_release_id" : currentReleaseID ?: @"",
        @"active_release_dir" : currentReleaseDir ?: @"",
        @"environment" : environment ?: @"production",
        @"deployment" : currentDeployment ?: @{},
        @"propane_handoff" : PropaneHandoffFromManifest(currentManifest, currentReleaseDir),
        @"target" : DeployTargetPayload(resolvedTarget),
        @"checks" : checks ?: @[],
        @"summary" : @{
          @"pass" : @(passCount),
          @"warn" : @(warnCount),
          @"fail" : @(failCount),
        },
      };
      PrintJSONPayload(stdout, payload);
      return (failCount > 0) ? 1 : 0;
    }

    fprintf(stdout, "Deploy doctor status: %s\n", [status UTF8String]);
    for (NSDictionary *check in checks) {
      fprintf(stdout, "[%s] %s\n", [[check[@"status"] description] UTF8String],
              [[check[@"message"] description] UTF8String]);
    }
    return (failCount > 0) ? 1 : 0;
  }

  if ([subcommand isEqualToString:@"logs"]) {
    NSDictionary *releaseEnv = [currentReleaseDir length] > 0
                                   ? DictionaryFromReleaseEnvFile([currentReleaseDir stringByAppendingPathComponent:@"metadata/release.env"])
                                   : @{};
    NSString *lifecycleLog = [releaseEnv[@"ARLEN_PROPANE_LIFECYCLE_LOG"] isKindOfClass:[NSString class]]
                                 ? releaseEnv[@"ARLEN_PROPANE_LIFECYCLE_LOG"]
                                 : @"";
    if ([serviceName length] > 0) {
      NSString *journalCommand = [NSString stringWithFormat:@"journalctl -u %@ -n %ld --no-pager%@",
                                                          ShellQuote(serviceName), (long)logLines,
                                                          followLogs ? @" --follow" : @""];
      if (asJSON) {
        int exitCode = 0;
        NSString *capturedOutput = RunShellCaptureCommand(journalCommand, &exitCode);
        NSDictionary *payload = @{
          @"version" : AgentContractVersion(),
          @"command" : @"deploy",
          @"workflow" : workflow,
          @"subcommand" : subcommand,
          @"status" : (exitCode == 0) ? @"ok" : @"error",
          @"active_release_id" : currentReleaseID ?: @"",
          @"active_release_dir" : currentReleaseDir ?: @"",
          @"service" : serviceName ?: @"",
          @"log_source" : @"journald",
          @"manifest_path" : currentManifestPath ?: @"",
          @"lifecycle_log_path" : lifecycleLog ?: @"",
          @"captured_output" : capturedOutput ?: @"",
          @"exit_code" : @(exitCode),
        };
        PrintJSONPayload(stdout, payload);
        return exitCode;
      }
      return RunShellCommand(journalCommand);
    }

    if ([logFilePath length] > 0) {
      NSString *tailCommand = [NSString stringWithFormat:@"tail -n %ld %@%@",
                                                       (long)logLines, followLogs ? @"-f " : @"",
                                                       ShellQuote(logFilePath)];
      if (asJSON) {
        int exitCode = 0;
        NSString *capturedOutput = RunShellCaptureCommand(tailCommand, &exitCode);
        NSDictionary *payload = @{
          @"version" : AgentContractVersion(),
          @"command" : @"deploy",
          @"workflow" : workflow,
          @"subcommand" : subcommand,
          @"status" : (exitCode == 0) ? @"ok" : @"error",
          @"active_release_id" : currentReleaseID ?: @"",
          @"active_release_dir" : currentReleaseDir ?: @"",
          @"log_source" : @"file",
          @"log_file" : logFilePath ?: @"",
          @"manifest_path" : currentManifestPath ?: @"",
          @"lifecycle_log_path" : lifecycleLog ?: @"",
          @"captured_output" : capturedOutput ?: @"",
          @"exit_code" : @(exitCode),
        };
        PrintJSONPayload(stdout, payload);
        return exitCode;
      }
      return RunShellCommand(tailCommand);
    }

    NSDictionary *payload = @{
      @"version" : AgentContractVersion(),
      @"command" : @"deploy",
      @"workflow" : workflow,
      @"subcommand" : subcommand,
      @"status" : ([currentReleaseDir length] > 0) ? @"ok" : @"warn",
      @"active_release_id" : currentReleaseID ?: @"",
      @"active_release_dir" : currentReleaseDir ?: @"",
      @"manifest_path" : currentManifestPath ?: @"",
      @"release_readme_path" : [currentReleaseDir length] > 0 ? [currentReleaseDir stringByAppendingPathComponent:@"metadata/README.txt"] : @"",
      @"release_env_path" : [currentReleaseDir length] > 0 ? [currentReleaseDir stringByAppendingPathComponent:@"metadata/release.env"] : @"",
      @"lifecycle_log_path" : lifecycleLog ?: @"",
      @"service" : serviceName ?: @"",
    };
    if (asJSON) {
      PrintJSONPayload(stdout, payload);
      return ([currentReleaseDir length] > 0) ? 0 : 1;
    }
    fprintf(stdout, "Active release: %s\n", [(currentReleaseID ?: @"(none)") UTF8String]);
    fprintf(stdout, "Manifest: %s\n", [[payload[@"manifest_path"] description] UTF8String]);
    fprintf(stdout, "Release README: %s\n", [[payload[@"release_readme_path"] description] UTF8String]);
    fprintf(stdout, "Release env: %s\n", [[payload[@"release_env_path"] description] UTF8String]);
    if ([lifecycleLog length] > 0) {
      fprintf(stdout, "Lifecycle log: %s\n", [lifecycleLog UTF8String]);
    }
    return ([currentReleaseDir length] > 0) ? 0 : 1;
  }

  BOOL releaseExists = NO;
  BOOL isDirectory = NO;
  if (PathExists(releaseDir, &isDirectory) && isDirectory) {
    releaseExists = YES;
  }

  if (!asJSON) {
    PrintDeployWarnings(multiWorkerStateWarnings);
  }

  NSMutableArray *steps = [NSMutableArray array];
  NSDictionary *buildPayload = nil;
  int buildExitCode = 0;
  if (!releaseExists) {
    NSMutableString *pushCommand = [buildCommand mutableCopy];
    [pushCommand appendString:@" --json"];
    NSString *capturedOutput = RunShellCaptureCommand(pushCommand, &buildExitCode);
    buildPayload = JSONDictionaryFromString(capturedOutput);
    if (buildExitCode != 0 || buildPayload == nil) {
      if (!asJSON && [capturedOutput length] > 0) {
        fprintf(stderr, "%s", [capturedOutput UTF8String]);
      }
      return asJSON ? EmitMachineError(@"deploy", workflow, @"deploy_release_push_failed",
                                       @"failed to build release artifact during deploy release",
                                       @"Inspect the build_release failure and rerun after the artifact builds cleanly.",
                                       @"arlen deploy push --json --skip-release-certification", buildExitCode ?: 1)
                    : buildExitCode ?: 1;
    }
    [steps addObject:@{
      @"id" : @"push",
      @"status" : @"ok",
      @"release_id" : releaseID ?: @"",
    }];
  } else {
    [steps addObject:@{
      @"id" : @"push",
      @"status" : @"reused",
      @"release_id" : releaseID ?: @"",
    }];
  }

  NSString *releaseAppRoot = [releaseDir stringByAppendingPathComponent:@"app"];
  NSString *releaseFrameworkRoot = [releaseDir stringByAppendingPathComponent:@"framework"];
  NSDictionary *releaseMetadata = LoadReleaseMetadataAtDirectory(releaseDir);
  NSDictionary *releaseManifest =
      [releaseMetadata[@"manifest"] isKindOfClass:[NSDictionary class]] ? releaseMetadata[@"manifest"] : @{};
  NSDictionary *releaseDeployment = DeploymentMetadataFromManifest(releaseManifest, allowRemoteRebuild);
  NSDictionary *releasePaths = ResolvedManifestPathsForRelease(releaseManifest, releaseDir);
  NSString *releaseSupportLevel =
      [releaseDeployment[@"support_level"] isKindOfClass:[NSString class]] ? releaseDeployment[@"support_level"] : @"supported";
  NSString *releaseCompatibilityReason =
      [releaseDeployment[@"compatibility_reason"] isKindOfClass:[NSString class]] ? releaseDeployment[@"compatibility_reason"] : @"same_profile";
  if ([releaseSupportLevel isEqualToString:@"unsupported"]) {
    if (asJSON) {
      NSDictionary *payload = @{
        @"version" : AgentContractVersion(),
        @"command" : @"deploy",
        @"workflow" : workflow,
        @"subcommand" : subcommand,
        @"status" : @"error",
        @"release_id" : releaseID ?: @"",
        @"release_dir" : releaseDir ?: @"",
        @"deployment" : releaseDeployment ?: @{},
        @"steps" : [steps arrayByAddingObject:@{
          @"id" : @"compatibility",
          @"status" : @"error",
          @"support_level" : releaseSupportLevel ?: @"unsupported",
          @"reason" : releaseCompatibilityReason ?: @"",
        }],
        @"error" : @{
          @"code" : @"deploy_release_unsupported_target",
          @"message" : @"deployment target is outside the supported compatibility contract",
          @"fixit" : @{
            @"action" : @"Deploy to the same platform profile, or opt into a supported GNUstep remote rebuild path.",
            @"example" : @"arlen deploy release --target-profile linux-x86_64-gnustep-clang --json",
          }
        },
        @"exit_code" : @1,
      };
      PrintJSONPayload(stdout, payload);
    }
    return 1;
  }
  if ([releaseSupportLevel isEqualToString:@"experimental"]) {
    NSDictionary *remoteBuildCheck = RunRemoteBuildCheck(remoteBuildCheckCommand);
    if (![[remoteBuildCheck[@"status"] description] isEqualToString:@"ok"]) {
      if (asJSON) {
        NSDictionary *payload = @{
          @"version" : AgentContractVersion(),
          @"command" : @"deploy",
          @"workflow" : workflow,
          @"subcommand" : subcommand,
          @"status" : @"error",
          @"release_id" : releaseID ?: @"",
          @"release_dir" : releaseDir ?: @"",
          @"deployment" : releaseDeployment ?: @{},
          @"steps" : [steps arrayByAddingObject:@{
            @"id" : @"remote_build_check",
            @"status" : @"error",
            @"captured_output" : remoteBuildCheck[@"captured_output"] ?: @"",
          }],
          @"error" : @{
            @"code" : @"deploy_release_remote_build_check_failed",
            @"message" : @"experimental remote rebuild target requires a successful build-chain validation command",
            @"fixit" : @{
              @"action" : @"Pass --remote-build-check-command and verify it can compile/link on the target host.",
              @"example" : @"arlen deploy release --allow-remote-rebuild --remote-build-check-command 'ssh host true' --json",
            }
          },
          @"exit_code" : @([remoteBuildCheck[@"exit_code"] integerValue] > 0 ? [remoteBuildCheck[@"exit_code"] integerValue] : 1),
        };
        PrintJSONPayload(stdout, payload);
      }
      return ([remoteBuildCheck[@"exit_code"] integerValue] > 0) ? [remoteBuildCheck[@"exit_code"] integerValue] : 1;
    }
    [steps addObject:@{
      @"id" : @"remote_build_check",
      @"status" : @"ok",
      @"support_level" : releaseSupportLevel ?: @"experimental",
    }];
  } else {
    [steps addObject:@{
      @"id" : @"compatibility",
      @"status" : @"ok",
      @"support_level" : releaseSupportLevel ?: @"supported",
    }];
  }
  NSString *releaseBinary =
      ([releasePaths[@"arlen"] isKindOfClass:[NSString class]] ? ResolveExecutablePath(releasePaths[@"arlen"]) : nil);
  if ([releaseBinary length] == 0) {
    releaseBinary = ResolveExecutablePath([releaseFrameworkRoot stringByAppendingPathComponent:@"build/arlen"]);
  }
  if ([releaseBinary length] == 0) {
    releaseBinary = [releaseFrameworkRoot stringByAppendingPathComponent:@"build/arlen"];
  }
  BOOL shouldMigrate = !skipMigrate && DirectoryContainsSQLFiles([releaseAppRoot stringByAppendingPathComponent:@"db/migrations"]);
  if (shouldMigrate) {
    NSString *migrateCommand = [NSString
        stringWithFormat:@"cd %@ && ARLEN_APP_ROOT=%@ ARLEN_FRAMEWORK_ROOT=%@ %@ migrate --env %@",
                         ShellQuote(releaseAppRoot), ShellQuote(releaseAppRoot),
                         ShellQuote(releaseFrameworkRoot), ShellQuote(releaseBinary),
                         ShellQuote(environment ?: @"production")];
    int migrateExitCode = 0;
    NSString *migrateOutput = RunShellCaptureCommand(migrateCommand, &migrateExitCode);
    if (migrateExitCode != 0) {
      if (!asJSON && [migrateOutput length] > 0) {
        fprintf(stderr, "%s", [migrateOutput UTF8String]);
      }
      if (asJSON) {
        NSDictionary *payload = @{
          @"version" : AgentContractVersion(),
          @"command" : @"deploy",
          @"workflow" : workflow,
          @"subcommand" : subcommand,
          @"status" : @"error",
          @"release_id" : releaseID ?: @"",
          @"release_dir" : releaseDir ?: @"",
          @"steps" : [steps arrayByAddingObject:@{
            @"id" : @"migrate",
            @"status" : @"error",
            @"captured_output" : migrateOutput ?: @"",
          }],
          @"error" : @{
            @"code" : @"deploy_release_migrate_failed",
            @"message" : @"release activation stopped because migrations failed",
            @"fixit" : @{
              @"action" : @"Repair the migration/config failure and rerun the release step.",
              @"example" : @"arlen deploy release --skip-migrate --json",
            }
          },
          @"exit_code" : @(migrateExitCode),
        };
        PrintJSONPayload(stdout, payload);
      }
      return migrateExitCode;
    }
    [steps addObject:@{
      @"id" : @"migrate",
      @"status" : @"ok",
      @"environment" : environment ?: @"production",
    }];
  } else {
    [steps addObject:@{
      @"id" : @"migrate",
      @"status" : skipMigrate ? @"skipped" : @"not_needed",
      @"environment" : environment ?: @"production",
    }];
  }

  NSString *activateCommand =
      [NSString stringWithFormat:@"%@/activate_release.sh --releases-dir %@ --release-id %@",
                                 ShellQuote(scriptRoot), ShellQuote(releasesDir), ShellQuote(releaseID)];
  int activateExitCode = 0;
  NSString *activateOutput = RunShellCaptureCommand(activateCommand, &activateExitCode);
  if (activateExitCode != 0) {
    if (!asJSON && [activateOutput length] > 0) {
      fprintf(stderr, "%s", [activateOutput UTF8String]);
    }
    if (asJSON) {
      NSDictionary *payload = @{
        @"version" : AgentContractVersion(),
        @"command" : @"deploy",
        @"workflow" : workflow,
        @"subcommand" : subcommand,
        @"status" : @"error",
        @"release_id" : releaseID ?: @"",
        @"release_dir" : releaseDir ?: @"",
        @"steps" : [steps arrayByAddingObject:@{
          @"id" : @"activate",
          @"status" : @"error",
          @"captured_output" : activateOutput ?: @"",
        }],
        @"error" : @{
          @"code" : @"deploy_release_activate_failed",
          @"message" : @"release activation failed",
          @"fixit" : @{
            @"action" : @"Inspect the releases directory and activation script output.",
            @"example" : @"tools/deploy/activate_release.sh --releases-dir /path/to/releases --release-id rel-1",
          }
        },
        @"exit_code" : @(activateExitCode),
      };
      PrintJSONPayload(stdout, payload);
    }
    return activateExitCode;
  }
  [steps addObject:@{
    @"id" : @"activate",
    @"status" : @"ok",
    @"current_path" : [releasesDir stringByAppendingPathComponent:@"current"],
  }];

  if ([serviceName length] > 0 && ![runtimeAction isEqualToString:@"none"]) {
    NSString *systemctlVerb = [runtimeAction isEqualToString:@"restart"] ? @"restart" : @"reload";
    NSString *runtimeCommand = RuntimeCommandForAction(systemctlVerb, serviceName, runtimeRestartCommand, runtimeReloadCommand);
    int runtimeExitCode = 0;
    NSString *runtimeOutput = RunShellCaptureCommand(runtimeCommand, &runtimeExitCode);
    if (runtimeExitCode != 0 && [runtimeAction isEqualToString:@"reload"]) {
      runtimeCommand = RuntimeCommandForAction(@"restart", serviceName, runtimeRestartCommand, runtimeReloadCommand);
      runtimeOutput = RunShellCaptureCommand(runtimeCommand, &runtimeExitCode);
      if (runtimeExitCode == 0) {
        systemctlVerb = @"restart";
      }
    }
    [steps addObject:@{
      @"id" : @"runtime",
      @"status" : (runtimeExitCode == 0) ? @"ok" : @"error",
      @"action" : systemctlVerb ?: @"",
      @"service" : serviceName ?: @"",
      @"captured_output" : runtimeOutput ?: @"",
    }];
    if (runtimeExitCode != 0) {
      NSString *rollbackActivationID = [currentReleaseID length] > 0 ? currentReleaseID : nil;
      int rollbackActivationExitCode = 0;
      NSString *rollbackActivationOutput = @"";
      NSString *deploymentState = @"stale_runtime";
      NSString *activeReleaseIDAfterFailure = releaseID ?: @"";
      if ([rollbackActivationID length] > 0) {
        NSString *rollbackActivationCommand =
            [NSString stringWithFormat:@"%@/activate_release.sh --releases-dir %@ --release-id %@",
                                       ShellQuote(scriptRoot), ShellQuote(releasesDir), ShellQuote(rollbackActivationID)];
        rollbackActivationOutput = RunShellCaptureCommand(rollbackActivationCommand, &rollbackActivationExitCode);
        deploymentState = (rollbackActivationExitCode == 0) ? @"activation_failed" : @"stale_runtime";
        activeReleaseIDAfterFailure = (rollbackActivationExitCode == 0) ? rollbackActivationID : (releaseID ?: @"");
        [steps addObject:@{
          @"id" : @"rollback_current",
          @"status" : (rollbackActivationExitCode == 0) ? @"ok" : @"error",
          @"target_release_id" : rollbackActivationID ?: @"",
          @"captured_output" : rollbackActivationOutput ?: @"",
        }];
      } else {
        [steps addObject:@{
          @"id" : @"rollback_current",
          @"status" : @"skipped",
          @"reason" : @"no_previous_active_release",
        }];
      }
      if (!asJSON && [runtimeOutput length] > 0) {
        fprintf(stderr, "%s", [runtimeOutput UTF8String]);
      }
      if (!asJSON) {
        if ([deploymentState isEqualToString:@"activation_failed"]) {
          fprintf(stderr, "arlen deploy release: runtime action failed; restored current to %s\n",
                  [activeReleaseIDAfterFailure UTF8String]);
        } else {
          fprintf(stderr, "arlen deploy release: runtime action failed after current changed; deployment_state=stale_runtime\n");
        }
      }
      if (asJSON) {
        NSDictionary *payload = @{
          @"version" : AgentContractVersion(),
          @"command" : @"deploy",
          @"workflow" : workflow,
          @"subcommand" : subcommand,
          @"status" : @"error",
          @"deployment_state" : deploymentState ?: @"stale_runtime",
          @"release_id" : releaseID ?: @"",
          @"release_dir" : releaseDir ?: @"",
          @"target_release_id" : releaseID ?: @"",
          @"active_release_id" : activeReleaseIDAfterFailure ?: @"",
          @"deployment" : releaseDeployment ?: @{},
          @"steps" : steps ?: @[],
          @"error" : @{
            @"code" : @"deploy_release_runtime_failed",
            @"message" : [deploymentState isEqualToString:@"activation_failed"]
                ? @"runtime reload/restart failed; current was restored to the previous release"
                : @"runtime reload/restart failed after current changed; runtime may be stale",
            @"fixit" : @{
              @"action" : @"Configure non-interactive runtime permissions or pass --runtime-restart-command with sudo -n.",
              @"example" : @"arlen deploy release --service arlen@myapp --runtime-action restart --runtime-restart-command 'sudo -n systemctl restart arlen@myapp' --json",
            }
          },
          @"exit_code" : @(runtimeExitCode),
        };
        PrintJSONPayload(stdout, payload);
      }
      return runtimeExitCode;
    }
  } else {
    [steps addObject:@{
      @"id" : @"runtime",
      @"status" : @"skipped",
      @"action" : @"none",
    }];
  }

  if ([baseURL length] > 0) {
    NSDictionary *healthProbe =
        RunReleaseHealthProbeWithRetry(baseURL, healthStartupTimeoutSeconds, healthStartupIntervalSeconds);
    NSString *healthStatus = [healthProbe[@"status"] isKindOfClass:[NSString class]] ? healthProbe[@"status"] : @"error";
    if (![healthStatus isEqualToString:@"ok"]) {
      NSString *serviceOutput = nil;
      NSString *serviceState = [serviceName length] > 0 ? ServiceRuntimeState(serviceName, &serviceOutput) : @"not_requested";
      if (asJSON) {
        NSDictionary *payload = @{
          @"version" : AgentContractVersion(),
          @"command" : @"deploy",
          @"workflow" : workflow,
          @"subcommand" : subcommand,
          @"status" : @"error",
          @"deployment_state" : @"activated_health_unverified",
          @"release_id" : releaseID ?: @"",
          @"release_dir" : releaseDir ?: @"",
          @"service" : serviceName ?: @"",
          @"service_state" : serviceState ?: @"",
          @"service_state_output" : serviceOutput ?: @"",
          @"steps" : [steps arrayByAddingObject:@{
            @"id" : @"health",
            @"status" : @"error",
            @"base_url" : baseURL ?: @"",
            @"captured_output" : healthProbe[@"captured_output"] ?: @"",
            @"attempts" : healthProbe[@"attempts"] ?: @0,
            @"timeout_seconds" : healthProbe[@"timeout_seconds"] ?: @(healthStartupTimeoutSeconds),
            @"interval_seconds" : healthProbe[@"interval_seconds"] ?: @(healthStartupIntervalSeconds),
          }],
          @"error" : @{
            @"code" : @"deploy_release_health_failed",
            @"message" : @"release activation and runtime action completed but health verification timed out",
            @"fixit" : @{
              @"action" : @"Run deploy status/doctor/logs; increase --health-startup-timeout if the service needs a longer normal startup window.",
              @"example" : @"arlen deploy status --json && arlen deploy doctor --json",
            }
          },
          @"exit_code" : @([healthProbe[@"exit_code"] integerValue] == 0 ? 1 : [healthProbe[@"exit_code"] integerValue]),
        };
        PrintJSONPayload(stdout, payload);
      }
      if (!asJSON && [healthProbe[@"captured_output"] isKindOfClass:[NSString class]] &&
          [healthProbe[@"captured_output"] length] > 0) {
        fprintf(stderr, "%s", [healthProbe[@"captured_output"] UTF8String]);
      }
      return ([healthProbe[@"exit_code"] integerValue] == 0) ? 1 : [healthProbe[@"exit_code"] intValue];
    }
    [steps addObject:@{
      @"id" : @"health",
      @"status" : @"ok",
      @"base_url" : baseURL ?: @"",
      @"health_path" : @"/healthz",
      @"attempts" : healthProbe[@"attempts"] ?: @0,
      @"timeout_seconds" : healthProbe[@"timeout_seconds"] ?: @(healthStartupTimeoutSeconds),
      @"interval_seconds" : healthProbe[@"interval_seconds"] ?: @(healthStartupIntervalSeconds),
    }];
  } else {
    [steps addObject:@{
      @"id" : @"health",
      @"status" : @"skipped",
      @"reason" : @"base_url_not_provided",
    }];
  }

  NSDictionary *manifest = JSONDictionaryFromFile(manifestPath) ?: @{};
  if (asJSON) {
    NSDictionary *payload = @{
      @"version" : AgentContractVersion(),
      @"command" : @"deploy",
      @"workflow" : workflow,
      @"subcommand" : subcommand,
      @"status" : @"ok",
      @"environment" : environment ?: @"production",
      @"release_id" : releaseID ?: @"",
      @"release_dir" : releaseDir ?: @"",
      @"releases_dir" : releasesDir ?: @"",
      @"manifest_path" : manifestPath ?: @"",
      @"manifest_version" : manifest[@"version"] ?: @"phase32-deploy-manifest-v1",
      @"deployment" : releaseDeployment ?: @{},
      @"propane_handoff" : PropaneHandoffFromManifest(manifest, releaseDir),
      @"state" : Phase39StateContractFromConfig(loadedConfig ?: @{}),
      @"warnings" : multiWorkerStateWarnings ?: @[],
      @"manifest" : manifest,
      @"steps" : steps ?: @[],
      @"build_release" : buildPayload ?: @{},
    };
    PrintJSONPayload(stdout, payload);
    return 0;
  }

  fprintf(stdout, "release activated: %s\n", [releaseDir UTF8String]);
  return 0;
}

static int RunMakeWorkflowCommand(NSString *commandName, NSString *makeTarget, NSArray *args) {
  BOOL asJSON = NO;
  BOOL dryRun = NO;
  for (NSUInteger idx = 0; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--json"]) {
      asJSON = YES;
    } else if ([arg isEqualToString:@"--dry-run"]) {
      dryRun = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      if ([commandName isEqualToString:@"build"]) {
        PrintBuildUsage();
      } else {
        PrintCheckUsage();
      }
      return 0;
    } else {
      if (asJSON) {
        return EmitMachineError(commandName, commandName, @"unknown_option",
                                [NSString stringWithFormat:@"arlen %@: unknown option %@", commandName ?: @"",
                                                           arg ?: @""],
                                @"Use only --dry-run and --json for this command.",
                                [NSString stringWithFormat:@"arlen %@ --dry-run --json", commandName ?: @""], 2);
      }
      fprintf(stderr, "arlen %s: unknown option %s\n", [commandName UTF8String], [arg UTF8String]);
      if ([commandName isEqualToString:@"build"]) {
        PrintBuildUsage();
      } else {
        PrintCheckUsage();
      }
      return 2;
    }
  }

  NSString *resolveError = nil;
  NSString *frameworkRoot = ResolveFrameworkRootForCommandDetailed(commandName, !asJSON, &resolveError);
  if ([frameworkRoot length] == 0) {
    if (asJSON) {
      NSString *example = [NSString stringWithFormat:@"ARLEN_FRAMEWORK_ROOT=/path/to/Arlen arlen %@ --dry-run --json",
                                                     commandName ?: @""];
      return EmitMachineError(commandName, commandName, @"framework_root_unresolved",
                              resolveError ?: @"failed to resolve framework root",
                              @"Set ARLEN_FRAMEWORK_ROOT or run inside an Arlen checkout/app.",
                              example, 1);
    }
    return 1;
  }

  NSString *shellCommand =
      [NSString stringWithFormat:@"cd %@ && make %@", ShellQuote(frameworkRoot), makeTarget ?: @""];

  if (dryRun) {
    if (asJSON) {
      NSDictionary *payload = @{
        @"version" : AgentContractVersion(),
        @"command" : commandName ?: @"",
        @"workflow" : commandName ?: @"",
        @"status" : @"planned",
        @"framework_root" : frameworkRoot ?: @"",
        @"make_target" : makeTarget ?: @"",
        @"shell_command" : shellCommand ?: @"",
      };
      PrintJSONPayload(stdout, payload);
      return 0;
    }
    fprintf(stdout, "arlen %s dry-run: %s\n", [commandName UTF8String], [shellCommand UTF8String]);
    return 0;
  }

  if (!asJSON) {
    return RunShellCommand(shellCommand);
  }

  int exitCode = 0;
  NSString *capturedOutput = RunShellCaptureCommand(shellCommand, &exitCode);
  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"version"] = AgentContractVersion();
  payload[@"command"] = commandName ?: @"";
  payload[@"workflow"] = commandName ?: @"";
  payload[@"status"] = (exitCode == 0) ? @"ok" : @"error";
  payload[@"framework_root"] = frameworkRoot ?: @"";
  payload[@"make_target"] = makeTarget ?: @"";
  payload[@"shell_command"] = shellCommand ?: @"";
  payload[@"exit_code"] = @(exitCode);
  payload[@"captured_output"] = capturedOutput ?: @"";
  if (exitCode != 0) {
    payload[@"error"] = @{
      @"code" : @"make_failed",
      @"message" : [NSString stringWithFormat:@"`make %@` failed", makeTarget ?: @""],
      @"fixit" : @{
        @"action" : @"Inspect captured_output and repair the first failing target before rerunning.",
        @"example" : [NSString stringWithFormat:@"arlen %@ --json", commandName ?: @""],
      }
    };
  }
  PrintJSONPayload(stdout, payload);
  return exitCode;
}

static int CommandBuild(NSArray *args) {
  return RunMakeWorkflowCommand(@"build", @"all", args ?: @[]);
}

static int CommandCheck(NSArray *args) {
  return RunMakeWorkflowCommand(@"check", @"check", args ?: @[]);
}

static void AddDoctorCheck(NSMutableArray *checks,
                           NSString *checkID,
                           NSString *status,
                           NSString *message,
                           NSString *hint) {
  [checks addObject:@{
    @"id" : checkID ?: @"",
    @"status" : status ?: @"warn",
    @"message" : message ?: @"",
    @"hint" : hint ?: @"",
  }];
}

static int CommandDoctor(NSArray *args) {
  NSString *environment = @"development";
  BOOL asJSON = NO;
  for (NSUInteger idx = 0; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--env"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen doctor: --env requires a value\n");
        return 2;
      }
      environment = args[++idx];
    } else if ([arg isEqualToString:@"--json"]) {
      asJSON = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      fprintf(stdout, "Usage: arlen doctor [--env <name>] [--json]\n");
      return 0;
    } else {
      fprintf(stderr, "arlen doctor: unknown option %s\n", [arg UTF8String]);
      return 2;
    }
  }

  NSString *appRoot = [[[NSFileManager defaultManager] currentDirectoryPath] stringByStandardizingPath];
  NSString *frameworkRoot = nil;
  NSString *frameworkOverride = EnvValue("ARLEN_FRAMEWORK_ROOT");
  BOOL overrideInvalid = NO;
  if ([frameworkOverride length] > 0) {
    NSString *candidate = [frameworkOverride hasPrefix:@"/"]
                              ? [frameworkOverride stringByStandardizingPath]
                              : [[appRoot stringByAppendingPathComponent:frameworkOverride]
                                    stringByStandardizingPath];
    if (IsFrameworkRoot(candidate)) {
      frameworkRoot = candidate;
    } else {
      overrideInvalid = YES;
    }
  } else {
    frameworkRoot = FindFrameworkRoot(appRoot);
    if ([frameworkRoot length] == 0) {
      frameworkRoot = FrameworkRootFromExecutablePath();
    }
  }

  NSMutableArray *checks = [NSMutableArray array];
  NSInteger passCount = 0;
  NSInteger warnCount = 0;
  NSInteger failCount = 0;

  if (overrideInvalid) {
    AddDoctorCheck(checks,
                   @"framework_root",
                   @"fail",
                   [NSString stringWithFormat:@"ARLEN_FRAMEWORK_ROOT is not a valid framework root: %@",
                                              frameworkOverride ?: @""],
                   @"Unset ARLEN_FRAMEWORK_ROOT or point it at an Arlen checkout or packaged release framework root.");
    failCount += 1;
  } else if ([frameworkRoot length] > 0) {
    AddDoctorCheck(checks,
                   @"framework_root",
                   @"pass",
                   [NSString stringWithFormat:@"framework root: %@", frameworkRoot],
                   @"");
    passCount += 1;
  } else {
    AddDoctorCheck(checks,
                   @"framework_root",
                   @"fail",
                   @"could not resolve framework root",
                   @"Set ARLEN_FRAMEWORK_ROOT or run from inside an Arlen checkout/app/release.");
    failCount += 1;
  }

  NSString *appConfigPath = [appRoot stringByAppendingPathComponent:@"config/app.plist"];
  if (PathExists(appConfigPath, NULL)) {
    AddDoctorCheck(checks,
                   @"app_root",
                   @"pass",
                   [NSString stringWithFormat:@"app config found: %@", appConfigPath],
                   @"");
    passCount += 1;
  } else {
    AddDoctorCheck(checks,
                   @"app_root",
                   @"warn",
                   [NSString stringWithFormat:@"app config not found at %@", appConfigPath],
                   @"Run `arlen new <AppName>` in this directory if you are creating a new app.");
    warnCount += 1;
  }

  NSString *gnustepScript = ResolveGNUstepScriptPath();
  if (PathExists(gnustepScript, NULL)) {
    AddDoctorCheck(checks, @"gnustep_script", @"pass",
                   [NSString stringWithFormat:@"GNUstep script present: %@", gnustepScript], @"");
    passCount += 1;
  } else {
    AddDoctorCheck(checks, @"gnustep_script", @"fail",
                   [NSString stringWithFormat:@"missing GNUstep script: %@", gnustepScript],
                   @"Set GNUSTEP_SH, export GNUSTEP_MAKEFILES, or source your toolchain env script before running Arlen.");
    failCount += 1;
  }

  NSArray *requiredTools = @[ @"clang", @"make", @"bash" ];
  for (NSString *tool in requiredTools) {
    int code = 0;
    NSString *path =
        Trimmed(RunShellCaptureCommand([NSString stringWithFormat:@"command -v %@ 2>/dev/null", tool], &code));
    if (code == 0 && [path length] > 0) {
      AddDoctorCheck(checks,
                     [NSString stringWithFormat:@"tool_%@", tool],
                     @"pass",
                     [NSString stringWithFormat:@"%@ found at %@", tool, path],
                     @"");
      passCount += 1;
    } else {
      AddDoctorCheck(checks,
                     [NSString stringWithFormat:@"tool_%@", tool],
                     @"fail",
                     [NSString stringWithFormat:@"%@ not found on PATH", tool],
                     @"Install toolchain prerequisites and ensure PATH is configured.");
      failCount += 1;
    }
  }

  NSArray *recommendedTools = @[ @"xctest", @"python3", @"curl" ];
  for (NSString *tool in recommendedTools) {
    int code = 0;
    NSString *path =
        Trimmed(RunShellCaptureCommand([NSString stringWithFormat:@"command -v %@ 2>/dev/null", tool], &code));
    if (code == 0 && [path length] > 0) {
      AddDoctorCheck(checks,
                     [NSString stringWithFormat:@"tool_%@", tool],
                     @"pass",
                     [NSString stringWithFormat:@"%@ found at %@", tool, path],
                     @"");
      passCount += 1;
    } else {
      AddDoctorCheck(checks,
                     [NSString stringWithFormat:@"tool_%@", tool],
                     @"warn",
                     [NSString stringWithFormat:@"%@ not found on PATH", tool],
                     [tool isEqualToString:@"xctest"] ? @"Install Debian package `tools-xctest` to run tests."
                                                       : @"Install recommended developer tooling for full workflows.");
      warnCount += 1;
    }
  }

  if (PathExists(gnustepScript, NULL)) {
    int gnustepCode = 0;
    NSString *flagsOutput =
        Trimmed(RunShellCaptureCommand([NSString stringWithFormat:@"set +u; source %@ >/dev/null 2>&1; set -u; gnustep-config --objc-flags",
                                                                ShellQuote(gnustepScript)],
                                       &gnustepCode));
    if (gnustepCode == 0 && [flagsOutput length] > 0) {
      AddDoctorCheck(checks, @"gnustep_config", @"pass", @"gnustep-config responded successfully", @"");
      passCount += 1;
    } else {
      AddDoctorCheck(checks,
                     @"gnustep_config",
                     @"fail",
                     @"failed running gnustep-config after sourcing GNUstep.sh",
                     @"Verify your active GNUstep environment and gnustep-config availability.");
      failCount += 1;
    }

    int dispatchHeaderCode = 0;
    RunShellCaptureCommand([NSString
                               stringWithFormat:@"set +u; source %@ >/dev/null 2>&1; set -u; printf '#import <dispatch/dispatch.h>\\n' | clang $(gnustep-config --objc-flags) -x objective-c -fsyntax-only - >/dev/null 2>&1",
                                                ShellQuote(gnustepScript)],
                           &dispatchHeaderCode);
    if (dispatchHeaderCode == 0) {
      AddDoctorCheck(checks, @"dispatch_headers", @"pass", @"dispatch/dispatch.h is available to clang", @"");
      passCount += 1;
    } else {
      AddDoctorCheck(checks,
                     @"dispatch_headers",
                     @"fail",
                     @"dispatch/dispatch.h is missing from the active toolchain include paths",
                     @"Install libdispatch development headers/runtime support or use a GNUstep toolchain that exposes dispatch headers.");
      failCount += 1;
    }
  }

  int libpqCode = 0;
  NSString *libpqLine =
      Trimmed(RunShellCaptureCommand(@"ldconfig -p 2>/dev/null | grep -m1 'libpq\\.so'", &libpqCode));
  if (libpqCode == 0 && [libpqLine length] > 0) {
    AddDoctorCheck(checks, @"libpq", @"pass", [NSString stringWithFormat:@"libpq available: %@", libpqLine], @"");
    passCount += 1;
  } else {
    AddDoctorCheck(checks,
                   @"libpq",
                   @"warn",
                   @"libpq not detected via ldconfig",
                   @"Install PostgreSQL client libraries (`libpq`) for ALNPg and schema-codegen workflows.");
    warnCount += 1;
  }

  int odbcCode = 0;
  NSString *odbcLine =
      Trimmed(RunShellCaptureCommand(@"ldconfig -p 2>/dev/null | grep -m1 'libodbc\\.so'", &odbcCode));
  if (odbcCode == 0 && [odbcLine length] > 0) {
    AddDoctorCheck(checks, @"libodbc", @"pass", [NSString stringWithFormat:@"ODBC manager available: %@", odbcLine], @"");
    passCount += 1;
  } else {
    AddDoctorCheck(checks,
                   @"libodbc",
                   @"warn",
                   @"ODBC manager not detected via ldconfig",
                   @"Install unixODBC or iODBC plus a SQL Server driver to enable the optional MSSQL adapter.");
    warnCount += 1;
  }

  if (PathExists(appConfigPath, NULL)) {
    NSError *configError = nil;
    NSDictionary *loadedConfig = [ALNConfig loadConfigAtRoot:appRoot
                                                 environment:environment
                                                       error:&configError];
    if (loadedConfig == nil) {
      AddDoctorCheck(checks,
                     @"config_load",
                     @"fail",
                     [NSString stringWithFormat:@"failed loading config for env '%@': %@",
                                                environment ?: @"development",
                                                configError.localizedDescription ?: @"unknown"],
                     @"Run `arlen config --env <name>` and fix malformed plist values.");
      failCount += 1;
    } else {
      NSString *host = [loadedConfig[@"host"] isKindOfClass:[NSString class]] ? loadedConfig[@"host"] : @"";
      NSInteger port = [loadedConfig[@"port"] respondsToSelector:@selector(integerValue)]
                           ? [loadedConfig[@"port"] integerValue]
                           : 0;
      AddDoctorCheck(checks,
                     @"config_load",
                     @"pass",
                     [NSString stringWithFormat:@"loaded config env '%@' (host=%@ port=%ld)",
                                                environment ?: @"development",
                                                host,
                                                (long)port],
                     @"");
      passCount += 1;
    }
  }

  NSDictionary *summary = @{
    @"pass" : @(passCount),
    @"warn" : @(warnCount),
    @"fail" : @(failCount),
  };

  if (asJSON) {
    NSDictionary *payload = @{
      @"appRoot" : appRoot ?: @"",
      @"frameworkRoot" : frameworkRoot ?: @"",
      @"environment" : environment ?: @"development",
      @"summary" : summary,
      @"checks" : checks,
    };
    if (!PrintJSONPayload(stdout, payload)) {
      return 1;
    }
  } else {
    NSString *safeFrameworkRoot = ([frameworkRoot length] > 0) ? frameworkRoot : @"(unresolved)";
    fprintf(stdout, "Arlen doctor\n");
    fprintf(stdout, "  app root: %s\n", [appRoot UTF8String]);
    fprintf(stdout, "  framework root: %s\n", [safeFrameworkRoot UTF8String]);
    fprintf(stdout, "  environment: %s\n", [environment UTF8String]);
    for (NSDictionary *entry in checks) {
      NSString *status = [entry[@"status"] isKindOfClass:[NSString class]] ? [entry[@"status"] uppercaseString] : @"WARN";
      NSString *message = [entry[@"message"] isKindOfClass:[NSString class]] ? entry[@"message"] : @"";
      NSString *hint = [entry[@"hint"] isKindOfClass:[NSString class]] ? entry[@"hint"] : @"";
      fprintf(stdout, "[%s] %s\n", [status UTF8String], [message UTF8String]);
      if ([hint length] > 0) {
        fprintf(stdout, "       hint: %s\n", [hint UTF8String]);
      }
    }
    fprintf(stdout, "\nSummary: pass=%ld warn=%ld fail=%ld\n",
            (long)passCount, (long)warnCount, (long)failCount);
    fprintf(stdout, "Known-good matrix: docs/TOOLCHAIN_MATRIX.md\n");
  }

  return (failCount == 0) ? 0 : 1;
}

static int CommandConfig(NSArray *args) {
  NSString *environment = @"development";
  BOOL asJSON = NO;
  for (NSUInteger idx = 0; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--env"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen config: --env requires a value\n");
        return 2;
      }
      environment = args[++idx];
    } else if ([arg isEqualToString:@"--json"]) {
      asJSON = YES;
    } else {
      fprintf(stderr, "arlen config: unknown option %s\n", [arg UTF8String]);
      return 2;
    }
  }

  NSError *error = nil;
  NSDictionary *config = [ALNConfig loadConfigAtRoot:[[NSFileManager defaultManager] currentDirectoryPath]
                                        environment:environment
                                              error:&error];
  if (config == nil) {
    fprintf(stderr, "arlen config: %s\n", [[error localizedDescription] UTF8String]);
    return 1;
  }

  if (asJSON) {
    NSData *json = [ALNJSONSerialization dataWithJSONObject:config
                                                    options:StableJSONWritingOptions()
                                                      error:&error];
    if (json == nil) {
      fprintf(stderr, "arlen config: %s\n", [[error localizedDescription] UTF8String]);
      return 1;
    }
    fprintf(stdout, "%s\n", [[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] UTF8String]);
    return 0;
  }

  NSArray *keys = [[config allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in keys) {
    fprintf(stdout, "%s=%s\n", [key UTF8String], [[config[key] description] UTF8String]);
  }
  return 0;
}

static NSString *NormalizeDatabaseTarget(NSString *rawValue) {
  NSString *target =
      [rawValue isKindOfClass:[NSString class]] ? [Trimmed(rawValue) lowercaseString] : @"";
  return ([target length] > 0) ? target : @"default";
}

static BOOL DatabaseTargetIsValid(NSString *target) {
  if (![target isKindOfClass:[NSString class]] || [target length] == 0) {
    return NO;
  }
  if ([target length] > 32) {
    return NO;
  }
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"];
  if ([[target stringByTrimmingCharactersInSet:allowed] length] > 0) {
    return NO;
  }
  unichar first = [target characterAtIndex:0];
  return ([[NSCharacterSet letterCharacterSet] characterIsMember:first] || first == '_');
}

static NSDictionary *DatabaseConfigSectionForTarget(NSDictionary *config, NSString *databaseTarget) {
  if (![config isKindOfClass:[NSDictionary class]]) {
    return nil;
  }

  NSString *target = NormalizeDatabaseTarget(databaseTarget);
  if ([target isEqualToString:@"default"]) {
    return [config[@"database"] isKindOfClass:[NSDictionary class]] ? config[@"database"] : nil;
  }

  NSDictionary *databases = [config[@"databases"] isKindOfClass:[NSDictionary class]] ? config[@"databases"] : nil;
  NSDictionary *targetConfig = [databases[target] isKindOfClass:[NSDictionary class]] ? databases[target] : nil;
  if (targetConfig != nil) {
    return targetConfig;
  }

  NSDictionary *databaseTargets =
      [config[@"databaseTargets"] isKindOfClass:[NSDictionary class]] ? config[@"databaseTargets"] : nil;
  targetConfig = [databaseTargets[target] isKindOfClass:[NSDictionary class]] ? databaseTargets[target] : nil;
  if (targetConfig != nil) {
    return targetConfig;
  }

  return nil;
}

static NSString *DatabaseConnectionStringFromEnvironmentForTarget(NSString *databaseTarget) {
  NSString *target = NormalizeDatabaseTarget(databaseTarget);
  if (![target isEqualToString:@"default"]) {
    NSString *envName = [NSString stringWithFormat:@"ARLEN_DATABASE_URL_%@", [target uppercaseString]];
    NSString *targeted = EnvValue([envName UTF8String]);
    if ([targeted length] > 0) {
      return targeted;
    }
  }
  return EnvValue("ARLEN_DATABASE_URL");
}

static NSString *DatabaseConnectionStringFromConfigForTarget(NSDictionary *config, NSString *databaseTarget) {
  NSDictionary *database = DatabaseConfigSectionForTarget(config, databaseTarget);
  NSString *connectionString =
      [database[@"connectionString"] isKindOfClass:[NSString class]] ? database[@"connectionString"] : nil;
  if ([connectionString length] > 0) {
    return connectionString;
  }

  if ([NormalizeDatabaseTarget(databaseTarget) isEqualToString:@"default"]) {
    return nil;
  }

  NSDictionary *fallback = [config[@"database"] isKindOfClass:[NSDictionary class]] ? config[@"database"] : nil;
  NSString *fallbackConnection =
      [fallback[@"connectionString"] isKindOfClass:[NSString class]] ? fallback[@"connectionString"] : nil;
  return ([fallbackConnection length] > 0) ? fallbackConnection : nil;
}

static NSUInteger DatabasePoolSizeFromConfigForTarget(NSDictionary *config, NSString *databaseTarget) {
  NSDictionary *database = DatabaseConfigSectionForTarget(config, databaseTarget);
  id value = database[@"poolSize"];
  if ([value respondsToSelector:@selector(unsignedIntegerValue)]) {
    NSUInteger parsed = [value unsignedIntegerValue];
    if (parsed >= 1) {
      return parsed;
    }
  }

  if (![NormalizeDatabaseTarget(databaseTarget) isEqualToString:@"default"]) {
    NSDictionary *fallback = [config[@"database"] isKindOfClass:[NSDictionary class]] ? config[@"database"] : nil;
    value = fallback[@"poolSize"];
    if ([value respondsToSelector:@selector(unsignedIntegerValue)]) {
      NSUInteger parsed = [value unsignedIntegerValue];
      if (parsed >= 1) {
        return parsed;
      }
    }
  }
  return 4;
}

static NSString *DatabaseAdapterNameFromConfigForTarget(NSDictionary *config, NSString *databaseTarget) {
  NSDictionary *database = DatabaseConfigSectionForTarget(config, databaseTarget);
  NSString *adapter =
      [database[@"adapter"] isKindOfClass:[NSString class]] ? Trimmed([database[@"adapter"] lowercaseString]) : @"";
  if ([adapter length] > 0) {
    return adapter;
  }

  if (![NormalizeDatabaseTarget(databaseTarget) isEqualToString:@"default"]) {
    NSDictionary *fallback = [config[@"database"] isKindOfClass:[NSDictionary class]] ? config[@"database"] : nil;
    adapter =
        [fallback[@"adapter"] isKindOfClass:[NSString class]] ? Trimmed([fallback[@"adapter"] lowercaseString]) : @"";
    if ([adapter length] > 0) {
      return adapter;
    }
  }

  return @"postgresql";
}

static id<ALNDatabaseAdapter> DatabaseAdapterForTarget(NSDictionary *config,
                                                       NSString *databaseTarget,
                                                       NSString *dsn,
                                                       NSError **error) {
  NSString *adapterName = DatabaseAdapterNameFromConfigForTarget(config, databaseTarget);
  NSUInteger poolSize = DatabasePoolSizeFromConfigForTarget(config, databaseTarget);
  if ([adapterName isEqualToString:@"postgresql"]) {
    return [[ALNPg alloc] initWithConnectionString:dsn maxConnections:poolSize error:error];
  }
  if ([adapterName isEqualToString:@"gdl2"]) {
    return [[ALNGDL2Adapter alloc] initWithConnectionString:dsn maxConnections:poolSize error:error];
  }
  if ([adapterName isEqualToString:@"mssql"] || [adapterName isEqualToString:@"sqlserver"]) {
    return [[ALNMSSQL alloc] initWithConnectionString:dsn maxConnections:poolSize error:error];
  }

  if (error != NULL) {
    *error = [NSError errorWithDomain:ALNDatabaseAdapterErrorDomain
                                 code:ALNDatabaseAdapterErrorUnsupported
                             userInfo:@{
                               NSLocalizedDescriptionKey :
                                   [NSString stringWithFormat:@"unsupported database adapter '%@'", adapterName ?: @""],
                               @"adapter" : adapterName ?: @"",
                             }];
  }
  return nil;
}

static NSString *DatabaseTargetPascalSuffix(NSString *databaseTarget) {
  NSArray<NSString *> *parts = [NormalizeDatabaseTarget(databaseTarget) componentsSeparatedByString:@"_"];
  NSMutableString *suffix = [NSMutableString string];
  for (NSString *part in parts) {
    if ([part length] == 0) {
      continue;
    }
    NSString *lower = [part lowercaseString];
    NSString *first = [[lower substringToIndex:1] uppercaseString];
    NSString *rest = ([lower length] > 1) ? [lower substringFromIndex:1] : @"";
    [suffix appendFormat:@"%@%@", first, rest];
  }
  if ([suffix length] == 0) {
    return @"Default";
  }
  return [NSString stringWithString:suffix];
}

static NSString *NormalizeDataverseTarget(NSString *rawValue) {
  return NormalizeDatabaseTarget(rawValue);
}

static BOOL DataverseTargetIsValid(NSString *target) {
  return DatabaseTargetIsValid(target);
}

static NSString *DataverseEnvironmentValueForTarget(NSString *baseName, NSString *dataverseTarget) {
  NSString *target = NormalizeDataverseTarget(dataverseTarget);
  if (![target isEqualToString:@"default"]) {
    NSString *targetedName = [NSString stringWithFormat:@"%@_%@", baseName ?: @"", [target uppercaseString]];
    NSString *targeted = EnvValue([targetedName UTF8String]);
    if ([targeted length] > 0) {
      return targeted;
    }
  }
  return EnvValue([baseName UTF8String]);
}

static NSDictionary *DataverseMergedConfigForTarget(NSDictionary *config, NSString *dataverseTarget) {
  NSDictionary *resolved = [ALNDataverseTarget configurationNamed:dataverseTarget fromConfig:config];
  return [resolved isKindOfClass:[NSDictionary class]] ? resolved : @{};
}

static ALNDataverseTarget *DataverseTargetForCommand(NSDictionary *config,
                                                     NSString *dataverseTarget,
                                                     NSDictionary *overrides,
                                                     NSError **error) {
  NSMutableDictionary *merged =
      [NSMutableDictionary dictionaryWithDictionary:DataverseMergedConfigForTarget(config, dataverseTarget) ?: @{}];
  NSDictionary *overrideValues = [overrides isKindOfClass:[NSDictionary class]] ? overrides : @{};
  for (NSString *key in overrideValues) {
    id value = overrideValues[key];
    if ([value isKindOfClass:[NSString class]] && [Trimmed(value) length] == 0) {
      continue;
    }
    if (value != nil && value != [NSNull null]) {
      merged[key] = value;
    }
  }

  NSString *serviceRoot = DataverseEnvironmentValueForTarget(@"ARLEN_DATAVERSE_URL", dataverseTarget);
  if ([serviceRoot length] == 0) {
    serviceRoot = DataverseEnvironmentValueForTarget(@"ARLEN_DATAVERSE_SERVICE_ROOT", dataverseTarget);
  }
  NSString *tenantID = DataverseEnvironmentValueForTarget(@"ARLEN_DATAVERSE_TENANT_ID", dataverseTarget);
  NSString *clientID = DataverseEnvironmentValueForTarget(@"ARLEN_DATAVERSE_CLIENT_ID", dataverseTarget);
  NSString *clientSecret = DataverseEnvironmentValueForTarget(@"ARLEN_DATAVERSE_CLIENT_SECRET", dataverseTarget);
  NSString *pageSize = DataverseEnvironmentValueForTarget(@"ARLEN_DATAVERSE_PAGE_SIZE", dataverseTarget);
  NSString *maxRetries = DataverseEnvironmentValueForTarget(@"ARLEN_DATAVERSE_MAX_RETRIES", dataverseTarget);
  NSString *timeout = DataverseEnvironmentValueForTarget(@"ARLEN_DATAVERSE_TIMEOUT", dataverseTarget);

  if ([serviceRoot length] > 0) {
    merged[@"serviceRootURL"] = serviceRoot;
  }
  if ([tenantID length] > 0) {
    merged[@"tenantID"] = tenantID;
  }
  if ([clientID length] > 0) {
    merged[@"clientID"] = clientID;
  }
  if ([clientSecret length] > 0) {
    merged[@"clientSecret"] = clientSecret;
  }
  if ([pageSize length] > 0) {
    merged[@"pageSize"] = @([pageSize integerValue]);
  }
  if ([maxRetries length] > 0) {
    merged[@"maxRetries"] = @([maxRetries integerValue]);
  }
  if ([timeout length] > 0) {
    merged[@"timeout"] = @([timeout doubleValue]);
  }

  NSString *target = NormalizeDataverseTarget(dataverseTarget);
  NSString *resolvedServiceRoot =
      [merged[@"serviceRootURL"] isKindOfClass:[NSString class]] ? merged[@"serviceRootURL"]
      : ([merged[@"serviceRoot"] isKindOfClass:[NSString class]] ? merged[@"serviceRoot"]
         : ([merged[@"baseURL"] isKindOfClass:[NSString class]] ? merged[@"baseURL"]
            : ([merged[@"url"] isKindOfClass:[NSString class]] ? merged[@"url"] : nil)));
  NSString *resolvedTenantID =
      [merged[@"tenantID"] isKindOfClass:[NSString class]] ? merged[@"tenantID"]
      : ([merged[@"tenantId"] isKindOfClass:[NSString class]] ? merged[@"tenantId"] : nil);
  NSString *resolvedClientID =
      [merged[@"clientID"] isKindOfClass:[NSString class]] ? merged[@"clientID"]
      : ([merged[@"clientId"] isKindOfClass:[NSString class]] ? merged[@"clientId"] : nil);
  NSString *resolvedClientSecret =
      [merged[@"clientSecret"] isKindOfClass:[NSString class]] ? merged[@"clientSecret"] : nil;
  NSTimeInterval resolvedTimeout =
      [merged[@"timeout"] respondsToSelector:@selector(doubleValue)] ? [merged[@"timeout"] doubleValue] : 60.0;
  NSUInteger resolvedMaxRetries =
      [merged[@"maxRetries"] respondsToSelector:@selector(unsignedIntegerValue)] ? [merged[@"maxRetries"] unsignedIntegerValue] : 2;
  NSUInteger resolvedPageSize =
      [merged[@"pageSize"] respondsToSelector:@selector(unsignedIntegerValue)] ? [merged[@"pageSize"] unsignedIntegerValue] : 500;

  return [[ALNDataverseTarget alloc] initWithServiceRootURLString:resolvedServiceRoot
                                                         tenantID:resolvedTenantID
                                                         clientID:resolvedClientID
                                                     clientSecret:resolvedClientSecret
                                                        targetName:target
                                                   timeoutInterval:resolvedTimeout
                                                        maxRetries:resolvedMaxRetries
                                                          pageSize:resolvedPageSize
                                                             error:error];
}

static NSString *DataverseTargetPascalSuffix(NSString *dataverseTarget) {
  return DatabaseTargetPascalSuffix(dataverseTarget);
}

static NSString *ResolvePathFromRoot(NSString *root, NSString *rawPath) {
  NSString *candidate = Trimmed(rawPath);
  if ([candidate length] == 0) {
    return root;
  }
  NSString *expanded = [candidate stringByExpandingTildeInPath];
  if ([expanded hasPrefix:@"/"]) {
    return [expanded stringByStandardizingPath];
  }
  return [[root stringByAppendingPathComponent:expanded] stringByStandardizingPath];
}

static NSString *const ALNTypedSQLCodegenErrorDomain = @"Arlen.CLI.TypedSQLCodegen.Error";

static NSError *ALNTypedSQLCodegenError(NSString *message, NSString *detail) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"typed sql codegen error";
  if ([detail length] > 0) {
    userInfo[@"detail"] = detail;
  }
  return [NSError errorWithDomain:ALNTypedSQLCodegenErrorDomain code:1 userInfo:userInfo];
}

static BOOL ALNTypedSQLIdentifierIsSafe(NSString *value) {
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

static NSString *ALNTypedSQLPascalSuffix(NSString *identifier) {
  NSArray<NSString *> *parts = [[Trimmed(identifier) lowercaseString] componentsSeparatedByString:@"_"];
  NSMutableString *suffix = [NSMutableString string];
  for (NSString *part in parts) {
    if ([part length] == 0) {
      continue;
    }
    NSString *first = [[part substringToIndex:1] uppercaseString];
    NSString *rest = ([part length] > 1) ? [part substringFromIndex:1] : @"";
    [suffix appendFormat:@"%@%@", first, rest];
  }
  if ([suffix length] == 0) {
    [suffix appendString:@"Query"];
  }
  return [NSString stringWithString:suffix];
}

static NSString *ALNTypedSQLLowerCamel(NSString *identifier) {
  NSString *pascalSuffix = ALNTypedSQLPascalSuffix(identifier);
  if ([pascalSuffix length] == 0) {
    return @"value";
  }
  NSString *first = [[pascalSuffix substringToIndex:1] lowercaseString];
  NSString *rest = ([pascalSuffix length] > 1) ? [pascalSuffix substringFromIndex:1] : @"";
  return [NSString stringWithFormat:@"%@%@", first, rest];
}

static NSDictionary<NSString *, NSString *> *ALNTypedSQLTypeDescriptor(NSString *token, BOOL *nullable) {
  NSString *normalized = [[Trimmed(token) lowercaseString] copy];
  BOOL isNullable = NO;
  if ([normalized hasSuffix:@"?"]) {
    isNullable = YES;
    normalized = [normalized substringToIndex:[normalized length] - 1];
  }
  if (nullable != NULL) {
    *nullable = isNullable;
  }
  if ([normalized isEqualToString:@"text"] || [normalized isEqualToString:@"string"] ||
      [normalized isEqualToString:@"uuid"]) {
    return @{
      @"objcType" : @"NSString *",
      @"runtimeClass" : @"NSString",
      @"propertyAttribute" : @"copy",
      @"displayType" : normalized,
    };
  }
  if ([normalized isEqualToString:@"int"] || [normalized isEqualToString:@"integer"] ||
      [normalized isEqualToString:@"number"] || [normalized isEqualToString:@"bool"] ||
      [normalized isEqualToString:@"boolean"]) {
    return @{
      @"objcType" : @"NSNumber *",
      @"runtimeClass" : @"NSNumber",
      @"propertyAttribute" : @"strong",
      @"displayType" : normalized,
    };
  }
  if ([normalized isEqualToString:@"json"]) {
    return @{
      @"objcType" : @"id",
      @"runtimeClass" : @"",
      @"propertyAttribute" : @"strong",
      @"displayType" : normalized,
    };
  }
  return @{
    @"objcType" : @"id",
    @"runtimeClass" : @"",
    @"propertyAttribute" : @"strong",
    @"displayType" : ([normalized length] > 0 ? normalized : @"any"),
  };
}

static NSArray<NSDictionary<NSString *, id> *> *ALNTypedSQLParseFieldSpecs(NSString *rawSpec,
                                                                            NSString *label,
                                                                            NSError **error) {
  NSString *spec = Trimmed(rawSpec);
  if ([spec length] == 0) {
    return @[];
  }

  NSString *normalized = [[spec stringByReplacingOccurrencesOfString:@"," withString:@" "]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSArray<NSString *> *tokens =
      [normalized componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSMutableArray<NSDictionary<NSString *, id> *> *fields = [NSMutableArray array];

  for (NSString *token in tokens) {
    NSString *part = Trimmed(token);
    if ([part length] == 0) {
      continue;
    }
    NSRange separatorRange = [part rangeOfString:@":"];
    if (separatorRange.location == NSNotFound) {
      if (error != NULL) {
        *error = ALNTypedSQLCodegenError(
            [NSString stringWithFormat:@"%@ entries must use name:type format", label], part);
      }
      return nil;
    }
    NSString *name = Trimmed([part substringToIndex:separatorRange.location]);
    NSString *typeToken = Trimmed([part substringFromIndex:separatorRange.location + 1]);
    if (!ALNTypedSQLIdentifierIsSafe(name)) {
      if (error != NULL) {
        *error = ALNTypedSQLCodegenError(
            [NSString stringWithFormat:@"%@ field identifier is invalid", label], name);
      }
      return nil;
    }

    BOOL nullable = NO;
    NSDictionary<NSString *, NSString *> *typeDescriptor = ALNTypedSQLTypeDescriptor(typeToken, &nullable);
    [fields addObject:@{
      @"name" : name,
      @"propertyName" : [NSString stringWithFormat:@"field%@", ALNTypedSQLPascalSuffix(name)],
      @"objcType" : typeDescriptor[@"objcType"] ?: @"id",
      @"runtimeClass" : typeDescriptor[@"runtimeClass"] ?: @"",
      @"propertyAttribute" : typeDescriptor[@"propertyAttribute"] ?: @"strong",
      @"displayType" : typeDescriptor[@"displayType"] ?: @"any",
      @"nullable" : @(nullable),
    }];
  }

  return fields;
}

static NSString *ALNTypedSQLEscapeObjCString(NSString *value) {
  NSMutableString *escaped = [NSMutableString stringWithCapacity:[value length] + 8];
  for (NSUInteger idx = 0; idx < [value length]; idx++) {
    unichar ch = [value characterAtIndex:idx];
    switch (ch) {
      case '"':
        [escaped appendString:@"\\\""];
        break;
      case '\\':
        [escaped appendString:@"\\\\"];
        break;
      case '\n':
        [escaped appendString:@"\\n"];
        break;
      case '\r':
        [escaped appendString:@"\\r"];
        break;
      case '\t':
        [escaped appendString:@"\\t"];
        break;
      default:
        [escaped appendFormat:@"%C", ch];
        break;
    }
  }
  return [NSString stringWithString:escaped];
}

static NSString *ALNTypedSQLJSONEscape(NSString *value) {
  NSMutableString *escaped = [NSMutableString stringWithCapacity:[value length] + 8];
  for (NSUInteger idx = 0; idx < [value length]; idx++) {
    unichar ch = [value characterAtIndex:idx];
    switch (ch) {
      case '"':
        [escaped appendString:@"\\\""];
        break;
      case '\\':
        [escaped appendString:@"\\\\"];
        break;
      case '\n':
        [escaped appendString:@"\\n"];
        break;
      case '\r':
        [escaped appendString:@"\\r"];
        break;
      case '\t':
        [escaped appendString:@"\\t"];
        break;
      default:
        if (ch < 0x20) {
          [escaped appendFormat:@"\\u%04x", ch];
        } else {
          [escaped appendFormat:@"%C", ch];
        }
        break;
    }
  }
  return [NSString stringWithString:escaped];
}

static NSDictionary<NSString *, id> *ALNTypedSQLParseDefinitionAtPath(NSString *path, NSError **error) {
  NSString *contents = [NSString stringWithContentsOfFile:path
                                                 encoding:NSUTF8StringEncoding
                                                    error:error];
  if (contents == nil) {
    return nil;
  }

  NSArray<NSString *> *lines = [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  NSString *queryName = nil;
  NSString *paramsSpec = @"";
  NSString *resultSpec = @"";
  NSMutableArray<NSString *> *sqlLines = [NSMutableArray array];

  for (NSString *line in lines) {
    NSString *trimmed = Trimmed(line);
    if ([trimmed hasPrefix:@"-- arlen:name "]) {
      queryName = Trimmed([trimmed substringFromIndex:[@"-- arlen:name " length]]);
      continue;
    }
    if ([trimmed hasPrefix:@"-- arlen:params "]) {
      paramsSpec = Trimmed([trimmed substringFromIndex:[@"-- arlen:params " length]]);
      continue;
    }
    if ([trimmed hasPrefix:@"-- arlen:result "]) {
      resultSpec = Trimmed([trimmed substringFromIndex:[@"-- arlen:result " length]]);
      continue;
    }
    if ([trimmed hasPrefix:@"--"]) {
      continue;
    }
    if ([trimmed length] > 0) {
      [sqlLines addObject:trimmed];
    }
  }

  if (!ALNTypedSQLIdentifierIsSafe(queryName)) {
    if (error != NULL) {
      *error = ALNTypedSQLCodegenError(@"typed SQL query requires '-- arlen:name <identifier>'",
                                       [path lastPathComponent]);
    }
    return nil;
  }

  NSArray<NSDictionary<NSString *, id> *> *params = ALNTypedSQLParseFieldSpecs(paramsSpec, @"params", error);
  if (params == nil) {
    return nil;
  }
  NSArray<NSDictionary<NSString *, id> *> *resultFields =
      ALNTypedSQLParseFieldSpecs(resultSpec, @"result", error);
  if (resultFields == nil) {
    return nil;
  }
  if ([resultFields count] == 0) {
    if (error != NULL) {
      *error = ALNTypedSQLCodegenError(@"typed SQL query requires at least one result field",
                                       [path lastPathComponent]);
    }
    return nil;
  }

  NSString *sql = [sqlLines componentsJoinedByString:@" "];
  if ([sql length] == 0) {
    if (error != NULL) {
      *error = ALNTypedSQLCodegenError(@"typed SQL query body is empty", [path lastPathComponent]);
    }
    return nil;
  }

  NSString *methodSuffix = ALNTypedSQLPascalSuffix(queryName);
  return @{
    @"name" : queryName,
    @"methodSuffix" : methodSuffix,
    @"params" : params,
    @"result" : resultFields,
    @"sql" : sql,
    @"sourcePath" : path,
  };
}

static NSDictionary<NSString *, id> *ALNTypedSQLRenderArtifacts(NSArray<NSDictionary<NSString *, id> *> *definitions,
                                                                NSString *classPrefix,
                                                                NSError **error) {
  NSString *prefix = Trimmed(classPrefix);
  if ([prefix length] == 0) {
    prefix = @"ALNDB";
  }
  if (!ALNTypedSQLIdentifierIsSafe(prefix)) {
    if (error != NULL) {
      *error = ALNTypedSQLCodegenError(@"class prefix must be a valid identifier", prefix);
    }
    return nil;
  }
  if ([definitions count] == 0) {
    if (error != NULL) {
      *error = ALNTypedSQLCodegenError(@"no typed SQL definitions were provided", @"");
    }
    return nil;
  }

  NSString *baseName = [NSString stringWithFormat:@"%@TypedSQL", prefix];
  NSString *guard = [NSString stringWithFormat:@"%@_H", [[baseName uppercaseString]
      stringByReplacingOccurrencesOfString:@"[^A-Z0-9_]" withString:@"_"]];
  NSString *errorDomainName = [NSString stringWithFormat:@"%@ErrorDomain", baseName];
  NSString *errorEnumName = [NSString stringWithFormat:@"%@ErrorCode", baseName];
  NSString *errorBuilderName = [NSString stringWithFormat:@"%@MakeError", baseName];

  NSMutableString *header = [NSMutableString string];
  [header appendString:@"// Generated by arlen typed-sql-codegen. Do not edit by hand.\n"];
  [header appendFormat:@"#ifndef %@\n", guard];
  [header appendFormat:@"#define %@\n\n", guard];
  [header appendString:@"#import <Foundation/Foundation.h>\n\n"];
  [header appendString:@"NS_ASSUME_NONNULL_BEGIN\n\n"];
  [header appendFormat:@"typedef NS_ENUM(NSInteger, %@) {\n", errorEnumName];
  [header appendFormat:@"  %@MissingField = 1,\n", errorEnumName];
  [header appendFormat:@"  %@InvalidType = 2,\n", errorEnumName];
  [header appendString:@"};\n\n"];
  [header appendFormat:@"FOUNDATION_EXPORT NSString *const %@;\n\n", errorDomainName];

  NSMutableString *implementation = [NSMutableString string];
  [implementation appendString:@"// Generated by arlen typed-sql-codegen. Do not edit by hand.\n"];
  [implementation appendFormat:@"#import \"%@.h\"\n\n", baseName];
  [implementation appendFormat:@"NSString *const %@ = @\"Arlen.CLI.TypedSQL.%@\";\n\n",
                               errorDomainName,
                               baseName];
  [implementation appendFormat:@"static NSError *%@( %@ code,\n", errorBuilderName, errorEnumName];
  [implementation appendString:@"                            NSString *field,\n"];
  [implementation appendString:@"                            NSString *expected,\n"];
  [implementation appendString:@"                            NSString *detail) {\n"];
  [implementation appendString:@"  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];\n"];
  [implementation appendString:@"  userInfo[NSLocalizedDescriptionKey] = detail ?: @\"typed SQL decode failure\";\n"];
  [implementation appendString:@"  if ([field length] > 0) {\n"];
  [implementation appendString:@"    userInfo[@\"field\"] = field;\n"];
  [implementation appendString:@"  }\n"];
  [implementation appendString:@"  if ([expected length] > 0) {\n"];
  [implementation appendString:@"    userInfo[@\"expected_type\"] = expected;\n"];
  [implementation appendString:@"  }\n"];
  [implementation appendFormat:@"  return [NSError errorWithDomain:%@ code:code userInfo:userInfo];\n", errorDomainName];
  [implementation appendString:@"}\n\n"];

  for (NSDictionary<NSString *, id> *definition in definitions) {
    NSString *suffix = definition[@"methodSuffix"];
    NSString *rowClass = [NSString stringWithFormat:@"%@%@Row", baseName, suffix];
    NSArray<NSDictionary<NSString *, id> *> *resultFields = definition[@"result"];

    [header appendFormat:@"@interface %@ : NSObject\n", rowClass];
    for (NSDictionary<NSString *, id> *field in resultFields) {
      NSString *propertyName = field[@"propertyName"];
      NSString *objcType = field[@"objcType"];
      NSString *propertyAttribute = field[@"propertyAttribute"];
      NSString *nullability =
          [field[@"nullable"] respondsToSelector:@selector(boolValue)] && [field[@"nullable"] boolValue]
              ? @"nullable"
              : @"nonnull";
      [header appendFormat:@"@property(nonatomic, %@, readonly, %@) %@ %@;\n",
                           propertyAttribute, nullability, objcType, propertyName];
    }
    [header appendString:@"- (instancetype)init"];
    NSUInteger idx = 0;
    for (NSDictionary<NSString *, id> *field in resultFields) {
      NSString *propertyName = field[@"propertyName"];
      NSString *objcType = field[@"objcType"];
      NSString *selector =
          (idx == 0) ? [NSString stringWithFormat:@"With%@:", ALNTypedSQLPascalSuffix(propertyName)]
                     : [NSString stringWithFormat:@"%@:", propertyName];
      [header appendFormat:@"%@(%@)%@", selector, objcType, propertyName];
      if (idx + 1 < [resultFields count]) {
        [header appendString:@" "];
      }
      idx += 1;
    }
    [header appendString:@" NS_DESIGNATED_INITIALIZER;\n"];
    [header appendString:@"- (instancetype)init NS_UNAVAILABLE;\n"];
    [header appendString:@"@end\n\n"];

    [implementation appendFormat:@"@interface %@ ()\n", rowClass];
    for (NSDictionary<NSString *, id> *field in resultFields) {
      NSString *propertyName = field[@"propertyName"];
      NSString *objcType = field[@"objcType"];
      NSString *propertyAttribute = field[@"propertyAttribute"];
      [implementation appendFormat:@"@property(nonatomic, %@, readwrite) %@ %@;\n",
                                   propertyAttribute, objcType, propertyName];
    }
    [implementation appendString:@"@end\n\n"];
    [implementation appendFormat:@"@implementation %@\n\n", rowClass];
    [implementation appendString:@"- (instancetype)init"];
    idx = 0;
    for (NSDictionary<NSString *, id> *field in resultFields) {
      NSString *propertyName = field[@"propertyName"];
      NSString *objcType = field[@"objcType"];
      NSString *selector =
          (idx == 0) ? [NSString stringWithFormat:@"With%@:", ALNTypedSQLPascalSuffix(propertyName)]
                     : [NSString stringWithFormat:@"%@:", propertyName];
      [implementation appendFormat:@"%@(%@)%@", selector, objcType, propertyName];
      if (idx + 1 < [resultFields count]) {
        [implementation appendString:@" "];
      }
      idx += 1;
    }
    [implementation appendString:@" {\n"];
    [implementation appendString:@"  self = [super init];\n"];
    [implementation appendString:@"  if (self == nil) {\n"];
    [implementation appendString:@"    return nil;\n"];
    [implementation appendString:@"  }\n"];
    for (NSDictionary<NSString *, id> *field in resultFields) {
      NSString *propertyName = field[@"propertyName"];
      [implementation appendFormat:@"  _%@ = %@;\n", propertyName, propertyName];
    }
    [implementation appendString:@"  return self;\n"];
    [implementation appendString:@"}\n\n"];
    [implementation appendString:@"@end\n\n"];
  }

  [header appendFormat:@"@interface %@ : NSObject\n", baseName];
  for (NSDictionary<NSString *, id> *definition in definitions) {
    NSString *suffix = definition[@"methodSuffix"];
    NSArray<NSDictionary<NSString *, id> *> *params = definition[@"params"];
    NSString *rowClass = [NSString stringWithFormat:@"%@%@Row", baseName, suffix];
    [header appendFormat:@"+ (NSString *)sql%@;\n", suffix];
    if ([params count] == 0) {
      [header appendFormat:@"+ (NSArray *)parametersFor%@;\n", suffix];
    } else {
      [header appendFormat:@"+ (NSArray *)parametersFor%@", suffix];
      NSUInteger paramIdx = 0;
      for (NSDictionary<NSString *, id> *param in params) {
        NSString *objcType = param[@"objcType"];
        NSString *name = ALNTypedSQLLowerCamel(param[@"name"]);
        NSString *selector =
            (paramIdx == 0) ? [NSString stringWithFormat:@"With%@:", ALNTypedSQLPascalSuffix(name)]
                            : [NSString stringWithFormat:@"%@:", name];
        [header appendFormat:@"%@(%@)%@", selector, objcType, name];
        if (paramIdx + 1 < [params count]) {
          [header appendString:@" "];
        }
        paramIdx += 1;
      }
      [header appendString:@";\n"];
    }
    [header appendFormat:@"+ (nullable %@ *)decode%@Row:(NSDictionary<NSString *, id> *)row\n",
                         rowClass, suffix];
    [header appendString:@"                            error:(NSError *_Nullable *_Nullable)error;\n"];
  }
  [header appendString:@"@end\n\n"];
  [header appendString:@"NS_ASSUME_NONNULL_END\n\n"];
  [header appendString:@"#endif\n"];

  [implementation appendFormat:@"@implementation %@\n\n", baseName];
  for (NSDictionary<NSString *, id> *definition in definitions) {
    NSString *suffix = definition[@"methodSuffix"];
    NSArray<NSDictionary<NSString *, id> *> *params = definition[@"params"];
    NSArray<NSDictionary<NSString *, id> *> *resultFields = definition[@"result"];
    NSString *rowClass = [NSString stringWithFormat:@"%@%@Row", baseName, suffix];
    NSString *sql = definition[@"sql"];

    [implementation appendFormat:@"+ (NSString *)sql%@ {\n", suffix];
    [implementation appendFormat:@"  return @\"%@\";\n", ALNTypedSQLEscapeObjCString(sql)];
    [implementation appendString:@"}\n\n"];

    if ([params count] == 0) {
      [implementation appendFormat:@"+ (NSArray *)parametersFor%@ {\n", suffix];
      [implementation appendString:@"  return @[];\n"];
      [implementation appendString:@"}\n\n"];
    } else {
      [implementation appendFormat:@"+ (NSArray *)parametersFor%@", suffix];
      NSUInteger paramIdx = 0;
      for (NSDictionary<NSString *, id> *param in params) {
        NSString *objcType = param[@"objcType"];
        NSString *name = ALNTypedSQLLowerCamel(param[@"name"]);
        NSString *selector =
            (paramIdx == 0) ? [NSString stringWithFormat:@"With%@:", ALNTypedSQLPascalSuffix(name)]
                            : [NSString stringWithFormat:@"%@:", name];
        [implementation appendFormat:@"%@(%@)%@", selector, objcType, name];
        if (paramIdx + 1 < [params count]) {
          [implementation appendString:@" "];
        }
        paramIdx += 1;
      }
      [implementation appendString:@" {\n"];
      [implementation appendString:@"  return @["];
      for (NSUInteger idx = 0; idx < [params count]; idx++) {
        NSDictionary<NSString *, id> *param = params[idx];
        NSString *name = ALNTypedSQLLowerCamel(param[@"name"]);
        [implementation appendFormat:@"%@ ?: [NSNull null]", name];
        if (idx + 1 < [params count]) {
          [implementation appendString:@", "];
        }
      }
      [implementation appendString:@"];\n"];
      [implementation appendString:@"}\n\n"];
    }

    [implementation appendFormat:@"+ (nullable %@ *)decode%@Row:(NSDictionary<NSString *, id> *)row\n",
                                 rowClass, suffix];
    [implementation appendString:@"                            error:(NSError **)error {\n"];
    [implementation appendString:@"  if (![row isKindOfClass:[NSDictionary class]]) {\n"];
    [implementation appendString:@"    if (error != NULL) {\n"];
    [implementation appendFormat:@"      *error = %@( %@InvalidType, @\"row\", @\"NSDictionary\", @\"typed SQL row must be a dictionary\");\n",
                                 errorBuilderName, errorEnumName];
    [implementation appendString:@"    }\n"];
    [implementation appendString:@"    return nil;\n"];
    [implementation appendString:@"  }\n"];

    for (NSDictionary<NSString *, id> *field in resultFields) {
      NSString *name = field[@"name"];
      NSString *propertyName = field[@"propertyName"];
      NSString *objcType = field[@"objcType"];
      NSString *runtimeClass = field[@"runtimeClass"];
      BOOL nullable = [field[@"nullable"] respondsToSelector:@selector(boolValue)] && [field[@"nullable"] boolValue];
      NSString *displayType = field[@"displayType"];
      NSString *pascalProperty = ALNTypedSQLPascalSuffix(propertyName);
      [implementation appendFormat:@"  id raw%@ = row[@\"%@\"];\n", pascalProperty, name];
      [implementation appendFormat:@"  if (raw%@ == [NSNull null]) {\n", pascalProperty];
      [implementation appendFormat:@"    raw%@ = nil;\n", pascalProperty];
      [implementation appendString:@"  }\n"];
      if (!nullable) {
        [implementation appendFormat:@"  if (raw%@ == nil) {\n", pascalProperty];
        [implementation appendString:@"    if (error != NULL) {\n"];
        [implementation appendFormat:@"      *error = %@( %@MissingField, @\"%@\", @\"%@\", @\"missing required result field\");\n",
                                     errorBuilderName, errorEnumName, name, displayType];
        [implementation appendString:@"    }\n"];
        [implementation appendString:@"    return nil;\n"];
        [implementation appendString:@"  }\n"];
      }
      if ([runtimeClass length] > 0) {
        [implementation appendFormat:@"  if (raw%@ != nil && ![raw%@ isKindOfClass:[%@ class]]) {\n",
                                     pascalProperty, pascalProperty, runtimeClass];
        [implementation appendString:@"    if (error != NULL) {\n"];
        [implementation appendFormat:@"      *error = %@( %@InvalidType, @\"%@\", @\"%@\", @\"result field has unexpected type\");\n",
                                     errorBuilderName, errorEnumName, name, displayType];
        [implementation appendString:@"    }\n"];
        [implementation appendString:@"    return nil;\n"];
        [implementation appendString:@"  }\n"];
      }
      [implementation appendFormat:@"  %@ %@ = (%@)raw%@;\n", objcType, propertyName, objcType, pascalProperty];
    }

    [implementation appendString:@"  return [["];
    [implementation appendString:rowClass];
    [implementation appendString:@" alloc] init"];
    NSUInteger resultIndex = 0;
    for (NSDictionary<NSString *, id> *field in resultFields) {
      NSString *propertyName = field[@"propertyName"];
      NSString *selector =
          (resultIndex == 0)
              ? [NSString stringWithFormat:@"With%@:", ALNTypedSQLPascalSuffix(propertyName)]
              : [NSString stringWithFormat:@"%@:", propertyName];
      [implementation appendFormat:@"%@%@", selector, propertyName];
      if (resultIndex + 1 < [resultFields count]) {
        [implementation appendString:@" "];
      }
      resultIndex += 1;
    }
    [implementation appendString:@"];\n"];
    [implementation appendString:@"}\n\n"];
  }
  [implementation appendString:@"@end\n"];

  NSMutableString *manifest = [NSMutableString string];
  [manifest appendString:@"{\n"];
  [manifest appendString:@"  \"version\": 1,\n"];
  [manifest appendFormat:@"  \"class_prefix\": \"%@\",\n", ALNTypedSQLJSONEscape(prefix)];
  [manifest appendFormat:@"  \"artifact_base_name\": \"%@\",\n", ALNTypedSQLJSONEscape(baseName)];
  [manifest appendString:@"  \"queries\": [\n"];
  for (NSUInteger idx = 0; idx < [definitions count]; idx++) {
    NSDictionary<NSString *, id> *definition = definitions[idx];
    [manifest appendString:@"    {\n"];
    [manifest appendFormat:@"      \"name\": \"%@\",\n", ALNTypedSQLJSONEscape(definition[@"name"] ?: @"")];
    [manifest appendFormat:@"      \"source\": \"%@\"\n",
                           ALNTypedSQLJSONEscape([definition[@"sourcePath"] lastPathComponent] ?: @"")];
    [manifest appendString:@"    }"];
    if (idx + 1 < [definitions count]) {
      [manifest appendString:@","];
    }
    [manifest appendString:@"\n"];
  }
  [manifest appendString:@"  ]\n"];
  [manifest appendString:@"}\n"];

  return @{
    @"baseName" : baseName,
    @"header" : [NSString stringWithString:header],
    @"implementation" : [NSString stringWithString:implementation],
    @"manifest" : [NSString stringWithString:manifest],
    @"queryCount" : @([definitions count]),
  };
}

static int CommandTypeScriptCodegen(NSArray *args) {
  NSString *ormInputArg = @"db/schema/arlen_orm_manifest.json";
  NSString *openAPIInputArg = nil;
  NSString *outputDirArg = @"frontend/generated/arlen";
  NSString *manifestArg = @"db/schema/arlen_typescript.json";
  NSString *classPrefix = @"ALNORM";
  NSString *databaseTarget = nil;
  NSString *packageName = @"arlen-generated-client";
  NSMutableArray<NSString *> *targets = [NSMutableArray array];
  BOOL force = NO;

  for (NSUInteger idx = 0; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--orm-input"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen typescript-codegen: --orm-input requires a value\n");
        return 2;
      }
      ormInputArg = args[++idx];
    } else if ([arg isEqualToString:@"--openapi-input"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen typescript-codegen: --openapi-input requires a value\n");
        return 2;
      }
      openAPIInputArg = args[++idx];
    } else if ([arg isEqualToString:@"--output-dir"] || [arg isEqualToString:@"--out-dir"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen typescript-codegen: %s requires a value\n", [arg UTF8String]);
        return 2;
      }
      outputDirArg = args[++idx];
    } else if ([arg isEqualToString:@"--manifest"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen typescript-codegen: --manifest requires a value\n");
        return 2;
      }
      manifestArg = args[++idx];
    } else if ([arg isEqualToString:@"--prefix"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen typescript-codegen: --prefix requires a value\n");
        return 2;
      }
      classPrefix = args[++idx];
    } else if ([arg isEqualToString:@"--database"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen typescript-codegen: --database requires a value\n");
        return 2;
      }
      databaseTarget = args[++idx];
    } else if ([arg isEqualToString:@"--package-name"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen typescript-codegen: --package-name requires a value\n");
        return 2;
      }
      packageName = args[++idx];
    } else if ([arg isEqualToString:@"--target"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen typescript-codegen: --target requires a value\n");
        return 2;
      }
      [targets addObject:args[++idx]];
    } else if ([arg isEqualToString:@"--force"]) {
      force = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      fprintf(stdout,
              "Usage: arlen typescript-codegen [--orm-input <path>] [--openapi-input <path>] "
              "[--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] "
              "[--database <target>] [--package-name <name>] "
              "[--target <models|validators|query|client|react|meta|all>] [--force]\n");
      return 0;
    } else {
      fprintf(stderr, "arlen typescript-codegen: unknown option %s\n", [arg UTF8String]);
      return 2;
    }
  }

  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *ormInputPath = ResolvePathFromRoot(appRoot, ormInputArg);
  NSString *openAPIInputPath =
      ([openAPIInputArg length] > 0) ? ResolvePathFromRoot(appRoot, openAPIInputArg) : nil;
  NSString *outputDir = ResolvePathFromRoot(appRoot, outputDirArg);
  NSString *manifestPath = ResolvePathFromRoot(appRoot, manifestArg);

  NSError *error = nil;
  NSData *ormData = ALNDataReadFromFile(ormInputPath, 0, &error);
  if (ormData == nil) {
    fprintf(stderr, "arlen typescript-codegen: failed reading %s: %s\n",
            [ormInputPath UTF8String], [[error localizedDescription] UTF8String]);
    return 1;
  }
  id ormPayload = [ALNJSONSerialization JSONObjectWithData:ormData options:0 error:&error];
  if (![ormPayload isKindOfClass:[NSDictionary class]]) {
    fprintf(stderr, "arlen typescript-codegen: invalid ORM JSON input: %s\n",
            [[error localizedDescription] UTF8String]);
    return 1;
  }
  NSDictionary<NSString *, id> *ormRoot = ormPayload;

  NSDictionary<NSString *, id> *openAPISpecification = nil;
  if ([openAPIInputPath length] > 0) {
    NSData *openAPIData = ALNDataReadFromFile(openAPIInputPath, 0, &error);
    if (openAPIData == nil) {
      fprintf(stderr, "arlen typescript-codegen: failed reading %s: %s\n",
              [openAPIInputPath UTF8String], [[error localizedDescription] UTF8String]);
      return 1;
    }
    id openAPIPayload = [ALNJSONSerialization JSONObjectWithData:openAPIData options:0 error:&error];
    if (![openAPIPayload isKindOfClass:[NSDictionary class]]) {
      fprintf(stderr, "arlen typescript-codegen: invalid OpenAPI JSON input: %s\n",
              [[error localizedDescription] UTF8String]);
      return 1;
    }
    openAPISpecification = openAPIPayload;
  }

  NSDictionary<NSString *, id> *artifacts = nil;
  NSDictionary<NSString *, id> *metadata =
      [ormRoot[@"metadata"] isKindOfClass:[NSDictionary class]] ? ormRoot[@"metadata"] : nil;
  BOOL looksLikeSchemaMetadata =
      (metadata != nil) || [ormRoot[@"relations"] isKindOfClass:[NSArray class]] ||
      [ormRoot[@"columns"] isKindOfClass:[NSArray class]];
  BOOL looksLikeORMManifest = [ormRoot[@"models"] isKindOfClass:[NSArray class]];

  if (looksLikeSchemaMetadata) {
    artifacts = [ALNORMTypeScriptCodegen renderArtifactsFromSchemaMetadata:metadata ?: ormRoot
                                                               classPrefix:classPrefix
                                                            databaseTarget:databaseTarget
                                                        descriptorOverrides:nil
                                                       openAPISpecification:openAPISpecification
                                                               packageName:packageName
                                                                   targets:targets
                                                                     error:&error];
  } else if (looksLikeORMManifest) {
    artifacts = [ALNORMTypeScriptCodegen renderArtifactsFromORMManifest:ormRoot
                                                    openAPISpecification:openAPISpecification
                                                            packageName:packageName
                                                                targets:targets
                                                                  error:&error];
  } else {
    fprintf(stderr,
            "arlen typescript-codegen: ORM input must be raw schema metadata, a `{ \"metadata\": ... }` wrapper, or an `arlen-orm-descriptor-v1` manifest\n");
    return 1;
  }

  if (artifacts == nil) {
    fprintf(stderr, "arlen typescript-codegen: %s\n", [[error localizedDescription] UTF8String]);
    return 1;
  }

  NSDictionary<NSString *, NSString *> *files =
      [artifacts[@"files"] isKindOfClass:[NSDictionary class]] ? artifacts[@"files"] : @{};
  NSArray<NSString *> *sortedPaths = [[files allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *relativePath in sortedPaths) {
    NSString *absolutePath = [outputDir stringByAppendingPathComponent:relativePath];
    if (!WriteTextFile(absolutePath, files[relativePath] ?: @"", force, &error)) {
      fprintf(stderr, "arlen typescript-codegen: failed writing %s: %s\n",
              [absolutePath UTF8String], [[error localizedDescription] UTF8String]);
      return 1;
    }
  }

  if (!WriteTextFile(manifestPath, artifacts[@"manifest"] ?: @"", force, &error)) {
    fprintf(stderr, "arlen typescript-codegen: failed writing %s: %s\n",
            [manifestPath UTF8String], [[error localizedDescription] UTF8String]);
    return 1;
  }

  NSInteger modelCount = [artifacts[@"modelCount"] respondsToSelector:@selector(integerValue)]
                             ? [artifacts[@"modelCount"] integerValue]
                             : 0;
  NSInteger operationCount = [artifacts[@"operationCount"] respondsToSelector:@selector(integerValue)]
                                 ? [artifacts[@"operationCount"] integerValue]
                                 : 0;
  NSString *resolvedPackageName =
      [artifacts[@"packageName"] isKindOfClass:[NSString class]] ? artifacts[@"packageName"] : packageName;

  fprintf(stdout, "Generated TypeScript artifacts.\n");
  fprintf(stdout, "  package: %s\n", [resolvedPackageName UTF8String]);
  fprintf(stdout, "  models: %ld\n", (long)modelCount);
  fprintf(stdout, "  operations: %ld\n", (long)operationCount);
  fprintf(stdout, "  output dir: %s\n", [outputDir UTF8String]);
  fprintf(stdout, "  manifest: %s\n", [manifestPath UTF8String]);
  return 0;
}

static int CommandTypedSQLCodegen(NSArray *args) {
  NSString *inputDirArg = @"db/sql/typed";
  NSString *outputDirArg = @"src/Generated";
  NSString *manifestArg = @"db/schema/arlen_typed_sql.json";
  NSString *classPrefix = @"ALNDB";
  BOOL force = NO;

  for (NSUInteger idx = 0; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--input-dir"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen typed-sql-codegen: --input-dir requires a value\n");
        return 2;
      }
      inputDirArg = args[++idx];
    } else if ([arg isEqualToString:@"--output-dir"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen typed-sql-codegen: --output-dir requires a value\n");
        return 2;
      }
      outputDirArg = args[++idx];
    } else if ([arg isEqualToString:@"--manifest"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen typed-sql-codegen: --manifest requires a value\n");
        return 2;
      }
      manifestArg = args[++idx];
    } else if ([arg isEqualToString:@"--prefix"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen typed-sql-codegen: --prefix requires a value\n");
        return 2;
      }
      classPrefix = args[++idx];
    } else if ([arg isEqualToString:@"--force"]) {
      force = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      fprintf(stdout,
              "Usage: arlen typed-sql-codegen [--input-dir <path>] [--output-dir <path>] "
              "[--manifest <path>] [--prefix <ClassPrefix>] [--force]\n");
      return 0;
    } else {
      fprintf(stderr, "arlen typed-sql-codegen: unknown option %s\n", [arg UTF8String]);
      return 2;
    }
  }

  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *inputDir = ResolvePathFromRoot(appRoot, inputDirArg);
  NSString *outputDir = ResolvePathFromRoot(appRoot, outputDirArg);
  NSString *manifestPath = ResolvePathFromRoot(appRoot, manifestArg);

  BOOL isDirectory = NO;
  if (![[NSFileManager defaultManager] fileExistsAtPath:inputDir isDirectory:&isDirectory] || !isDirectory) {
    fprintf(stderr, "arlen typed-sql-codegen: input directory not found: %s\n", [inputDir UTF8String]);
    return 1;
  }

  NSError *error = nil;
  NSArray<NSString *> *entries =
      [[NSFileManager defaultManager] contentsOfDirectoryAtPath:inputDir error:&error];
  if (entries == nil) {
    fprintf(stderr, "arlen typed-sql-codegen: failed to read input directory: %s\n",
            [[error localizedDescription] UTF8String]);
    return 1;
  }
  NSMutableArray<NSString *> *sqlFiles = [NSMutableArray array];
  for (NSString *entry in entries) {
    if (![[entry pathExtension] isEqualToString:@"sql"]) {
      continue;
    }
    NSString *fullPath = [inputDir stringByAppendingPathComponent:entry];
    BOOL childDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&childDirectory] && !childDirectory) {
      [sqlFiles addObject:fullPath];
    }
  }
  [sqlFiles sortUsingSelector:@selector(compare:)];
  if ([sqlFiles count] == 0) {
    fprintf(stderr, "arlen typed-sql-codegen: no .sql files found in %s\n", [inputDir UTF8String]);
    return 1;
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *definitions = [NSMutableArray array];
  NSMutableSet<NSString *> *seenNames = [NSMutableSet set];
  for (NSString *filePath in sqlFiles) {
    NSDictionary<NSString *, id> *definition = ALNTypedSQLParseDefinitionAtPath(filePath, &error);
    if (definition == nil) {
      fprintf(stderr, "arlen typed-sql-codegen: %s\n", [[error localizedDescription] UTF8String]);
      return 1;
    }
    NSString *name = definition[@"name"];
    if ([seenNames containsObject:name]) {
      fprintf(stderr, "arlen typed-sql-codegen: duplicate query name: %s\n", [name UTF8String]);
      return 1;
    }
    [seenNames addObject:name];
    [definitions addObject:definition];
  }

  NSDictionary<NSString *, id> *artifacts = ALNTypedSQLRenderArtifacts(definitions, classPrefix, &error);
  if (artifacts == nil) {
    fprintf(stderr, "arlen typed-sql-codegen: %s\n", [[error localizedDescription] UTF8String]);
    return 1;
  }

  NSString *baseName = [artifacts[@"baseName"] isKindOfClass:[NSString class]] ? artifacts[@"baseName"] : @"ALNDBTypedSQL";
  NSString *headerPath = [outputDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.h", baseName]];
  NSString *implementationPath = [outputDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m", baseName]];

  if (!WriteTextFile(headerPath, artifacts[@"header"] ?: @"", force, &error)) {
    fprintf(stderr, "arlen typed-sql-codegen: failed writing %s: %s\n",
            [headerPath UTF8String], [[error localizedDescription] UTF8String]);
    return 1;
  }
  if (!WriteTextFile(implementationPath, artifacts[@"implementation"] ?: @"", force, &error)) {
    fprintf(stderr, "arlen typed-sql-codegen: failed writing %s: %s\n",
            [implementationPath UTF8String], [[error localizedDescription] UTF8String]);
    return 1;
  }
  if (!WriteTextFile(manifestPath, artifacts[@"manifest"] ?: @"", force, &error)) {
    fprintf(stderr, "arlen typed-sql-codegen: failed writing %s: %s\n",
            [manifestPath UTF8String], [[error localizedDescription] UTF8String]);
    return 1;
  }

  NSInteger queryCount = [artifacts[@"queryCount"] respondsToSelector:@selector(integerValue)]
                             ? [artifacts[@"queryCount"] integerValue]
                             : 0;
  fprintf(stdout, "Generated typed SQL artifacts.\n");
  fprintf(stdout, "  queries: %ld\n", (long)queryCount);
  fprintf(stdout, "  header: %s\n", [headerPath UTF8String]);
  fprintf(stdout, "  implementation: %s\n", [implementationPath UTF8String]);
  fprintf(stdout, "  manifest: %s\n", [manifestPath UTF8String]);
  return 0;
}

static int CommandSchemaCodegen(NSArray *args) {
  NSString *environment = @"development";
  NSString *databaseTarget = @"default";
  NSString *dsnOverride = nil;
  NSString *outputDirArg = @"src/Generated";
  NSString *manifestArg = @"db/schema/arlen_schema.json";
  NSString *classPrefix = @"ALNDB";
  BOOL outputDirExplicit = NO;
  BOOL manifestExplicit = NO;
  BOOL classPrefixExplicit = NO;
  BOOL includeTypedContracts = NO;
  BOOL force = NO;

  for (NSUInteger idx = 0; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--env"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen schema-codegen: --env requires a value\n");
        return 2;
      }
      environment = args[++idx];
    } else if ([arg isEqualToString:@"--dsn"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen schema-codegen: --dsn requires a value\n");
        return 2;
      }
      dsnOverride = args[++idx];
    } else if ([arg isEqualToString:@"--database"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen schema-codegen: --database requires a value\n");
        return 2;
      }
      databaseTarget = NormalizeDatabaseTarget(args[++idx]);
      if (!DatabaseTargetIsValid(databaseTarget)) {
        fprintf(stderr,
                "arlen schema-codegen: --database must match [a-z][a-z0-9_]* and be <= 32 characters\n");
        return 2;
      }
    } else if ([arg isEqualToString:@"--output-dir"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen schema-codegen: --output-dir requires a value\n");
        return 2;
      }
      outputDirArg = args[++idx];
      outputDirExplicit = YES;
    } else if ([arg isEqualToString:@"--manifest"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen schema-codegen: --manifest requires a value\n");
        return 2;
      }
      manifestArg = args[++idx];
      manifestExplicit = YES;
    } else if ([arg isEqualToString:@"--prefix"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen schema-codegen: --prefix requires a value\n");
        return 2;
      }
      classPrefix = args[++idx];
      classPrefixExplicit = YES;
    } else if ([arg isEqualToString:@"--force"]) {
      force = YES;
    } else if ([arg isEqualToString:@"--typed-contracts"]) {
      includeTypedContracts = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      fprintf(stdout,
              "Usage: arlen schema-codegen [--env <name>] [--database <target>] [--dsn <connection_string>] "
              "[--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] [--typed-contracts] [--force]\n");
      return 0;
    } else {
      fprintf(stderr, "arlen schema-codegen: unknown option %s\n", [arg UTF8String]);
      return 2;
    }
  }

  if (![databaseTarget isEqualToString:@"default"]) {
    if (!outputDirExplicit) {
      outputDirArg = [NSString stringWithFormat:@"src/Generated/%@", databaseTarget];
    }
    if (!manifestExplicit) {
      manifestArg = [NSString stringWithFormat:@"db/schema/arlen_schema_%@.json", databaseTarget];
    }
    if (!classPrefixExplicit) {
      classPrefix = [NSString stringWithFormat:@"ALNDB%@", DatabaseTargetPascalSuffix(databaseTarget)];
    }
  }

  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSError *error = nil;
  NSDictionary *config = [ALNConfig loadConfigAtRoot:appRoot environment:environment error:&error];
  if (config == nil) {
    fprintf(stderr, "arlen schema-codegen: failed to load config: %s\n", [[error localizedDescription] UTF8String]);
    return 1;
  }

  NSString *dsn = dsnOverride;
  if ([dsn length] == 0) {
    dsn = DatabaseConnectionStringFromEnvironmentForTarget(databaseTarget);
  }
  if ([dsn length] == 0) {
    dsn = DatabaseConnectionStringFromConfigForTarget(config, databaseTarget);
  }
  if ([dsn length] == 0) {
    fprintf(stderr,
            "arlen schema-codegen: no database connection string configured (set --dsn or "
            "ARLEN_DATABASE_URL[_TARGET] or config.database/config.databases connectionString)\n");
    return 1;
  }

  NSUInteger poolSize = DatabasePoolSizeFromConfigForTarget(config, databaseTarget);
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:poolSize error:&error];
  if (database == nil) {
    fprintf(stderr, "arlen schema-codegen: failed to initialize database adapter: %s\n",
            [[error localizedDescription] UTF8String]);
    return 1;
  }

  NSArray *rows = [ALNDatabaseInspector inspectSchemaColumnsForAdapter:database error:&error];
  if (rows == nil) {
    fprintf(stderr, "arlen schema-codegen: failed schema inspection: %s\n",
            [[error localizedDescription] UTF8String]);
    return 1;
  }

  NSDictionary *artifacts = [ALNSchemaCodegen renderArtifactsFromColumns:rows
                                                              classPrefix:classPrefix
                                                           databaseTarget:databaseTarget
                                                    includeTypedContracts:includeTypedContracts
                                                                    error:&error];
  if (artifacts == nil) {
    fprintf(stderr, "arlen schema-codegen: %s\n", [[error localizedDescription] UTF8String]);
    return 1;
  }

  NSString *outputDir = ResolvePathFromRoot(appRoot, outputDirArg);
  NSString *manifestPath = ResolvePathFromRoot(appRoot, manifestArg);
  NSString *baseName = [artifacts[@"baseName"] isKindOfClass:[NSString class]]
                           ? artifacts[@"baseName"]
                           : @"ALNDBSchema";
  NSString *headerPath = [outputDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.h", baseName]];
  NSString *implementationPath =
      [outputDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m", baseName]];

  if (!WriteTextFile(headerPath, artifacts[@"header"] ?: @"", force, &error)) {
    fprintf(stderr, "arlen schema-codegen: failed writing %s: %s\n",
            [headerPath UTF8String], [[error localizedDescription] UTF8String]);
    return 1;
  }
  if (!WriteTextFile(implementationPath, artifacts[@"implementation"] ?: @"", force, &error)) {
    fprintf(stderr, "arlen schema-codegen: failed writing %s: %s\n",
            [implementationPath UTF8String], [[error localizedDescription] UTF8String]);
    return 1;
  }
  if (!WriteTextFile(manifestPath, artifacts[@"manifest"] ?: @"", force, &error)) {
    fprintf(stderr, "arlen schema-codegen: failed writing %s: %s\n",
            [manifestPath UTF8String], [[error localizedDescription] UTF8String]);
    return 1;
  }

  NSInteger tableCount = [artifacts[@"tableCount"] respondsToSelector:@selector(integerValue)]
                             ? [artifacts[@"tableCount"] integerValue]
                             : 0;
  NSInteger columnCount = [artifacts[@"columnCount"] respondsToSelector:@selector(integerValue)]
                              ? [artifacts[@"columnCount"] integerValue]
                              : 0;
  fprintf(stdout, "Generated typed schema artifacts.\n");
  fprintf(stdout, "  database target: %s\n", [databaseTarget UTF8String]);
  fprintf(stdout, "  typed contracts: %s\n", includeTypedContracts ? "enabled" : "disabled");
  fprintf(stdout, "  tables: %ld\n", (long)tableCount);
  fprintf(stdout, "  columns: %ld\n", (long)columnCount);
  fprintf(stdout, "  header: %s\n", [headerPath UTF8String]);
  fprintf(stdout, "  implementation: %s\n", [implementationPath UTF8String]);
  fprintf(stdout, "  manifest: %s\n", [manifestPath UTF8String]);
  return 0;
}

static int CommandDataverseCodegen(NSArray *args) {
  NSString *environment = @"development";
  NSString *dataverseTarget = @"default";
  NSString *inputArg = nil;
  NSString *serviceRootOverride = nil;
  NSString *tenantIDOverride = nil;
  NSString *clientIDOverride = nil;
  NSString *clientSecretOverride = nil;
  NSString *outputDirArg = @"src/Generated";
  NSString *manifestArg = @"db/schema/dataverse.json";
  NSString *classPrefix = @"ALNDV";
  BOOL outputDirExplicit = NO;
  BOOL manifestExplicit = NO;
  BOOL classPrefixExplicit = NO;
  BOOL force = NO;
  NSMutableArray<NSString *> *logicalNames = [NSMutableArray array];

  for (NSUInteger idx = 0; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--env"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen dataverse-codegen: --env requires a value\n");
        return 2;
      }
      environment = args[++idx];
    } else if ([arg isEqualToString:@"--target"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen dataverse-codegen: --target requires a value\n");
        return 2;
      }
      dataverseTarget = NormalizeDataverseTarget(args[++idx]);
      if (!DataverseTargetIsValid(dataverseTarget)) {
        fprintf(stderr,
                "arlen dataverse-codegen: --target must match [a-z][a-z0-9_]* and be <= 32 characters\n");
        return 2;
      }
    } else if ([arg isEqualToString:@"--input"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen dataverse-codegen: --input requires a value\n");
        return 2;
      }
      inputArg = args[++idx];
    } else if ([arg isEqualToString:@"--service-root"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen dataverse-codegen: --service-root requires a value\n");
        return 2;
      }
      serviceRootOverride = args[++idx];
    } else if ([arg isEqualToString:@"--tenant-id"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen dataverse-codegen: --tenant-id requires a value\n");
        return 2;
      }
      tenantIDOverride = args[++idx];
    } else if ([arg isEqualToString:@"--client-id"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen dataverse-codegen: --client-id requires a value\n");
        return 2;
      }
      clientIDOverride = args[++idx];
    } else if ([arg isEqualToString:@"--client-secret"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen dataverse-codegen: --client-secret requires a value\n");
        return 2;
      }
      clientSecretOverride = args[++idx];
    } else if ([arg isEqualToString:@"--entity"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen dataverse-codegen: --entity requires a value\n");
        return 2;
      }
      [logicalNames addObject:[Trimmed([args[++idx] lowercaseString]) copy]];
    } else if ([arg isEqualToString:@"--output-dir"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen dataverse-codegen: --output-dir requires a value\n");
        return 2;
      }
      outputDirArg = args[++idx];
      outputDirExplicit = YES;
    } else if ([arg isEqualToString:@"--manifest"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen dataverse-codegen: --manifest requires a value\n");
        return 2;
      }
      manifestArg = args[++idx];
      manifestExplicit = YES;
    } else if ([arg isEqualToString:@"--prefix"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen dataverse-codegen: --prefix requires a value\n");
        return 2;
      }
      classPrefix = args[++idx];
      classPrefixExplicit = YES;
    } else if ([arg isEqualToString:@"--force"]) {
      force = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      fprintf(stdout,
              "Usage: arlen dataverse-codegen [--input <metadata.json>] [--env <name>] [--target <name>] "
              "[--service-root <url>] [--tenant-id <id>] [--client-id <id>] [--client-secret <secret>] "
              "[--entity <logical_name>] [--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] "
              "[--force]\n");
      return 0;
    } else {
      fprintf(stderr, "arlen dataverse-codegen: unknown option %s\n", [arg UTF8String]);
      return 2;
    }
  }

  if (![dataverseTarget isEqualToString:@"default"]) {
    if (!outputDirExplicit) {
      outputDirArg = [NSString stringWithFormat:@"src/Generated/%@", dataverseTarget];
    }
    if (!manifestExplicit) {
      manifestArg = [NSString stringWithFormat:@"db/schema/dataverse_%@.json", dataverseTarget];
    }
    if (!classPrefixExplicit) {
      classPrefix = [NSString stringWithFormat:@"ALNDV%@", DataverseTargetPascalSuffix(dataverseTarget)];
    }
  }

  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputDir = ResolvePathFromRoot(appRoot, outputDirArg);
  NSString *manifestPath = ResolvePathFromRoot(appRoot, manifestArg);
  NSError *error = nil;
  NSDictionary<NSString *, id> *normalizedMetadata = nil;

  if ([Trimmed(inputArg) length] > 0) {
    NSString *inputPath = ResolvePathFromRoot(appRoot, inputArg);
    NSData *data = ALNDataReadFromFile(inputPath, 0, &error);
    if (data == nil) {
      fprintf(stderr, "arlen dataverse-codegen: failed reading %s: %s\n",
              [inputPath UTF8String], [[error localizedDescription] UTF8String]);
      return 1;
    }
    id payload = [ALNJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (payload == nil) {
      fprintf(stderr, "arlen dataverse-codegen: invalid metadata JSON: %s\n",
              [[error localizedDescription] UTF8String]);
      return 1;
    }
    normalizedMetadata = [ALNDataverseMetadata normalizedMetadataFromPayload:payload error:&error];
    if (normalizedMetadata == nil) {
      fprintf(stderr, "arlen dataverse-codegen: %s\n", [[error localizedDescription] UTF8String]);
      return 1;
    }
  } else {
    NSDictionary *config = [ALNConfig loadConfigAtRoot:appRoot environment:environment error:&error];
    if (config == nil) {
      fprintf(stderr, "arlen dataverse-codegen: failed to load config: %s\n",
              [[error localizedDescription] UTF8String]);
      return 1;
    }

    NSDictionary *overrides = @{
      @"serviceRootURL" : serviceRootOverride ?: @"",
      @"tenantID" : tenantIDOverride ?: @"",
      @"clientID" : clientIDOverride ?: @"",
      @"clientSecret" : clientSecretOverride ?: @"",
    };
    ALNDataverseTarget *target = DataverseTargetForCommand(config, dataverseTarget, overrides, &error);
    if (target == nil) {
      fprintf(stderr,
              "arlen dataverse-codegen: Dataverse credentials are missing (set --service-root/--tenant-id/--client-id/--client-secret or config.dataverse/config.dataverseTargets or ARLEN_DATAVERSE_* env vars): %s\n",
              [[error localizedDescription] UTF8String]);
      return 1;
    }

    ALNDataverseClient *client = [[ALNDataverseClient alloc] initWithTarget:target error:&error];
    if (client == nil) {
      fprintf(stderr, "arlen dataverse-codegen: failed to initialize Dataverse client: %s\n",
              [[error localizedDescription] UTF8String]);
      return 1;
    }

    normalizedMetadata = [ALNDataverseMetadata fetchNormalizedMetadataWithClient:client
                                                                    logicalNames:logicalNames
                                                                           error:&error];
    if (normalizedMetadata == nil) {
      fprintf(stderr, "arlen dataverse-codegen: failed metadata fetch: %s\n",
              [[error localizedDescription] UTF8String]);
      return 1;
    }
  }

  NSDictionary<NSString *, id> *artifacts =
      [ALNDataverseCodegen renderArtifactsFromMetadata:normalizedMetadata
                                           classPrefix:classPrefix
                                       dataverseTarget:dataverseTarget
                                                 error:&error];
  if (artifacts == nil) {
    fprintf(stderr, "arlen dataverse-codegen: %s\n", [[error localizedDescription] UTF8String]);
    return 1;
  }

  NSString *baseName = [artifacts[@"baseName"] isKindOfClass:[NSString class]] ? artifacts[@"baseName"] : @"ALNDVDataverseSchema";
  NSString *headerPath = [outputDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.h", baseName]];
  NSString *implementationPath =
      [outputDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m", baseName]];

  if (!WriteTextFile(headerPath, artifacts[@"header"] ?: @"", force, &error)) {
    fprintf(stderr, "arlen dataverse-codegen: failed writing %s: %s\n",
            [headerPath UTF8String], [[error localizedDescription] UTF8String]);
    return 1;
  }
  if (!WriteTextFile(implementationPath, artifacts[@"implementation"] ?: @"", force, &error)) {
    fprintf(stderr, "arlen dataverse-codegen: failed writing %s: %s\n",
            [implementationPath UTF8String], [[error localizedDescription] UTF8String]);
    return 1;
  }
  if (!WriteTextFile(manifestPath, artifacts[@"manifest"] ?: @"", force, &error)) {
    fprintf(stderr, "arlen dataverse-codegen: failed writing %s: %s\n",
            [manifestPath UTF8String], [[error localizedDescription] UTF8String]);
    return 1;
  }

  NSInteger entityCount = [artifacts[@"entityCount"] respondsToSelector:@selector(integerValue)]
                              ? [artifacts[@"entityCount"] integerValue]
                              : 0;
  NSInteger attributeCount = [artifacts[@"attributeCount"] respondsToSelector:@selector(integerValue)]
                                 ? [artifacts[@"attributeCount"] integerValue]
                                 : 0;
  fprintf(stdout, "Generated Dataverse artifacts.\n");
  fprintf(stdout, "  dataverse target: %s\n", [dataverseTarget UTF8String]);
  fprintf(stdout, "  entities: %ld\n", (long)entityCount);
  fprintf(stdout, "  attributes: %ld\n", (long)attributeCount);
  fprintf(stdout, "  header: %s\n", [headerPath UTF8String]);
  fprintf(stdout, "  implementation: %s\n", [implementationPath UTF8String]);
  fprintf(stdout, "  manifest: %s\n", [manifestPath UTF8String]);
  return 0;
}

static int CommandMigrate(NSArray *args) {
  NSString *environment = @"development";
  NSString *databaseTarget = @"default";
  NSString *dsnOverride = nil;
  BOOL dryRun = NO;

  for (NSUInteger idx = 0; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--env"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen migrate: --env requires a value\n");
        return 2;
      }
      environment = args[++idx];
    } else if ([arg isEqualToString:@"--dsn"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen migrate: --dsn requires a value\n");
        return 2;
      }
      dsnOverride = args[++idx];
    } else if ([arg isEqualToString:@"--database"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen migrate: --database requires a value\n");
        return 2;
      }
      databaseTarget = NormalizeDatabaseTarget(args[++idx]);
      if (!DatabaseTargetIsValid(databaseTarget)) {
        fprintf(stderr,
                "arlen migrate: --database must match [a-z][a-z0-9_]* and be <= 32 characters\n");
        return 2;
      }
    } else if ([arg isEqualToString:@"--dry-run"]) {
      dryRun = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      fprintf(stdout,
              "Usage: arlen migrate [--env <name>] [--database <target>] [--dsn <connection_string>] [--dry-run]\n");
      return 0;
    } else {
      fprintf(stderr, "arlen migrate: unknown option %s\n", [arg UTF8String]);
      return 2;
    }
  }

  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSError *error = nil;
  NSDictionary *config = [ALNConfig loadConfigAtRoot:appRoot environment:environment error:&error];
  if (config == nil) {
    fprintf(stderr, "arlen migrate: failed to load config: %s\n", [[error localizedDescription] UTF8String]);
    return 1;
  }

  NSString *dsn = dsnOverride;
  if ([dsn length] == 0) {
    dsn = DatabaseConnectionStringFromEnvironmentForTarget(databaseTarget);
  }
  if ([dsn length] == 0) {
    dsn = DatabaseConnectionStringFromConfigForTarget(config, databaseTarget);
  }
  if ([dsn length] == 0) {
    fprintf(stderr,
            "arlen migrate: no database connection string configured (set --dsn or "
            "ARLEN_DATABASE_URL[_TARGET] or config.database/config.databases connectionString)\n");
    return 1;
  }

  id<ALNDatabaseAdapter> database =
      DatabaseAdapterForTarget(config, databaseTarget, dsn, &error);
  if (database == nil) {
    fprintf(stderr, "arlen migrate: failed to initialize database adapter: %s\n",
            [[error localizedDescription] UTF8String]);
    return 1;
  }

  NSString *migrationsPath = [appRoot stringByAppendingPathComponent:@"db/migrations"];
  if (![databaseTarget isEqualToString:@"default"]) {
    migrationsPath = [migrationsPath stringByAppendingPathComponent:databaseTarget];
  }
  NSArray *files = nil;
  BOOL ok = [ALNMigrationRunner applyMigrationsAtPath:migrationsPath
                                             database:database
                                       databaseTarget:databaseTarget
                                               dryRun:dryRun
                                         appliedFiles:&files
                                                error:&error];
  if (!ok) {
    fprintf(stderr, "arlen migrate: %s\n", [[error localizedDescription] UTF8String]);
    NSString *detail =
        [error.userInfo[@"detail"] isKindOfClass:[NSString class]] ? error.userInfo[@"detail"] : @"";
    if ([detail length] > 0) {
      fprintf(stderr, "detail: %s\n", [detail UTF8String]);
    }
    return 1;
  }

  if (dryRun) {
    fprintf(stdout, "Database target: %s\n", [databaseTarget UTF8String]);
    fprintf(stdout, "Pending migrations: %lu\n", (unsigned long)[files count]);
    for (NSString *file in files) {
      fprintf(stdout, "  %s\n", [[file lastPathComponent] UTF8String]);
    }
    return 0;
  }

  fprintf(stdout, "Database target: %s\n", [databaseTarget UTF8String]);
  fprintf(stdout, "Applied migrations: %lu\n", (unsigned long)[files count]);
  for (NSString *file in files) {
    fprintf(stdout, "  %s\n", [[file lastPathComponent] UTF8String]);
  }
  return 0;
}

static int CommandModuleAddOrUpgrade(NSArray *args, BOOL upgradeMode) {
  BOOL asJSON = ArgsContainFlag(args, @"--json");
  NSString *name = nil;
  NSString *sourceOption = nil;
  BOOL force = NO;

  for (NSUInteger idx = 0; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--source"]) {
      if (idx + 1 >= [args count]) {
        return asJSON ? EmitMachineError(@"module", upgradeMode ? @"upgrade" : @"add",
                                         @"missing_source",
                                         @"arlen module: --source requires a value",
                                         @"Pass a local module directory after --source.",
                                         @"arlen module add auth --source ../auth --json", 2)
                      : 2;
      }
      sourceOption = args[++idx];
    } else if ([arg isEqualToString:@"--force"]) {
      force = YES;
    } else if ([arg isEqualToString:@"--json"]) {
      asJSON = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      PrintModuleUsage();
      return 0;
    } else if ([arg hasPrefix:@"-"]) {
      return asJSON ? EmitMachineError(@"module", upgradeMode ? @"upgrade" : @"add",
                                       @"unknown_option",
                                       [NSString stringWithFormat:@"arlen module: unknown option %@", arg ?: @""],
                                       @"Use only supported flags for this subcommand.",
                                       @"arlen module add auth --source ../auth --json", 2)
                    : 2;
    } else if (name == nil) {
      name = arg;
    } else {
      return asJSON ? EmitMachineError(@"module", upgradeMode ? @"upgrade" : @"add",
                                       @"unexpected_argument",
                                       [NSString stringWithFormat:@"arlen module: unexpected argument %@", arg ?: @""],
                                       @"Pass only one module name.",
                                       @"arlen module add auth --source ../auth --json", 2)
                    : 2;
    }
  }

  if ([name length] == 0) {
    return asJSON ? EmitMachineError(@"module", upgradeMode ? @"upgrade" : @"add",
                                     @"missing_module_name",
                                     @"arlen module: missing module name",
                                     @"Pass the module name immediately after the subcommand.",
                                     @"arlen module add auth --source ../auth --json", 2)
                  : 2;
  }
  if (upgradeMode && [Trimmed(sourceOption) length] == 0) {
    return asJSON ? EmitMachineError(@"module", @"upgrade",
                                     @"missing_source",
                                     @"arlen module upgrade: --source is required",
                                     @"Point --source at the upgraded module directory.",
                                     @"arlen module upgrade auth --source ../auth-v2 --json", 2)
                  : 2;
  }

  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *frameworkRoot = EnvValue("ARLEN_FRAMEWORK_ROOT");
  if ([frameworkRoot length] == 0) {
    frameworkRoot = FindFrameworkRoot(appRoot);
  }
  NSString *sourcePath = ResolveModuleSourcePath(appRoot, frameworkRoot ?: @"", name, sourceOption);
  if ([sourcePath length] == 0) {
    return asJSON ? EmitMachineError(@"module", upgradeMode ? @"upgrade" : @"add",
                                     @"module_source_not_found",
                                     [NSString stringWithFormat:@"unable to resolve module source for %@", name ?: @""],
                                     @"Pass --source <path> or set ARLEN_FRAMEWORK_ROOT to a checkout containing modules/<name>.",
                                     @"arlen module add auth --source ../auth --json", 1)
                  : 1;
  }

  NSError *error = nil;
  ALNModuleDefinition *definition = [ALNModuleSystem moduleDefinitionAtPath:sourcePath error:&error];
  if (definition == nil) {
    if (asJSON) {
      return EmitMachineError(@"module", upgradeMode ? @"upgrade" : @"add",
                              @"module_manifest_invalid",
                              error.localizedDescription ?: @"invalid module manifest",
                              @"Fix module.plist before installing the module.",
                              @"arlen module add auth --source ../auth --json", 1);
    }
    fprintf(stderr, "arlen module: %s\n", [[error localizedDescription] UTF8String]);
    return 1;
  }

  NSMutableArray<NSDictionary *> *entries = MutableModuleLockEntriesAtAppRoot(appRoot, &error);
  if (entries == nil) {
    if (asJSON) {
      return EmitMachineError(@"module", upgradeMode ? @"upgrade" : @"add",
                              @"module_lock_invalid",
                              error.localizedDescription ?: @"invalid modules lock",
                              @"Fix config/modules.plist or remove it and retry.",
                              @"rm -f config/modules.plist && arlen module add auth --source ../auth --json", 1);
    }
    fprintf(stderr, "arlen module: %s\n", [[error localizedDescription] UTF8String]);
    return 1;
  }

  NSString *relativeInstallPath = [NSString stringWithFormat:@"modules/%@", definition.identifier ?: @""];
  NSString *destinationPath = [appRoot stringByAppendingPathComponent:relativeInstallPath];
  NSInteger existingIndex = ModuleLockEntryIndex(entries, definition.identifier);
  NSString *status = @"ok";

  if (upgradeMode && existingIndex < 0) {
    return asJSON ? EmitMachineError(@"module", @"upgrade",
                                     @"module_not_installed",
                                     [NSString stringWithFormat:@"module %@ is not installed", definition.identifier ?: @""],
                                     @"Install the module first with `arlen module add`.",
                                     [NSString stringWithFormat:@"arlen module add %@ --source %@ --json",
                                                                definition.identifier ?: @"",
                                                                sourcePath ?: @""], 1)
                  : 1;
  }
  if (!upgradeMode && existingIndex >= 0) {
    NSDictionary *existing = entries[(NSUInteger)existingIndex];
    if ([[Trimmed(existing[@"version"]) lowercaseString] isEqualToString:[[definition.version lowercaseString] copy]]) {
      status = @"noop";
    } else if (!force) {
      return asJSON ? EmitMachineError(@"module", @"add",
                                       @"module_already_installed",
                                       [NSString stringWithFormat:@"module %@ is already installed", definition.identifier ?: @""],
                                       @"Use `arlen module upgrade` or re-run with --force to replace the vendored files.",
                                       [NSString stringWithFormat:@"arlen module upgrade %@ --source %@ --json",
                                                                  definition.identifier ?: @"",
                                                                  sourcePath ?: @""], 1)
                    : 1;
    } else {
      status = @"replaced";
    }
  }
  if (upgradeMode && existingIndex >= 0) {
    NSDictionary *existing = entries[(NSUInteger)existingIndex];
    if ([Trimmed(existing[@"version"]) isEqualToString:definition.version] && !force) {
      status = @"noop";
    } else {
      status = @"updated";
    }
  }

  if (![status isEqualToString:@"noop"]) {
    if (!RemoveItemIfExists(destinationPath, &error)) {
      if (asJSON) {
        return EmitMachineError(@"module", upgradeMode ? @"upgrade" : @"add",
                                @"module_remove_failed",
                                error.localizedDescription ?: @"failed removing existing module directory",
                                @"Inspect file permissions and retry.",
                                @"ls -la modules", 1);
      }
      fprintf(stderr, "arlen module: %s\n", [[error localizedDescription] UTF8String]);
      return 1;
    }
    if (!CopyDirectoryTree(sourcePath, destinationPath, &error)) {
      if (asJSON) {
        return EmitMachineError(@"module", upgradeMode ? @"upgrade" : @"add",
                                @"module_copy_failed",
                                error.localizedDescription ?: @"failed copying module into app",
                                @"Inspect source and destination permissions, then retry.",
                                @"ls -la modules", 1);
      }
      fprintf(stderr, "arlen module: %s\n", [[error localizedDescription] UTF8String]);
      return 1;
    }
  }

  NSDictionary *lockEntry = ModuleLockEntryForDefinition(definition, relativeInstallPath);
  if (existingIndex >= 0) {
    entries[(NSUInteger)existingIndex] = lockEntry;
  } else {
    [entries addObject:lockEntry];
  }
  if (!WriteModuleLockEntriesAtAppRoot(appRoot, entries, &error)) {
    if (asJSON) {
      return EmitMachineError(@"module", upgradeMode ? @"upgrade" : @"add",
                              @"module_lock_write_failed",
                              error.localizedDescription ?: @"failed writing modules lock",
                              @"Fix config/ permissions and retry.",
                              @"mkdir -p config", 1);
    }
    fprintf(stderr, "arlen module: %s\n", [[error localizedDescription] UTF8String]);
    return 1;
  }

  if (asJSON) {
    NSDictionary *payload = @{
      @"version" : AgentContractVersion(),
      @"command" : @"module",
      @"workflow" : upgradeMode ? @"upgrade" : @"add",
      @"status" : status,
      @"module" : ModuleJSONDictionary(definition, relativeInstallPath, status),
    };
    PrintJSONPayload(stdout, payload);
    return 0;
  }

  fprintf(stdout, "%s module %s at %s\n",
          upgradeMode ? "Upgraded" : "Installed",
          [definition.identifier UTF8String],
          [relativeInstallPath UTF8String]);
  return 0;
}

static int CommandModuleRemove(NSArray *args) {
  BOOL asJSON = ArgsContainFlag(args, @"--json");
  NSString *name = nil;
  BOOL keepFiles = NO;

  for (NSUInteger idx = 0; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--keep-files"]) {
      keepFiles = YES;
    } else if ([arg isEqualToString:@"--json"]) {
      asJSON = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      PrintModuleUsage();
      return 0;
    } else if ([arg hasPrefix:@"-"]) {
      return asJSON ? EmitMachineError(@"module", @"remove", @"unknown_option",
                                       [NSString stringWithFormat:@"unknown option %@", arg ?: @""],
                                       @"Use only supported flags for `arlen module remove`.",
                                       @"arlen module remove auth --json", 2)
                    : 2;
    } else if (name == nil) {
      name = arg;
    } else {
      return 2;
    }
  }

  if ([name length] == 0) {
    return asJSON ? EmitMachineError(@"module", @"remove", @"missing_module_name",
                                     @"arlen module remove: missing module name",
                                     @"Pass the installed module identifier after `remove`.",
                                     @"arlen module remove auth --json", 2)
                  : 2;
  }

  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSError *error = nil;
  NSMutableArray<NSDictionary *> *entries = MutableModuleLockEntriesAtAppRoot(appRoot, &error);
  if (entries == nil) {
    return asJSON ? EmitMachineError(@"module", @"remove", @"module_lock_invalid",
                                     error.localizedDescription ?: @"invalid modules lock",
                                     @"Fix config/modules.plist and retry.",
                                     @"arlen module list --json", 1)
                  : 1;
  }

  NSInteger index = ModuleLockEntryIndex(entries, name);
  NSString *status = @"noop";
  NSDictionary *removedEntry = nil;
  if (index >= 0) {
    removedEntry = entries[(NSUInteger)index];
    [entries removeObjectAtIndex:(NSUInteger)index];
    status = @"ok";
  }

  if (![status isEqualToString:@"noop"] &&
      !WriteModuleLockEntriesAtAppRoot(appRoot, entries, &error)) {
    return asJSON ? EmitMachineError(@"module", @"remove", @"module_lock_write_failed",
                                     error.localizedDescription ?: @"failed writing modules lock",
                                     @"Fix config/ permissions and retry.",
                                     @"arlen module list --json", 1)
                  : 1;
  }

  if (![status isEqualToString:@"noop"] && !keepFiles) {
    NSString *relativePath = Trimmed(removedEntry[@"path"]);
    if ([relativePath length] == 0) {
      relativePath = [NSString stringWithFormat:@"modules/%@", name];
    }
    NSString *absolutePath = [appRoot stringByAppendingPathComponent:relativePath];
    if (!RemoveItemIfExists(absolutePath, &error)) {
      return asJSON ? EmitMachineError(@"module", @"remove", @"module_remove_failed",
                                       error.localizedDescription ?: @"failed removing vendored module files",
                                       @"Inspect file permissions and retry.",
                                       @"ls -la modules", 1)
                    : 1;
    }
  }

  if (asJSON) {
    NSDictionary *payload = @{
      @"version" : AgentContractVersion(),
      @"command" : @"module",
      @"workflow" : @"remove",
      @"status" : status,
      @"module" : @{
        @"identifier" : name ?: @"",
        @"keepFiles" : @(keepFiles),
      },
    };
    PrintJSONPayload(stdout, payload);
    return 0;
  }

  fprintf(stdout, "%s module %s\n",
          [status isEqualToString:@"noop"] ? "No-op for" : "Removed",
          [name UTF8String]);
  return 0;
}

static int CommandModuleList(NSArray *args) {
  BOOL asJSON = ArgsContainFlag(args, @"--json");
  for (NSString *arg in args) {
    if ([arg isEqualToString:@"--json"]) {
      continue;
    }
    if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      PrintModuleUsage();
      return 0;
    }
    return 2;
  }

  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSError *error = nil;
  NSArray<ALNModuleDefinition *> *definitions = [ALNModuleSystem moduleDefinitionsAtAppRoot:appRoot error:&error];
  if (definitions == nil) {
    return asJSON ? EmitMachineError(@"module", @"list", @"module_manifest_invalid",
                                     error.localizedDescription ?: @"invalid module state",
                                     @"Fix the modules lock or installed module manifests and retry.",
                                     @"arlen module doctor --json", 1)
                  : 1;
  }

  NSMutableArray *modules = [NSMutableArray array];
  for (ALNModuleDefinition *definition in definitions) {
    [modules addObject:[definition dictionaryRepresentation]];
  }
  [modules sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    return [left[@"identifier"] compare:right[@"identifier"]];
  }];

  if (asJSON) {
    NSDictionary *payload = @{
      @"version" : AgentContractVersion(),
      @"command" : @"module",
      @"workflow" : @"list",
      @"status" : @"ok",
      @"modules" : modules ?: @[],
    };
    PrintJSONPayload(stdout, payload);
    return 0;
  }

  fprintf(stdout, "Installed modules: %lu\n", (unsigned long)[modules count]);
  for (NSDictionary *entry in modules) {
    fprintf(stdout, "  %s %s\n",
            [entry[@"identifier"] UTF8String],
            [entry[@"version"] UTF8String]);
  }
  return 0;
}

static int CommandModuleDoctor(NSArray *args) {
  BOOL asJSON = ArgsContainFlag(args, @"--json");
  NSString *environment = @"development";

  for (NSUInteger idx = 0; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--env"]) {
      if (idx + 1 >= [args count]) {
        return asJSON ? EmitMachineError(@"module", @"doctor", @"missing_env",
                                         @"arlen module doctor: --env requires a value",
                                         @"Pass an environment name after --env.",
                                         @"arlen module doctor --env production --json", 2)
                      : 2;
      }
      environment = args[++idx];
    } else if ([arg isEqualToString:@"--json"]) {
      asJSON = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      PrintModuleUsage();
      return 0;
    } else {
      return 2;
    }
  }

  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSError *error = nil;
  NSDictionary *rawConfig = LoadRawConfigForModuleCommand(appRoot, environment, &error);
  if (rawConfig == nil) {
    return asJSON ? EmitMachineError(@"module", @"doctor", @"config_load_failed",
                                     error.localizedDescription ?: @"failed loading config",
                                     @"Fix malformed plist values or the requested environment file.",
                                     @"arlen config --env development --json", 1)
                  : 1;
  }

  NSArray<NSDictionary *> *diagnostics =
      [ALNModuleSystem doctorDiagnosticsAtAppRoot:appRoot config:rawConfig error:&error];
  BOOL hasErrors = NO;
  for (NSDictionary *entry in diagnostics ?: @[]) {
    if ([entry[@"status"] isEqualToString:@"error"]) {
      hasErrors = YES;
      break;
    }
  }

  if (asJSON) {
    NSDictionary *payload = @{
      @"version" : AgentContractVersion(),
      @"command" : @"module",
      @"workflow" : @"doctor",
      @"status" : hasErrors ? @"error" : @"ok",
      @"environment" : environment ?: @"development",
      @"diagnostics" : diagnostics ?: @[],
    };
    PrintJSONPayload(stdout, payload);
    return hasErrors ? 1 : 0;
  }

  fprintf(stdout, "Module doctor (%s)\n", [environment UTF8String]);
  for (NSDictionary *entry in diagnostics ?: @[]) {
    fprintf(stdout, "  [%s] %s\n",
            [entry[@"status"] UTF8String],
            [entry[@"message"] UTF8String]);
  }
  return hasErrors ? 1 : 0;
}

static int CommandModuleAssets(NSArray *args) {
  BOOL asJSON = ArgsContainFlag(args, @"--json");
  NSString *outputDirArg = @"build/module_assets";

  for (NSUInteger idx = 0; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--output-dir"]) {
      if (idx + 1 >= [args count]) {
        return asJSON ? EmitMachineError(@"module", @"assets", @"missing_output_dir",
                                         @"arlen module assets: --output-dir requires a value",
                                         @"Pass a staging directory after --output-dir.",
                                         @"arlen module assets --output-dir build/module_assets --json", 2)
                      : 2;
      }
      outputDirArg = args[++idx];
    } else if ([arg isEqualToString:@"--json"]) {
      asJSON = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      PrintModuleUsage();
      return 0;
    } else {
      return 2;
    }
  }

  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputDir = ResolvePathFromRoot(appRoot, outputDirArg);
  NSError *error = nil;
  NSArray<NSString *> *stagedFiles = nil;
  BOOL ok = [ALNModuleSystem stagePublicAssetsAtAppRoot:appRoot
                                              outputDir:outputDir
                                            stagedFiles:&stagedFiles
                                                  error:&error];
  if (!ok) {
    return asJSON ? EmitMachineError(@"module", @"assets", @"module_asset_stage_failed",
                                     error.localizedDescription ?: @"failed staging module assets",
                                     @"Inspect module public directories and retry.",
                                     @"arlen module doctor --json", 1)
                  : 1;
  }

  if (asJSON) {
    NSDictionary *payload = @{
      @"version" : AgentContractVersion(),
      @"command" : @"module",
      @"workflow" : @"assets",
      @"status" : @"ok",
      @"output_dir" : outputDir ?: @"",
      @"staged_files" : stagedFiles ?: @[],
    };
    PrintJSONPayload(stdout, payload);
    return 0;
  }

  fprintf(stdout, "Staged module assets: %lu\n", (unsigned long)[stagedFiles count]);
  fprintf(stdout, "  output: %s\n", [outputDir UTF8String]);
  return 0;
}

static int CommandModuleEject(NSArray *args) {
  BOOL asJSON = ArgsContainFlag(args, @"--json");
  BOOL force = NO;
  NSString *target = nil;

  for (NSUInteger idx = 0; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--force"]) {
      force = YES;
    } else if ([arg isEqualToString:@"--json"]) {
      asJSON = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      PrintModuleUsage();
      return 0;
    } else if ([arg hasPrefix:@"-"]) {
      return asJSON ? EmitMachineError(@"module", @"eject", @"unknown_option",
                                       [NSString stringWithFormat:@"unknown option %@", arg ?: @""],
                                       @"Use only supported flags for `arlen module eject`.",
                                       @"arlen module eject auth-ui --json", 2)
                    : 2;
    } else if (target == nil) {
      target = arg;
    } else {
      return asJSON ? EmitMachineError(@"module", @"eject", @"unexpected_argument",
                                       [NSString stringWithFormat:@"unexpected argument %@", arg ?: @""],
                                       @"Pass only one eject target.",
                                       @"arlen module eject auth-ui --json", 2)
                    : 2;
    }
  }

  if (![target isEqualToString:@"auth-ui"]) {
    return asJSON ? EmitMachineError(@"module", @"eject", @"unsupported_target",
                                     @"arlen module eject currently supports only `auth-ui`",
                                     @"Use `arlen module eject auth-ui`.",
                                     @"arlen module eject auth-ui --json", 2)
                  : 2;
  }

  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *frameworkRoot = EnvValue("ARLEN_FRAMEWORK_ROOT");
  if ([frameworkRoot length] == 0) {
    frameworkRoot = FindFrameworkRoot(appRoot);
  }
  NSString *moduleRoot = [appRoot stringByAppendingPathComponent:@"modules/auth"];
  BOOL isDirectory = NO;
  if (![[NSFileManager defaultManager] fileExistsAtPath:moduleRoot isDirectory:&isDirectory] || !isDirectory) {
    moduleRoot = ResolveModuleSourcePath(appRoot, frameworkRoot ?: @"", @"auth", nil);
  }
  if ([moduleRoot length] == 0) {
    return asJSON ? EmitMachineError(@"module", @"eject", @"module_source_not_found",
                                     @"unable to resolve auth module source for auth-ui eject",
                                     @"Install the auth module first or set ARLEN_FRAMEWORK_ROOT.",
                                     @"arlen module add auth --json", 1)
                  : 1;
  }

  NSArray<NSDictionary *> *mappings = @[
    @{
      @"source" : @"Resources/Templates/login/index.html.eoc",
      @"destination" : @"templates/auth/login.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/register/index.html.eoc",
      @"destination" : @"templates/auth/register.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/password/forgot.html.eoc",
      @"destination" : @"templates/auth/password/forgot.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/password/reset.html.eoc",
      @"destination" : @"templates/auth/password/reset.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/mfa/manage.html.eoc",
      @"destination" : @"templates/auth/mfa/manage.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/mfa/sms.html.eoc",
      @"destination" : @"templates/auth/mfa/sms.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/mfa/totp.html.eoc",
      @"destination" : @"templates/auth/mfa/totp.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/mfa/totp_enrollment.html.eoc",
      @"destination" : @"templates/auth/mfa/totp_enrollment.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/mfa/totp_recovery_codes.html.eoc",
      @"destination" : @"templates/auth/mfa/totp_recovery_codes.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/result/index.html.eoc",
      @"destination" : @"templates/auth/result.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/page_wrapper.html.eoc",
      @"destination" : @"templates/auth/partials/page_wrapper.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/message_block.html.eoc",
      @"destination" : @"templates/auth/partials/message_block.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/error_block.html.eoc",
      @"destination" : @"templates/auth/partials/error_block.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/form_shell.html.eoc",
      @"destination" : @"templates/auth/partials/form_shell.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/field_row.html.eoc",
      @"destination" : @"templates/auth/partials/field_row.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/provider_row.html.eoc",
      @"destination" : @"templates/auth/partials/provider_row.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/result_actions.html.eoc",
      @"destination" : @"templates/auth/partials/result_actions.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/fragments/provider_login_buttons.html.eoc",
      @"destination" : @"templates/auth/fragments/provider_login_buttons.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/fragments/mfa_factor_inventory_panel.html.eoc",
      @"destination" : @"templates/auth/fragments/mfa_factor_inventory_panel.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/fragments/mfa_enrollment_panel.html.eoc",
      @"destination" : @"templates/auth/fragments/mfa_enrollment_panel.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/fragments/mfa_challenge_form.html.eoc",
      @"destination" : @"templates/auth/fragments/mfa_challenge_form.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/fragments/mfa_sms_enrollment_panel.html.eoc",
      @"destination" : @"templates/auth/fragments/mfa_sms_enrollment_panel.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/fragments/mfa_sms_challenge_form.html.eoc",
      @"destination" : @"templates/auth/fragments/mfa_sms_challenge_form.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/fragments/mfa_recovery_codes_panel.html.eoc",
      @"destination" : @"templates/auth/fragments/mfa_recovery_codes_panel.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/bodies/login_body.html.eoc",
      @"destination" : @"templates/auth/partials/bodies/login_body.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/bodies/register_body.html.eoc",
      @"destination" : @"templates/auth/partials/bodies/register_body.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/bodies/forgot_password_body.html.eoc",
      @"destination" : @"templates/auth/partials/bodies/forgot_password_body.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/bodies/reset_password_body.html.eoc",
      @"destination" : @"templates/auth/partials/bodies/reset_password_body.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/bodies/mfa_manage_body.html.eoc",
      @"destination" : @"templates/auth/partials/bodies/mfa_manage_body.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/bodies/sms_challenge_body.html.eoc",
      @"destination" : @"templates/auth/partials/bodies/sms_challenge_body.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/bodies/totp_enrollment_body.html.eoc",
      @"destination" : @"templates/auth/partials/bodies/totp_enrollment_body.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/bodies/totp_challenge_body.html.eoc",
      @"destination" : @"templates/auth/partials/bodies/totp_challenge_body.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/bodies/totp_recovery_codes_body.html.eoc",
      @"destination" : @"templates/auth/partials/bodies/totp_recovery_codes_body.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/partials/bodies/result_body.html.eoc",
      @"destination" : @"templates/auth/partials/bodies/result_body.html.eoc",
    },
    @{
      @"source" : @"Resources/Templates/layouts/main.html.eoc",
      @"destination" : @"templates/layouts/auth_generated.html.eoc",
    },
    @{
      @"source" : @"Resources/Public/auth.css",
      @"destination" : @"public/auth/auth.css",
    },
    @{
      @"source" : @"Resources/Public/auth_totp_qr.js",
      @"destination" : @"public/auth/auth_totp_qr.js",
    },
  ];

  NSMutableArray *createdFiles = [NSMutableArray array];
  NSMutableArray *updatedFiles = [NSMutableArray array];
  NSError *error = nil;
  for (NSDictionary *mapping in mappings) {
    NSString *sourcePath = [moduleRoot stringByAppendingPathComponent:mapping[@"source"] ?: @""];
    NSString *destinationPath = [appRoot stringByAppendingPathComponent:mapping[@"destination"] ?: @""];
    NSString *status = nil;
    if (!CopyUTF8TextFile(sourcePath, destinationPath, force, &status, &error)) {
      return asJSON ? EmitMachineError(@"module", @"eject", @"file_copy_failed",
                                       error.localizedDescription ?: @"failed copying auth-ui scaffold file",
                                       @"Use --force to overwrite existing files or remove conflicting files.",
                                       @"arlen module eject auth-ui --force --json", 1)
                    : 1;
    }
    NSString *relative = RelativePathFromRoot(appRoot, destinationPath);
    if ([status isEqualToString:@"updated"]) {
      [updatedFiles addObject:relative ?: destinationPath];
    } else {
      [createdFiles addObject:relative ?: destinationPath];
    }
  }

  if (!ConfigureGeneratedAuthUIAtAppRoot(appRoot, @"layouts/auth_generated", @"auth", &error)) {
    return asJSON ? EmitMachineError(@"module", @"eject", @"config_update_failed",
                                     error.localizedDescription ?: @"failed updating config/app.plist",
                                     @"Inspect config/app.plist and retry.",
                                     @"arlen module eject auth-ui --json", 1)
                  : 1;
  }
  [updatedFiles addObject:@"config/app.plist"];

  NSArray *nextSteps = @[
    @"Edit templates/auth/... to own the auth presentation while keeping the module backend routes.",
    @"Run boomhauer and verify /auth/login still boots under generated-app-ui mode.",
    @"Adjust authModule.ui.layout if you want a different app-owned guest shell.",
  ];

  if (asJSON) {
    NSDictionary *payload = @{
      @"version" : AgentContractVersion(),
      @"command" : @"module",
      @"workflow" : @"eject",
      @"status" : @"ok",
      @"target" : @"auth-ui",
      @"created_files" : createdFiles ?: @[],
      @"updated_files" : updatedFiles ?: @[],
      @"next_steps" : nextSteps,
    };
    PrintJSONPayload(stdout, payload);
    return 0;
  }

  fprintf(stdout, "Ejected auth-ui templates into the app tree.\n");
  for (NSString *path in createdFiles) {
    fprintf(stdout, "  created %s\n", [path UTF8String]);
  }
  for (NSString *path in updatedFiles) {
    fprintf(stdout, "  updated %s\n", [path UTF8String]);
  }
  return 0;
}

static int CommandModuleMigrate(NSArray *args) {
  BOOL asJSON = ArgsContainFlag(args, @"--json");
  NSString *environment = @"development";
  NSString *databaseTarget = @"default";
  NSString *dsnOverride = nil;
  BOOL dryRun = NO;

  for (NSUInteger idx = 0; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--env"]) {
      if (idx + 1 >= [args count]) {
        return 2;
      }
      environment = args[++idx];
    } else if ([arg isEqualToString:@"--dsn"]) {
      if (idx + 1 >= [args count]) {
        return 2;
      }
      dsnOverride = args[++idx];
    } else if ([arg isEqualToString:@"--database"]) {
      if (idx + 1 >= [args count]) {
        return 2;
      }
      databaseTarget = NormalizeDatabaseTarget(args[++idx]);
      if (!DatabaseTargetIsValid(databaseTarget)) {
        return 2;
      }
    } else if ([arg isEqualToString:@"--dry-run"]) {
      dryRun = YES;
    } else if ([arg isEqualToString:@"--json"]) {
      asJSON = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      PrintModuleUsage();
      return 0;
    } else {
      return 2;
    }
  }

  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSError *error = nil;
  NSDictionary *config = [ALNConfig loadConfigAtRoot:appRoot
                                         environment:environment
                                      includeModules:YES
                                               error:&error];
  if (config == nil) {
    return asJSON ? EmitMachineError(@"module", @"migrate", @"config_load_failed",
                                     error.localizedDescription ?: @"failed loading config",
                                     @"Fix config or module validation errors, then retry.",
                                     @"arlen module doctor --env development --json", 1)
                  : 1;
  }

  NSString *dsn = dsnOverride;
  if ([dsn length] == 0) {
    dsn = DatabaseConnectionStringFromEnvironmentForTarget(databaseTarget);
  }
  if ([dsn length] == 0) {
    dsn = DatabaseConnectionStringFromConfigForTarget(config, databaseTarget);
  }
  if ([dsn length] == 0) {
    return asJSON ? EmitMachineError(@"module", @"migrate", @"missing_database_dsn",
                                     @"arlen module migrate: no database connection string configured",
                                     @"Set --dsn or configure database.connectionString.",
                                     @"arlen module migrate --dsn postgres://... --json", 1)
                  : 1;
  }

  id<ALNDatabaseAdapter> database =
      DatabaseAdapterForTarget(config, databaseTarget, dsn, &error);
  if (database == nil) {
    return asJSON ? EmitMachineError(@"module", @"migrate", @"database_init_failed",
                                     error.localizedDescription ?: @"failed initializing database adapter",
                                     @"Check the DSN, configured adapter, and backend transport availability.",
                                     @"arlen module migrate --dsn postgres://... --json", 1)
                  : 1;
  }

  NSArray<NSDictionary *> *plans = [ALNModuleSystem migrationPlansAtAppRoot:appRoot config:config error:&error];
  if (plans == nil) {
    return asJSON ? EmitMachineError(@"module", @"migrate", @"module_migration_plan_failed",
                                     error.localizedDescription ?: @"failed resolving module migration plans",
                                     @"Fix module manifests and retry.",
                                     @"arlen module doctor --json", 1)
                  : 1;
  }

  NSMutableArray<NSDictionary *> *selectedPlans = [NSMutableArray array];
  for (NSDictionary *plan in plans) {
    NSString *planTarget = plan[@"databaseTarget"];
    if ([NormalizeDatabaseTarget(planTarget) isEqualToString:databaseTarget]) {
      [selectedPlans addObject:plan];
    }
  }

  NSMutableArray<NSString *> *applied = [NSMutableArray array];
  for (NSDictionary *plan in selectedPlans) {
    NSString *planPath = plan[@"path"];
    NSString *moduleID = plan[@"identifier"];
    NSString *namespace = plan[@"namespace"];
    NSArray<NSString *> *files = nil;
    BOOL ok = dryRun
                  ? ((files = [ALNMigrationRunner pendingMigrationFilesAtPath:planPath
                                                                      database:database
                                                                databaseTarget:databaseTarget
                                                             versionNamespace:namespace
                                                                         error:&error]) != nil)
                  : [ALNMigrationRunner applyMigrationsAtPath:planPath
                                                     database:database
                                               databaseTarget:databaseTarget
                                            versionNamespace:namespace
                                                       dryRun:NO
                                                 appliedFiles:&files
                                                        error:&error];
    if (!ok) {
      return asJSON ? EmitMachineError(@"module", @"migrate", @"module_migration_failed",
                                       error.localizedDescription ?: @"module migration failed",
                                       @"Inspect the module migration SQL and database state.",
                                       @"arlen module migrate --dry-run --json", 1)
                    : 1;
    }
    for (NSString *file in files ?: @[]) {
      [applied addObject:[NSString stringWithFormat:@"%@:%@", moduleID ?: @"", [file lastPathComponent]]];
    }
  }

  if (asJSON) {
    NSDictionary *payload = @{
      @"version" : AgentContractVersion(),
      @"command" : @"module",
      @"workflow" : @"migrate",
      @"status" : @"ok",
      @"environment" : environment ?: @"development",
      @"database_target" : databaseTarget ?: @"default",
      @"dry_run" : @(dryRun),
      @"plans" : selectedPlans ?: @[],
      @"files" : applied ?: @[],
    };
    PrintJSONPayload(stdout, payload);
    return 0;
  }

  fprintf(stdout, "Database target: %s\n", [databaseTarget UTF8String]);
  fprintf(stdout, "%s module migrations: %lu\n",
          dryRun ? "Pending" : "Applied",
          (unsigned long)[applied count]);
  for (NSString *entry in applied) {
    fprintf(stdout, "  %s\n", [entry UTF8String]);
  }
  return 0;
}

static int CommandModule(NSArray *args) {
  if ([args count] == 0) {
    PrintModuleUsage();
    return 2;
  }
  NSString *subcommand = args[0];
  NSArray *subArgs = ([args count] > 1) ? [args subarrayWithRange:NSMakeRange(1, [args count] - 1)] : @[];
  if ([subcommand isEqualToString:@"add"]) {
    return CommandModuleAddOrUpgrade(subArgs, NO);
  }
  if ([subcommand isEqualToString:@"remove"]) {
    return CommandModuleRemove(subArgs);
  }
  if ([subcommand isEqualToString:@"list"]) {
    return CommandModuleList(subArgs);
  }
  if ([subcommand isEqualToString:@"doctor"]) {
    return CommandModuleDoctor(subArgs);
  }
  if ([subcommand isEqualToString:@"migrate"]) {
    return CommandModuleMigrate(subArgs);
  }
  if ([subcommand isEqualToString:@"assets"]) {
    return CommandModuleAssets(subArgs);
  }
  if ([subcommand isEqualToString:@"eject"]) {
    return CommandModuleEject(subArgs);
  }
  if ([subcommand isEqualToString:@"upgrade"]) {
    return CommandModuleAddOrUpgrade(subArgs, YES);
  }
  PrintModuleUsage();
  return 2;
}

static NSArray<NSString *> *TopLevelCompletionCandidates(void) {
  return @[ @"new", @"generate", @"boomhauer", @"jobs", @"propane", @"deploy", @"completion",
            @"migrate", @"module", @"schema-codegen", @"dataverse-codegen", @"typed-sql-codegen",
            @"typescript-codegen", @"routes", @"test", @"perf", @"check", @"build", @"config", @"doctor" ];
}

static NSArray<NSString *> *DeploySubcommandCompletionCandidates(void) {
  return @[ @"list", @"dryrun", @"init", @"push", @"releases", @"release", @"status",
            @"rollback", @"doctor", @"logs", @"target", @"plan" ];
}

static NSArray<NSString *> *DeployTargetSubcommandCompletionCandidates(void) {
  return @[ @"sample" ];
}

static NSArray<NSString *> *DeployOptionCompletionCandidates(void) {
  return @[ @"--app-root", @"--framework-root", @"--releases-dir", @"--release-id", @"--service",
            @"--base-url", @"--target-profile", @"--runtime-strategy", @"--database-mode",
            @"--database-adapter", @"--database-target", @"--require-env-key",
            @"--allow-remote-rebuild", @"--remote-build-check-command", @"--runtime-restart-command",
            @"--runtime-reload-command", @"--health-startup-timeout", @"--health-startup-interval",
            @"--certification-manifest",
            @"--json-performance-manifest", @"--allow-missing-certification",
            @"--skip-release-certification", @"--dev", @"--json",
            @"--env", @"--skip-migrate", @"--runtime-action", @"--lines", @"--follow", @"--file",
            @"--write", @"--force", @"--target", @"--ssh-host", @"--output" ];
}

static NSString *CompletionScriptBash(void) {
  return @"# bash completion for arlen\n"
         "_arlen_complete() {\n"
         "  local cur prev first second\n"
         "  COMPREPLY=()\n"
         "  cur=\"${COMP_WORDS[COMP_CWORD]}\"\n"
         "  prev=\"${COMP_WORDS[COMP_CWORD-1]}\"\n"
         "  first=\"${COMP_WORDS[1]}\"\n"
         "  second=\"${COMP_WORDS[2]}\"\n"
         "  if [[ $COMP_CWORD -eq 1 ]]; then\n"
         "    COMPREPLY=( $(compgen -W \"$(arlen completion candidates top-level-commands 2>/dev/null)\" -- \"$cur\") )\n"
         "    return 0\n"
         "  fi\n"
         "  if [[ \"$first\" == \"deploy\" ]]; then\n"
         "    if [[ $COMP_CWORD -eq 2 ]]; then\n"
         "      COMPREPLY=( $(compgen -W \"$(arlen completion candidates deploy-subcommands 2>/dev/null)\" -- \"$cur\") )\n"
         "      return 0\n"
         "    fi\n"
         "    if [[ \"$second\" == \"target\" && $COMP_CWORD -eq 3 ]]; then\n"
         "      COMPREPLY=( $(compgen -W \"$(arlen completion candidates deploy-target-subcommands 2>/dev/null)\" -- \"$cur\") )\n"
         "      return 0\n"
         "    fi\n"
         "    if [[ \"$cur\" == --* ]]; then\n"
         "      COMPREPLY=( $(compgen -W \"$(arlen completion candidates deploy-options 2>/dev/null)\" -- \"$cur\") )\n"
         "      return 0\n"
         "    fi\n"
         "    if [[ \"$prev\" == \"--release-id\" ]]; then\n"
         "      local target_name=\"\"\n"
         "      local i word previous\n"
         "      for (( i=3; i<COMP_CWORD; i++ )); do\n"
         "        word=\"${COMP_WORDS[i]}\"\n"
         "        previous=\"${COMP_WORDS[i-1]}\"\n"
         "        if [[ \"$word\" != --* && \"$previous\" != --* ]]; then target_name=\"$word\"; break; fi\n"
         "      done\n"
         "      COMPREPLY=( $(compgen -W \"$(arlen completion candidates deploy-release-ids --target \"$target_name\" 2>/dev/null)\" -- \"$cur\") )\n"
         "      return 0\n"
         "    fi\n"
         "    COMPREPLY=( $(compgen -W \"$(arlen completion candidates deploy-targets 2>/dev/null)\" -- \"$cur\") )\n"
         "    return 0\n"
         "  fi\n"
         "}\n"
         "complete -F _arlen_complete arlen\n";
}

static NSString *CompletionScriptPowerShell(void) {
  return @"# PowerShell completion for arlen\n"
         "Register-ArgumentCompleter -CommandName arlen -ScriptBlock {\n"
         "  param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)\n"
         "  $line = $commandAst.ToString()\n"
         "  $words = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })\n"
         "  $candidates = @()\n"
         "  if ($words.Count -le 1) {\n"
         "    $candidates = arlen completion candidates top-level-commands 2>$null\n"
         "  } elseif ($words[1] -eq 'deploy') {\n"
         "    if ($words.Count -le 2) {\n"
         "      $candidates = arlen completion candidates deploy-subcommands 2>$null\n"
         "    } elseif ($words[2] -eq 'target' -and $words.Count -le 3) {\n"
         "      $candidates = arlen completion candidates deploy-target-subcommands 2>$null\n"
         "    } elseif ($wordToComplete -like '--*') {\n"
         "      $candidates = arlen completion candidates deploy-options 2>$null\n"
         "    } else {\n"
         "      $candidates = arlen completion candidates deploy-targets 2>$null\n"
         "      if (-not $candidates) { $candidates = arlen completion candidates deploy-subcommands 2>$null }\n"
         "    }\n"
         "  } elseif ($line -match '^arlen\\s+deploy\\s+') {\n"
         "    if ($wordToComplete -like '--*') {\n"
         "      $candidates = arlen completion candidates deploy-options 2>$null\n"
         "    } else {\n"
         "      $candidates = arlen completion candidates deploy-targets 2>$null\n"
         "      if (-not $candidates) { $candidates = arlen completion candidates deploy-subcommands 2>$null }\n"
         "    }\n"
         "  } elseif ($line -match '^arlen\\s+deploy$') {\n"
         "    $candidates = arlen completion candidates deploy-subcommands 2>$null\n"
         "  } else {\n"
         "    $candidates = arlen completion candidates top-level-commands 2>$null\n"
         "  }\n"
         "  $candidates | Where-Object { $_ -like \"$wordToComplete*\" } | ForEach-Object {\n"
         "    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)\n"
         "  }\n"
         "}\n";
}

static int CommandCompletionCandidates(NSArray *args) {
  if ([args count] == 0) {
    return 0;
  }
  NSString *kind = args[0];
  NSString *appRoot = [[[NSFileManager defaultManager] currentDirectoryPath] stringByStandardizingPath];
  NSString *targetName = nil;
  NSString *releasesDir = nil;
  for (NSUInteger idx = 1; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--app-root"] && idx + 1 < [args count]) {
      appRoot = [ResolvePathFromRoot([[NSFileManager defaultManager] currentDirectoryPath], args[++idx])
                    stringByStandardizingPath];
    } else if ([arg isEqualToString:@"--target"] && idx + 1 < [args count]) {
      targetName = args[++idx];
    } else if ([arg isEqualToString:@"--releases-dir"] && idx + 1 < [args count]) {
      releasesDir = [ResolvePathFromRoot(appRoot, args[++idx]) stringByStandardizingPath];
    }
  }

  NSArray<NSString *> *candidates = @[];
  if ([kind isEqualToString:@"top-level-commands"]) {
    candidates = TopLevelCompletionCandidates();
  } else if ([kind isEqualToString:@"deploy-subcommands"]) {
    candidates = DeploySubcommandCompletionCandidates();
  } else if ([kind isEqualToString:@"deploy-target-subcommands"]) {
    candidates = DeployTargetSubcommandCompletionCandidates();
  } else if ([kind isEqualToString:@"deploy-options"]) {
    candidates = DeployOptionCompletionCandidates();
  } else if ([kind isEqualToString:@"deploy-targets"]) {
    NSString *configPath = nil;
    NSError *error = nil;
    NSArray *targets = LoadDeployTargets(appRoot, &configPath, &error);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    if (targets != nil) {
      for (NSDictionary *target in targets) {
        NSString *name = StringValueForDeployKey(target, @"name");
        if ([name length] > 0) {
          [names addObject:name];
        }
      }
    }
    candidates = names;
  } else if ([kind isEqualToString:@"deploy-release-ids"]) {
    NSString *candidateReleasesDir = releasesDir;
    if ([candidateReleasesDir length] == 0 && [targetName length] > 0 &&
        ![@[ @"list", @"dryrun", @"init", @"push", @"releases", @"release", @"status", @"rollback", @"doctor", @"logs", @"target", @"plan" ] containsObject:targetName]) {
      NSError *error = nil;
      NSDictionary *target = LoadDeployTargetNamed(appRoot, targetName, &error);
      if (target != nil) {
        candidateReleasesDir = [target[@"remote_enabled"] boolValue]
            ? StringValueForDeployKey(target, @"local_staging_releases_dir")
            : StringValueForDeployKey(target, @"releases_dir");
      }
    }
    if ([candidateReleasesDir length] == 0) {
      candidateReleasesDir = [[appRoot stringByAppendingPathComponent:@"releases"] stringByStandardizingPath];
    }
    candidates = SortedReleaseDirectories(candidateReleasesDir);
  }

  for (NSString *candidate in candidates ?: @[]) {
    fprintf(stdout, "%s\n", [candidate UTF8String]);
  }
  return 0;
}

static int CommandCompletion(NSArray *args) {
  if ([args count] == 0) {
    PrintCompletionUsage();
    return 2;
  }
  NSString *subcommand = args[0];
  NSArray *subArgs = ([args count] > 1) ? [args subarrayWithRange:NSMakeRange(1, [args count] - 1)] : @[];
  if ([subcommand isEqualToString:@"bash"]) {
    fprintf(stdout, "%s", [CompletionScriptBash() UTF8String]);
    return 0;
  }
  if ([subcommand isEqualToString:@"powershell"]) {
    fprintf(stdout, "%s", [CompletionScriptPowerShell() UTF8String]);
    return 0;
  }
  if ([subcommand isEqualToString:@"candidates"]) {
    return CommandCompletionCandidates(subArgs);
  }
  if ([subcommand isEqualToString:@"--help"] || [subcommand isEqualToString:@"-h"]) {
    PrintCompletionUsage();
    return 0;
  }
  PrintCompletionUsage();
  return 2;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc < 2) {
      PrintUsage();
      return 2;
    }

    NSString *command = [NSString stringWithUTF8String:argv[1]];
    NSMutableArray *args = [NSMutableArray array];
    for (int idx = 2; idx < argc; idx++) {
      [args addObject:[NSString stringWithUTF8String:argv[idx]]];
    }

    if ([command isEqualToString:@"new"]) {
      return CommandNew(args);
    }
    if ([command isEqualToString:@"generate"]) {
      return CommandGenerate(args);
    }
    if ([command isEqualToString:@"boomhauer"]) {
      return CommandBoomhauer(args);
    }
    if ([command isEqualToString:@"jobs"]) {
      return CommandJobs(args);
    }
    if ([command isEqualToString:@"propane"]) {
      return CommandPropane(args);
    }
    if ([command isEqualToString:@"deploy"]) {
      return CommandDeploy(args);
    }
    if ([command isEqualToString:@"completion"]) {
      return CommandCompletion(args);
    }
    if ([command isEqualToString:@"migrate"]) {
      return CommandMigrate(args);
    }
    if ([command isEqualToString:@"module"]) {
      return CommandModule(args);
    }
    if ([command isEqualToString:@"schema-codegen"]) {
      return CommandSchemaCodegen(args);
    }
    if ([command isEqualToString:@"dataverse-codegen"]) {
      return CommandDataverseCodegen(args);
    }
    if ([command isEqualToString:@"typed-sql-codegen"]) {
      return CommandTypedSQLCodegen(args);
    }
    if ([command isEqualToString:@"typescript-codegen"]) {
      return CommandTypeScriptCodegen(args);
    }
    if ([command isEqualToString:@"routes"]) {
      return CommandRoutes();
    }
    if ([command isEqualToString:@"test"]) {
      return CommandTest(args);
    }
    if ([command isEqualToString:@"perf"]) {
      return CommandPerf();
    }
    if ([command isEqualToString:@"build"]) {
      return CommandBuild(args);
    }
    if ([command isEqualToString:@"check"]) {
      return CommandCheck(args);
    }
    if ([command isEqualToString:@"config"]) {
      return CommandConfig(args);
    }
    if ([command isEqualToString:@"doctor"]) {
      return CommandDoctor(args);
    }

    PrintUsage();
    return 2;
  }
}

#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdlib.h>

#import "ALNConfig.h"
#import "ALNMigrationRunner.h"
#import "ALNPg.h"
#import "ALNSchemaCodegen.h"

static void PrintUsage(void) {
  fprintf(stderr,
          "Usage: arlen <command> [options]\n"
          "\n"
          "Commands:\n"
          "  new <AppName> [--full|--lite] [--force] [--json]\n"
          "  generate <controller|endpoint|model|migration|test|plugin|frontend> <Name> [options] [--json]\n"
          "  boomhauer [server args...]\n"
          "  propane [manager args...]\n"
          "  migrate [--env <name>] [--database <target>] [--dsn <connection_string>] [--dry-run]\n"
          "  schema-codegen [--env <name>] [--database <target>] [--dsn <connection_string>] [--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] [--typed-contracts] [--force]\n"
          "  typed-sql-codegen [--input-dir <path>] [--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] [--force]\n"
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
          "Usage: arlen generate <controller|endpoint|model|migration|test|plugin|frontend> <Name> [options] [--json]\n"
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
          "Machine-readable output:\n"
          "  --json\n");
}

static void PrintBuildUsage(void) {
  fprintf(stdout, "Usage: arlen build [--dry-run] [--json]\n");
}

static void PrintCheckUsage(void) {
  fprintf(stdout, "Usage: arlen check [--dry-run] [--json]\n");
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

static void PrintJSONPayload(FILE *stream, NSDictionary *payload) {
  NSError *error = nil;
  NSData *json = [NSJSONSerialization dataWithJSONObject:payload ?: @{}
                                                 options:NSJSONWritingPrettyPrinted
                                                   error:&error];
  if (json == nil) {
    fprintf(stderr, "arlen: failed to render JSON output: %s\n",
            [[error localizedDescription] UTF8String]);
    return;
  }
  NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"{}";
  fprintf(stream, "%s\n", [text UTF8String]);
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

static NSString *RunShellCaptureCommand(NSString *command, int *exitCode) {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  task.arguments = @[ @"-lc", command ?: @"" ];
  NSPipe *stdoutPipe = [NSPipe pipe];
  NSPipe *stderrPipe = [NSPipe pipe];
  task.standardOutput = stdoutPipe;
  task.standardError = stderrPipe;
  [task launch];
  [task waitUntilExit];

  if (exitCode != NULL) {
    *exitCode = task.terminationStatus;
  }
  NSData *stdoutData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
  NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
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

static BOOL IsFrameworkRoot(NSString *path) {
  BOOL isDirectory = NO;
  if (!PathExists(path, &isDirectory) || !isDirectory) {
    return NO;
  }

  NSString *makefile = [path stringByAppendingPathComponent:@"GNUmakefile"];
  NSString *tool = [path stringByAppendingPathComponent:@"tools/boomhauer.m"];
  NSString *runtime = [path stringByAppendingPathComponent:@"src/Arlen/ArlenServer.h"];
  return PathExists(makefile, NULL) && PathExists(tool, NULL) && PathExists(runtime, NULL);
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

static BOOL AddPluginClassToAppConfig(NSString *root, NSString *pluginClassName, NSError **error) {
  if ([pluginClassName length] == 0) {
    return YES;
  }

  NSString *configPath = [root stringByAppendingPathComponent:@"config/app.plist"];
  NSData *data = [NSData dataWithContentsOfFile:configPath options:0 error:error];
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
                                                                   format:NSPropertyListOpenStepFormat
                                                                  options:0
                                                                    error:error];
  if (serialized == nil) {
    return NO;
  }
  return [serialized writeToFile:configPath options:NSDataWritingAtomic error:error];
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
  ok = ok && WriteTextFile([root stringByAppendingPathComponent:@"templates/index.html.eoc"],
                           @"<h1><%= $title %></h1>\n", force, error);
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
                            "  [self stashValue:@\"Welcome to Arlen\" forKey:@\"title\"];\n"
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
                            "- `templates/index.html.eoc` renders the home page.\n",
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
                            "- You can split this into full mode structure later.\n",
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

    NSString *impl = [NSString stringWithFormat:
                                   @"#import \"%@Controller.h\"\n"
                                    "#import \"ALNContext.h\"\n\n"
                                    "@implementation %@Controller\n\n"
                                    "%@\n"
                                    "@end\n",
                                   controllerBase, controllerBase, actionBody];

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
        ok = WriteTextFile(templatePath, @"<h1><%= $title %></h1>\n", NO, &error);
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
  } else {
    if (asJSON) {
      return EmitMachineError(@"generate", @"scaffold", @"unknown_generator_type",
                              [NSString stringWithFormat:@"arlen generate: unknown type %@", type ?: @""],
                              @"Use one of: controller, endpoint, model, migration, test, plugin, frontend.",
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
                   @"Unset ARLEN_FRAMEWORK_ROOT or point it at a checkout containing GNUmakefile + src/Arlen.");
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
                   @"Set ARLEN_FRAMEWORK_ROOT or run from inside an Arlen checkout/app.");
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

  NSString *gnustepScript = @"/usr/GNUstep/System/Library/Makefiles/GNUstep.sh";
  if (PathExists(gnustepScript, NULL)) {
    AddDoctorCheck(checks, @"gnustep_script", @"pass",
                   [NSString stringWithFormat:@"GNUstep script present: %@", gnustepScript], @"");
    passCount += 1;
  } else {
    AddDoctorCheck(checks, @"gnustep_script", @"fail",
                   [NSString stringWithFormat:@"missing GNUstep script: %@", gnustepScript],
                   @"Install GNUstep base development packages.");
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
        Trimmed(RunShellCaptureCommand([NSString stringWithFormat:@"source %@ >/dev/null 2>&1 && gnustep-config --objc-flags",
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
                     @"Verify GNUstep installation and shell init: source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh");
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
                   @"Install PostgreSQL client libraries (`libpq`) for ALNPg/migrations.");
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
    NSError *jsonError = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&jsonError];
    if (json == nil) {
      fprintf(stderr, "arlen doctor: %s\n", [[jsonError localizedDescription] UTF8String]);
      return 1;
    }
    fprintf(stdout, "%s\n", [[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] UTF8String]);
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
    NSData *json = [NSJSONSerialization dataWithJSONObject:config options:NSJSONWritingPrettyPrinted error:&error];
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
  NSString *pascal = ALNTypedSQLPascalSuffix(identifier);
  if ([pascal length] == 0) {
    return @"value";
  }
  NSString *first = [[pascal substringToIndex:1] lowercaseString];
  NSString *rest = ([pascal length] > 1) ? [pascal substringFromIndex:1] : @"";
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

  NSString *introspectionSQL =
      @"SELECT c.table_schema, c.table_name, c.column_name, c.ordinal_position, c.data_type, c.is_nullable "
       "FROM information_schema.columns c "
       "JOIN information_schema.tables t "
       "  ON t.table_schema = c.table_schema "
       " AND t.table_name = c.table_name "
       "WHERE c.table_schema NOT IN ('pg_catalog', 'information_schema') "
       "  AND t.table_type IN ('BASE TABLE', 'VIEW') "
       "ORDER BY c.table_schema, c.table_name, c.ordinal_position, c.column_name";
  NSArray *rows = [database executeQuery:introspectionSQL parameters:@[] error:&error];
  if (rows == nil) {
    fprintf(stderr, "arlen schema-codegen: failed schema introspection query: %s\n",
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

  NSUInteger poolSize = DatabasePoolSizeFromConfigForTarget(config, databaseTarget);
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:poolSize error:&error];
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
    if ([command isEqualToString:@"propane"]) {
      return CommandPropane(args);
    }
    if ([command isEqualToString:@"migrate"]) {
      return CommandMigrate(args);
    }
    if ([command isEqualToString:@"schema-codegen"]) {
      return CommandSchemaCodegen(args);
    }
    if ([command isEqualToString:@"typed-sql-codegen"]) {
      return CommandTypedSQLCodegen(args);
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

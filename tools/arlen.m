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
          "  new <AppName> [--full|--lite] [--force]\n"
          "  generate <controller|endpoint|model|migration|test|plugin> <Name> [options]\n"
          "  boomhauer [server args...]\n"
          "  propane [manager args...]\n"
          "  migrate [--env <name>] [--database <target>] [--dsn <connection_string>] [--dry-run]\n"
          "  schema-codegen [--env <name>] [--database <target>] [--dsn <connection_string>] [--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] [--force]\n"
          "  routes\n"
          "  test [--unit|--integration|--all]\n"
          "  perf\n"
          "  check\n"
          "  build\n"
          "  config [--env <name>] [--json]\n"
          "  doctor [--env <name>] [--json]\n");
}

static void PrintNewUsage(void) {
  fprintf(stdout, "Usage: arlen new <AppName> [--full|--lite] [--force]\n");
}

static void PrintGenerateUsage(void) {
  fprintf(stdout,
          "Usage: arlen generate <controller|endpoint|model|migration|test|plugin> <Name> [options]\n"
          "\n"
          "Generator options (controller/endpoint):\n"
          "  --route <path>\n"
          "  --method <HTTP>\n"
          "  --action <name>\n"
          "  --template [<logical_template>]\n"
          "  --api\n"
          "\n"
          "Generator options (plugin):\n"
          "  --preset <generic|redis-cache|queue-jobs|smtp-mail>\n");
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
  if ([args count] == 0) {
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
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      PrintNewUsage();
      return 0;
    } else {
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
    fprintf(stderr, "arlen new: %s\n", [[error localizedDescription] UTF8String]);
    return 1;
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
  return InsertRouteIntoRegisterRoutes(target, line, error);
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

static int CommandGenerate(NSArray *args) {
  if ([args count] == 1 &&
      ([args[0] isEqualToString:@"--help"] || [args[0] isEqualToString:@"-h"])) {
    PrintGenerateUsage();
    return 0;
  }
  if ([args count] < 2) {
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
  NSString *pluginPreset = @"generic";
  BOOL pluginPresetExplicit = NO;

  for (NSUInteger idx = 2; idx < [args count]; idx++) {
    NSString *arg = args[idx];
    if ([arg isEqualToString:@"--route"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen generate: --route requires a value\n");
        return 2;
      }
      routePath = args[++idx];
      if (![routePath hasPrefix:@"/"]) {
        routePath = [@"/" stringByAppendingString:routePath];
      }
    } else if ([arg isEqualToString:@"--method"]) {
      if (idx + 1 >= [args count]) {
        fprintf(stderr, "arlen generate: --method requires a value\n");
        return 2;
      }
      method = [args[++idx] uppercaseString];
    } else if ([arg isEqualToString:@"--action"]) {
      if (idx + 1 >= [args count]) {
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
        fprintf(stderr, "arlen generate: --preset requires a value\n");
        return 2;
      }
      pluginPreset = [[args[++idx] lowercaseString] copy];
      pluginPresetExplicit = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      PrintGenerateUsage();
      return 0;
    } else {
      fprintf(stderr, "arlen generate: unknown option %s\n", [arg UTF8String]);
      return 2;
    }
  }

  if ([type isEqualToString:@"endpoint"] && [routePath length] == 0) {
    fprintf(stderr, "arlen generate endpoint: --route is required\n");
    return 2;
  }
  if (pluginPresetExplicit && ![type isEqualToString:@"plugin"]) {
    fprintf(stderr, "arlen generate: --preset is only valid for plugin generator\n");
    return 2;
  }
  if ([type isEqualToString:@"plugin"] && !IsSupportedPluginPreset(pluginPreset)) {
    fprintf(stderr, "arlen generate plugin: unsupported --preset %s\n", [pluginPreset UTF8String]);
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

    ok = WriteTextFile(headerPath, header, NO, &error) &&
         WriteTextFile(implPath, impl, NO, &error);

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
      }
    }

    if (ok && [routePath length] > 0) {
      ok = WireGeneratedRoute(root, method, routePath, controllerBase, actionName, &error);
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
                       NO, &error) &&
         WriteTextFile(implPath,
                       [NSString stringWithFormat:@"#import \"%@Repository.h\"\n\n@implementation %@Repository\n@end\n",
                                                   name, name],
                       NO, &error);
  } else if ([type isEqualToString:@"migration"]) {
    NSString *timestamp =
        [NSString stringWithFormat:@"%lld", (long long)[[NSDate date] timeIntervalSince1970]];
    NSString *path =
        [root stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"db/migrations/%@_%@.sql", timestamp,
                                             [name lowercaseString]]];
    ok = WriteTextFile(path, @"-- migration\n", NO, &error);
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
    NSString *impl = PluginImplementationForPreset(pluginName, logicalName, pluginPreset);

    ok = WriteTextFile(headerPath, header, NO, &error) &&
         WriteTextFile(implPath, impl, NO, &error);
    if (ok) {
      ok = AddPluginClassToAppConfig(root, pluginName, &error);
    }
  } else {
    fprintf(stderr, "arlen generate: unknown type %s\n", [type UTF8String]);
    return 2;
  }

  if (!ok) {
    fprintf(stderr, "arlen generate: %s\n", [[error localizedDescription] UTF8String]);
    return 1;
  }

  fprintf(stdout, "Generated %s %s\n", [type UTF8String], [name UTF8String]);
  return 0;
}

static NSString *ResolveFrameworkRootForCommand(NSString *commandName) {
  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *override = EnvValue("ARLEN_FRAMEWORK_ROOT");
  if ([override length] > 0) {
    NSString *candidate = [override hasPrefix:@"/"]
                              ? [override stringByStandardizingPath]
                              : [[appRoot stringByAppendingPathComponent:override] stringByStandardizingPath];
    if (IsFrameworkRoot(candidate)) {
      return candidate;
    }
    fprintf(stderr,
            "arlen %s: ARLEN_FRAMEWORK_ROOT does not point to a valid Arlen root: %s\n",
            [commandName UTF8String], [candidate UTF8String]);
    return nil;
  }

  NSString *frameworkRoot = FindFrameworkRoot(appRoot);
  if ([frameworkRoot length] == 0) {
    frameworkRoot = FrameworkRootFromExecutablePath();
  }
  if ([frameworkRoot length] == 0) {
    fprintf(stderr, "arlen %s: could not locate Arlen framework root from %s\n",
            [commandName UTF8String], [appRoot UTF8String]);
    return nil;
  }
  return frameworkRoot;
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

static int CommandBuild(void) {
  NSString *frameworkRoot = ResolveFrameworkRootForCommand(@"build");
  if ([frameworkRoot length] == 0) {
    return 1;
  }
  return RunShellCommand([NSString stringWithFormat:@"cd %@ && make all", ShellQuote(frameworkRoot)]);
}

static int CommandCheck(void) {
  NSString *frameworkRoot = ResolveFrameworkRootForCommand(@"check");
  if ([frameworkRoot length] == 0) {
    return 1;
  }
  return RunShellCommand([NSString stringWithFormat:@"cd %@ && make check", ShellQuote(frameworkRoot)]);
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
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      fprintf(stdout,
              "Usage: arlen schema-codegen [--env <name>] [--database <target>] [--dsn <connection_string>] "
              "[--output-dir <path>] [--manifest <path>] [--prefix <ClassPrefix>] [--force]\n");
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
      @"SELECT c.table_schema, c.table_name, c.column_name, c.ordinal_position "
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
      return CommandBuild();
    }
    if ([command isEqualToString:@"check"]) {
      return CommandCheck();
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

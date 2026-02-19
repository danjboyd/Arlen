#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdlib.h>

#import "ALNConfig.h"
#import "ALNMigrationRunner.h"
#import "ALNPg.h"

static void PrintUsage(void) {
  fprintf(stderr,
          "Usage: arlen <command> [options]\n"
          "\n"
          "Commands:\n"
          "  new <AppName> [--full|--lite] [--force]\n"
          "  generate <controller|endpoint|model|migration|test|plugin> <Name> [options]\n"
          "  boomhauer [server args...]\n"
          "  propane [manager args...]\n"
          "  migrate [--env <name>] [--dsn <connection_string>] [--dry-run]\n"
          "  routes\n"
          "  test [--unit|--integration|--all]\n"
          "  perf\n"
          "  check\n"
          "  build\n"
          "  config [--env <name>] [--json]\n");
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
          "  --api\n");
}

static NSString *ShellQuote(NSString *value) {
  NSString *escaped = [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\"'\"'"];
  return [NSString stringWithFormat:@"'%@'", escaped];
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
                           @"{\n  host = \"127.0.0.1\";\n  port = 3000;\n  serveStatic = YES;\n  listenBacklog = 128;\n  connectionTimeoutSeconds = 30;\n  database = {\n    connectionString = \"\";\n    adapter = \"postgresql\";\n    poolSize = 8;\n  };\n  session = {\n    enabled = NO;\n    secret = \"\";\n    cookieName = \"arlen_session\";\n    maxAgeSeconds = 1209600;\n    secure = NO;\n    sameSite = \"Lax\";\n  };\n  csrf = {\n    enabled = NO;\n    headerName = \"x-csrf-token\";\n    queryParamName = \"csrf_token\";\n  };\n  rateLimit = {\n    enabled = NO;\n    requests = 120;\n    windowSeconds = 60;\n  };\n  securityHeaders = {\n    enabled = YES;\n    contentSecurityPolicy = \"default-src 'self'\";\n  };\n  auth = {\n    enabled = NO;\n    bearerSecret = \"\";\n    issuer = \"\";\n    audience = \"\";\n  };\n  openapi = {\n    enabled = YES;\n    docsUIEnabled = YES;\n    docsUIStyle = \"interactive\";\n    title = \"Arlen API\";\n    version = \"0.1.0\";\n    description = \"Generated by Arlen\";\n  };\n  compatibility = {\n    pageStateEnabled = NO;\n  };\n  plugins = {\n    classes = ();\n  };\n  propaneAccessories = {\n    workerCount = 4;\n    gracefulShutdownSeconds = 10;\n    respawnDelayMs = 250;\n    reloadOverlapSeconds = 1;\n  };\n}\n",
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
    NSString *impl = [NSString stringWithFormat:
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

static NSString *DatabaseConnectionStringFromConfig(NSDictionary *config) {
  NSDictionary *database = [config[@"database"] isKindOfClass:[NSDictionary class]] ? config[@"database"] : nil;
  NSString *connectionString =
      [database[@"connectionString"] isKindOfClass:[NSString class]] ? database[@"connectionString"] : nil;
  return ([connectionString length] > 0) ? connectionString : nil;
}

static NSUInteger DatabasePoolSizeFromConfig(NSDictionary *config) {
  NSDictionary *database = [config[@"database"] isKindOfClass:[NSDictionary class]] ? config[@"database"] : nil;
  id value = database[@"poolSize"];
  if ([value respondsToSelector:@selector(unsignedIntegerValue)]) {
    NSUInteger parsed = [value unsignedIntegerValue];
    if (parsed >= 1) {
      return parsed;
    }
  }
  return 4;
}

static int CommandMigrate(NSArray *args) {
  NSString *environment = @"development";
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
    } else if ([arg isEqualToString:@"--dry-run"]) {
      dryRun = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      fprintf(stdout,
              "Usage: arlen migrate [--env <name>] [--dsn <connection_string>] [--dry-run]\n");
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

  NSString *dsn = dsnOverride ?: EnvValue("ARLEN_DATABASE_URL");
  if ([dsn length] == 0) {
    dsn = DatabaseConnectionStringFromConfig(config);
  }
  if ([dsn length] == 0) {
    fprintf(stderr,
            "arlen migrate: no database connection string configured (set --dsn or "
            "ARLEN_DATABASE_URL or config.database.connectionString)\n");
    return 1;
  }

  NSUInteger poolSize = DatabasePoolSizeFromConfig(config);
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:poolSize error:&error];
  if (database == nil) {
    fprintf(stderr, "arlen migrate: failed to initialize database adapter: %s\n",
            [[error localizedDescription] UTF8String]);
    return 1;
  }

  NSString *migrationsPath = [appRoot stringByAppendingPathComponent:@"db/migrations"];
  NSArray *files = nil;
  BOOL ok = [ALNMigrationRunner applyMigrationsAtPath:migrationsPath
                                             database:database
                                               dryRun:dryRun
                                         appliedFiles:&files
                                                error:&error];
  if (!ok) {
    fprintf(stderr, "arlen migrate: %s\n", [[error localizedDescription] UTF8String]);
    return 1;
  }

  if (dryRun) {
    fprintf(stdout, "Pending migrations: %lu\n", (unsigned long)[files count]);
    for (NSString *file in files) {
      fprintf(stdout, "  %s\n", [[file lastPathComponent] UTF8String]);
    }
    return 0;
  }

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

    PrintUsage();
    return 2;
  }
}

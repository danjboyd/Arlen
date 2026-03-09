#import "ALNModuleSystem.h"

#import "ALNApplication.h"

NSString *const ALNModuleSystemErrorDomain = @"Arlen.ModuleSystem.Error";
NSString *const ALNModuleSystemFrameworkVersion = @"0.1.0";

static NSString *ALNModuleTrim(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSError *ALNModuleError(NSInteger code,
                               NSString *message,
                               NSString *detail,
                               NSArray<NSDictionary *> *diagnostics) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"module system error";
  if ([detail length] > 0) {
    userInfo[@"detail"] = detail;
  }
  if ([diagnostics count] > 0) {
    userInfo[@"diagnostics"] = diagnostics;
  }
  return [NSError errorWithDomain:ALNModuleSystemErrorDomain code:code userInfo:userInfo];
}

static NSDictionary *ALNModuleLoadPlist(NSString *path, NSError **error) {
  if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
    if (error != NULL) {
      *error = ALNModuleError(1,
                              [NSString stringWithFormat:@"plist not found: %@", path ?: @""],
                              nil,
                              nil);
    }
    return nil;
  }

  NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
  if (data == nil) {
    return nil;
  }

  NSPropertyListFormat format = NSPropertyListOpenStepFormat;
  id plist = [NSPropertyListSerialization propertyListWithData:data
                                                       options:NSPropertyListMutableContainersAndLeaves
                                                        format:&format
                                                         error:error];
  if (![plist isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNModuleError(2,
                              [NSString stringWithFormat:@"plist is not a dictionary: %@", path ?: @""],
                              nil,
                              nil);
    }
    return nil;
  }
  return plist;
}

static NSString *ALNModuleResolvePath(NSString *basePath,
                                      NSString *rawPath,
                                      NSString *defaultRelativePath) {
  NSString *candidate = ALNModuleTrim(rawPath);
  if ([candidate length] == 0) {
    candidate = defaultRelativePath ?: @"";
  }
  if ([candidate length] == 0) {
    return [basePath stringByStandardizingPath];
  }
  NSString *expanded = [candidate stringByExpandingTildeInPath];
  if ([expanded hasPrefix:@"/"]) {
    return [expanded stringByStandardizingPath];
  }
  return [[basePath stringByAppendingPathComponent:expanded] stringByStandardizingPath];
}

static BOOL ALNModuleIdentifierIsValid(NSString *identifier) {
  if ([identifier length] == 0) {
    return NO;
  }
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
  return ([[identifier stringByTrimmingCharactersInSet:allowed] length] == 0);
}

static BOOL ALNModuleVersionIsValid(NSString *version) {
  if ([version length] == 0) {
    return NO;
  }
  NSArray<NSString *> *parts = [version componentsSeparatedByString:@"."];
  if ([parts count] < 2) {
    return NO;
  }
  NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
  for (NSString *part in parts) {
    if ([part length] == 0 || [[part stringByTrimmingCharactersInSet:digits] length] > 0) {
      return NO;
    }
  }
  return YES;
}

static NSArray<NSNumber *> *ALNModuleVersionComponents(NSString *version) {
  NSMutableArray<NSNumber *> *components = [NSMutableArray array];
  for (NSString *part in [version componentsSeparatedByString:@"."]) {
    [components addObject:@([part integerValue])];
  }
  while ([components count] < 3) {
    [components addObject:@0];
  }
  return components;
}

static NSComparisonResult ALNModuleCompareVersions(NSString *left, NSString *right) {
  NSArray<NSNumber *> *leftParts = ALNModuleVersionComponents(left ?: @"0.0.0");
  NSArray<NSNumber *> *rightParts = ALNModuleVersionComponents(right ?: @"0.0.0");
  NSUInteger count = MAX([leftParts count], [rightParts count]);
  for (NSUInteger idx = 0; idx < count; idx++) {
    NSInteger leftValue = (idx < [leftParts count]) ? [leftParts[idx] integerValue] : 0;
    NSInteger rightValue = (idx < [rightParts count]) ? [rightParts[idx] integerValue] : 0;
    if (leftValue < rightValue) {
      return NSOrderedAscending;
    }
    if (leftValue > rightValue) {
      return NSOrderedDescending;
    }
  }
  return NSOrderedSame;
}

static BOOL ALNModuleVersionMatchesConstraint(NSString *version, NSString *constraint) {
  NSString *trimmed = ALNModuleTrim(constraint);
  if ([trimmed length] == 0) {
    return YES;
  }
  NSArray<NSString *> *clauses = [trimmed componentsSeparatedByString:@","];
  for (NSString *rawClause in clauses) {
    NSString *clause = ALNModuleTrim(rawClause);
    NSString *operatorToken = @"=";
    NSString *operand = clause;
    NSArray<NSString *> *operators = @[ @">=", @"<=", @">", @"<", @"=" ];
    for (NSString *candidate in operators) {
      if ([clause hasPrefix:candidate]) {
        operatorToken = candidate;
        operand = ALNModuleTrim([clause substringFromIndex:[candidate length]]);
        break;
      }
    }
    if ([operand length] == 0 || !ALNModuleVersionIsValid(operand)) {
      return NO;
    }
    NSComparisonResult comparison = ALNModuleCompareVersions(version, operand);
    BOOL clauseMatched = NO;
    if ([operatorToken isEqualToString:@"="]) {
      clauseMatched = (comparison == NSOrderedSame);
    } else if ([operatorToken isEqualToString:@">="]) {
      clauseMatched = (comparison == NSOrderedSame || comparison == NSOrderedDescending);
    } else if ([operatorToken isEqualToString:@">"]) {
      clauseMatched = (comparison == NSOrderedDescending);
    } else if ([operatorToken isEqualToString:@"<="]) {
      clauseMatched = (comparison == NSOrderedSame || comparison == NSOrderedAscending);
    } else if ([operatorToken isEqualToString:@"<"]) {
      clauseMatched = (comparison == NSOrderedAscending);
    }
    if (!clauseMatched) {
      return NO;
    }
  }
  return YES;
}

static BOOL ALNModuleIsConfigValueMissing(id value) {
  if (value == nil || value == [NSNull null]) {
    return YES;
  }
  if ([value isKindOfClass:[NSString class]]) {
    return ([ALNModuleTrim(value) length] == 0);
  }
  if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSDictionary class]]) {
    return ([(id)value count] == 0);
  }
  return NO;
}

static id ALNModuleConfigValueForKeyPath(NSDictionary *config, NSString *keyPath) {
  NSArray<NSString *> *parts = [ALNModuleTrim(keyPath) componentsSeparatedByString:@"."];
  id current = config;
  for (NSString *part in parts) {
    if ([part length] == 0) {
      continue;
    }
    if (![current isKindOfClass:[NSDictionary class]]) {
      return nil;
    }
    current = [(NSDictionary *)current objectForKey:part];
  }
  return current;
}

static void ALNModuleAppendDiagnostic(NSMutableArray<NSDictionary *> *diagnostics,
                                      NSString *status,
                                      NSString *code,
                                      NSString *moduleID,
                                      NSString *message,
                                      NSString *detail,
                                      NSString *keyPath) {
  NSMutableDictionary *entry = [NSMutableDictionary dictionary];
  entry[@"status"] = [ALNModuleTrim(status) length] > 0 ? status : @"error";
  entry[@"code"] = code ?: @"module_error";
  entry[@"module"] = moduleID ?: @"";
  entry[@"message"] = message ?: @"";
  if ([detail length] > 0) {
    entry[@"detail"] = detail;
  }
  if ([keyPath length] > 0) {
    entry[@"key_path"] = keyPath;
  }
  [diagnostics addObject:entry];
}

static void ALNModuleMergeDefaultsIntoDictionary(NSMutableDictionary *target,
                                                 NSDictionary *incoming,
                                                 NSString *moduleID,
                                                 NSString *prefix,
                                                 NSMutableArray<NSDictionary *> *diagnostics) {
  NSArray<NSString *> *keys = [[incoming allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in keys) {
    NSString *keyPath = ([prefix length] > 0) ? [NSString stringWithFormat:@"%@.%@", prefix, key] : key;
    id incomingValue = incoming[key];
    id existingValue = target[key];
    if (existingValue == nil) {
      target[key] = incomingValue;
      continue;
    }
    if ([existingValue isKindOfClass:[NSDictionary class]] &&
        [incomingValue isKindOfClass:[NSDictionary class]]) {
      NSMutableDictionary *child = [NSMutableDictionary dictionaryWithDictionary:existingValue];
      ALNModuleMergeDefaultsIntoDictionary(child, incomingValue, moduleID, keyPath, diagnostics);
      target[key] = child;
      continue;
    }
    if ((existingValue == nil && incomingValue == nil) || [existingValue isEqual:incomingValue]) {
      continue;
    }
    ALNModuleAppendDiagnostic(
        diagnostics,
        @"error",
        @"module_config_default_conflict",
        moduleID,
        [NSString stringWithFormat:@"conflicting module config default for %@", keyPath],
        @"module defaults must not assign different values to the same config key",
        keyPath);
  }
}

static BOOL ALNModuleDirectoryExists(NSString *path) {
  BOOL isDirectory = NO;
  return [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory;
}

static NSDictionary *ALNModuleMergeDictionaries(NSDictionary *base, NSDictionary *overlay) {
  NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:base ?: @{}];
  for (NSString *key in overlay ?: @{}) {
    id overlayValue = overlay[key];
    id baseValue = merged[key];
    if ([baseValue isKindOfClass:[NSDictionary class]] && [overlayValue isKindOfClass:[NSDictionary class]]) {
      merged[key] = ALNModuleMergeDictionaries(baseValue, overlayValue);
    } else {
      merged[key] = overlayValue;
    }
  }
  return merged;
}

static NSDictionary *ALNModuleNormalizedDependency(id rawDependency,
                                                   NSString *moduleID,
                                                   NSError **error) {
  if ([rawDependency isKindOfClass:[NSString class]]) {
    NSString *identifier = ALNModuleTrim(rawDependency);
    if (!ALNModuleIdentifierIsValid(identifier)) {
      if (error != NULL) {
        *error = ALNModuleError(3,
                                [NSString stringWithFormat:@"module %@ declares invalid dependency %@", moduleID ?: @"", identifier ?: @""],
                                nil,
                                nil);
      }
      return nil;
    }
    return @{ @"identifier" : identifier, @"version" : @"", @"required" : @(YES) };
  }
  if (![rawDependency isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNModuleError(4,
                              [NSString stringWithFormat:@"module %@ dependency entries must be strings or dictionaries",
                                                         moduleID ?: @""],
                              nil,
                              nil);
    }
    return nil;
  }
  NSDictionary *entry = (NSDictionary *)rawDependency;
  NSString *identifier = ALNModuleTrim(entry[@"identifier"]);
  NSString *version = ALNModuleTrim(entry[@"version"]);
  id requiredValue = entry[@"required"];
  BOOL required = [requiredValue respondsToSelector:@selector(boolValue)] ? [requiredValue boolValue] : YES;
  if (!ALNModuleIdentifierIsValid(identifier)) {
    if (error != NULL) {
      *error = ALNModuleError(5,
                              [NSString stringWithFormat:@"module %@ declares invalid dependency identifier %@", moduleID ?: @"", identifier ?: @""],
                              nil,
                              nil);
    }
    return nil;
  }
  if ([version length] > 0 && !ALNModuleVersionMatchesConstraint(@"0.0.0", version) &&
      !ALNModuleVersionIsValid(ALNModuleTrim([version stringByTrimmingCharactersInSet:
                                                       [NSCharacterSet characterSetWithCharactersInString:@"><= "]]))) {
    if (error != NULL) {
      *error = ALNModuleError(6,
                              [NSString stringWithFormat:@"module %@ declares invalid dependency version constraint %@", moduleID ?: @"", version ?: @""],
                              nil,
                              nil);
    }
    return nil;
  }
  return @{
    @"identifier" : identifier,
    @"version" : version ?: @"",
    @"required" : @(required),
  };
}

@interface ALNModuleDefinition ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *version;
@property(nonatomic, copy, readwrite) NSString *principalClassName;
@property(nonatomic, copy, readwrite) NSString *rootPath;
@property(nonatomic, copy, readwrite) NSString *manifestPath;
@property(nonatomic, copy, readwrite) NSString *sourcePath;
@property(nonatomic, copy, readwrite) NSString *templatePath;
@property(nonatomic, copy, readwrite) NSString *publicPath;
@property(nonatomic, copy, readwrite) NSString *localePath;
@property(nonatomic, copy, readwrite) NSString *migrationPath;
@property(nonatomic, copy, readwrite) NSString *migrationDatabaseTarget;
@property(nonatomic, copy, readwrite) NSString *migrationNamespace;
@property(nonatomic, copy, readwrite) NSString *compatibleArlenVersion;
@property(nonatomic, copy, readwrite) NSArray<NSDictionary *> *dependencies;
@property(nonatomic, copy, readwrite) NSDictionary *configDefaults;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *requiredConfigKeys;
@property(nonatomic, copy, readwrite) NSArray<NSDictionary *> *publicMounts;
@property(nonatomic, copy, readwrite) NSDictionary *manifest;

@end

@implementation ALNModuleDefinition

+ (instancetype)definitionWithModuleRoot:(NSString *)moduleRoot
                                   error:(NSError **)error {
  NSString *rootPath = [[moduleRoot ?: @"" stringByStandardizingPath] copy];
  NSString *manifestPath = [rootPath stringByAppendingPathComponent:@"module.plist"];
  NSDictionary *manifest = ALNModuleLoadPlist(manifestPath, error);
  if (manifest == nil) {
    return nil;
  }

  NSString *identifier = ALNModuleTrim(manifest[@"identifier"]);
  NSString *version = ALNModuleTrim(manifest[@"version"]);
  NSString *principalClassName = ALNModuleTrim(manifest[@"principalClass"]);
  if (!ALNModuleIdentifierIsValid(identifier)) {
    if (error != NULL) {
      *error = ALNModuleError(7,
                              [NSString stringWithFormat:@"module identifier is invalid in %@", manifestPath],
                              @"identifiers must use only letters, digits, hyphen, or underscore",
                              nil);
    }
    return nil;
  }
  if (!ALNModuleVersionIsValid(version)) {
    if (error != NULL) {
      *error = ALNModuleError(8,
                              [NSString stringWithFormat:@"module %@ must declare a semantic version", identifier],
                              nil,
                              nil);
    }
    return nil;
  }
  if ([principalClassName length] == 0) {
    if (error != NULL) {
      *error = ALNModuleError(9,
                              [NSString stringWithFormat:@"module %@ must declare principalClass", identifier],
                              nil,
                              nil);
    }
    return nil;
  }

  NSMutableArray<NSDictionary *> *dependencies = [NSMutableArray array];
  NSArray *dependencyEntries = [manifest[@"dependencies"] isKindOfClass:[NSArray class]] ? manifest[@"dependencies"] : @[];
  for (id entry in dependencyEntries) {
    NSDictionary *normalized = ALNModuleNormalizedDependency(entry, identifier, error);
    if (normalized == nil) {
      return nil;
    }
    [dependencies addObject:normalized];
  }

  NSDictionary *config = [manifest[@"config"] isKindOfClass:[NSDictionary class]] ? manifest[@"config"] : @{};
  NSDictionary *configDefaults = [config[@"defaults"] isKindOfClass:[NSDictionary class]] ? config[@"defaults"] : @{};
  NSMutableArray<NSString *> *requiredConfigKeys = [NSMutableArray array];
  for (id value in ([config[@"requiredKeys"] isKindOfClass:[NSArray class]] ? config[@"requiredKeys"] : @[])) {
    NSString *keyPath = ALNModuleTrim(value);
    if ([keyPath length] > 0 && ![requiredConfigKeys containsObject:keyPath]) {
      [requiredConfigKeys addObject:keyPath];
    }
  }

  NSDictionary *resources = [manifest[@"resources"] isKindOfClass:[NSDictionary class]] ? manifest[@"resources"] : @{};
  NSString *sourcePath = ALNModuleResolvePath(rootPath, manifest[@"sourcePath"], @"Sources");
  NSString *templatePath = ALNModuleResolvePath(rootPath, resources[@"templates"], @"Resources/Templates");
  NSString *publicPath = ALNModuleResolvePath(rootPath, resources[@"public"], @"Resources/Public");
  NSString *localePath = ALNModuleResolvePath(rootPath, resources[@"locales"], @"Resources/Locales");

  NSDictionary *migrations = [manifest[@"migrations"] isKindOfClass:[NSDictionary class]] ? manifest[@"migrations"] : @{};
  NSString *migrationPath = ALNModuleResolvePath(rootPath, migrations[@"path"], @"Migrations");
  NSString *migrationDatabaseTarget = ALNModuleTrim(migrations[@"databaseTarget"]);
  if ([migrationDatabaseTarget length] == 0) {
    migrationDatabaseTarget = @"default";
  }
  NSString *migrationNamespace = ALNModuleTrim(migrations[@"namespace"]);
  if ([migrationNamespace length] == 0) {
    migrationNamespace = identifier;
  }

  NSDictionary *compatibility =
      [manifest[@"compatibility"] isKindOfClass:[NSDictionary class]] ? manifest[@"compatibility"] : @{};
  NSString *compatibleArlenVersion = ALNModuleTrim(compatibility[@"arlenVersion"]);

  NSMutableArray<NSDictionary *> *publicMounts = [NSMutableArray array];
  NSArray *manifestPublicMounts =
      [manifest[@"publicMounts"] isKindOfClass:[NSArray class]] ? manifest[@"publicMounts"] : @[];
  for (NSDictionary *entry in manifestPublicMounts) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *prefix = ALNModuleTrim(entry[@"prefix"]);
    if ([prefix length] == 0) {
      continue;
    }
    NSString *directory =
        ALNModuleResolvePath(rootPath, entry[@"path"], ALNModuleTrim(entry[@"subpath"]));
    NSArray *allowExtensions = [entry[@"allowExtensions"] isKindOfClass:[NSArray class]]
                                   ? entry[@"allowExtensions"]
                                   : @[];
    [publicMounts addObject:@{
      @"prefix" : prefix,
      @"directory" : directory,
      @"allowExtensions" : allowExtensions,
    }];
  }
  if ([publicMounts count] == 0 && ALNModuleDirectoryExists(publicPath)) {
    [publicMounts addObject:@{
      @"prefix" : [NSString stringWithFormat:@"/modules/%@", identifier],
      @"directory" : publicPath,
      @"allowExtensions" : @[],
    }];
  }

  ALNModuleDefinition *definition = [[ALNModuleDefinition alloc] init];
  definition.identifier = identifier;
  definition.version = version;
  definition.principalClassName = principalClassName;
  definition.rootPath = rootPath;
  definition.manifestPath = manifestPath;
  definition.sourcePath = sourcePath;
  definition.templatePath = templatePath;
  definition.publicPath = publicPath;
  definition.localePath = localePath;
  definition.migrationPath = migrationPath;
  definition.migrationDatabaseTarget = migrationDatabaseTarget;
  definition.migrationNamespace = migrationNamespace;
  definition.compatibleArlenVersion = compatibleArlenVersion;
  definition.dependencies = [dependencies sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    return [left[@"identifier"] compare:right[@"identifier"]];
  }];
  definition.configDefaults = configDefaults ?: @{};
  definition.requiredConfigKeys = [requiredConfigKeys sortedArrayUsingSelector:@selector(compare:)];
  definition.publicMounts = [publicMounts sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    return [left[@"prefix"] compare:right[@"prefix"]];
  }];
  definition.manifest = manifest;
  return definition;
}

- (NSDictionary *)dictionaryRepresentation {
  return @{
    @"identifier" : self.identifier ?: @"",
    @"version" : self.version ?: @"",
    @"principalClass" : self.principalClassName ?: @"",
    @"path" : self.rootPath ?: @"",
    @"migrationDatabaseTarget" : self.migrationDatabaseTarget ?: @"default",
  };
}

@end

@implementation ALNModuleSystem

+ (NSString *)frameworkVersion {
  return ALNModuleSystemFrameworkVersion;
}

+ (NSString *)modulesConfigRelativePath {
  return @"config/modules.plist";
}

+ (NSDictionary *)modulesLockDocumentAtAppRoot:(NSString *)appRoot
                                         error:(NSError **)error {
  NSString *lockPath = [[appRoot stringByAppendingPathComponent:[self modulesConfigRelativePath]]
      stringByStandardizingPath];
  if (![[NSFileManager defaultManager] fileExistsAtPath:lockPath]) {
    return @{ @"modules" : @[] };
  }
  NSDictionary *document = ALNModuleLoadPlist(lockPath, error);
  if (document == nil) {
    return nil;
  }
  if (![document[@"modules"] isKindOfClass:[NSArray class]]) {
    if (error != NULL) {
      *error = ALNModuleError(10,
                              @"config/modules.plist must contain a modules array",
                              lockPath,
                              nil);
    }
    return nil;
  }
  return document;
}

+ (BOOL)writeModulesLockDocument:(NSDictionary *)document
                         appRoot:(NSString *)appRoot
                           error:(NSError **)error {
  NSArray *entries = [document[@"modules"] isKindOfClass:[NSArray class]] ? document[@"modules"] : @[];
  NSMutableArray<NSDictionary *> *normalizedEntries = [NSMutableArray array];
  for (NSDictionary *entry in entries) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *identifier = ALNModuleTrim(entry[@"identifier"]);
    if (!ALNModuleIdentifierIsValid(identifier)) {
      if (error != NULL) {
        *error = ALNModuleError(11,
                                [NSString stringWithFormat:@"modules lock contains invalid identifier %@", identifier ?: @""],
                                nil,
                                nil);
      }
      return NO;
    }
    NSString *path = ALNModuleTrim(entry[@"path"]);
    if ([path length] == 0) {
      path = [NSString stringWithFormat:@"modules/%@", identifier];
    }
    NSString *version = ALNModuleTrim(entry[@"version"]);
    id enabledValue = entry[@"enabled"];
    BOOL enabled = [enabledValue respondsToSelector:@selector(boolValue)] ? [enabledValue boolValue] : YES;
    NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
    normalized[@"identifier"] = identifier;
    normalized[@"path"] = path;
    normalized[@"enabled"] = @(enabled);
    if ([version length] > 0) {
      normalized[@"version"] = version;
    }
    [normalizedEntries addObject:normalized];
  }
  [normalizedEntries sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    return [left[@"identifier"] compare:right[@"identifier"]];
  }];

  NSDictionary *finalDocument = @{ @"modules" : normalizedEntries };
  NSString *lockPath = [appRoot stringByAppendingPathComponent:[self modulesConfigRelativePath]];
  NSString *directory = [lockPath stringByDeletingLastPathComponent];
  if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:error]) {
    return NO;
  }
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:finalDocument
                                                            format:NSPropertyListOpenStepFormat
                                                           options:0
                                                             error:error];
  if (data == nil) {
    return NO;
  }
  return [data writeToFile:lockPath options:NSDataWritingAtomic error:error];
}

+ (NSArray<NSDictionary *> *)installedModuleRecordsAtAppRoot:(NSString *)appRoot
                                                       error:(NSError **)error {
  NSDictionary *document = [self modulesLockDocumentAtAppRoot:appRoot error:error];
  if (document == nil) {
    return nil;
  }

  NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
  for (id rawEntry in document[@"modules"]) {
    if (![rawEntry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *entry = (NSDictionary *)rawEntry;
    NSString *identifier = ALNModuleTrim(entry[@"identifier"]);
    NSString *path = ALNModuleTrim(entry[@"path"]);
    id enabledValue = entry[@"enabled"];
    BOOL enabled = [enabledValue respondsToSelector:@selector(boolValue)] ? [enabledValue boolValue] : YES;
    NSString *version = ALNModuleTrim(entry[@"version"]);
    if (!ALNModuleIdentifierIsValid(identifier)) {
      if (error != NULL) {
        *error = ALNModuleError(12,
                                [NSString stringWithFormat:@"modules lock contains invalid identifier %@", identifier ?: @""],
                                nil,
                                nil);
      }
      return nil;
    }
    if ([path length] == 0) {
      path = [NSString stringWithFormat:@"modules/%@", identifier];
    }
    [records addObject:@{
      @"identifier" : identifier,
      @"path" : path,
      @"enabled" : @(enabled),
      @"version" : version ?: @"",
    }];
  }
  [records sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    return [left[@"identifier"] compare:right[@"identifier"]];
  }];
  return records;
}

+ (ALNModuleDefinition *)moduleDefinitionAtPath:(NSString *)moduleRoot
                                          error:(NSError **)error {
  return [ALNModuleDefinition definitionWithModuleRoot:moduleRoot error:error];
}

+ (NSArray<ALNModuleDefinition *> *)moduleDefinitionsAtAppRoot:(NSString *)appRoot
                                                         error:(NSError **)error {
  NSArray<NSDictionary *> *records = [self installedModuleRecordsAtAppRoot:appRoot error:error];
  if (records == nil) {
    return nil;
  }
  NSMutableArray<ALNModuleDefinition *> *definitions = [NSMutableArray array];
  for (NSDictionary *record in records) {
    if (![record[@"enabled"] boolValue]) {
      continue;
    }
    NSString *identifier = record[@"identifier"];
    NSString *path = ALNModuleResolvePath(appRoot, record[@"path"], nil);
    ALNModuleDefinition *definition = [self moduleDefinitionAtPath:path error:error];
    if (definition == nil) {
      return nil;
    }
    if (![definition.identifier isEqualToString:identifier]) {
      if (error != NULL) {
        *error = ALNModuleError(
            13,
            [NSString stringWithFormat:@"modules lock identifier %@ does not match manifest identifier %@",
                                       identifier ?: @"", definition.identifier ?: @""],
            path,
            nil);
      }
      return nil;
    }
    [definitions addObject:definition];
  }
  return definitions;
}

+ (NSArray<ALNModuleDefinition *> *)sortedModuleDefinitionsAtAppRoot:(NSString *)appRoot
                                                               error:(NSError **)error {
  NSArray<ALNModuleDefinition *> *definitions = [self moduleDefinitionsAtAppRoot:appRoot error:error];
  if (definitions == nil) {
    return nil;
  }

  NSMutableDictionary<NSString *, ALNModuleDefinition *> *byIdentifier = [NSMutableDictionary dictionary];
  for (ALNModuleDefinition *definition in definitions) {
    if (byIdentifier[definition.identifier] != nil) {
      if (error != NULL) {
        *error = ALNModuleError(14,
                                [NSString stringWithFormat:@"duplicate installed module identifier %@", definition.identifier ?: @""],
                                nil,
                                nil);
      }
      return nil;
    }
    if ([definition.compatibleArlenVersion length] > 0 &&
        !ALNModuleVersionMatchesConstraint(ALNModuleSystemFrameworkVersion,
                                           definition.compatibleArlenVersion)) {
      if (error != NULL) {
        *error = ALNModuleError(15,
                                [NSString stringWithFormat:@"module %@ requires Arlen %@", definition.identifier ?: @"", definition.compatibleArlenVersion ?: @""],
                                [NSString stringWithFormat:@"current framework version is %@", ALNModuleSystemFrameworkVersion],
                                nil);
      }
      return nil;
    }
    byIdentifier[definition.identifier] = definition;
  }

  NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *outgoing = [NSMutableDictionary dictionary];
  NSMutableDictionary<NSString *, NSNumber *> *indegree = [NSMutableDictionary dictionary];
  for (ALNModuleDefinition *definition in definitions) {
    outgoing[definition.identifier] = [NSMutableSet set];
    indegree[definition.identifier] = @0;
  }

  for (ALNModuleDefinition *definition in definitions) {
    NSMutableSet<NSString *> *edges = outgoing[definition.identifier];
    for (NSDictionary *dependency in definition.dependencies) {
      NSString *dependencyID = dependency[@"identifier"];
      NSString *versionConstraint = dependency[@"version"];
      BOOL required = [dependency[@"required"] boolValue];
      ALNModuleDefinition *dependencyDefinition = byIdentifier[dependencyID];
      if (dependencyDefinition == nil) {
        if (required) {
          if (error != NULL) {
            *error = ALNModuleError(16,
                                    [NSString stringWithFormat:@"module %@ requires missing dependency %@",
                                                               definition.identifier ?: @"", dependencyID ?: @""],
                                    nil,
                                    nil);
          }
          return nil;
        }
        continue;
      }
      if ([versionConstraint length] > 0 &&
          !ALNModuleVersionMatchesConstraint(dependencyDefinition.version, versionConstraint)) {
        if (error != NULL) {
          *error = ALNModuleError(17,
                                  [NSString stringWithFormat:@"module %@ requires %@ %@", definition.identifier ?: @"", dependencyID ?: @"", versionConstraint ?: @""],
                                  [NSString stringWithFormat:@"installed %@ version is %@", dependencyID ?: @"", dependencyDefinition.version ?: @""],
                                  nil);
        }
        return nil;
      }
      if (![edges containsObject:dependencyID]) {
        [edges addObject:dependencyID];
        indegree[definition.identifier] = @([indegree[definition.identifier] integerValue] + 1);
      }
    }
  }

  NSMutableArray<NSString *> *ready = [NSMutableArray array];
  for (NSString *identifier in [[indegree allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    if ([indegree[identifier] integerValue] == 0) {
      [ready addObject:identifier];
    }
  }

  NSMutableArray<ALNModuleDefinition *> *sorted = [NSMutableArray array];
  while ([ready count] > 0) {
    NSString *nextIdentifier = ready[0];
    [ready removeObjectAtIndex:0];
    ALNModuleDefinition *nextDefinition = byIdentifier[nextIdentifier];
    [sorted addObject:nextDefinition];

    NSArray<NSString *> *allIdentifiers = [[outgoing allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *identifier in allIdentifiers) {
      NSMutableSet<NSString *> *edges = outgoing[identifier];
      if (![edges containsObject:nextIdentifier]) {
        continue;
      }
      [edges removeObject:nextIdentifier];
      NSInteger nextIndegree = [indegree[identifier] integerValue] - 1;
      indegree[identifier] = @(nextIndegree);
      if (nextIndegree == 0 && ![ready containsObject:identifier]) {
        [ready addObject:identifier];
      }
    }
    [ready sortUsingSelector:@selector(compare:)];
  }

  if ([sorted count] != [definitions count]) {
    NSMutableArray<NSString *> *remaining = [NSMutableArray array];
    for (NSString *identifier in [[indegree allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
      if ([indegree[identifier] integerValue] > 0) {
        [remaining addObject:identifier];
      }
    }
    if (error != NULL) {
      *error = ALNModuleError(18,
                              @"cyclic module dependency graph detected",
                              [remaining componentsJoinedByString:@", "],
                              nil);
    }
    return nil;
  }

  NSMutableDictionary<NSString *, NSString *> *publicPrefixes = [NSMutableDictionary dictionary];
  for (ALNModuleDefinition *definition in sorted) {
    for (NSDictionary *mount in definition.publicMounts) {
      NSString *prefix = ALNModuleTrim(mount[@"prefix"]);
      NSString *owner = publicPrefixes[prefix];
      if ([owner length] > 0 && ![owner isEqualToString:definition.identifier]) {
        if (error != NULL) {
          *error = ALNModuleError(
              19,
              [NSString stringWithFormat:@"module public mount prefix collision at %@", prefix ?: @""],
              [NSString stringWithFormat:@"modules %@ and %@ both declare %@", owner, definition.identifier, prefix],
              nil);
        }
        return nil;
      }
      publicPrefixes[prefix] = definition.identifier;
    }
  }

  return sorted;
}

+ (NSDictionary *)configByApplyingModuleDefaultsToConfig:(NSDictionary *)config
                                                 appRoot:(NSString *)appRoot
                                                  strict:(BOOL)strict
                                             diagnostics:(NSArray<NSDictionary *> **)diagnostics
                                                  error:(NSError **)error {
  NSArray<ALNModuleDefinition *> *definitions = [self sortedModuleDefinitionsAtAppRoot:appRoot error:error];
  if (definitions == nil) {
    return nil;
  }

  NSMutableArray<NSDictionary *> *collectedDiagnostics = [NSMutableArray array];
  NSMutableDictionary *moduleDefaults = [NSMutableDictionary dictionary];
  for (ALNModuleDefinition *definition in definitions) {
    ALNModuleMergeDefaultsIntoDictionary(moduleDefaults,
                                         definition.configDefaults ?: @{},
                                         definition.identifier,
                                         @"",
                                         collectedDiagnostics);
  }

  NSMutableDictionary *merged =
      [NSMutableDictionary dictionaryWithDictionary:ALNModuleMergeDictionaries(moduleDefaults, config ?: @{})];

  NSMutableArray<NSString *> *moduleIdentifiers = [NSMutableArray array];
  for (ALNModuleDefinition *definition in definitions) {
    [moduleIdentifiers addObject:definition.identifier];
    for (NSString *requiredKey in definition.requiredConfigKeys) {
      id value = ALNModuleConfigValueForKeyPath(merged, requiredKey);
      if (ALNModuleIsConfigValueMissing(value)) {
        ALNModuleAppendDiagnostic(
            collectedDiagnostics,
            @"error",
            @"module_required_config_missing",
            definition.identifier,
            [NSString stringWithFormat:@"module %@ requires config key %@", definition.identifier ?: @"", requiredKey ?: @""],
            @"set the required config value in config/app.plist or the active environment plist",
            requiredKey);
      }
    }
  }

  NSArray *staticMounts = [config[@"staticMounts"] isKindOfClass:[NSArray class]] ? config[@"staticMounts"] : @[];
  NSMutableSet<NSString *> *appPrefixes = [NSMutableSet set];
  for (NSDictionary *entry in staticMounts) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *prefix = ALNModuleTrim(entry[@"prefix"]);
    if ([prefix length] > 0) {
      [appPrefixes addObject:prefix];
    }
  }
  for (ALNModuleDefinition *definition in definitions) {
    for (NSDictionary *mount in definition.publicMounts) {
      NSString *prefix = ALNModuleTrim(mount[@"prefix"]);
      if ([appPrefixes containsObject:prefix]) {
        ALNModuleAppendDiagnostic(
            collectedDiagnostics,
            @"warning",
            @"module_public_mount_overridden_by_app",
            definition.identifier,
            [NSString stringWithFormat:@"app static mount overrides module public mount %@", prefix ?: @""],
            @"app-owned static mounts take precedence over installed module public assets",
            prefix);
      }
    }
  }

  NSMutableDictionary *moduleMetadata = [NSMutableDictionary dictionary];
  moduleMetadata[@"installed"] = moduleIdentifiers ?: @[];
  moduleMetadata[@"diagnostics"] = collectedDiagnostics ?: @[];
  merged[@"moduleSystem"] = moduleMetadata;

  if (diagnostics != NULL) {
    *diagnostics = [NSArray arrayWithArray:collectedDiagnostics];
  }

  if (strict) {
    for (NSDictionary *entry in collectedDiagnostics) {
      if ([entry[@"status"] isEqualToString:@"error"]) {
        if (error != NULL) {
          *error = ALNModuleError(20,
                                  entry[@"message"] ?: @"module validation failed",
                                  entry[@"detail"],
                                  collectedDiagnostics);
        }
        return nil;
      }
    }
  }

  return [NSDictionary dictionaryWithDictionary:merged];
}

+ (NSArray<NSDictionary *> *)doctorDiagnosticsAtAppRoot:(NSString *)appRoot
                                                 config:(NSDictionary *)config
                                                  error:(NSError **)error {
  NSMutableArray<NSDictionary *> *diagnostics = [NSMutableArray array];
  NSError *moduleError = nil;
  NSDictionary *merged = [self configByApplyingModuleDefaultsToConfig:config
                                                              appRoot:appRoot
                                                               strict:NO
                                                          diagnostics:&diagnostics
                                                                error:&moduleError];
  if (merged == nil) {
    if (moduleError != nil) {
      ALNModuleAppendDiagnostic(diagnostics,
                                @"error",
                                @"module_validation_failed",
                                @"",
                                moduleError.localizedDescription ?: @"module validation failed",
                                [moduleError.userInfo[@"detail"] isKindOfClass:[NSString class]]
                                    ? moduleError.userInfo[@"detail"]
                                    : @"",
                                @"");
    }
    if (error != NULL) {
      *error = moduleError;
    }
    return diagnostics;
  }

  NSArray<NSString *> *installed =
      [merged[@"moduleSystem"][@"installed"] isKindOfClass:[NSArray class]]
          ? merged[@"moduleSystem"][@"installed"]
          : @[];
  ALNModuleAppendDiagnostic(diagnostics,
                            @"pass",
                            @"modules_loaded",
                            @"",
                            [NSString stringWithFormat:@"loaded %lu installed module definitions",
                                                       (unsigned long)[installed count]],
                            @"",
                            @"");
  return diagnostics;
}

+ (NSArray<id<ALNModule>> *)loadModulesForApplication:(ALNApplication *)application
                                                error:(NSError **)error {
  NSString *appRoot = ALNModuleTrim(application.config[@"appRoot"]);
  if ([appRoot length] == 0) {
    return @[];
  }

  NSArray<ALNModuleDefinition *> *definitions = [self sortedModuleDefinitionsAtAppRoot:appRoot error:error];
  if (definitions == nil) {
    return nil;
  }

  NSMutableArray<id<ALNModule>> *loaded = [NSMutableArray array];
  for (ALNModuleDefinition *definition in definitions) {
    Class klass = NSClassFromString(definition.principalClassName);
    if (klass == Nil) {
      if (error != NULL) {
        *error = ALNModuleError(21,
                                [NSString stringWithFormat:@"module class not found: %@", definition.principalClassName ?: @""],
                                definition.identifier,
                                nil);
      }
      return nil;
    }
    id instance = [[klass alloc] init];
    if (![instance conformsToProtocol:@protocol(ALNModule)]) {
      if (error != NULL) {
        *error = ALNModuleError(22,
                                [NSString stringWithFormat:@"%@ does not conform to ALNModule", definition.principalClassName ?: @""],
                                definition.identifier,
                                nil);
      }
      return nil;
    }
    id<ALNModule> module = (id<ALNModule>)instance;
    if (![[module moduleIdentifier] isEqualToString:definition.identifier]) {
      if (error != NULL) {
        *error = ALNModuleError(23,
                                [NSString stringWithFormat:@"module class %@ reported identifier %@ but manifest declares %@",
                                                           definition.principalClassName ?: @"",
                                                           [module moduleIdentifier] ?: @"",
                                                           definition.identifier ?: @""],
                                nil,
                                nil);
      }
      return nil;
    }

    for (NSDictionary *mount in definition.publicMounts) {
      [application mountStaticDirectory:mount[@"directory"]
                               atPrefix:mount[@"prefix"]
                        allowExtensions:mount[@"allowExtensions"]];
    }

    if (![module registerWithApplication:application error:error]) {
      return nil;
    }
    if ([module respondsToSelector:@selector(pluginsForApplication:)]) {
      NSArray<id<ALNPlugin>> *plugins = [module pluginsForApplication:application];
      for (id plugin in plugins ?: @[]) {
        if (![application registerPlugin:plugin error:error]) {
          return nil;
        }
      }
    }
    if ([module conformsToProtocol:@protocol(ALNLifecycleHook)]) {
      [application registerLifecycleHook:(id<ALNLifecycleHook>)module];
    }
    [loaded addObject:module];
  }

  return loaded;
}

+ (NSArray<NSDictionary *> *)migrationPlansAtAppRoot:(NSString *)appRoot
                                              config:(NSDictionary *)config
                                               error:(NSError **)error {
  (void)config;
  NSArray<ALNModuleDefinition *> *definitions = [self sortedModuleDefinitionsAtAppRoot:appRoot error:error];
  if (definitions == nil) {
    return nil;
  }
  NSMutableArray<NSDictionary *> *plans = [NSMutableArray array];
  for (ALNModuleDefinition *definition in definitions) {
    if (!ALNModuleDirectoryExists(definition.migrationPath)) {
      continue;
    }
    [plans addObject:@{
      @"identifier" : definition.identifier,
      @"version" : definition.version,
      @"path" : definition.migrationPath,
      @"databaseTarget" : definition.migrationDatabaseTarget ?: @"default",
      @"namespace" : definition.migrationNamespace ?: definition.identifier,
    }];
  }
  return plans;
}

+ (BOOL)stagePublicAssetsAtAppRoot:(NSString *)appRoot
                         outputDir:(NSString *)outputDir
                       stagedFiles:(NSArray<NSString *> **)stagedFiles
                             error:(NSError **)error {
  NSArray<ALNModuleDefinition *> *definitions = [self sortedModuleDefinitionsAtAppRoot:appRoot error:error];
  if (definitions == nil) {
    return NO;
  }

  NSFileManager *fm = [NSFileManager defaultManager];
  [fm removeItemAtPath:outputDir error:nil];
  if (![fm createDirectoryAtPath:outputDir
     withIntermediateDirectories:YES
                      attributes:nil
                           error:error]) {
    return NO;
  }

  NSMutableArray<NSString *> *relativeFiles = [NSMutableArray array];
  for (ALNModuleDefinition *definition in definitions) {
    if (!ALNModuleDirectoryExists(definition.publicPath)) {
      continue;
    }
    NSString *destinationRoot =
        [outputDir stringByAppendingPathComponent:[NSString stringWithFormat:@"modules/%@", definition.identifier]];

    NSArray<NSString *> *sourceRoots = @[
      definition.publicPath,
      [appRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"public/modules/%@", definition.identifier]],
    ];

    for (NSString *sourceRoot in sourceRoots) {
      if (!ALNModuleDirectoryExists(sourceRoot)) {
        continue;
      }
      NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:sourceRoot];
      for (NSString *relativePath in enumerator) {
        NSString *sourcePath = [sourceRoot stringByAppendingPathComponent:relativePath];
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:sourcePath isDirectory:&isDirectory] || isDirectory) {
          continue;
        }
        NSString *destinationPath = [destinationRoot stringByAppendingPathComponent:relativePath];
        NSString *destinationDir = [destinationPath stringByDeletingLastPathComponent];
        if (![fm createDirectoryAtPath:destinationDir
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:error]) {
          return NO;
        }
        [fm removeItemAtPath:destinationPath error:nil];
        if (![fm copyItemAtPath:sourcePath toPath:destinationPath error:error]) {
          return NO;
        }
        NSString *relativeOutput = [destinationPath substringFromIndex:[[outputDir stringByAppendingString:@"/"] length]];
        if (![relativeFiles containsObject:relativeOutput]) {
          [relativeFiles addObject:relativeOutput];
        }
      }
    }
  }

  [relativeFiles sortUsingSelector:@selector(compare:)];
  if (stagedFiles != NULL) {
    *stagedFiles = relativeFiles;
  }
  return YES;
}

@end

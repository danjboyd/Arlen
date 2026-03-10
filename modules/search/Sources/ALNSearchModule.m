#import "ALNSearchModule.h"

#import "ALNAdminUIModule.h"
#import "ALNApplication.h"
#import "ALNAuthModule.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNJobsModule.h"
#import "ALNRequest.h"

NSString *const ALNSearchModuleErrorDomain = @"Arlen.Modules.Search.Error";

static NSString *const ALNSearchReindexJobIdentifier = @"search.reindex";
static NSUInteger const ALNSearchHistoryLimit = 20;

static NSString *STTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *STLowerTrimmedString(id value) {
  return [[STTrimmedString(value) lowercaseString] copy];
}

static NSError *STError(ALNSearchModuleErrorCode code, NSString *message, NSDictionary *details) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:details ?: @{}];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"search module error";
  return [NSError errorWithDomain:ALNSearchModuleErrorDomain code:code userInfo:userInfo];
}

static NSString *STTitleCaseIdentifier(NSString *identifier) {
  NSArray *parts = [STLowerTrimmedString(identifier) componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"._-/ "]];
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *part in parts) {
    if ([part length] == 0) {
      continue;
    }
    [out addObject:[part.capitalizedString copy]];
  }
  return ([out count] > 0) ? [out componentsJoinedByString:@" "] : @"Search Resource";
}

static NSString *STPathJoin(NSString *prefix, NSString *suffix) {
  NSString *cleanPrefix = STTrimmedString(prefix);
  if ([cleanPrefix length] == 0) {
    cleanPrefix = @"/search";
  }
  if (![cleanPrefix hasPrefix:@"/"]) {
    cleanPrefix = [@"/" stringByAppendingString:cleanPrefix];
  }
  while ([cleanPrefix hasSuffix:@"/"] && [cleanPrefix length] > 1) {
    cleanPrefix = [cleanPrefix substringToIndex:([cleanPrefix length] - 1)];
  }
  NSString *cleanSuffix = STTrimmedString(suffix);
  while ([cleanSuffix hasPrefix:@"/"]) {
    cleanSuffix = [cleanSuffix substringFromIndex:1];
  }
  if ([cleanSuffix length] == 0) {
    return cleanPrefix;
  }
  return [NSString stringWithFormat:@"%@/%@", cleanPrefix, cleanSuffix];
}

static NSString *STConfiguredPath(NSDictionary *moduleConfig, NSString *key, NSString *defaultSuffix) {
  NSDictionary *paths = [moduleConfig[@"paths"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"paths"] : @{};
  NSString *prefix = STTrimmedString(paths[@"prefix"]);
  if ([prefix length] == 0) {
    prefix = @"/search";
  }
  NSString *override = STTrimmedString(paths[key]);
  if ([override hasPrefix:@"/"]) {
    return override;
  }
  if ([override length] > 0) {
    return STPathJoin(prefix, override);
  }
  return STPathJoin(prefix, defaultSuffix);
}

static NSArray *STNormalizedStringArray(id value) {
  NSMutableArray *strings = [NSMutableArray array];
  for (id entry in [value isKindOfClass:[NSArray class]] ? value : @[]) {
    NSString *normalized = STLowerTrimmedString(entry);
    if ([normalized length] == 0 || [strings containsObject:normalized]) {
      continue;
    }
    [strings addObject:normalized];
  }
  return [strings sortedArrayUsingSelector:@selector(compare:)];
}

static NSString *STPercentEncodedQueryComponent(NSString *value) {
  NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];
  NSMutableCharacterSet *blocked = [allowed mutableCopy];
  [blocked removeCharactersInString:@"=&+?"];
  return [STTrimmedString(value) stringByAddingPercentEncodingWithAllowedCharacters:blocked] ?: @"";
}

static NSDictionary *STJSONParametersFromBody(NSData *body) {
  if ([body length] == 0) {
    return @{};
  }
  id object = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
  return [object isKindOfClass:[NSDictionary class]] ? object : @{};
}

static NSString *STQueryDecodeComponent(NSString *component) {
  NSString *value = [[component ?: @"" stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding];
  return value ?: @"";
}

static NSDictionary *STFormParametersFromBody(NSData *body) {
  if ([body length] == 0) {
    return @{};
  }
  NSString *raw = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] ?: @"";
  NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
  for (NSString *pair in [raw componentsSeparatedByString:@"&"]) {
    if ([pair length] == 0) {
      continue;
    }
    NSArray *parts = [pair componentsSeparatedByString:@"="];
    NSString *key = STQueryDecodeComponent(([parts count] > 0) ? parts[0] : @"");
    if ([key length] == 0) {
      continue;
    }
    NSString *value = STQueryDecodeComponent(([parts count] > 1) ? [[parts subarrayWithRange:NSMakeRange(1, [parts count] - 1)] componentsJoinedByString:@"="] : @"");
    parameters[key] = value ?: @"";
  }
  return parameters;
}

static BOOL STRolesAllowAccess(NSArray *grantedRoles, NSArray *configuredRoles) {
  NSSet *granted = [NSSet setWithArray:[grantedRoles isKindOfClass:[NSArray class]] ? grantedRoles : @[]];
  for (NSString *role in [configuredRoles isKindOfClass:[NSArray class]] ? configuredRoles : @[]) {
    if ([granted containsObject:role]) {
      return YES;
    }
  }
  return NO;
}

static NSString *STStringifyValue(id value) {
  if ([value isKindOfClass:[NSString class]]) {
    return value;
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [value stringValue];
  }
  if ([value isKindOfClass:[NSArray class]]) {
    NSMutableArray *parts = [NSMutableArray array];
    for (id entry in (NSArray *)value) {
      NSString *piece = STStringifyValue(entry);
      if ([piece length] > 0) {
        [parts addObject:piece];
      }
    }
    return [parts componentsJoinedByString:@" "];
  }
  return @"";
}

static NSArray *STSortedArrayFromValues(id values, NSString *key) {
  NSArray *array = [values isKindOfClass:[NSArray class]] ? values : @[];
  return [array sortedArrayUsingComparator:^NSComparisonResult(id lhs, id rhs) {
    NSString *left = STLowerTrimmedString([lhs isKindOfClass:[NSDictionary class]] ? lhs[key] : @"");
    NSString *right = STLowerTrimmedString([rhs isKindOfClass:[NSDictionary class]] ? rhs[key] : @"");
    return [left compare:right];
  }];
}

@interface ALNSearchModuleRuntime ()

@property(nonatomic, copy, readwrite) NSString *prefix;
@property(nonatomic, copy, readwrite) NSString *apiPrefix;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *accessRoles;
@property(nonatomic, assign, readwrite) NSUInteger minimumAuthAssuranceLevel;
@property(nonatomic, strong, readwrite, nullable) ALNApplication *application;
@property(nonatomic, copy) NSDictionary *moduleConfig;
@property(nonatomic, strong) NSMutableDictionary *resourceDefinitionsByIdentifier;
@property(nonatomic, strong) NSMutableDictionary *resourceMetadataByIdentifier;
@property(nonatomic, strong) NSMutableDictionary *indexedDocumentsByResource;
@property(nonatomic, strong) NSMutableDictionary *statusByResource;
@property(nonatomic, strong) NSMutableArray *reindexHistory;
@property(nonatomic, strong) NSLock *lock;

@end

@interface ALNSearchReindexJob : NSObject <ALNJobsJobDefinition>
@end

@interface ALNSearchAdminRuntimeBackedResource : NSObject <ALNSearchResourceDefinition>

@property(nonatomic, strong) ALNAdminUIModuleRuntime *adminRuntime;
@property(nonatomic, copy) NSDictionary *metadata;

- (instancetype)initWithAdminRuntime:(ALNAdminUIModuleRuntime *)adminRuntime
                             metadata:(NSDictionary *)metadata;

@end

@interface ALNSearchAdminResource : NSObject <ALNAdminUIResource>

@property(nonatomic, strong) ALNSearchModuleRuntime *runtime;

- (instancetype)initWithRuntime:(ALNSearchModuleRuntime *)runtime;

@end

@interface ALNSearchAdminResourceProvider : NSObject <ALNAdminUIResourceProvider>
@end

@interface ALNSearchModuleController : ALNController

@property(nonatomic, strong) ALNSearchModuleRuntime *runtime;
@property(nonatomic, strong) ALNAuthModuleRuntime *authRuntime;

@end

@implementation ALNSearchReindexJob

- (NSString *)jobsModuleJobIdentifier {
  return ALNSearchReindexJobIdentifier;
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Search Reindex",
    @"queue" : @"default",
    @"maxAttempts" : @2,
  };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  NSString *resource = STLowerTrimmedString(payload[@"resource"]);
  if ([resource length] > 0) {
    return YES;
  }
  if (error != NULL) {
    *error = STError(ALNSearchModuleErrorValidationFailed, @"resource is required", nil);
  }
  return NO;
}

- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error {
  (void)context;
  return ([[ALNSearchModuleRuntime sharedRuntime] processReindexJobPayload:payload error:error] != nil);
}

@end

@implementation ALNSearchAdminRuntimeBackedResource

- (instancetype)initWithAdminRuntime:(ALNAdminUIModuleRuntime *)adminRuntime
                             metadata:(NSDictionary *)metadata {
  self = [super init];
  if (self != nil) {
    _adminRuntime = adminRuntime;
    _metadata = [metadata isKindOfClass:[NSDictionary class]] ? [metadata copy] : @{};
  }
  return self;
}

- (NSString *)searchModuleResourceIdentifier {
  return STLowerTrimmedString(self.metadata[@"identifier"]);
}

- (NSDictionary *)searchModuleResourceMetadata {
  NSString *identifier = [self searchModuleResourceIdentifier];
  NSArray *fields = [self.metadata[@"fields"] isKindOfClass:[NSArray class]] ? self.metadata[@"fields"] : @[];
  NSMutableArray *indexedFields = [NSMutableArray array];
  NSMutableArray *filters = [NSMutableArray array];
  NSMutableArray *sorts = [NSMutableArray array];
  for (NSDictionary *field in STSortedArrayFromValues(fields, @"name")) {
    NSString *name = STLowerTrimmedString(field[@"name"]);
    if ([name length] == 0) {
      continue;
    }
    [indexedFields addObject:name];
    [filters addObject:@{ @"name" : name, @"label" : field[@"label"] ?: STTitleCaseIdentifier(name), @"operators" : @[ @"eq", @"contains" ] }];
    [sorts addObject:@{ @"name" : name, @"label" : field[@"label"] ?: STTitleCaseIdentifier(name) }];
  }
  NSDictionary *paths = [self.metadata[@"paths"] isKindOfClass:[NSDictionary class]] ? self.metadata[@"paths"] : @{};
  return @{
    @"label" : self.metadata[@"label"] ?: STTitleCaseIdentifier(identifier),
    @"summary" : self.metadata[@"summary"] ?: @"",
    @"identifierField" : self.metadata[@"identifierField"] ?: @"id",
    @"primaryField" : self.metadata[@"primaryField"] ?: self.metadata[@"identifierField"] ?: @"id",
    @"indexedFields" : indexedFields,
    @"filters" : filters,
    @"sorts" : sorts,
    @"pathTemplate" : paths[@"html_detail_template"] ?: @"",
    @"source" : @"admin-ui",
    @"adminIntegrated" : @YES,
  };
}

- (NSArray<NSDictionary *> *)searchModuleDocumentsForRuntime:(ALNSearchModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)runtime;
  NSString *identifier = [self searchModuleResourceIdentifier];
  return [self.adminRuntime listRecordsForResourceIdentifier:identifier query:nil limit:500 offset:0 error:error];
}

@end

@implementation ALNSearchModuleRuntime

+ (instancetype)sharedRuntime {
  static ALNSearchModuleRuntime *runtime = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    runtime = [[ALNSearchModuleRuntime alloc] init];
  });
  return runtime;
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _prefix = @"/search";
    _apiPrefix = @"/search/api";
    _accessRoles = @[ @"operator", @"admin" ];
    _minimumAuthAssuranceLevel = 2;
    _moduleConfig = @{};
    _resourceDefinitionsByIdentifier = [NSMutableDictionary dictionary];
    _resourceMetadataByIdentifier = [NSMutableDictionary dictionary];
    _indexedDocumentsByResource = [NSMutableDictionary dictionary];
    _statusByResource = [NSMutableDictionary dictionary];
    _reindexHistory = [NSMutableArray array];
    _lock = [[NSLock alloc] init];
  }
  return self;
}

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError **)error {
  if (application == nil) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorInvalidConfiguration, @"search module requires an application", nil);
    }
    return NO;
  }

  ALNJobsModuleRuntime *jobsRuntime = [ALNJobsModuleRuntime sharedRuntime];
  if (jobsRuntime.application == nil || jobsRuntime.jobsAdapter == nil) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorInvalidConfiguration,
                       @"search module requires the jobs module to be configured first",
                       nil);
    }
    return NO;
  }

  NSDictionary *moduleConfig =
      [application.config[@"searchModule"] isKindOfClass:[NSDictionary class]] ? application.config[@"searchModule"] : @{};
  NSDictionary *access = [moduleConfig[@"access"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"access"] : @{};
  NSArray *roles = STNormalizedStringArray(access[@"roles"]);
  NSDictionary *adminUI = [moduleConfig[@"adminUI"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"adminUI"] : @{};

  self.application = application;
  self.moduleConfig = moduleConfig;
  self.prefix = STConfiguredPath(moduleConfig, @"prefix", @"");
  self.apiPrefix = STConfiguredPath(moduleConfig, @"apiPrefix", @"api");
  self.accessRoles = ([roles count] > 0) ? roles : @[ @"operator", @"admin" ];
  self.minimumAuthAssuranceLevel =
      [access[@"minimumAuthAssuranceLevel"] respondsToSelector:@selector(unsignedIntegerValue)]
          ? [access[@"minimumAuthAssuranceLevel"] unsignedIntegerValue]
          : 2;
  if (self.minimumAuthAssuranceLevel == 0) {
    self.minimumAuthAssuranceLevel = 2;
  }

  [self.lock lock];
  [self.resourceDefinitionsByIdentifier removeAllObjects];
  [self.resourceMetadataByIdentifier removeAllObjects];
  [self.indexedDocumentsByResource removeAllObjects];
  [self.statusByResource removeAllObjects];
  [self.reindexHistory removeAllObjects];
  [self.lock unlock];

  if (![jobsRuntime registerSystemJobDefinition:[[ALNSearchReindexJob alloc] init] error:error]) {
    return NO;
  }

  NSArray *providerClasses =
      [moduleConfig[@"resourceProviderClasses"] isKindOfClass:[NSArray class]]
          ? moduleConfig[@"resourceProviderClasses"]
          : ([moduleConfig[@"providers"] isKindOfClass:[NSDictionary class]] &&
                     [moduleConfig[@"providers"][@"classes"] isKindOfClass:[NSArray class]]
                 ? moduleConfig[@"providers"][@"classes"]
                 : @[]);
  for (id rawClassName in providerClasses) {
    NSString *className = STTrimmedString(rawClassName);
    if ([className length] == 0) {
      continue;
    }
    Class klass = NSClassFromString(className);
    id provider = (klass != Nil) ? [[klass alloc] init] : nil;
    if (provider == nil || ![provider conformsToProtocol:@protocol(ALNSearchResourceProvider)]) {
      if (error != NULL) {
        *error = STError(ALNSearchModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"search resource provider %@ is invalid", className],
                         @{ @"class" : className ?: @"" });
      }
      return NO;
    }
    NSError *providerError = nil;
    NSArray *definitions = [(id<ALNSearchResourceProvider>)provider searchModuleResourcesForRuntime:self error:&providerError];
    if (definitions == nil) {
      if (error != NULL) {
        *error = providerError ?: STError(ALNSearchModuleErrorInvalidConfiguration,
                                          @"search resource provider failed to load definitions",
                                          @{ @"class" : className ?: @"" });
      }
      return NO;
    }
    for (id definition in definitions) {
      if (![self registerResourceDefinition:definition source:className allowExisting:NO error:error]) {
        return NO;
      }
    }
  }

  BOOL autoResources = ![adminUI[@"autoResources"] respondsToSelector:@selector(boolValue)] || [adminUI[@"autoResources"] boolValue];
  NSArray *includeIdentifiers = STNormalizedStringArray(adminUI[@"includeIdentifiers"]);
  NSArray *excludeIdentifiers = STNormalizedStringArray(adminUI[@"excludeIdentifiers"]);
  ALNAdminUIModuleRuntime *adminRuntime = [ALNAdminUIModuleRuntime sharedRuntime];
  if (autoResources && adminRuntime.mountedApplication != nil) {
    for (NSDictionary *metadata in [adminRuntime registeredResources]) {
      NSString *identifier = STLowerTrimmedString(metadata[@"identifier"]);
      if ([identifier length] == 0 || [identifier isEqualToString:@"search_indexes"]) {
        continue;
      }
      if ([includeIdentifiers count] > 0 && ![includeIdentifiers containsObject:identifier]) {
        continue;
      }
      if ([excludeIdentifiers containsObject:identifier]) {
        continue;
      }
      ALNSearchAdminRuntimeBackedResource *resource =
          [[ALNSearchAdminRuntimeBackedResource alloc] initWithAdminRuntime:adminRuntime metadata:metadata];
      if (![self registerResourceDefinition:resource source:@"admin-ui" allowExisting:YES error:error]) {
        return NO;
      }
    }
  }

  return YES;
}

- (BOOL)registerResourceDefinition:(id)definition
                            source:(NSString *)source
                     allowExisting:(BOOL)allowExisting
                             error:(NSError **)error {
  if (definition == nil || ![definition conformsToProtocol:@protocol(ALNSearchResourceDefinition)]) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorInvalidConfiguration, @"search definition must conform to ALNSearchResourceDefinition", nil);
    }
    return NO;
  }
  NSString *identifier = STLowerTrimmedString([(id<ALNSearchResourceDefinition>)definition searchModuleResourceIdentifier]);
  if ([identifier length] == 0) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorInvalidConfiguration, @"search resource identifier is required", nil);
    }
    return NO;
  }

  [self.lock lock];
  BOOL exists = (self.resourceDefinitionsByIdentifier[identifier] != nil);
  [self.lock unlock];
  if (exists && allowExisting) {
    return YES;
  }
  if (exists) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorInvalidConfiguration,
                       [NSString stringWithFormat:@"duplicate search resource %@", identifier],
                       @{ @"identifier" : identifier });
    }
    return NO;
  }

  NSDictionary *normalized = [self normalizedMetadataForDefinition:definition source:source error:error];
  if (normalized == nil) {
    return NO;
  }

  [self.lock lock];
  self.resourceDefinitionsByIdentifier[identifier] = definition;
  self.resourceMetadataByIdentifier[identifier] = normalized;
  self.indexedDocumentsByResource[identifier] = @[];
  self.statusByResource[identifier] = @{
    @"identifier" : identifier,
    @"label" : normalized[@"label"] ?: STTitleCaseIdentifier(identifier),
    @"documentCount" : @0,
    @"lastIndexedAt" : @"",
    @"lastJobID" : @"",
    @"lastError" : @"",
    @"source" : normalized[@"source"] ?: @"provider",
  };
  [self.lock unlock];
  return YES;
}

- (NSDictionary *)normalizedMetadataForDefinition:(id<ALNSearchResourceDefinition>)definition
                                           source:(NSString *)source
                                            error:(NSError **)error {
  NSString *identifier = STLowerTrimmedString([definition searchModuleResourceIdentifier]);
  NSDictionary *rawMetadata = [[definition searchModuleResourceMetadata] isKindOfClass:[NSDictionary class]]
                                  ? [definition searchModuleResourceMetadata]
                                  : @{};
  NSString *label = STTrimmedString(rawMetadata[@"label"]);
  if ([label length] == 0) {
    label = STTitleCaseIdentifier(identifier);
  }
  NSString *summary = STTrimmedString(rawMetadata[@"summary"]);
  NSString *identifierField = STLowerTrimmedString(rawMetadata[@"identifierField"]);
  if ([identifierField length] == 0) {
    identifierField = @"id";
  }
  NSString *primaryField = STLowerTrimmedString(rawMetadata[@"primaryField"]);
  if ([primaryField length] == 0) {
    primaryField = identifierField;
  }
  NSArray *indexedFields = STNormalizedStringArray(rawMetadata[@"indexedFields"]);
  if ([indexedFields count] == 0) {
    indexedFields = @[ primaryField ];
  }
  NSMutableArray *filters = [NSMutableArray array];
  for (NSDictionary *entry in STSortedArrayFromValues(rawMetadata[@"filters"], @"name")) {
    NSString *name = STLowerTrimmedString(entry[@"name"]);
    if ([name length] == 0) {
      continue;
    }
    [filters addObject:@{
      @"name" : name,
      @"label" : entry[@"label"] ?: STTitleCaseIdentifier(name),
      @"operators" : ([STNormalizedStringArray(entry[@"operators"]) count] > 0) ? STNormalizedStringArray(entry[@"operators"]) : @[ @"eq" ],
    }];
  }
  NSMutableArray *sorts = [NSMutableArray array];
  for (NSDictionary *entry in STSortedArrayFromValues(rawMetadata[@"sorts"], @"name")) {
    NSString *name = STLowerTrimmedString(entry[@"name"]);
    if ([name length] == 0) {
      continue;
    }
    [sorts addObject:@{
      @"name" : name,
      @"label" : entry[@"label"] ?: STTitleCaseIdentifier(name),
    }];
  }
  if ([sorts count] == 0) {
    [sorts addObject:@{ @"name" : primaryField, @"label" : STTitleCaseIdentifier(primaryField) }];
  }
  return @{
    @"identifier" : identifier,
    @"label" : label,
    @"summary" : summary ?: @"",
    @"identifierField" : identifierField,
    @"primaryField" : primaryField,
    @"indexedFields" : indexedFields,
    @"filters" : filters,
    @"sorts" : sorts,
    @"pathTemplate" : STTrimmedString(rawMetadata[@"pathTemplate"]),
    @"source" : ([STTrimmedString(rawMetadata[@"source"]) length] > 0) ? STTrimmedString(rawMetadata[@"source"]) : STTrimmedString(source),
    @"adminIntegrated" : @([rawMetadata[@"adminIntegrated"] respondsToSelector:@selector(boolValue)] ? [rawMetadata[@"adminIntegrated"] boolValue] : NO),
  };
}

- (NSDictionary *)resolvedConfigSummary {
  NSDictionary *adminUI = [self.moduleConfig[@"adminUI"] isKindOfClass:[NSDictionary class]] ? self.moduleConfig[@"adminUI"] : @{};
  return @{
    @"prefix" : self.prefix ?: @"/search",
    @"apiPrefix" : self.apiPrefix ?: @"/search/api",
    @"accessRoles" : self.accessRoles ?: @[ @"operator", @"admin" ],
    @"minimumAuthAssuranceLevel" : @(self.minimumAuthAssuranceLevel),
    @"resourceCount" : @([[self registeredResources] count]),
    @"adminUIAutoResources" : @(![adminUI[@"autoResources"] respondsToSelector:@selector(boolValue)] || [adminUI[@"autoResources"] boolValue]),
  };
}

- (NSArray<NSDictionary *> *)registeredResources {
  [self.lock lock];
  NSArray *resources = [self.resourceMetadataByIdentifier allValues];
  [self.lock unlock];
  return STSortedArrayFromValues(resources, @"identifier");
}

- (NSDictionary *)resourceMetadataForIdentifier:(NSString *)identifier {
  [self.lock lock];
  NSDictionary *metadata = self.resourceMetadataByIdentifier[STLowerTrimmedString(identifier)];
  [self.lock unlock];
  return metadata;
}

- (NSDictionary *)queueReindexForResourceIdentifier:(NSString *)identifier
                                              error:(NSError **)error {
  NSString *resourceIdentifier = STLowerTrimmedString(identifier);
  if ([resourceIdentifier length] == 0) {
    resourceIdentifier = @"*";
  } else if ([self resourceMetadataForIdentifier:resourceIdentifier] == nil) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorNotFound,
                       [NSString stringWithFormat:@"unknown search resource %@", resourceIdentifier],
                       @{ @"resource" : resourceIdentifier });
    }
    return nil;
  }
  NSString *jobID = [[ALNJobsModuleRuntime sharedRuntime] enqueueJobIdentifier:ALNSearchReindexJobIdentifier
                                                                       payload:@{ @"resource" : resourceIdentifier }
                                                                       options:nil
                                                                         error:error];
  if ([jobID length] == 0) {
    return nil;
  }

  NSArray *targets = [resourceIdentifier isEqualToString:@"*"] ? [[self registeredResources] valueForKey:@"identifier"] : @[ resourceIdentifier ];
  NSString *queuedAt = [[NSDate date] description];
  [self.lock lock];
  for (NSString *target in targets) {
    NSDictionary *existing = [self.statusByResource[target] isKindOfClass:[NSDictionary class]] ? self.statusByResource[target] : @{};
    NSMutableDictionary *status = [NSMutableDictionary dictionaryWithDictionary:existing];
    status[@"lastJobID"] = jobID;
    status[@"queuedAt"] = queuedAt;
    self.statusByResource[target] = status;
  }
  [self.lock unlock];

  return @{
    @"jobID" : jobID,
    @"resource" : resourceIdentifier,
  };
}

- (NSDictionary *)normalizedDocumentForRecord:(NSDictionary *)record
                                     metadata:(NSDictionary *)metadata {
  NSString *identifierField = metadata[@"identifierField"] ?: @"id";
  NSString *primaryField = metadata[@"primaryField"] ?: identifierField;
  NSString *recordID = STTrimmedString(record[identifierField]);
  if ([recordID length] == 0) {
    return nil;
  }

  NSMutableArray *parts = [NSMutableArray array];
  for (NSString *field in metadata[@"indexedFields"] ?: @[]) {
    NSString *value = STStringifyValue(record[field]);
    if ([value length] > 0) {
      [parts addObject:value];
    }
  }
  NSString *title = STStringifyValue(record[primaryField]);
  if ([title length] == 0) {
    title = recordID;
  }

  NSString *summary = @"";
  for (NSString *field in metadata[@"indexedFields"] ?: @[]) {
    if ([field isEqualToString:primaryField]) {
      continue;
    }
    summary = STStringifyValue(record[field]);
    if ([summary length] > 0) {
      break;
    }
  }

  NSString *pathTemplate = STTrimmedString(metadata[@"pathTemplate"]);
  NSString *path = @"";
  if ([pathTemplate length] > 0) {
    path = [pathTemplate stringByReplacingOccurrencesOfString:@":identifier" withString:recordID];
  }

  return @{
    @"resource" : metadata[@"identifier"] ?: @"",
    @"recordID" : recordID,
    @"title" : title ?: recordID,
    @"summary" : summary ?: @"",
    @"searchableText" : [parts componentsJoinedByString:@" "],
    @"path" : path ?: @"",
    @"record" : [record isKindOfClass:[NSDictionary class]] ? record : @{},
  };
}

- (NSDictionary *)reindexResourceIdentifier:(NSString *)identifier
                                      error:(NSError **)error {
  NSString *resourceIdentifier = STLowerTrimmedString(identifier);
  NSDictionary *metadata = [self resourceMetadataForIdentifier:resourceIdentifier];
  if (metadata == nil) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorNotFound,
                       [NSString stringWithFormat:@"unknown search resource %@", resourceIdentifier],
                       @{ @"resource" : resourceIdentifier });
    }
    return nil;
  }
  id<ALNSearchResourceDefinition> definition = nil;
  [self.lock lock];
  definition = self.resourceDefinitionsByIdentifier[resourceIdentifier];
  [self.lock unlock];
  NSError *loadError = nil;
  NSArray *records = [definition searchModuleDocumentsForRuntime:self error:&loadError];
  if (records == nil) {
    if (error != NULL) {
      *error = loadError ?: STError(ALNSearchModuleErrorExecutionFailed, @"search resource failed to build documents", @{ @"resource" : resourceIdentifier });
    }
    return nil;
  }

  NSMutableArray *documents = [NSMutableArray array];
  for (NSDictionary *record in records) {
    if (![record isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *document = [self normalizedDocumentForRecord:record metadata:metadata];
    if (document != nil) {
      [documents addObject:document];
    }
  }
  documents = [[documents sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
    NSString *left = STTrimmedString(lhs[@"recordID"]);
    NSString *right = STTrimmedString(rhs[@"recordID"]);
    return [left compare:right];
  }] mutableCopy];

  NSString *indexedAt = [[NSDate date] description];
  [self.lock lock];
  self.indexedDocumentsByResource[resourceIdentifier] = [NSArray arrayWithArray:documents];
  NSDictionary *existing = [self.statusByResource[resourceIdentifier] isKindOfClass:[NSDictionary class]] ? self.statusByResource[resourceIdentifier] : @{};
  NSMutableDictionary *status = [NSMutableDictionary dictionaryWithDictionary:existing];
  status[@"documentCount"] = @([documents count]);
  status[@"lastIndexedAt"] = indexedAt;
  status[@"lastError"] = @"";
  self.statusByResource[resourceIdentifier] = status;
  NSDictionary *historyEntry = @{
    @"resource" : resourceIdentifier,
    @"documentCount" : @([documents count]),
    @"indexedAt" : indexedAt,
    @"jobID" : status[@"lastJobID"] ?: @"",
  };
  [self.reindexHistory addObject:historyEntry];
  while ([self.reindexHistory count] > ALNSearchHistoryLimit) {
    [self.reindexHistory removeObjectAtIndex:0];
  }
  [self.lock unlock];

  return @{
    @"identifier" : resourceIdentifier,
    @"documentCount" : @([documents count]),
  };
}

- (NSDictionary *)processReindexJobPayload:(NSDictionary *)payload
                                     error:(NSError **)error {
  NSString *resource = STLowerTrimmedString(payload[@"resource"]);
  if ([resource length] == 0) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorValidationFailed, @"resource is required", nil);
    }
    return nil;
  }

  NSArray *targets = [resource isEqualToString:@"*"] ? [[self registeredResources] valueForKey:@"identifier"] : @[ resource ];
  NSMutableArray *results = [NSMutableArray array];
  NSUInteger totalDocuments = 0;
  for (NSString *target in targets) {
    NSDictionary *summary = [self reindexResourceIdentifier:target error:error];
    if (summary == nil) {
      [self.lock lock];
      NSDictionary *existing = [self.statusByResource[target] isKindOfClass:[NSDictionary class]] ? self.statusByResource[target] : @{};
      NSMutableDictionary *status = [NSMutableDictionary dictionaryWithDictionary:existing];
      status[@"lastError"] = [*error localizedDescription] ?: @"reindex failed";
      self.statusByResource[target] = status;
      [self.lock unlock];
      return nil;
    }
    totalDocuments += [summary[@"documentCount"] unsignedIntegerValue];
    [results addObject:summary];
  }
  return @{
    @"resources" : results,
    @"resourceCount" : @([results count]),
    @"documentCount" : @(totalDocuments),
  };
}

- (BOOL)document:(NSDictionary *)document matchesFilters:(NSDictionary *)filters
        metadata:(NSDictionary *)metadata
           error:(NSError **)error {
  NSDictionary *record = [document[@"record"] isKindOfClass:[NSDictionary class]] ? document[@"record"] : @{};
  NSArray *allowedFilters = [metadata[@"filters"] isKindOfClass:[NSArray class]] ? metadata[@"filters"] : @[];
  NSMutableDictionary *allowedByField = [NSMutableDictionary dictionary];
  for (NSDictionary *entry in allowedFilters) {
    NSString *name = STLowerTrimmedString(entry[@"name"]);
    if ([name length] == 0) {
      continue;
    }
    allowedByField[name] = entry;
  }

  for (NSString *rawKey in [filters allKeys]) {
    NSString *normalizedKey = STLowerTrimmedString(rawKey);
    NSString *field = normalizedKey;
    NSString *operatorName = @"eq";
    NSRange range = [normalizedKey rangeOfString:@"__"];
    if (range.location != NSNotFound) {
      field = [normalizedKey substringToIndex:range.location];
      operatorName = [normalizedKey substringFromIndex:(range.location + range.length)];
    }
    NSDictionary *filterMetadata = allowedByField[field];
    if (filterMetadata == nil) {
      if (error != NULL) {
        *error = STError(ALNSearchModuleErrorValidationFailed,
                         [NSString stringWithFormat:@"unsupported filter %@", field],
                         @{ @"field" : field ?: @"" });
      }
      return NO;
    }
    NSArray *operators = [filterMetadata[@"operators"] isKindOfClass:[NSArray class]] ? filterMetadata[@"operators"] : @[ @"eq" ];
    if (![operators containsObject:operatorName]) {
      if (error != NULL) {
        *error = STError(ALNSearchModuleErrorValidationFailed,
                         [NSString stringWithFormat:@"unsupported operator %@", operatorName],
                         @{ @"field" : field ?: @"", @"operator" : operatorName ?: @"" });
      }
      return NO;
    }
    NSString *expected = STStringifyValue(filters[rawKey]);
    NSString *actual = STStringifyValue(record[field]);
    if ([operatorName isEqualToString:@"contains"]) {
      if ([[actual lowercaseString] rangeOfString:[expected lowercaseString]].location == NSNotFound) {
        return NO;
      }
    } else if (![[actual lowercaseString] isEqualToString:[expected lowercaseString]]) {
      return NO;
    }
  }
  return YES;
}

- (NSDictionary *)searchQuery:(NSString *)query
           resourceIdentifier:(NSString *)resourceIdentifier
                      filters:(NSDictionary *)filters
                         sort:(NSString *)sort
                        limit:(NSUInteger)limit
                       offset:(NSUInteger)offset
                        error:(NSError **)error {
  NSString *resource = STLowerTrimmedString(resourceIdentifier);
  NSArray *resourceMetadata = nil;
  if ([resource length] > 0) {
    NSDictionary *metadata = [self resourceMetadataForIdentifier:resource];
    if (metadata == nil) {
      if (error != NULL) {
        *error = STError(ALNSearchModuleErrorNotFound,
                         [NSString stringWithFormat:@"unknown search resource %@", resource],
                         @{ @"resource" : resource });
      }
      return nil;
    }
    resourceMetadata = @[ metadata ];
  } else {
    resourceMetadata = [self registeredResources];
  }

  NSString *normalizedQuery = [[STTrimmedString(query) lowercaseString] copy];
  NSString *normalizedSort = STLowerTrimmedString(sort);
  if ([normalizedSort length] == 0) {
    normalizedSort = @"relevance";
  }

  NSMutableArray *matches = [NSMutableArray array];
  for (NSDictionary *metadata in resourceMetadata) {
    NSString *identifier = metadata[@"identifier"];
    NSArray *documents = nil;
    [self.lock lock];
    documents = [self.indexedDocumentsByResource[identifier] isKindOfClass:[NSArray class]] ? self.indexedDocumentsByResource[identifier] : @[];
    [self.lock unlock];

    NSMutableDictionary *allowedSorts = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in metadata[@"sorts"] ?: @[]) {
      NSString *name = STLowerTrimmedString(entry[@"name"]);
      if ([name length] > 0) {
        allowedSorts[name] = entry;
      }
    }
    if (![normalizedSort isEqualToString:@"relevance"] && [allowedSorts objectForKey:[normalizedSort hasPrefix:@"-"] ? [normalizedSort substringFromIndex:1] : normalizedSort] == nil) {
      if (error != NULL) {
        NSString *field = [normalizedSort hasPrefix:@"-"] ? [normalizedSort substringFromIndex:1] : normalizedSort;
        *error = STError(ALNSearchModuleErrorValidationFailed,
                         [NSString stringWithFormat:@"unsupported sort %@", field],
                         @{ @"field" : field ?: @"" });
      }
      return nil;
    }

    for (NSDictionary *document in documents) {
      if (![self document:document matchesFilters:filters ?: @{} metadata:metadata error:error]) {
        if (error != NULL && *error != NULL) {
          return nil;
        }
        continue;
      }
      NSString *haystack = [STStringifyValue(document[@"searchableText"]) lowercaseString];
      NSUInteger score = 0;
      if ([normalizedQuery length] > 0) {
        NSRange searchRange = NSMakeRange(0, [haystack length]);
        while (searchRange.location != NSNotFound && searchRange.location < [haystack length]) {
          NSRange found = [haystack rangeOfString:normalizedQuery options:0 range:searchRange];
          if (found.location == NSNotFound) {
            break;
          }
          score += 1;
          NSUInteger nextLocation = found.location + found.length;
          if (nextLocation >= [haystack length]) {
            break;
          }
          searchRange = NSMakeRange(nextLocation, [haystack length] - nextLocation);
        }
        if (score == 0) {
          continue;
        }
      }
      NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:document];
      result[@"resourceLabel"] = metadata[@"label"] ?: STTitleCaseIdentifier(identifier);
      result[@"score"] = @(score);
      [matches addObject:result];
    }
  }

  BOOL descending = [normalizedSort hasPrefix:@"-"];
  NSString *sortField = descending ? [normalizedSort substringFromIndex:1] : normalizedSort;
  [matches sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
    if ([sortField isEqualToString:@"relevance"]) {
      NSInteger leftScore = [lhs[@"score"] integerValue];
      NSInteger rightScore = [rhs[@"score"] integerValue];
      if (leftScore != rightScore) {
        return (leftScore > rightScore) ? NSOrderedAscending : NSOrderedDescending;
      }
    } else {
      NSString *leftValue = STStringifyValue(lhs[@"record"][sortField]);
      NSString *rightValue = STStringifyValue(rhs[@"record"][sortField]);
      NSComparisonResult result = [[leftValue lowercaseString] compare:[rightValue lowercaseString]];
      if (result != NSOrderedSame) {
        return descending ? -result : result;
      }
    }
    NSString *leftTitle = STStringifyValue(lhs[@"title"]);
    NSString *rightTitle = STStringifyValue(rhs[@"title"]);
    return [[leftTitle lowercaseString] compare:[rightTitle lowercaseString]];
  }];

  NSUInteger start = MIN(offset, [matches count]);
  NSUInteger sliceLength = MIN(limit > 0 ? limit : 25, ([matches count] - start));
  NSArray *page = [matches subarrayWithRange:NSMakeRange(start, sliceLength)];
  return @{
    @"query" : STTrimmedString(query),
    @"resource" : resource ?: @"",
    @"results" : page ?: @[],
    @"total" : @([matches count]),
    @"limit" : @(limit > 0 ? limit : 25),
    @"offset" : @(offset),
  };
}

- (NSDictionary *)dashboardSummary {
  NSArray *resources = [self registeredResources];
  NSMutableArray *statusRows = [NSMutableArray array];
  NSUInteger documentCount = 0;
  for (NSDictionary *metadata in resources) {
    NSString *identifier = metadata[@"identifier"];
    NSDictionary *status = nil;
    [self.lock lock];
    status = [self.statusByResource[identifier] isKindOfClass:[NSDictionary class]] ? self.statusByResource[identifier] : @{};
    [self.lock unlock];
    documentCount += [status[@"documentCount"] unsignedIntegerValue];
    NSMutableDictionary *row = [NSMutableDictionary dictionaryWithDictionary:status];
    row[@"label"] = metadata[@"label"] ?: status[@"label"] ?: STTitleCaseIdentifier(identifier);
    row[@"adminIntegrated"] = metadata[@"adminIntegrated"] ?: @NO;
    [statusRows addObject:row];
  }

  NSArray *pendingJobs = [[[ALNJobsModuleRuntime sharedRuntime] pendingJobs] filteredArrayUsingPredicate:
      [NSPredicate predicateWithBlock:^BOOL(NSDictionary *job, NSDictionary *bindings) {
        (void)bindings;
        return [STLowerTrimmedString(job[@"job"]) isEqualToString:ALNSearchReindexJobIdentifier];
      }]];
  NSArray *deadJobs = [[[ALNJobsModuleRuntime sharedRuntime] deadLetterJobs] filteredArrayUsingPredicate:
      [NSPredicate predicateWithBlock:^BOOL(NSDictionary *job, NSDictionary *bindings) {
        (void)bindings;
        return [STLowerTrimmedString(job[@"job"]) isEqualToString:ALNSearchReindexJobIdentifier];
      }]];

  [self.lock lock];
  NSArray *history = [NSArray arrayWithArray:self.reindexHistory];
  [self.lock unlock];

  return @{
    @"config" : [self resolvedConfigSummary],
    @"resources" : STSortedArrayFromValues(statusRows, @"identifier"),
    @"history" : history ?: @[],
    @"totals" : @{
      @"resources" : @([resources count]),
      @"documents" : @(documentCount),
      @"pendingJobs" : @([pendingJobs count]),
      @"deadLetters" : @([deadJobs count]),
    },
    @"cards" : @[
      @{ @"label" : @"Resources", @"value" : [NSString stringWithFormat:@"%lu", (unsigned long)[resources count]] },
      @{ @"label" : @"Documents", @"value" : [NSString stringWithFormat:@"%lu", (unsigned long)documentCount] },
      @{ @"label" : @"Queued Reindex Jobs", @"value" : [NSString stringWithFormat:@"%lu", (unsigned long)[pendingJobs count]] },
      @{ @"label" : @"Dead Letters", @"value" : [NSString stringWithFormat:@"%lu", (unsigned long)[deadJobs count]] },
    ],
  };
}

@end

@implementation ALNSearchAdminResource

- (instancetype)initWithRuntime:(ALNSearchModuleRuntime *)runtime {
  self = [super init];
  if (self != nil) {
    _runtime = runtime;
  }
  return self;
}

- (NSString *)adminUIResourceIdentifier {
  return @"search_indexes";
}

- (NSDictionary *)adminUIResourceMetadata {
  return @{
    @"label" : @"Search Indexes",
    @"singularLabel" : @"Search Index",
    @"summary" : @"Inspect registered search resources, indexed counts, and reindex status.",
    @"identifierField" : @"identifier",
    @"primaryField" : @"label",
    @"legacyPath" : @"search/indexes",
    @"fields" : @[
      @{ @"name" : @"label", @"label" : @"Resource", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"identifier", @"label" : @"Identifier", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"documentCount", @"label" : @"Documents", @"kind" : @"integer", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"lastIndexedAt", @"label" : @"Last Indexed", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"lastJobID", @"label" : @"Last Job", @"list" : @NO, @"detail" : @YES },
      @{ @"name" : @"lastError", @"label" : @"Last Error", @"list" : @NO, @"detail" : @YES },
    ],
    @"actions" : @[
      @{ @"name" : @"reindex", @"label" : @"Reindex", @"scope" : @"row", @"method" : @"POST" },
    ],
  };
}

- (NSArray<NSDictionary *> *)adminUIListRecordsMatching:(NSString *)query
                                                  limit:(NSUInteger)limit
                                                 offset:(NSUInteger)offset
                                                  error:(NSError **)error {
  (void)error;
  NSString *search = [STLowerTrimmedString(query) copy];
  NSArray *resources = [self.runtime dashboardSummary][@"resources"];
  NSMutableArray *matches = [NSMutableArray array];
  for (NSDictionary *entry in [resources isKindOfClass:[NSArray class]] ? resources : @[]) {
    NSString *haystack = [[NSString stringWithFormat:@"%@ %@",
                                                     STStringifyValue(entry[@"identifier"]),
                                                     STStringifyValue(entry[@"label"])] lowercaseString];
    if ([search length] > 0 && [haystack rangeOfString:search].location == NSNotFound) {
      continue;
    }
    [matches addObject:entry];
  }
  NSUInteger start = MIN(offset, [matches count]);
  NSUInteger length = MIN(limit, ([matches count] - start));
  return [matches subarrayWithRange:NSMakeRange(start, length)];
}

- (NSDictionary *)adminUIDetailRecordForIdentifier:(NSString *)identifier
                                             error:(NSError **)error {
  NSDictionary *record = nil;
  for (NSDictionary *entry in [self.runtime dashboardSummary][@"resources"] ?: @[]) {
    if ([STLowerTrimmedString(entry[@"identifier"]) isEqualToString:STLowerTrimmedString(identifier)]) {
      record = entry;
      break;
    }
  }
  if (record == nil && error != NULL) {
    *error = STError(ALNSearchModuleErrorNotFound, @"search resource not found", @{ @"resource" : STTrimmedString(identifier) });
  }
  return record;
}

- (NSDictionary *)adminUIUpdateRecordWithIdentifier:(NSString *)identifier
                                         parameters:(NSDictionary *)parameters
                                              error:(NSError **)error {
  (void)identifier;
  (void)parameters;
  if (error != NULL) {
    *error = STError(ALNSearchModuleErrorValidationFailed, @"search index records are not directly editable", nil);
  }
  return nil;
}

- (NSDictionary *)adminUIDashboardSummaryWithError:(NSError **)error {
  (void)error;
  return @{ @"cards" : [self.runtime dashboardSummary][@"cards"] ?: @[] };
}

- (NSDictionary *)adminUIPerformActionNamed:(NSString *)actionName
                                 identifier:(NSString *)identifier
                                 parameters:(NSDictionary *)parameters
                                      error:(NSError **)error {
  (void)parameters;
  if (![[STLowerTrimmedString(actionName) lowercaseString] isEqualToString:@"reindex"]) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorNotFound, @"unknown search action", @{ @"action" : STTrimmedString(actionName) });
    }
    return nil;
  }
  NSDictionary *result = [self.runtime queueReindexForResourceIdentifier:identifier error:error];
  if (result == nil) {
    return nil;
  }
  return @{
    @"record" : [self adminUIDetailRecordForIdentifier:identifier error:NULL] ?: @{},
    @"message" : @"Search reindex queued.",
    @"jobID" : result[@"jobID"] ?: @"",
  };
}

@end

@implementation ALNSearchAdminResourceProvider

- (NSArray<id<ALNAdminUIResource>> *)adminUIResourcesForRuntime:(ALNAdminUIModuleRuntime *)runtime
                                                          error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[ALNSearchAdminResource alloc] initWithRuntime:[ALNSearchModuleRuntime sharedRuntime]] ];
}

@end

@implementation ALNSearchModuleController

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _runtime = [ALNSearchModuleRuntime sharedRuntime];
    _authRuntime = [ALNAuthModuleRuntime sharedRuntime];
  }
  return self;
}

- (NSDictionary *)requestParameters {
  NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:[self params] ?: @{}];
  NSDictionary *bodyParameters = @{};
  NSString *contentType = STLowerTrimmedString([self headerValueForName:@"Content-Type"]);
  if ([contentType containsString:@"application/json"]) {
    bodyParameters = STJSONParametersFromBody(self.context.request.body);
  } else if ([contentType containsString:@"application/x-www-form-urlencoded"]) {
    bodyParameters = STFormParametersFromBody(self.context.request.body);
  }
  [parameters addEntriesFromDictionary:bodyParameters ?: @{}];
  return parameters;
}

- (NSDictionary *)pageContextWithTitle:(NSString *)title
                               heading:(NSString *)heading
                               message:(NSString *)message
                                errors:(NSArray *)errors
                                 extra:(NSDictionary *)extra {
  NSMutableDictionary *context = [NSMutableDictionary dictionary];
  context[@"pageTitle"] = title ?: @"Arlen Search";
  context[@"pageHeading"] = heading ?: @"Search";
  context[@"message"] = message ?: @"";
  context[@"errors"] = [errors isKindOfClass:[NSArray class]] ? errors : @[];
  context[@"searchPrefix"] = self.runtime.prefix ?: @"/search";
  context[@"searchAPIPrefix"] = self.runtime.apiPrefix ?: @"/search/api";
  context[@"authLoginPath"] = [self.authRuntime loginPath] ?: @"/auth/login";
  context[@"authLogoutPath"] = [self.authRuntime logoutPath] ?: @"/auth/logout";
  context[@"csrfToken"] = [self csrfToken] ?: @"";
  context[@"searchSummary"] = [self.runtime dashboardSummary] ?: @{};
  context[@"searchResources"] = [self.runtime registeredResources] ?: @[];
  context[@"searchAdminAllowed"] = @(STRolesAllowAccess([self authRoles], self.runtime.accessRoles) &&
                                     [self.context authAssuranceLevel] >= self.runtime.minimumAuthAssuranceLevel);
  if ([extra isKindOfClass:[NSDictionary class]]) {
    [context addEntriesFromDictionary:extra];
  }
  return context;
}

- (NSString *)searchReturnPathForContext:(ALNContext *)ctx {
  NSString *path = STTrimmedString(ctx.request.path);
  NSString *query = STTrimmedString(ctx.request.queryString);
  if ([query length] > 0) {
    return [NSString stringWithFormat:@"%@?%@", path, query];
  }
  return ([path length] > 0) ? path : (self.runtime.prefix ?: @"/search");
}

- (void)renderAPIErrorWithStatus:(NSInteger)status
                            code:(NSString *)code
                         message:(NSString *)message
                            meta:(NSDictionary *)meta {
  [self setStatus:status];
  NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:meta ?: @{}];
  payload[@"code"] = code ?: @"error";
  payload[@"error"] = message ?: @"request rejected";
  [self renderJSONEnvelopeWithData:nil meta:payload error:NULL];
}

- (BOOL)requireSearchAdminHTML:(ALNContext *)ctx {
  NSString *returnTo = [self searchReturnPathForContext:ctx];
  if ([[ctx authSubject] length] == 0) {
    NSString *location = [NSString stringWithFormat:@"%@?return_to=%@",
                                                    [self.authRuntime loginPath] ?: @"/auth/login",
                                                    STPercentEncodedQueryComponent(returnTo)];
    [self redirectTo:location status:302];
    return NO;
  }
  if (!STRolesAllowAccess([ctx authRoles], self.runtime.accessRoles)) {
    [self setStatus:403];
    [self renderTemplate:@"modules/search/result/index"
                 context:[self pageContextWithTitle:@"Search Access"
                                            heading:@"Access denied"
                                            message:@"You do not have the operator/admin role required for reindex."
                                             errors:nil
                                              extra:nil]
                  layout:@"modules/search/layouts/main"
                   error:NULL];
    return NO;
  }
  if ([ctx authAssuranceLevel] < self.runtime.minimumAuthAssuranceLevel) {
    NSString *location = [NSString stringWithFormat:@"%@?return_to=%@",
                                                    [self.authRuntime totpPath] ?: @"/auth/mfa/totp",
                                                    STPercentEncodedQueryComponent(returnTo)];
    [self redirectTo:location status:302];
    return NO;
  }
  return YES;
}

- (BOOL)requireSearchAdminAPI:(ALNContext *)ctx {
  if ([[ctx authSubject] length] == 0) {
    [self renderAPIErrorWithStatus:401 code:@"unauthorized" message:@"Authentication required" meta:nil];
    return NO;
  }
  if (!STRolesAllowAccess([ctx authRoles], self.runtime.accessRoles)) {
    [self renderAPIErrorWithStatus:403
                              code:@"forbidden"
                           message:@"Missing operator/admin role"
                              meta:@{ @"required_roles_any" : self.runtime.accessRoles ?: @[] }];
    return NO;
  }
  if ([ctx authAssuranceLevel] < self.runtime.minimumAuthAssuranceLevel) {
    [self renderAPIErrorWithStatus:403
                              code:@"step_up_required"
                           message:@"Additional authentication assurance is required"
                              meta:@{
                                @"minimumAuthAssuranceLevel" : @(self.runtime.minimumAuthAssuranceLevel),
                                @"stepUpPath" : [self.authRuntime totpPath] ?: @"/auth/mfa/totp",
                              }];
    return NO;
  }
  return YES;
}

- (NSDictionary *)searchFiltersFromParameters:(NSDictionary *)parameters {
  NSMutableDictionary *filters = [NSMutableDictionary dictionary];
  for (NSString *key in [parameters allKeys]) {
    if (![key hasPrefix:@"filter."]) {
      continue;
    }
    NSString *filterKey = [key substringFromIndex:[@"filter." length]];
    if ([filterKey length] == 0) {
      continue;
    }
    filters[filterKey] = parameters[key];
  }
  return filters;
}

- (NSDictionary *)searchResultFromParameters:(NSDictionary *)parameters
                           resourceIdentifier:(NSString *)resourceIdentifier
                                        error:(NSError **)error {
  NSUInteger limit = [parameters[@"limit"] respondsToSelector:@selector(unsignedIntegerValue)] ? [parameters[@"limit"] unsignedIntegerValue] : 25;
  NSUInteger offset = [parameters[@"offset"] respondsToSelector:@selector(unsignedIntegerValue)] ? [parameters[@"offset"] unsignedIntegerValue] : 0;
  return [self.runtime searchQuery:parameters[@"q"]
                resourceIdentifier:resourceIdentifier
                           filters:[self searchFiltersFromParameters:parameters]
                              sort:parameters[@"sort"]
                             limit:limit
                            offset:offset
                             error:error];
}

- (id)queryHTML:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSDictionary *result = [self searchResultFromParameters:parameters resourceIdentifier:nil error:&error];
  NSArray *errors = (error != nil) ? @[ error.localizedDescription ?: @"search failed" ] : @[];
  [self renderTemplate:@"modules/search/dashboard/index"
               context:[self pageContextWithTitle:@"Search"
                                          heading:@"Search"
                                          message:@""
                                           errors:errors
                                            extra:@{
                                              @"query" : parameters[@"q"] ?: @"",
                                              @"searchResult" : result ?: @{ @"results" : @[], @"total" : @0 },
                                              @"activeResource" : @"",
                                            }]
                layout:@"modules/search/layouts/main"
                 error:NULL];
  return nil;
}

- (id)resourceQueryHTML:(ALNContext *)ctx {
  NSString *resource = STLowerTrimmedString([ctx paramValueForName:@"resource"]);
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSDictionary *result = [self searchResultFromParameters:parameters resourceIdentifier:resource error:&error];
  NSArray *errors = (error != nil) ? @[ error.localizedDescription ?: @"search failed" ] : @[];
  [self renderTemplate:@"modules/search/dashboard/index"
               context:[self pageContextWithTitle:@"Search"
                                          heading:@"Search"
                                          message:@""
                                           errors:errors
                                            extra:@{
                                              @"query" : parameters[@"q"] ?: @"",
                                              @"searchResult" : result ?: @{ @"results" : @[], @"total" : @0 },
                                              @"activeResource" : resource ?: @"",
                                            }]
                layout:@"modules/search/layouts/main"
                 error:NULL];
  return nil;
}

- (id)queueReindexHTML:(ALNContext *)ctx {
  (void)ctx;
  [self.runtime queueReindexForResourceIdentifier:nil error:NULL];
  [self redirectTo:self.runtime.prefix ?: @"/search" status:302];
  return nil;
}

- (id)queueReindexResourceHTML:(ALNContext *)ctx {
  NSString *resource = STLowerTrimmedString([ctx paramValueForName:@"resource"]);
  [self.runtime queueReindexForResourceIdentifier:resource error:NULL];
  [self redirectTo:[NSString stringWithFormat:@"%@/resources/%@", self.runtime.prefix ?: @"/search", resource ?: @""] status:302];
  return nil;
}

- (id)apiResources:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:@{ @"resources" : [self.runtime registeredResources] ?: @[] } meta:nil error:NULL];
  return nil;
}

- (id)apiQuery:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  NSDictionary *result = [self searchResultFromParameters:[self requestParameters] resourceIdentifier:nil error:&error];
  if (result == nil) {
    [self renderAPIErrorWithStatus:(error.code == ALNSearchModuleErrorNotFound) ? 404 : 422
                              code:(error.code == ALNSearchModuleErrorNotFound) ? @"not_found" : @"validation_failed"
                           message:error.localizedDescription ?: @"search failed"
                              meta:nil];
    return nil;
  }
  [self renderJSONEnvelopeWithData:result meta:nil error:NULL];
  return nil;
}

- (id)apiResourceQuery:(ALNContext *)ctx {
  NSString *resource = STLowerTrimmedString([ctx paramValueForName:@"resource"]);
  NSError *error = nil;
  NSDictionary *result = [self searchResultFromParameters:[self requestParameters] resourceIdentifier:resource error:&error];
  if (result == nil) {
    [self renderAPIErrorWithStatus:(error.code == ALNSearchModuleErrorNotFound) ? 404 : 422
                              code:(error.code == ALNSearchModuleErrorNotFound) ? @"not_found" : @"validation_failed"
                           message:error.localizedDescription ?: @"search failed"
                              meta:nil];
    return nil;
  }
  [self renderJSONEnvelopeWithData:result meta:nil error:NULL];
  return nil;
}

- (id)apiQueueReindex:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  NSDictionary *result = [self.runtime queueReindexForResourceIdentifier:nil error:&error];
  if (result == nil) {
    [self renderAPIErrorWithStatus:422 code:@"queue_failed" message:error.localizedDescription ?: @"queue failed" meta:nil];
    return nil;
  }
  [self renderJSONEnvelopeWithData:result meta:nil error:NULL];
  return nil;
}

- (id)apiQueueReindexResource:(ALNContext *)ctx {
  NSString *resource = STLowerTrimmedString([ctx paramValueForName:@"resource"]);
  NSError *error = nil;
  NSDictionary *result = [self.runtime queueReindexForResourceIdentifier:resource error:&error];
  if (result == nil) {
    [self renderAPIErrorWithStatus:(error.code == ALNSearchModuleErrorNotFound) ? 404 : 422
                              code:(error.code == ALNSearchModuleErrorNotFound) ? @"not_found" : @"queue_failed"
                           message:error.localizedDescription ?: @"queue failed"
                              meta:nil];
    return nil;
  }
  [self renderJSONEnvelopeWithData:result meta:nil error:NULL];
  return nil;
}

@end

@implementation ALNSearchModule

- (NSString *)moduleIdentifier {
  return @"search";
}

- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error {
  ALNSearchModuleRuntime *runtime = [ALNSearchModuleRuntime sharedRuntime];
  if (![runtime configureWithApplication:application error:error]) {
    return NO;
  }

  [application beginRouteGroupWithPrefix:runtime.prefix guardAction:nil formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/"
                              name:@"search_query_html"
                   controllerClass:[ALNSearchModuleController class]
                            action:@"queryHTML"];
  [application registerRouteMethod:@"GET"
                              path:@"/resources/:resource"
                              name:@"search_resource_query_html"
                   controllerClass:[ALNSearchModuleController class]
                            action:@"resourceQueryHTML"];
  [application endRouteGroup];

  [application beginRouteGroupWithPrefix:runtime.prefix guardAction:@"requireSearchAdminHTML" formats:nil];
  [application registerRouteMethod:@"POST"
                              path:@"/reindex"
                              name:@"search_reindex_html"
                   controllerClass:[ALNSearchModuleController class]
                            action:@"queueReindexHTML"];
  [application registerRouteMethod:@"POST"
                              path:@"/resources/:resource/reindex"
                              name:@"search_resource_reindex_html"
                   controllerClass:[ALNSearchModuleController class]
                            action:@"queueReindexResourceHTML"];
  [application endRouteGroup];

  [application beginRouteGroupWithPrefix:runtime.apiPrefix guardAction:nil formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/resources"
                              name:@"search_api_resources"
                   controllerClass:[ALNSearchModuleController class]
                            action:@"apiResources"];
  [application registerRouteMethod:@"GET"
                              path:@"/query"
                              name:@"search_api_query"
                   controllerClass:[ALNSearchModuleController class]
                            action:@"apiQuery"];
  [application registerRouteMethod:@"GET"
                              path:@"/resources/:resource/query"
                              name:@"search_api_resource_query"
                   controllerClass:[ALNSearchModuleController class]
                            action:@"apiResourceQuery"];
  [application endRouteGroup];

  [application beginRouteGroupWithPrefix:runtime.apiPrefix guardAction:@"requireSearchAdminAPI" formats:nil];
  [application registerRouteMethod:@"POST"
                              path:@"/reindex"
                              name:@"search_api_reindex"
                   controllerClass:[ALNSearchModuleController class]
                            action:@"apiQueueReindex"];
  [application registerRouteMethod:@"POST"
                              path:@"/resources/:resource/reindex"
                              name:@"search_api_resource_reindex"
                   controllerClass:[ALNSearchModuleController class]
                            action:@"apiQueueReindexResource"];
  [application endRouteGroup];

  for (NSString *routeName in @[
         @"search_api_resources",
         @"search_api_query",
         @"search_api_resource_query",
         @"search_api_reindex",
         @"search_api_resource_reindex",
       ]) {
    [application configureRouteNamed:routeName
                       requestSchema:nil
                      responseSchema:nil
                             summary:@"Search module API"
                         operationID:routeName
                                tags:@[ @"search" ]
                      requiredScopes:nil
                       requiredRoles:nil
                     includeInOpenAPI:YES
                                error:NULL];
  }
  return YES;
}

@end

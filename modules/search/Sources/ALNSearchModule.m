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
static NSUInteger const ALNSearchHistoryLimit = 30;
static NSUInteger const ALNSearchGenerationHistoryLimit = 6;

static NSString *STTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *STLowerTrimmedString(id value) {
  return [[STTrimmedString(value) lowercaseString] copy];
}

static NSDictionary *STNormalizeDictionary(id value) {
  return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

static NSArray *STNormalizeArray(id value) {
  return [value isKindOfClass:[NSArray class]] ? value : @[];
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

static id STPropertyListValue(id value) {
  if (value == nil || value == [NSNull null]) {
    return @"";
  }
  if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ||
      [value isKindOfClass:[NSData class]] || [value isKindOfClass:[NSDate class]]) {
    return value;
  }
  if ([value isKindOfClass:[NSArray class]]) {
    NSMutableArray *items = [NSMutableArray array];
    for (id entry in (NSArray *)value) {
      [items addObject:STPropertyListValue(entry)];
    }
    return items;
  }
  if ([value isKindOfClass:[NSDictionary class]]) {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    for (id rawKey in [(NSDictionary *)value allKeys]) {
      NSString *key = STTrimmedString(rawKey);
      if ([key length] == 0) {
        continue;
      }
      dictionary[key] = STPropertyListValue([(NSDictionary *)value objectForKey:rawKey]);
    }
    return dictionary;
  }
  return [value description] ?: @"";
}

static NSString *STResolvedPersistencePath(ALNApplication *application, NSDictionary *moduleConfig) {
  NSDictionary *persistence = [moduleConfig[@"persistence"] isKindOfClass:[NSDictionary class]]
                                  ? moduleConfig[@"persistence"]
                                  : @{};
  BOOL enabled = ![persistence[@"enabled"] respondsToSelector:@selector(boolValue)] ||
                 [persistence[@"enabled"] boolValue];
  if (!enabled) {
    return @"";
  }
  NSString *configured = STTrimmedString(persistence[@"path"]);
  if ([configured length] > 0) {
    if ([configured hasPrefix:@"/"]) {
      return configured;
    }
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath] ?: NSTemporaryDirectory();
    return [cwd stringByAppendingPathComponent:configured];
  }
  NSString *environment = STLowerTrimmedString(application.environment);
  if ([environment isEqualToString:@"test"]) {
    return @"";
  }
  NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath] ?: NSTemporaryDirectory();
  return [cwd stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"var/module_state/search-%@.plist",
                                              ([environment length] > 0) ? environment : @"development"]];
}

static NSDictionary *STReadPropertyListAtPath(NSString *path, NSError **error) {
  NSString *statePath = STTrimmedString(path);
  if ([statePath length] == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:statePath]) {
    return nil;
  }
  NSData *data = [NSData dataWithContentsOfFile:statePath options:0 error:error];
  if (data == nil) {
    return nil;
  }
  NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
  id object = [NSPropertyListSerialization propertyListWithData:data
                                                        options:NSPropertyListMutableContainersAndLeaves
                                                         format:&format
                                                          error:error];
  return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

static BOOL STWritePropertyListAtPath(NSString *path, NSDictionary *payload, NSError **error) {
  NSString *statePath = STTrimmedString(path);
  if ([statePath length] == 0) {
    return YES;
  }
  NSString *parent = [statePath stringByDeletingLastPathComponent];
  if ([parent length] > 0 &&
      ![[NSFileManager defaultManager] createDirectoryAtPath:parent
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:error]) {
    return NO;
  }
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:STPropertyListValue(payload)
                                                            format:NSPropertyListBinaryFormat_v1_0
                                                           options:0
                                                             error:error];
  if (data == nil) {
    return NO;
  }
  return [data writeToFile:statePath options:NSDataWritingAtomic error:error];
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

static NSString *STResolvedIndexState(id value) {
  NSString *state = STLowerTrimmedString(value);
  NSSet *allowed = [NSSet setWithArray:@[ @"idle", @"queued", @"rebuilding", @"ready", @"degraded", @"failing" ]];
  return [allowed containsObject:state] ? state : @"idle";
}

static NSString *STResolvedModuleStatus(NSArray *resourceRows, NSArray *pendingJobs, NSArray *deadJobs) {
  if ([deadJobs count] > 0) {
    return @"failing";
  }
  BOOL hasDegraded = NO;
  for (NSDictionary *row in resourceRows) {
    NSString *state = STResolvedIndexState(row[@"indexState"]);
    if ([state isEqualToString:@"failing"]) {
      return @"failing";
    }
    if (![state isEqualToString:@"ready"] && ![state isEqualToString:@"idle"]) {
      hasDegraded = YES;
    }
  }
  if (hasDegraded || [pendingJobs count] > 0) {
    return @"degraded";
  }
  return @"healthy";
}

static NSDictionary *STStatusCard(NSString *label, NSString *value, NSString *status, NSString *href) {
  NSMutableDictionary *card = [NSMutableDictionary dictionary];
  card[@"label"] = label ?: @"Metric";
  card[@"value"] = value ?: @"0";
  card[@"status"] = ([STLowerTrimmedString(status) length] > 0) ? STLowerTrimmedString(status) : @"informational";
  if ([STTrimmedString(href) length] > 0) {
    card[@"href"] = STTrimmedString(href);
  }
  return card;
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
@property(nonatomic, strong) NSMutableDictionary *generationHistoryByResource;
@property(nonatomic, strong) NSMutableArray *reindexHistory;
@property(nonatomic, assign) BOOL persistenceEnabled;
@property(nonatomic, copy) NSString *statePath;
@property(nonatomic, assign) NSUInteger nextGeneration;
@property(nonatomic, strong) id<ALNSearchEngine> engine;
@property(nonatomic, copy) NSString *engineIdentifier;
@property(nonatomic, strong) NSLock *lock;

- (BOOL)loadPersistedStateWithError:(NSError **)error;
- (BOOL)persistStateWithError:(NSError **)error;
- (nullable NSDictionary *)normalizedMetadataForDefinition:(id<ALNSearchResourceDefinition>)definition
                                                    source:(NSString *)source
                                                     error:(NSError **)error;
- (nullable NSDictionary *)reindexResourceIdentifier:(NSString *)identifier
                                               error:(NSError **)error;
- (nullable NSDictionary *)applyIncrementalOperation:(NSString *)operation
                                   resourceIdentifier:(NSString *)identifier
                                               record:(nullable NSDictionary *)record
                                                error:(NSError **)error;
- (NSDictionary *)snapshotForResourceIdentifier:(NSString *)identifier metadata:(NSDictionary *)metadata;
- (NSMutableDictionary *)mutableStatusForResourceIdentifier:(NSString *)identifier metadata:(NSDictionary *)metadata;
- (void)recordHistoryEntry:(NSDictionary *)entry;
- (void)appendGenerationEntry:(NSDictionary *)entry forResourceIdentifier:(NSString *)identifier;
- (NSDictionary *)resourceRowForIdentifier:(NSString *)identifier metadata:(NSDictionary *)metadata;

@end

@interface ALNSearchReindexJob : NSObject <ALNJobsJobDefinition>
@end

@interface ALNDefaultSearchEngine : NSObject <ALNSearchEngine>
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

@implementation ALNDefaultSearchEngine

- (NSDictionary *)normalizedDocumentForRecord:(NSDictionary *)record metadata:(NSDictionary *)metadata {
  NSString *identifierField = metadata[@"identifierField"] ?: @"id";
  NSString *primaryField = metadata[@"primaryField"] ?: identifierField;
  NSString *recordID = STTrimmedString(record[identifierField]);
  if ([recordID length] == 0) {
    recordID = STTrimmedString(record[@"recordID"]);
  }
  if ([recordID length] == 0) {
    return nil;
  }

  NSMutableDictionary *fieldText = [NSMutableDictionary dictionary];
  NSMutableArray *parts = [NSMutableArray array];
  for (NSString *field in STNormalizeArray(metadata[@"indexedFields"])) {
    NSString *value = STStringifyValue(record[field]);
    if ([value length] == 0) {
      continue;
    }
    fieldText[field] = value;
    [parts addObject:value];
  }

  NSString *title = STStringifyValue(record[primaryField]);
  if ([title length] == 0) {
    title = recordID;
  }

  NSString *summary = @"";
  for (NSString *field in STNormalizeArray(metadata[@"indexedFields"])) {
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
    @"fieldText" : fieldText,
    @"path" : path ?: @"",
    @"record" : [record isKindOfClass:[NSDictionary class]] ? record : @{},
  };
}

- (NSString *)snippetForText:(NSString *)text query:(NSString *)query {
  NSString *source = STTrimmedString(text);
  NSString *needle = STTrimmedString(query);
  if ([source length] == 0 || [needle length] == 0) {
    return @"";
  }
  NSString *lowerSource = [source lowercaseString];
  NSString *lowerNeedle = [needle lowercaseString];
  NSRange match = [lowerSource rangeOfString:lowerNeedle];
  if (match.location == NSNotFound) {
    return @"";
  }
  NSUInteger prefix = (match.location > 24U) ? (match.location - 24U) : 0U;
  NSUInteger suffix = MIN([source length], match.location + match.length + 36U);
  NSString *snippet = [source substringWithRange:NSMakeRange(prefix, suffix - prefix)];
  if (prefix > 0) {
    snippet = [@"..." stringByAppendingString:snippet];
  }
  if (suffix < [source length]) {
    snippet = [snippet stringByAppendingString:@"..."];
  }
  return snippet;
}

- (NSUInteger)scoreDocument:(NSDictionary *)document metadata:(NSDictionary *)metadata query:(NSString *)query highlight:(NSString **)highlight {
  NSString *needle = STLowerTrimmedString(query);
  if ([needle length] == 0) {
    if (highlight != NULL) {
      *highlight = @"";
    }
    return 0U;
  }
  NSDictionary *fieldText = STNormalizeDictionary(document[@"fieldText"]);
  NSDictionary *weights = STNormalizeDictionary(metadata[@"weightedFields"]);
  NSUInteger score = 0U;
  NSString *resolvedHighlight = @"";
  for (NSString *field in STNormalizeArray(metadata[@"indexedFields"])) {
    NSString *text = STStringifyValue(fieldText[field]);
    NSString *lower = [text lowercaseString];
    if ([lower length] == 0) {
      continue;
    }
    NSUInteger fieldMatches = 0U;
    NSRange searchRange = NSMakeRange(0, [lower length]);
    while (searchRange.location != NSNotFound && searchRange.location < [lower length]) {
      NSRange found = [lower rangeOfString:needle options:0 range:searchRange];
      if (found.location == NSNotFound) {
        break;
      }
      fieldMatches += 1U;
      NSUInteger nextLocation = found.location + found.length;
      if (nextLocation >= [lower length]) {
        break;
      }
      searchRange = NSMakeRange(nextLocation, [lower length] - nextLocation);
    }
    if (fieldMatches == 0U) {
      continue;
    }
    NSUInteger weight = [weights[field] respondsToSelector:@selector(unsignedIntegerValue)]
                            ? MAX((NSUInteger)1U, [weights[field] unsignedIntegerValue])
                            : 1U;
    score += (fieldMatches * weight);
    if ([resolvedHighlight length] == 0 && [metadata[@"supportsHighlights"] boolValue]) {
      resolvedHighlight = [self snippetForText:text query:needle];
    }
  }
  if (highlight != NULL) {
    *highlight = resolvedHighlight ?: @"";
  }
  return score;
}

- (nullable NSDictionary *)searchModuleSnapshotForMetadata:(NSDictionary *)metadata
                                                   records:(NSArray<NSDictionary *> *)records
                                                generation:(NSUInteger)generation
                                                     error:(NSError **)error {
  NSMutableArray *documents = [NSMutableArray array];
  for (NSDictionary *record in STNormalizeArray(records)) {
    if (![record isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *document = [self normalizedDocumentForRecord:record metadata:metadata];
    if (document != nil) {
      [documents addObject:document];
    }
  }
  [documents sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
    NSString *left = STTrimmedString(lhs[@"recordID"]);
    NSString *right = STTrimmedString(rhs[@"recordID"]);
    return [left compare:right];
  }];
  (void)error;
  return @{
    @"generation" : @(MAX((NSUInteger)1U, generation)),
    @"builtAt" : @([[NSDate date] timeIntervalSince1970]),
    @"documentCount" : @([documents count]),
    @"documents" : [NSArray arrayWithArray:documents],
  };
}

- (nullable NSDictionary *)searchModuleApplyOperation:(NSString *)operation
                                               record:(NSDictionary *)record
                                             metadata:(NSDictionary *)metadata
                                      existingSnapshot:(NSDictionary *)snapshot
                                                error:(NSError **)error {
  NSString *normalizedOperation = STLowerTrimmedString(operation);
  if ([normalizedOperation length] == 0) {
    normalizedOperation = @"upsert";
  }
  NSMutableArray *documents = [NSMutableArray arrayWithArray:STNormalizeArray(snapshot[@"documents"])];
  NSString *identifierField = metadata[@"identifierField"] ?: @"id";
  NSString *recordID = STTrimmedString(record[identifierField]);
  if ([recordID length] == 0) {
    recordID = STTrimmedString(record[@"recordID"]);
  }
  if ([recordID length] == 0) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorValidationFailed,
                       @"incremental sync requires a record identifier",
                       @{ @"field" : identifierField ?: @"id" });
    }
    return nil;
  }

  NSInteger existingIndex = NSNotFound;
  for (NSUInteger index = 0; index < [documents count]; index++) {
    NSDictionary *entry = [documents[index] isKindOfClass:[NSDictionary class]] ? documents[index] : @{};
    if ([STTrimmedString(entry[@"recordID"]) isEqualToString:recordID]) {
      existingIndex = (NSInteger)index;
      break;
    }
  }

  if ([normalizedOperation isEqualToString:@"delete"]) {
    if (existingIndex != NSNotFound) {
      [documents removeObjectAtIndex:(NSUInteger)existingIndex];
    }
  } else {
    NSDictionary *document = [self normalizedDocumentForRecord:record metadata:metadata];
    if (document == nil) {
      if (error != NULL) {
        *error = STError(ALNSearchModuleErrorValidationFailed,
                         @"incremental sync record could not be normalized",
                         @{ @"resource" : metadata[@"identifier"] ?: @"" });
      }
      return nil;
    }
    if (existingIndex != NSNotFound) {
      [documents replaceObjectAtIndex:(NSUInteger)existingIndex withObject:document];
    } else {
      [documents addObject:document];
    }
  }

  [documents sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
    return [STTrimmedString(lhs[@"recordID"]) compare:STTrimmedString(rhs[@"recordID"])];
  }];

  NSUInteger generation = [snapshot[@"generation"] respondsToSelector:@selector(unsignedIntegerValue)]
                              ? MAX((NSUInteger)1U, [snapshot[@"generation"] unsignedIntegerValue])
                              : 1U;
  return @{
    @"generation" : @(generation),
    @"builtAt" : @([[NSDate date] timeIntervalSince1970]),
    @"documentCount" : @([documents count]),
    @"documents" : [NSArray arrayWithArray:documents],
  };
}

- (BOOL)document:(NSDictionary *)document
    matchesFilters:(NSDictionary *)filters
          metadata:(NSDictionary *)metadata
             error:(NSError **)error {
  NSDictionary *record = STNormalizeDictionary(document[@"record"]);
  NSArray *allowedFilters = STNormalizeArray(metadata[@"filters"]);
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
    NSArray *operators = STNormalizeArray(filterMetadata[@"operators"]);
    if ([operators count] == 0) {
      operators = @[ @"eq" ];
    }
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
    NSString *lowerActual = [actual lowercaseString];
    NSString *lowerExpected = [expected lowercaseString];
    if ([operatorName isEqualToString:@"contains"]) {
      if ([lowerActual rangeOfString:lowerExpected].location == NSNotFound) {
        return NO;
      }
      continue;
    }
    if ([operatorName isEqualToString:@"gt"] || [operatorName isEqualToString:@"gte"] ||
        [operatorName isEqualToString:@"lt"] || [operatorName isEqualToString:@"lte"]) {
      NSComparisonResult result = [lowerActual compare:lowerExpected options:NSNumericSearch];
      if ([operatorName isEqualToString:@"gt"] && !(result == NSOrderedDescending)) {
        return NO;
      }
      if ([operatorName isEqualToString:@"gte"] && !(result == NSOrderedDescending || result == NSOrderedSame)) {
        return NO;
      }
      if ([operatorName isEqualToString:@"lt"] && !(result == NSOrderedAscending)) {
        return NO;
      }
      if ([operatorName isEqualToString:@"lte"] && !(result == NSOrderedAscending || result == NSOrderedSame)) {
        return NO;
      }
      continue;
    }
    if ([operatorName isEqualToString:@"in"]) {
      NSArray *expectedParts = STNormalizedStringArray([expected componentsSeparatedByString:@","]);
      if (![expectedParts containsObject:lowerActual]) {
        return NO;
      }
      continue;
    }
    if (![lowerActual isEqualToString:lowerExpected]) {
      return NO;
    }
  }
  return YES;
}

- (nullable NSDictionary *)searchModuleExecuteQuery:(NSString *)query
                                     resourceMetadata:(NSArray<NSDictionary *> *)resourceMetadata
                                  snapshotsByResource:(NSDictionary<NSString *, NSDictionary *> *)snapshotsByResource
                                              filters:(NSDictionary *)filters
                                                 sort:(NSString *)sort
                                                limit:(NSUInteger)limit
                                               offset:(NSUInteger)offset
                                                error:(NSError **)error {
  NSString *normalizedQuery = STTrimmedString(query);
  NSString *normalizedSort = STLowerTrimmedString(sort);
  NSMutableArray *matches = [NSMutableArray array];

  for (NSDictionary *metadata in STNormalizeArray(resourceMetadata)) {
    NSString *identifier = STLowerTrimmedString(metadata[@"identifier"]);
    NSDictionary *snapshot = STNormalizeDictionary(snapshotsByResource[identifier]);
    NSArray *documents = STNormalizeArray(snapshot[@"documents"]);

    NSMutableDictionary *allowedSorts = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in STNormalizeArray(metadata[@"sorts"])) {
      NSString *name = STLowerTrimmedString(entry[@"name"]);
      if ([name length] > 0) {
        allowedSorts[name] = entry;
      }
    }

    NSString *effectiveSort = normalizedSort;
    if ([effectiveSort length] == 0) {
      effectiveSort = ([normalizedQuery length] > 0) ? @"relevance" : STLowerTrimmedString(metadata[@"defaultSort"]);
      if ([effectiveSort length] == 0) {
        effectiveSort = @"relevance";
      }
    }
    NSString *sortField = [effectiveSort hasPrefix:@"-"] ? [effectiveSort substringFromIndex:1] : effectiveSort;
    if (![sortField isEqualToString:@"relevance"] && allowedSorts[sortField] == nil) {
      if (error != NULL) {
        *error = STError(ALNSearchModuleErrorValidationFailed,
                         [NSString stringWithFormat:@"unsupported sort %@", sortField],
                         @{ @"field" : sortField ?: @"" });
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

      NSString *highlight = @"";
      NSUInteger score = [self scoreDocument:document metadata:metadata query:normalizedQuery highlight:&highlight];
      if ([normalizedQuery length] > 0 && score == 0U) {
        continue;
      }

      NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:document];
      result[@"resourceLabel"] = metadata[@"label"] ?: STTitleCaseIdentifier(identifier);
      result[@"score"] = @(score);
      result[@"generation"] = snapshot[@"generation"] ?: @0;
      if ([highlight length] > 0) {
        result[@"highlights"] = @[ highlight ];
      } else {
        result[@"highlights"] = @[];
      }
      [matches addObject:result];
    }
  }

  NSString *effectiveSort = normalizedSort;
  if ([effectiveSort length] == 0) {
    effectiveSort = ([normalizedQuery length] > 0) ? @"relevance" : @"relevance";
  }
  BOOL descending = [effectiveSort hasPrefix:@"-"];
  NSString *sortField = descending ? [effectiveSort substringFromIndex:1] : effectiveSort;
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
      NSComparisonResult result = [[leftValue lowercaseString] compare:[rightValue lowercaseString] options:NSNumericSearch];
      if (result != NSOrderedSame) {
        return descending ? -result : result;
      }
    }
    NSString *leftTitle = STStringifyValue(lhs[@"title"]);
    NSString *rightTitle = STStringifyValue(rhs[@"title"]);
    return [[leftTitle lowercaseString] compare:[rightTitle lowercaseString]];
  }];

  NSUInteger start = MIN(offset, [matches count]);
  NSUInteger sliceLength = MIN((limit > 0 ? limit : 25U), ([matches count] - start));
  NSArray *page = [matches subarrayWithRange:NSMakeRange(start, sliceLength)];
  return @{
    @"query" : normalizedQuery ?: @"",
    @"results" : page ?: @[],
    @"total" : @([matches count]),
    @"limit" : @(limit > 0 ? limit : 25U),
    @"offset" : @(offset),
  };
}

- (NSDictionary *)searchModuleCapabilities {
  return @{
    @"engine" : @"default",
    @"supportsHighlights" : @YES,
    @"supportsIncrementalSync" : @YES,
    @"supportsGenerations" : @YES,
  };
}

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
  NSArray *fields = STNormalizeArray(self.metadata[@"fields"]);
  NSMutableArray *indexedFields = [NSMutableArray array];
  NSMutableDictionary *weights = [NSMutableDictionary dictionary];
  for (NSDictionary *field in STSortedArrayFromValues(fields, @"name")) {
    NSString *name = STLowerTrimmedString(field[@"name"]);
    if ([name length] == 0) {
      continue;
    }
    [indexedFields addObject:name];
    NSUInteger weight = [field[@"searchWeight"] respondsToSelector:@selector(unsignedIntegerValue)]
                            ? MAX((NSUInteger)1U, [field[@"searchWeight"] unsignedIntegerValue])
                            : ([name isEqualToString:STLowerTrimmedString(self.metadata[@"primaryField"])] ? 4U : 1U);
    weights[name] = @(weight);
  }
  NSDictionary *paths = STNormalizeDictionary(self.metadata[@"paths"]);
  return @{
    @"label" : self.metadata[@"label"] ?: STTitleCaseIdentifier(identifier),
    @"summary" : self.metadata[@"summary"] ?: @"",
    @"identifierField" : self.metadata[@"identifierField"] ?: @"id",
    @"primaryField" : self.metadata[@"primaryField"] ?: self.metadata[@"identifierField"] ?: @"id",
    @"indexedFields" : indexedFields,
    @"filters" : ([STNormalizeArray(self.metadata[@"filters"]) count] > 0) ? STNormalizeArray(self.metadata[@"filters"]) : @[],
    @"sorts" : ([STNormalizeArray(self.metadata[@"sorts"]) count] > 0) ? STNormalizeArray(self.metadata[@"sorts"]) : @[],
    @"defaultSort" : STLowerTrimmedString(self.metadata[@"defaultSort"]),
    @"pagination" : STNormalizeDictionary(self.metadata[@"pagination"]),
    @"weightedFields" : weights,
    @"supportsHighlights" : @YES,
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
    _generationHistoryByResource = [NSMutableDictionary dictionary];
    _reindexHistory = [NSMutableArray array];
    _persistenceEnabled = NO;
    _statePath = @"";
    _nextGeneration = 1U;
    _engine = [[ALNDefaultSearchEngine alloc] init];
    _engineIdentifier = @"ALNDefaultSearchEngine";
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
  NSDictionary *engineConfig = [moduleConfig[@"engine"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"engine"] : @{};
  NSString *engineClassName = STTrimmedString(moduleConfig[@"engineClass"]);
  if ([engineClassName length] == 0) {
    engineClassName = STTrimmedString(engineConfig[@"class"]);
  }
  if ([engineClassName length] == 0) {
    engineClassName = @"ALNDefaultSearchEngine";
  }
  Class engineClass = NSClassFromString(engineClassName);
  id engine = (engineClass != Nil) ? [[engineClass alloc] init] : nil;
  if (engine == nil || ![engine conformsToProtocol:@protocol(ALNSearchEngine)]) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorInvalidConfiguration,
                       [NSString stringWithFormat:@"search engine %@ is invalid", engineClassName],
                       @{ @"class" : engineClassName ?: @"" });
    }
    return NO;
  }

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
  self.statePath = STResolvedPersistencePath(application, moduleConfig);
  self.persistenceEnabled = ([self.statePath length] > 0);
  self.nextGeneration = 1U;
  self.engine = engine;
  self.engineIdentifier = engineClassName;

  [self.lock lock];
  [self.resourceDefinitionsByIdentifier removeAllObjects];
  [self.resourceMetadataByIdentifier removeAllObjects];
  [self.indexedDocumentsByResource removeAllObjects];
  [self.statusByResource removeAllObjects];
  [self.generationHistoryByResource removeAllObjects];
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

  if (![self loadPersistedStateWithError:error]) {
    return NO;
  }
  return [self persistStateWithError:error];
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
    @"activeGeneration" : @0,
    @"buildingGeneration" : @0,
    @"generationCount" : @0,
    @"lastIndexedAt" : @"",
    @"lastJobID" : @"",
    @"lastError" : @"",
    @"lastFailureAt" : @0,
    @"lastSyncAt" : @0,
    @"lastSyncOperation" : @"",
    @"lastMode" : @"",
    @"indexState" : @"idle",
    @"engine" : self.engineIdentifier ?: @"ALNDefaultSearchEngine",
    @"source" : normalized[@"source"] ?: @"provider",
  };
  self.generationHistoryByResource[identifier] = [NSMutableArray array];
  [self.lock unlock];
  return YES;
}

- (BOOL)loadPersistedStateWithError:(NSError **)error {
  if (!self.persistenceEnabled || [self.statePath length] == 0) {
    return YES;
  }
  NSError *readError = nil;
  NSDictionary *state = STReadPropertyListAtPath(self.statePath, &readError);
  if (state == nil) {
    if (readError != nil && error != NULL) {
      *error = readError;
      return NO;
    }
    return YES;
  }
  [self.lock lock];
  self.nextGeneration = [state[@"nextGeneration"] respondsToSelector:@selector(unsignedIntegerValue)]
                            ? MAX((NSUInteger)1U, [state[@"nextGeneration"] unsignedIntegerValue])
                            : self.nextGeneration;
  NSDictionary *persistedDocuments = STNormalizeDictionary(state[@"indexedDocumentsByResource"]);
  NSDictionary *persistedStatus = STNormalizeDictionary(state[@"statusByResource"]);
  NSDictionary *persistedGenerations = STNormalizeDictionary(state[@"generationHistoryByResource"]);
  for (NSString *identifier in self.resourceMetadataByIdentifier) {
    if ([persistedDocuments[identifier] isKindOfClass:[NSArray class]]) {
      self.indexedDocumentsByResource[identifier] = [persistedDocuments[identifier] copy];
    }
    if ([persistedStatus[identifier] isKindOfClass:[NSDictionary class]]) {
      NSMutableDictionary *status = [NSMutableDictionary dictionaryWithDictionary:self.statusByResource[identifier] ?: @{}];
      [status addEntriesFromDictionary:persistedStatus[identifier]];
      status[@"engine"] = self.engineIdentifier ?: @"ALNDefaultSearchEngine";
      status[@"indexState"] = STResolvedIndexState(status[@"indexState"]);
      self.statusByResource[identifier] = status;
    }
    if ([persistedGenerations[identifier] isKindOfClass:[NSArray class]]) {
      self.generationHistoryByResource[identifier] = [NSMutableArray arrayWithArray:persistedGenerations[identifier]];
    }
  }
  NSArray *history = STNormalizeArray(state[@"reindexHistory"]);
  [self.reindexHistory addObjectsFromArray:history];
  while ([self.reindexHistory count] > ALNSearchHistoryLimit) {
    [self.reindexHistory removeObjectAtIndex:0];
  }
  [self.lock unlock];
  return YES;
}

- (BOOL)persistStateWithError:(NSError **)error {
  if (!self.persistenceEnabled || [self.statePath length] == 0) {
    return YES;
  }
  NSDictionary *payload = nil;
  [self.lock lock];
  NSMutableDictionary *generationHistory = [NSMutableDictionary dictionary];
  for (NSString *identifier in self.generationHistoryByResource) {
    generationHistory[identifier] =
        [[NSArray alloc] initWithArray:(self.generationHistoryByResource[identifier] ?: @[]) copyItems:YES] ?: @[];
  }
  payload = @{
    @"version" : @1,
    @"nextGeneration" : @(MAX((NSUInteger)1U, self.nextGeneration)),
    @"indexedDocumentsByResource" : [NSDictionary dictionaryWithDictionary:self.indexedDocumentsByResource ?: @{}],
    @"statusByResource" : [NSDictionary dictionaryWithDictionary:self.statusByResource ?: @{}],
    @"generationHistoryByResource" : generationHistory,
    @"reindexHistory" : [[NSArray alloc] initWithArray:self.reindexHistory copyItems:YES] ?: @[],
  };
  [self.lock unlock];
  return STWritePropertyListAtPath(self.statePath, payload, error);
}

- (NSDictionary *)normalizedMetadataForDefinition:(id<ALNSearchResourceDefinition>)definition
                                           source:(NSString *)source
                                            error:(NSError **)error {
  NSString *identifier = STLowerTrimmedString([definition searchModuleResourceIdentifier]);
  NSDictionary *rawMetadata = STNormalizeDictionary([definition searchModuleResourceMetadata]);
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
  NSMutableDictionary *weightedFields = [NSMutableDictionary dictionary];
  NSDictionary *rawWeights = STNormalizeDictionary(rawMetadata[@"weightedFields"]);
  for (NSString *field in indexedFields) {
    NSUInteger weight = [rawWeights[field] respondsToSelector:@selector(unsignedIntegerValue)]
                            ? MAX((NSUInteger)1U, [rawWeights[field] unsignedIntegerValue])
                            : ([field isEqualToString:primaryField] ? 4U : 1U);
    weightedFields[field] = @(weight);
  }
  NSMutableArray *filters = [NSMutableArray array];
  for (NSDictionary *entry in STSortedArrayFromValues(rawMetadata[@"filters"], @"name")) {
    NSString *name = STLowerTrimmedString(entry[@"name"]);
    if ([name length] == 0) {
      continue;
    }
    NSArray *operators = STNormalizedStringArray(entry[@"operators"]);
    NSString *filterType = STLowerTrimmedString(entry[@"type"]);
    if ([filterType length] == 0) {
      filterType = @"string";
    }
    [filters addObject:@{
      @"name" : name,
      @"label" : entry[@"label"] ?: STTitleCaseIdentifier(name),
      @"type" : filterType,
      @"operators" : ([operators count] > 0) ? operators : @[ @"eq" ],
    }];
  }
  NSMutableArray *sorts = [NSMutableArray array];
  NSString *defaultSort = STLowerTrimmedString(rawMetadata[@"defaultSort"]);
  for (NSDictionary *entry in STSortedArrayFromValues(rawMetadata[@"sorts"], @"name")) {
    NSString *name = STLowerTrimmedString(entry[@"name"]);
    if ([name length] == 0) {
      continue;
    }
    BOOL sortDefault = [entry[@"default"] respondsToSelector:@selector(boolValue)] ? [entry[@"default"] boolValue] : NO;
    NSString *direction = STLowerTrimmedString(entry[@"direction"]);
    if (![direction isEqualToString:@"desc"]) {
      direction = @"asc";
    }
    BOOL allowDescending =
        ![entry[@"allowDescending"] respondsToSelector:@selector(boolValue)] || [entry[@"allowDescending"] boolValue];
    if ([defaultSort length] == 0 && sortDefault) {
      defaultSort = [direction isEqualToString:@"desc"] ? [@"-" stringByAppendingString:name] : name;
    }
    [sorts addObject:@{
      @"name" : name,
      @"label" : entry[@"label"] ?: STTitleCaseIdentifier(name),
      @"default" : @(sortDefault),
      @"direction" : direction,
      @"allowDescending" : @(allowDescending),
    }];
  }
  if ([sorts count] == 0) {
    [sorts addObject:@{
      @"name" : primaryField,
      @"label" : STTitleCaseIdentifier(primaryField),
      @"default" : @YES,
      @"direction" : @"asc",
      @"allowDescending" : @YES,
    }];
    if ([defaultSort length] == 0) {
      defaultSort = primaryField;
    }
  }
  NSDictionary *rawPagination = STNormalizeDictionary(rawMetadata[@"pagination"]);
  NSUInteger defaultLimit = [rawPagination[@"defaultLimit"] respondsToSelector:@selector(unsignedIntegerValue)]
                                ? [rawPagination[@"defaultLimit"] unsignedIntegerValue]
                                : ([rawMetadata[@"pageSize"] respondsToSelector:@selector(unsignedIntegerValue)]
                                       ? [rawMetadata[@"pageSize"] unsignedIntegerValue]
                                       : 25U);
  if (defaultLimit == 0U) {
    defaultLimit = 25U;
  }
  NSUInteger maxLimit = [rawPagination[@"maxLimit"] respondsToSelector:@selector(unsignedIntegerValue)]
                            ? [rawPagination[@"maxLimit"] unsignedIntegerValue]
                            : MAX(defaultLimit, 100U);
  if (maxLimit < defaultLimit) {
    maxLimit = defaultLimit;
  }
  return @{
    @"identifier" : identifier,
    @"label" : label,
    @"summary" : summary ?: @"",
    @"identifierField" : identifierField,
    @"primaryField" : primaryField,
    @"indexedFields" : indexedFields,
    @"weightedFields" : weightedFields,
    @"filters" : filters,
    @"sorts" : sorts,
    @"defaultSort" : defaultSort ?: @"",
    @"pagination" : @{
      @"defaultLimit" : @(defaultLimit),
      @"maxLimit" : @(maxLimit),
    },
    @"supportsHighlights" : @([rawMetadata[@"supportsHighlights"] respondsToSelector:@selector(boolValue)]
                                  ? [rawMetadata[@"supportsHighlights"] boolValue]
                                  : YES),
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
    @"persistenceEnabled" : @(self.persistenceEnabled),
    @"statePath" : self.statePath ?: @"",
    @"nextGeneration" : @(self.nextGeneration),
    @"engine" : self.engineIdentifier ?: @"ALNDefaultSearchEngine",
    @"engineCapabilities" : [self.engine searchModuleCapabilities] ?: @{},
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
                                                                       payload:@{
                                                                         @"resource" : resourceIdentifier,
                                                                         @"mode" : @"full",
                                                                       }
                                                                       options:nil
                                                                         error:error];
  if ([jobID length] == 0) {
    return nil;
  }

  NSArray *targets = [resourceIdentifier isEqualToString:@"*"] ? [[self registeredResources] valueForKey:@"identifier"] : @[ resourceIdentifier ];
  NSTimeInterval queuedAt = [[NSDate date] timeIntervalSince1970];
  [self.lock lock];
  for (NSString *target in targets) {
    NSDictionary *existing = [self.statusByResource[target] isKindOfClass:[NSDictionary class]] ? self.statusByResource[target] : @{};
    NSMutableDictionary *status = [NSMutableDictionary dictionaryWithDictionary:existing];
    status[@"lastJobID"] = jobID;
    status[@"queuedAt"] = @(queuedAt);
    status[@"lastMode"] = @"full";
    status[@"indexState"] = @"queued";
    self.statusByResource[target] = status;
  }
  [self.lock unlock];
  (void)[self persistStateWithError:NULL];

  return @{
    @"jobID" : jobID,
    @"resource" : resourceIdentifier,
    @"mode" : @"full",
  };
}

- (NSDictionary *)queueIncrementalSyncForResourceIdentifier:(NSString *)identifier
                                                     record:(NSDictionary *)record
                                                  operation:(NSString *)operation
                                                      error:(NSError **)error {
  NSString *resourceIdentifier = STLowerTrimmedString(identifier);
  if ([resourceIdentifier length] == 0 || [self resourceMetadataForIdentifier:resourceIdentifier] == nil) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorNotFound,
                       @"incremental sync requires a known resource",
                       @{ @"resource" : resourceIdentifier ?: @"" });
    }
    return nil;
  }
  NSString *normalizedOperation = STLowerTrimmedString(operation);
  if ([normalizedOperation length] == 0) {
    normalizedOperation = @"upsert";
  }
  NSString *jobID = [[ALNJobsModuleRuntime sharedRuntime] enqueueJobIdentifier:ALNSearchReindexJobIdentifier
                                                                       payload:@{
                                                                         @"resource" : resourceIdentifier,
                                                                         @"mode" : @"incremental",
                                                                         @"operation" : normalizedOperation,
                                                                         @"record" : STNormalizeDictionary(record),
                                                                       }
                                                                       options:nil
                                                                         error:error];
  if ([jobID length] == 0) {
    return nil;
  }
  NSTimeInterval queuedAt = [[NSDate date] timeIntervalSince1970];
  NSDictionary *metadata = [self resourceMetadataForIdentifier:resourceIdentifier];
  [self.lock lock];
  NSMutableDictionary *status = [self mutableStatusForResourceIdentifier:resourceIdentifier
                                                                metadata:metadata];
  status[@"lastJobID"] = jobID;
  status[@"queuedAt"] = @(queuedAt);
  status[@"lastMode"] = @"incremental";
  status[@"indexState"] = @"queued";
  self.statusByResource[resourceIdentifier] = status;
  [self.lock unlock];
  (void)[self persistStateWithError:NULL];
  return @{
    @"jobID" : jobID,
    @"resource" : resourceIdentifier,
    @"mode" : @"incremental",
    @"operation" : normalizedOperation,
  };
}

- (NSDictionary *)snapshotForResourceIdentifier:(NSString *)identifier metadata:(NSDictionary *)metadata {
  [self.lock lock];
  NSArray *documents = [self.indexedDocumentsByResource[identifier] isKindOfClass:[NSArray class]] ? self.indexedDocumentsByResource[identifier] : @[];
  NSDictionary *status = [self.statusByResource[identifier] isKindOfClass:[NSDictionary class]] ? self.statusByResource[identifier] : @{};
  [self.lock unlock];
  return @{
    @"generation" : [status[@"activeGeneration"] respondsToSelector:@selector(unsignedIntegerValue)]
                        ? @([status[@"activeGeneration"] unsignedIntegerValue])
                        : @0,
    @"documents" : documents ?: @[],
    @"metadata" : metadata ?: @{},
  };
}

- (NSMutableDictionary *)mutableStatusForResourceIdentifier:(NSString *)identifier metadata:(NSDictionary *)metadata {
  NSDictionary *existing = [self.statusByResource[identifier] isKindOfClass:[NSDictionary class]] ? self.statusByResource[identifier] : @{};
  NSMutableDictionary *status = [NSMutableDictionary dictionaryWithDictionary:existing];
  status[@"identifier"] = identifier ?: @"";
  status[@"label"] = metadata[@"label"] ?: existing[@"label"] ?: STTitleCaseIdentifier(identifier);
  status[@"source"] = metadata[@"source"] ?: existing[@"source"] ?: @"provider";
  status[@"engine"] = self.engineIdentifier ?: existing[@"engine"] ?: @"ALNDefaultSearchEngine";
  status[@"indexState"] = STResolvedIndexState(existing[@"indexState"]);
  return status;
}

- (void)recordHistoryEntry:(NSDictionary *)entry {
  [self.reindexHistory addObject:entry ?: @{}];
  while ([self.reindexHistory count] > ALNSearchHistoryLimit) {
    [self.reindexHistory removeObjectAtIndex:0];
  }
}

- (void)appendGenerationEntry:(NSDictionary *)entry forResourceIdentifier:(NSString *)identifier {
  NSMutableArray *history = [self.generationHistoryByResource[identifier] isKindOfClass:[NSMutableArray class]]
                                ? self.generationHistoryByResource[identifier]
                                : [NSMutableArray array];
  [history addObject:entry ?: @{}];
  while ([history count] > ALNSearchGenerationHistoryLimit) {
    [history removeObjectAtIndex:0];
  }
  self.generationHistoryByResource[identifier] = history;
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
  NSUInteger generation = MAX((NSUInteger)1U, self.nextGeneration);
  self.nextGeneration = generation + 1U;
  NSMutableDictionary *status = [self mutableStatusForResourceIdentifier:resourceIdentifier metadata:metadata];
  status[@"buildingGeneration"] = @(generation);
  status[@"indexState"] = @"rebuilding";
  status[@"lastMode"] = @"full";
  self.statusByResource[resourceIdentifier] = status;
  [self.lock unlock];
  (void)[self persistStateWithError:NULL];

  NSError *loadError = nil;
  NSArray *records = [definition searchModuleDocumentsForRuntime:self error:&loadError];
  if (records == nil) {
    if (error != NULL) {
      *error = loadError ?: STError(ALNSearchModuleErrorExecutionFailed,
                                    @"search resource failed to build documents",
                                    @{ @"resource" : resourceIdentifier });
    }
    return nil;
  }

  NSDictionary *snapshot = [self.engine searchModuleSnapshotForMetadata:metadata
                                                                records:records
                                                             generation:generation
                                                                  error:error];
  if (snapshot == nil) {
    return nil;
  }

  NSTimeInterval indexedAt = [[NSDate date] timeIntervalSince1970];
  [self.lock lock];
  self.indexedDocumentsByResource[resourceIdentifier] = STNormalizeArray(snapshot[@"documents"]);
  status = [self mutableStatusForResourceIdentifier:resourceIdentifier metadata:metadata];
  status[@"documentCount"] = snapshot[@"documentCount"] ?: @0;
  status[@"activeGeneration"] = snapshot[@"generation"] ?: @(generation);
  status[@"buildingGeneration"] = @0;
  status[@"generationCount"] = @([STNormalizeArray(self.generationHistoryByResource[resourceIdentifier]) count] + 1U);
  status[@"lastIndexedAt"] = @(indexedAt);
  status[@"lastError"] = @"";
  status[@"lastFailureAt"] = @0;
  status[@"lastSyncAt"] = @(indexedAt);
  status[@"lastSyncOperation"] = @"full";
  status[@"indexState"] = @"ready";
  self.statusByResource[resourceIdentifier] = status;
  [self appendGenerationEntry:@{
    @"generation" : snapshot[@"generation"] ?: @(generation),
    @"activatedAt" : @(indexedAt),
    @"documentCount" : snapshot[@"documentCount"] ?: @0,
    @"mode" : @"full",
    @"status" : @"activated",
  }
               forResourceIdentifier:resourceIdentifier];
  [self recordHistoryEntry:@{
    @"resource" : resourceIdentifier,
    @"documentCount" : snapshot[@"documentCount"] ?: @0,
    @"indexedAt" : @(indexedAt),
    @"jobID" : status[@"lastJobID"] ?: @"",
    @"mode" : @"full",
    @"status" : @"succeeded",
    @"generation" : snapshot[@"generation"] ?: @(generation),
  }];
  [self.lock unlock];
  if (![self persistStateWithError:error]) {
    return nil;
  }

  return @{
    @"identifier" : resourceIdentifier,
    @"documentCount" : snapshot[@"documentCount"] ?: @0,
    @"generation" : snapshot[@"generation"] ?: @(generation),
    @"mode" : @"full",
  };
}

- (NSDictionary *)applyIncrementalOperation:(NSString *)operation
                          resourceIdentifier:(NSString *)identifier
                                      record:(NSDictionary *)record
                                       error:(NSError **)error {
  NSString *resourceIdentifier = STLowerTrimmedString(identifier);
  NSDictionary *metadata = [self resourceMetadataForIdentifier:resourceIdentifier];
  if (metadata == nil) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorNotFound,
                       @"unknown search resource",
                       @{ @"resource" : resourceIdentifier ?: @"" });
    }
    return nil;
  }
  NSString *normalizedOperation = STLowerTrimmedString(operation);
  if ([normalizedOperation length] == 0) {
    normalizedOperation = @"upsert";
  }
  NSDictionary *snapshot = [self snapshotForResourceIdentifier:resourceIdentifier metadata:metadata];
  [self.lock lock];
  NSUInteger generation = [snapshot[@"generation"] respondsToSelector:@selector(unsignedIntegerValue)]
                              ? [snapshot[@"generation"] unsignedIntegerValue]
                              : 0U;
  if (generation == 0U) {
    generation = MAX((NSUInteger)1U, self.nextGeneration);
    self.nextGeneration = generation + 1U;
    snapshot = @{
      @"generation" : @(generation),
      @"documents" : snapshot[@"documents"] ?: @[],
      @"metadata" : metadata ?: @{},
    };
  } else if (self.nextGeneration <= generation) {
    self.nextGeneration = generation + 1U;
  }
  [self.lock unlock];
  NSDictionary *updated = [self.engine searchModuleApplyOperation:normalizedOperation
                                                           record:record ?: @{}
                                                         metadata:metadata
                                                  existingSnapshot:snapshot
                                                            error:error];
  if (updated == nil) {
    return nil;
  }
  NSTimeInterval syncedAt = [[NSDate date] timeIntervalSince1970];
  [self.lock lock];
  self.indexedDocumentsByResource[resourceIdentifier] = STNormalizeArray(updated[@"documents"]);
  NSMutableDictionary *status = [self mutableStatusForResourceIdentifier:resourceIdentifier metadata:metadata];
  status[@"documentCount"] = updated[@"documentCount"] ?: @0;
  status[@"activeGeneration"] = updated[@"generation"] ?: snapshot[@"generation"] ?: @1;
  status[@"buildingGeneration"] = @0;
  status[@"lastError"] = @"";
  status[@"lastFailureAt"] = @0;
  status[@"lastSyncAt"] = @(syncedAt);
  status[@"lastSyncOperation"] = normalizedOperation;
  status[@"lastMode"] = @"incremental";
  status[@"indexState"] = @"ready";
  NSArray *history = STNormalizeArray(self.generationHistoryByResource[resourceIdentifier]);
  if ([history count] == 0U) {
    [self appendGenerationEntry:@{
      @"generation" : updated[@"generation"] ?: snapshot[@"generation"] ?: @1,
      @"activatedAt" : @(syncedAt),
      @"documentCount" : updated[@"documentCount"] ?: @0,
      @"mode" : @"incremental",
      @"status" : @"seeded",
    }
                 forResourceIdentifier:resourceIdentifier];
  }
  status[@"generationCount"] = @([STNormalizeArray(self.generationHistoryByResource[resourceIdentifier]) count]);
  self.statusByResource[resourceIdentifier] = status;
  [self recordHistoryEntry:@{
    @"resource" : resourceIdentifier,
    @"documentCount" : updated[@"documentCount"] ?: @0,
    @"indexedAt" : @(syncedAt),
    @"jobID" : status[@"lastJobID"] ?: @"",
    @"mode" : @"incremental",
    @"operation" : normalizedOperation,
    @"status" : @"succeeded",
    @"generation" : updated[@"generation"] ?: snapshot[@"generation"] ?: @1,
  }];
  [self.lock unlock];
  if (![self persistStateWithError:error]) {
    return nil;
  }
  return @{
    @"identifier" : resourceIdentifier,
    @"documentCount" : updated[@"documentCount"] ?: @0,
    @"generation" : updated[@"generation"] ?: snapshot[@"generation"] ?: @1,
    @"mode" : @"incremental",
    @"operation" : normalizedOperation,
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
  NSString *mode = STLowerTrimmedString(payload[@"mode"]);
  if ([mode length] == 0) {
    mode = @"full";
  }

  NSArray *targets = [resource isEqualToString:@"*"] ? [[self registeredResources] valueForKey:@"identifier"] : @[ resource ];
  NSMutableArray *results = [NSMutableArray array];
  NSUInteger totalDocuments = 0;
  for (NSString *target in targets) {
    NSDictionary *summary = nil;
    if ([mode isEqualToString:@"incremental"]) {
      summary = [self applyIncrementalOperation:payload[@"operation"]
                              resourceIdentifier:target
                                          record:STNormalizeDictionary(payload[@"record"])
                                           error:error];
    } else {
      summary = [self reindexResourceIdentifier:target error:error];
    }
    if (summary == nil) {
      NSDictionary *metadata = [self resourceMetadataForIdentifier:target] ?: @{};
      [self.lock lock];
      NSMutableDictionary *status = [self mutableStatusForResourceIdentifier:target metadata:metadata];
      status[@"buildingGeneration"] = @0;
      status[@"lastError"] = (error != NULL && *error != nil) ? ([*error localizedDescription] ?: @"reindex failed") : @"reindex failed";
      status[@"lastFailureAt"] = @([[NSDate date] timeIntervalSince1970]);
      status[@"indexState"] = ([status[@"activeGeneration"] unsignedIntegerValue] > 0U) ? @"degraded" : @"failing";
      status[@"lastMode"] = mode;
      self.statusByResource[target] = status;
      [self recordHistoryEntry:@{
        @"resource" : target ?: @"",
        @"documentCount" : status[@"documentCount"] ?: @0,
        @"indexedAt" : @([[NSDate date] timeIntervalSince1970]),
        @"jobID" : status[@"lastJobID"] ?: @"",
        @"mode" : mode ?: @"full",
        @"operation" : STLowerTrimmedString(payload[@"operation"]),
        @"status" : @"failed",
        @"error" : status[@"lastError"] ?: @"reindex failed",
      }];
      [self.lock unlock];
      (void)[self persistStateWithError:NULL];
      return nil;
    }
    totalDocuments += [summary[@"documentCount"] unsignedIntegerValue];
    [results addObject:summary];
  }
  return @{
    @"resources" : results,
    @"resourceCount" : @([results count]),
    @"documentCount" : @(totalDocuments),
    @"mode" : mode ?: @"full",
  };
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
  NSDictionary *pagination = ([resourceMetadata count] == 1) ? STNormalizeDictionary(resourceMetadata[0][@"pagination"]) : @{};
  NSUInteger resolvedLimit = [pagination[@"defaultLimit"] respondsToSelector:@selector(unsignedIntegerValue)]
                                 ? [pagination[@"defaultLimit"] unsignedIntegerValue]
                                 : 25U;
  if (limit > 0U) {
    resolvedLimit = limit;
  }
  NSUInteger maxLimit = [pagination[@"maxLimit"] respondsToSelector:@selector(unsignedIntegerValue)]
                            ? [pagination[@"maxLimit"] unsignedIntegerValue]
                            : 100U;
  if (maxLimit == 0U) {
    maxLimit = 100U;
  }
  if (resolvedLimit == 0U) {
    resolvedLimit = 25U;
  }
  resolvedLimit = MIN(resolvedLimit, maxLimit);

  NSMutableDictionary *snapshotsByResource = [NSMutableDictionary dictionary];
  for (NSDictionary *metadata in resourceMetadata) {
    NSString *identifier = STLowerTrimmedString(metadata[@"identifier"]);
    snapshotsByResource[identifier] = [self snapshotForResourceIdentifier:identifier metadata:metadata];
  }
  NSDictionary *result = [self.engine searchModuleExecuteQuery:query
                                                resourceMetadata:resourceMetadata
                                             snapshotsByResource:snapshotsByResource
                                                         filters:filters ?: @{}
                                                            sort:sort
                                                           limit:resolvedLimit
                                                          offset:offset
                                                           error:error];
  if (result == nil) {
    return nil;
  }
  NSMutableDictionary *response = [NSMutableDictionary dictionaryWithDictionary:result];
  response[@"resource"] = resource ?: @"";
  response[@"limit"] = @(resolvedLimit);
  response[@"offset"] = @(offset);
  response[@"engine"] = self.engineIdentifier ?: @"ALNDefaultSearchEngine";
  return response;
}

- (NSDictionary *)resourceRowForIdentifier:(NSString *)identifier metadata:(NSDictionary *)metadata {
  NSDictionary *status = nil;
  NSArray *generationHistory = nil;
  [self.lock lock];
  status = [self.statusByResource[identifier] isKindOfClass:[NSDictionary class]] ? self.statusByResource[identifier] : @{};
  generationHistory = [NSArray arrayWithArray:STNormalizeArray(self.generationHistoryByResource[identifier])];
  [self.lock unlock];
  NSMutableDictionary *row = [NSMutableDictionary dictionaryWithDictionary:status ?: @{}];
  row[@"identifier"] = identifier ?: @"";
  row[@"label"] = metadata[@"label"] ?: status[@"label"] ?: STTitleCaseIdentifier(identifier);
  row[@"adminIntegrated"] = metadata[@"adminIntegrated"] ?: @NO;
  row[@"supportsHighlights"] = metadata[@"supportsHighlights"] ?: @NO;
  row[@"defaultSort"] = metadata[@"defaultSort"] ?: @"";
  row[@"pagination"] = metadata[@"pagination"] ?: @{};
  row[@"generationHistory"] = generationHistory ?: @[];
  row[@"status"] = STResolvedIndexState(row[@"indexState"]);
  row[@"paths"] = @{
    @"html" : [NSString stringWithFormat:@"%@/resources/%@", self.prefix ?: @"/search", identifier ?: @""],
    @"api" : [NSString stringWithFormat:@"%@/resources/%@", self.apiPrefix ?: @"/search/api", identifier ?: @""],
    @"apiQuery" : [NSString stringWithFormat:@"%@/resources/%@/query", self.apiPrefix ?: @"/search/api", identifier ?: @""],
  };
  return row;
}

- (NSDictionary *)resourceDrilldownForIdentifier:(NSString *)identifier {
  NSString *resourceIdentifier = STLowerTrimmedString(identifier);
  NSDictionary *metadata = [self resourceMetadataForIdentifier:resourceIdentifier];
  if (metadata == nil) {
    return nil;
  }
  NSMutableArray *history = [NSMutableArray array];
  [self.lock lock];
  for (NSDictionary *entry in self.reindexHistory) {
    if ([STLowerTrimmedString(entry[@"resource"]) isEqualToString:resourceIdentifier]) {
      [history addObject:entry];
    }
  }
  [self.lock unlock];
  return @{
    @"resource" : [self resourceRowForIdentifier:resourceIdentifier metadata:metadata] ?: @{},
    @"history" : history ?: @[],
  };
}

- (NSDictionary *)dashboardSummary {
  NSArray *resources = [self registeredResources];
  NSMutableArray *statusRows = [NSMutableArray array];
  NSUInteger documentCount = 0;
  for (NSDictionary *metadata in resources) {
    NSString *identifier = STLowerTrimmedString(metadata[@"identifier"]);
    NSDictionary *row = [self resourceRowForIdentifier:identifier metadata:metadata];
    documentCount += [row[@"documentCount"] unsignedIntegerValue];
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
  NSString *moduleStatus = STResolvedModuleStatus(statusRows, pendingJobs, deadJobs);

  return @{
    @"config" : [self resolvedConfigSummary],
    @"resources" : STSortedArrayFromValues(statusRows, @"identifier"),
    @"history" : history ?: @[],
    @"status" : moduleStatus ?: @"healthy",
    @"engine" : @{
      @"identifier" : self.engineIdentifier ?: @"ALNDefaultSearchEngine",
      @"capabilities" : [self.engine searchModuleCapabilities] ?: @{},
    },
    @"drilldowns" : @{
      @"html" : @{
        @"dashboard" : self.prefix ?: @"/search",
        @"resourceTemplate" : [NSString stringWithFormat:@"%@/resources/:resource", self.prefix ?: @"/search"],
      },
      @"api" : @{
        @"resources" : [NSString stringWithFormat:@"%@/resources", self.apiPrefix ?: @"/search/api"],
        @"resourceTemplate" : [NSString stringWithFormat:@"%@/resources/:resource", self.apiPrefix ?: @"/search/api"],
      },
    },
    @"totals" : @{
      @"resources" : @([resources count]),
      @"documents" : @(documentCount),
      @"pendingJobs" : @([pendingJobs count]),
      @"deadLetters" : @([deadJobs count]),
    },
    @"cards" : @[
      STStatusCard(@"Resources",
                   [NSString stringWithFormat:@"%lu", (unsigned long)[resources count]],
                   @"informational",
                   @""),
      STStatusCard(@"Documents",
                   [NSString stringWithFormat:@"%lu", (unsigned long)documentCount],
                   @"informational",
                   @""),
      STStatusCard(@"Queued Reindex Jobs",
                   [NSString stringWithFormat:@"%lu", (unsigned long)[pendingJobs count]],
                   ([pendingJobs count] > 0) ? @"degraded" : @"healthy",
                   @""),
      STStatusCard(@"Dead Letters",
                   [NSString stringWithFormat:@"%lu", (unsigned long)[deadJobs count]],
                   ([deadJobs count] > 0) ? @"failing" : @"healthy",
                   @""),
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
      @{ @"name" : @"indexState", @"label" : @"State", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"documentCount", @"label" : @"Documents", @"kind" : @"integer", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"activeGeneration", @"label" : @"Active Generation", @"kind" : @"integer", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"buildingGeneration", @"label" : @"Building Generation", @"kind" : @"integer", @"list" : @NO, @"detail" : @YES },
      @{ @"name" : @"generationCount", @"label" : @"Generations", @"kind" : @"integer", @"list" : @NO, @"detail" : @YES },
      @{ @"name" : @"lastSyncOperation", @"label" : @"Last Sync", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"lastIndexedAt", @"label" : @"Last Indexed", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"lastFailureAt", @"label" : @"Last Failure", @"list" : @NO, @"detail" : @YES },
      @{ @"name" : @"lastJobID", @"label" : @"Last Job", @"list" : @NO, @"detail" : @YES },
      @{ @"name" : @"engine", @"label" : @"Engine", @"list" : @NO, @"detail" : @YES },
      @{ @"name" : @"lastError", @"label" : @"Last Error", @"list" : @NO, @"detail" : @YES },
    ],
    @"filters" : @[
      @{ @"name" : @"q", @"label" : @"Search", @"type" : @"search", @"placeholder" : @"resource, identifier, state" },
      @{ @"name" : @"indexState", @"label" : @"State", @"type" : @"select", @"choices" : @[ @"idle", @"queued", @"rebuilding", @"ready", @"degraded", @"failing" ] },
    ],
    @"sorts" : @[
      @{ @"name" : @"label", @"label" : @"Name", @"default" : @YES },
      @{ @"name" : @"documentCount", @"label" : @"Document count" },
      @{ @"name" : @"activeGeneration", @"label" : @"Generation" },
      @{ @"name" : @"lastIndexedAt", @"label" : @"Last indexed", @"direction" : @"desc" },
    ],
    @"bulkActions" : @[
      @{ @"name" : @"reindex", @"label" : @"Queue reindex", @"method" : @"POST" },
    ],
    @"exports" : @[ @"json", @"csv" ],
    @"actions" : @[
      @{ @"name" : @"reindex", @"label" : @"Reindex", @"scope" : @"row", @"method" : @"POST" },
    ],
  };
}

- (NSArray<NSDictionary *> *)adminUIListRecordsMatching:(NSString *)query
                                                  limit:(NSUInteger)limit
                                                 offset:(NSUInteger)offset
                                                  error:(NSError **)error {
  return [self adminUIListRecordsWithParameters:@{ @"q" : query ?: @"" } limit:limit offset:offset error:error];
}

- (NSArray<NSDictionary *> *)adminUIListRecordsWithParameters:(NSDictionary *)parameters
                                                        limit:(NSUInteger)limit
                                                       offset:(NSUInteger)offset
                                                        error:(NSError **)error {
  (void)error;
  NSString *search = [STLowerTrimmedString(parameters[@"q"]) copy];
  NSString *stateFilter = STLowerTrimmedString(parameters[@"indexState"]);
  NSString *sort = STLowerTrimmedString(parameters[@"sort"]);
  BOOL descending = [sort hasPrefix:@"-"];
  NSString *sortField = descending ? [sort substringFromIndex:1] : sort;
  if ([sortField length] == 0) {
    sortField = @"label";
  }
  NSArray *resources = [self.runtime dashboardSummary][@"resources"];
  NSMutableArray *matches = [NSMutableArray array];
  for (NSDictionary *entry in [resources isKindOfClass:[NSArray class]] ? resources : @[]) {
    NSString *haystack = [[NSString stringWithFormat:@"%@ %@",
                                                     STStringifyValue(entry[@"identifier"]),
                                                     STStringifyValue(entry[@"label"])] lowercaseString];
    if ([search length] > 0 && [haystack rangeOfString:search].location == NSNotFound) {
      continue;
    }
    if ([stateFilter length] > 0 && ![STLowerTrimmedString(entry[@"indexState"]) isEqualToString:stateFilter]) {
      continue;
    }
    [matches addObject:entry];
  }
  [matches sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
    NSString *left = STStringifyValue(lhs[sortField]);
    NSString *right = STStringifyValue(rhs[sortField]);
    NSComparisonResult result = [[left lowercaseString] compare:[right lowercaseString] options:NSNumericSearch];
    if (result == NSOrderedSame) {
      result = [[STStringifyValue(lhs[@"label"]) lowercaseString] compare:[STStringifyValue(rhs[@"label"]) lowercaseString]];
    }
    return descending ? -result : result;
  }];
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

- (NSDictionary *)adminUIPerformBulkActionNamed:(NSString *)actionName
                                     identifiers:(NSArray<NSString *> *)identifiers
                                      parameters:(NSDictionary *)parameters
                                           error:(NSError **)error {
  if (![[STLowerTrimmedString(actionName) lowercaseString] isEqualToString:@"reindex"]) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorNotFound, @"unknown search action", @{ @"action" : STTrimmedString(actionName) });
    }
    return nil;
  }
  NSMutableArray *records = [NSMutableArray array];
  for (NSString *identifier in identifiers ?: @[]) {
    NSDictionary *result = [self adminUIPerformActionNamed:@"reindex" identifier:identifier parameters:parameters error:error];
    if (result == nil) {
      return nil;
    }
    if ([result[@"record"] isKindOfClass:[NSDictionary class]]) {
      [records addObject:result[@"record"]];
    }
  }
  return @{
    @"count" : @([records count]),
    @"records" : records,
    @"message" : [NSString stringWithFormat:@"Queued reindex for %lu resources.", (unsigned long)[records count]],
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
                                              @"parameters" : parameters ?: @{},
                                              @"searchResult" : result ?: @{ @"results" : @[], @"total" : @0 },
                                              @"activeResource" : @"",
                                              @"activeResourceMetadata" : @{},
                                              @"searchDrilldown" : @{},
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
  NSDictionary *drilldown = [self.runtime resourceDrilldownForIdentifier:resource] ?: @{};
  NSArray *errors = (error != nil) ? @[ error.localizedDescription ?: @"search failed" ] : @[];
  [self renderTemplate:@"modules/search/dashboard/index"
               context:[self pageContextWithTitle:@"Search"
                                          heading:@"Search"
                                          message:@""
                                           errors:errors
                                            extra:@{
                                              @"query" : parameters[@"q"] ?: @"",
                                              @"parameters" : parameters ?: @{},
                                              @"searchResult" : result ?: @{ @"results" : @[], @"total" : @0 },
                                              @"activeResource" : resource ?: @"",
                                              @"activeResourceMetadata" : [self.runtime resourceMetadataForIdentifier:resource] ?: @{},
                                              @"searchDrilldown" : drilldown ?: @{},
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

- (id)apiResourceDrilldown:(ALNContext *)ctx {
  NSString *resource = STLowerTrimmedString([ctx paramValueForName:@"resource"]);
  NSDictionary *drilldown = [self.runtime resourceDrilldownForIdentifier:resource];
  if (drilldown == nil) {
    [self renderAPIErrorWithStatus:404 code:@"not_found" message:@"search resource not found" meta:@{ @"resource" : resource ?: @"" }];
    return nil;
  }
  [self renderJSONEnvelopeWithData:drilldown meta:nil error:NULL];
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
  [application registerRouteMethod:@"GET"
                              path:@"/resources/:resource"
                              name:@"search_api_resource_drilldown"
                   controllerClass:[ALNSearchModuleController class]
                            action:@"apiResourceDrilldown"];
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
         @"search_api_resource_drilldown",
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

#import "ALNSearchModule.h"

#import "ALNAdminUIModule.h"
#import "ALNApplication.h"
#import "ALNAuthModule.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNEOCRuntime.h"
#import "ALNPg.h"
#import "ALNJobsModule.h"
#import "ALNRequest.h"

NSString *const ALNSearchModuleErrorDomain = @"Arlen.Modules.Search.Error";

static NSString *const ALNSearchReindexJobIdentifier = @"search.reindex";
static NSUInteger const ALNSearchHistoryLimit = 30;
static NSUInteger const ALNSearchGenerationHistoryLimit = 6;

extern NSString *ALNEOCRender_modules_search_dashboard_index_html_eoc(id ctx, NSError **error);
extern NSString *ALNEOCRender_modules_search_layouts_main_html_eoc(id ctx, NSError **error);
extern NSString *ALNEOCRender_modules_search_result_index_html_eoc(id ctx, NSError **error);

static void STRegisterSearchModuleTemplates(void) {
  // Tests clear the global EOC registry; re-register module-owned templates when the module boots.
  ALNEOCRegisterTemplate(@"modules/search/dashboard/index.html.eoc",
                         &ALNEOCRender_modules_search_dashboard_index_html_eoc);
  ALNEOCRegisterTemplate(@"modules/search/layouts/main.html.eoc",
                         &ALNEOCRender_modules_search_layouts_main_html_eoc);
  ALNEOCRegisterTemplate(@"modules/search/result/index.html.eoc",
                         &ALNEOCRender_modules_search_result_index_html_eoc);
}

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

static NSData *STJSONDataFromObject(id object, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (object == nil || object == [NSNull null]) {
    object = @{};
  }
  return [NSJSONSerialization dataWithJSONObject:object options:0 error:error];
}

static id STJSONObjectFromData(NSData *data, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (![data isKindOfClass:[NSData class]] || [data length] == 0) {
    return nil;
  }
  return [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
}

static NSDictionary *STJSONDictionaryFromPath(NSString *path, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSString *resolvedPath = STTrimmedString(path);
  if ([resolvedPath length] == 0) {
    return @{};
  }
  NSData *data = [NSData dataWithContentsOfFile:resolvedPath options:0 error:error];
  if (data == nil) {
    return nil;
  }
  id object = STJSONObjectFromData(data, error);
  return [object isKindOfClass:[NSDictionary class]] ? object : @{};
}

static BOOL STBooleanValue(id value, BOOL defaultValue) {
  if ([value respondsToSelector:@selector(boolValue)]) {
    return [value boolValue];
  }
  NSString *normalized = STLowerTrimmedString(value);
  if ([normalized isEqualToString:@"true"] || [normalized isEqualToString:@"yes"] ||
      [normalized isEqualToString:@"1"]) {
    return YES;
  }
  if ([normalized isEqualToString:@"false"] || [normalized isEqualToString:@"no"] ||
      [normalized isEqualToString:@"0"]) {
    return NO;
  }
  return defaultValue;
}

static NSError *STError(ALNSearchModuleErrorCode code, NSString *message, NSDictionary *details) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:details ?: @{}];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"search module error";
  return [NSError errorWithDomain:ALNSearchModuleErrorDomain code:code userInfo:userInfo];
}

@protocol ALNSearchOptionalAdminRuntime <NSObject>
+ (instancetype)sharedRuntime;
- (nullable ALNApplication *)mountedApplication;
- (NSArray<NSDictionary *> *)registeredResources;
- (nullable NSArray<NSDictionary *> *)listRecordsForResourceIdentifier:(NSString *)identifier
                                                                 query:(nullable NSString *)query
                                                                 limit:(NSUInteger)limit
                                                                offset:(NSUInteger)offset
                                                                 error:(NSError **)error;
@end

@protocol ALNSearchOptionalAuthRuntime <NSObject>
+ (instancetype)sharedRuntime;
- (nullable NSString *)loginPath;
- (nullable NSString *)logoutPath;
- (nullable NSString *)totpPath;
@end

static id<ALNSearchOptionalAdminRuntime> STSharedAdminRuntime(void) {
  Class runtimeClass = NSClassFromString(@"ALNAdminUIModuleRuntime");
  if (runtimeClass == Nil || ![(id)runtimeClass respondsToSelector:@selector(sharedRuntime)]) {
    return nil;
  }
  return [(id<ALNSearchOptionalAdminRuntime>)runtimeClass sharedRuntime];
}

static id<ALNSearchOptionalAuthRuntime> STSharedAuthRuntime(void) {
  Class runtimeClass = NSClassFromString(@"ALNAuthModuleRuntime");
  if (runtimeClass == Nil || ![(id)runtimeClass respondsToSelector:@selector(sharedRuntime)]) {
    return nil;
  }
  return [(id<ALNSearchOptionalAuthRuntime>)runtimeClass sharedRuntime];
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

static NSString *STBase64URLEncodedString(NSData *data) {
  NSString *encoded = [data base64EncodedStringWithOptions:0] ?: @"";
  encoded = [encoded stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
  encoded = [encoded stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
  encoded = [encoded stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"="]];
  return encoded ?: @"";
}

static NSData *STBase64URLDecodedData(NSString *value) {
  NSString *encoded = STTrimmedString(value);
  if ([encoded length] == 0) {
    return nil;
  }
  encoded = [encoded stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
  encoded = [encoded stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
  while (([encoded length] % 4U) != 0U) {
    encoded = [encoded stringByAppendingString:@"="];
  }
  return [[NSData alloc] initWithBase64EncodedString:encoded options:0];
}

static NSString *STCursorForRecordID(NSString *recordID) {
  NSData *data = [STTrimmedString(recordID) dataUsingEncoding:NSUTF8StringEncoding];
  return ([data length] > 0) ? STBase64URLEncodedString(data) : @"";
}

static NSString *STRecordIDFromCursor(NSString *cursor) {
  NSData *data = STBase64URLDecodedData(cursor);
  NSString *value = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding];
  return STTrimmedString(value);
}

static NSDictionary *STHTTPDataRequest(NSString *method,
                                       NSString *urlString,
                                       NSDictionary *headers,
                                       NSData *bodyData,
                                       NSError **error);

static NSDictionary *STHTTPJSONRequest(NSString *method,
                                       NSString *urlString,
                                       NSDictionary *headers,
                                       id bodyObject,
                                       NSError **error) {
  NSData *bodyData = nil;
  if (bodyObject != nil && bodyObject != [NSNull null]) {
    bodyData = STJSONDataFromObject(bodyObject, error);
    if (bodyData == nil) {
      return nil;
    }
  }
  NSMutableDictionary *requestHeaders = [NSMutableDictionary dictionaryWithDictionary:headers ?: @{}];
  if (bodyData != nil) {
    requestHeaders[@"Content-Type"] = @"application/json";
  }
  return STHTTPDataRequest(method, urlString, requestHeaders, bodyData, error);
}

static NSDictionary *STHTTPDataRequest(NSString *method,
                                       NSString *urlString,
                                       NSDictionary *headers,
                                       NSData *bodyData,
                                       NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSURL *url = [NSURL URLWithString:STTrimmedString(urlString)];
  if (url == nil) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorInvalidConfiguration,
                       @"search engine URL is invalid",
                       @{ @"url" : STTrimmedString(urlString) ?: @"" });
    }
    return nil;
  }
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  [request setHTTPMethod:([STTrimmedString(method) length] > 0) ? STTrimmedString(method) : @"GET"];
  for (id rawKey in STNormalizeDictionary(headers)) {
    NSString *key = STTrimmedString(rawKey);
    NSString *value = STTrimmedString(headers[rawKey]);
    if ([key length] == 0 || [value length] == 0) {
      continue;
    }
    [request setValue:value forHTTPHeaderField:key];
  }
  if ([bodyData isKindOfClass:[NSData class]] && [bodyData length] > 0) {
    [request setHTTPBody:bodyData];
  }
  NSURLResponse *response = nil;
  NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:error];
  NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
  id object = nil;
  if ([data length] > 0) {
    object = STJSONObjectFromData(data, NULL);
    if (object == nil) {
      object = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    }
  }
  return @{
    @"status" : @([http statusCode]),
    @"headers" : [http allHeaderFields] ?: @{},
    @"body" : object ?: @{},
    @"rawBody" : data ?: [NSData data],
  };
}

static BOOL STHTTPStatusIsSuccess(NSInteger statusCode) {
  return (statusCode >= 200 && statusCode < 300);
}

static NSDictionary *STFilterComponentsFromRawKey(NSString *rawKey) {
  NSString *normalizedKey = STLowerTrimmedString(rawKey);
  NSString *field = normalizedKey;
  NSString *operatorName = @"eq";
  NSRange range = [normalizedKey rangeOfString:@"__"];
  if (range.location != NSNotFound) {
    field = [normalizedKey substringToIndex:range.location];
    operatorName = [normalizedKey substringFromIndex:(range.location + range.length)];
  }
  return @{
    @"field" : field ?: @"",
    @"operator" : operatorName ?: @"eq",
  };
}

static BOOL STSearchFieldTypeIsNumeric(NSString *type) {
  NSString *normalized = STLowerTrimmedString(type);
  return ([normalized isEqualToString:@"integer"] || [normalized isEqualToString:@"number"] ||
          [normalized isEqualToString:@"decimal"] || [normalized isEqualToString:@"float"] ||
          [normalized isEqualToString:@"double"]);
}

static BOOL STSearchFieldTypeIsBoolean(NSString *type) {
  NSString *normalized = STLowerTrimmedString(type);
  return ([normalized isEqualToString:@"boolean"] || [normalized isEqualToString:@"bool"]);
}

static NSArray *STTrimmedUniqueStringArray(id value);
static NSString *STStringifyValue(id value);

static NSString *STJSONLiteralString(id value) {
  id payload = value;
  if (payload == nil || payload == [NSNull null]) {
    payload = @"";
  }
  if (![payload isKindOfClass:[NSString class]] && ![payload isKindOfClass:[NSNumber class]] &&
      ![payload isKindOfClass:[NSArray class]] && ![payload isKindOfClass:[NSDictionary class]]) {
    payload = [payload description] ?: @"";
  }
  NSData *data = [NSJSONSerialization dataWithJSONObject:@[ payload ] options:0 error:NULL];
  NSString *text = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"[\"\"]";
  if ([text length] >= 2U && [text hasPrefix:@"["] && [text hasSuffix:@"]"]) {
    return [text substringWithRange:NSMakeRange(1U, [text length] - 2U)];
  }
  return @"\"\"";
}

static id STTypedSearchValue(id value, NSString *type) {
  NSString *normalizedType = STLowerTrimmedString(type);
  if (STSearchFieldTypeIsNumeric(normalizedType)) {
    if ([normalizedType isEqualToString:@"integer"]) {
      return @([STStringifyValue(value) integerValue]);
    }
    return @([STStringifyValue(value) doubleValue]);
  }
  if (STSearchFieldTypeIsBoolean(normalizedType)) {
    return @(STBooleanValue(value, NO));
  }
  return STTrimmedString(value);
}

static NSArray *STTypedSearchValues(id value, NSString *type) {
  NSMutableArray *values = [NSMutableArray array];
  NSArray *candidates = [value isKindOfClass:[NSArray class]]
                            ? value
                            : STTrimmedUniqueStringArray([STTrimmedString(value) componentsSeparatedByString:@","]);
  for (id entry in candidates) {
    [values addObject:STTypedSearchValue(entry, type) ?: @""];
  }
  return values;
}

static NSDictionary *STResolvedSearchSortDescriptor(NSDictionary *metadata,
                                                    NSString *requestedSort,
                                                    NSString *query) {
  NSString *resolvedSort = STLowerTrimmedString(requestedSort);
  if ([resolvedSort length] == 0) {
    resolvedSort = ([STTrimmedString(query) length] > 0) ? @"relevance" : STLowerTrimmedString(metadata[@"defaultSort"]);
    if ([resolvedSort length] == 0) {
      resolvedSort = @"relevance";
    }
  }
  BOOL descending = [resolvedSort hasPrefix:@"-"];
  NSString *field = descending ? [resolvedSort substringFromIndex:1] : resolvedSort;
  return @{
    @"value" : resolvedSort ?: @"",
    @"field" : field ?: @"",
    @"direction" : descending ? @"desc" : @"asc",
  };
}

static BOOL STAppendNDJSONLine(NSMutableData *data, id object, NSError **error) {
  NSData *line = STJSONDataFromObject(object, error);
  if (line == nil) {
    return NO;
  }
  [data appendData:line];
  [data appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
  return YES;
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

static NSArray *STTrimmedUniqueStringArray(id value) {
  NSMutableArray *strings = [NSMutableArray array];
  NSMutableSet *seen = [NSMutableSet set];
  for (id entry in [value isKindOfClass:[NSArray class]] ? value : @[]) {
    NSString *trimmed = STTrimmedString(entry);
    if ([trimmed length] == 0) {
      continue;
    }
    NSString *canonical = [trimmed lowercaseString];
    if ([seen containsObject:canonical]) {
      continue;
    }
    [seen addObject:canonical];
    [strings addObject:trimmed];
  }
  return [strings copy];
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

static NSString *STPercentEncodedPathComponent(NSString *value) {
  NSCharacterSet *allowed = [NSCharacterSet URLPathAllowedCharacterSet];
  NSMutableCharacterSet *blocked = [allowed mutableCopy];
  [blocked removeCharactersInString:@"/?#%"];
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

static NSArray<NSDictionary *> *STNormalizedChoiceArray(id value) {
  NSMutableArray<NSDictionary *> *choices = [NSMutableArray array];
  for (id entry in STNormalizeArray(value)) {
    NSString *resolvedValue = @"";
    NSString *resolvedLabel = @"";
    if ([entry isKindOfClass:[NSDictionary class]]) {
      resolvedValue = STTrimmedString(entry[@"value"]);
      if ([resolvedValue length] == 0) {
        resolvedValue = STTrimmedString(entry[@"id"]);
      }
      resolvedLabel = STTrimmedString(entry[@"label"]);
    } else {
      resolvedValue = STTrimmedString(entry);
    }
    if ([resolvedValue length] == 0) {
      continue;
    }
    if ([resolvedLabel length] == 0) {
      resolvedLabel = resolvedValue;
    }
    BOOL exists = NO;
    for (NSDictionary *existing in choices) {
      if ([STLowerTrimmedString(existing[@"value"]) isEqualToString:STLowerTrimmedString(resolvedValue)]) {
        exists = YES;
        break;
      }
    }
    if (exists) {
      continue;
    }
    [choices addObject:@{
      @"value" : resolvedValue,
      @"label" : resolvedLabel,
    }];
  }
  return [choices sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
    return [STLowerTrimmedString(lhs[@"label"]) compare:STLowerTrimmedString(rhs[@"label"])];
  }];
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
@property(nonatomic, strong) NSMutableDictionary *engineStateByResource;
@property(nonatomic, strong) NSMutableDictionary *pendingReplayOperationsByResource;
@property(nonatomic, strong) NSMutableDictionary *statusByResource;
@property(nonatomic, strong) NSMutableDictionary *generationHistoryByResource;
@property(nonatomic, strong) NSMutableArray *reindexHistory;
@property(nonatomic, strong) NSMutableArray *recentQueries;
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
- (nullable id<ALNSearchResourceDefinition>)resourceDefinitionForIdentifier:(NSString *)identifier;
- (NSArray<NSString *> *)resourceIdentifiersFromMetadataArray:(NSArray<NSDictionary *> *)resourceMetadata;
- (nullable NSDictionary *)searchQuery:(nullable NSString *)query
                    resourceIdentifier:(nullable NSString *)resourceIdentifier
              allowedResourceIdentifiers:(nullable NSArray<NSString *> *)allowedResourceIdentifiers
                               filters:(nullable NSDictionary *)filters
                                  sort:(nullable NSString *)sort
                                 limit:(NSUInteger)limit
                                offset:(NSUInteger)offset
                          queryOptions:(nullable NSDictionary *)queryOptions
                                 error:(NSError **)error;
- (NSDictionary *)shapedResultForDocument:(NSDictionary *)document
                                  metadata:(NSDictionary *)metadata
                                     error:(NSError **)error;
- (nullable NSArray<NSDictionary *> *)promotedResultsForQuery:(NSString *)query
                                              resourceMetadata:(NSArray<NSDictionary *> *)resourceMetadata
                                           snapshotsByResource:(NSDictionary<NSString *, NSDictionary *> *)snapshotsByResource
                                                         error:(NSError **)error;
- (NSArray<NSDictionary *> *)facetSummariesForMatchedDocuments:(NSArray<NSDictionary *> *)matchedDocuments
                                               resourceMetadata:(NSArray<NSDictionary *> *)resourceMetadata
                                                        filters:(nullable NSDictionary *)filters;
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
- (void)recordRecentQuery:(NSDictionary *)entry;
- (nullable NSDictionary *)additionalQueryFiltersForResourceMetadata:(NSDictionary *)metadata
                                                             context:(ALNContext *)context
                                                               error:(NSError **)error;
- (nullable NSArray<NSString *> *)visibleFilterValuesForField:(NSString *)field
                                                     metadata:(NSDictionary *)metadata
                                                   visibility:(NSDictionary *)visibility
                                              explicitKeyName:(NSString *)explicitKeyName
                                                 hiddenValues:(NSArray<NSString *> *)hiddenValues
                                                        error:(NSError **)error;
- (BOOL)record:(NSDictionary *)record
  isIndexableForMetadata:(NSDictionary *)metadata
              definition:(id<ALNSearchResourceDefinition>)definition
                   error:(NSError **)error;
- (BOOL)enumerateIndexableRecordsForDefinition:(id<ALNSearchResourceDefinition>)definition
                                      metadata:(NSDictionary *)metadata
                                     batchSize:(NSUInteger)batchSize
                                    usingBlock:(ALNSearchResourceBatchConsumer)consumer
                                         error:(NSError **)error;
- (nullable NSArray<NSDictionary *> *)recordsForDefinition:(id<ALNSearchResourceDefinition>)definition
                                                  metadata:(NSDictionary *)metadata
                                                 batchSize:(NSUInteger)batchSize
                                                     error:(NSError **)error;
- (nullable NSDictionary *)drainReplayOperationsForResourceIdentifier:(NSString *)identifier
                                                                 mode:(NSString *)mode
                                                                error:(NSError **)error;
- (void)enqueueReplayOperation:(NSDictionary *)payload
          forResourceIdentifier:(NSString *)identifier
                       metadata:(NSDictionary *)metadata;
- (NSDictionary *)resourceRowForIdentifier:(NSString *)identifier metadata:(NSDictionary *)metadata;

@end

@interface ALNSearchReindexJob : NSObject <ALNJobsJobDefinition>
@end

@interface ALNDefaultSearchEngine : NSObject <ALNSearchEngine>

- (NSDictionary *)effectiveFilters:(NSDictionary *)filters
                           metadata:(NSDictionary *)metadata
                            options:(NSDictionary *)options;
- (nullable id)searchModuleBeginBuildForMetadata:(NSDictionary *)metadata
                                      generation:(NSUInteger)generation
                                           error:(NSError **)error;
- (BOOL)searchModuleAppendBuildRecords:(NSArray<NSDictionary *> *)records
                              metadata:(NSDictionary *)metadata
                                 state:(id)state
                                 error:(NSError **)error;
- (nullable NSDictionary *)searchModuleFinalizeBuildState:(id)state
                                                 metadata:(NSDictionary *)metadata
                                                    error:(NSError **)error;

@end

@interface ALNPostgresSearchEngine : ALNDefaultSearchEngine
@end

@interface ALNExternalSearchEngine : ALNDefaultSearchEngine

@property(nonatomic, assign) ALNSearchModuleRuntime *runtime;
@property(nonatomic, assign) ALNApplication *application;
@property(nonatomic, copy) NSDictionary *moduleConfig;
@property(nonatomic, copy) NSDictionary *engineConfig;
@property(nonatomic, copy) NSDictionary *fixturePayload;
@property(nonatomic, copy) NSString *serviceURL;
@property(nonatomic, copy) NSString *apiKey;
@property(nonatomic, assign) BOOL liveRequestsEnabled;
@property(nonatomic, assign) NSUInteger chunkSize;

- (NSString *)engineConfigKey;
- (NSString *)externalEngineName;
- (NSDictionary *)externalCapabilities;
- (NSDictionary *)externalIndexDescriptorForMetadata:(NSDictionary *)metadata;
- (NSString *)externalIndexNameForMetadata:(NSDictionary *)metadata;
- (BOOL)syncLiveSnapshotForMetadata:(NSDictionary *)metadata
                           snapshot:(NSDictionary *)snapshot
                              error:(NSError **)error;
- (BOOL)syncLiveOperation:(NSString *)operation
                   record:(NSDictionary *)record
                 metadata:(NSDictionary *)metadata
                 snapshot:(NSDictionary *)snapshot
                    error:(NSError **)error;
- (NSString *)searchPathForIndexName:(NSString *)indexName;
- (nullable NSDictionary *)fixtureResponseForOperation:(NSString *)operation
                                         resourceID:(NSString *)resourceID
                                              query:(NSString *)query
                                            options:(NSDictionary *)options;
- (NSDictionary *)normalizedExternalResponse:(NSDictionary *)response
                             resourceMetadata:(NSDictionary *)metadata;
- (NSDictionary<NSString *, NSDictionary *> *)filterMetadataByFieldForMetadata:(NSDictionary *)metadata;
- (NSString *)fieldTypeForField:(NSString *)field metadata:(NSDictionary *)metadata;
- (NSArray<NSString *> *)queryFieldsForMetadata:(NSDictionary *)metadata autocomplete:(BOOL)autocomplete;
- (id)liveDocumentPayloadForDocument:(NSDictionary *)document metadata:(NSDictionary *)metadata;
- (nullable NSDictionary *)validatedHTTPResponse:(NSDictionary *)response
                                   allowNotFound:(BOOL)allowNotFound
                                         message:(NSString *)message
                                            path:(NSString *)path
                                           error:(NSError **)error;
- (nullable NSDictionary *)jsonRequestWithMethod:(NSString *)method
                                            path:(NSString *)path
                                         headers:(NSDictionary *)headers
                                            body:(id)body
                                   allowNotFound:(BOOL)allowNotFound
                                         message:(NSString *)message
                                           error:(NSError **)error;
- (nullable NSDictionary *)dataRequestWithMethod:(NSString *)method
                                            path:(NSString *)path
                                         headers:(NSDictionary *)headers
                                            body:(NSData *)body
                                   allowNotFound:(BOOL)allowNotFound
                                         message:(NSString *)message
                                           error:(NSError **)error;
- (NSArray<NSDictionary *> *)facetSummariesFromBuckets:(NSDictionary<NSString *, NSDictionary *> *)buckets
                                              metadata:(NSDictionary *)metadata
                                               filters:(NSDictionary *)filters;
- (nullable NSDictionary *)performLiveSearchForIndexName:(NSString *)indexName
                                                metadata:(NSDictionary *)metadata
                                                   query:(NSString *)query
                                                 filters:(NSDictionary *)filters
                                                    sort:(NSString *)sort
                                                   limit:(NSUInteger)limit
                                                  offset:(NSUInteger)offset
                                                 options:(NSDictionary *)options
                                                   error:(NSError **)error;

@end

@interface ALNMeilisearchSearchEngine : ALNExternalSearchEngine
@end

@interface ALNOpenSearchSearchEngine : ALNExternalSearchEngine
@end

@interface ALNSearchAdminRuntimeBackedResource : NSObject <ALNSearchResourceDefinition>

@property(nonatomic, strong) id<ALNSearchOptionalAdminRuntime> adminRuntime;
@property(nonatomic, copy) NSDictionary *metadata;

- (instancetype)initWithAdminRuntime:(id<ALNSearchOptionalAdminRuntime>)adminRuntime
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
@property(nonatomic, strong) id<ALNSearchOptionalAuthRuntime> authRuntime;

@end

@implementation ALNDefaultSearchEngine

- (NSArray<NSString *> *)searchFieldsForMetadata:(NSDictionary *)metadata {
  NSArray *fields = STNormalizedStringArray(metadata[@"searchFields"]);
  return ([fields count] > 0) ? fields : STNormalizeArray(metadata[@"indexedFields"]);
}

- (NSArray<NSString *> *)autocompleteFieldsForMetadata:(NSDictionary *)metadata {
  NSArray *fields = STNormalizedStringArray(metadata[@"autocompleteFields"]);
  if ([fields count] > 0) {
    return fields;
  }
  NSString *primaryField = STLowerTrimmedString(metadata[@"primaryField"]);
  return ([primaryField length] > 0) ? @[ primaryField ] : [self searchFieldsForMetadata:metadata];
}

- (NSArray<NSString *> *)suggestionFieldsForMetadata:(NSDictionary *)metadata {
  NSArray *fields = STNormalizedStringArray(metadata[@"suggestionFields"]);
  return ([fields count] > 0) ? fields : [self searchFieldsForMetadata:metadata];
}

- (NSArray<NSString *> *)highlightFieldsForMetadata:(NSDictionary *)metadata {
  NSArray *fields = STNormalizedStringArray(metadata[@"highlightFields"]);
  return ([fields count] > 0) ? fields : [self searchFieldsForMetadata:metadata];
}

- (NSArray<NSString *> *)availableQueryModesForMetadata:(NSDictionary *)metadata {
  NSArray *modes = STNormalizedStringArray(metadata[@"queryModes"]);
  return ([modes count] > 0) ? modes : @[ @"autocomplete", @"fuzzy", @"phrase", @"search" ];
}

- (NSDictionary *)effectiveFilters:(NSDictionary *)filters
                           metadata:(NSDictionary *)metadata
                            options:(NSDictionary *)options {
  NSMutableDictionary *effective = [NSMutableDictionary dictionaryWithDictionary:filters ?: @{}];
  NSString *identifier = STLowerTrimmedString(metadata[@"identifier"]);
  NSDictionary *resourceFilters = STNormalizeDictionary(STNormalizeDictionary(options[@"resourceFilters"])[identifier]);
  if ([resourceFilters count] > 0) {
    [effective addEntriesFromDictionary:resourceFilters];
  }
  return effective;
}

- (NSString *)normalizedQueryModeFromOptions:(NSDictionary *)options metadata:(NSDictionary *)metadata {
  NSString *mode = STLowerTrimmedString(options[@"mode"]);
  if ([mode length] == 0) {
    mode = @"search";
  }
  NSArray *availableModes = [self availableQueryModesForMetadata:metadata];
  return [availableModes containsObject:mode] ? mode : @"search";
}

- (NSArray<NSString *> *)tokensForText:(NSString *)text {
  NSString *source = STLowerTrimmedString(text);
  if ([source length] == 0) {
    return @[];
  }
  NSCharacterSet *separator = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
  NSMutableOrderedSet<NSString *> *tokens = [NSMutableOrderedSet orderedSet];
  for (NSString *part in [source componentsSeparatedByCharactersInSet:separator]) {
    NSString *token = STLowerTrimmedString(part);
    if ([token length] < 2) {
      continue;
    }
    [tokens addObject:token];
  }
  return [tokens array];
}

- (NSSet<NSString *> *)trigramsForString:(NSString *)text {
  NSString *normalized = [NSString stringWithFormat:@"  %@  ", STLowerTrimmedString(text)];
  if ([normalized length] < 3) {
    return [NSSet set];
  }
  NSMutableSet<NSString *> *trigrams = [NSMutableSet set];
  for (NSUInteger index = 0; (index + 2U) < [normalized length]; index++) {
    [trigrams addObject:[normalized substringWithRange:NSMakeRange(index, 3U)]];
  }
  return trigrams;
}

- (double)trigramSimilarityForString:(NSString *)lhs other:(NSString *)rhs {
  NSSet<NSString *> *left = [self trigramsForString:lhs];
  NSSet<NSString *> *right = [self trigramsForString:rhs];
  if ([left count] == 0 || [right count] == 0) {
    return 0.0;
  }
  NSMutableSet<NSString *> *intersection = [NSMutableSet setWithSet:left];
  [intersection intersectSet:right];
  return (2.0 * (double)[intersection count]) / ((double)[left count] + (double)[right count]);
}

- (NSUInteger)levenshteinDistanceBetween:(NSString *)lhs and:(NSString *)rhs {
  NSString *left = STLowerTrimmedString(lhs);
  NSString *right = STLowerTrimmedString(rhs);
  NSUInteger leftLength = [left length];
  NSUInteger rightLength = [right length];
  if (leftLength == 0U) {
    return rightLength;
  }
  if (rightLength == 0U) {
    return leftLength;
  }
  NSMutableArray<NSNumber *> *previous = [NSMutableArray arrayWithCapacity:(rightLength + 1U)];
  NSMutableArray<NSNumber *> *current = [NSMutableArray arrayWithCapacity:(rightLength + 1U)];
  for (NSUInteger column = 0; column <= rightLength; column++) {
    [previous addObject:@(column)];
    [current addObject:@0];
  }
  for (NSUInteger row = 1; row <= leftLength; row++) {
    current[0] = @(row);
    unichar leftChar = [left characterAtIndex:(row - 1U)];
    for (NSUInteger column = 1; column <= rightLength; column++) {
      unichar rightChar = [right characterAtIndex:(column - 1U)];
      NSUInteger substitutionCost = (leftChar == rightChar) ? 0U : 1U;
      NSUInteger deletion = [previous[column] unsignedIntegerValue] + 1U;
      NSUInteger insertion = [current[column - 1U] unsignedIntegerValue] + 1U;
      NSUInteger substitution = [previous[column - 1U] unsignedIntegerValue] + substitutionCost;
      current[column] = @(MIN(MIN(deletion, insertion), substitution));
    }
    NSMutableArray<NSNumber *> *swap = previous;
    previous = current;
    current = swap;
  }
  return [[previous lastObject] unsignedIntegerValue];
}

- (BOOL)text:(NSString *)text containsQueryAtWordBoundary:(NSString *)query {
  NSString *source = STLowerTrimmedString(text);
  NSString *needle = STLowerTrimmedString(query);
  if ([source length] == 0 || [needle length] == 0) {
    return NO;
  }
  if ([source hasPrefix:needle]) {
    return YES;
  }
  NSRange match = [source rangeOfString:[@" " stringByAppendingString:needle]];
  return (match.location != NSNotFound);
}

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

  NSArray *searchFields = [self searchFieldsForMetadata:metadata];
  NSArray *autocompleteFields = [self autocompleteFieldsForMetadata:metadata];
  NSMutableDictionary *fieldText = [NSMutableDictionary dictionary];
  NSMutableArray *parts = [NSMutableArray array];
  NSMutableArray *autocompleteParts = [NSMutableArray array];
  for (NSString *field in searchFields) {
    NSString *value = STStringifyValue(record[field]);
    if ([value length] == 0) {
      continue;
    }
    fieldText[field] = value;
    [parts addObject:value];
  }
  for (NSString *field in autocompleteFields) {
    NSString *value = STStringifyValue(record[field]);
    if ([value length] == 0 || [autocompleteParts containsObject:value]) {
      continue;
    }
    [autocompleteParts addObject:value];
  }

  NSString *title = STStringifyValue(record[primaryField]);
  if ([title length] == 0) {
    title = recordID;
  }

  NSString *summaryField = STLowerTrimmedString(metadata[@"summaryField"]);
  NSString *summary = @"";
  if ([summaryField length] > 0) {
    summary = STStringifyValue(record[summaryField]);
  }
  if ([summary length] == 0) {
    for (NSString *field in searchFields) {
      if ([field isEqualToString:primaryField]) {
        continue;
      }
      summary = STStringifyValue(record[field]);
      if ([summary length] > 0) {
        break;
      }
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
    @"autocompleteText" : [autocompleteParts componentsJoinedByString:@" "],
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

- (NSComparisonResult)compareActualValue:(id)actual expectedValue:(id)expected type:(NSString *)type {
  NSString *normalizedType = STLowerTrimmedString(type);
  if ([normalizedType isEqualToString:@"integer"] || [normalizedType isEqualToString:@"number"] ||
      [normalizedType isEqualToString:@"decimal"] || [normalizedType isEqualToString:@"float"]) {
    double left = [STStringifyValue(actual) doubleValue];
    double right = [STStringifyValue(expected) doubleValue];
    if (left < right) {
      return NSOrderedAscending;
    }
    if (left > right) {
      return NSOrderedDescending;
    }
    return NSOrderedSame;
  }
  if ([normalizedType isEqualToString:@"boolean"] || [normalizedType isEqualToString:@"bool"]) {
    BOOL left = STBooleanValue(actual, NO);
    BOOL right = STBooleanValue(expected, NO);
    if (left == right) {
      return NSOrderedSame;
    }
    return left ? NSOrderedDescending : NSOrderedAscending;
  }
  NSString *left = [[STStringifyValue(actual) lowercaseString] copy];
  NSString *right = [[STStringifyValue(expected) lowercaseString] copy];
  return [left compare:right options:NSNumericSearch];
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
    id expectedValue = filters[rawKey];
    id actualValue = record[field];
    NSString *filterType = STLowerTrimmedString(filterMetadata[@"type"]);
    if ([filterType length] == 0) {
      filterType = @"string";
    }
    NSString *actualString = [[STStringifyValue(actualValue) lowercaseString] copy];
    NSString *expectedString = [[STStringifyValue(expectedValue) lowercaseString] copy];
    if ([operatorName isEqualToString:@"contains"]) {
      if ([actualString rangeOfString:expectedString].location == NSNotFound) {
        return NO;
      }
      continue;
    }
    if ([operatorName isEqualToString:@"gt"] || [operatorName isEqualToString:@"gte"] ||
        [operatorName isEqualToString:@"lt"] || [operatorName isEqualToString:@"lte"]) {
      NSComparisonResult result = [self compareActualValue:actualValue expectedValue:expectedValue type:filterType];
      if ([operatorName isEqualToString:@"gt"] && result != NSOrderedDescending) {
        return NO;
      }
      if ([operatorName isEqualToString:@"gte"] && !(result == NSOrderedDescending || result == NSOrderedSame)) {
        return NO;
      }
      if ([operatorName isEqualToString:@"lt"] && result != NSOrderedAscending) {
        return NO;
      }
      if ([operatorName isEqualToString:@"lte"] && !(result == NSOrderedAscending || result == NSOrderedSame)) {
        return NO;
      }
      continue;
    }
    if ([operatorName isEqualToString:@"in"]) {
      NSArray *expectedParts = [expectedValue isKindOfClass:[NSArray class]]
                                   ? STNormalizedStringArray(expectedValue)
                                   : STNormalizedStringArray([expectedString componentsSeparatedByString:@","]);
      if (![expectedParts containsObject:actualString]) {
        return NO;
      }
      continue;
    }
    if ([self compareActualValue:actualValue expectedValue:expectedValue type:filterType] != NSOrderedSame) {
      return NO;
    }
  }
  return YES;
}

- (double)scoreText:(NSString *)text
             weight:(NSUInteger)weight
              query:(NSString *)query
               mode:(NSString *)mode
          highlight:(NSString **)highlight {
  NSString *source = STStringifyValue(text);
  NSString *needle = STLowerTrimmedString(query);
  NSString *lowerSource = [source lowercaseString];
  if ([needle length] == 0 || [lowerSource length] == 0) {
    return 0.0;
  }
  double score = 0.0;
  NSString *resolvedHighlight = @"";
  if ([mode isEqualToString:@"phrase"]) {
    if ([lowerSource rangeOfString:needle].location != NSNotFound) {
      score = (double)(weight * 12U);
      resolvedHighlight = [self snippetForText:source query:needle];
    }
  } else if ([mode isEqualToString:@"autocomplete"]) {
    if ([self text:source containsQueryAtWordBoundary:needle]) {
      score = (double)(weight * 16U);
      resolvedHighlight = [self snippetForText:source query:needle];
    }
  } else if ([mode isEqualToString:@"fuzzy"]) {
    if ([lowerSource rangeOfString:needle].location != NSNotFound) {
      score = (double)(weight * 10U);
      resolvedHighlight = [self snippetForText:source query:needle];
    } else {
      for (NSString *token in [self tokensForText:source]) {
        double trigram = [self trigramSimilarityForString:token other:needle];
        NSUInteger distance = [self levenshteinDistanceBetween:token and:needle];
        if (trigram < 0.25 && distance > 2U) {
          continue;
        }
        double candidate = ((trigram * 100.0) + (distance <= 2U ? (28.0 - (double)(distance * 8U)) : 0.0)) * (double)weight / 10.0;
        if (candidate > score) {
          score = candidate;
          resolvedHighlight = [self snippetForText:source query:token];
        }
      }
    }
  } else {
    NSUInteger fieldMatches = 0U;
    NSRange searchRange = NSMakeRange(0, [lowerSource length]);
    while (searchRange.location != NSNotFound && searchRange.location < [lowerSource length]) {
      NSRange found = [lowerSource rangeOfString:needle options:0 range:searchRange];
      if (found.location == NSNotFound) {
        break;
      }
      fieldMatches += 1U;
      NSUInteger nextLocation = found.location + found.length;
      if (nextLocation >= [lowerSource length]) {
        break;
      }
      searchRange = NSMakeRange(nextLocation, [lowerSource length] - nextLocation);
    }
    if (fieldMatches > 0U) {
      score = (double)(fieldMatches * weight);
      resolvedHighlight = [self snippetForText:source query:needle];
    }
  }
  if (highlight != NULL) {
    *highlight = resolvedHighlight;
  }
  return score;
}

- (nullable NSDictionary *)rankedMatchForDocument:(NSDictionary *)document
                                         metadata:(NSDictionary *)metadata
                                       generation:(NSNumber *)generation
                                            query:(NSString *)query
                                             mode:(NSString *)mode {
  NSString *needle = STTrimmedString(query);
  NSString *resolvedHighlight = @"";
  double score = 0.0;
  NSMutableArray<NSString *> *matchedFields = [NSMutableArray array];
  NSDictionary *fieldText = STNormalizeDictionary(document[@"fieldText"]);
  NSDictionary *weights = STNormalizeDictionary(metadata[@"weightedFields"]);
  NSArray *fields = [mode isEqualToString:@"autocomplete"] ? [self autocompleteFieldsForMetadata:metadata] : [self searchFieldsForMetadata:metadata];
  for (NSString *field in fields) {
    NSString *text = STStringifyValue(fieldText[field]);
    if ([text length] == 0) {
      continue;
    }
    NSUInteger weight = [weights[field] respondsToSelector:@selector(unsignedIntegerValue)]
                            ? MAX((NSUInteger)1U, [weights[field] unsignedIntegerValue])
                            : 1U;
    NSString *fieldHighlight = @"";
    double fieldScore = [self scoreText:text weight:weight query:needle mode:mode highlight:&fieldHighlight];
    if (fieldScore > 0.0 && ![matchedFields containsObject:field]) {
      [matchedFields addObject:field];
    }
    if (fieldScore > score) {
      score = fieldScore;
      if ([fieldHighlight length] > 0) {
        resolvedHighlight = fieldHighlight;
      }
    } else {
      score += fieldScore;
      if ([resolvedHighlight length] == 0 && [fieldHighlight length] > 0) {
        resolvedHighlight = fieldHighlight;
      }
    }
  }
  if ([needle length] > 0 && score <= 0.0) {
    return nil;
  }
  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:document];
  result[@"resourceLabel"] = metadata[@"label"] ?: STTitleCaseIdentifier(metadata[@"identifier"]);
  result[@"score"] = @((NSInteger)llround(score));
  result[@"scoreValue"] = @(score);
  result[@"generation"] = generation ?: @0;
  result[@"matchedFields"] = matchedFields ?: @[];
  if ([resolvedHighlight length] > 0 && STBooleanValue(metadata[@"supportsHighlights"], YES)) {
    result[@"highlights"] = @[ resolvedHighlight ];
  } else {
    result[@"highlights"] = @[];
  }
  result[@"explain"] = @{
    @"mode" : mode ?: @"search",
    @"matchedFields" : matchedFields ?: @[],
    @"supportsHighlights" : @(STBooleanValue(metadata[@"supportsHighlights"], YES)),
  };
  return result;
}

- (NSArray<NSDictionary *> *)sortedMatches:(NSArray<NSDictionary *> *)matches
                                      sort:(NSString *)sort
                                 queryMode:(NSString *)queryMode
                             queryProvided:(BOOL)queryProvided {
  NSString *effectiveSort = STLowerTrimmedString(sort);
  if ([effectiveSort length] == 0) {
    effectiveSort = queryProvided ? @"relevance" : @"";
  }
  BOOL descending = [effectiveSort hasPrefix:@"-"];
  NSString *sortField = descending ? [effectiveSort substringFromIndex:1] : effectiveSort;
  return [matches sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
    if ([sortField length] == 0 || [sortField isEqualToString:@"relevance"]) {
      double leftScore = [lhs[@"scoreValue"] respondsToSelector:@selector(doubleValue)] ? [lhs[@"scoreValue"] doubleValue] : [lhs[@"score"] doubleValue];
      double rightScore = [rhs[@"scoreValue"] respondsToSelector:@selector(doubleValue)] ? [rhs[@"scoreValue"] doubleValue] : [rhs[@"score"] doubleValue];
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
}

- (NSArray<NSString *> *)autocompleteSuggestionsForDocuments:(NSArray<NSDictionary *> *)documents
                                                    metadata:(NSDictionary *)metadata
                                                       query:(NSString *)query
                                                       limit:(NSUInteger)limit {
  NSString *needle = STLowerTrimmedString(query);
  if ([needle length] == 0) {
    return @[];
  }
  NSMutableOrderedSet<NSString *> *suggestions = [NSMutableOrderedSet orderedSet];
  NSArray *fields = [self autocompleteFieldsForMetadata:metadata];
  for (NSDictionary *document in documents) {
    NSDictionary *record = STNormalizeDictionary(document[@"record"]);
    for (NSString *field in fields) {
      NSString *value = STTrimmedString(record[field]);
      if ([value length] == 0) {
        continue;
      }
      NSString *lower = [value lowercaseString];
      if (![self text:value containsQueryAtWordBoundary:needle] && [lower rangeOfString:needle].location == NSNotFound) {
        continue;
      }
      [suggestions addObject:value];
      if ([suggestions count] >= MAX((NSUInteger)1U, limit)) {
        return [suggestions array];
      }
    }
  }
  return [suggestions array];
}

- (NSArray<NSString *> *)suggestedTermsForDocuments:(NSArray<NSDictionary *> *)documents
                                           metadata:(NSDictionary *)metadata
                                              query:(NSString *)query
                                              limit:(NSUInteger)limit {
  NSString *needle = STLowerTrimmedString(query);
  if ([needle length] == 0) {
    return @[];
  }
  NSMutableDictionary<NSString *, NSNumber *> *scoresByCandidate = [NSMutableDictionary dictionary];
  NSArray *fields = [self suggestionFieldsForMetadata:metadata];
  for (NSDictionary *document in documents) {
    NSDictionary *record = STNormalizeDictionary(document[@"record"]);
    for (NSString *field in fields) {
      for (NSString *token in [self tokensForText:STStringifyValue(record[field])]) {
        if ([token isEqualToString:needle]) {
          continue;
        }
        double trigram = [self trigramSimilarityForString:token other:needle];
        NSUInteger distance = [self levenshteinDistanceBetween:token and:needle];
        if (trigram < 0.22 && distance > 2U) {
          continue;
        }
        NSInteger score = (NSInteger)llround(trigram * 100.0) + (distance <= 2U ? (24 - (NSInteger)(distance * 8U)) : 0);
        NSNumber *existing = scoresByCandidate[token];
        if (existing == nil || [existing integerValue] < score) {
          scoresByCandidate[token] = @(score);
        }
      }
    }
  }
  NSArray<NSString *> *candidates = [scoresByCandidate allKeys];
  candidates = [candidates sortedArrayUsingComparator:^NSComparisonResult(NSString *lhs, NSString *rhs) {
    NSInteger leftScore = [scoresByCandidate[lhs] integerValue];
    NSInteger rightScore = [scoresByCandidate[rhs] integerValue];
    if (leftScore != rightScore) {
      return (leftScore > rightScore) ? NSOrderedAscending : NSOrderedDescending;
    }
    return [lhs compare:rhs];
  }];
  if ([candidates count] > MAX((NSUInteger)1U, limit)) {
    candidates = [candidates subarrayWithRange:NSMakeRange(0, MAX((NSUInteger)1U, limit))];
  }
  return candidates;
}

- (nullable id)searchModuleBeginBuildForMetadata:(NSDictionary *)metadata
                                      generation:(NSUInteger)generation
                                           error:(NSError **)error {
  (void)metadata;
  (void)error;
  return [@{
    @"generation" : @(MAX((NSUInteger)1U, generation)),
    @"documents" : [NSMutableArray array],
  } mutableCopy];
}

- (BOOL)searchModuleAppendBuildRecords:(NSArray<NSDictionary *> *)records
                              metadata:(NSDictionary *)metadata
                                 state:(id)state
                                 error:(NSError **)error {
  NSMutableDictionary *buildState = [state isKindOfClass:[NSMutableDictionary class]] ? (NSMutableDictionary *)state : nil;
  NSMutableArray *documents = [buildState[@"documents"] isKindOfClass:[NSMutableArray class]] ? buildState[@"documents"] : nil;
  if (buildState == nil || documents == nil) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorExecutionFailed, @"search engine build state is invalid", nil);
    }
    return NO;
  }
  for (NSDictionary *record in STNormalizeArray(records)) {
    if (![record isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *document = [self normalizedDocumentForRecord:record metadata:metadata];
    if (document != nil) {
      [documents addObject:document];
    }
  }
  return YES;
}

- (nullable NSDictionary *)searchModuleFinalizeBuildState:(id)state
                                                 metadata:(NSDictionary *)metadata
                                                    error:(NSError **)error {
  (void)metadata;
  NSMutableDictionary *buildState = [state isKindOfClass:[NSMutableDictionary class]] ? (NSMutableDictionary *)state : nil;
  NSMutableArray *documents = [buildState[@"documents"] isKindOfClass:[NSMutableArray class]] ? buildState[@"documents"] : nil;
  NSUInteger generation = [buildState[@"generation"] respondsToSelector:@selector(unsignedIntegerValue)]
                              ? MAX((NSUInteger)1U, [buildState[@"generation"] unsignedIntegerValue])
                              : 1U;
  if (buildState == nil || documents == nil) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorExecutionFailed, @"search engine build state is invalid", nil);
    }
    return nil;
  }
  [documents sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
    return [STTrimmedString(lhs[@"recordID"]) compare:STTrimmedString(rhs[@"recordID"])];
  }];
  return @{
    @"generation" : @(generation),
    @"builtAt" : @([[NSDate date] timeIntervalSince1970]),
    @"documentCount" : @([documents count]),
    @"documents" : [NSArray arrayWithArray:documents],
  };
}

- (nullable NSDictionary *)searchModuleSnapshotForMetadata:(NSDictionary *)metadata
                                                   records:(NSArray<NSDictionary *> *)records
                                                generation:(NSUInteger)generation
                                                     error:(NSError **)error {
  id state = [self searchModuleBeginBuildForMetadata:metadata generation:generation error:error];
  if (state == nil) {
    return nil;
  }
  if (![self searchModuleAppendBuildRecords:records metadata:metadata state:state error:error]) {
    return nil;
  }
  return [self searchModuleFinalizeBuildState:state metadata:metadata error:error];
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

- (nullable NSDictionary *)searchModuleExecuteQuery:(NSString *)query
                                     resourceMetadata:(NSArray<NSDictionary *> *)resourceMetadata
                                  snapshotsByResource:(NSDictionary<NSString *, NSDictionary *> *)snapshotsByResource
                                              filters:(NSDictionary *)filters
                                                 sort:(NSString *)sort
                                                limit:(NSUInteger)limit
                                               offset:(NSUInteger)offset
                                                error:(NSError **)error {
  return [self searchModuleExecuteQuery:query
                        resourceMetadata:resourceMetadata
                     snapshotsByResource:snapshotsByResource
                                 filters:filters
                                    sort:sort
                                   limit:limit
                                  offset:offset
                                 options:nil
                                   error:error];
}

- (nullable NSDictionary *)searchModuleExecuteQuery:(NSString *)query
                                     resourceMetadata:(NSArray<NSDictionary *> *)resourceMetadata
                                  snapshotsByResource:(NSDictionary<NSString *, NSDictionary *> *)snapshotsByResource
                                              filters:(NSDictionary *)filters
                                                 sort:(NSString *)sort
                                                limit:(NSUInteger)limit
                                               offset:(NSUInteger)offset
                                              options:(NSDictionary *)options
                                                error:(NSError **)error {
  NSString *normalizedQuery = STTrimmedString(query);
  NSString *normalizedSort = STLowerTrimmedString(sort);
  NSMutableArray *matches = [NSMutableArray array];
  NSMutableArray *candidateDocuments = [NSMutableArray array];
  NSMutableOrderedSet<NSString *> *availableModes = [NSMutableOrderedSet orderedSet];
  NSUInteger autocompleteLimit = [options[@"autocompleteLimit"] respondsToSelector:@selector(unsignedIntegerValue)]
                                     ? MAX((NSUInteger)1U, [options[@"autocompleteLimit"] unsignedIntegerValue])
                                     : 5U;
  NSUInteger suggestionsLimit = [options[@"suggestionsLimit"] respondsToSelector:@selector(unsignedIntegerValue)]
                                    ? MAX((NSUInteger)1U, [options[@"suggestionsLimit"] unsignedIntegerValue])
                                    : 3U;

  for (NSDictionary *metadata in STNormalizeArray(resourceMetadata)) {
    NSString *identifier = STLowerTrimmedString(metadata[@"identifier"]);
    NSDictionary *snapshot = STNormalizeDictionary(snapshotsByResource[identifier]);
    NSArray *documents = STNormalizeArray(snapshot[@"documents"]);
    NSString *queryMode = [self normalizedQueryModeFromOptions:options metadata:metadata];
    for (NSString *mode in [self availableQueryModesForMetadata:metadata]) {
      [availableModes addObject:mode];
    }

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
    if (![sortField isEqualToString:@"relevance"] && [sortField length] > 0 && allowedSorts[sortField] == nil) {
      if (error != NULL) {
        *error = STError(ALNSearchModuleErrorValidationFailed,
                         [NSString stringWithFormat:@"unsupported sort %@", sortField],
                         @{ @"field" : sortField ?: @"" });
      }
      return nil;
    }

    NSDictionary *effectiveFilters = [self effectiveFilters:filters metadata:metadata options:options];
    for (NSDictionary *document in documents) {
      if (![self document:document matchesFilters:effectiveFilters metadata:metadata error:error]) {
        if (error != NULL && *error != NULL) {
          return nil;
        }
        continue;
      }
      [candidateDocuments addObject:document];
      NSDictionary *ranked = [self rankedMatchForDocument:document
                                                 metadata:metadata
                                               generation:snapshot[@"generation"]
                                                    query:normalizedQuery
                                                     mode:queryMode];
      if (ranked == nil && [normalizedQuery length] > 0) {
        continue;
      }
      if (ranked != nil) {
        [matches addObject:ranked];
      } else {
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:document];
        result[@"resourceLabel"] = metadata[@"label"] ?: STTitleCaseIdentifier(identifier);
        result[@"score"] = @0;
        result[@"scoreValue"] = @0.0;
        result[@"generation"] = snapshot[@"generation"] ?: @0;
        result[@"highlights"] = @[];
        [matches addObject:result];
      }
    }
  }

  NSArray *orderedMatches = [self sortedMatches:matches
                                           sort:normalizedSort
                                      queryMode:STLowerTrimmedString(options[@"mode"])
                                  queryProvided:([normalizedQuery length] > 0)];
  NSUInteger start = MIN(offset, [orderedMatches count]);
  NSUInteger sliceLength = MIN((limit > 0 ? limit : 25U), ([orderedMatches count] - start));
  NSArray *page = [orderedMatches subarrayWithRange:NSMakeRange(start, sliceLength)];

  NSMutableOrderedSet<NSString *> *autocomplete = [NSMutableOrderedSet orderedSet];
  NSMutableOrderedSet<NSString *> *suggestions = [NSMutableOrderedSet orderedSet];
  for (NSDictionary *metadata in STNormalizeArray(resourceMetadata)) {
    NSArray *values = [self autocompleteSuggestionsForDocuments:candidateDocuments
                                                       metadata:metadata
                                                          query:normalizedQuery
                                                          limit:autocompleteLimit];
    for (NSString *value in values) {
      [autocomplete addObject:value];
      if ([autocomplete count] >= autocompleteLimit) {
        break;
      }
    }
    NSArray *suggested = [self suggestedTermsForDocuments:candidateDocuments
                                                 metadata:metadata
                                                    query:normalizedQuery
                                                    limit:suggestionsLimit];
    for (NSString *value in suggested) {
      [suggestions addObject:value];
      if ([suggestions count] >= suggestionsLimit) {
        break;
      }
    }
  }

  return @{
    @"query" : normalizedQuery ?: @"",
    @"mode" : STLowerTrimmedString(options[@"mode"]).length > 0 ? STLowerTrimmedString(options[@"mode"]) : @"search",
    @"availableModes" : [availableModes array] ?: @[ @"search" ],
    @"results" : page ?: @[],
    @"matchedDocuments" : orderedMatches ?: @[],
    @"autocomplete" : [autocomplete array] ?: @[],
    @"suggestions" : [suggestions array] ?: @[],
    @"total" : @([orderedMatches count]),
    @"limit" : @(limit > 0 ? limit : 25U),
    @"offset" : @(offset),
    @"debug" : @{
      @"adapter" : @"default",
      @"candidateDocuments" : @([candidateDocuments count]),
      @"matchedDocuments" : @([orderedMatches count]),
    },
  };
}

- (NSDictionary *)searchModuleCapabilities {
  return @{
    @"engine" : @"default",
    @"supportsHighlights" : @YES,
    @"supportsIncrementalSync" : @YES,
    @"supportsGenerations" : @YES,
    @"supportsAutocomplete" : @YES,
    @"supportsSuggestions" : @YES,
    @"supportsFacets" : @YES,
    @"supportsPromotedResults" : @YES,
    @"supportsFullTextRanking" : @NO,
    @"supportsFuzzyMatching" : @YES,
    @"supportsTypedFilters" : @YES,
    @"supportsCursorPagination" : @NO,
    @"supportsSoftDeleteFilters" : @NO,
    @"supportsTenantScoping" : @NO,
    @"supportsPhraseSearch" : @YES,
    @"supportsBooleanSearch" : @NO,
    @"queryModes" : @[ @"search", @"phrase", @"fuzzy", @"autocomplete" ],
  };
}

@end

@interface ALNPostgresSearchEngine ()

@property(nonatomic, strong) ALNPg *database;
@property(nonatomic, copy) NSString *tableName;
@property(nonatomic, copy) NSString *textSearchConfiguration;

- (BOOL)ensureSchemaWithError:(NSError **)error;
- (BOOL)writeDocument:(nullable NSDictionary *)document
    resourceIdentifier:(NSString *)resourceIdentifier
            generation:(NSUInteger)generation
             operation:(NSString *)operation
                 error:(NSError **)error;

@end

@implementation ALNPostgresSearchEngine

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _tableName = @"search_module_documents";
    _textSearchConfiguration = @"simple";
  }
  return self;
}

- (NSString *)validatedSQLIdentifier:(NSString *)value defaultValue:(NSString *)defaultValue {
  NSString *candidate = STTrimmedString(value);
  if ([candidate length] == 0) {
    candidate = defaultValue ?: @"search_module_documents";
  }
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
  for (NSUInteger index = 0; index < [candidate length]; index++) {
    if (![allowed characterIsMember:[candidate characterAtIndex:index]]) {
      return defaultValue ?: @"search_module_documents";
    }
  }
  return candidate;
}

- (NSString *)validatedTextSearchConfiguration:(NSString *)value {
  NSString *candidate = STLowerTrimmedString(value);
  if ([candidate length] == 0) {
    return @"simple";
  }
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"];
  for (NSUInteger index = 0; index < [candidate length]; index++) {
    if (![allowed characterIsMember:[candidate characterAtIndex:index]]) {
      return @"simple";
    }
  }
  return candidate;
}

- (BOOL)searchModuleConfigureWithRuntime:(ALNSearchModuleRuntime *)runtime
                             application:(ALNApplication *)application
                              moduleConfig:(NSDictionary *)moduleConfig
                                   error:(NSError **)error {
  (void)runtime;
  NSDictionary *engineConfig = [moduleConfig[@"engine"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"engine"] : @{};
  NSDictionary *postgres = [engineConfig[@"postgres"] isKindOfClass:[NSDictionary class]] ? engineConfig[@"postgres"] : @{};
  NSString *connectionString = STTrimmedString(postgres[@"connectionString"]);
  if ([connectionString length] == 0) {
    NSDictionary *database = [application.config[@"database"] isKindOfClass:[NSDictionary class]] ? application.config[@"database"] : @{};
    connectionString = STTrimmedString(database[@"connectionString"]);
  }
  if ([connectionString length] == 0) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorInvalidConfiguration,
                       @"ALNPostgresSearchEngine requires searchModule.engine.postgres.connectionString or database.connectionString",
                       nil);
    }
    return NO;
  }
  NSUInteger maxConnections = [postgres[@"maxConnections"] respondsToSelector:@selector(unsignedIntegerValue)]
                                  ? MAX((NSUInteger)1U, [postgres[@"maxConnections"] unsignedIntegerValue])
                                  : 2U;
  NSError *dbError = nil;
  self.database = [[ALNPg alloc] initWithConnectionString:connectionString maxConnections:maxConnections error:&dbError];
  if (self.database == nil) {
    if (error != NULL) {
      *error = dbError ?: STError(ALNSearchModuleErrorInvalidConfiguration, @"failed to initialize PostgreSQL search engine", nil);
    }
    return NO;
  }
  self.tableName = [self validatedSQLIdentifier:postgres[@"tableName"] defaultValue:@"search_module_documents"];
  self.textSearchConfiguration = [self validatedTextSearchConfiguration:postgres[@"textSearchConfiguration"]];
  return [self ensureSchemaWithError:error];
}

- (BOOL)ensureSchemaWithError:(NSError **)error {
  if (self.database == nil) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorInvalidConfiguration, @"PostgreSQL search engine is not configured", nil);
    }
    return NO;
  }
  NSString *createExtension = @"CREATE EXTENSION IF NOT EXISTS pg_trgm";
  NSString *createTable = [NSString stringWithFormat:
      @"CREATE TABLE IF NOT EXISTS %@ ("
       "resource_identifier TEXT NOT NULL, "
       "generation BIGINT NOT NULL, "
       "record_id TEXT NOT NULL, "
       "title TEXT NOT NULL, "
       "summary TEXT NOT NULL, "
       "searchable_text TEXT NOT NULL, "
       "autocomplete_text TEXT NOT NULL DEFAULT '', "
       "field_text_json JSONB NOT NULL DEFAULT '{}'::jsonb, "
       "record_json JSONB NOT NULL DEFAULT '{}'::jsonb, "
       "PRIMARY KEY (resource_identifier, generation, record_id))",
      self.tableName];
  NSString *ftsIndex = [NSString stringWithFormat:
      @"CREATE INDEX IF NOT EXISTS %@_fts_idx ON %@ USING GIN (to_tsvector('%@', searchable_text))",
      self.tableName,
      self.tableName,
      self.textSearchConfiguration];
  NSString *trgmIndex = [NSString stringWithFormat:
      @"CREATE INDEX IF NOT EXISTS %@_trgm_idx ON %@ USING GIN (searchable_text gin_trgm_ops)",
      self.tableName,
      self.tableName];
  NSString *autocompleteIndex = [NSString stringWithFormat:
      @"CREATE INDEX IF NOT EXISTS %@_autocomplete_idx ON %@ USING GIN (autocomplete_text gin_trgm_ops)",
      self.tableName,
      self.tableName];
  for (NSString *sql in @[ createExtension, createTable, ftsIndex, trgmIndex, autocompleteIndex ]) {
    if ([self.database executeCommand:sql parameters:@[] error:error] < 0) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)writeDocument:(NSDictionary *)document
    resourceIdentifier:(NSString *)resourceIdentifier
            generation:(NSUInteger)generation
             operation:(NSString *)operation
                 error:(NSError **)error {
  if (![self ensureSchemaWithError:error]) {
    return NO;
  }
  NSString *recordID = STTrimmedString(document[@"recordID"]);
  if ([recordID length] == 0) {
    return YES;
  }
  NSString *deleteSQL = [NSString stringWithFormat:@"DELETE FROM %@ WHERE resource_identifier = $1 AND generation = $2 AND record_id = $3",
                                                   self.tableName];
  if ([self.database executeCommand:deleteSQL
                         parameters:@[ resourceIdentifier ?: @"", @(generation), recordID ]
                              error:error] < 0) {
    return NO;
  }
  if ([[STLowerTrimmedString(operation) lowercaseString] isEqualToString:@"delete"]) {
    return YES;
  }
  NSString *insertSQL = [NSString stringWithFormat:
      @"INSERT INTO %@ "
       "(resource_identifier, generation, record_id, title, summary, searchable_text, autocomplete_text, field_text_json, record_json) "
       "VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9::jsonb)",
      self.tableName];
  NSArray *parameters = @[
    resourceIdentifier ?: @"",
    @(generation),
    recordID,
    STStringifyValue(document[@"title"]),
    STStringifyValue(document[@"summary"]),
    STStringifyValue(document[@"searchableText"]),
    STStringifyValue(document[@"autocompleteText"]),
    ALNDatabaseJSONParameter(STNormalizeDictionary(document[@"fieldText"])),
    ALNDatabaseJSONParameter(STNormalizeDictionary(document[@"record"])),
  ];
  return ([self.database executeCommand:insertSQL parameters:parameters error:error] >= 0);
}

- (nullable NSDictionary *)searchModuleSnapshotForMetadata:(NSDictionary *)metadata
                                                   records:(NSArray<NSDictionary *> *)records
                                                generation:(NSUInteger)generation
                                                     error:(NSError **)error {
  id state = [self searchModuleBeginBuildForMetadata:metadata generation:generation error:error];
  if (state == nil) {
    return nil;
  }
  if (![self searchModuleAppendBuildRecords:records metadata:metadata state:state error:error]) {
    return nil;
  }
  return [self searchModuleFinalizeBuildState:state metadata:metadata error:error];
}

- (nullable NSDictionary *)searchModuleFinalizeBuildState:(id)state
                                                 metadata:(NSDictionary *)metadata
                                                    error:(NSError **)error {
  NSDictionary *snapshot = [super searchModuleFinalizeBuildState:state metadata:metadata error:error];
  if (snapshot == nil) {
    return nil;
  }
  NSString *resourceIdentifier = STLowerTrimmedString(metadata[@"identifier"]);
  NSArray *documents = STNormalizeArray(snapshot[@"documents"]);
  NSNumber *resolvedGeneration = [snapshot[@"generation"] respondsToSelector:@selector(unsignedIntegerValue)]
                                     ? snapshot[@"generation"]
                                     : @1;
  if (![self ensureSchemaWithError:error]) {
    return nil;
  }
  if (![self.database withTransaction:^BOOL(ALNPgConnection *connection, NSError **txError) {
        NSString *deleteSQL = [NSString stringWithFormat:@"DELETE FROM %@ WHERE resource_identifier = $1 AND generation = $2",
                                                         self.tableName];
        if ([connection executeCommand:deleteSQL parameters:@[ resourceIdentifier ?: @"", resolvedGeneration ] error:txError] < 0) {
          return NO;
        }
        NSString *insertSQL = [NSString stringWithFormat:
            @"INSERT INTO %@ "
             "(resource_identifier, generation, record_id, title, summary, searchable_text, autocomplete_text, field_text_json, record_json) "
             "VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9::jsonb)",
            self.tableName];
        NSMutableArray<NSArray *> *parameterSets = [NSMutableArray array];
        for (NSDictionary *document in documents) {
          [parameterSets addObject:@[
            resourceIdentifier ?: @"",
            resolvedGeneration,
            STTrimmedString(document[@"recordID"]),
            STStringifyValue(document[@"title"]),
            STStringifyValue(document[@"summary"]),
            STStringifyValue(document[@"searchableText"]),
            STStringifyValue(document[@"autocompleteText"]),
            ALNDatabaseJSONParameter(STNormalizeDictionary(document[@"fieldText"])),
            ALNDatabaseJSONParameter(STNormalizeDictionary(document[@"record"])),
          ]];
        }
        if ([parameterSets count] > 0 &&
            [connection executeCommandBatch:insertSQL parameterSets:parameterSets error:txError] < 0) {
          return NO;
        }
        NSString *pruneSQL = [NSString stringWithFormat:@"DELETE FROM %@ WHERE resource_identifier = $1 AND generation <> $2",
                                                        self.tableName];
        if ([connection executeCommand:pruneSQL parameters:@[ resourceIdentifier ?: @"", resolvedGeneration ] error:txError] < 0) {
          return NO;
        }
        return YES;
      }
                                   error:error]) {
    return nil;
  }
  return snapshot;
}

- (nullable NSDictionary *)searchModuleApplyOperation:(NSString *)operation
                                               record:(NSDictionary *)record
                                             metadata:(NSDictionary *)metadata
                                      existingSnapshot:(NSDictionary *)snapshot
                                                error:(NSError **)error {
  NSDictionary *updated = [super searchModuleApplyOperation:operation record:record metadata:metadata existingSnapshot:snapshot error:error];
  if (updated == nil) {
    return nil;
  }
  NSString *resourceIdentifier = STLowerTrimmedString(metadata[@"identifier"]);
  NSString *normalizedOperation = STLowerTrimmedString(operation);
  NSDictionary *document = nil;
  if (![normalizedOperation isEqualToString:@"delete"]) {
    document = [self normalizedDocumentForRecord:record metadata:metadata];
  } else {
    document = @{
      @"recordID" : STTrimmedString(record[metadata[@"identifierField"] ?: @"id"]) ?: STTrimmedString(record[@"recordID"]),
    };
  }
  if (![self writeDocument:document
        resourceIdentifier:resourceIdentifier
                generation:[updated[@"generation"] unsignedIntegerValue]
                 operation:normalizedOperation
                     error:error]) {
    return nil;
  }
  return updated;
}

- (nullable NSDictionary *)searchModuleExecuteQuery:(NSString *)query
                                     resourceMetadata:(NSArray<NSDictionary *> *)resourceMetadata
                                  snapshotsByResource:(NSDictionary<NSString *, NSDictionary *> *)snapshotsByResource
                                              filters:(NSDictionary *)filters
                                                 sort:(NSString *)sort
                                                limit:(NSUInteger)limit
                                               offset:(NSUInteger)offset
                                              options:(NSDictionary *)options
                                                error:(NSError **)error {
  if ([STTrimmedString(query) length] == 0 || self.database == nil) {
    return [super searchModuleExecuteQuery:query
                           resourceMetadata:resourceMetadata
                        snapshotsByResource:snapshotsByResource
                                    filters:filters
                                       sort:sort
                                      limit:limit
                                     offset:offset
                                    options:options
                                      error:error];
  }
  NSMutableArray *matches = [NSMutableArray array];
  NSMutableOrderedSet<NSString *> *availableModes = [NSMutableOrderedSet orderedSet];
  NSString *normalizedQuery = STTrimmedString(query);
  NSString *normalizedSort = STLowerTrimmedString(sort);
  for (NSDictionary *metadata in STNormalizeArray(resourceMetadata)) {
    NSString *identifier = STLowerTrimmedString(metadata[@"identifier"]);
    NSDictionary *snapshot = STNormalizeDictionary(snapshotsByResource[identifier]);
    NSArray *documents = STNormalizeArray(snapshot[@"documents"]);
    NSNumber *generation = [snapshot[@"generation"] respondsToSelector:@selector(unsignedIntegerValue)] ? snapshot[@"generation"] : @0;
    if ([documents count] == 0 || [generation unsignedIntegerValue] == 0U) {
      continue;
    }
    NSString *queryMode = [self normalizedQueryModeFromOptions:options metadata:metadata];
    for (NSString *mode in [self availableQueryModesForMetadata:metadata]) {
      [availableModes addObject:mode];
    }
    NSMutableDictionary *documentsByRecordID = [NSMutableDictionary dictionary];
    for (NSDictionary *document in documents) {
      NSString *recordID = STTrimmedString(document[@"recordID"]);
      if ([recordID length] > 0) {
        documentsByRecordID[recordID] = document;
      }
    }

    NSString *sql = @"";
    NSMutableArray *parameters = [NSMutableArray arrayWithArray:@[ identifier ?: @"", generation, normalizedQuery ?: @"" ]];
    if ([queryMode isEqualToString:@"phrase"]) {
      sql = [NSString stringWithFormat:
          @"SELECT record_id, "
           "ts_rank_cd(to_tsvector('%@', searchable_text), phraseto_tsquery('%@', $3)) AS score, "
           "ts_headline('%@', searchable_text, phraseto_tsquery('%@', $3)) AS highlight "
           "FROM %@ "
           "WHERE resource_identifier = $1 AND generation = $2 "
           "AND to_tsvector('%@', searchable_text) @@ phraseto_tsquery('%@', $3) "
           "ORDER BY score DESC, record_id ASC",
          self.textSearchConfiguration,
          self.textSearchConfiguration,
          self.textSearchConfiguration,
          self.textSearchConfiguration,
          self.tableName,
          self.textSearchConfiguration,
          self.textSearchConfiguration];
    } else if ([queryMode isEqualToString:@"fuzzy"]) {
      sql = [NSString stringWithFormat:
          @"SELECT record_id, "
           "GREATEST(ts_rank_cd(to_tsvector('%@', searchable_text), plainto_tsquery('%@', $3)), similarity(searchable_text, $3)) AS score, "
           "CASE WHEN searchable_text ILIKE ('%%' || $3 || '%%') "
           "THEN regexp_replace(searchable_text, '(' || regexp_replace($3, '([\\\\.\\\\[\\\\]\\\\(\\\\)\\\\?\\\\+\\\\*\\\\^\\\\$\\\\|])', '\\\\\\\\\\1', 'g') || ')', '<b>\\\\1</b>', 'i') "
           "ELSE searchable_text END AS highlight "
           "FROM %@ "
           "WHERE resource_identifier = $1 AND generation = $2 "
           "AND (searchable_text %% $3 OR to_tsvector('%@', searchable_text) @@ plainto_tsquery('%@', $3)) "
           "ORDER BY score DESC, record_id ASC",
          self.textSearchConfiguration,
          self.textSearchConfiguration,
          self.tableName,
          self.textSearchConfiguration,
          self.textSearchConfiguration];
    } else if ([queryMode isEqualToString:@"autocomplete"]) {
      [parameters addObject:[NSString stringWithFormat:@"%@%%", normalizedQuery ?: @""]];
      sql = [NSString stringWithFormat:
          @"SELECT record_id, "
           "CASE WHEN lower(autocomplete_text) LIKE lower($4) THEN 1.0 ELSE similarity(autocomplete_text, $3) END AS score, "
           "autocomplete_text AS highlight "
           "FROM %@ "
           "WHERE resource_identifier = $1 AND generation = $2 "
           "AND (lower(autocomplete_text) LIKE lower($4) OR autocomplete_text %% $3) "
           "ORDER BY score DESC, record_id ASC",
          self.tableName];
    } else {
      sql = [NSString stringWithFormat:
          @"SELECT record_id, "
           "ts_rank_cd(to_tsvector('%@', searchable_text), plainto_tsquery('%@', $3)) AS score, "
           "ts_headline('%@', searchable_text, plainto_tsquery('%@', $3)) AS highlight "
           "FROM %@ "
           "WHERE resource_identifier = $1 AND generation = $2 "
           "AND to_tsvector('%@', searchable_text) @@ plainto_tsquery('%@', $3) "
           "ORDER BY score DESC, record_id ASC",
          self.textSearchConfiguration,
          self.textSearchConfiguration,
          self.textSearchConfiguration,
          self.textSearchConfiguration,
          self.tableName,
          self.textSearchConfiguration,
          self.textSearchConfiguration];
    }
    NSArray<NSDictionary *> *rows = [self.database executeQuery:sql parameters:parameters error:error];
    if (rows == nil) {
      return nil;
    }
    for (NSDictionary *row in rows) {
      NSDictionary *document = documentsByRecordID[STTrimmedString(row[@"record_id"])];
      if (document == nil) {
        continue;
      }
      if (![self document:document matchesFilters:filters ?: @{} metadata:metadata error:error]) {
        if (error != NULL && *error != NULL) {
          return nil;
        }
        continue;
      }
      NSMutableDictionary *ranked = [NSMutableDictionary dictionaryWithDictionary:document];
      ranked[@"resourceLabel"] = metadata[@"label"] ?: STTitleCaseIdentifier(identifier);
      double score = [row[@"score"] respondsToSelector:@selector(doubleValue)] ? [row[@"score"] doubleValue] * 100.0 : 0.0;
      ranked[@"score"] = @((NSInteger)llround(score));
      ranked[@"scoreValue"] = @(score);
      ranked[@"generation"] = generation ?: @0;
      NSString *highlight = STTrimmedString(row[@"highlight"]);
      ranked[@"highlights"] = ([highlight length] > 0) ? @[ highlight ] : @[];
      [matches addObject:ranked];
    }
  }
  NSArray *orderedMatches = [self sortedMatches:matches
                                           sort:normalizedSort
                                      queryMode:STLowerTrimmedString(options[@"mode"])
                                  queryProvided:([normalizedQuery length] > 0)];
  NSUInteger start = MIN(offset, [orderedMatches count]);
  NSUInteger sliceLength = MIN((limit > 0 ? limit : 25U), ([orderedMatches count] - start));
  NSArray *page = [orderedMatches subarrayWithRange:NSMakeRange(start, sliceLength)];
  NSMutableOrderedSet<NSString *> *autocomplete = [NSMutableOrderedSet orderedSet];
  NSMutableOrderedSet<NSString *> *suggestions = [NSMutableOrderedSet orderedSet];
  for (NSDictionary *metadata in STNormalizeArray(resourceMetadata)) {
    for (NSString *value in [self autocompleteSuggestionsForDocuments:orderedMatches
                                                             metadata:metadata
                                                                query:normalizedQuery
                                                                limit:5U]) {
      [autocomplete addObject:value];
    }
    for (NSString *value in [self suggestedTermsForDocuments:orderedMatches
                                                    metadata:metadata
                                                       query:normalizedQuery
                                                       limit:3U]) {
      [suggestions addObject:value];
    }
  }
  return @{
    @"query" : normalizedQuery ?: @"",
    @"mode" : STLowerTrimmedString(options[@"mode"]).length > 0 ? STLowerTrimmedString(options[@"mode"]) : @"search",
    @"availableModes" : [availableModes array] ?: @[ @"search" ],
    @"results" : page ?: @[],
    @"matchedDocuments" : orderedMatches ?: @[],
    @"autocomplete" : [autocomplete array] ?: @[],
    @"suggestions" : [suggestions array] ?: @[],
    @"total" : @([orderedMatches count]),
    @"limit" : @(limit > 0 ? limit : 25U),
    @"offset" : @(offset),
    @"debug" : @{
      @"adapter" : @"postgres",
      @"matchedDocuments" : @([orderedMatches count]),
      @"tableName" : self.tableName ?: @"",
      @"textSearchConfiguration" : self.textSearchConfiguration ?: @"simple",
    },
  };
}

- (NSDictionary *)searchModuleCapabilities {
  NSMutableDictionary *capabilities = [NSMutableDictionary dictionaryWithDictionary:[super searchModuleCapabilities]];
  capabilities[@"engine"] = @"postgres";
  capabilities[@"supportsFullTextRanking"] = @YES;
  capabilities[@"supportsFuzzyMatching"] = @YES;
  capabilities[@"supportsAutocomplete"] = @YES;
  capabilities[@"supportsPhraseSearch"] = @YES;
  return capabilities;
}

@end

@implementation ALNExternalSearchEngine

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _moduleConfig = @{};
    _engineConfig = @{};
    _fixturePayload = @{};
    _serviceURL = @"";
    _apiKey = @"";
    _liveRequestsEnabled = NO;
    _chunkSize = 250U;
  }
  return self;
}

- (NSString *)engineConfigKey {
  return @"external";
}

- (NSString *)externalEngineName {
  return @"external";
}

- (NSDictionary *)externalCapabilities {
  return @{
    @"supportsCursorPagination" : @YES,
    @"supportsTenantScoping" : @YES,
    @"supportsSoftDeleteFilters" : @YES,
  };
}

- (NSString *)externalIndexNameForMetadata:(NSDictionary *)metadata {
  NSString *prefix = STLowerTrimmedString(self.engineConfig[@"indexPrefix"]);
  if ([prefix length] == 0) {
    prefix = [self externalEngineName];
  }
  NSString *identifier = STLowerTrimmedString(metadata[@"identifier"]);
  return [NSString stringWithFormat:@"%@_%@", prefix ?: [self externalEngineName], identifier ?: @"resource"];
}

- (NSDictionary *)externalIndexDescriptorForMetadata:(NSDictionary *)metadata {
  NSMutableDictionary *descriptor = [NSMutableDictionary dictionaryWithDictionary:STNormalizeDictionary(metadata[@"engineDescriptor"])];
  descriptor[@"adapter"] = [self externalEngineName];
  descriptor[@"indexName"] = [self externalIndexNameForMetadata:metadata];
  descriptor[@"serviceURL"] = self.serviceURL ?: @"";
  descriptor[@"chunkSize"] = @(self.chunkSize);
  return descriptor;
}

- (NSString *)searchPathForIndexName:(NSString *)indexName {
  (void)indexName;
  return @"";
}

- (nullable NSDictionary *)fixtureResponseForOperation:(NSString *)operation
                                            resourceID:(NSString *)resourceID
                                                 query:(NSString *)query
                                               options:(NSDictionary *)options {
  (void)options;
  NSDictionary *operationPayload = STNormalizeDictionary(self.fixturePayload[STLowerTrimmedString(operation)]);
  NSDictionary *resourcePayload = STNormalizeDictionary(operationPayload[STLowerTrimmedString(resourceID)]);
  NSString *normalizedQuery = STLowerTrimmedString(query);
  NSDictionary *queryPayload = STNormalizeDictionary(resourcePayload[normalizedQuery]);
  if ([queryPayload count] > 0) {
    return queryPayload;
  }
  queryPayload = STNormalizeDictionary(resourcePayload[@"*"]);
  if ([queryPayload count] > 0) {
    return queryPayload;
  }
  resourcePayload = STNormalizeDictionary(operationPayload[@"*"]);
  queryPayload = STNormalizeDictionary(resourcePayload[normalizedQuery]);
  if ([queryPayload count] > 0) {
    return queryPayload;
  }
  return STNormalizeDictionary(resourcePayload[@"*"]);
}

- (NSDictionary *)normalizedExternalResponse:(NSDictionary *)response
                            resourceMetadata:(NSDictionary *)metadata {
  NSMutableArray *hits = [NSMutableArray array];
  NSArray *rawHits = STNormalizeArray(response[@"hits"]);
  NSString *identifierField = STLowerTrimmedString(metadata[@"identifierField"]);
  if ([identifierField length] == 0) {
    identifierField = @"recordid";
  }
  for (NSDictionary *entry in rawHits) {
    NSString *recordID = STTrimmedString(entry[@"recordID"]);
    if ([recordID length] == 0) {
      recordID = STTrimmedString(entry[@"id"]);
    }
    if ([recordID length] == 0) {
      recordID = STTrimmedString(entry[identifierField]);
    }
    if ([recordID length] == 0) {
      continue;
    }
    NSMutableDictionary *hit = [NSMutableDictionary dictionaryWithDictionary:entry];
    hit[@"recordID"] = recordID;
    [hits addObject:hit];
  }
  NSArray *order = STTrimmedUniqueStringArray(response[@"order"]);
  return @{
    @"hits" : hits ?: @[],
    @"order" : order ?: @[],
    @"autocomplete" : STNormalizeArray(response[@"autocomplete"]),
    @"suggestions" : STNormalizeArray(response[@"suggestions"]),
    @"facets" : STNormalizeArray(response[@"facets"]),
    @"facetDistribution" : STNormalizeDictionary(response[@"facetDistribution"]),
    @"total" : [response[@"total"] respondsToSelector:@selector(unsignedIntegerValue)] ? response[@"total"] : @([hits count]),
    @"debug" : STNormalizeDictionary(response[@"debug"]),
    @"source" : ([STTrimmedString(response[@"source"]) length] > 0) ? STTrimmedString(response[@"source"]) : @"fixture",
  };
}

- (NSDictionary<NSString *, NSDictionary *> *)filterMetadataByFieldForMetadata:(NSDictionary *)metadata {
  NSMutableDictionary<NSString *, NSDictionary *> *byField = [NSMutableDictionary dictionary];
  for (NSDictionary *entry in STNormalizeArray(metadata[@"filters"])) {
    NSString *field = STLowerTrimmedString(entry[@"name"]);
    if ([field length] == 0) {
      continue;
    }
    byField[field] = entry;
  }
  return byField;
}

- (NSString *)fieldTypeForField:(NSString *)field metadata:(NSDictionary *)metadata {
  NSDictionary *fieldTypes = STNormalizeDictionary(metadata[@"fieldTypes"]);
  NSString *resolved = STLowerTrimmedString(fieldTypes[STLowerTrimmedString(field)]);
  return ([resolved length] > 0) ? resolved : @"string";
}

- (NSArray<NSString *> *)queryFieldsForMetadata:(NSDictionary *)metadata autocomplete:(BOOL)autocomplete {
  NSArray *fields = autocomplete ? [self autocompleteFieldsForMetadata:metadata] : [self searchFieldsForMetadata:metadata];
  return ([fields count] > 0) ? fields : @[ STLowerTrimmedString(metadata[@"primaryField"]) ?: @"id" ];
}

- (id)liveDocumentPayloadForDocument:(NSDictionary *)document metadata:(NSDictionary *)metadata {
  NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:STNormalizeDictionary(document[@"record"])];
  NSString *recordID = STTrimmedString(document[@"recordID"]);
  NSString *identifierField = STLowerTrimmedString(metadata[@"identifierField"]);
  if ([identifierField length] == 0) {
    identifierField = @"id";
  }
  if ([recordID length] > 0) {
    payload[@"recordID"] = recordID;
    if ([STTrimmedString(payload[identifierField]) length] == 0) {
      payload[identifierField] = recordID;
    }
  }
  payload[@"resource"] = STLowerTrimmedString(metadata[@"identifier"]);
  payload[@"title"] = STStringifyValue(document[@"title"]);
  payload[@"summary"] = STStringifyValue(document[@"summary"]);
  payload[@"searchableText"] = STStringifyValue(document[@"searchableText"]);
  payload[@"autocompleteText"] = STStringifyValue(document[@"autocompleteText"]);
  return STPropertyListValue(payload);
}

- (nullable NSDictionary *)validatedHTTPResponse:(NSDictionary *)response
                                 allowNotFound:(BOOL)allowNotFound
                                       message:(NSString *)message
                                          path:(NSString *)path
                                         error:(NSError **)error {
  NSInteger statusCode = [response[@"status"] respondsToSelector:@selector(integerValue)] ? [response[@"status"] integerValue] : 0;
  if (STHTTPStatusIsSuccess(statusCode) || (allowNotFound && statusCode == 404)) {
    return response ?: @{};
  }
  NSString *bodyMessage = @"";
  id body = response[@"body"];
  if ([body isKindOfClass:[NSDictionary class]]) {
    bodyMessage = STTrimmedString(body[@"message"]);
    if ([bodyMessage length] == 0) {
      bodyMessage = STTrimmedString(body[@"error"]);
    }
  } else {
    bodyMessage = STTrimmedString(body);
  }
  if (error != NULL) {
    *error = STError(ALNSearchModuleErrorExecutionFailed,
                     ([bodyMessage length] > 0) ? bodyMessage : (message ?: @"search engine request failed"),
                     @{
                       @"engine" : [self externalEngineName] ?: @"external",
                       @"path" : STTrimmedString(path),
                       @"status" : @(statusCode),
                     });
  }
  return nil;
}

- (nullable NSDictionary *)jsonRequestWithMethod:(NSString *)method
                                            path:(NSString *)path
                                         headers:(NSDictionary *)headers
                                            body:(id)body
                                   allowNotFound:(BOOL)allowNotFound
                                         message:(NSString *)message
                                           error:(NSError **)error {
  NSDictionary *response = STHTTPJSONRequest(method, path, headers, body, error);
  if (response == nil) {
    return nil;
  }
  return [self validatedHTTPResponse:response allowNotFound:allowNotFound message:message path:path error:error];
}

- (nullable NSDictionary *)dataRequestWithMethod:(NSString *)method
                                            path:(NSString *)path
                                         headers:(NSDictionary *)headers
                                            body:(NSData *)body
                                   allowNotFound:(BOOL)allowNotFound
                                         message:(NSString *)message
                                           error:(NSError **)error {
  NSDictionary *response = STHTTPDataRequest(method, path, headers, body, error);
  if (response == nil) {
    return nil;
  }
  return [self validatedHTTPResponse:response allowNotFound:allowNotFound message:message path:path error:error];
}

- (NSArray<NSDictionary *> *)facetSummariesFromBuckets:(NSDictionary<NSString *, NSDictionary *> *)buckets
                                              metadata:(NSDictionary *)metadata
                                               filters:(NSDictionary *)filters {
  NSMutableArray<NSDictionary *> *summaries = [NSMutableArray array];
  for (NSDictionary *facet in STNormalizeArray(metadata[@"facetFields"])) {
    NSString *fieldName = STLowerTrimmedString(facet[@"name"]);
    NSDictionary *bucketCounts = [buckets[fieldName] isKindOfClass:[NSDictionary class]] ? buckets[fieldName] : @{};
    if ([fieldName length] == 0 || [bucketCounts count] == 0) {
      continue;
    }
    NSMutableDictionary<NSString *, NSString *> *labels = [NSMutableDictionary dictionary];
    for (NSDictionary *choice in STNormalizeArray(facet[@"choices"])) {
      NSString *value = STTrimmedString(choice[@"value"]);
      if ([value length] > 0) {
        labels[value] = ([STTrimmedString(choice[@"label"]) length] > 0) ? STTrimmedString(choice[@"label"]) : value;
      }
    }
    NSMutableSet<NSString *> *selectedValues = [NSMutableSet set];
    for (NSString *filterKey in @[ fieldName, [NSString stringWithFormat:@"%@__in", fieldName] ]) {
      id raw = filters[filterKey];
      if ([raw isKindOfClass:[NSArray class]]) {
        for (NSString *value in STTrimmedUniqueStringArray(raw)) {
          [selectedValues addObject:value];
        }
      } else {
        for (NSString *value in STTrimmedUniqueStringArray([STTrimmedString(raw) componentsSeparatedByString:@","])) {
          [selectedValues addObject:value];
        }
      }
    }
    NSArray<NSString *> *values = [[bucketCounts allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *lhs, NSString *rhs) {
      NSInteger left = [bucketCounts[lhs] integerValue];
      NSInteger right = [bucketCounts[rhs] integerValue];
      if (left != right) {
        return (left > right) ? NSOrderedAscending : NSOrderedDescending;
      }
      return [lhs compare:rhs];
    }];
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (NSString *value in values) {
      [entries addObject:@{
        @"value" : value,
        @"label" : labels[value] ?: value,
        @"count" : bucketCounts[value] ?: @0,
        @"selected" : @([selectedValues containsObject:value]),
      }];
    }
    [summaries addObject:@{
      @"resource" : STLowerTrimmedString(metadata[@"identifier"]),
      @"resourceLabel" : metadata[@"label"] ?: STTitleCaseIdentifier(metadata[@"identifier"]),
      @"name" : fieldName,
      @"label" : ([STTrimmedString(facet[@"label"]) length] > 0) ? STTrimmedString(facet[@"label"]) : STTitleCaseIdentifier(fieldName),
      @"type" : ([STLowerTrimmedString(facet[@"type"]) length] > 0) ? STLowerTrimmedString(facet[@"type"]) : @"string",
      @"values" : entries ?: @[],
      @"totalValues" : @([bucketCounts count]),
    }];
  }
  return summaries;
}

- (BOOL)searchModuleConfigureWithRuntime:(ALNSearchModuleRuntime *)runtime
                             application:(ALNApplication *)application
                              moduleConfig:(NSDictionary *)moduleConfig
                                   error:(NSError **)error {
  self.runtime = runtime;
  self.application = application;
  self.moduleConfig = STNormalizeDictionary(moduleConfig);
  NSDictionary *engineRoot = [moduleConfig[@"engine"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"engine"] : @{};
  self.engineConfig = STNormalizeDictionary(engineRoot[[self engineConfigKey]]);
  self.serviceURL = STTrimmedString(self.engineConfig[@"serviceURL"]);
  if ([self.serviceURL length] == 0) {
    self.serviceURL = STTrimmedString(self.engineConfig[@"baseURL"]);
  }
  self.apiKey = STTrimmedString(self.engineConfig[@"apiKey"]);
  self.chunkSize = [self.engineConfig[@"chunkSize"] respondsToSelector:@selector(unsignedIntegerValue)]
                       ? MAX((NSUInteger)1U, [self.engineConfig[@"chunkSize"] unsignedIntegerValue])
                       : ([self.engineConfig[@"bulkBatchSize"] respondsToSelector:@selector(unsignedIntegerValue)]
                              ? MAX((NSUInteger)1U, [self.engineConfig[@"bulkBatchSize"] unsignedIntegerValue])
                              : 250U);
  self.liveRequestsEnabled = ([self.serviceURL length] > 0) && STBooleanValue(self.engineConfig[@"liveRequestsEnabled"], YES);
  NSDictionary *inlineFixtures = STNormalizeDictionary(self.engineConfig[@"fixtures"]);
  NSString *fixturesPath = STTrimmedString(self.engineConfig[@"fixturesPath"]);
  if ([fixturesPath length] > 0) {
    NSString *resolvedPath = [fixturesPath hasPrefix:@"/"]
                                 ? fixturesPath
                                 : [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:fixturesPath];
    NSDictionary *loaded = STJSONDictionaryFromPath(resolvedPath, error);
    if (loaded == nil && error != NULL && *error != nil) {
      return NO;
    }
    self.fixturePayload = loaded ?: @{};
  } else {
    self.fixturePayload = inlineFixtures ?: @{};
  }
  return YES;
}

- (BOOL)syncLiveSnapshotForMetadata:(NSDictionary *)metadata
                           snapshot:(NSDictionary *)snapshot
                              error:(NSError **)error {
  (void)metadata;
  (void)snapshot;
  (void)error;
  return YES;
}

- (BOOL)syncLiveOperation:(NSString *)operation
                   record:(NSDictionary *)record
                 metadata:(NSDictionary *)metadata
                 snapshot:(NSDictionary *)snapshot
                    error:(NSError **)error {
  (void)operation;
  (void)record;
  (void)metadata;
  (void)snapshot;
  (void)error;
  return YES;
}

- (nullable NSDictionary *)performLiveSearchForIndexName:(NSString *)indexName
                                                metadata:(NSDictionary *)metadata
                                                   query:(NSString *)query
                                                 filters:(NSDictionary *)filters
                                                    sort:(NSString *)sort
                                                   limit:(NSUInteger)limit
                                                  offset:(NSUInteger)offset
                                                 options:(NSDictionary *)options
                                                   error:(NSError **)error {
  (void)indexName;
  (void)metadata;
  (void)query;
  (void)filters;
  (void)sort;
  (void)limit;
  (void)offset;
  (void)options;
  (void)error;
  return nil;
}

- (NSDictionary *)decoratedDocument:(NSDictionary *)document
                            withHit:(NSDictionary *)hit
                          sourceTag:(NSString *)sourceTag {
  NSMutableDictionary *decorated = [NSMutableDictionary dictionaryWithDictionary:document ?: @{}];
  if ([hit[@"score"] respondsToSelector:@selector(doubleValue)]) {
    double score = [hit[@"score"] doubleValue];
    decorated[@"scoreValue"] = @(score);
    decorated[@"score"] = @((NSInteger)llround(score));
  }
  NSArray *highlights = STNormalizeArray(hit[@"highlights"]);
  if ([highlights count] == 0 && [STTrimmedString(hit[@"highlight"]) length] > 0) {
    highlights = @[ STTrimmedString(hit[@"highlight"]) ];
  }
  if ([highlights count] > 0) {
    decorated[@"highlights"] = highlights;
  }
  NSArray *matchedFields = STNormalizedStringArray(hit[@"matchedFields"]);
  if ([matchedFields count] > 0) {
    decorated[@"matchedFields"] = matchedFields;
  }
  NSMutableDictionary *explain = [NSMutableDictionary dictionaryWithDictionary:STNormalizeDictionary(decorated[@"explain"])];
  [explain addEntriesFromDictionary:STNormalizeDictionary(hit[@"explain"])];
  explain[@"source"] = ([STTrimmedString(sourceTag) length] > 0) ? STTrimmedString(sourceTag) : @"external";
  decorated[@"explain"] = explain;
  return decorated;
}

- (nullable NSDictionary *)searchModuleSnapshotForMetadata:(NSDictionary *)metadata
                                                   records:(NSArray<NSDictionary *> *)records
                                                generation:(NSUInteger)generation
                                                     error:(NSError **)error {
  id state = [self searchModuleBeginBuildForMetadata:metadata generation:generation error:error];
  if (state == nil) {
    return nil;
  }
  if (![self searchModuleAppendBuildRecords:records metadata:metadata state:state error:error]) {
    return nil;
  }
  return [self searchModuleFinalizeBuildState:state metadata:metadata error:error];
}

- (nullable NSDictionary *)searchModuleFinalizeBuildState:(id)state
                                                 metadata:(NSDictionary *)metadata
                                                    error:(NSError **)error {
  NSDictionary *snapshot = [super searchModuleFinalizeBuildState:state metadata:metadata error:error];
  if (snapshot == nil) {
    return nil;
  }
  if (self.liveRequestsEnabled && ![self syncLiveSnapshotForMetadata:metadata snapshot:snapshot error:error]) {
    return nil;
  }
  NSUInteger documentCount = [snapshot[@"documentCount"] respondsToSelector:@selector(unsignedIntegerValue)]
                                 ? [snapshot[@"documentCount"] unsignedIntegerValue]
                                 : [STNormalizeArray(snapshot[@"documents"]) count];
  NSUInteger chunkCount = (documentCount == 0U) ? 0U : ((documentCount + self.chunkSize - 1U) / self.chunkSize);
  NSMutableDictionary *engineState = [NSMutableDictionary dictionaryWithDictionary:[self externalIndexDescriptorForMetadata:metadata]];
  engineState[@"lastSyncOperation"] = @"full";
  engineState[@"documentCount"] = @(documentCount);
  engineState[@"chunkCount"] = @(chunkCount);
  engineState[@"syncedAt"] = @([[NSDate date] timeIntervalSince1970]);
  NSDictionary *fixture = [self fixtureResponseForOperation:@"snapshot" resourceID:metadata[@"identifier"] query:@"" options:@{}];
  if ([fixture count] > 0) {
    [engineState addEntriesFromDictionary:fixture];
  }
  NSMutableDictionary *decorated = [NSMutableDictionary dictionaryWithDictionary:snapshot];
  decorated[@"engineState"] = engineState;
  return decorated;
}

- (nullable NSDictionary *)searchModuleApplyOperation:(NSString *)operation
                                               record:(NSDictionary *)record
                                             metadata:(NSDictionary *)metadata
                                      existingSnapshot:(NSDictionary *)snapshot
                                                error:(NSError **)error {
  NSDictionary *updated = [super searchModuleApplyOperation:operation record:record metadata:metadata existingSnapshot:snapshot error:error];
  if (updated == nil) {
    return nil;
  }
  if (self.liveRequestsEnabled && ![self syncLiveOperation:operation record:record metadata:metadata snapshot:updated error:error]) {
    return nil;
  }
  NSMutableDictionary *engineState = [NSMutableDictionary dictionaryWithDictionary:STNormalizeDictionary(snapshot[@"engineState"])];
  if ([engineState count] == 0) {
    [engineState addEntriesFromDictionary:[self externalIndexDescriptorForMetadata:metadata]];
  }
  engineState[@"lastSyncOperation"] = STLowerTrimmedString(operation);
  engineState[@"documentCount"] = updated[@"documentCount"] ?: @0;
  engineState[@"syncedAt"] = @([[NSDate date] timeIntervalSince1970]);
  NSDictionary *fixture = [self fixtureResponseForOperation:@"operation"
                                                 resourceID:metadata[@"identifier"]
                                                      query:STLowerTrimmedString(operation)
                                                    options:@{}];
  if ([fixture count] > 0) {
    [engineState addEntriesFromDictionary:fixture];
  }
  NSMutableDictionary *decorated = [NSMutableDictionary dictionaryWithDictionary:updated];
  decorated[@"engineState"] = engineState;
  return decorated;
}

- (nullable NSDictionary *)searchModuleExecuteQuery:(NSString *)query
                                     resourceMetadata:(NSArray<NSDictionary *> *)resourceMetadata
                                  snapshotsByResource:(NSDictionary<NSString *, NSDictionary *> *)snapshotsByResource
                                              filters:(NSDictionary *)filters
                                                 sort:(NSString *)sort
                                                limit:(NSUInteger)limit
                                               offset:(NSUInteger)offset
                                              options:(NSDictionary *)options
                                                error:(NSError **)error {
  NSUInteger fetchLimit = MAX(MAX((NSUInteger)25U, limit), (NSUInteger)200U);
  NSDictionary *base = [super searchModuleExecuteQuery:query
                                       resourceMetadata:resourceMetadata
                                    snapshotsByResource:snapshotsByResource
                                                filters:filters
                                                   sort:sort
                                                  limit:fetchLimit
                                                 offset:0
                                                options:options
                                                  error:error];
  if (base == nil) {
    return nil;
  }

  NSMutableDictionary<NSString *, NSDictionary *> *documentsByKey = [NSMutableDictionary dictionary];
  for (NSDictionary *metadata in STNormalizeArray(resourceMetadata)) {
    NSString *resourceID = STLowerTrimmedString(metadata[@"identifier"]);
    NSDictionary *snapshot = STNormalizeDictionary(snapshotsByResource[resourceID]);
    for (NSDictionary *document in STNormalizeArray(snapshot[@"documents"])) {
      NSString *recordID = STTrimmedString(document[@"recordID"]);
      if ([resourceID length] == 0 || [recordID length] == 0) {
        continue;
      }
      documentsByKey[[NSString stringWithFormat:@"%@:%@", resourceID, recordID]] = document;
    }
  }

  NSMutableArray *engineOrdered = [NSMutableArray array];
  NSMutableSet *seen = [NSMutableSet set];
  NSMutableSet *externalizedResources = [NSMutableSet set];
  NSMutableArray *debugEntries = [NSMutableArray array];
  NSMutableArray *externalFacets = [NSMutableArray array];
  NSMutableOrderedSet *autocomplete = [NSMutableOrderedSet orderedSet];
  NSMutableOrderedSet *suggestions = [NSMutableOrderedSet orderedSet];
  NSUInteger externalTotal = 0U;

  for (NSDictionary *metadata in STNormalizeArray(resourceMetadata)) {
    NSString *resourceID = STLowerTrimmedString(metadata[@"identifier"]);
    NSDictionary *effectiveFilters = [self effectiveFilters:filters metadata:metadata options:options];
    NSDictionary *response = [self fixtureResponseForOperation:@"query" resourceID:resourceID query:query options:options ?: @{}];
    if ([response count] == 0 && self.liveRequestsEnabled) {
      NSDictionary *live = [self performLiveSearchForIndexName:[self externalIndexNameForMetadata:metadata]
                                                      metadata:metadata
                                                         query:query
                                                       filters:effectiveFilters
                                                          sort:sort
                                                         limit:fetchLimit
                                                        offset:0U
                                                       options:options ?: @{}
                                                         error:NULL];
      response = live ?: @{};
    }
    if ([response count] == 0) {
      continue;
    }

    [externalizedResources addObject:resourceID];
    NSDictionary *normalized = [self normalizedExternalResponse:response resourceMetadata:metadata];
    externalTotal += [normalized[@"total"] respondsToSelector:@selector(unsignedIntegerValue)] ? [normalized[@"total"] unsignedIntegerValue] : 0U;
    NSArray *resourceFacets = STNormalizeArray(normalized[@"facets"]);
    if ([resourceFacets count] == 0) {
      resourceFacets = [self facetSummariesFromBuckets:STNormalizeDictionary(normalized[@"facetDistribution"])
                                             metadata:metadata
                                              filters:effectiveFilters];
    }
    if ([resourceFacets count] > 0) {
      [externalFacets addObjectsFromArray:resourceFacets];
    }
    NSArray *hits = STNormalizeArray(normalized[@"hits"]);
    if ([hits count] == 0) {
      NSMutableArray *synthesized = [NSMutableArray array];
      for (NSString *recordID in STTrimmedUniqueStringArray(normalized[@"order"])) {
        [synthesized addObject:@{ @"recordID" : recordID }];
      }
      hits = synthesized;
    }
    for (NSDictionary *hit in hits) {
      NSString *recordID = STTrimmedString(hit[@"recordID"]);
      NSString *key = [NSString stringWithFormat:@"%@:%@", resourceID ?: @"", recordID ?: @""];
      NSDictionary *document = documentsByKey[key];
      if (document == nil || [seen containsObject:key]) {
        continue;
      }
      [engineOrdered addObject:[self decoratedDocument:document withHit:hit sourceTag:normalized[@"source"]]];
      [seen addObject:key];
    }
    for (NSString *value in STNormalizeArray(normalized[@"autocomplete"])) {
      [autocomplete addObject:value];
    }
    for (NSString *value in STNormalizeArray(normalized[@"suggestions"])) {
      [suggestions addObject:value];
    }
    [debugEntries addObject:@{
      @"resource" : resourceID ?: @"",
      @"indexName" : [self externalIndexNameForMetadata:metadata] ?: @"",
      @"source" : normalized[@"source"] ?: @"external",
      @"response" : STNormalizeDictionary(normalized[@"debug"]),
    }];
  }

  if ([externalizedResources count] == 0U) {
    NSMutableDictionary *fallback = [NSMutableDictionary dictionaryWithDictionary:base];
    fallback[@"debug"] = @{
      @"adapter" : [self externalEngineName] ?: @"external",
      @"source" : @"local_fallback",
      @"entries" : @[],
    };
    return fallback;
  }

  if ([externalizedResources count] < [resourceMetadata count]) {
    for (NSString *value in STNormalizeArray(base[@"autocomplete"])) {
      [autocomplete addObject:value];
    }
    for (NSString *value in STNormalizeArray(base[@"suggestions"])) {
      [suggestions addObject:value];
    }
  }

  NSArray *orderedMatches = engineOrdered;
  NSUInteger fallbackTotal = 0U;
  if ([externalizedResources count] < [resourceMetadata count]) {
    NSMutableArray *tail = [NSMutableArray array];
    for (NSDictionary *document in STNormalizeArray(base[@"matchedDocuments"])) {
      NSString *resourceID = STLowerTrimmedString(document[@"resource"]);
      if ([externalizedResources containsObject:resourceID]) {
        continue;
      }
      fallbackTotal += 1U;
      NSString *key = [NSString stringWithFormat:@"%@:%@", resourceID, STTrimmedString(document[@"recordID"])];
      if ([seen containsObject:key]) {
        continue;
      }
      [tail addObject:document];
    }
    orderedMatches = [engineOrdered arrayByAddingObjectsFromArray:tail];
  }

  NSString *requestedCursor = STTrimmedString(options[@"cursor"]);
  NSUInteger start = 0U;
  if ([requestedCursor length] > 0) {
    NSString *recordID = STRecordIDFromCursor(requestedCursor);
    for (NSUInteger index = 0; index < [orderedMatches count]; index++) {
      if ([STTrimmedString(orderedMatches[index][@"recordID"]) isEqualToString:recordID]) {
        start = index + 1U;
        break;
      }
    }
  } else {
    start = MIN(offset, [orderedMatches count]);
  }
  NSUInteger resolvedLimit = (limit > 0U) ? limit : 25U;
  NSUInteger sliceLength = MIN(resolvedLimit, ([orderedMatches count] - MIN(start, [orderedMatches count])));
  NSArray *page = [orderedMatches subarrayWithRange:NSMakeRange(MIN(start, [orderedMatches count]), sliceLength)];
  NSString *nextCursor = @"";
  if ((start + sliceLength) < [orderedMatches count] && [page count] > 0) {
    nextCursor = STCursorForRecordID([[page lastObject] objectForKey:@"recordID"]);
  }

  return @{
    @"query" : STTrimmedString(query),
    @"mode" : STLowerTrimmedString(options[@"mode"]).length > 0 ? STLowerTrimmedString(options[@"mode"]) : (base[@"mode"] ?: @"search"),
    @"availableModes" : base[@"availableModes"] ?: @[ @"search" ],
    @"results" : page ?: @[],
    @"matchedDocuments" : orderedMatches ?: @[],
    @"autocomplete" : [autocomplete array] ?: @[],
    @"suggestions" : [suggestions array] ?: @[],
    @"facets" : externalFacets ?: @[],
    @"total" : @((externalTotal > 0U || [externalizedResources count] > 0U) ? (externalTotal + fallbackTotal) : [orderedMatches count]),
    @"limit" : @(resolvedLimit),
    @"offset" : @(requestedCursor.length > 0 ? 0U : offset),
    @"nextCursor" : nextCursor ?: @"",
    @"debug" : @{
      @"adapter" : [self externalEngineName] ?: @"external",
      @"source" : ([externalizedResources count] == [resourceMetadata count]) ? @"external" : @"mixed",
      @"entries" : debugEntries ?: @[],
    },
  };
}

- (NSDictionary *)searchModuleCapabilities {
  NSMutableDictionary *capabilities = [NSMutableDictionary dictionaryWithDictionary:[super searchModuleCapabilities]];
  [capabilities addEntriesFromDictionary:[self externalCapabilities] ?: @{}];
  capabilities[@"engine"] = [self externalEngineName] ?: @"external";
  return capabilities;
}

@end

@implementation ALNMeilisearchSearchEngine

- (NSString *)engineConfigKey {
  return @"meilisearch";
}

- (NSString *)externalEngineName {
  return @"meilisearch";
}

- (NSDictionary *)externalCapabilities {
  return @{
    @"supportsHighlights" : @YES,
    @"supportsIncrementalSync" : @YES,
    @"supportsGenerations" : @YES,
    @"supportsAutocomplete" : @YES,
    @"supportsSuggestions" : @YES,
    @"supportsFacets" : @YES,
    @"supportsPromotedResults" : @YES,
    @"supportsFullTextRanking" : @YES,
    @"supportsFuzzyMatching" : @YES,
    @"supportsTypedFilters" : @YES,
    @"supportsCursorPagination" : @YES,
    @"supportsSoftDeleteFilters" : @YES,
    @"supportsTenantScoping" : @YES,
    @"supportsPhraseSearch" : @YES,
    @"supportsBooleanSearch" : @NO,
    @"queryModes" : @[ @"search", @"phrase", @"fuzzy", @"autocomplete" ],
  };
}

- (NSDictionary *)externalIndexDescriptorForMetadata:(NSDictionary *)metadata {
  NSMutableDictionary *descriptor = [NSMutableDictionary dictionaryWithDictionary:[super externalIndexDescriptorForMetadata:metadata]];
  NSMutableOrderedSet<NSString *> *filterable = [NSMutableOrderedSet orderedSet];
  for (NSDictionary *entry in STNormalizeArray(metadata[@"filters"])) {
    NSString *name = STLowerTrimmedString(entry[@"name"]);
    if ([name length] > 0) {
      [filterable addObject:name];
    }
  }
  for (NSDictionary *entry in STNormalizeArray(metadata[@"facetFields"])) {
    NSString *name = STLowerTrimmedString(entry[@"name"]);
    if ([name length] > 0) {
      [filterable addObject:name];
    }
  }
  NSArray *sortable = [[[STNormalizeArray(metadata[@"sorts"]) valueForKey:@"name"] ?: @[] copy] sortedArrayUsingSelector:@selector(compare:)];
  descriptor[@"settings"] = @{
    @"filterableAttributes" : [[filterable array] sortedArrayUsingSelector:@selector(compare:)] ?: @[],
    @"sortableAttributes" : sortable ?: @[],
    @"searchableAttributes" : metadata[@"searchFields"] ?: @[],
    @"displayedAttributes" : metadata[@"resultFields"] ?: @[],
    @"rankingRules" : STNormalizeArray(self.engineConfig[@"rankingRules"]),
    @"synonyms" : STNormalizeDictionary(self.engineConfig[@"synonyms"]),
    @"typoTolerance" : STNormalizeDictionary(self.engineConfig[@"typoTolerance"]),
  };
  return descriptor;
}

- (NSDictionary *)meilisearchHeaders {
  NSMutableDictionary *headers = [NSMutableDictionary dictionary];
  if ([self.apiKey length] > 0) {
    headers[@"Authorization"] = [NSString stringWithFormat:@"Bearer %@", self.apiKey];
  }
  return headers;
}

- (NSArray<NSString *> *)meilisearchFilterExpressionsForMetadata:(NSDictionary *)metadata
                                                         filters:(NSDictionary *)filters {
  NSMutableArray<NSString *> *expressions = [NSMutableArray array];
  NSDictionary<NSString *, NSDictionary *> *filterMetadata = [self filterMetadataByFieldForMetadata:metadata];
  NSArray<NSString *> *keys = [[filters allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *rawKey in keys) {
    NSDictionary *components = STFilterComponentsFromRawKey(rawKey);
    NSString *field = STLowerTrimmedString(components[@"field"]);
    NSString *operatorName = STLowerTrimmedString(components[@"operator"]);
    NSDictionary *entry = filterMetadata[field];
    if ([field length] == 0 || entry == nil) {
      continue;
    }
    NSString *type = ([STLowerTrimmedString(entry[@"type"]) length] > 0) ? STLowerTrimmedString(entry[@"type"]) : [self fieldTypeForField:field metadata:metadata];
    id rawValue = filters[rawKey];
    if ([operatorName isEqualToString:@"in"]) {
      NSArray *values = STTypedSearchValues(rawValue, type);
      if ([values count] == 0U) {
        continue;
      }
      NSMutableArray<NSString *> *literals = [NSMutableArray array];
      for (id value in values) {
        [literals addObject:STJSONLiteralString(value)];
      }
      [expressions addObject:[NSString stringWithFormat:@"%@ IN [%@]", field, [literals componentsJoinedByString:@", "]]];
      continue;
    }
    NSString *symbol = @"=";
    if ([operatorName isEqualToString:@"gt"]) {
      symbol = @">";
    } else if ([operatorName isEqualToString:@"gte"]) {
      symbol = @">=";
    } else if ([operatorName isEqualToString:@"lt"]) {
      symbol = @"<";
    } else if ([operatorName isEqualToString:@"lte"]) {
      symbol = @"<=";
    } else if ([operatorName isEqualToString:@"contains"]) {
      symbol = @"CONTAINS";
    }
    [expressions addObject:[NSString stringWithFormat:@"%@ %@ %@",
                                                      field,
                                                      symbol,
                                                      STJSONLiteralString(STTypedSearchValue(rawValue, type))]];
  }
  return expressions;
}

- (NSArray<NSString *> *)meilisearchSortExpressionsForMetadata:(NSDictionary *)metadata
                                                          sort:(NSString *)sort
                                                         query:(NSString *)query {
  NSDictionary *descriptor = STResolvedSearchSortDescriptor(metadata, sort, query);
  NSString *field = STLowerTrimmedString(descriptor[@"field"]);
  if ([field length] == 0 || [field isEqualToString:@"relevance"]) {
    return @[];
  }
  return @[ [NSString stringWithFormat:@"%@:%@", field, descriptor[@"direction"] ?: @"asc"] ];
}

- (BOOL)syncLiveSnapshotForMetadata:(NSDictionary *)metadata
                           snapshot:(NSDictionary *)snapshot
                              error:(NSError **)error {
  NSString *baseURL = [self.serviceURL stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
  NSString *indexName = [self externalIndexNameForMetadata:metadata];
  NSString *primaryKey = STLowerTrimmedString(metadata[@"identifierField"]);
  if ([primaryKey length] == 0) {
    primaryKey = @"recordID";
  }
  NSDictionary *headers = [self meilisearchHeaders];
  NSString *indexesPath = [NSString stringWithFormat:@"%@/indexes", baseURL];
  NSString *indexPath = [NSString stringWithFormat:@"%@/%@", indexesPath, STPercentEncodedPathComponent(indexName)];
  if ([self jsonRequestWithMethod:@"DELETE"
                             path:indexPath
                          headers:headers
                             body:nil
                    allowNotFound:YES
                          message:@"Meilisearch index reset failed"
                            error:error] == nil) {
    return NO;
  }
  if ([self jsonRequestWithMethod:@"POST"
                             path:indexesPath
                          headers:headers
                             body:@{
                               @"uid" : indexName ?: @"",
                               @"primaryKey" : primaryKey ?: @"recordID",
                             }
                    allowNotFound:NO
                          message:@"Meilisearch index creation failed"
                            error:error] == nil) {
    return NO;
  }
  NSDictionary *settings = STNormalizeDictionary([self externalIndexDescriptorForMetadata:metadata][@"settings"]);
  if ([settings count] > 0 &&
      [self jsonRequestWithMethod:@"PATCH"
                             path:[NSString stringWithFormat:@"%@/settings", indexPath]
                          headers:headers
                             body:settings
                    allowNotFound:NO
                          message:@"Meilisearch settings sync failed"
                            error:error] == nil) {
    return NO;
  }
  NSArray *documents = STNormalizeArray(snapshot[@"documents"]);
  for (NSUInteger index = 0U; index < [documents count]; index += self.chunkSize) {
    NSUInteger length = MIN(self.chunkSize, [documents count] - index);
    NSArray *chunk = [documents subarrayWithRange:NSMakeRange(index, length)];
    NSMutableArray *payload = [NSMutableArray arrayWithCapacity:[chunk count]];
    for (NSDictionary *document in chunk) {
      [payload addObject:[self liveDocumentPayloadForDocument:document metadata:metadata] ?: @{}];
    }
    NSString *path = [NSString stringWithFormat:@"%@/documents?primaryKey=%@",
                                                indexPath,
                                                STPercentEncodedQueryComponent(primaryKey)];
    if ([self jsonRequestWithMethod:@"POST"
                               path:path
                            headers:headers
                               body:payload
                      allowNotFound:NO
                            message:@"Meilisearch document sync failed"
                              error:error] == nil) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)syncLiveOperation:(NSString *)operation
                   record:(NSDictionary *)record
                 metadata:(NSDictionary *)metadata
                 snapshot:(NSDictionary *)snapshot
                    error:(NSError **)error {
  (void)snapshot;
  NSString *baseURL = [self.serviceURL stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
  NSString *indexName = [self externalIndexNameForMetadata:metadata];
  NSString *indexPath = [NSString stringWithFormat:@"%@/indexes/%@",
                                                   baseURL,
                                                   STPercentEncodedPathComponent(indexName)];
  NSDictionary *headers = [self meilisearchHeaders];
  NSString *identifierField = STLowerTrimmedString(metadata[@"identifierField"]);
  if ([identifierField length] == 0) {
    identifierField = @"recordID";
  }
  NSString *recordID = STTrimmedString(record[identifierField]);
  if ([recordID length] == 0) {
    recordID = STTrimmedString(record[@"recordID"]);
  }
  if ([recordID length] == 0) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorValidationFailed,
                       @"search record is missing an identifier for Meilisearch sync",
                       @{ @"resource" : metadata[@"identifier"] ?: @"" });
    }
    return NO;
  }
  if ([[STLowerTrimmedString(operation) lowercaseString] isEqualToString:@"delete"]) {
    NSString *path = [NSString stringWithFormat:@"%@/documents/%@",
                                                indexPath,
                                                STPercentEncodedPathComponent(recordID)];
    return ([self jsonRequestWithMethod:@"DELETE"
                                   path:path
                                headers:headers
                                   body:nil
                          allowNotFound:YES
                                message:@"Meilisearch document delete failed"
                                  error:error] != nil);
  }
  NSDictionary *document = [self normalizedDocumentForRecord:record metadata:metadata];
  if (document == nil) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorValidationFailed,
                       @"search record could not be normalized for Meilisearch sync",
                       @{ @"resource" : metadata[@"identifier"] ?: @"" });
    }
    return NO;
  }
  NSString *path = [NSString stringWithFormat:@"%@/documents?primaryKey=%@",
                                              indexPath,
                                              STPercentEncodedQueryComponent(identifierField)];
  return ([self jsonRequestWithMethod:@"POST"
                                 path:path
                              headers:headers
                                 body:@[ [self liveDocumentPayloadForDocument:document metadata:metadata] ?: @{} ]
                        allowNotFound:NO
                              message:@"Meilisearch document upsert failed"
                                error:error] != nil);
}

- (nullable NSDictionary *)performLiveSearchForIndexName:(NSString *)indexName
                                                metadata:(NSDictionary *)metadata
                                                   query:(NSString *)query
                                                 filters:(NSDictionary *)filters
                                                    sort:(NSString *)sort
                                                   limit:(NSUInteger)limit
                                                  offset:(NSUInteger)offset
                                                 options:(NSDictionary *)options
                                                   error:(NSError **)error {
  if (!self.liveRequestsEnabled) {
    return nil;
  }
  NSString *baseURL = [self.serviceURL stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
  NSString *path = [NSString stringWithFormat:@"%@/indexes/%@/search",
                                              baseURL,
                                              STPercentEncodedPathComponent(indexName)];
  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"q"] = STTrimmedString(query);
  payload[@"limit"] = @(MAX((NSUInteger)1U, limit));
  payload[@"offset"] = @(offset);
  payload[@"attributesToSearchOn"] = [self queryFieldsForMetadata:metadata
                                                     autocomplete:[[self normalizedQueryModeFromOptions:options metadata:metadata] isEqualToString:@"autocomplete"]];
  NSArray *filtersPayload = [self meilisearchFilterExpressionsForMetadata:metadata filters:filters ?: @{}];
  if ([filtersPayload count] > 0) {
    payload[@"filter"] = filtersPayload;
  }
  NSArray *sortPayload = [self meilisearchSortExpressionsForMetadata:metadata sort:sort query:query];
  if ([sortPayload count] > 0) {
    payload[@"sort"] = sortPayload;
  }
  NSArray *highlightFields = [self highlightFieldsForMetadata:metadata];
  if ([highlightFields count] > 0) {
    payload[@"attributesToHighlight"] = highlightFields;
  }
  NSArray *facetFields = STNormalizedStringArray([STNormalizeArray(metadata[@"facetFields"]) valueForKey:@"name"]);
  if ([facetFields count] > 0) {
    payload[@"facets"] = facetFields;
  }
  payload[@"showRankingScore"] = @YES;
  NSDictionary *response = [self jsonRequestWithMethod:@"POST"
                                                  path:path
                                               headers:[self meilisearchHeaders]
                                                  body:payload
                                         allowNotFound:NO
                                               message:@"Meilisearch search failed"
                                                 error:error];
  if (response == nil) {
    return nil;
  }
  NSDictionary *body = STNormalizeDictionary(response[@"body"]);
  NSString *identifierField = STLowerTrimmedString(metadata[@"identifierField"]);
  if ([identifierField length] == 0) {
    identifierField = @"recordID";
  }
  NSMutableArray *hits = [NSMutableArray array];
  for (NSDictionary *entry in STNormalizeArray(body[@"hits"])) {
    NSString *recordID = STTrimmedString(entry[@"recordID"]);
    if ([recordID length] == 0) {
      recordID = STTrimmedString(entry[identifierField]);
    }
    if ([recordID length] == 0) {
      continue;
    }
    NSMutableDictionary *hit = [NSMutableDictionary dictionary];
    hit[@"recordID"] = recordID;
    if ([entry[@"_rankingScore"] respondsToSelector:@selector(doubleValue)]) {
      hit[@"score"] = @([entry[@"_rankingScore"] doubleValue] * 100.0);
    }
    NSDictionary *formatted = STNormalizeDictionary(entry[@"_formatted"]);
    NSMutableArray<NSString *> *highlights = [NSMutableArray array];
    NSMutableArray<NSString *> *matchedFields = [NSMutableArray array];
    for (NSString *field in [self highlightFieldsForMetadata:metadata]) {
      NSString *value = STTrimmedString(formatted[field]);
      if ([value length] == 0) {
        continue;
      }
      [highlights addObject:value];
      [matchedFields addObject:field];
    }
    if ([highlights count] > 0) {
      hit[@"highlights"] = highlights;
    }
    if ([matchedFields count] > 0) {
      hit[@"matchedFields"] = matchedFields;
    }
    [hits addObject:hit];
  }
  return @{
    @"source" : @"live",
    @"hits" : hits ?: @[],
    @"total" : body[@"estimatedTotalHits"] ?: body[@"totalHits"] ?: @([hits count]),
    @"facetDistribution" : STNormalizeDictionary(body[@"facetDistribution"]),
    @"debug" : @{
      @"httpStatus" : response[@"status"] ?: @0,
      @"path" : path ?: @"",
      @"payload" : payload ?: @{},
    },
  };
}

@end

@implementation ALNOpenSearchSearchEngine

- (NSString *)engineConfigKey {
  return @"opensearch";
}

- (NSString *)externalEngineName {
  return @"opensearch";
}

- (NSDictionary *)externalCapabilities {
  return @{
    @"supportsHighlights" : @YES,
    @"supportsIncrementalSync" : @YES,
    @"supportsGenerations" : @YES,
    @"supportsAutocomplete" : @YES,
    @"supportsSuggestions" : @YES,
    @"supportsFacets" : @YES,
    @"supportsPromotedResults" : @YES,
    @"supportsFullTextRanking" : @YES,
    @"supportsFuzzyMatching" : @YES,
    @"supportsTypedFilters" : @YES,
    @"supportsCursorPagination" : @YES,
    @"supportsSoftDeleteFilters" : @YES,
    @"supportsTenantScoping" : @YES,
    @"supportsPhraseSearch" : @YES,
    @"supportsBooleanSearch" : @YES,
    @"queryModes" : @[ @"search", @"phrase", @"fuzzy", @"autocomplete" ],
  };
}

- (NSDictionary *)externalIndexDescriptorForMetadata:(NSDictionary *)metadata {
  NSMutableDictionary *descriptor = [NSMutableDictionary dictionaryWithDictionary:[super externalIndexDescriptorForMetadata:metadata]];
  NSMutableDictionary *properties = [NSMutableDictionary dictionary];
  NSDictionary *fieldTypes = STNormalizeDictionary(metadata[@"fieldTypes"]);
  for (NSString *field in STNormalizeArray(metadata[@"indexedFields"])) {
    NSString *type = STLowerTrimmedString(fieldTypes[field]);
    if ([type isEqualToString:@"integer"]) {
      properties[field] = @{ @"type" : @"integer" };
    } else if (STSearchFieldTypeIsNumeric(type)) {
      properties[field] = @{ @"type" : @"double" };
    } else if (STSearchFieldTypeIsBoolean(type)) {
      properties[field] = @{ @"type" : @"boolean" };
    } else {
      properties[field] = @{
        @"type" : @"text",
        @"fields" : @{
          @"keyword" : @{
            @"type" : @"keyword",
            @"ignore_above" : @256,
          },
        },
      };
    }
  }
  properties[@"recordID"] = @{ @"type" : @"keyword" };
  properties[@"resource"] = @{ @"type" : @"keyword" };
  properties[@"title"] = @{
    @"type" : @"text",
    @"fields" : @{
      @"keyword" : @{
        @"type" : @"keyword",
        @"ignore_above" : @256,
      },
    },
  };
  properties[@"summary"] = @{ @"type" : @"text" };
  properties[@"searchableText"] = @{ @"type" : @"text" };
  properties[@"autocompleteText"] = @{ @"type" : @"text" };
  descriptor[@"mappings"] = @{ @"properties" : properties ?: @{} };
  descriptor[@"analysis"] = STNormalizeDictionary(self.engineConfig[@"analysis"]);
  descriptor[@"aliases"] = STNormalizeArray(self.engineConfig[@"aliases"]);
  descriptor[@"synonyms"] = STNormalizeArray(self.engineConfig[@"synonyms"]);
  return descriptor;
}

- (NSDictionary *)openSearchHeaders {
  NSMutableDictionary *headers = [NSMutableDictionary dictionary];
  if ([self.apiKey length] > 0) {
    headers[@"Authorization"] = [NSString stringWithFormat:@"ApiKey %@", self.apiKey];
  }
  return headers;
}

- (NSString *)openSearchExactFieldNameForField:(NSString *)field metadata:(NSDictionary *)metadata {
  NSString *type = [self fieldTypeForField:field metadata:metadata];
  if (STSearchFieldTypeIsNumeric(type) || STSearchFieldTypeIsBoolean(type) ||
      [field isEqualToString:@"recordid"] || [field isEqualToString:@"resource"]) {
    return field;
  }
  return [NSString stringWithFormat:@"%@.keyword", field];
}

- (NSArray<NSString *> *)openSearchQueryFieldsForMetadata:(NSDictionary *)metadata
                                                    mode:(NSString *)mode {
  BOOL autocomplete = [mode isEqualToString:@"autocomplete"];
  NSArray *fields = [self queryFieldsForMetadata:metadata autocomplete:autocomplete];
  NSDictionary *weights = STNormalizeDictionary(metadata[@"weightedFields"]);
  NSMutableArray<NSString *> *resolved = [NSMutableArray array];
  for (NSString *field in fields) {
    NSUInteger weight = [weights[field] respondsToSelector:@selector(unsignedIntegerValue)]
                            ? MAX((NSUInteger)1U, [weights[field] unsignedIntegerValue])
                            : 1U;
    if (weight > 1U) {
      [resolved addObject:[NSString stringWithFormat:@"%@^%lu", field, (unsigned long)weight]];
    } else {
      [resolved addObject:field];
    }
  }
  return ([resolved count] > 0) ? resolved : @[ @"searchableText" ];
}

- (NSArray<NSDictionary *> *)openSearchFilterClausesForMetadata:(NSDictionary *)metadata
                                                        filters:(NSDictionary *)filters {
  NSMutableArray<NSDictionary *> *clauses = [NSMutableArray array];
  NSDictionary<NSString *, NSDictionary *> *filterMetadata = [self filterMetadataByFieldForMetadata:metadata];
  NSArray<NSString *> *keys = [[filters allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *rawKey in keys) {
    NSDictionary *components = STFilterComponentsFromRawKey(rawKey);
    NSString *field = STLowerTrimmedString(components[@"field"]);
    NSString *operatorName = STLowerTrimmedString(components[@"operator"]);
    NSDictionary *entry = filterMetadata[field];
    if ([field length] == 0 || entry == nil) {
      continue;
    }
    NSString *type = ([STLowerTrimmedString(entry[@"type"]) length] > 0) ? STLowerTrimmedString(entry[@"type"]) : [self fieldTypeForField:field metadata:metadata];
    id rawValue = filters[rawKey];
    if ([operatorName isEqualToString:@"contains"]) {
      [clauses addObject:@{
        @"match_phrase" : @{
          field : STTrimmedString(rawValue),
        },
      }];
      continue;
    }
    if ([operatorName isEqualToString:@"in"]) {
      NSArray *values = STTypedSearchValues(rawValue, type);
      if ([values count] == 0U) {
        continue;
      }
      [clauses addObject:@{
        @"terms" : @{
          [self openSearchExactFieldNameForField:field metadata:metadata] : values,
        },
      }];
      continue;
    }
    if ([operatorName isEqualToString:@"gt"] || [operatorName isEqualToString:@"gte"] ||
        [operatorName isEqualToString:@"lt"] || [operatorName isEqualToString:@"lte"]) {
      [clauses addObject:@{
        @"range" : @{
          field : @{
            operatorName : STTypedSearchValue(rawValue, type),
          },
        },
      }];
      continue;
    }
    [clauses addObject:@{
      @"term" : @{
        [self openSearchExactFieldNameForField:field metadata:metadata] : STTypedSearchValue(rawValue, type),
      },
    }];
  }
  return clauses;
}

- (NSArray<NSDictionary *> *)openSearchSortClausesForMetadata:(NSDictionary *)metadata
                                                         sort:(NSString *)sort
                                                        query:(NSString *)query {
  NSDictionary *descriptor = STResolvedSearchSortDescriptor(metadata, sort, query);
  NSString *field = STLowerTrimmedString(descriptor[@"field"]);
  if ([field length] == 0 || [field isEqualToString:@"relevance"]) {
    return @[];
  }
  return @[
    @{
      [self openSearchExactFieldNameForField:field metadata:metadata] : @{
        @"order" : descriptor[@"direction"] ?: @"asc",
      },
    },
  ];
}

- (NSDictionary *)openSearchTextQueryForMetadata:(NSDictionary *)metadata
                                           query:(NSString *)query
                                            mode:(NSString *)mode {
  NSString *normalizedQuery = STTrimmedString(query);
  if ([normalizedQuery length] == 0) {
    return @{ @"match_all" : @{} };
  }
  NSMutableDictionary *multiMatch = [NSMutableDictionary dictionary];
  multiMatch[@"query"] = normalizedQuery;
  multiMatch[@"fields"] = [self openSearchQueryFieldsForMetadata:metadata mode:mode];
  if ([mode isEqualToString:@"phrase"]) {
    multiMatch[@"type"] = @"phrase";
  } else if ([mode isEqualToString:@"autocomplete"]) {
    multiMatch[@"type"] = @"bool_prefix";
  } else if ([mode isEqualToString:@"fuzzy"]) {
    multiMatch[@"fuzziness"] = @"AUTO";
  }
  return @{ @"multi_match" : multiMatch };
}

- (BOOL)syncLiveSnapshotForMetadata:(NSDictionary *)metadata
                           snapshot:(NSDictionary *)snapshot
                              error:(NSError **)error {
  NSString *baseURL = [self.serviceURL stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
  NSString *indexName = [self externalIndexNameForMetadata:metadata];
  NSString *indexPath = [NSString stringWithFormat:@"%@/%@", baseURL, STPercentEncodedPathComponent(indexName)];
  NSDictionary *headers = [self openSearchHeaders];
  if ([self jsonRequestWithMethod:@"DELETE"
                             path:indexPath
                          headers:headers
                             body:nil
                    allowNotFound:YES
                          message:@"OpenSearch index reset failed"
                            error:error] == nil) {
    return NO;
  }
  NSDictionary *descriptor = [self externalIndexDescriptorForMetadata:metadata];
  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  NSDictionary *analysis = STNormalizeDictionary(descriptor[@"analysis"]);
  if ([analysis count] > 0) {
    payload[@"settings"] = @{ @"analysis" : analysis };
  }
  NSDictionary *mappings = STNormalizeDictionary(descriptor[@"mappings"]);
  if ([mappings count] > 0) {
    payload[@"mappings"] = mappings;
  }
  NSMutableDictionary *aliases = [NSMutableDictionary dictionary];
  for (NSString *alias in STNormalizedStringArray(descriptor[@"aliases"])) {
    aliases[alias] = @{};
  }
  if ([aliases count] > 0) {
    payload[@"aliases"] = aliases;
  }
  if ([self jsonRequestWithMethod:@"PUT"
                             path:indexPath
                          headers:headers
                             body:payload
                    allowNotFound:NO
                          message:@"OpenSearch index creation failed"
                            error:error] == nil) {
    return NO;
  }

  NSArray *documents = STNormalizeArray(snapshot[@"documents"]);
  for (NSUInteger index = 0U; index < [documents count]; index += self.chunkSize) {
    NSUInteger length = MIN(self.chunkSize, [documents count] - index);
    NSArray *chunk = [documents subarrayWithRange:NSMakeRange(index, length)];
    NSMutableData *body = [NSMutableData data];
    for (NSDictionary *document in chunk) {
      NSString *recordID = STTrimmedString(document[@"recordID"]);
      if ([recordID length] == 0) {
        continue;
      }
      if (!STAppendNDJSONLine(body,
                              @{
                                @"index" : @{
                                  @"_index" : indexName ?: @"",
                                  @"_id" : recordID ?: @"",
                                },
                              },
                              error)) {
        return NO;
      }
      if (!STAppendNDJSONLine(body, [self liveDocumentPayloadForDocument:document metadata:metadata] ?: @{}, error)) {
        return NO;
      }
    }
    NSMutableDictionary *bulkHeaders = [NSMutableDictionary dictionaryWithDictionary:headers ?: @{}];
    bulkHeaders[@"Content-Type"] = @"application/x-ndjson";
    NSDictionary *response = [self dataRequestWithMethod:@"POST"
                                                    path:[NSString stringWithFormat:@"%@/_bulk?refresh=true", indexPath]
                                                 headers:bulkHeaders
                                                    body:body
                                           allowNotFound:NO
                                                 message:@"OpenSearch bulk sync failed"
                                                   error:error];
    if (response == nil) {
      return NO;
    }
    if ([STNormalizeDictionary(response[@"body"])[@"errors"] boolValue]) {
      if (error != NULL) {
        *error = STError(ALNSearchModuleErrorExecutionFailed,
                         @"OpenSearch bulk sync returned partial failures",
                         @{
                           @"engine" : @"opensearch",
                           @"indexName" : indexName ?: @"",
                         });
      }
      return NO;
    }
  }
  return YES;
}

- (BOOL)syncLiveOperation:(NSString *)operation
                   record:(NSDictionary *)record
                 metadata:(NSDictionary *)metadata
                 snapshot:(NSDictionary *)snapshot
                    error:(NSError **)error {
  (void)snapshot;
  NSString *baseURL = [self.serviceURL stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
  NSString *indexName = [self externalIndexNameForMetadata:metadata];
  NSString *identifierField = STLowerTrimmedString(metadata[@"identifierField"]);
  if ([identifierField length] == 0) {
    identifierField = @"recordID";
  }
  NSString *recordID = STTrimmedString(record[identifierField]);
  if ([recordID length] == 0) {
    recordID = STTrimmedString(record[@"recordID"]);
  }
  if ([recordID length] == 0) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorValidationFailed,
                       @"search record is missing an identifier for OpenSearch sync",
                       @{ @"resource" : metadata[@"identifier"] ?: @"" });
    }
    return NO;
  }
  NSString *documentPath = [NSString stringWithFormat:@"%@/%@/_doc/%@?refresh=true",
                                                      baseURL,
                                                      STPercentEncodedPathComponent(indexName),
                                                      STPercentEncodedPathComponent(recordID)];
  if ([[STLowerTrimmedString(operation) lowercaseString] isEqualToString:@"delete"]) {
    return ([self jsonRequestWithMethod:@"DELETE"
                                   path:documentPath
                                headers:[self openSearchHeaders]
                                   body:nil
                          allowNotFound:YES
                                message:@"OpenSearch document delete failed"
                                  error:error] != nil);
  }
  NSDictionary *document = [self normalizedDocumentForRecord:record metadata:metadata];
  if (document == nil) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorValidationFailed,
                       @"search record could not be normalized for OpenSearch sync",
                       @{ @"resource" : metadata[@"identifier"] ?: @"" });
    }
    return NO;
  }
  return ([self jsonRequestWithMethod:@"PUT"
                                 path:documentPath
                              headers:[self openSearchHeaders]
                                 body:[self liveDocumentPayloadForDocument:document metadata:metadata] ?: @{}
                        allowNotFound:NO
                              message:@"OpenSearch document upsert failed"
                                error:error] != nil);
}

- (nullable NSDictionary *)performLiveSearchForIndexName:(NSString *)indexName
                                                metadata:(NSDictionary *)metadata
                                                   query:(NSString *)query
                                                 filters:(NSDictionary *)filters
                                                    sort:(NSString *)sort
                                                   limit:(NSUInteger)limit
                                                  offset:(NSUInteger)offset
                                                 options:(NSDictionary *)options
                                                   error:(NSError **)error {
  if (!self.liveRequestsEnabled) {
    return nil;
  }
  NSString *baseURL = [self.serviceURL stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
  NSString *path = [NSString stringWithFormat:@"%@/%@/_search",
                                              baseURL,
                                              STPercentEncodedPathComponent(indexName)];
  NSString *mode = [self normalizedQueryModeFromOptions:options metadata:metadata];
  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"size"] = @(MAX((NSUInteger)1U, limit));
  payload[@"from"] = @(offset);
  payload[@"track_total_hits"] = @YES;
  NSMutableDictionary *boolQuery = [NSMutableDictionary dictionary];
  NSArray *filterClauses = [self openSearchFilterClausesForMetadata:metadata filters:filters ?: @{}];
  if ([filterClauses count] > 0) {
    boolQuery[@"filter"] = filterClauses;
  }
  NSDictionary *textQuery = [self openSearchTextQueryForMetadata:metadata query:query mode:mode];
  if ([textQuery count] > 0) {
    boolQuery[@"must"] = @[ textQuery ];
  }
  payload[@"query"] = @{ @"bool" : boolQuery };
  NSArray *sortClauses = [self openSearchSortClausesForMetadata:metadata sort:sort query:query];
  if ([sortClauses count] > 0) {
    payload[@"sort"] = sortClauses;
  }
  NSArray *highlightFields = [self highlightFieldsForMetadata:metadata];
  if ([STTrimmedString(query) length] > 0 && [highlightFields count] > 0) {
    NSMutableDictionary *highlightConfig = [NSMutableDictionary dictionary];
    NSMutableDictionary *highlightFieldsConfig = [NSMutableDictionary dictionary];
    for (NSString *field in highlightFields) {
      highlightFieldsConfig[field] = @{};
    }
    highlightConfig[@"fields"] = highlightFieldsConfig;
    payload[@"highlight"] = highlightConfig;
  }
  NSMutableDictionary *aggregations = [NSMutableDictionary dictionary];
  for (NSDictionary *facet in STNormalizeArray(metadata[@"facetFields"])) {
    NSString *field = STLowerTrimmedString(facet[@"name"]);
    if ([field length] == 0) {
      continue;
    }
    NSUInteger facetLimit = [facet[@"limit"] respondsToSelector:@selector(unsignedIntegerValue)]
                                ? MAX((NSUInteger)1U, [facet[@"limit"] unsignedIntegerValue])
                                : 10U;
    aggregations[field] = @{
      @"terms" : @{
        @"field" : [self openSearchExactFieldNameForField:field metadata:metadata],
        @"size" : @(facetLimit),
      },
    };
  }
  if ([aggregations count] > 0) {
    payload[@"aggs"] = aggregations;
  }

  NSDictionary *response = [self jsonRequestWithMethod:@"POST"
                                                  path:path
                                               headers:[self openSearchHeaders]
                                                  body:payload
                                         allowNotFound:NO
                                               message:@"OpenSearch search failed"
                                                 error:error];
  if (response == nil) {
    return nil;
  }
  NSDictionary *body = STNormalizeDictionary(response[@"body"]);
  NSArray *hitsPayload = STNormalizeArray(STNormalizeDictionary(body[@"hits"])[@"hits"]);
  NSMutableArray *hits = [NSMutableArray array];
  for (NSDictionary *entry in hitsPayload) {
    NSDictionary *source = STNormalizeDictionary(entry[@"_source"]);
    NSString *recordID = STTrimmedString(source[@"recordID"]);
    if ([recordID length] == 0) {
      recordID = STTrimmedString(source[metadata[@"identifierField"] ?: @"id"]);
    }
    if ([recordID length] == 0) {
      continue;
    }
    NSMutableDictionary *hit = [NSMutableDictionary dictionary];
    hit[@"recordID"] = recordID;
    if ([entry[@"_score"] respondsToSelector:@selector(doubleValue)]) {
      hit[@"score"] = @([entry[@"_score"] doubleValue] * 10.0);
    }
    NSDictionary *highlight = STNormalizeDictionary(entry[@"highlight"]);
    NSMutableArray<NSString *> *highlightValues = [NSMutableArray array];
    NSMutableArray<NSString *> *matchedFields = [NSMutableArray array];
    for (NSString *field in [highlight allKeys]) {
      NSArray *values = STNormalizeArray(highlight[field]);
      if ([values count] == 0U) {
        continue;
      }
      [highlightValues addObjectsFromArray:values];
      [matchedFields addObject:field];
    }
    if ([highlightValues count] > 0) {
      hit[@"highlights"] = highlightValues;
    }
    if ([matchedFields count] > 0) {
      hit[@"matchedFields"] = matchedFields;
    }
    [hits addObject:hit];
  }
  NSMutableDictionary *facetDistribution = [NSMutableDictionary dictionary];
  for (NSString *field in [STNormalizeDictionary(body[@"aggregations"]) allKeys]) {
    NSDictionary *aggregation = STNormalizeDictionary(body[@"aggregations"])[field];
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    for (NSDictionary *bucket in STNormalizeArray(aggregation[@"buckets"])) {
      NSString *value = STTrimmedString(bucket[@"key_as_string"]);
      if ([value length] == 0) {
        value = STTrimmedString(bucket[@"key"]);
      }
      if ([value length] == 0) {
        continue;
      }
      counts[value] = bucket[@"doc_count"] ?: @0;
    }
    if ([counts count] > 0) {
      facetDistribution[field] = counts;
    }
  }
  id totalValue = STNormalizeDictionary(STNormalizeDictionary(body[@"hits"])[@"total"])[@"value"];
  if (![totalValue respondsToSelector:@selector(unsignedIntegerValue)]) {
    totalValue = STNormalizeDictionary(body[@"hits"])[@"total"];
  }
  return @{
    @"source" : @"live",
    @"hits" : hits ?: @[],
    @"total" : totalValue ?: @([hits count]),
    @"facetDistribution" : facetDistribution ?: @{},
    @"debug" : @{
      @"httpStatus" : response[@"status"] ?: @0,
      @"path" : path ?: @"",
      @"payload" : payload ?: @{},
    },
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

- (instancetype)initWithAdminRuntime:(id<ALNSearchOptionalAdminRuntime>)adminRuntime
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
  NSMutableArray *resultFields = [NSMutableArray array];
  NSMutableArray *facetFields = [NSMutableArray array];
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
    if (STBooleanValue(field[@"list"], NO) || STBooleanValue(field[@"detail"], NO)) {
      [resultFields addObject:name];
    }
  }
  for (NSDictionary *filter in STNormalizeArray(self.metadata[@"filters"])) {
    NSString *type = STLowerTrimmedString(filter[@"type"]);
    NSString *name = STLowerTrimmedString(filter[@"name"]);
    if ([name length] == 0) {
      continue;
    }
    if ([type isEqualToString:@"select"] || [type isEqualToString:@"checkboxes"]) {
      [facetFields addObject:@{
        @"name" : name,
        @"label" : filter[@"label"] ?: STTitleCaseIdentifier(name),
        @"type" : ([type length] > 0) ? type : @"string",
        @"choices" : STNormalizedChoiceArray(filter[@"choices"]),
        @"limit" : @10,
      }];
    }
  }
  NSDictionary *paths = STNormalizeDictionary(self.metadata[@"paths"]);
  return @{
    @"label" : self.metadata[@"label"] ?: STTitleCaseIdentifier(identifier),
    @"summary" : self.metadata[@"summary"] ?: @"",
    @"identifierField" : self.metadata[@"identifierField"] ?: @"id",
    @"primaryField" : self.metadata[@"primaryField"] ?: self.metadata[@"identifierField"] ?: @"id",
    @"indexedFields" : indexedFields,
    @"searchFields" : indexedFields,
    @"autocompleteFields" : @[ STLowerTrimmedString(self.metadata[@"primaryField"] ?: self.metadata[@"identifierField"] ?: @"id") ?: @"id" ],
    @"suggestionFields" : indexedFields,
    @"highlightFields" : indexedFields,
    @"resultFields" : STNormalizedStringArray(resultFields),
    @"facetFields" : facetFields,
    @"filters" : ([STNormalizeArray(self.metadata[@"filters"]) count] > 0) ? STNormalizeArray(self.metadata[@"filters"]) : @[],
    @"sorts" : ([STNormalizeArray(self.metadata[@"sorts"]) count] > 0) ? STNormalizeArray(self.metadata[@"sorts"]) : @[],
    @"defaultSort" : STLowerTrimmedString(self.metadata[@"defaultSort"]),
    @"pagination" : STNormalizeDictionary(self.metadata[@"pagination"]),
    @"queryPolicy" : @"public",
    @"queryRoles" : @[],
    @"queryModes" : @[ @"search", @"phrase", @"fuzzy", @"autocomplete" ],
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
    _engineStateByResource = [NSMutableDictionary dictionary];
    _pendingReplayOperationsByResource = [NSMutableDictionary dictionary];
    _statusByResource = [NSMutableDictionary dictionary];
    _generationHistoryByResource = [NSMutableDictionary dictionary];
    _reindexHistory = [NSMutableArray array];
    _recentQueries = [NSMutableArray array];
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

  if ([self.engine respondsToSelector:@selector(searchModuleConfigureWithRuntime:application:moduleConfig:error:)]) {
    if (![(id<ALNSearchEngine>)self.engine searchModuleConfigureWithRuntime:self
                                                               application:application
                                                                moduleConfig:moduleConfig
                                                                     error:error]) {
      return NO;
    }
  }

  [self.lock lock];
  [self.resourceDefinitionsByIdentifier removeAllObjects];
  [self.resourceMetadataByIdentifier removeAllObjects];
  [self.indexedDocumentsByResource removeAllObjects];
  [self.engineStateByResource removeAllObjects];
  [self.pendingReplayOperationsByResource removeAllObjects];
  [self.statusByResource removeAllObjects];
  [self.generationHistoryByResource removeAllObjects];
  [self.reindexHistory removeAllObjects];
  [self.recentQueries removeAllObjects];
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
  id<ALNSearchOptionalAdminRuntime> adminRuntime = STSharedAdminRuntime();
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
  self.engineStateByResource[identifier] = normalized[@"engineDescriptor"] ?: @{};
  self.pendingReplayOperationsByResource[identifier] = [NSMutableArray array];
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
    @"replayQueueDepth" : @0,
    @"lastReplayAt" : @0,
    @"lastReplayStatus" : @"idle",
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
  NSDictionary *persistedEngineState = STNormalizeDictionary(state[@"engineStateByResource"]);
  NSDictionary *persistedReplayState = STNormalizeDictionary(state[@"pendingReplayOperationsByResource"]);
  NSDictionary *persistedStatus = STNormalizeDictionary(state[@"statusByResource"]);
  NSDictionary *persistedGenerations = STNormalizeDictionary(state[@"generationHistoryByResource"]);
  for (NSString *identifier in self.resourceMetadataByIdentifier) {
    if ([persistedDocuments[identifier] isKindOfClass:[NSArray class]]) {
      self.indexedDocumentsByResource[identifier] = [persistedDocuments[identifier] copy];
    }
    if ([persistedEngineState[identifier] isKindOfClass:[NSDictionary class]]) {
      self.engineStateByResource[identifier] = [persistedEngineState[identifier] copy];
    }
    if ([persistedReplayState[identifier] isKindOfClass:[NSArray class]]) {
      self.pendingReplayOperationsByResource[identifier] =
          [NSMutableArray arrayWithArray:STNormalizeArray(persistedReplayState[identifier])];
    }
    if ([persistedStatus[identifier] isKindOfClass:[NSDictionary class]]) {
      NSMutableDictionary *status = [NSMutableDictionary dictionaryWithDictionary:self.statusByResource[identifier] ?: @{}];
      [status addEntriesFromDictionary:persistedStatus[identifier]];
      status[@"engine"] = self.engineIdentifier ?: @"ALNDefaultSearchEngine";
      status[@"indexState"] = STResolvedIndexState(status[@"indexState"]);
      status[@"replayQueueDepth"] = @([STNormalizeArray(self.pendingReplayOperationsByResource[identifier]) count]);
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
  NSArray *queries = STNormalizeArray(state[@"recentQueries"]);
  [self.recentQueries addObjectsFromArray:queries];
  while ([self.recentQueries count] > ALNSearchHistoryLimit) {
    [self.recentQueries removeObjectAtIndex:0];
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
    @"engineStateByResource" : [NSDictionary dictionaryWithDictionary:self.engineStateByResource ?: @{}],
    @"pendingReplayOperationsByResource" : [NSDictionary dictionaryWithDictionary:self.pendingReplayOperationsByResource ?: @{}],
    @"statusByResource" : [NSDictionary dictionaryWithDictionary:self.statusByResource ?: @{}],
    @"generationHistoryByResource" : generationHistory,
    @"reindexHistory" : [[NSArray alloc] initWithArray:self.reindexHistory copyItems:YES] ?: @[],
    @"recentQueries" : [[NSArray alloc] initWithArray:self.recentQueries copyItems:YES] ?: @[],
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
  NSDictionary *rawFieldTypes = STNormalizeDictionary(rawMetadata[@"fieldTypes"]);
  NSMutableDictionary *fieldTypes = [NSMutableDictionary dictionary];
  for (NSString *field in indexedFields) {
    NSString *type = STLowerTrimmedString(rawFieldTypes[field]);
    fieldTypes[field] = ([type length] > 0) ? type : @"string";
  }
  NSString *summaryField = STLowerTrimmedString(rawMetadata[@"summaryField"]);
  NSArray *searchFields = STNormalizedStringArray(rawMetadata[@"searchFields"]);
  if ([searchFields count] == 0) {
    searchFields = indexedFields;
  }
  NSArray *autocompleteFields = STNormalizedStringArray(rawMetadata[@"autocompleteFields"]);
  if ([autocompleteFields count] == 0) {
    autocompleteFields = @[ primaryField ];
  }
  NSArray *highlightFields = STNormalizedStringArray(rawMetadata[@"highlightFields"]);
  if ([highlightFields count] == 0) {
    highlightFields = searchFields;
  }
  NSArray *suggestionFields = STNormalizedStringArray(rawMetadata[@"suggestionFields"]);
  if ([suggestionFields count] == 0) {
    suggestionFields = searchFields;
  }
  NSMutableArray *resultFieldCandidates = [NSMutableArray array];
  [resultFieldCandidates addObjectsFromArray:STNormalizedStringArray(rawMetadata[@"resultFields"])];
  [resultFieldCandidates addObjectsFromArray:STNormalizedStringArray(rawMetadata[@"publicResultFields"])];
  if ([resultFieldCandidates count] == 0) {
    [resultFieldCandidates addObject:identifierField];
    if (![primaryField isEqualToString:identifierField]) {
      [resultFieldCandidates addObject:primaryField];
    }
    if ([summaryField length] > 0 &&
        ![summaryField isEqualToString:primaryField] &&
        ![summaryField isEqualToString:identifierField]) {
      [resultFieldCandidates addObject:summaryField];
    }
  }
  NSArray *resultFields = STNormalizedStringArray(resultFieldCandidates);
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
      filterType = STLowerTrimmedString(rawFieldTypes[name]);
    }
    if ([filterType length] == 0) {
      filterType = @"string";
    }
    fieldTypes[name] = filterType;
    [filters addObject:@{
      @"name" : name,
      @"label" : entry[@"label"] ?: STTitleCaseIdentifier(name),
      @"type" : filterType,
      @"choices" : STNormalizedChoiceArray(entry[@"choices"]),
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
    NSString *sortType = STLowerTrimmedString(entry[@"type"]);
    if ([sortType length] == 0) {
      sortType = STLowerTrimmedString(rawFieldTypes[name]);
    }
    if ([sortType length] == 0) {
      sortType = @"string";
    }
    fieldTypes[name] = sortType;
    [sorts addObject:@{
      @"name" : name,
      @"label" : entry[@"label"] ?: STTitleCaseIdentifier(name),
      @"default" : @(sortDefault),
      @"direction" : direction,
      @"type" : sortType,
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
  NSMutableOrderedSet<NSNumber *> *pageSizes = [NSMutableOrderedSet orderedSet];
  for (id entry in STNormalizeArray(rawPagination[@"pageSizes"])) {
    if ([entry respondsToSelector:@selector(unsignedIntegerValue)] && [entry unsignedIntegerValue] > 0U) {
      [pageSizes addObject:@([entry unsignedIntegerValue])];
    }
  }
  for (id entry in STNormalizeArray(rawMetadata[@"pageSizes"])) {
    if ([entry respondsToSelector:@selector(unsignedIntegerValue)] && [entry unsignedIntegerValue] > 0U) {
      [pageSizes addObject:@([entry unsignedIntegerValue])];
    }
  }
  [pageSizes addObject:@(defaultLimit)];
  [pageSizes addObject:@(maxLimit)];
  NSArray *normalizedPageSizes = [[pageSizes array] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *lhs, NSNumber *rhs) {
    return [lhs compare:rhs];
  }];
  NSMutableArray *facetFields = [NSMutableArray array];
  NSArray *rawFacetFields = ([rawMetadata[@"facetFields"] isKindOfClass:[NSArray class]] ? rawMetadata[@"facetFields"] : rawMetadata[@"facets"]);
  for (id rawFacet in STNormalizeArray(rawFacetFields)) {
    NSString *name = @"";
    NSString *label = @"";
    NSString *facetType = @"string";
    NSArray *choices = @[];
    NSUInteger facetLimit = 10U;
    if ([rawFacet isKindOfClass:[NSDictionary class]]) {
      name = STLowerTrimmedString(rawFacet[@"name"]);
      label = STTrimmedString(rawFacet[@"label"]);
      facetType = STLowerTrimmedString(rawFacet[@"type"]);
      choices = STNormalizedChoiceArray(rawFacet[@"choices"]);
      if ([rawFacet[@"limit"] respondsToSelector:@selector(unsignedIntegerValue)]) {
        facetLimit = MAX((NSUInteger)1U, [rawFacet[@"limit"] unsignedIntegerValue]);
      }
    } else {
      name = STLowerTrimmedString(rawFacet);
    }
    if ([name length] == 0) {
      continue;
    }
    if ([label length] == 0) {
      label = STTitleCaseIdentifier(name);
    }
    if ([facetType length] == 0) {
      facetType = STLowerTrimmedString(rawFieldTypes[name]);
    }
    if ([facetType length] == 0) {
      facetType = @"string";
    }
    fieldTypes[name] = facetType;
    [facetFields addObject:@{
      @"name" : name,
      @"label" : label,
      @"type" : facetType,
      @"choices" : choices ?: @[],
      @"limit" : @(facetLimit),
    }];
  }
  if ([facetFields count] == 0) {
    for (NSDictionary *filter in filters) {
      if ([STNormalizeArray(filter[@"choices"]) count] == 0) {
        continue;
      }
      [facetFields addObject:@{
        @"name" : filter[@"name"] ?: @"",
        @"label" : filter[@"label"] ?: STTitleCaseIdentifier(filter[@"name"]),
        @"type" : filter[@"type"] ?: @"string",
        @"choices" : filter[@"choices"] ?: @[],
        @"limit" : @10,
      }];
    }
  }
  id rawQueryPolicy = rawMetadata[@"queryPolicy"];
  if (rawQueryPolicy == nil || rawQueryPolicy == [NSNull null] ||
      (![rawQueryPolicy isKindOfClass:[NSDictionary class]] && [STTrimmedString(rawQueryPolicy) length] == 0)) {
    rawQueryPolicy = rawMetadata[@"queryAccess"];
  }
  NSString *queryPolicy = @"";
  NSArray *queryRoles = @[];
  if ([rawQueryPolicy isKindOfClass:[NSDictionary class]]) {
    queryPolicy = STLowerTrimmedString(rawQueryPolicy[@"policy"]);
    queryRoles = STNormalizedStringArray(rawQueryPolicy[@"roles"]);
  } else {
    queryPolicy = STLowerTrimmedString(rawQueryPolicy);
    queryRoles = STNormalizedStringArray(rawMetadata[@"queryRoles"]);
  }
  if ([queryPolicy length] == 0) {
    queryPolicy = ([queryRoles count] > 0) ? @"role_gated" : @"public";
  }
  NSSet *allowedQueryPolicies = [NSSet setWithArray:@[ @"public", @"authenticated", @"role_gated", @"predicate" ]];
  if (![allowedQueryPolicies containsObject:queryPolicy]) {
    queryPolicy = ([queryRoles count] > 0) ? @"role_gated" : @"public";
  }
  NSArray *queryModes = STNormalizedStringArray(rawMetadata[@"queryModes"]);
  if ([queryModes count] == 0) {
    queryModes = @[ @"autocomplete", @"fuzzy", @"phrase", @"search" ];
  }
  NSString *tenantField = STLowerTrimmedString(rawMetadata[@"tenantField"]);
  NSString *tenantContextKey = STTrimmedString(rawMetadata[@"tenantContextKey"]);
  NSString *tenantClaim = STTrimmedString(rawMetadata[@"tenantClaim"]);
  if ([tenantClaim length] == 0) {
    tenantClaim = @"tenant";
  }
  NSString *softDeleteField = STLowerTrimmedString(rawMetadata[@"softDeleteField"]);
  NSString *archivedField = STLowerTrimmedString(rawMetadata[@"archivedField"]);
  NSArray *softDeleteHiddenValues = STTrimmedUniqueStringArray(rawMetadata[@"softDeleteHiddenValues"]);
  if ([softDeleteHiddenValues count] == 0 && [softDeleteField length] > 0) {
    softDeleteHiddenValues = @[ @"1", @"true", @"yes" ];
  }
  NSArray *softDeleteVisibleValues = STTrimmedUniqueStringArray(rawMetadata[@"softDeleteVisibleValues"]);
  NSArray *archivedHiddenValues = STTrimmedUniqueStringArray(rawMetadata[@"archivedHiddenValues"]);
  if ([archivedHiddenValues count] == 0 && [archivedField length] > 0) {
    archivedHiddenValues = @[ @"1", @"true", @"yes", @"archived" ];
  }
  NSArray *archivedVisibleValues = STTrimmedUniqueStringArray(rawMetadata[@"archivedVisibleValues"]);
  NSArray *internalFilterFields = @[ tenantField ?: @"", softDeleteField ?: @"", archivedField ?: @"" ];
  for (NSString *internalField in internalFilterFields) {
    if ([internalField length] == 0) {
      continue;
    }
    BOOL exists = NO;
    for (NSDictionary *entry in filters) {
      if ([STLowerTrimmedString(entry[@"name"]) isEqualToString:internalField]) {
        exists = YES;
        break;
      }
    }
    if (exists) {
      continue;
    }
    NSString *type = STLowerTrimmedString(rawFieldTypes[internalField]);
    if ([type length] == 0) {
      type = @"string";
    }
    fieldTypes[internalField] = type;
    [filters addObject:@{
      @"name" : internalField,
      @"label" : STTitleCaseIdentifier(internalField),
      @"type" : type,
      @"choices" : @[],
      @"operators" : @[ @"eq", @"in" ],
      @"internal" : @YES,
    }];
  }
  NSDictionary *rawSyncPolicy = STNormalizeDictionary(rawMetadata[@"syncPolicy"]);
  NSUInteger bulkBatchSize = [rawSyncPolicy[@"bulkBatchSize"] respondsToSelector:@selector(unsignedIntegerValue)]
                                 ? MAX((NSUInteger)1U, [rawSyncPolicy[@"bulkBatchSize"] unsignedIntegerValue])
                                 : 250U;
  NSUInteger replayLimit = [rawSyncPolicy[@"replayLimit"] respondsToSelector:@selector(unsignedIntegerValue)]
                               ? MAX((NSUInteger)1U, [rawSyncPolicy[@"replayLimit"] unsignedIntegerValue])
                               : 20U;
  NSString *softDeleteMode = STLowerTrimmedString(rawSyncPolicy[@"softDeleteMode"]);
  if (![softDeleteMode isEqualToString:@"delete"]) {
    softDeleteMode = ([softDeleteField length] > 0) ? @"filter" : @"ignore";
  }
  NSDictionary *engineDescriptor = STNormalizeDictionary(rawMetadata[@"engineDescriptor"]);
  NSString *cursorField = STLowerTrimmedString(rawPagination[@"cursorField"]);
  if ([cursorField length] == 0) {
    cursorField = identifierField;
  }
  NSMutableArray *promotions = [NSMutableArray array];
  NSArray *rawPromotions = ([rawMetadata[@"promotions"] isKindOfClass:[NSArray class]] ? rawMetadata[@"promotions"] : rawMetadata[@"promotedResults"]);
  for (NSDictionary *entry in STNormalizeArray(rawPromotions)) {
    NSArray *queries = [entry[@"queries"] isKindOfClass:[NSArray class]]
                           ? STNormalizedStringArray(entry[@"queries"])
                           : ([STTrimmedString(entry[@"query"]) length] > 0 ? @[ STLowerTrimmedString(entry[@"query"]) ] : @[]);
    NSArray *recordIDs = [entry[@"recordIDs"] isKindOfClass:[NSArray class]]
                             ? STTrimmedUniqueStringArray(entry[@"recordIDs"])
                             : ([entry[@"identifiers"] isKindOfClass:[NSArray class]] ? STTrimmedUniqueStringArray(entry[@"identifiers"]) : @[]);
    if ([queries count] == 0 || [recordIDs count] == 0) {
      continue;
    }
    [promotions addObject:@{
      @"queries" : queries,
      @"recordIDs" : recordIDs,
      @"label" : ([STTrimmedString(entry[@"label"]) length] > 0) ? STTrimmedString(entry[@"label"]) : @"Promoted",
    }];
  }
  return @{
    @"identifier" : identifier,
    @"label" : label,
    @"summary" : summary ?: @"",
    @"identifierField" : identifierField,
    @"primaryField" : primaryField,
    @"summaryField" : summaryField ?: @"",
    @"indexedFields" : indexedFields,
    @"searchFields" : searchFields,
    @"autocompleteFields" : autocompleteFields,
    @"highlightFields" : highlightFields,
    @"suggestionFields" : suggestionFields,
    @"resultFields" : resultFields,
    @"facetFields" : facetFields,
    @"queryModes" : queryModes,
    @"queryPolicy" : queryPolicy,
    @"queryRoles" : queryRoles ?: @[],
    @"weightedFields" : weightedFields,
    @"fieldTypes" : fieldTypes,
    @"filters" : filters,
    @"sorts" : sorts,
    @"defaultSort" : defaultSort ?: @"",
    @"pagination" : @{
      @"defaultLimit" : @(defaultLimit),
      @"maxLimit" : @(maxLimit),
      @"pageSizes" : normalizedPageSizes ?: @[ @(defaultLimit), @(maxLimit) ],
      @"cursorField" : cursorField ?: identifierField,
    },
    @"visibility" : @{
      @"tenantField" : tenantField ?: @"",
      @"tenantContextKey" : tenantContextKey ?: @"",
      @"tenantClaim" : tenantClaim ?: @"tenant",
      @"softDeleteField" : softDeleteField ?: @"",
      @"softDeleteHiddenValues" : softDeleteHiddenValues ?: @[],
      @"softDeleteVisibleValues" : softDeleteVisibleValues ?: @[],
      @"archivedField" : archivedField ?: @"",
      @"archivedHiddenValues" : archivedHiddenValues ?: @[],
      @"archivedVisibleValues" : archivedVisibleValues ?: @[],
    },
    @"syncPolicy" : @{
      @"bulkBatchSize" : @(bulkBatchSize),
      @"replayLimit" : @(replayLimit),
      @"softDeleteMode" : softDeleteMode ?: @"ignore",
      @"paused" : @(STBooleanValue(rawSyncPolicy[@"paused"], NO)),
      @"pauseReason" : STTrimmedString(rawSyncPolicy[@"pauseReason"]),
      @"conditionalField" : STLowerTrimmedString(rawSyncPolicy[@"conditionalField"]),
      @"conditionalValue" : STTrimmedString(rawSyncPolicy[@"conditionalValue"]),
      @"conditionalValues" : STTrimmedUniqueStringArray(rawSyncPolicy[@"conditionalValues"]),
    },
    @"engineDescriptor" : engineDescriptor ?: @{},
    @"promotions" : promotions ?: @[],
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
    @"recentQueryCount" : @([self.recentQueries count]),
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
  if (![resourceIdentifier isEqualToString:@"*"]) {
    NSDictionary *metadata = [self resourceMetadataForIdentifier:resourceIdentifier] ?: @{};
    NSDictionary *syncPolicy = STNormalizeDictionary(metadata[@"syncPolicy"]);
    if (STBooleanValue(syncPolicy[@"paused"], NO)) {
      if (error != NULL) {
        *error = STError(ALNSearchModuleErrorValidationFailed,
                         @"search indexing is paused for this resource",
                         @{ @"resource" : resourceIdentifier ?: @"", @"reason" : STTrimmedString(syncPolicy[@"pauseReason"]) });
      }
      return nil;
    }
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
  NSDictionary *metadata = [self resourceMetadataForIdentifier:resourceIdentifier] ?: @{};
  NSDictionary *syncPolicy = STNormalizeDictionary(metadata[@"syncPolicy"]);
  if (STBooleanValue(syncPolicy[@"paused"], NO)) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorValidationFailed,
                       @"search indexing is paused for this resource",
                       @{ @"resource" : resourceIdentifier ?: @"", @"reason" : STTrimmedString(syncPolicy[@"pauseReason"]) });
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
  NSDictionary *engineState = [self.engineStateByResource[identifier] isKindOfClass:[NSDictionary class]] ? self.engineStateByResource[identifier] : @{};
  NSDictionary *status = [self.statusByResource[identifier] isKindOfClass:[NSDictionary class]] ? self.statusByResource[identifier] : @{};
  [self.lock unlock];
  return @{
    @"generation" : [status[@"activeGeneration"] respondsToSelector:@selector(unsignedIntegerValue)]
                        ? @([status[@"activeGeneration"] unsignedIntegerValue])
                        : @0,
    @"documents" : documents ?: @[],
    @"engineState" : engineState ?: @{},
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
  status[@"syncPolicy"] = metadata[@"syncPolicy"] ?: existing[@"syncPolicy"] ?: @{};
  status[@"visibility"] = metadata[@"visibility"] ?: existing[@"visibility"] ?: @{};
  status[@"engineDescriptor"] = self.engineStateByResource[identifier] ?: metadata[@"engineDescriptor"] ?: existing[@"engineDescriptor"] ?: @{};
  status[@"replayQueueDepth"] = @([STNormalizeArray(self.pendingReplayOperationsByResource[identifier]) count]);
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
  NSDictionary *syncPolicy = STNormalizeDictionary(metadata[@"syncPolicy"]);
  if (STBooleanValue(syncPolicy[@"paused"], NO)) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorValidationFailed,
                       @"search indexing is paused for this resource",
                       @{ @"resource" : resourceIdentifier ?: @"", @"reason" : STTrimmedString(syncPolicy[@"pauseReason"]) });
    }
    return nil;
  }
  id<ALNSearchResourceDefinition> definition = nil;
  NSUInteger batchSize = [syncPolicy[@"bulkBatchSize"] respondsToSelector:@selector(unsignedIntegerValue)]
                             ? MAX((NSUInteger)1U, [syncPolicy[@"bulkBatchSize"] unsignedIntegerValue])
                             : 250U;
  NSTimeInterval startedAt = [[NSDate date] timeIntervalSince1970];
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

  NSDictionary *snapshot = nil;
  __block NSUInteger enumeratedDocumentCount = 0U;
  __block NSUInteger importedBatchCount = 0U;
  BOOL supportsStreamingBuild = [self.engine respondsToSelector:@selector(searchModuleBeginBuildForMetadata:generation:error:)] &&
                                [self.engine respondsToSelector:@selector(searchModuleAppendBuildRecords:metadata:state:error:)] &&
                                [self.engine respondsToSelector:@selector(searchModuleFinalizeBuildState:metadata:error:)];
  if (supportsStreamingBuild) {
    id buildState = [(id<ALNSearchEngine>)self.engine searchModuleBeginBuildForMetadata:metadata generation:generation error:error];
    if (buildState == nil) {
      return nil;
    }
    if (![self enumerateIndexableRecordsForDefinition:definition
                                             metadata:metadata
                                            batchSize:batchSize
                                           usingBlock:^BOOL(NSArray<NSDictionary *> *records, NSError **batchError) {
                                             if ([records count] == 0U) {
                                               return YES;
                                             }
                                             enumeratedDocumentCount += [records count];
                                             importedBatchCount += 1U;
                                             return [(id<ALNSearchEngine>)self.engine searchModuleAppendBuildRecords:records
                                                                                                          metadata:metadata
                                                                                                             state:buildState
                                                                                                             error:batchError];
                                           }
                                                error:error]) {
      return nil;
    }
    snapshot = [(id<ALNSearchEngine>)self.engine searchModuleFinalizeBuildState:buildState metadata:metadata error:error];
  } else {
    NSError *loadError = nil;
    NSArray *records = [self recordsForDefinition:definition metadata:metadata batchSize:batchSize error:&loadError];
    if (records == nil) {
      if (error != NULL) {
        *error = loadError ?: STError(ALNSearchModuleErrorExecutionFailed,
                                      @"search resource failed to build documents",
                                      @{ @"resource" : resourceIdentifier });
      }
      return nil;
    }
    enumeratedDocumentCount = [records count];
    importedBatchCount = (enumeratedDocumentCount == 0U) ? 0U : ((enumeratedDocumentCount + batchSize - 1U) / batchSize);
    snapshot = [self.engine searchModuleSnapshotForMetadata:metadata
                                                    records:records
                                                 generation:generation
                                                      error:error];
  }
  if (snapshot == nil) {
    return nil;
  }

  NSTimeInterval indexedAt = [[NSDate date] timeIntervalSince1970];
  NSUInteger documentCount = [snapshot[@"documentCount"] respondsToSelector:@selector(unsignedIntegerValue)]
                                 ? [snapshot[@"documentCount"] unsignedIntegerValue]
                                 : enumeratedDocumentCount;
  NSUInteger batchCount = (importedBatchCount > 0U || documentCount == 0U)
                              ? importedBatchCount
                              : ((documentCount + batchSize - 1U) / batchSize);
  double duration = MAX(0.001, indexedAt - startedAt);
  NSDictionary *replay = @{};
  [self.lock lock];
  self.indexedDocumentsByResource[resourceIdentifier] = STNormalizeArray(snapshot[@"documents"]);
  self.engineStateByResource[resourceIdentifier] =
      [snapshot[@"engineState"] isKindOfClass:[NSDictionary class]] ? snapshot[@"engineState"] : (metadata[@"engineDescriptor"] ?: @{});
  status = [self mutableStatusForResourceIdentifier:resourceIdentifier metadata:metadata];
  status[@"documentCount"] = @(documentCount);
  status[@"activeGeneration"] = snapshot[@"generation"] ?: @(generation);
  status[@"buildingGeneration"] = @0;
  status[@"generationCount"] = @([STNormalizeArray(self.generationHistoryByResource[resourceIdentifier]) count] + 1U);
  status[@"lastIndexedAt"] = @(indexedAt);
  status[@"lastError"] = @"";
  status[@"lastFailureAt"] = @0;
  status[@"lastSyncAt"] = @(indexedAt);
  status[@"lastSyncOperation"] = @"full";
  status[@"lastReplayAt"] = @(indexedAt);
  status[@"lastReplayStatus"] = ([replay[@"remaining"] unsignedIntegerValue] == 0U) ? @"drained" : @"pending";
  status[@"indexState"] = @"ready";
  status[@"bulkImport"] = @{
    @"batchSize" : @(batchSize),
    @"batchCount" : @(batchCount),
    @"importedBatches" : @(batchCount),
    @"importedDocuments" : @(documentCount),
    @"durationSeconds" : @(duration),
    @"throughputPerSecond" : @(((double)documentCount) / duration),
  };
  self.statusByResource[resourceIdentifier] = status;
  [self appendGenerationEntry:@{
    @"generation" : snapshot[@"generation"] ?: @(generation),
    @"activatedAt" : @(indexedAt),
    @"documentCount" : @(documentCount),
    @"mode" : @"full",
    @"status" : @"activated",
  }
               forResourceIdentifier:resourceIdentifier];
  [self recordHistoryEntry:@{
    @"resource" : resourceIdentifier,
    @"documentCount" : @(documentCount),
    @"indexedAt" : @(indexedAt),
    @"jobID" : status[@"lastJobID"] ?: @"",
    @"mode" : @"full",
    @"status" : @"succeeded",
    @"generation" : snapshot[@"generation"] ?: @(generation),
    @"replayed" : replay[@"replayed"] ?: @0,
    @"replayRemaining" : replay[@"remaining"] ?: @0,
  }];
  [self.lock unlock];
  if (![self persistStateWithError:error]) {
    return nil;
  }
  replay = [self drainReplayOperationsForResourceIdentifier:resourceIdentifier mode:@"full" error:NULL] ?: @{};
  [self.lock lock];
  status = [self mutableStatusForResourceIdentifier:resourceIdentifier metadata:metadata];
  status[@"lastReplayAt"] = @([[NSDate date] timeIntervalSince1970]);
  status[@"lastReplayStatus"] = ([replay[@"remaining"] unsignedIntegerValue] == 0U) ? @"drained" : @"pending";
  self.statusByResource[resourceIdentifier] = status;
  [self.lock unlock];
  (void)[self persistStateWithError:NULL];

  return @{
    @"identifier" : resourceIdentifier,
    @"documentCount" : @(documentCount),
    @"generation" : snapshot[@"generation"] ?: @(generation),
    @"mode" : @"full",
    @"bulkImport" : status[@"bulkImport"] ?: @{},
    @"replay" : replay ?: @{},
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
  NSDictionary *syncPolicy = STNormalizeDictionary(metadata[@"syncPolicy"]);
  if (STBooleanValue(syncPolicy[@"paused"], NO)) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorValidationFailed,
                       @"search indexing is paused for this resource",
                       @{ @"resource" : resourceIdentifier ?: @"", @"reason" : STTrimmedString(syncPolicy[@"pauseReason"]) });
    }
    return nil;
  }
  NSString *normalizedOperation = STLowerTrimmedString(operation);
  if ([normalizedOperation length] == 0) {
    normalizedOperation = @"upsert";
  }
  id<ALNSearchResourceDefinition> definition = [self resourceDefinitionForIdentifier:resourceIdentifier];
  if (![normalizedOperation isEqualToString:@"delete"] &&
      ![self record:record ?: @{} isIndexableForMetadata:metadata definition:definition error:error]) {
    if (error != NULL && *error != nil) {
      return nil;
    }
    normalizedOperation = @"delete";
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
  self.engineStateByResource[resourceIdentifier] =
      [updated[@"engineState"] isKindOfClass:[NSDictionary class]] ? updated[@"engineState"] : (self.engineStateByResource[resourceIdentifier] ?: @{});
  NSMutableDictionary *status = [self mutableStatusForResourceIdentifier:resourceIdentifier metadata:metadata];
  status[@"documentCount"] = updated[@"documentCount"] ?: @0;
  status[@"activeGeneration"] = updated[@"generation"] ?: snapshot[@"generation"] ?: @1;
  status[@"buildingGeneration"] = @0;
  status[@"lastError"] = @"";
  status[@"lastFailureAt"] = @0;
  status[@"lastSyncAt"] = @(syncedAt);
  status[@"lastSyncOperation"] = normalizedOperation;
  status[@"lastMode"] = @"incremental";
  status[@"lastReplayStatus"] = ([STNormalizeArray(self.pendingReplayOperationsByResource[resourceIdentifier]) count] > 0) ? @"pending" : @"idle";
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
    @"engineState" : self.engineStateByResource[resourceIdentifier] ?: @{},
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
      if ([mode isEqualToString:@"incremental"]) {
        [self enqueueReplayOperation:@{
          @"operation" : STLowerTrimmedString(payload[@"operation"]),
          @"record" : STNormalizeDictionary(payload[@"record"]),
        }
              forResourceIdentifier:target
                           metadata:metadata];
        status[@"lastReplayStatus"] = @"pending";
        status[@"replayQueueDepth"] = @([STNormalizeArray(self.pendingReplayOperationsByResource[target]) count]);
      }
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
    if ([mode isEqualToString:@"incremental"]) {
      NSDictionary *replay = [self drainReplayOperationsForResourceIdentifier:target mode:@"incremental" error:NULL] ?: @{};
      NSMutableDictionary *decorated = [NSMutableDictionary dictionaryWithDictionary:summary ?: @{}];
      decorated[@"replay"] = replay;
      summary = decorated;
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
  return [self searchQuery:query
        resourceIdentifier:resourceIdentifier
                   filters:filters
                      sort:sort
                     limit:limit
                    offset:offset
              queryOptions:nil
                     error:error];
}

- (NSDictionary *)searchQuery:(NSString *)query
           resourceIdentifier:(NSString *)resourceIdentifier
                      filters:(NSDictionary *)filters
                         sort:(NSString *)sort
                        limit:(NSUInteger)limit
                       offset:(NSUInteger)offset
                 queryOptions:(NSDictionary *)queryOptions
                        error:(NSError **)error {
  return [self searchQuery:query
        resourceIdentifier:resourceIdentifier
  allowedResourceIdentifiers:nil
                   filters:filters
                      sort:sort
                     limit:limit
                    offset:offset
              queryOptions:queryOptions
                     error:error];
}

- (id<ALNSearchResourceDefinition>)resourceDefinitionForIdentifier:(NSString *)identifier {
  [self.lock lock];
  id<ALNSearchResourceDefinition> definition = self.resourceDefinitionsByIdentifier[STLowerTrimmedString(identifier)];
  [self.lock unlock];
  return definition;
}

- (NSArray<NSString *> *)resourceIdentifiersFromMetadataArray:(NSArray<NSDictionary *> *)resourceMetadata {
  NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
  for (NSDictionary *metadata in STNormalizeArray(resourceMetadata)) {
    NSString *identifier = STLowerTrimmedString(metadata[@"identifier"]);
    if ([identifier length] == 0 || [identifiers containsObject:identifier]) {
      continue;
    }
    [identifiers addObject:identifier];
  }
  return [identifiers copy];
}

- (void)recordRecentQuery:(NSDictionary *)entry {
  if (![entry isKindOfClass:[NSDictionary class]]) {
    return;
  }
  [self.recentQueries addObject:entry];
  while ([self.recentQueries count] > ALNSearchHistoryLimit) {
    [self.recentQueries removeObjectAtIndex:0];
  }
}

- (NSDictionary *)additionalQueryFiltersForResourceMetadata:(NSDictionary *)metadata
                                                    context:(ALNContext *)context
                                                      error:(NSError **)error {
  NSMutableDictionary *filters = [NSMutableDictionary dictionary];
  NSDictionary *visibility = STNormalizeDictionary(metadata[@"visibility"]);
  NSString *tenantField = STLowerTrimmedString(visibility[@"tenantField"]);
  NSString *tenantClaim = STTrimmedString(visibility[@"tenantClaim"]);
  if ([tenantClaim length] == 0) {
    tenantClaim = @"tenant";
  }
  NSString *tenantContextKey = STTrimmedString(visibility[@"tenantContextKey"]);
  if ([tenantField length] > 0) {
    NSString *tenantValue = @"";
    NSDictionary *claims = [context authClaims];
    if ([claims[tenantClaim] isKindOfClass:[NSString class]]) {
      tenantValue = STTrimmedString(claims[tenantClaim]);
    }
    if ([tenantValue length] == 0 && [tenantContextKey length] > 0 &&
        [context.stash[tenantContextKey] isKindOfClass:[NSString class]]) {
      tenantValue = STTrimmedString(context.stash[tenantContextKey]);
    }
    if ([tenantValue length] == 0) {
      if (error != NULL) {
        *error = STError([[context authSubject] length] > 0 ? ALNSearchModuleErrorForbidden : ALNSearchModuleErrorUnauthorized,
                         @"this search resource requires tenant scoping",
                         @{ @"resource" : metadata[@"identifier"] ?: @"", @"tenantField" : tenantField ?: @"" });
      }
      return nil;
    }
    filters[tenantField] = tenantValue;
  }

  NSString *softDeleteField = STLowerTrimmedString(visibility[@"softDeleteField"]);
  NSArray *softDeleteHiddenValues = STTrimmedUniqueStringArray(visibility[@"softDeleteHiddenValues"]);
  if ([softDeleteField length] > 0 && [softDeleteHiddenValues count] > 0) {
    NSArray *visibleValues = [self visibleFilterValuesForField:softDeleteField
                                                      metadata:metadata
                                                    visibility:visibility
                                               explicitKeyName:@"softDeleteVisibleValues"
                                                  hiddenValues:softDeleteHiddenValues
                                                         error:error];
    if (visibleValues == nil && error != NULL && *error != nil) {
      return nil;
    }
    if ([visibleValues count] > 0) {
      filters[[NSString stringWithFormat:@"%@__in", softDeleteField]] = visibleValues;
    }
  }

  NSString *archivedField = STLowerTrimmedString(visibility[@"archivedField"]);
  NSArray *archivedHiddenValues = STTrimmedUniqueStringArray(visibility[@"archivedHiddenValues"]);
  if ([archivedField length] > 0 && [archivedHiddenValues count] > 0) {
    NSArray *visibleValues = [self visibleFilterValuesForField:archivedField
                                                      metadata:metadata
                                                    visibility:visibility
                                               explicitKeyName:@"archivedVisibleValues"
                                                  hiddenValues:archivedHiddenValues
                                                         error:error];
    if (visibleValues == nil && error != NULL && *error != nil) {
      return nil;
    }
    if ([visibleValues count] > 0) {
      filters[[NSString stringWithFormat:@"%@__in", archivedField]] = visibleValues;
    }
  }

  id<ALNSearchResourceDefinition> definition = [self resourceDefinitionForIdentifier:metadata[@"identifier"]];
  if (definition != nil &&
      [definition respondsToSelector:@selector(searchModuleAdditionalFiltersForContext:metadata:runtime:error:)]) {
    NSDictionary *custom = [(id<ALNSearchResourceDefinition>)definition searchModuleAdditionalFiltersForContext:context
                                                                                                       metadata:metadata
                                                                                                        runtime:self
                                                                                                          error:error];
    if (custom == nil && error != NULL && *error != nil) {
      return nil;
    }
    [filters addEntriesFromDictionary:STNormalizeDictionary(custom)];
  }
  return filters;
}

- (NSArray<NSString *> *)visibleFilterValuesForField:(NSString *)field
                                            metadata:(NSDictionary *)metadata
                                          visibility:(NSDictionary *)visibility
                                     explicitKeyName:(NSString *)explicitKeyName
                                        hiddenValues:(NSArray<NSString *> *)hiddenValues
                                               error:(NSError **)error {
  NSArray<NSString *> *explicitValues = STTrimmedUniqueStringArray(visibility[explicitKeyName]);
  if ([explicitValues count] > 0) {
    return explicitValues;
  }

  NSMutableSet<NSString *> *hiddenSet = [NSMutableSet set];
  for (NSString *value in hiddenValues ?: @[]) {
    [hiddenSet addObject:[STLowerTrimmedString(value) lowercaseString]];
  }

  for (NSDictionary *entry in STNormalizeArray(metadata[@"filters"])) {
    if (![STLowerTrimmedString(entry[@"name"]) isEqualToString:STLowerTrimmedString(field)]) {
      continue;
    }
    NSMutableArray<NSString *> *derived = [NSMutableArray array];
    for (NSDictionary *choice in STNormalizeArray(entry[@"choices"])) {
      NSString *value = STTrimmedString(choice[@"value"]);
      if ([value length] == 0 || [hiddenSet containsObject:[STLowerTrimmedString(value) lowercaseString]]) {
        continue;
      }
      [derived addObject:value];
    }
    if ([derived count] > 0) {
      return [derived copy];
    }
    break;
  }

  NSString *fieldType = STLowerTrimmedString(STNormalizeDictionary(metadata[@"fieldTypes"])[STLowerTrimmedString(field)]);
  if (STSearchFieldTypeIsBoolean(fieldType)) {
    return @[ @"0", @"false", @"no" ];
  }

  if ([hiddenValues count] > 0 && error != NULL) {
    *error = STError(ALNSearchModuleErrorInvalidConfiguration,
                     [NSString stringWithFormat:@"visibility rules for %@ require explicit visible values or filter choices", field ?: @"field"],
                     @{
                       @"resource" : metadata[@"identifier"] ?: @"",
                       @"field" : field ?: @"",
                     });
  }
  return nil;
}

- (BOOL)record:(NSDictionary *)record
  isIndexableForMetadata:(NSDictionary *)metadata
              definition:(id<ALNSearchResourceDefinition>)definition
                   error:(NSError **)error {
  NSDictionary *syncPolicy = STNormalizeDictionary(metadata[@"syncPolicy"]);
  NSString *conditionalField = STLowerTrimmedString(syncPolicy[@"conditionalField"]);
  NSArray *conditionalValues = STTrimmedUniqueStringArray(syncPolicy[@"conditionalValues"]);
  NSString *conditionalValue = STTrimmedString(syncPolicy[@"conditionalValue"]);
  if ([conditionalValues count] == 0 && [conditionalValue length] > 0) {
    conditionalValues = @[ conditionalValue ];
  }
  if ([conditionalField length] > 0 && [conditionalValues count] > 0) {
    NSString *actual = STTrimmedString(record[conditionalField]);
    if (![conditionalValues containsObject:actual]) {
      return NO;
    }
  }

  NSDictionary *visibility = STNormalizeDictionary(metadata[@"visibility"]);
  NSString *softDeleteField = STLowerTrimmedString(visibility[@"softDeleteField"]);
  NSArray *softDeleteHiddenValues = STTrimmedUniqueStringArray(visibility[@"softDeleteHiddenValues"]);
  NSString *softDeleteMode = STLowerTrimmedString(syncPolicy[@"softDeleteMode"]);
  if ([softDeleteMode isEqualToString:@"delete"] && [softDeleteField length] > 0 && [softDeleteHiddenValues count] > 0) {
    NSString *actual = [STTrimmedString(record[softDeleteField]) lowercaseString];
    for (NSString *entry in softDeleteHiddenValues) {
      if ([[entry lowercaseString] isEqualToString:actual]) {
        return NO;
      }
    }
  }

  if (definition != nil &&
      [definition respondsToSelector:@selector(searchModuleAllowsIndexingRecord:metadata:runtime:error:)]) {
    return [(id<ALNSearchResourceDefinition>)definition searchModuleAllowsIndexingRecord:record
                                                                                metadata:metadata
                                                                                 runtime:self
                                                                                   error:error];
  }
  return YES;
}

- (BOOL)enumerateIndexableRecordsForDefinition:(id<ALNSearchResourceDefinition>)definition
                                      metadata:(NSDictionary *)metadata
                                     batchSize:(NSUInteger)batchSize
                                    usingBlock:(ALNSearchResourceBatchConsumer)consumer
                                         error:(NSError **)error {
  if (consumer == nil) {
    return YES;
  }
  NSUInteger resolvedBatchSize = MAX((NSUInteger)1U, batchSize);
  if (definition != nil &&
      [definition respondsToSelector:@selector(searchModuleEnumerateDocumentBatchesForRuntime:batchSize:usingBlock:error:)]) {
    return [(id<ALNSearchResourceDefinition>)definition searchModuleEnumerateDocumentBatchesForRuntime:self
                                                                                              batchSize:resolvedBatchSize
                                                                                             usingBlock:^BOOL(NSArray<NSDictionary *> *batch,
                                                                                                              NSError **batchError) {
                                                                                               NSMutableArray<NSDictionary *> *filtered = [NSMutableArray array];
                                                                                               for (NSDictionary *record in STNormalizeArray(batch)) {
                                                                                                 if (![record isKindOfClass:[NSDictionary class]]) {
                                                                                                   continue;
                                                                                                 }
                                                                                                 if (![self record:record
                                                                                                       isIndexableForMetadata:metadata
                                                                                                                   definition:definition
                                                                                                                        error:batchError]) {
                                                                                                   if (batchError != NULL && *batchError != nil) {
                                                                                                     return NO;
                                                                                                   }
                                                                                                   continue;
                                                                                                 }
                                                                                                 [filtered addObject:[record copy]];
                                                                                               }
                                                                                               return consumer([filtered copy], batchError);
                                                                                             }
                                                                                                  error:error];
  }

  NSArray *loaded = [definition searchModuleDocumentsForRuntime:self error:error];
  if (loaded == nil) {
    return NO;
  }
  NSMutableArray<NSDictionary *> *filtered = [NSMutableArray arrayWithCapacity:resolvedBatchSize];
  for (NSDictionary *record in STNormalizeArray(loaded)) {
    if (![record isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    if (![self record:record isIndexableForMetadata:metadata definition:definition error:error]) {
      if (error != NULL && *error != nil) {
        return NO;
      }
      continue;
    }
    [filtered addObject:[record copy]];
    if ([filtered count] >= resolvedBatchSize) {
      if (!consumer([filtered copy], error)) {
        return NO;
      }
      [filtered removeAllObjects];
    }
  }
  if ([filtered count] > 0U && !consumer([filtered copy], error)) {
    return NO;
  }
  return YES;
}

- (NSArray<NSDictionary *> *)recordsForDefinition:(id<ALNSearchResourceDefinition>)definition
                                         metadata:(NSDictionary *)metadata
                                        batchSize:(NSUInteger)batchSize
                                            error:(NSError **)error {
  NSMutableArray *records = [NSMutableArray array];
  if (![self enumerateIndexableRecordsForDefinition:definition
                                           metadata:metadata
                                          batchSize:batchSize
                                         usingBlock:^BOOL(NSArray<NSDictionary *> *batch, NSError **batchError) {
                                           (void)batchError;
                                           [records addObjectsFromArray:STNormalizeArray(batch)];
                                           return YES;
                                         }
                                              error:error]) {
    return nil;
  }
  return [records copy];
}

- (void)enqueueReplayOperation:(NSDictionary *)payload
          forResourceIdentifier:(NSString *)identifier
                       metadata:(NSDictionary *)metadata {
  NSString *resourceIdentifier = STLowerTrimmedString(identifier);
  if ([resourceIdentifier length] == 0) {
    return;
  }
  NSDictionary *syncPolicy = STNormalizeDictionary(metadata[@"syncPolicy"]);
  NSUInteger replayLimit = [syncPolicy[@"replayLimit"] respondsToSelector:@selector(unsignedIntegerValue)]
                               ? MAX((NSUInteger)1U, [syncPolicy[@"replayLimit"] unsignedIntegerValue])
                               : 20U;
  NSMutableArray *queue = [self.pendingReplayOperationsByResource[resourceIdentifier] isKindOfClass:[NSMutableArray class]]
                              ? self.pendingReplayOperationsByResource[resourceIdentifier]
                              : [NSMutableArray array];
  NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:STNormalizeDictionary(payload)];
  entry[@"queuedAt"] = @([[NSDate date] timeIntervalSince1970]);
  [queue addObject:entry];
  while ([queue count] > replayLimit) {
    [queue removeObjectAtIndex:0];
  }
  self.pendingReplayOperationsByResource[resourceIdentifier] = queue;
}

- (NSDictionary *)drainReplayOperationsForResourceIdentifier:(NSString *)identifier
                                                        mode:(NSString *)mode
                                                       error:(NSError **)error {
  NSString *resourceIdentifier = STLowerTrimmedString(identifier);
  NSMutableArray *queue = [self.pendingReplayOperationsByResource[resourceIdentifier] isKindOfClass:[NSMutableArray class]]
                              ? self.pendingReplayOperationsByResource[resourceIdentifier]
                              : nil;
  if ([queue count] == 0) {
    return @{
      @"resource" : resourceIdentifier ?: @"",
      @"replayed" : @0,
      @"remaining" : @0,
      @"mode" : STLowerTrimmedString(mode),
    };
  }

  NSArray *pending = [NSArray arrayWithArray:queue];
  [queue removeAllObjects];
  NSUInteger replayed = 0U;
  for (NSDictionary *entry in pending) {
    NSDictionary *result = [self applyIncrementalOperation:entry[@"operation"]
                                        resourceIdentifier:resourceIdentifier
                                                    record:STNormalizeDictionary(entry[@"record"])
                                                     error:error];
    if (result == nil) {
      [queue addObject:entry];
      NSUInteger failedIndex = [pending indexOfObject:entry];
      if (failedIndex != NSNotFound && (failedIndex + 1U) < [pending count]) {
        [queue addObjectsFromArray:[pending subarrayWithRange:NSMakeRange(failedIndex + 1U, [pending count] - failedIndex - 1U)]];
      }
      break;
    }
    replayed += 1U;
  }
  self.pendingReplayOperationsByResource[resourceIdentifier] = queue;
  return @{
    @"resource" : resourceIdentifier ?: @"",
    @"replayed" : @(replayed),
    @"remaining" : @([queue count]),
    @"mode" : STLowerTrimmedString(mode),
  };
}

- (NSDictionary *)shapedResultForDocument:(NSDictionary *)document
                                  metadata:(NSDictionary *)metadata
                                     error:(NSError **)error {
  NSString *resourceIdentifier = STLowerTrimmedString(metadata[@"identifier"] ?: document[@"resource"]);
  NSDictionary *record = STNormalizeDictionary(document[@"record"]);
  NSMutableDictionary *fields = [NSMutableDictionary dictionary];
  for (NSString *field in STNormalizedStringArray(metadata[@"resultFields"])) {
    id value = record[field];
    if (value == nil || value == [NSNull null]) {
      continue;
    }
    fields[field] = STPropertyListValue(value);
  }

  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  result[@"resource"] = ([resourceIdentifier length] > 0) ? resourceIdentifier : @"";
  result[@"resourceLabel"] = ([STTrimmedString(document[@"resourceLabel"]) length] > 0)
                                 ? STTrimmedString(document[@"resourceLabel"])
                                 : (metadata[@"label"] ?: STTitleCaseIdentifier(resourceIdentifier));
  result[@"recordID"] = STTrimmedString(document[@"recordID"]);
  result[@"title"] = STStringifyValue(document[@"title"]);
  result[@"summary"] = STStringifyValue(document[@"summary"]);
  result[@"path"] = STTrimmedString(document[@"path"]);
  result[@"score"] = [document[@"score"] respondsToSelector:@selector(integerValue)] ? document[@"score"] : @0;
  result[@"generation"] = [document[@"generation"] respondsToSelector:@selector(unsignedIntegerValue)] ? document[@"generation"] : @0;
  result[@"highlights"] = STNormalizeArray(document[@"highlights"]);
  if ([STNormalizeArray(document[@"matchedFields"]) count] > 0) {
    result[@"matchedFields"] = STNormalizeArray(document[@"matchedFields"]);
  }
  if ([document[@"explain"] isKindOfClass:[NSDictionary class]]) {
    result[@"explain"] = STNormalizeDictionary(document[@"explain"]);
  }
  result[@"fields"] = fields ?: @{};

  id<ALNSearchResourceDefinition> definition = [self resourceDefinitionForIdentifier:resourceIdentifier];
  if (definition != nil &&
      [definition respondsToSelector:@selector(searchModulePublicResultForDocument:metadata:runtime:error:)]) {
    NSDictionary *custom = [(id<ALNSearchResourceDefinition>)definition searchModulePublicResultForDocument:document
                                                                                                   metadata:metadata
                                                                                                    runtime:self
                                                                                                      error:error];
    if (custom == nil) {
      return nil;
    }
    NSMutableDictionary *normalizedCustom = [NSMutableDictionary dictionary];
    for (id rawKey in [custom allKeys]) {
      NSString *key = STTrimmedString(rawKey);
      if ([key length] == 0) {
        continue;
      }
      normalizedCustom[key] = STPropertyListValue(custom[rawKey]);
    }
    if ([normalizedCustom[@"fields"] isKindOfClass:[NSDictionary class]]) {
      result[@"fields"] = normalizedCustom[@"fields"];
      [normalizedCustom removeObjectForKey:@"fields"];
    }
    [result addEntriesFromDictionary:normalizedCustom];
  }

  [result removeObjectForKey:@"record"];
  [result removeObjectForKey:@"fieldText"];
  [result removeObjectForKey:@"searchableText"];
  [result removeObjectForKey:@"autocompleteText"];
  [result removeObjectForKey:@"scoreValue"];
  return result;
}

- (nullable NSArray<NSDictionary *> *)promotedResultsForQuery:(NSString *)query
                                              resourceMetadata:(NSArray<NSDictionary *> *)resourceMetadata
                                           snapshotsByResource:(NSDictionary<NSString *, NSDictionary *> *)snapshotsByResource
                                                         error:(NSError **)error {
  NSString *normalizedQuery = STLowerTrimmedString(query);
  if ([normalizedQuery length] == 0) {
    return @[];
  }
  NSMutableArray<NSDictionary *> *promoted = [NSMutableArray array];
  NSMutableSet<NSString *> *seenKeys = [NSMutableSet set];
  for (NSDictionary *metadata in STNormalizeArray(resourceMetadata)) {
    NSString *resourceIdentifier = STLowerTrimmedString(metadata[@"identifier"]);
    NSDictionary *snapshot = STNormalizeDictionary(snapshotsByResource[resourceIdentifier]);
    NSMutableDictionary *documentsByRecordID = [NSMutableDictionary dictionary];
    for (NSDictionary *document in STNormalizeArray(snapshot[@"documents"])) {
      NSString *recordID = STTrimmedString(document[@"recordID"]);
      if ([recordID length] == 0) {
        continue;
      }
      documentsByRecordID[recordID] = document;
    }
    for (NSDictionary *promotion in STNormalizeArray(metadata[@"promotions"])) {
      if (![STNormalizeArray(promotion[@"queries"]) containsObject:normalizedQuery]) {
        continue;
      }
      for (NSString *recordID in STTrimmedUniqueStringArray(promotion[@"recordIDs"])) {
        NSDictionary *document = documentsByRecordID[recordID];
        if (document == nil) {
          continue;
        }
        NSString *dedupeKey = [NSString stringWithFormat:@"%@:%@", resourceIdentifier, recordID];
        if ([seenKeys containsObject:dedupeKey]) {
          continue;
        }
        NSMutableDictionary *decorated = [NSMutableDictionary dictionaryWithDictionary:document];
        decorated[@"generation"] =
            [snapshot[@"generation"] respondsToSelector:@selector(unsignedIntegerValue)] ? snapshot[@"generation"] : @0;
        decorated[@"score"] = @0;
        decorated[@"highlights"] = @[];
        NSDictionary *shaped = [self shapedResultForDocument:decorated metadata:metadata error:error];
        if (shaped == nil) {
          return nil;
        }
        NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:shaped];
        entry[@"promoted"] = @YES;
        entry[@"promotionLabel"] = ([STTrimmedString(promotion[@"label"]) length] > 0) ? STTrimmedString(promotion[@"label"]) : @"Promoted";
        [promoted addObject:entry];
        [seenKeys addObject:dedupeKey];
      }
    }
  }
  return promoted;
}

- (NSArray<NSDictionary *> *)facetSummariesForMatchedDocuments:(NSArray<NSDictionary *> *)matchedDocuments
                                               resourceMetadata:(NSArray<NSDictionary *> *)resourceMetadata
                                                        filters:(NSDictionary *)filters {
  NSMutableArray<NSDictionary *> *summaries = [NSMutableArray array];
  for (NSDictionary *metadata in STNormalizeArray(resourceMetadata)) {
    NSString *resourceIdentifier = STLowerTrimmedString(metadata[@"identifier"]);
    NSArray *facetFields = STNormalizeArray(metadata[@"facetFields"]);
    if ([facetFields count] == 0) {
      continue;
    }

    NSMutableArray<NSDictionary *> *documents = [NSMutableArray array];
    for (NSDictionary *document in STNormalizeArray(matchedDocuments)) {
      if ([STLowerTrimmedString(document[@"resource"]) isEqualToString:resourceIdentifier]) {
        [documents addObject:document];
      }
    }

    for (NSDictionary *facet in facetFields) {
      NSString *fieldName = STLowerTrimmedString(facet[@"name"]);
      if ([fieldName length] == 0) {
        continue;
      }
      NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
      NSMutableDictionary<NSString *, NSString *> *labels = [NSMutableDictionary dictionary];
      for (NSDictionary *choice in STNormalizeArray(facet[@"choices"])) {
        NSString *value = STTrimmedString(choice[@"value"]);
        if ([value length] == 0) {
          continue;
        }
        labels[value] = ([STTrimmedString(choice[@"label"]) length] > 0) ? STTrimmedString(choice[@"label"]) : value;
      }

      for (NSDictionary *document in documents) {
        NSDictionary *record = STNormalizeDictionary(document[@"record"]);
        id rawValue = record[fieldName];
        NSArray *values = [rawValue isKindOfClass:[NSArray class]] ? rawValue : (rawValue != nil ? @[ rawValue ] : @[]);
        for (id entry in values) {
          NSString *value = STTrimmedString(entry);
          if ([value length] == 0) {
            continue;
          }
          NSUInteger existing = [counts[value] respondsToSelector:@selector(unsignedIntegerValue)]
                                    ? [counts[value] unsignedIntegerValue]
                                    : 0U;
          counts[value] = @(existing + 1U);
          if ([labels[value] length] == 0) {
            labels[value] = value;
          }
        }
      }

      if ([counts count] == 0) {
        continue;
      }
      NSMutableSet<NSString *> *selectedValues = [NSMutableSet set];
      id rawSelected = filters[fieldName];
      if (rawSelected != nil) {
        if ([rawSelected isKindOfClass:[NSArray class]]) {
          for (NSString *value in STTrimmedUniqueStringArray(rawSelected)) {
            [selectedValues addObject:value];
          }
        } else {
          for (NSString *value in STTrimmedUniqueStringArray([STTrimmedString(rawSelected) componentsSeparatedByString:@","])) {
            [selectedValues addObject:value];
          }
        }
      }
      rawSelected = filters[[NSString stringWithFormat:@"%@__in", fieldName]];
      if (rawSelected != nil) {
        if ([rawSelected isKindOfClass:[NSArray class]]) {
          for (NSString *value in STTrimmedUniqueStringArray(rawSelected)) {
            [selectedValues addObject:value];
          }
        } else {
          for (NSString *value in STTrimmedUniqueStringArray([STTrimmedString(rawSelected) componentsSeparatedByString:@","])) {
            [selectedValues addObject:value];
          }
        }
      }

      NSArray<NSString *> *sortedValues = [[counts allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *lhs, NSString *rhs) {
        NSUInteger left = [counts[lhs] unsignedIntegerValue];
        NSUInteger right = [counts[rhs] unsignedIntegerValue];
        if (left != right) {
          return (left > right) ? NSOrderedAscending : NSOrderedDescending;
        }
        return [STLowerTrimmedString(labels[lhs]) compare:STLowerTrimmedString(labels[rhs])];
      }];
      NSUInteger facetLimit = [facet[@"limit"] respondsToSelector:@selector(unsignedIntegerValue)]
                                  ? MAX((NSUInteger)1U, [facet[@"limit"] unsignedIntegerValue])
                                  : 10U;
      if ([sortedValues count] > facetLimit) {
        sortedValues = [sortedValues subarrayWithRange:NSMakeRange(0, facetLimit)];
      }

      NSMutableArray<NSDictionary *> *values = [NSMutableArray array];
      for (NSString *value in sortedValues) {
        [values addObject:@{
          @"value" : value,
          @"label" : labels[value] ?: value,
          @"count" : counts[value] ?: @0,
          @"selected" : @([selectedValues containsObject:value]),
        }];
      }

      [summaries addObject:@{
        @"resource" : resourceIdentifier,
        @"resourceLabel" : metadata[@"label"] ?: STTitleCaseIdentifier(resourceIdentifier),
        @"name" : fieldName,
        @"label" : ([STTrimmedString(facet[@"label"]) length] > 0) ? STTrimmedString(facet[@"label"]) : STTitleCaseIdentifier(fieldName),
        @"type" : ([STLowerTrimmedString(facet[@"type"]) length] > 0) ? STLowerTrimmedString(facet[@"type"]) : @"string",
        @"values" : values ?: @[],
        @"totalValues" : @([counts count]),
      }];
    }
  }
  return summaries;
}

- (NSDictionary *)searchQuery:(NSString *)query
           resourceIdentifier:(NSString *)resourceIdentifier
     allowedResourceIdentifiers:(NSArray<NSString *> *)allowedResourceIdentifiers
                      filters:(NSDictionary *)filters
                         sort:(NSString *)sort
                        limit:(NSUInteger)limit
                       offset:(NSUInteger)offset
                 queryOptions:(NSDictionary *)queryOptions
                        error:(NSError **)error {
  NSString *resource = STLowerTrimmedString(resourceIdentifier);
  NSSet *allowedSet = ([allowedResourceIdentifiers count] > 0) ? [NSSet setWithArray:allowedResourceIdentifiers] : nil;
  NSArray *candidateMetadata = nil;
  if ([resource length] > 0) {
    NSDictionary *metadata = [self resourceMetadataForIdentifier:resource];
    if (metadata == nil || (allowedSet != nil && ![allowedSet containsObject:resource])) {
      if (error != NULL) {
        *error = STError(ALNSearchModuleErrorNotFound,
                         [NSString stringWithFormat:@"unknown search resource %@", resource],
                         @{ @"resource" : resource ?: @"" });
      }
      return nil;
    }
    candidateMetadata = @[ metadata ];
  } else {
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSDictionary *metadata in [self registeredResources]) {
      NSString *identifier = STLowerTrimmedString(metadata[@"identifier"]);
      if (allowedSet != nil && ![allowedSet containsObject:identifier]) {
        continue;
      }
      [filtered addObject:metadata];
    }
    candidateMetadata = filtered;
  }

  if ([candidateMetadata count] == 0) {
    NSUInteger emptyLimit = (limit > 0U) ? limit : 25U;
    return @{
      @"query" : STTrimmedString(query),
      @"mode" : STLowerTrimmedString(queryOptions[@"mode"]).length > 0 ? STLowerTrimmedString(queryOptions[@"mode"]) : @"search",
      @"availableModes" : @[],
      @"resource" : resource ?: @"",
      @"resources" : @[],
      @"resourceMetadata" : @{},
      @"results" : @[],
      @"promotedResults" : @[],
      @"autocomplete" : @[],
      @"suggestions" : @[],
      @"facets" : @[],
      @"total" : @0,
      @"matchedCount" : @0,
      @"limit" : @(emptyLimit),
      @"offset" : @(offset),
      @"pagination" : @{
        @"limit" : @(emptyLimit),
        @"offset" : @(offset),
        @"returned" : @0,
        @"total" : @0,
      },
      @"engine" : self.engineIdentifier ?: @"ALNDefaultSearchEngine",
      @"engineCapabilities" : [self.engine searchModuleCapabilities] ?: @{},
    };
  }

  NSString *requestedMode = STLowerTrimmedString(queryOptions[@"mode"]);
  NSString *requestedCursor = STTrimmedString(queryOptions[@"cursor"]);
  BOOL explain = STBooleanValue(queryOptions[@"explain"], NO);
  NSArray *engineModes = STNormalizedStringArray([self.engine searchModuleCapabilities][@"queryModes"]);
  if ([requestedMode length] > 0 && [engineModes count] > 0 && ![engineModes containsObject:requestedMode]) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorValidationFailed,
                       [NSString stringWithFormat:@"unsupported query mode %@", requestedMode],
                       @{ @"mode" : requestedMode ?: @"" });
    }
    return nil;
  }
  if ([requestedMode length] > 0) {
    for (NSDictionary *metadata in candidateMetadata) {
      NSArray *resourceModes = STNormalizedStringArray(metadata[@"queryModes"]);
      if ([resourceModes count] > 0 && ![resourceModes containsObject:requestedMode]) {
        if (error != NULL) {
          *error = STError(ALNSearchModuleErrorValidationFailed,
                           [NSString stringWithFormat:@"query mode %@ is not available for %@", requestedMode, metadata[@"identifier"] ?: @"resource"],
                           @{
                             @"mode" : requestedMode ?: @"",
                             @"resource" : metadata[@"identifier"] ?: @"",
                           });
        }
        return nil;
      }
    }
  }
  if ([requestedCursor length] > 0 &&
      !STBooleanValue([self.engine searchModuleCapabilities][@"supportsCursorPagination"], NO)) {
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorValidationFailed,
                       @"the active search engine does not support cursor pagination",
                       @{ @"engine" : self.engineIdentifier ?: @"ALNDefaultSearchEngine" });
    }
    return nil;
  }

  NSDictionary *pagination = ([candidateMetadata count] == 1) ? STNormalizeDictionary(candidateMetadata[0][@"pagination"]) : @{};
  NSUInteger defaultLimit = [pagination[@"defaultLimit"] respondsToSelector:@selector(unsignedIntegerValue)]
                                ? [pagination[@"defaultLimit"] unsignedIntegerValue]
                                : 25U;
  if (defaultLimit == 0U) {
    defaultLimit = 25U;
  }
  NSUInteger resolvedLimit = (limit > 0U) ? limit : defaultLimit;
  NSUInteger maxLimit = [pagination[@"maxLimit"] respondsToSelector:@selector(unsignedIntegerValue)]
                            ? [pagination[@"maxLimit"] unsignedIntegerValue]
                            : 100U;
  if (maxLimit == 0U) {
    maxLimit = 100U;
  }
  resolvedLimit = MIN(MAX((NSUInteger)1U, resolvedLimit), maxLimit);

  NSMutableDictionary *snapshotsByResource = [NSMutableDictionary dictionary];
  for (NSDictionary *metadata in candidateMetadata) {
    NSString *identifier = STLowerTrimmedString(metadata[@"identifier"]);
    snapshotsByResource[identifier] = [self snapshotForResourceIdentifier:identifier metadata:metadata];
  }

  NSDictionary *result = nil;
  if ([self.engine respondsToSelector:@selector(searchModuleExecuteQuery:resourceMetadata:snapshotsByResource:filters:sort:limit:offset:options:error:)]) {
    result = [(id<ALNSearchEngine>)self.engine searchModuleExecuteQuery:query
                                                        resourceMetadata:candidateMetadata
                                                     snapshotsByResource:snapshotsByResource
                                                                 filters:filters ?: @{}
                                                                    sort:sort
                                                                   limit:resolvedLimit
                                                                  offset:offset
                                                                 options:queryOptions ?: @{}
                                                                   error:error];
  } else {
    result = [self.engine searchModuleExecuteQuery:query
                                    resourceMetadata:candidateMetadata
                                 snapshotsByResource:snapshotsByResource
                                             filters:filters ?: @{}
                                                sort:sort
                                               limit:resolvedLimit
                                              offset:offset
                                               error:error];
  }
  if (result == nil) {
    return nil;
  }

  NSArray *matchedDocuments = STNormalizeArray(result[@"matchedDocuments"]);
  NSArray *rawResults = STNormalizeArray(result[@"results"]);
  NSArray *promotedResults = [self promotedResultsForQuery:query
                                          resourceMetadata:candidateMetadata
                                       snapshotsByResource:snapshotsByResource
                                                     error:error];
  if (promotedResults == nil) {
    return nil;
  }
  NSMutableSet<NSString *> *promotedKeys = [NSMutableSet set];
  for (NSDictionary *entry in promotedResults) {
    NSString *resourceID = STLowerTrimmedString(entry[@"resource"]);
    NSString *recordID = STTrimmedString(entry[@"recordID"]);
    if ([resourceID length] > 0 && [recordID length] > 0) {
      [promotedKeys addObject:[NSString stringWithFormat:@"%@:%@", resourceID, recordID]];
    }
  }

  NSMutableDictionary<NSString *, NSDictionary *> *metadataByIdentifier = [NSMutableDictionary dictionary];
  for (NSDictionary *metadata in candidateMetadata) {
    NSString *identifier = STLowerTrimmedString(metadata[@"identifier"]);
    if ([identifier length] > 0) {
      metadataByIdentifier[identifier] = metadata;
    }
  }
  NSMutableArray<NSDictionary *> *shapedResults = [NSMutableArray array];
  for (NSDictionary *document in rawResults) {
    NSString *resourceID = STLowerTrimmedString(document[@"resource"]);
    NSString *recordID = STTrimmedString(document[@"recordID"]);
    if ([promotedKeys containsObject:[NSString stringWithFormat:@"%@:%@", resourceID, recordID]]) {
      continue;
    }
    NSDictionary *metadata = metadataByIdentifier[resourceID] ?: @{};
    NSDictionary *shaped = [self shapedResultForDocument:document metadata:metadata error:error];
    if (shaped == nil) {
      return nil;
    }
    [shapedResults addObject:shaped];
  }

  NSDictionary *engineCapabilities = [self.engine searchModuleCapabilities] ?: @{};
  NSMutableDictionary *response = [NSMutableDictionary dictionary];
  response[@"query"] = STTrimmedString(result[@"query"] ?: query);
  response[@"mode"] = ([requestedMode length] > 0) ? requestedMode : (STLowerTrimmedString(result[@"mode"]).length > 0 ? STLowerTrimmedString(result[@"mode"]) : @"search");
  response[@"availableModes"] = STNormalizedStringArray(result[@"availableModes"] ?: engineModes);
  response[@"resource"] = resource ?: @"";
  response[@"resources"] = [self resourceIdentifiersFromMetadataArray:candidateMetadata] ?: @[];
  response[@"resourceMetadata"] = ([candidateMetadata count] == 1) ? candidateMetadata[0] : @{};
  response[@"engine"] = self.engineIdentifier ?: @"ALNDefaultSearchEngine";
  response[@"engineCapabilities"] = engineCapabilities;
  response[@"results"] = shapedResults ?: @[];
  response[@"promotedResults"] = promotedResults ?: @[];
  response[@"autocomplete"] = STNormalizeArray(result[@"autocomplete"]);
  response[@"suggestions"] = STNormalizeArray(result[@"suggestions"]);
  NSArray *engineFacets = STNormalizeArray(result[@"facets"]);
  response[@"facets"] = ([engineFacets count] > 0)
                            ? engineFacets
                            : ([self facetSummariesForMatchedDocuments:matchedDocuments
                                                         resourceMetadata:candidateMetadata
                                                                  filters:filters ?: @{}] ?: @[]);
  response[@"total"] = [result[@"total"] respondsToSelector:@selector(unsignedIntegerValue)] ? result[@"total"] : @([rawResults count]);
  response[@"matchedCount"] = @([matchedDocuments count]);
  response[@"limit"] = @(resolvedLimit);
  response[@"offset"] = @(offset);
  response[@"pagination"] = @{
    @"defaultLimit" : @(defaultLimit),
    @"maxLimit" : @(maxLimit),
    @"limit" : @(resolvedLimit),
    @"offset" : @(offset),
    @"returned" : @([shapedResults count]),
    @"total" : response[@"total"] ?: @0,
  };
  response[@"cursor"] = @{
    @"requested" : requestedCursor ?: @"",
    @"next" : STTrimmedString(result[@"nextCursor"]),
    @"supported" : @([engineCapabilities[@"supportsCursorPagination"] boolValue]),
  };
  if (explain || [STNormalizeDictionary(result[@"debug"]) count] > 0) {
    response[@"debug"] = STNormalizeDictionary(result[@"debug"]);
  }
  [self.lock lock];
  [self recordRecentQuery:@{
    @"query" : STTrimmedString(result[@"query"] ?: query),
    @"mode" : response[@"mode"] ?: @"search",
    @"resource" : resource ?: @"*",
    @"returned" : @([shapedResults count]),
    @"total" : response[@"total"] ?: @0,
    @"engine" : self.engineIdentifier ?: @"ALNDefaultSearchEngine",
    @"cursor" : STTrimmedString(result[@"nextCursor"]),
    @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
  }];
  [self.lock unlock];
  return response;
}

- (NSDictionary *)resourceRowForIdentifier:(NSString *)identifier metadata:(NSDictionary *)metadata {
  NSDictionary *status = nil;
  NSDictionary *engineState = nil;
  NSArray *pendingReplay = nil;
  NSArray *generationHistory = nil;
  [self.lock lock];
  status = [self.statusByResource[identifier] isKindOfClass:[NSDictionary class]] ? self.statusByResource[identifier] : @{};
  engineState = [self.engineStateByResource[identifier] isKindOfClass:[NSDictionary class]] ? self.engineStateByResource[identifier] : @{};
  pendingReplay = [NSArray arrayWithArray:STNormalizeArray(self.pendingReplayOperationsByResource[identifier])];
  generationHistory = [NSArray arrayWithArray:STNormalizeArray(self.generationHistoryByResource[identifier])];
  [self.lock unlock];
  NSMutableDictionary *row = [NSMutableDictionary dictionaryWithDictionary:status ?: @{}];
  row[@"identifier"] = identifier ?: @"";
  row[@"label"] = metadata[@"label"] ?: status[@"label"] ?: STTitleCaseIdentifier(identifier);
  row[@"summary"] = metadata[@"summary"] ?: @"";
  row[@"adminIntegrated"] = metadata[@"adminIntegrated"] ?: @NO;
  row[@"supportsHighlights"] = metadata[@"supportsHighlights"] ?: @NO;
  row[@"defaultSort"] = metadata[@"defaultSort"] ?: @"";
  row[@"pagination"] = metadata[@"pagination"] ?: @{};
  row[@"queryPolicy"] = metadata[@"queryPolicy"] ?: @"public";
  row[@"queryRoles"] = metadata[@"queryRoles"] ?: @[];
  row[@"queryModes"] = metadata[@"queryModes"] ?: @[];
  row[@"resultFields"] = metadata[@"resultFields"] ?: @[];
  row[@"facetFields"] = metadata[@"facetFields"] ?: @[];
  row[@"fieldTypes"] = metadata[@"fieldTypes"] ?: @{};
  row[@"visibility"] = metadata[@"visibility"] ?: @{};
  row[@"syncPolicy"] = metadata[@"syncPolicy"] ?: @{};
  row[@"engineDescriptor"] = ([engineState count] > 0) ? engineState : (metadata[@"engineDescriptor"] ?: @{});
  row[@"pendingReplayOperations"] = pendingReplay ?: @[];
  row[@"replayQueueDepth"] = @([pendingReplay count]);
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
  NSMutableArray *recentQueries = [NSMutableArray array];
  [self.lock lock];
  for (NSDictionary *entry in self.reindexHistory) {
    if ([STLowerTrimmedString(entry[@"resource"]) isEqualToString:resourceIdentifier]) {
      [history addObject:entry];
    }
  }
  for (NSDictionary *entry in self.recentQueries) {
    NSString *entryResource = STLowerTrimmedString(entry[@"resource"]);
    if ([entryResource isEqualToString:resourceIdentifier] || [entryResource isEqualToString:@"*"]) {
      [recentQueries addObject:entry];
    }
  }
  [self.lock unlock];
  return @{
    @"resource" : [self resourceRowForIdentifier:resourceIdentifier metadata:metadata] ?: @{},
    @"history" : history ?: @[],
    @"recentQueries" : recentQueries ?: @[],
    @"resourceMetadata" : metadata ?: @{},
  };
}

- (NSDictionary *)dashboardSummary {
  NSArray *resources = [self registeredResources];
  NSMutableArray *statusRows = [NSMutableArray array];
  NSUInteger documentCount = 0;
  NSUInteger replayQueueDepth = 0;
  for (NSDictionary *metadata in resources) {
    NSString *identifier = STLowerTrimmedString(metadata[@"identifier"]);
    NSDictionary *row = [self resourceRowForIdentifier:identifier metadata:metadata];
    documentCount += [row[@"documentCount"] unsignedIntegerValue];
    replayQueueDepth += [row[@"replayQueueDepth"] unsignedIntegerValue];
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
  NSArray *recentQueries = [NSArray arrayWithArray:self.recentQueries];
  [self.lock unlock];
  NSString *moduleStatus = STResolvedModuleStatus(statusRows, pendingJobs, deadJobs);

  return @{
    @"config" : [self resolvedConfigSummary],
    @"resources" : STSortedArrayFromValues(statusRows, @"identifier"),
    @"history" : history ?: @[],
    @"recentQueries" : recentQueries ?: @[],
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
      @"replayQueueDepth" : @(replayQueueDepth),
      @"recentQueries" : @([recentQueries count]),
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
      STStatusCard(@"Replay Queue",
                   [NSString stringWithFormat:@"%lu", (unsigned long)replayQueueDepth],
                   (replayQueueDepth > 0U) ? @"degraded" : @"healthy",
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
      @{ @"name" : @"replayQueueDepth", @"label" : @"Replay Queue", @"kind" : @"integer", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"lastReplayStatus", @"label" : @"Replay Status", @"list" : @NO, @"detail" : @YES },
      @{ @"name" : @"lastIndexedAt", @"label" : @"Last Indexed", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"lastFailureAt", @"label" : @"Last Failure", @"list" : @NO, @"detail" : @YES },
      @{ @"name" : @"lastJobID", @"label" : @"Last Job", @"list" : @NO, @"detail" : @YES },
      @{ @"name" : @"engine", @"label" : @"Engine", @"list" : @NO, @"detail" : @YES },
      @{ @"name" : @"engineDescriptor", @"label" : @"Engine Descriptor", @"kind" : @"json", @"list" : @NO, @"detail" : @YES },
      @{ @"name" : @"syncPolicy", @"label" : @"Sync Policy", @"kind" : @"json", @"list" : @NO, @"detail" : @YES },
      @{ @"name" : @"visibility", @"label" : @"Visibility", @"kind" : @"json", @"list" : @NO, @"detail" : @YES },
      @{ @"name" : @"bulkImport", @"label" : @"Bulk Import", @"kind" : @"json", @"list" : @NO, @"detail" : @YES },
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
    _authRuntime = STSharedAuthRuntime();
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

- (NSDictionary *)apiErrorPresentationForError:(NSError *)error {
  if (error == nil) {
    return @{
      @"status" : @422,
      @"code" : @"validation_failed",
    };
  }
  switch (error.code) {
  case ALNSearchModuleErrorUnauthorized:
    return @{
      @"status" : @401,
      @"code" : @"unauthorized",
    };
  case ALNSearchModuleErrorForbidden:
    return @{
      @"status" : @403,
      @"code" : @"forbidden",
    };
  case ALNSearchModuleErrorNotFound:
    return @{
      @"status" : @404,
      @"code" : @"not_found",
    };
  case ALNSearchModuleErrorExecutionFailed:
    return @{
      @"status" : @500,
      @"code" : @"execution_failed",
    };
  default:
    return @{
      @"status" : @422,
      @"code" : @"validation_failed",
    };
  }
}

- (BOOL)resourceMetadata:(NSDictionary *)metadata
      allowsQueryInContext:(ALNContext *)ctx
                     error:(NSError **)error {
  NSString *policy = STLowerTrimmedString(metadata[@"queryPolicy"]);
  NSString *identifier = STLowerTrimmedString(metadata[@"identifier"]);
  if ([policy length] == 0 || [policy isEqualToString:@"public"]) {
    return YES;
  }
  if ([policy isEqualToString:@"authenticated"]) {
    if ([[ctx authSubject] length] > 0) {
      return YES;
    }
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorUnauthorized,
                       @"authentication is required for this search resource",
                       @{ @"resource" : identifier ?: @"" });
    }
    return NO;
  }
  if ([policy isEqualToString:@"role_gated"]) {
    if ([[ctx authSubject] length] == 0) {
      if (error != NULL) {
        *error = STError(ALNSearchModuleErrorUnauthorized,
                         @"authentication is required for this search resource",
                         @{ @"resource" : identifier ?: @"" });
      }
      return NO;
    }
    NSArray *requiredRoles = STNormalizeArray(metadata[@"queryRoles"]);
    if (STRolesAllowAccess([ctx authRoles], requiredRoles)) {
      return YES;
    }
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorForbidden,
                       @"you do not have access to query this search resource",
                       @{
                         @"resource" : identifier ?: @"",
                         @"required_roles_any" : requiredRoles ?: @[],
                       });
    }
    return NO;
  }
  if ([policy isEqualToString:@"predicate"]) {
    id<ALNSearchResourceDefinition> definition = [self.runtime resourceDefinitionForIdentifier:identifier];
    if (definition != nil &&
        [definition respondsToSelector:@selector(searchModuleAllowsQueryForContext:runtime:error:)]) {
      BOOL allowed = [(id<ALNSearchResourceDefinition>)definition searchModuleAllowsQueryForContext:ctx
                                                                                            runtime:self.runtime
                                                                                              error:error];
      if (allowed) {
        return YES;
      }
      if (error != NULL && *error == nil) {
        *error = STError(ALNSearchModuleErrorForbidden,
                         @"you do not have access to query this search resource",
                         @{ @"resource" : identifier ?: @"" });
      }
      return NO;
    }
    if (error != NULL) {
      *error = STError(ALNSearchModuleErrorForbidden,
                       @"you do not have access to query this search resource",
                       @{ @"resource" : identifier ?: @"" });
    }
    return NO;
  }
  return YES;
}

- (NSArray<NSDictionary *> *)queryableResourcesForContext:(ALNContext *)ctx
                                       resourceIdentifier:(NSString *)resourceIdentifier
                                                    error:(NSError **)error {
  NSString *resource = STLowerTrimmedString(resourceIdentifier);
  NSArray *resources = nil;
  if ([resource length] > 0) {
    NSDictionary *metadata = [self.runtime resourceMetadataForIdentifier:resource];
    if (metadata == nil) {
      if (error != NULL) {
        *error = STError(ALNSearchModuleErrorNotFound,
                         [NSString stringWithFormat:@"unknown search resource %@", resource],
                         @{ @"resource" : resource ?: @"" });
      }
      return nil;
    }
    resources = @[ metadata ];
  } else {
    resources = [self.runtime registeredResources] ?: @[];
  }

  NSMutableArray<NSDictionary *> *visible = [NSMutableArray array];
  for (NSDictionary *metadata in resources) {
    NSError *policyError = nil;
    BOOL allowed = [self resourceMetadata:metadata allowsQueryInContext:ctx error:&policyError];
    if (allowed) {
      [visible addObject:metadata];
      continue;
    }
    if ([resource length] > 0) {
      if (error != NULL) {
        *error = policyError;
      }
      return nil;
    }
    if (policyError != nil &&
        policyError.code != ALNSearchModuleErrorUnauthorized &&
        policyError.code != ALNSearchModuleErrorForbidden) {
      if (error != NULL) {
        *error = policyError;
      }
      return nil;
    }
  }
  return visible;
}

- (NSDictionary *)searchSummaryForVisibleResources:(NSArray<NSDictionary *> *)visibleResources {
  NSDictionary *summary = [self.runtime dashboardSummary] ?: @{};
  NSArray *rows = STNormalizeArray(summary[@"resources"]);
  NSSet *visibleIdentifiers = [NSSet setWithArray:[self.runtime resourceIdentifiersFromMetadataArray:visibleResources] ?: @[]];
  NSMutableArray *filteredRows = [NSMutableArray array];
  NSUInteger documentCount = 0U;
  for (NSDictionary *row in rows) {
    NSString *identifier = STLowerTrimmedString(row[@"identifier"]);
    if ([identifier length] == 0 || ![visibleIdentifiers containsObject:identifier]) {
      continue;
    }
    [filteredRows addObject:row];
    documentCount += [row[@"documentCount"] unsignedIntegerValue];
  }
  NSMutableDictionary *filteredSummary = [NSMutableDictionary dictionaryWithDictionary:summary];
  filteredSummary[@"resources"] = filteredRows ?: @[];
  NSMutableDictionary *totals = [NSMutableDictionary dictionaryWithDictionary:STNormalizeDictionary(summary[@"totals"])];
  totals[@"resources"] = @([filteredRows count]);
  totals[@"documents"] = @(documentCount);
  filteredSummary[@"totals"] = totals;
  return filteredSummary;
}

- (NSDictionary *)searchQueryOptionsFromParameters:(NSDictionary *)parameters {
  NSMutableDictionary *options = [NSMutableDictionary dictionary];
  NSString *mode = STLowerTrimmedString(parameters[@"mode"]);
  if ([mode length] > 0) {
    options[@"mode"] = mode;
  }
  if ([parameters[@"autocomplete_limit"] respondsToSelector:@selector(unsignedIntegerValue)] &&
      [parameters[@"autocomplete_limit"] unsignedIntegerValue] > 0U) {
    options[@"autocompleteLimit"] = @([parameters[@"autocomplete_limit"] unsignedIntegerValue]);
  }
  if ([parameters[@"suggestions_limit"] respondsToSelector:@selector(unsignedIntegerValue)] &&
      [parameters[@"suggestions_limit"] unsignedIntegerValue] > 0U) {
    options[@"suggestionsLimit"] = @([parameters[@"suggestions_limit"] unsignedIntegerValue]);
  }
  NSString *cursor = STTrimmedString(parameters[@"cursor"]);
  if ([cursor length] > 0) {
    options[@"cursor"] = cursor;
  }
  if (STBooleanValue(parameters[@"explain"], NO)) {
    options[@"explain"] = @YES;
  }
  return options;
}

- (BOOL)renderSearchErrorHTML:(NSError *)error context:(ALNContext *)ctx {
  if (error == nil) {
    return NO;
  }
  NSString *returnTo = [self searchReturnPathForContext:ctx];
  if (error.code == ALNSearchModuleErrorUnauthorized) {
    NSString *location = [NSString stringWithFormat:@"%@?return_to=%@",
                                                    [self.authRuntime loginPath] ?: @"/auth/login",
                                                    STPercentEncodedQueryComponent(returnTo)];
    [self redirectTo:location status:302];
    return YES;
  }
  NSInteger status = (error.code == ALNSearchModuleErrorForbidden) ? 403 : (error.code == ALNSearchModuleErrorNotFound ? 404 : 422);
  [self setStatus:status];
  [self renderTemplate:@"modules/search/result/index"
               context:[self pageContextWithTitle:@"Search"
                                          heading:(status == 404) ? @"Search resource not found" : @"Search unavailable"
                                          message:error.localizedDescription ?: @"search failed"
                                           errors:nil
                                            extra:nil]
                layout:@"modules/search/layouts/main"
                 error:NULL];
  return YES;
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
                                      context:(ALNContext *)ctx
                                        error:(NSError **)error {
  NSArray *visibleResources = [self queryableResourcesForContext:ctx resourceIdentifier:resourceIdentifier error:error];
  if (visibleResources == nil) {
    return nil;
  }
  NSUInteger limit = [parameters[@"limit"] respondsToSelector:@selector(unsignedIntegerValue)] ? [parameters[@"limit"] unsignedIntegerValue] : 25;
  NSUInteger offset = [parameters[@"offset"] respondsToSelector:@selector(unsignedIntegerValue)] ? [parameters[@"offset"] unsignedIntegerValue] : 0;
  NSDictionary *explicitFilters = [self searchFiltersFromParameters:parameters] ?: @{};
  NSString *query = STTrimmedString(parameters[@"q"]);
  if ([query length] == 0 && [STLowerTrimmedString(resourceIdentifier) length] == 0 && [explicitFilters count] == 0) {
    return @{
      @"query" : @"",
      @"mode" : STLowerTrimmedString(parameters[@"mode"]).length > 0 ? STLowerTrimmedString(parameters[@"mode"]) : @"search",
      @"availableModes" : @[],
      @"resource" : @"",
      @"resources" : [self.runtime resourceIdentifiersFromMetadataArray:visibleResources] ?: @[],
      @"resourceMetadata" : @{},
      @"results" : @[],
      @"promotedResults" : @[],
      @"autocomplete" : @[],
      @"suggestions" : @[],
      @"facets" : @[],
      @"total" : @0,
      @"matchedCount" : @0,
      @"limit" : @(limit),
      @"offset" : @(offset),
      @"pagination" : @{
        @"limit" : @(limit),
        @"offset" : @(offset),
        @"returned" : @0,
        @"total" : @0,
      },
      @"engine" : self.runtime.engineIdentifier ?: @"ALNDefaultSearchEngine",
      @"engineCapabilities" : [self.runtime.engine searchModuleCapabilities] ?: @{},
      @"cursor" : @{ @"requested" : @"", @"next" : @"", @"supported" : @NO },
    };
  }
  NSMutableDictionary *resourceFilters = [NSMutableDictionary dictionary];
  for (NSDictionary *metadata in visibleResources) {
    NSDictionary *extra = [self.runtime additionalQueryFiltersForResourceMetadata:metadata context:ctx error:error];
    if (extra == nil && error != NULL && *error != nil) {
      return nil;
    }
    if ([extra count] > 0) {
      resourceFilters[STLowerTrimmedString(metadata[@"identifier"])] = extra;
    }
  }
  NSMutableDictionary *queryOptions = [NSMutableDictionary dictionaryWithDictionary:[self searchQueryOptionsFromParameters:parameters] ?: @{}];
  if ([resourceFilters count] > 0) {
    queryOptions[@"resourceFilters"] = resourceFilters;
  }
  return [self.runtime searchQuery:parameters[@"q"]
                resourceIdentifier:resourceIdentifier
          allowedResourceIdentifiers:[self.runtime resourceIdentifiersFromMetadataArray:visibleResources]
                           filters:explicitFilters
                              sort:parameters[@"sort"]
                             limit:limit
                            offset:offset
                      queryOptions:queryOptions
                             error:error];
}

- (id)queryHTML:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSArray *visibleResources = [self queryableResourcesForContext:ctx resourceIdentifier:nil error:&error] ?: @[];
  if (error != nil && [self renderSearchErrorHTML:error context:ctx]) {
    return nil;
  }
  NSDictionary *result = [self searchResultFromParameters:parameters resourceIdentifier:nil context:ctx error:&error];
  if (result == nil && error != nil && [self renderSearchErrorHTML:error context:ctx]) {
    return nil;
  }
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
                                              @"searchSummary" : [self searchSummaryForVisibleResources:visibleResources] ?: @{},
                                              @"searchResources" : visibleResources ?: @[],
                                            }]
                layout:@"modules/search/layouts/main"
                 error:NULL];
  return nil;
}

- (id)resourceQueryHTML:(ALNContext *)ctx {
  NSString *resource = STLowerTrimmedString([ctx paramValueForName:@"resource"]);
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSArray *visibleResources = [self queryableResourcesForContext:ctx resourceIdentifier:nil error:&error] ?: @[];
  if (error != nil && [self renderSearchErrorHTML:error context:ctx]) {
    return nil;
  }
  NSDictionary *result = [self searchResultFromParameters:parameters resourceIdentifier:resource context:ctx error:&error];
  if (result == nil && error != nil && [self renderSearchErrorHTML:error context:ctx]) {
    return nil;
  }
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
                                              @"searchSummary" : [self searchSummaryForVisibleResources:visibleResources] ?: @{},
                                              @"searchResources" : visibleResources ?: @[],
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
  NSError *error = nil;
  NSArray *resources = [self queryableResourcesForContext:ctx resourceIdentifier:nil error:&error];
  if (resources == nil) {
    NSDictionary *presentation = [self apiErrorPresentationForError:error];
    [self renderAPIErrorWithStatus:[presentation[@"status"] integerValue]
                              code:presentation[@"code"]
                           message:error.localizedDescription ?: @"search failed"
                              meta:nil];
    return nil;
  }
  [self renderJSONEnvelopeWithData:@{
    @"resources" : resources ?: @[],
    @"engine" : self.runtime.engineIdentifier ?: @"ALNDefaultSearchEngine",
    @"engineCapabilities" : [self.runtime.engine searchModuleCapabilities] ?: @{},
  }
                          meta:nil
                         error:NULL];
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
  NSError *error = nil;
  NSDictionary *result = [self searchResultFromParameters:[self requestParameters] resourceIdentifier:nil context:ctx error:&error];
  if (result == nil) {
    NSDictionary *presentation = [self apiErrorPresentationForError:error];
    [self renderAPIErrorWithStatus:[presentation[@"status"] integerValue]
                              code:presentation[@"code"]
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
  NSDictionary *result = [self searchResultFromParameters:[self requestParameters]
                                       resourceIdentifier:resource
                                                  context:ctx
                                                    error:&error];
  if (result == nil) {
    NSDictionary *presentation = [self apiErrorPresentationForError:error];
    [self renderAPIErrorWithStatus:[presentation[@"status"] integerValue]
                              code:presentation[@"code"]
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
  STRegisterSearchModuleTemplates();

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

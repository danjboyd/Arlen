#import "ALNAdminUIModule.h"

#import "../../auth/Sources/ALNAuthModule.h"

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNPg.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNRoute.h"
#import "ALNRouter.h"

NSString *const ALNAdminUIModuleErrorDomain = @"Arlen.Modules.AdminUI.Error";

static NSString *AUTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *AULowerTrimmedString(id value) {
  return [[AUTrimmedString(value) lowercaseString] copy];
}

static NSDictionary *AUNormalizeDictionary(id value) {
  return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

static NSArray *AUNormalizeArray(id value) {
  return [value isKindOfClass:[NSArray class]] ? value : @[];
}

static BOOL AUBoolValue(id value, BOOL fallbackValue) {
  if ([value respondsToSelector:@selector(boolValue)]) {
    return [value boolValue];
  }
  NSString *string = AULowerTrimmedString(value);
  if ([string length] == 0) {
    return fallbackValue;
  }
  return [string isEqualToString:@"1"] || [string isEqualToString:@"true"] || [string isEqualToString:@"yes"] ||
         [string isEqualToString:@"t"];
}

static BOOL AUBoolFromDatabaseValue(id value) {
  return AUBoolValue(value, NO);
}

static NSArray *AUJSONArrayFromJSONString(id value) {
  NSString *json = AUTrimmedString(value);
  if ([json length] == 0) {
    return @[];
  }
  NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
  if (![object isKindOfClass:[NSArray class]]) {
    return @[];
  }
  NSMutableArray *normalized = [NSMutableArray array];
  for (id entry in (NSArray *)object) {
    NSString *string = AULowerTrimmedString(entry);
    if ([string length] == 0 || [normalized containsObject:string]) {
      continue;
    }
    [normalized addObject:string];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSString *AUJSONString(id object) {
  if (object == nil) {
    return @"[]";
  }
  NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
  if (data == nil) {
    return @"[]";
  }
  NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  return string ?: @"[]";
}

static NSString *AUPathJoin(NSString *prefix, NSString *suffix) {
  NSString *cleanPrefix = AUTrimmedString(prefix);
  if ([cleanPrefix length] == 0) {
    cleanPrefix = @"/";
  }
  if (![cleanPrefix hasPrefix:@"/"]) {
    cleanPrefix = [@"/" stringByAppendingString:cleanPrefix];
  }
  while ([cleanPrefix hasSuffix:@"/"] && [cleanPrefix length] > 1) {
    cleanPrefix = [cleanPrefix substringToIndex:([cleanPrefix length] - 1)];
  }
  NSString *cleanSuffix = AUTrimmedString(suffix);
  while ([cleanSuffix hasPrefix:@"/"]) {
    cleanSuffix = [cleanSuffix substringFromIndex:1];
  }
  if ([cleanSuffix length] == 0) {
    return cleanPrefix;
  }
  if ([cleanPrefix isEqualToString:@"/"]) {
    return [@"/" stringByAppendingString:cleanSuffix];
  }
  return [NSString stringWithFormat:@"%@/%@", cleanPrefix, cleanSuffix];
}

static NSString *AUPercentEncodedQueryComponent(NSString *value) {
  NSString *string = AUTrimmedString(value);
  if ([string length] == 0) {
    return @"";
  }
  return [string stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"";
}

static NSError *AUError(ALNAdminUIModuleErrorCode code, NSString *message, NSDictionary *details) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:details ?: @{}];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"admin ui module error";
  return [NSError errorWithDomain:ALNAdminUIModuleErrorDomain code:code userInfo:userInfo];
}

static NSString *AUTitleCaseIdentifier(NSString *identifier) {
  NSString *normalized = AUTrimmedString(identifier);
  if ([normalized length] == 0) {
    return @"Resource";
  }
  NSArray *components = [[normalized stringByReplacingOccurrencesOfString:@"_" withString:@"-"] componentsSeparatedByString:@"-"];
  NSMutableArray *words = [NSMutableArray array];
  for (NSString *component in components) {
    NSString *word = AUTrimmedString(component);
    if ([word length] == 0) {
      continue;
    }
    [words addObject:[word capitalizedString]];
  }
  return ([words count] > 0) ? [words componentsJoinedByString:@" "] : @"Resource";
}

static NSDictionary *AUQueryParametersFromBody(NSData *body) {
  if ([body length] == 0) {
    return @{};
  }
  NSString *raw = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
  if ([raw length] == 0) {
    return @{};
  }
  NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
  for (NSString *pair in [raw componentsSeparatedByString:@"&"]) {
    if ([pair length] == 0) {
      continue;
    }
    NSRange separator = [pair rangeOfString:@"="];
    NSString *name = nil;
    NSString *value = nil;
    if (separator.location == NSNotFound) {
      name = pair;
      value = @"";
    } else {
      name = [pair substringToIndex:separator.location];
      value = [pair substringFromIndex:(separator.location + 1)];
    }
    NSString *decodedName = [[name stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding] ?: @"";
    if ([decodedName length] == 0) {
      continue;
    }
    NSString *decodedValue = [[value stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding] ?: @"";
    parameters[decodedName] = decodedValue;
  }
  return parameters;
}

static NSDictionary *AUUserDictionaryFromRow(NSDictionary *row) {
  if (![row isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  NSString *subject = AUTrimmedString(row[@"subject"]);
  if ([subject length] == 0) {
    return nil;
  }
  return @{
    @"id" : AUTrimmedString(row[@"id"]),
    @"subject" : subject,
    @"email" : AULowerTrimmedString(row[@"email"]),
    @"display_name" : AUTrimmedString(row[@"display_name"]),
    @"roles" : AUJSONArrayFromJSONString(row[@"roles_json"]),
    @"email_verified" : @(AUBoolFromDatabaseValue(row[@"email_verified"])),
    @"mfa_enabled" : @(AUBoolFromDatabaseValue(row[@"mfa_enabled"])),
    @"provider_identity_count" : @([AUTrimmedString(row[@"provider_identity_count"]) integerValue]),
    @"created_at" : AUTrimmedString(row[@"created_at"]),
    @"updated_at" : AUTrimmedString(row[@"updated_at"]),
  };
}

static NSString *AUStringifyValue(id value) {
  if ([value isKindOfClass:[NSString class]]) {
    return value;
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [value stringValue];
  }
  if ([value isKindOfClass:[NSArray class]]) {
    NSMutableArray *parts = [NSMutableArray array];
    for (id entry in (NSArray *)value) {
      NSString *piece = AUStringifyValue(entry);
      if ([piece length] > 0) {
        [parts addObject:piece];
      }
    }
    return [parts componentsJoinedByString:@", "];
  }
  if ([value isKindOfClass:[NSDictionary class]]) {
    NSString *label = AUTrimmedString(value[@"label"]);
    if ([label length] > 0) {
      return label;
    }
    return AUTrimmedString(value[@"value"]);
  }
  return @"";
}

static NSArray<NSDictionary *> *AUNormalizedChoiceArray(id rawChoices) {
  NSMutableArray *normalized = [NSMutableArray array];
  NSMutableSet *seenValues = [NSMutableSet set];
  for (id entry in AUNormalizeArray(rawChoices)) {
    NSString *value = @"";
    NSString *label = @"";
    if ([entry isKindOfClass:[NSDictionary class]]) {
      value = AUTrimmedString(entry[@"value"]);
      label = AUTrimmedString(entry[@"label"]);
    } else {
      value = AUTrimmedString(entry);
    }
    if ([value length] == 0 || [seenValues containsObject:value]) {
      continue;
    }
    [seenValues addObject:value];
    [normalized addObject:@{
      @"value" : value,
      @"label" : ([label length] > 0) ? label : value,
    }];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSArray<NSString *> *AUNormalizedStringValueArray(id rawValues) {
  NSMutableArray<NSString *> *normalized = [NSMutableArray array];
  for (id entry in AUNormalizeArray(rawValues)) {
    NSString *value = AULowerTrimmedString([entry isKindOfClass:[NSDictionary class]] ? entry[@"value"] : entry);
    if ([value length] == 0 || [normalized containsObject:value]) {
      continue;
    }
    [normalized addObject:value];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSArray<NSNumber *> *AUNormalizedPositiveIntegerArray(id rawValues) {
  NSMutableArray<NSNumber *> *normalized = [NSMutableArray array];
  NSMutableSet<NSNumber *> *seenValues = [NSMutableSet set];
  for (id entry in AUNormalizeArray(rawValues)) {
    NSUInteger value = 0U;
    if ([entry respondsToSelector:@selector(unsignedIntegerValue)]) {
      value = [entry unsignedIntegerValue];
    } else {
      NSString *stringValue = AUTrimmedString([entry isKindOfClass:[NSDictionary class]] ? entry[@"value"] : entry);
      value = (NSUInteger)[stringValue integerValue];
    }
    if (value == 0U) {
      continue;
    }
    NSNumber *boxedValue = @(value);
    if ([seenValues containsObject:boxedValue]) {
      continue;
    }
    [seenValues addObject:boxedValue];
    [normalized addObject:boxedValue];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSString *AUResolvedFilterInputType(NSString *type) {
  NSString *normalizedType = AULowerTrimmedString(type);
  if ([normalizedType isEqualToString:@"search"]) {
    return @"search";
  }
  if ([normalizedType isEqualToString:@"date"] || [normalizedType isEqualToString:@"email"] ||
      [normalizedType isEqualToString:@"month"] || [normalizedType isEqualToString:@"week"] ||
      [normalizedType isEqualToString:@"time"]) {
    return normalizedType;
  }
  if ([normalizedType isEqualToString:@"datetime"] || [normalizedType isEqualToString:@"datetime-local"]) {
    return @"datetime-local";
  }
  if ([normalizedType isEqualToString:@"integer"] || [normalizedType isEqualToString:@"decimal"] ||
      [normalizedType isEqualToString:@"number"] || [normalizedType isEqualToString:@"range"]) {
    return @"number";
  }
  return @"text";
}

static NSArray<NSDictionary *> *AUNormalizedFieldArray(id rawFields) {
  NSArray *fields = AUNormalizeArray(rawFields);
  NSMutableArray *normalized = [NSMutableArray array];
  NSMutableSet *seenNames = [NSMutableSet set];
  for (id entry in fields) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *name = AULowerTrimmedString(entry[@"name"]);
    if ([name length] == 0 || [seenNames containsObject:name]) {
      continue;
    }
    [seenNames addObject:name];
    NSString *kind = ([AULowerTrimmedString(entry[@"kind"]) length] > 0) ? AULowerTrimmedString(entry[@"kind"]) : @"string";
    NSString *inputType = AULowerTrimmedString(entry[@"inputType"]);
    if ([inputType length] == 0) {
      inputType = ([kind isEqualToString:@"boolean"])
                      ? @"checkbox"
                      : (([kind isEqualToString:@"integer"] || [kind isEqualToString:@"number"]) ? @"number"
                                                                                                : (([kind isEqualToString:@"date"] || [kind isEqualToString:@"datetime"])
                                                                                                       ? kind
                                                                                                       : (([kind isEqualToString:@"email"]) ? @"email" : @"text")));
    }
    NSDictionary *autocomplete = AUNormalizeDictionary(entry[@"autocomplete"]);
    [normalized addObject:@{
      @"name" : name,
      @"label" : ([AUTrimmedString(entry[@"label"]) length] > 0) ? AUTrimmedString(entry[@"label"]) : AUTitleCaseIdentifier(name),
      @"kind" : kind,
      @"inputType" : inputType,
      @"list" : @(AUBoolValue(entry[@"list"], YES)),
      @"detail" : @(AUBoolValue(entry[@"detail"], YES)),
      @"editable" : @(AUBoolValue(entry[@"editable"], NO)),
      @"required" : @(AUBoolValue(entry[@"required"], NO)),
      @"multiline" : @(AUBoolValue(entry[@"multiline"], NO)),
      @"placeholder" : AUTrimmedString(entry[@"placeholder"]),
      @"choices" : AUNormalizedChoiceArray(entry[@"choices"]),
      @"autocomplete" : @{
        @"enabled" : @(AUBoolValue(autocomplete[@"enabled"], [autocomplete count] > 0)),
        @"minQueryLength" : @([autocomplete[@"minQueryLength"] respondsToSelector:@selector(unsignedIntegerValue)]
                                  ? [autocomplete[@"minQueryLength"] unsignedIntegerValue]
                                  : 1U),
      },
    }];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSArray<NSDictionary *> *AUNormalizedFilterArray(id rawFilters) {
  NSArray *filters = AUNormalizeArray(rawFilters);
  NSMutableArray *normalized = [NSMutableArray array];
  NSMutableSet *seenNames = [NSMutableSet set];
  for (id entry in filters) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *name = AULowerTrimmedString(entry[@"name"]);
    if ([name length] == 0 || [seenNames containsObject:name]) {
      continue;
    }
    [seenNames addObject:name];
    [normalized addObject:@{
      @"name" : name,
      @"label" : ([AUTrimmedString(entry[@"label"]) length] > 0) ? AUTrimmedString(entry[@"label"]) : AUTitleCaseIdentifier(name),
      @"type" : ([AULowerTrimmedString(entry[@"type"]) length] > 0) ? AULowerTrimmedString(entry[@"type"]) : @"search",
      @"inputType" : AUResolvedFilterInputType(entry[@"type"]),
      @"placeholder" : AUTrimmedString(entry[@"placeholder"]),
      @"operators" : AUNormalizedStringValueArray(entry[@"operators"]),
      @"field" : ([AULowerTrimmedString(entry[@"field"]) length] > 0) ? AULowerTrimmedString(entry[@"field"]) : name,
      @"choices" : AUNormalizedChoiceArray(entry[@"choices"]),
      @"min" : AUTrimmedString(entry[@"min"]),
      @"max" : AUTrimmedString(entry[@"max"]),
      @"step" : AUTrimmedString(entry[@"step"]),
    }];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSArray<NSDictionary *> *AUNormalizedSortArray(id rawSorts) {
  NSArray *sorts = AUNormalizeArray(rawSorts);
  NSMutableArray *normalized = [NSMutableArray array];
  NSMutableSet *seenNames = [NSMutableSet set];
  for (id entry in sorts) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *name = AULowerTrimmedString(entry[@"name"]);
    if ([name length] == 0 || [seenNames containsObject:name]) {
      continue;
    }
    [seenNames addObject:name];
    [normalized addObject:@{
      @"name" : name,
      @"label" : ([AUTrimmedString(entry[@"label"]) length] > 0) ? AUTrimmedString(entry[@"label"]) : AUTitleCaseIdentifier(name),
      @"default" : @(AUBoolValue(entry[@"default"], NO)),
      @"direction" : ([AULowerTrimmedString(entry[@"direction"]) length] > 0) ? AULowerTrimmedString(entry[@"direction"]) : @"asc",
      @"optional" : @(AUBoolValue(entry[@"optional"], YES)),
    }];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSArray<NSDictionary *> *AUNormalizedActionArray(id rawActions) {
  NSArray *actions = AUNormalizeArray(rawActions);
  NSMutableArray *normalized = [NSMutableArray array];
  NSMutableSet *seenNames = [NSMutableSet set];
  for (id entry in actions) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *name = AULowerTrimmedString(entry[@"name"]);
    if ([name length] == 0 || [seenNames containsObject:name]) {
      continue;
    }
    [seenNames addObject:name];
    [normalized addObject:@{
      @"name" : name,
      @"label" : ([AUTrimmedString(entry[@"label"]) length] > 0) ? AUTrimmedString(entry[@"label"]) : AUTitleCaseIdentifier(name),
      @"scope" : ([AULowerTrimmedString(entry[@"scope"]) length] > 0) ? AULowerTrimmedString(entry[@"scope"]) : @"row",
      @"method" : ([AULowerTrimmedString(entry[@"method"]) length] > 0) ? [AULowerTrimmedString(entry[@"method"]) uppercaseString] : @"POST",
      @"requires_aal2" : @(AUBoolValue(entry[@"requires_aal2"], YES)),
    }];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSArray<NSDictionary *> *AUNormalizedBulkActionArray(id rawActions) {
  NSArray *actions = AUNormalizeArray(rawActions);
  NSMutableArray *normalized = [NSMutableArray array];
  NSMutableSet *seenNames = [NSMutableSet set];
  for (id entry in actions) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *name = AULowerTrimmedString(entry[@"name"]);
    if ([name length] == 0 || [seenNames containsObject:name]) {
      continue;
    }
    [seenNames addObject:name];
    [normalized addObject:@{
      @"name" : name,
      @"label" : ([AUTrimmedString(entry[@"label"]) length] > 0) ? AUTrimmedString(entry[@"label"]) : AUTitleCaseIdentifier(name),
      @"method" : ([AULowerTrimmedString(entry[@"method"]) length] > 0) ? [AULowerTrimmedString(entry[@"method"]) uppercaseString] : @"POST",
      @"requires_aal2" : @(AUBoolValue(entry[@"requires_aal2"], YES)),
    }];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSArray<NSDictionary *> *AUNormalizedExportArray(id rawExports) {
  NSArray *exports = AUNormalizeArray(rawExports);
  NSMutableArray *normalized = [NSMutableArray array];
  NSMutableSet *seenFormats = [NSMutableSet set];
  for (id entry in exports) {
    NSString *format = @"";
    NSString *label = @"";
    if ([entry isKindOfClass:[NSDictionary class]]) {
      format = AULowerTrimmedString(entry[@"format"]);
      label = AUTrimmedString(entry[@"label"]);
    } else {
      format = AULowerTrimmedString(entry);
    }
    if ((![format isEqualToString:@"json"] && ![format isEqualToString:@"csv"]) || [seenFormats containsObject:format]) {
      continue;
    }
    [seenFormats addObject:format];
    [normalized addObject:@{
      @"format" : format,
      @"label" : ([label length] > 0) ? label : [format uppercaseString],
    }];
  }
  if ([normalized count] == 0) {
    return @[ @{ @"format" : @"json", @"label" : @"JSON" }, @{ @"format" : @"csv", @"label" : @"CSV" } ];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSDictionary *AUAdminMetadataPathSchema(NSString *name, NSString *description) {
  return @{
    @"type" : @"object",
    @"properties" : @{
      @"resource" : @{
        @"type" : @"string",
        @"source" : @"path",
        @"description" : name ?: @"resource identifier",
      },
    },
    @"required" : @[ @"resource" ],
    @"description" : description ?: @"resource path schema",
  };
}

static NSDictionary *AUAdminMetadataActionSchema(void) {
  return @{
    @"type" : @"object",
    @"properties" : @{
      @"resource" : @{ @"type" : @"string", @"source" : @"path" },
      @"identifier" : @{ @"type" : @"string", @"source" : @"path" },
      @"action" : @{ @"type" : @"string", @"source" : @"path" },
    },
    @"required" : @[ @"resource", @"identifier", @"action" ],
  };
}

static NSArray<NSString *> *AUNormalizedIdentifierArray(id values) {
  NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
  for (id entry in AUNormalizeArray(values)) {
    NSString *identifier = AUTrimmedString(entry);
    if ([identifier length] == 0 || [identifiers containsObject:identifier]) {
      continue;
    }
    [identifiers addObject:identifier];
  }
  return [NSArray arrayWithArray:identifiers];
}

static void AUNotifySearchIncrementalSync(NSString *resourceIdentifier, NSDictionary *record, NSString *operation) {
  Class runtimeClass = NSClassFromString(@"ALNSearchModuleRuntime");
  if (runtimeClass == Nil || ![runtimeClass respondsToSelector:@selector(sharedRuntime)]) {
    return;
  }
  id (*sharedRuntimeIMP)(id, SEL) = (id (*)(id, SEL))[runtimeClass methodForSelector:@selector(sharedRuntime)];
  id runtime = sharedRuntimeIMP(runtimeClass, @selector(sharedRuntime));
  if (![runtime respondsToSelector:@selector(application)] || [runtime valueForKey:@"application"] == nil) {
    return;
  }
  SEL selector = @selector(queueIncrementalSyncForResourceIdentifier:record:operation:error:);
  if (![runtime respondsToSelector:selector]) {
    return;
  }
  NSDictionary *safeRecord = [record isKindOfClass:[NSDictionary class]] ? record : @{};
  NSError *error = nil;
  NSDictionary *(*syncIMP)(id, SEL, NSString *, NSDictionary *, NSString *, NSError **) =
      (NSDictionary *(*)(id, SEL, NSString *, NSDictionary *, NSString *, NSError **))[runtime methodForSelector:selector];
  (void)syncIMP(runtime, selector, AUTrimmedString(resourceIdentifier), safeRecord, AULowerTrimmedString(operation), &error);
}

@interface ALNAdminUIResourceDescriptor : NSObject

@property(nonatomic, strong) id<ALNAdminUIResource> resource;
@property(nonatomic, copy) NSDictionary *metadata;

@end

@implementation ALNAdminUIResourceDescriptor
@end

@interface ALNAdminUIUsersResource : NSObject <ALNAdminUIResource>

@property(nonatomic, strong) ALNAdminUIModuleRuntime *runtime;

- (instancetype)initWithRuntime:(ALNAdminUIModuleRuntime *)runtime;

@end

@interface ALNAdminUIModuleRuntime ()

@property(nonatomic, strong, readwrite) ALNPg *database;
@property(nonatomic, copy) NSDictionary *moduleConfig;
@property(nonatomic, copy) NSDictionary *applicationConfig;
@property(nonatomic, copy, readwrite) NSString *mountPrefix;
@property(nonatomic, copy, readwrite) NSString *apiPrefix;
@property(nonatomic, copy, readwrite) NSString *dashboardTitle;
@property(nonatomic, strong, readwrite) ALNApplication *mountedApplication;
@property(nonatomic, copy) NSArray<ALNAdminUIResourceDescriptor *> *resourceDescriptors;
@property(nonatomic, copy) NSDictionary<NSString *, ALNAdminUIResourceDescriptor *> *resourceDescriptorMap;
@property(nonatomic, copy) NSDictionary<NSString *, ALNAdminUIResourceDescriptor *> *legacyResourceDescriptorMap;

- (nullable ALNAdminUIResourceDescriptor *)descriptorForIdentifier:(NSString *)identifier;
- (nullable NSDictionary *)normalizedMetadataForResource:(id<ALNAdminUIResource>)resource
                                                   error:(NSError **)error;
- (NSArray<NSString *> *)configuredResourceProviderClassNames;
- (BOOL)loadResourceRegistryWithError:(NSError **)error;

@end

@interface ALNAdminUIController : ALNController
@end

@implementation ALNAdminUIUsersResource

- (instancetype)initWithRuntime:(ALNAdminUIModuleRuntime *)runtime {
  self = [super init];
  if (self != nil) {
    _runtime = runtime;
  }
  return self;
}

- (NSString *)adminUIResourceIdentifier {
  return @"users";
}

- (NSDictionary *)adminUIResourceMetadata {
  return @{
    @"label" : @"Users",
    @"singularLabel" : @"User",
    @"summary" : @"Manage registered accounts, roles, and MFA posture from one admin contract.",
    @"primaryField" : @"email",
    @"identifierField" : @"subject",
    @"legacyPath" : @"users",
    @"pageSize" : @25,
    @"pageSizes" : @[ @25, @50, @100 ],
    @"fields" : @[
      @{ @"name" : @"email", @"label" : @"Email", @"kind" : @"email", @"list" : @YES, @"detail" : @YES },
      @{
        @"name" : @"display_name",
        @"label" : @"Display",
        @"kind" : @"string",
        @"list" : @YES,
        @"detail" : @YES,
        @"editable" : @YES,
        @"required" : @YES,
        @"placeholder" : @"Display name",
      },
      @{
        @"name" : @"roles",
        @"label" : @"Roles",
        @"kind" : @"array",
        @"list" : @YES,
        @"detail" : @YES,
        @"choices" : @[ @"user", @"admin" ],
        @"autocomplete" : @{ @"enabled" : @YES, @"minQueryLength" : @1 },
      },
      @{ @"name" : @"email_verified", @"label" : @"Verified", @"kind" : @"boolean", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"mfa_enabled", @"label" : @"MFA", @"kind" : @"boolean", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"provider_identity_count", @"label" : @"Providers", @"kind" : @"integer", @"detail" : @YES, @"list" : @NO },
      @{ @"name" : @"subject", @"label" : @"Subject", @"kind" : @"string", @"detail" : @YES, @"list" : @NO },
      @{ @"name" : @"created_at", @"label" : @"Created", @"kind" : @"datetime", @"detail" : @YES, @"list" : @NO },
      @{ @"name" : @"updated_at", @"label" : @"Updated", @"kind" : @"datetime", @"detail" : @YES, @"list" : @NO },
    ],
    @"filters" : @[
      @{
        @"name" : @"q",
        @"label" : @"Search",
        @"type" : @"search",
        @"placeholder" : @"email, display name, subject",
      },
      @{
        @"name" : @"roles",
        @"label" : @"Role",
        @"type" : @"select",
        @"choices" : @[ @"user", @"admin" ],
      },
      @{
        @"name" : @"email_verified",
        @"label" : @"Verified",
        @"type" : @"select",
        @"choices" : @[
          @{ @"value" : @"true", @"label" : @"Verified" },
          @{ @"value" : @"false", @"label" : @"Unverified" },
        ],
      },
      @{
        @"name" : @"mfa_enabled",
        @"label" : @"MFA",
        @"type" : @"select",
        @"choices" : @[
          @{ @"value" : @"true", @"label" : @"Enabled" },
          @{ @"value" : @"false", @"label" : @"Disabled" },
        ],
      },
    ],
    @"sorts" : @[
      @{ @"name" : @"created_at", @"label" : @"Created", @"default" : @YES, @"direction" : @"desc" },
      @{ @"name" : @"updated_at", @"label" : @"Updated", @"direction" : @"desc" },
      @{ @"name" : @"email", @"label" : @"Email" },
      @{ @"name" : @"display_name", @"label" : @"Display name" },
    ],
    @"bulkActions" : @[
      @{ @"name" : @"grant_admin", @"label" : @"Grant admin", @"method" : @"POST" },
      @{ @"name" : @"revoke_admin", @"label" : @"Revoke admin", @"method" : @"POST" },
    ],
    @"exports" : @[ @"json", @"csv" ],
    @"actions" : @[
      @{ @"name" : @"grant_admin", @"label" : @"Grant admin", @"scope" : @"row", @"method" : @"POST" },
      @{ @"name" : @"revoke_admin", @"label" : @"Revoke admin", @"scope" : @"row", @"method" : @"POST" },
    ],
  };
}

- (NSDictionary *)loadUserBySQL:(NSString *)sql
                     parameters:(NSArray *)parameters
                          error:(NSError **)error {
  if (self.runtime.database == nil) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorDatabaseUnavailable, @"admin-ui database is not configured", nil);
    }
    return nil;
  }
  NSDictionary *row = [[self.runtime.database executeQuery:(sql ?: @"") parameters:(parameters ?: @[]) error:error] firstObject];
  return AUUserDictionaryFromRow(row);
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
  if (self.runtime.database == nil) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorDatabaseUnavailable, @"admin-ui database is not configured", nil);
    }
    return nil;
  }
  NSString *search = AULowerTrimmedString(parameters[@"q"]);
  NSString *like = ([search length] > 0) ? [NSString stringWithFormat:@"%%%@%%", search] : @"";
  NSString *role = AULowerTrimmedString(parameters[@"roles"]);
  NSString *verified = AULowerTrimmedString(parameters[@"email_verified"]);
  NSString *mfaEnabled = AULowerTrimmedString(parameters[@"mfa_enabled"]);
  NSString *sort = AULowerTrimmedString(parameters[@"sort"]);
  NSString *orderBy = @"u.created_at DESC, u.id DESC";
  if ([sort isEqualToString:@"email"]) {
    orderBy = @"lower(u.email) ASC, u.id DESC";
  } else if ([sort isEqualToString:@"-email"]) {
    orderBy = @"lower(u.email) DESC, u.id DESC";
  } else if ([sort isEqualToString:@"display_name"]) {
    orderBy = @"lower(COALESCE(u.display_name, '')) ASC, u.id DESC";
  } else if ([sort isEqualToString:@"-display_name"]) {
    orderBy = @"lower(COALESCE(u.display_name, '')) DESC, u.id DESC";
  } else if ([sort isEqualToString:@"updated_at"]) {
    orderBy = @"u.updated_at ASC, u.id DESC";
  } else if ([sort isEqualToString:@"-updated_at"]) {
    orderBy = @"u.updated_at DESC, u.id DESC";
  } else if ([sort isEqualToString:@"created_at"]) {
    orderBy = @"u.created_at ASC, u.id DESC";
  }

  NSMutableString *sql = [NSMutableString stringWithString:
      @"SELECT u.id::text AS id, u.subject, u.email, "
       "COALESCE(u.display_name, '') AS display_name, "
       "COALESCE(u.roles_json, '[]') AS roles_json, "
       "CASE WHEN u.email_verified_at IS NULL THEN 'f' ELSE 't' END AS email_verified, "
       "CASE WHEN EXISTS (SELECT 1 FROM auth_mfa_enrollments m WHERE m.user_id = u.id AND m.enabled = TRUE) "
       "THEN 't' ELSE 'f' END AS mfa_enabled, "
       "(SELECT COUNT(*)::text FROM auth_provider_identities p WHERE p.user_id = u.id) AS provider_identity_count, "
       "COALESCE(u.created_at::text, '') AS created_at, "
       "COALESCE(u.updated_at::text, '') AS updated_at "
       "FROM auth_users u WHERE 1 = 1 "];
  NSMutableArray *sqlParameters = [NSMutableArray array];
  NSUInteger parameterIndex = 1U;
  if ([search length] > 0) {
    [sql appendFormat:@"AND ($%lu = '' OR lower(u.email) LIKE $%lu OR lower(COALESCE(u.display_name, '')) LIKE $%lu OR lower(u.subject) LIKE $%lu) ",
                      (unsigned long)parameterIndex,
                      (unsigned long)(parameterIndex + 1U),
                      (unsigned long)(parameterIndex + 1U),
                      (unsigned long)(parameterIndex + 1U)];
    [sqlParameters addObject:search ?: @""];
    [sqlParameters addObject:like ?: @""];
    parameterIndex += 2U;
  }
  if ([role length] > 0) {
    [sql appendFormat:@"AND lower(COALESCE(u.roles_json, '[]')) LIKE $%lu ", (unsigned long)parameterIndex];
    [sqlParameters addObject:[NSString stringWithFormat:@"%%\"%@\"%%", role]];
    parameterIndex += 1U;
  }
  if ([verified isEqualToString:@"true"] || [verified isEqualToString:@"false"]) {
    [sql appendFormat:@"AND (CASE WHEN u.email_verified_at IS NULL THEN 'false' ELSE 'true' END) = $%lu ",
                      (unsigned long)parameterIndex];
    [sqlParameters addObject:verified];
    parameterIndex += 1U;
  }
  if ([mfaEnabled isEqualToString:@"true"] || [mfaEnabled isEqualToString:@"false"]) {
    [sql appendFormat:@"AND (CASE WHEN EXISTS (SELECT 1 FROM auth_mfa_enrollments m WHERE m.user_id = u.id AND m.enabled = TRUE) THEN 'true' ELSE 'false' END) = $%lu ",
                      (unsigned long)parameterIndex];
    [sqlParameters addObject:mfaEnabled];
    parameterIndex += 1U;
  }
  [sql appendFormat:@"ORDER BY %@ LIMIT $%lu OFFSET $%lu",
                    orderBy,
                    (unsigned long)parameterIndex,
                    (unsigned long)(parameterIndex + 1U)];
  [sqlParameters addObject:@(limit)];
  [sqlParameters addObject:@(offset)];

  NSArray *rows = [self.runtime.database executeQuery:sql parameters:sqlParameters error:error];
  if (rows == nil) {
    return nil;
  }
  NSMutableArray *users = [NSMutableArray array];
  for (NSDictionary *row in rows) {
    NSDictionary *user = AUUserDictionaryFromRow(row);
    if (user != nil) {
      [users addObject:user];
    }
  }
  return [NSArray arrayWithArray:users];
}

- (NSDictionary *)adminUIDetailRecordForIdentifier:(NSString *)identifier
                                             error:(NSError **)error {
  NSString *subject = AUTrimmedString(identifier);
  if ([subject length] == 0) {
    return nil;
  }
  return [self loadUserBySQL:@"SELECT u.id::text AS id, u.subject, u.email, "
                             "COALESCE(u.display_name, '') AS display_name, "
                             "COALESCE(u.roles_json, '[]') AS roles_json, "
                             "CASE WHEN u.email_verified_at IS NULL THEN 'f' ELSE 't' END AS email_verified, "
                             "CASE WHEN EXISTS (SELECT 1 FROM auth_mfa_enrollments m WHERE m.user_id = u.id AND m.enabled = TRUE) "
                             "THEN 't' ELSE 'f' END AS mfa_enabled, "
                             "(SELECT COUNT(*)::text FROM auth_provider_identities p WHERE p.user_id = u.id) AS provider_identity_count, "
                             "COALESCE(u.created_at::text, '') AS created_at, "
                             "COALESCE(u.updated_at::text, '') AS updated_at "
                             "FROM auth_users u WHERE u.subject = $1 LIMIT 1"
                   parameters:@[ subject ]
                        error:error];
}

- (NSDictionary *)adminUIUpdateRecordWithIdentifier:(NSString *)identifier
                                         parameters:(NSDictionary *)parameters
                                              error:(NSError **)error {
  NSString *subject = AUTrimmedString(identifier);
  if ([subject length] == 0) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorValidationFailed, @"subject is required", @{ @"field" : @"subject" });
    }
    return nil;
  }
  NSString *displayName = AUTrimmedString(parameters[@"display_name"]);
  if ([displayName length] == 0) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorValidationFailed,
                       @"display name is required",
                       @{ @"field" : @"display_name" });
    }
    return nil;
  }
  NSDictionary *row = [[self.runtime.database
      executeQuery:@"UPDATE auth_users SET display_name = $2, updated_at = NOW() "
                   "WHERE subject = $1 "
                   "RETURNING id::text AS id, subject, email, "
                   "COALESCE(display_name, '') AS display_name, "
                   "COALESCE(roles_json, '[]') AS roles_json, "
                   "CASE WHEN email_verified_at IS NULL THEN 'f' ELSE 't' END AS email_verified, "
                   "CASE WHEN EXISTS (SELECT 1 FROM auth_mfa_enrollments m WHERE m.user_id = auth_users.id AND m.enabled = TRUE) "
                   "THEN 't' ELSE 'f' END AS mfa_enabled, "
                   "(SELECT COUNT(*)::text FROM auth_provider_identities p WHERE p.user_id = auth_users.id) AS provider_identity_count, "
                   "COALESCE(created_at::text, '') AS created_at, "
                   "COALESCE(updated_at::text, '') AS updated_at"
        parameters:@[ subject, displayName ]
             error:error] firstObject];
  NSDictionary *user = AUUserDictionaryFromRow(row);
  if (user == nil && error != NULL && *error == NULL) {
    *error = AUError(ALNAdminUIModuleErrorNotFound, @"user not found", nil);
  }
  return user;
}

- (NSDictionary *)adminUIDashboardSummaryWithError:(NSError **)error {
  if (self.runtime.database == nil) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorDatabaseUnavailable, @"admin-ui database is not configured", nil);
    }
    return nil;
  }

  NSDictionary *counts = [[self.runtime.database
      executeQuery:@"SELECT "
                   "COUNT(*)::text AS total_users, "
                   "COUNT(*) FILTER (WHERE email_verified_at IS NOT NULL)::text AS verified_users, "
                   "COUNT(*) FILTER (WHERE roles_json LIKE '%\"admin\"%')::text AS admin_users, "
                   "COUNT(*) FILTER (WHERE EXISTS (SELECT 1 FROM auth_mfa_enrollments m "
                   "                              WHERE m.user_id = auth_users.id AND m.enabled = TRUE))::text AS mfa_users "
                   "FROM auth_users"
        parameters:@[]
             error:error] firstObject];
  if (counts == nil && error != NULL && *error != NULL) {
    return nil;
  }

  NSArray *recentRows = [self.runtime.database
      executeQuery:@"SELECT u.id::text AS id, u.subject, u.email, "
                   "COALESCE(u.display_name, '') AS display_name, "
                   "COALESCE(u.roles_json, '[]') AS roles_json, "
                   "CASE WHEN u.email_verified_at IS NULL THEN 'f' ELSE 't' END AS email_verified, "
                   "CASE WHEN EXISTS (SELECT 1 FROM auth_mfa_enrollments m WHERE m.user_id = u.id AND m.enabled = TRUE) "
                   "THEN 't' ELSE 'f' END AS mfa_enabled, "
                   "(SELECT COUNT(*)::text FROM auth_provider_identities p WHERE p.user_id = u.id) AS provider_identity_count, "
                   "COALESCE(u.created_at::text, '') AS created_at, "
                   "COALESCE(u.updated_at::text, '') AS updated_at "
                   "FROM auth_users u ORDER BY u.created_at DESC, u.id DESC LIMIT 5"
        parameters:@[]
             error:error];
  if (recentRows == nil && error != NULL && *error != NULL) {
    return nil;
  }

  NSMutableArray *recentUsers = [NSMutableArray array];
  for (NSDictionary *row in recentRows ?: @[]) {
    NSDictionary *user = AUUserDictionaryFromRow(row);
    if (user != nil) {
      [recentUsers addObject:user];
    }
  }

  return @{
    @"cards" : @[
      @{ @"label" : @"Total users", @"value" : @([AUTrimmedString(counts[@"total_users"]) integerValue]) },
      @{ @"label" : @"Verified", @"value" : @([AUTrimmedString(counts[@"verified_users"]) integerValue]) },
      @{ @"label" : @"Admins", @"value" : @([AUTrimmedString(counts[@"admin_users"]) integerValue]) },
      @{ @"label" : @"MFA enabled", @"value" : @([AUTrimmedString(counts[@"mfa_users"]) integerValue]) },
    ],
    @"highlights" : @[
      @{
        @"title" : @"Recent users",
        @"resource" : @"users",
        @"items" : recentUsers,
      },
    ],
  };
}

- (BOOL)adminUIResourceAllowsOperation:(NSString *)operation
                            identifier:(NSString *)identifier
                               context:(ALNContext *)context
                                 error:(NSError **)error {
  (void)context;
  NSString *operationName = AULowerTrimmedString(operation);
  NSString *recordID = AUTrimmedString(identifier);
  if (![operationName isEqualToString:@"action:grant_admin"] && ![operationName isEqualToString:@"action:revoke_admin"]) {
    return YES;
  }
  NSDictionary *user = [self adminUIDetailRecordForIdentifier:recordID error:error];
  if (user == nil) {
    return NO;
  }
  NSArray *roles = [user[@"roles"] isKindOfClass:[NSArray class]] ? user[@"roles"] : @[];
  if ([roles count] == 1 && [roles containsObject:@"admin"] && [operationName isEqualToString:@"action:revoke_admin"]) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorPolicyRejected,
                       @"cannot revoke the only role from this admin user",
                       @{ @"identifier" : recordID ?: @"" });
    }
    return NO;
  }
  return YES;
}

- (NSDictionary *)adminUIPerformActionNamed:(NSString *)actionName
                                 identifier:(NSString *)identifier
                                 parameters:(NSDictionary *)parameters
                                      error:(NSError **)error {
  (void)parameters;
  NSString *normalizedAction = AULowerTrimmedString(actionName);
  NSDictionary *user = [self adminUIDetailRecordForIdentifier:identifier error:error];
  if (user == nil) {
    return nil;
  }
  NSMutableArray *roles = [NSMutableArray array];
  for (id entry in ([user[@"roles"] isKindOfClass:[NSArray class]] ? user[@"roles"] : @[])) {
    NSString *role = AULowerTrimmedString(entry);
    if ([role length] > 0 && ![roles containsObject:role]) {
      [roles addObject:role];
    }
  }

  NSString *message = @"";
  if ([normalizedAction isEqualToString:@"grant_admin"]) {
    if (![roles containsObject:@"admin"]) {
      [roles addObject:@"admin"];
    }
    message = @"Admin role granted.";
  } else if ([normalizedAction isEqualToString:@"revoke_admin"]) {
    [roles removeObject:@"admin"];
    if (![roles containsObject:@"user"]) {
      [roles addObject:@"user"];
    }
    message = @"Admin role revoked.";
  } else {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorNotFound,
                       [NSString stringWithFormat:@"unknown action %@", normalizedAction ?: @""],
                       @{ @"action" : normalizedAction ?: @"" });
    }
    return nil;
  }

  NSDictionary *row = [[self.runtime.database
      executeQuery:@"UPDATE auth_users SET roles_json = $2, updated_at = NOW() "
                   "WHERE subject = $1 "
                   "RETURNING id::text AS id, subject, email, "
                   "COALESCE(display_name, '') AS display_name, "
                   "COALESCE(roles_json, '[]') AS roles_json, "
                   "CASE WHEN email_verified_at IS NULL THEN 'f' ELSE 't' END AS email_verified, "
                   "CASE WHEN EXISTS (SELECT 1 FROM auth_mfa_enrollments m WHERE m.user_id = auth_users.id AND m.enabled = TRUE) "
                   "THEN 't' ELSE 'f' END AS mfa_enabled, "
                   "(SELECT COUNT(*)::text FROM auth_provider_identities p WHERE p.user_id = auth_users.id) AS provider_identity_count, "
                   "COALESCE(created_at::text, '') AS created_at, "
                   "COALESCE(updated_at::text, '') AS updated_at"
        parameters:@[ AUTrimmedString(identifier), AUJSONString(roles) ]
             error:error] firstObject];
  NSDictionary *updated = AUUserDictionaryFromRow(row);
  if (updated == nil && error != NULL && *error == NULL) {
    *error = AUError(ALNAdminUIModuleErrorNotFound, @"user not found", nil);
  }
  return (updated != nil) ? @{ @"record" : updated, @"message" : message ?: @"" } : nil;
}

- (NSDictionary *)adminUIPerformBulkActionNamed:(NSString *)actionName
                                     identifiers:(NSArray<NSString *> *)identifiers
                                      parameters:(NSDictionary *)parameters
                                           error:(NSError **)error {
  NSMutableArray *records = [NSMutableArray array];
  for (NSString *identifier in identifiers ?: @[]) {
    NSDictionary *result = [self adminUIPerformActionNamed:actionName identifier:identifier parameters:parameters error:error];
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
    @"message" : [NSString stringWithFormat:@"Updated %lu users.", (unsigned long)[records count]],
  };
}

- (NSArray<NSDictionary *> *)adminUIAutocompleteSuggestionsForFieldNamed:(NSString *)fieldName
                                                                   query:(NSString *)query
                                                                   limit:(NSUInteger)limit
                                                                   error:(NSError **)error {
  (void)error;
  if (![AULowerTrimmedString(fieldName) isEqualToString:@"roles"]) {
    return @[];
  }
  NSString *needle = AULowerTrimmedString(query);
  NSMutableArray *matches = [NSMutableArray array];
  for (NSDictionary *choice in @[ @{ @"value" : @"user", @"label" : @"user" }, @{ @"value" : @"admin", @"label" : @"admin" } ]) {
    if ([needle length] > 0 &&
        [AULowerTrimmedString(choice[@"value"]) rangeOfString:needle].location == NSNotFound &&
        [AULowerTrimmedString(choice[@"label"]) rangeOfString:needle].location == NSNotFound) {
      continue;
    }
    [matches addObject:choice];
    if ([matches count] >= MAX((NSUInteger)1U, limit)) {
      break;
    }
  }
  return matches;
}

@end

@implementation ALNAdminUIModuleRuntime

+ (instancetype)sharedRuntime {
  static ALNAdminUIModuleRuntime *runtime = nil;
  @synchronized(self) {
    if (runtime == nil) {
      runtime = [[ALNAdminUIModuleRuntime alloc] init];
    }
  }
  return runtime;
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _moduleConfig = @{};
    _applicationConfig = @{};
    _mountPrefix = @"/admin";
    _apiPrefix = @"/api";
    _dashboardTitle = @"Arlen Admin";
    _mountedApplication = nil;
    _resourceDescriptors = @[];
    _resourceDescriptorMap = @{};
  }
  return self;
}

- (NSArray<NSString *> *)configuredResourceProviderClassNames {
  NSMutableArray *classNames = [NSMutableArray array];
  NSDictionary *resourceProviders =
      [self.moduleConfig[@"resourceProviders"] isKindOfClass:[NSDictionary class]] ? self.moduleConfig[@"resourceProviders"] : @{};
  NSArray *nestedClasses = [resourceProviders[@"classes"] isKindOfClass:[NSArray class]] ? resourceProviders[@"classes"] : @[];
  NSArray *flatClasses = [self.moduleConfig[@"resourceProviderClasses"] isKindOfClass:[NSArray class]]
                             ? self.moduleConfig[@"resourceProviderClasses"]
                             : @[];
  for (id entry in [nestedClasses arrayByAddingObjectsFromArray:flatClasses]) {
    NSString *className = AUTrimmedString(entry);
    if ([className length] == 0 || [classNames containsObject:className]) {
      continue;
    }
    [classNames addObject:className];
  }
  NSArray *topLevelKeys = [[self.applicationConfig allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in topLevelKeys) {
    NSDictionary *moduleEntry = [self.applicationConfig[key] isKindOfClass:[NSDictionary class]] ? self.applicationConfig[key] : nil;
    NSDictionary *moduleAdminUI = [moduleEntry[@"adminUI"] isKindOfClass:[NSDictionary class]] ? moduleEntry[@"adminUI"] : @{};
    NSDictionary *moduleResourceProviders =
        [moduleAdminUI[@"resourceProviders"] isKindOfClass:[NSDictionary class]] ? moduleAdminUI[@"resourceProviders"] : @{};
    NSMutableArray *moduleClasses = [NSMutableArray array];
    NSString *singleClass = AUTrimmedString(moduleAdminUI[@"resourceProviderClass"]);
    if ([singleClass length] > 0) {
      [moduleClasses addObject:singleClass];
    }
    NSArray *flatModuleClasses = [moduleAdminUI[@"resourceProviderClasses"] isKindOfClass:[NSArray class]]
                                     ? moduleAdminUI[@"resourceProviderClasses"]
                                     : @[];
    NSArray *nestedModuleClasses = [moduleResourceProviders[@"classes"] isKindOfClass:[NSArray class]]
                                       ? moduleResourceProviders[@"classes"]
                                       : @[];
    [moduleClasses addObjectsFromArray:flatModuleClasses];
    [moduleClasses addObjectsFromArray:nestedModuleClasses];
    for (id entry in moduleClasses) {
      NSString *className = AUTrimmedString(entry);
      if ([className length] == 0 || [classNames containsObject:className]) {
        continue;
      }
      [classNames addObject:className];
    }
  }
  return [NSArray arrayWithArray:classNames];
}

- (NSDictionary *)normalizedMetadataForResource:(id<ALNAdminUIResource>)resource
                                          error:(NSError **)error {
  NSString *identifier = AULowerTrimmedString([resource adminUIResourceIdentifier]);
  if ([identifier length] == 0) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorInvalidConfiguration,
                       @"admin resource identifier is required",
                       @{ @"resource" : NSStringFromClass([(NSObject *)resource class]) ?: @"" });
    }
    return nil;
  }
  NSDictionary *rawMetadata = [[resource adminUIResourceMetadata] isKindOfClass:[NSDictionary class]]
                                  ? [resource adminUIResourceMetadata]
                                  : @{};
  NSString *label = AUTrimmedString(rawMetadata[@"label"]);
  if ([label length] == 0) {
    label = AUTitleCaseIdentifier(identifier);
  }
  NSString *singularLabel = AUTrimmedString(rawMetadata[@"singularLabel"]);
  if ([singularLabel length] == 0) {
    singularLabel = label;
  }
  NSString *summary = AUTrimmedString(rawMetadata[@"summary"]);
  NSString *identifierField = AULowerTrimmedString(rawMetadata[@"identifierField"]);
  if ([identifierField length] == 0) {
    identifierField = @"id";
  }
  NSString *primaryField = AULowerTrimmedString(rawMetadata[@"primaryField"]);
  if ([primaryField length] == 0) {
    primaryField = identifierField;
  }
  NSString *legacyPath = AUTrimmedString(rawMetadata[@"legacyPath"]);
  NSString *htmlIndexGenericPath = [self mountedPathForChildPath:[NSString stringWithFormat:@"resources/%@", identifier]];
  NSString *htmlIndexPath = htmlIndexGenericPath;
  NSString *legacyHTMLIndexPath = @"";
  if ([legacyPath length] > 0) {
    legacyHTMLIndexPath = [self mountedPathForChildPath:legacyPath];
    htmlIndexPath = legacyHTMLIndexPath;
  }
  NSString *apiMetadataPath = [self mountedPathForChildPath:[NSString stringWithFormat:@"%@/resources/%@", self.apiPrefix, identifier]];
  NSString *apiItemsPath = [self mountedPathForChildPath:[NSString stringWithFormat:@"%@/resources/%@/items", self.apiPrefix, identifier]];
  NSString *apiExportPath = [self mountedPathForChildPath:[NSString stringWithFormat:@"%@/resources/%@/export", self.apiPrefix, identifier]];
  NSString *apiAutocompletePath =
      [self mountedPathForChildPath:[NSString stringWithFormat:@"%@/resources/%@/autocomplete", self.apiPrefix, identifier]];
  NSString *htmlExportPath = [NSString stringWithFormat:@"%@/export", htmlIndexPath];
  NSMutableDictionary *paths = [NSMutableDictionary dictionaryWithDictionary:@{
    @"html_index" : htmlIndexPath,
    @"html_index_generic" : htmlIndexGenericPath,
    @"html_detail_template" : [NSString stringWithFormat:@"%@/:identifier", htmlIndexPath],
    @"html_bulk_action_template" : [NSString stringWithFormat:@"%@/bulk-actions/:action", htmlIndexPath],
    @"html_export_json" : [NSString stringWithFormat:@"%@/json", htmlExportPath],
    @"html_export_csv" : [NSString stringWithFormat:@"%@/csv", htmlExportPath],
    @"api_metadata" : apiMetadataPath,
    @"api_items" : apiItemsPath,
    @"api_item_template" : [NSString stringWithFormat:@"%@/:identifier", apiItemsPath],
    @"api_action_template" : [NSString stringWithFormat:@"%@/:identifier/actions/:action", apiItemsPath],
    @"api_bulk_action_template" : [NSString stringWithFormat:@"%@/bulk-actions/:action", apiMetadataPath],
    @"api_export_template" : [NSString stringWithFormat:@"%@/:format", apiExportPath],
    @"api_export_json" : [NSString stringWithFormat:@"%@/json", apiExportPath],
    @"api_export_csv" : [NSString stringWithFormat:@"%@/csv", apiExportPath],
    @"api_autocomplete_template" : [NSString stringWithFormat:@"%@/:field", apiAutocompletePath],
  }];
  if ([legacyPath length] > 0) {
    NSString *legacyAPIItemsPath = [self mountedPathForChildPath:[NSString stringWithFormat:@"%@/%@", self.apiPrefix, legacyPath]];
    paths[@"legacy_html_index"] = legacyHTMLIndexPath;
    paths[@"legacy_html_detail_template"] = [NSString stringWithFormat:@"%@/:identifier", legacyHTMLIndexPath];
    paths[@"legacy_html_bulk_action_template"] = [NSString stringWithFormat:@"%@/bulk-actions/:action", legacyHTMLIndexPath];
    paths[@"legacy_html_export_json"] = [NSString stringWithFormat:@"%@/export/json", legacyHTMLIndexPath];
    paths[@"legacy_html_export_csv"] = [NSString stringWithFormat:@"%@/export/csv", legacyHTMLIndexPath];
    paths[@"legacy_api_items"] = legacyAPIItemsPath;
    paths[@"legacy_api_item_template"] = [NSString stringWithFormat:@"%@/:identifier", legacyAPIItemsPath];
    paths[@"legacy_api_action_template"] = [NSString stringWithFormat:@"%@/:identifier/actions/:action", legacyAPIItemsPath];
    paths[@"legacy_api_bulk_action_template"] = [NSString stringWithFormat:@"%@/bulk-actions/:action", legacyAPIItemsPath];
    paths[@"legacy_api_export_template"] = [NSString stringWithFormat:@"%@/export/:format", legacyAPIItemsPath];
    paths[@"legacy_api_export_json"] = [NSString stringWithFormat:@"%@/export/json", legacyAPIItemsPath];
    paths[@"legacy_api_export_csv"] = [NSString stringWithFormat:@"%@/export/csv", legacyAPIItemsPath];
    paths[@"legacy_api_autocomplete_template"] = [NSString stringWithFormat:@"%@/autocomplete/:field", legacyAPIItemsPath];
  }
  NSArray *normalizedActions = AUNormalizedActionArray(rawMetadata[@"actions"]);
  NSMutableArray *rowActions = [NSMutableArray array];
  NSMutableArray *bulkActions = [NSMutableArray arrayWithArray:AUNormalizedBulkActionArray(rawMetadata[@"bulkActions"])];
  for (NSDictionary *action in normalizedActions) {
    if ([AULowerTrimmedString(action[@"scope"]) isEqualToString:@"bulk"]) {
      [bulkActions addObject:@{
        @"name" : action[@"name"] ?: @"",
        @"label" : action[@"label"] ?: @"",
        @"method" : action[@"method"] ?: @"POST",
        @"requires_aal2" : action[@"requires_aal2"] ?: @YES,
      }];
    } else {
      [rowActions addObject:action];
    }
  }
  NSMutableArray *fields = ([AUNormalizedFieldArray(rawMetadata[@"fields"]) mutableCopy] ?: [NSMutableArray array]);
  for (NSUInteger index = 0; index < [fields count]; index++) {
    NSMutableDictionary *field = ([fields[index] mutableCopy] ?: [NSMutableDictionary dictionary]);
    NSMutableDictionary *autocomplete =
        [field[@"autocomplete"] isKindOfClass:[NSDictionary class]] ? [field[@"autocomplete"] mutableCopy] : [NSMutableDictionary dictionary];
    if ([autocomplete[@"enabled"] boolValue]) {
      autocomplete[@"path"] = [apiAutocompletePath stringByAppendingPathComponent:(field[@"name"] ?: @"field")];
    }
    field[@"autocomplete"] = autocomplete;
    fields[index] = field;
  }
  NSUInteger pageSize = [rawMetadata[@"pageSize"] respondsToSelector:@selector(unsignedIntegerValue)] ? [rawMetadata[@"pageSize"] unsignedIntegerValue] : 50U;
  if (pageSize == 0U) {
    pageSize = 50U;
  }
  NSUInteger maxPageSize = [rawMetadata[@"maxPageSize"] respondsToSelector:@selector(unsignedIntegerValue)]
                               ? [rawMetadata[@"maxPageSize"] unsignedIntegerValue]
                               : MAX(pageSize, 200U);
  if (maxPageSize < pageSize) {
    maxPageSize = pageSize;
  }
  NSMutableArray *numericPageSizes = [AUNormalizedPositiveIntegerArray(rawMetadata[@"pageSizes"]) mutableCopy];
  if (numericPageSizes == nil) {
    numericPageSizes = [NSMutableArray array];
  }
  if ([numericPageSizes count] == 0) {
    numericPageSizes = [@[ @(pageSize), @(MIN(maxPageSize, MAX((NSUInteger)100U, pageSize * 2U))) ] mutableCopy];
  }
  NSString *defaultSort = @"";
  for (NSDictionary *sort in AUNormalizedSortArray(rawMetadata[@"sorts"])) {
    if ([sort[@"default"] boolValue]) {
      defaultSort = [sort[@"name"] ?: @"" copy];
      if ([AULowerTrimmedString(sort[@"direction"]) isEqualToString:@"desc"]) {
        defaultSort = [@"-" stringByAppendingString:defaultSort];
      }
      break;
    }
  }
  return @{
    @"identifier" : identifier,
    @"label" : label,
    @"singularLabel" : singularLabel,
    @"summary" : summary ?: @"",
    @"identifierField" : identifierField,
    @"primaryField" : primaryField,
    @"fields" : fields,
    @"filters" : AUNormalizedFilterArray(rawMetadata[@"filters"]),
    @"sorts" : AUNormalizedSortArray(rawMetadata[@"sorts"]),
    @"actions" : rowActions,
    @"bulkActions" : bulkActions,
    @"exports" : AUNormalizedExportArray(rawMetadata[@"exports"]),
    @"defaultSort" : defaultSort ?: @"",
    @"pageSize" : @(pageSize),
    @"pagination" : @{
      @"defaultLimit" : @(pageSize),
      @"maxLimit" : @(maxPageSize),
      @"pageSizes" : numericPageSizes,
    },
    @"legacyPath" : legacyPath ?: @"",
    @"paths" : paths,
  };
}

- (BOOL)loadResourceRegistryWithError:(NSError **)error {
  NSMutableArray<id<ALNAdminUIResource>> *resources = [NSMutableArray array];
  if (self.database != nil) {
    [resources addObject:[[ALNAdminUIUsersResource alloc] initWithRuntime:self]];
  }

  for (NSString *className in [self configuredResourceProviderClassNames]) {
    Class klass = NSClassFromString(className);
    if (klass == Nil) {
      if (error != NULL) {
        *error = AUError(ALNAdminUIModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"resource provider class %@ could not be resolved", className],
                         @{ @"class" : className ?: @"" });
      }
      return NO;
    }
    if (![klass conformsToProtocol:@protocol(ALNAdminUIResourceProvider)]) {
      if (error != NULL) {
        *error = AUError(ALNAdminUIModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"%@ must conform to ALNAdminUIResourceProvider", className],
                         @{ @"class" : className ?: @"" });
      }
      return NO;
    }
    id<ALNAdminUIResourceProvider> provider = [[klass alloc] init];
    NSArray *provided = [provider adminUIResourcesForRuntime:self error:error];
    if (provided == nil && error != NULL && *error != NULL) {
      return NO;
    }
    for (id entry in provided ?: @[]) {
      if ([entry conformsToProtocol:@protocol(ALNAdminUIResource)]) {
        [resources addObject:entry];
      }
    }
  }

  NSMutableArray *descriptors = [NSMutableArray array];
  NSMutableDictionary *map = [NSMutableDictionary dictionary];
  NSMutableDictionary *legacyMap = [NSMutableDictionary dictionary];
  for (id<ALNAdminUIResource> resource in resources) {
    NSDictionary *metadata = [self normalizedMetadataForResource:resource error:error];
    if (metadata == nil) {
      return NO;
    }
    NSString *identifier = metadata[@"identifier"];
    if ([map objectForKey:identifier] != nil) {
      if (error != NULL) {
        *error = AUError(ALNAdminUIModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"duplicate admin resource %@", identifier ?: @""],
                         @{ @"identifier" : identifier ?: @"" });
      }
      return NO;
    }
    ALNAdminUIResourceDescriptor *descriptor = [[ALNAdminUIResourceDescriptor alloc] init];
    descriptor.resource = resource;
    descriptor.metadata = metadata;
    [descriptors addObject:descriptor];
    map[identifier] = descriptor;
    NSString *legacyPath = AULowerTrimmedString(metadata[@"legacyPath"]);
    if ([legacyPath length] > 0) {
      if (legacyMap[legacyPath] != nil || ([map objectForKey:legacyPath] != nil && ![legacyPath isEqualToString:identifier])) {
        if (error != NULL) {
          *error = AUError(ALNAdminUIModuleErrorInvalidConfiguration,
                           [NSString stringWithFormat:@"duplicate admin legacy path %@", legacyPath ?: @""],
                           @{ @"legacyPath" : legacyPath ?: @"", @"identifier" : identifier ?: @"" });
        }
        return NO;
      }
      legacyMap[legacyPath] = descriptor;
    }
  }
  self.resourceDescriptors = [NSArray arrayWithArray:descriptors];
  self.resourceDescriptorMap = [NSDictionary dictionaryWithDictionary:map];
  self.legacyResourceDescriptorMap = [NSDictionary dictionaryWithDictionary:legacyMap];
  return YES;
}

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError **)error {
  self.applicationConfig = [application.config isKindOfClass:[NSDictionary class]] ? application.config : @{};
  NSDictionary *moduleConfig = [application.config[@"adminUI"] isKindOfClass:[NSDictionary class]]
                                   ? application.config[@"adminUI"]
                                   : @{};
  self.moduleConfig = moduleConfig;

  NSDictionary *paths = [moduleConfig[@"paths"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"paths"] : @{};
  NSString *mountPrefix = AUTrimmedString(paths[@"prefix"]);
  NSString *apiPrefix = AUTrimmedString(paths[@"apiPrefix"]);
  self.mountPrefix = AUPathJoin(([mountPrefix length] > 0) ? mountPrefix : @"/admin", @"");
  self.apiPrefix = AUPathJoin(([apiPrefix length] > 0) ? apiPrefix : @"/api", @"");
  NSString *dashboardTitle = AUTrimmedString(moduleConfig[@"title"]);
  self.dashboardTitle = ([dashboardTitle length] > 0) ? dashboardTitle : @"Arlen Admin";

  NSDictionary *database = [application.config[@"database"] isKindOfClass:[NSDictionary class]]
                               ? application.config[@"database"]
                               : @{};
  NSString *connectionString = AUTrimmedString(database[@"connectionString"]);
  self.database = nil;
  if ([connectionString length] > 0) {
    NSError *dbError = nil;
    self.database = [[ALNPg alloc] initWithConnectionString:connectionString maxConnections:4 error:&dbError];
    if (self.database == nil) {
      if (error != NULL) {
        *error = dbError ?: AUError(ALNAdminUIModuleErrorDatabaseUnavailable,
                                    @"failed to initialize admin-ui database adapter",
                                    nil);
      }
      return NO;
    }
  }

  NSMutableDictionary *childConfig = [NSMutableDictionary dictionary];
  childConfig[@"environment"] = application.environment ?: @"development";
  childConfig[@"logFormat"] = [application.config[@"logFormat"] isKindOfClass:[NSString class]]
                                  ? application.config[@"logFormat"]
                                  : @"text";
  if ([application.config[@"runtimeInvocationMode"] isKindOfClass:[NSString class]]) {
    childConfig[@"runtimeInvocationMode"] = application.config[@"runtimeInvocationMode"];
  }
  for (NSString *key in @[ @"session", @"csrf", @"database", @"security", @"securityHeaders", @"observability", @"services" ]) {
    if ([application.config[key] isKindOfClass:[NSDictionary class]]) {
      childConfig[key] = application.config[key];
    }
  }
  if (application.config[@"performanceLogging"] != nil) {
    childConfig[@"performanceLogging"] = application.config[@"performanceLogging"];
  }
  self.mountedApplication = [[ALNApplication alloc] initWithConfig:childConfig];
  if (self.mountedApplication == nil) {
    return NO;
  }
  NSMutableSet<NSString *> *childMiddlewareClasses = [NSMutableSet set];
  for (id middleware in [self.mountedApplication middlewares] ?: @[]) {
    NSString *className = NSStringFromClass([(NSObject *)middleware class]);
    if ([className length] > 0) {
      [childMiddlewareClasses addObject:className];
    }
  }
  for (id middleware in [application middlewares] ?: @[]) {
    if (middleware == nil) {
      continue;
    }
    NSString *className = NSStringFromClass([(NSObject *)middleware class]);
    if ([className length] > 0 && [childMiddlewareClasses containsObject:className]) {
      continue;
    }
    [self.mountedApplication addMiddleware:middleware];
    if ([className length] > 0) {
      [childMiddlewareClasses addObject:className];
    }
  }
  return [self loadResourceRegistryWithError:error];
}

- (NSDictionary *)resolvedConfigSummary {
  return @{
    @"mountPrefix" : self.mountPrefix ?: @"/admin",
    @"apiPrefix" : self.apiPrefix ?: @"/api",
    @"dashboardTitle" : self.dashboardTitle ?: @"Arlen Admin",
    @"resources" : [self registeredResources],
  };
}

- (NSString *)mountedPathForChildPath:(NSString *)childPath {
  NSString *cleanChildPath = AUTrimmedString(childPath);
  if ([cleanChildPath length] == 0) {
    cleanChildPath = @"/";
  }
  return AUPathJoin(self.mountPrefix ?: @"/admin", cleanChildPath);
}

- (NSArray<NSDictionary *> *)registeredResources {
  NSMutableArray *resources = [NSMutableArray array];
  for (ALNAdminUIResourceDescriptor *descriptor in self.resourceDescriptors ?: @[]) {
    if ([descriptor.metadata isKindOfClass:[NSDictionary class]]) {
      [resources addObject:descriptor.metadata];
    }
  }
  return [NSArray arrayWithArray:resources];
}

- (ALNAdminUIResourceDescriptor *)descriptorForIdentifier:(NSString *)identifier {
  NSString *normalized = AULowerTrimmedString(identifier);
  ALNAdminUIResourceDescriptor *descriptor = self.resourceDescriptorMap[normalized];
  if (descriptor != nil) {
    return descriptor;
  }
  return self.legacyResourceDescriptorMap[normalized];
}

- (NSDictionary *)resourceMetadataForIdentifier:(NSString *)identifier {
  return [self descriptorForIdentifier:identifier].metadata;
}

- (NSDictionary *)resourceDescriptorForIdentifier:(NSString *)identifier {
  return [self resourceMetadataForIdentifier:identifier];
}

- (BOOL)resourceIdentifier:(NSString *)identifier
            allowsOperation:(NSString *)operation
                  recordID:(NSString *)recordID
                   context:(ALNContext *)context
                     error:(NSError **)error {
  ALNAdminUIResourceDescriptor *descriptor = [self descriptorForIdentifier:identifier];
  if (descriptor == nil) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorNotFound,
                       [NSString stringWithFormat:@"unknown admin resource %@", identifier ?: @""],
                       @{ @"resource" : AUTrimmedString(identifier) });
    }
    return NO;
  }
  if ([descriptor.resource respondsToSelector:@selector(adminUIResourceAllowsOperation:identifier:context:error:)]) {
    BOOL allowed = [descriptor.resource adminUIResourceAllowsOperation:(operation ?: @"")
                                                            identifier:(recordID ?: @"")
                                                               context:context
                                                                 error:error];
    if (!allowed && error != NULL && *error == NULL) {
      *error = AUError(ALNAdminUIModuleErrorPolicyRejected,
                       @"admin policy denied this operation",
                       @{ @"resource" : descriptor.metadata[@"identifier"] ?: @"" });
    }
    return allowed;
  }
  return YES;
}

- (NSArray<NSDictionary *> *)listRecordsForResourceIdentifier:(NSString *)identifier
                                                        query:(NSString *)query
                                                        limit:(NSUInteger)limit
                                                       offset:(NSUInteger)offset
                                                        error:(NSError **)error {
  return [self listRecordsForResourceIdentifier:identifier
                                     parameters:@{ @"q" : query ?: @"" }
                                          limit:limit
                                         offset:offset
                                          error:error];
}

- (NSArray<NSDictionary *> *)listRecordsForResourceIdentifier:(NSString *)identifier
                                                    parameters:(NSDictionary *)parameters
                                                         limit:(NSUInteger)limit
                                                        offset:(NSUInteger)offset
                                                         error:(NSError **)error {
  ALNAdminUIResourceDescriptor *descriptor = [self descriptorForIdentifier:identifier];
  if (descriptor == nil) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorNotFound,
                       [NSString stringWithFormat:@"unknown admin resource %@", identifier ?: @""],
                       @{ @"resource" : AUTrimmedString(identifier) });
    }
    return nil;
  }
  if ([descriptor.resource respondsToSelector:@selector(adminUIListRecordsWithParameters:limit:offset:error:)]) {
    return [descriptor.resource adminUIListRecordsWithParameters:(parameters ?: @{})
                                                           limit:limit
                                                          offset:offset
                                                           error:error];
  }
  NSString *query = AUTrimmedString(parameters[@"q"]);
  return [descriptor.resource adminUIListRecordsMatching:query limit:limit offset:offset error:error];
}

- (NSDictionary *)recordDetailForResourceIdentifier:(NSString *)identifier
                                           recordID:(NSString *)recordID
                                              error:(NSError **)error {
  ALNAdminUIResourceDescriptor *descriptor = [self descriptorForIdentifier:identifier];
  if (descriptor == nil) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorNotFound,
                       [NSString stringWithFormat:@"unknown admin resource %@", identifier ?: @""],
                       @{ @"resource" : AUTrimmedString(identifier) });
    }
    return nil;
  }
  return [descriptor.resource adminUIDetailRecordForIdentifier:recordID error:error];
}

- (NSDictionary *)updateRecordForResourceIdentifier:(NSString *)identifier
                                           recordID:(NSString *)recordID
                                         parameters:(NSDictionary *)parameters
                                              error:(NSError **)error {
  ALNAdminUIResourceDescriptor *descriptor = [self descriptorForIdentifier:identifier];
  if (descriptor == nil) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorNotFound,
                       [NSString stringWithFormat:@"unknown admin resource %@", identifier ?: @""],
                       @{ @"resource" : AUTrimmedString(identifier) });
    }
    return nil;
  }
  NSDictionary *record = [descriptor.resource adminUIUpdateRecordWithIdentifier:recordID parameters:(parameters ?: @{}) error:error];
  if (record != nil) {
    AUNotifySearchIncrementalSync(identifier, record, @"upsert");
  }
  return record;
}

- (NSDictionary *)performActionNamed:(NSString *)actionName
               forResourceIdentifier:(NSString *)identifier
                            recordID:(NSString *)recordID
                          parameters:(NSDictionary *)parameters
                               error:(NSError **)error {
  ALNAdminUIResourceDescriptor *descriptor = [self descriptorForIdentifier:identifier];
  if (descriptor == nil) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorNotFound,
                       [NSString stringWithFormat:@"unknown admin resource %@", identifier ?: @""],
                       @{ @"resource" : AUTrimmedString(identifier) });
    }
    return nil;
  }
  if (![descriptor.resource respondsToSelector:@selector(adminUIPerformActionNamed:identifier:parameters:error:)]) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorNotFound,
                       [NSString stringWithFormat:@"resource %@ does not expose actions", identifier ?: @""],
                       @{ @"resource" : AUTrimmedString(identifier) });
    }
    return nil;
  }
  NSDictionary *result = [descriptor.resource adminUIPerformActionNamed:actionName identifier:recordID parameters:(parameters ?: @{}) error:error];
  if (result != nil) {
    NSDictionary *record = [result[@"record"] isKindOfClass:[NSDictionary class]] ? result[@"record"] : @{};
    NSString *operation = ([AULowerTrimmedString(actionName) containsString:@"delete"] || [record count] == 0) ? @"delete" : @"upsert";
    NSMutableDictionary *searchRecord = [record mutableCopy] ?: [NSMutableDictionary dictionary];
    if ([searchRecord count] == 0) {
      NSString *identifierField = descriptor.metadata[@"identifierField"] ?: @"id";
      searchRecord[identifierField] = AUTrimmedString(recordID);
    }
    AUNotifySearchIncrementalSync(identifier, searchRecord, operation);
  }
  return result;
}

- (NSDictionary *)performBulkActionNamed:(NSString *)actionName
                   forResourceIdentifier:(NSString *)identifier
                               recordIDs:(NSArray<NSString *> *)recordIDs
                              parameters:(NSDictionary *)parameters
                                   error:(NSError **)error {
  ALNAdminUIResourceDescriptor *descriptor = [self descriptorForIdentifier:identifier];
  if (descriptor == nil) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorNotFound,
                       [NSString stringWithFormat:@"unknown admin resource %@", identifier ?: @""],
                       @{ @"resource" : AUTrimmedString(identifier) });
    }
    return nil;
  }
  NSArray<NSString *> *identifiers = AUNormalizedIdentifierArray(recordIDs);
  if ([identifiers count] == 0) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorValidationFailed, @"at least one record identifier is required", nil);
    }
    return nil;
  }
  if ([descriptor.resource respondsToSelector:@selector(adminUIPerformBulkActionNamed:identifiers:parameters:error:)]) {
    NSDictionary *result = [descriptor.resource adminUIPerformBulkActionNamed:actionName
                                                                   identifiers:identifiers
                                                                    parameters:(parameters ?: @{})
                                                                         error:error];
    if (result != nil) {
      NSString *operation = [AULowerTrimmedString(actionName) containsString:@"delete"] ? @"delete" : @"upsert";
      NSArray *records = [result[@"records"] isKindOfClass:[NSArray class]] ? result[@"records"] : @[];
      if ([records count] > 0) {
        for (NSDictionary *record in records) {
          AUNotifySearchIncrementalSync(identifier, record, operation);
        }
      } else {
        NSString *identifierField = descriptor.metadata[@"identifierField"] ?: @"id";
        for (NSString *recordID in identifiers) {
          AUNotifySearchIncrementalSync(identifier, @{ identifierField : recordID ?: @"" }, operation);
        }
      }
    }
    return result;
  }
  NSMutableArray *records = [NSMutableArray array];
  NSMutableArray *messages = [NSMutableArray array];
  for (NSString *recordID in identifiers) {
    NSDictionary *result = [self performActionNamed:actionName
                              forResourceIdentifier:identifier
                                           recordID:recordID
                                         parameters:parameters
                                              error:error];
    if (result == nil) {
      return nil;
    }
    if ([result[@"record"] isKindOfClass:[NSDictionary class]]) {
      [records addObject:result[@"record"]];
    }
    if ([AUTrimmedString(result[@"message"]) length] > 0) {
      [messages addObject:AUTrimmedString(result[@"message"])];
    }
  }
  return @{
    @"count" : @([identifiers count]),
    @"records" : records,
    @"message" : ([messages count] > 0)
                     ? [NSString stringWithFormat:@"%@ (%lu records)", messages[0], (unsigned long)[identifiers count]]
                     : [NSString stringWithFormat:@"Bulk action completed for %lu records.", (unsigned long)[identifiers count]],
  };
}

- (NSDictionary *)exportPayloadForResourceIdentifier:(NSString *)identifier
                                              format:(NSString *)format
                                          parameters:(NSDictionary *)parameters
                                               error:(NSError **)error {
  NSDictionary *resource = [self resourceMetadataForIdentifier:identifier];
  if (resource == nil) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorNotFound,
                       @"resource not found",
                       @{ @"resource" : AUTrimmedString(identifier) });
    }
    return nil;
  }
  NSString *normalizedFormat = AULowerTrimmedString(format);
  if (![normalizedFormat isEqualToString:@"json"] && ![normalizedFormat isEqualToString:@"csv"]) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorValidationFailed,
                       @"unsupported export format",
                       @{ @"format" : normalizedFormat ?: @"" });
    }
    return nil;
  }
  NSUInteger maxLimit = [resource[@"pagination"][@"maxLimit"] respondsToSelector:@selector(unsignedIntegerValue)]
                            ? [resource[@"pagination"][@"maxLimit"] unsignedIntegerValue]
                            : 200U;
  NSUInteger exportLimit = [parameters[@"exportLimit"] respondsToSelector:@selector(unsignedIntegerValue)]
                               ? [parameters[@"exportLimit"] unsignedIntegerValue]
                               : MIN((NSUInteger)1000U, MAX((NSUInteger)1U, maxLimit));
  exportLimit = MIN(exportLimit, MAX((NSUInteger)1U, maxLimit));
  NSArray *records = [self listRecordsForResourceIdentifier:identifier parameters:(parameters ?: @{}) limit:exportLimit offset:0 error:error];
  if (records == nil) {
    return nil;
  }
  NSArray *fields = [resource[@"fields"] isKindOfClass:[NSArray class]] ? resource[@"fields"] : @[];
  NSMutableArray *exportFields = [NSMutableArray array];
  for (NSDictionary *field in fields) {
    if ([field[@"list"] boolValue]) {
      [exportFields addObject:field];
    }
  }
  if ([exportFields count] == 0) {
    exportFields = [fields mutableCopy] ?: [NSMutableArray array];
  }
  NSData *bodyData = [NSData data];
  NSString *contentType = @"application/octet-stream";
  if ([normalizedFormat isEqualToString:@"json"]) {
    bodyData = [NSJSONSerialization dataWithJSONObject:records ?: @[] options:NSJSONWritingPrettyPrinted error:NULL] ?: [NSData data];
    contentType = @"application/json";
  } else {
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    NSMutableArray<NSString *> *headers = [NSMutableArray array];
    for (NSDictionary *field in exportFields) {
      [headers addObject:[AUTrimmedString(field[@"label"]) length] > 0 ? AUTrimmedString(field[@"label"]) : AUTrimmedString(field[@"name"])];
    }
    [rows addObject:[headers componentsJoinedByString:@","]];
    for (NSDictionary *record in records) {
      NSMutableArray<NSString *> *values = [NSMutableArray array];
      for (NSDictionary *field in exportFields) {
        NSString *value = [AUStringifyValue(record[field[@"name"]]) copy];
        NSString *escaped = [[value stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""] copy];
        [values addObject:[NSString stringWithFormat:@"\"%@\"", escaped ?: @""]];
      }
      [rows addObject:[values componentsJoinedByString:@","]];
    }
    bodyData = [[rows componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    contentType = @"text/csv; charset=utf-8";
  }
  return @{
    @"format" : normalizedFormat,
    @"contentType" : contentType,
    @"filename" : [NSString stringWithFormat:@"%@.%@", identifier ?: @"resource", normalizedFormat],
    @"bodyData" : bodyData ?: [NSData data],
    @"count" : @([records count]),
  };
}

- (NSArray<NSDictionary *> *)autocompleteSuggestionsForResourceIdentifier:(NSString *)identifier
                                                                 fieldName:(NSString *)fieldName
                                                                     query:(NSString *)query
                                                                     limit:(NSUInteger)limit
                                                                     error:(NSError **)error {
  ALNAdminUIResourceDescriptor *descriptor = [self descriptorForIdentifier:identifier];
  if (descriptor == nil) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorNotFound,
                       @"resource not found",
                       @{ @"resource" : AUTrimmedString(identifier) });
    }
    return nil;
  }
  if ([descriptor.resource respondsToSelector:@selector(adminUIAutocompleteSuggestionsForFieldNamed:query:limit:error:)]) {
    return [descriptor.resource adminUIAutocompleteSuggestionsForFieldNamed:fieldName query:query limit:limit error:error];
  }
  NSDictionary *resource = descriptor.metadata ?: @{};
  NSDictionary *field = nil;
  for (NSDictionary *entry in [resource[@"fields"] isKindOfClass:[NSArray class]] ? resource[@"fields"] : @[]) {
    if ([AULowerTrimmedString(entry[@"name"]) isEqualToString:AULowerTrimmedString(fieldName)]) {
      field = entry;
      break;
    }
  }
  NSArray *choices = [field[@"choices"] isKindOfClass:[NSArray class]] ? field[@"choices"] : @[];
  NSString *needle = AULowerTrimmedString(query);
  NSMutableArray *matches = [NSMutableArray array];
  for (NSDictionary *choice in choices) {
    NSString *label = AULowerTrimmedString(choice[@"label"]);
    NSString *value = AULowerTrimmedString(choice[@"value"]);
    if ([needle length] > 0 && [label rangeOfString:needle].location == NSNotFound &&
        [value rangeOfString:needle].location == NSNotFound) {
      continue;
    }
    [matches addObject:choice];
    if ([matches count] >= MAX((NSUInteger)1U, limit)) {
      break;
    }
  }
  return matches;
}

- (NSDictionary *)dashboardSummaryWithError:(NSError **)error {
  NSMutableArray *cards = [NSMutableArray array];
  NSMutableArray *highlights = [NSMutableArray array];
  for (ALNAdminUIResourceDescriptor *descriptor in self.resourceDescriptors ?: @[]) {
    if (![descriptor.resource respondsToSelector:@selector(adminUIDashboardSummaryWithError:)]) {
      continue;
    }
    NSError *summaryError = nil;
    NSDictionary *summary = [descriptor.resource adminUIDashboardSummaryWithError:&summaryError];
    if (summary == nil) {
      if (error != NULL && summaryError != nil) {
        *error = summaryError;
      }
      continue;
    }
    NSArray *resourceCards = [summary[@"cards"] isKindOfClass:[NSArray class]] ? summary[@"cards"] : @[];
    NSArray *resourceHighlights = [summary[@"highlights"] isKindOfClass:[NSArray class]] ? summary[@"highlights"] : @[];
    [cards addObjectsFromArray:resourceCards];
    [highlights addObjectsFromArray:resourceHighlights];
  }
  return @{
    @"cards" : cards,
    @"highlights" : highlights,
    @"resources" : [self registeredResources],
  };
}

- (NSArray<NSDictionary *> *)listUsersMatching:(NSString *)query
                                         limit:(NSUInteger)limit
                                        offset:(NSUInteger)offset
                                         error:(NSError **)error {
  return [self listRecordsForResourceIdentifier:@"users" query:query limit:limit offset:offset error:error];
}

- (NSDictionary *)userDetailForSubject:(NSString *)subject
                                 error:(NSError **)error {
  return [self recordDetailForResourceIdentifier:@"users" recordID:subject error:error];
}

- (NSDictionary *)updateUserForSubject:(NSString *)subject
                           displayName:(NSString *)displayName
                                 error:(NSError **)error {
  return [self updateRecordForResourceIdentifier:@"users"
                                        recordID:subject
                                      parameters:@{ @"display_name" : displayName ?: @"" }
                                           error:error];
}

@end

@implementation ALNAdminUIController

- (ALNAdminUIModuleRuntime *)runtime {
  return [ALNAdminUIModuleRuntime sharedRuntime];
}

- (ALNAuthModuleRuntime *)authRuntime {
  return [ALNAuthModuleRuntime sharedRuntime];
}

- (NSDictionary *)requestParameters {
  NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:self.context.request.queryParams ?: @{}];
  NSString *contentType = [[[self headerValueForName:@"content-type"] lowercaseString] componentsSeparatedByString:@";"][0];
  NSDictionary *bodyParameters = @{};
  if ([contentType containsString:@"application/json"]) {
    id object = [NSJSONSerialization JSONObjectWithData:self.context.request.body options:0 error:NULL];
    bodyParameters = [object isKindOfClass:[NSDictionary class]] ? object : @{};
  } else if ([contentType containsString:@"application/x-www-form-urlencoded"]) {
    bodyParameters = AUQueryParametersFromBody(self.context.request.body);
  }
  [parameters addEntriesFromDictionary:bodyParameters ?: @{}];
  return parameters;
}

- (NSString *)mountedReturnPathForContext:(ALNContext *)ctx {
  NSString *path = [self.runtime mountedPathForChildPath:ctx.request.path ?: @"/"];
  NSString *query = AUTrimmedString(ctx.request.queryString);
  if ([query length] > 0) {
    return [NSString stringWithFormat:@"%@?%@", path, query];
  }
  return path;
}

- (NSArray *)navigationEntries {
  NSMutableArray *entries = [NSMutableArray arrayWithObject:@{
    @"label" : @"Dashboard",
    @"href" : self.runtime.mountPrefix ?: @"/admin",
  }];
  for (NSDictionary *resource in [self.runtime registeredResources]) {
    NSDictionary *paths = [resource[@"paths"] isKindOfClass:[NSDictionary class]] ? resource[@"paths"] : @{};
    NSString *href = AUTrimmedString(paths[@"html_index"]);
    if ([href length] == 0) {
      href = [self.runtime mountedPathForChildPath:[NSString stringWithFormat:@"resources/%@", resource[@"identifier"] ?: @"resource"]];
    }
    [entries addObject:@{
      @"label" : AUTrimmedString(resource[@"label"]),
      @"href" : href,
    }];
  }
  [entries addObject:@{
    @"label" : @"Session JSON",
    @"href" : [self.runtime mountedPathForChildPath:[NSString stringWithFormat:@"%@/session", self.runtime.apiPrefix ?: @"/api"]],
  }];
  return [NSArray arrayWithArray:entries];
}

- (NSDictionary *)pageContextWithTitle:(NSString *)title
                               heading:(NSString *)heading
                               message:(NSString *)message
                                errors:(NSArray *)errors
                               current:(NSDictionary *)currentUser
                              extraCtx:(NSDictionary *)extraCtx {
  NSMutableDictionary *context = [NSMutableDictionary dictionary];
  context[@"pageTitle"] = title ?: self.runtime.dashboardTitle ?: @"Arlen Admin";
  context[@"pageHeading"] = heading ?: context[@"pageTitle"];
  context[@"message"] = message ?: @"";
  context[@"errors"] = [errors isKindOfClass:[NSArray class]] ? errors : @[];
  context[@"adminTitle"] = self.runtime.dashboardTitle ?: @"Arlen Admin";
  context[@"adminPrefix"] = self.runtime.mountPrefix ?: @"/admin";
  context[@"adminAPIPrefix"] = self.runtime.apiPrefix ?: @"/api";
  context[@"adminAPISessionPath"] =
      [self.runtime mountedPathForChildPath:[NSString stringWithFormat:@"%@/session", self.runtime.apiPrefix ?: @"/api"]];
  context[@"authLoginPath"] = [self.authRuntime loginPath] ?: @"/auth/login";
  context[@"authLogoutPath"] = [self.authRuntime logoutPath] ?: @"/auth/logout";
  context[@"csrfToken"] = [self csrfToken] ?: @"";
  context[@"navigation"] = [self navigationEntries];
  context[@"currentUser"] = [currentUser isKindOfClass:[NSDictionary class]] ? currentUser : @{};
  context[@"registeredResources"] = [self.runtime registeredResources];
  if ([extraCtx isKindOfClass:[NSDictionary class]]) {
    [context addEntriesFromDictionary:extraCtx];
  }
  return context;
}

- (BOOL)requireAdminHTML:(ALNContext *)ctx {
  NSString *returnTo = [self mountedReturnPathForContext:ctx];
  if ([[ctx authSubject] length] == 0) {
    NSString *location = [NSString stringWithFormat:@"%@?return_to=%@",
                                                    [self.authRuntime loginPath] ?: @"/auth/login",
                                                    AUPercentEncodedQueryComponent(returnTo)];
    [self redirectTo:location status:302];
    return NO;
  }
  if (![self.authRuntime isAdminContext:ctx error:NULL]) {
    [self setStatus:403];
    [self renderTemplate:@"modules/admin-ui/result/index"
                 context:[self pageContextWithTitle:@"Admin Access"
                                         heading:@"Access denied"
                                         message:@"You do not have the admin role required for this surface."
                                          errors:nil
                                         current:[self.authRuntime currentUserForContext:ctx error:NULL]
                                        extraCtx:@{
                                          @"resultActionPath" : self.runtime.mountPrefix ?: @"/admin",
                                          @"resultActionLabel" : @"Back to admin",
                                        }]
                  layout:@"modules/admin-ui/layouts/main"
                   error:NULL];
    return NO;
  }
  if ([ctx authAssuranceLevel] < 2) {
    NSString *location = [NSString stringWithFormat:@"%@?return_to=%@",
                                                    [self.authRuntime totpPath] ?: @"/auth/mfa/totp",
                                                    AUPercentEncodedQueryComponent(returnTo)];
    [self redirectTo:location status:302];
    return NO;
  }
  return YES;
}

- (NSDictionary *)resourceMetadataForIdentifier:(NSString *)resourceID error:(NSError **)error {
  NSDictionary *resource = [self.runtime resourceMetadataForIdentifier:resourceID];
  if (resource == nil && error != NULL) {
    *error = AUError(ALNAdminUIModuleErrorNotFound,
                     [NSString stringWithFormat:@"unknown admin resource %@", resourceID ?: @""],
                     @{ @"resource" : AUTrimmedString(resourceID) });
  }
  return resource;
}

- (BOOL)ensureResourceOperation:(NSString *)operation
                 resourceID:(NSString *)resourceID
                   recordID:(NSString *)recordID
                    context:(ALNContext *)ctx
                 errorBlock:(BOOL (^)(NSError *error))errorBlock {
  NSError *error = nil;
  BOOL allowed = [self.runtime resourceIdentifier:resourceID
                                   allowsOperation:operation
                                         recordID:recordID
                                          context:ctx
                                            error:&error];
  if (allowed) {
    return YES;
  }
  if (errorBlock != NULL) {
    return errorBlock(error ?: AUError(ALNAdminUIModuleErrorPolicyRejected, @"admin policy denied this operation", nil));
  }
  return NO;
}

- (void)renderResourceResultWithStatus:(NSInteger)status
                                 title:(NSString *)title
                               heading:(NSString *)heading
                               message:(NSString *)message
                           actionPath:(NSString *)actionPath
                          actionLabel:(NSString *)actionLabel {
  [self setStatus:status];
  [self renderTemplate:@"modules/admin-ui/result/index"
               context:[self pageContextWithTitle:title
                                       heading:heading
                                       message:message
                                        errors:nil
                                       current:[self.authRuntime currentUserForContext:self.context error:NULL]
                                      extraCtx:@{
                                        @"resultActionPath" : actionPath ?: (self.runtime.mountPrefix ?: @"/admin"),
                                        @"resultActionLabel" : actionLabel ?: @"Back to admin",
                                      }]
                layout:@"modules/admin-ui/layouts/main"
                 error:NULL];
}

- (NSDictionary *)listContextForResource:(NSDictionary *)resource
                               identifier:(NSString *)resourceID
                               parameters:(NSDictionary *)parameters
                                    error:(NSError **)error {
  NSDictionary *pagination = [resource[@"pagination"] isKindOfClass:[NSDictionary class]] ? resource[@"pagination"] : @{};
  NSUInteger defaultLimit = [pagination[@"defaultLimit"] respondsToSelector:@selector(unsignedIntegerValue)]
                                ? [pagination[@"defaultLimit"] unsignedIntegerValue]
                                : 50U;
  NSUInteger maxLimit = [pagination[@"maxLimit"] respondsToSelector:@selector(unsignedIntegerValue)]
                            ? [pagination[@"maxLimit"] unsignedIntegerValue]
                            : MAX((NSUInteger)50U, defaultLimit);
  if (defaultLimit == 0U) {
    defaultLimit = 50U;
  }
  if (maxLimit < defaultLimit) {
    maxLimit = defaultLimit;
  }
  NSUInteger limit = [parameters[@"limit"] respondsToSelector:@selector(unsignedIntegerValue)]
                         ? [parameters[@"limit"] unsignedIntegerValue]
                         : defaultLimit;
  if (limit == 0U) {
    limit = defaultLimit;
  }
  limit = MIN(MAX((NSUInteger)1U, limit), maxLimit);
  NSUInteger page = [parameters[@"page"] respondsToSelector:@selector(unsignedIntegerValue)]
                        ? [parameters[@"page"] unsignedIntegerValue]
                        : 1U;
  if (page == 0U) {
    page = 1U;
  }
  NSUInteger offset = (page - 1U) * limit;
  NSArray *fetched = [self.runtime listRecordsForResourceIdentifier:resourceID
                                                         parameters:(parameters ?: @{})
                                                              limit:(limit + 1U)
                                                             offset:offset
                                                              error:error];
  if (fetched == nil) {
    return nil;
  }
  BOOL hasNext = [fetched count] > limit;
  NSArray *records = hasNext ? [fetched subarrayWithRange:NSMakeRange(0, limit)] : fetched;
  return @{
    @"records" : records ?: @[],
    @"parameters" : parameters ?: @{},
    @"pagination" : @{
      @"page" : @(page),
      @"limit" : @(limit),
      @"offset" : @(offset),
      @"hasPrevious" : @(page > 1U),
      @"hasNext" : @(hasNext),
      @"previousPage" : @(page > 1U ? (page - 1U) : 1U),
      @"nextPage" : @(page + 1U),
      @"pageSizes" : [pagination[@"pageSizes"] isKindOfClass:[NSArray class]] ? pagination[@"pageSizes"] : @[ @(defaultLimit) ],
    },
  };
}

- (NSArray<NSString *> *)selectedRecordIDsFromParameters:(NSDictionary *)parameters {
  NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
  if ([parameters[@"identifiers"] isKindOfClass:[NSArray class]]) {
    [identifiers addObjectsFromArray:AUNormalizedIdentifierArray(parameters[@"identifiers"])];
  } else {
    NSString *csvIdentifiers = AUTrimmedString(parameters[@"identifiers"]);
    if ([csvIdentifiers length] > 0) {
      [identifiers addObjectsFromArray:AUNormalizedIdentifierArray([csvIdentifiers componentsSeparatedByString:@","])];
    }
  }
  for (NSString *key in [parameters allKeys]) {
    if (![key hasPrefix:@"selected__"]) {
      continue;
    }
    if (!AUBoolValue(parameters[key], NO)) {
      continue;
    }
    NSString *identifier = [key substringFromIndex:[@"selected__" length]];
    if ([identifier length] == 0 || [identifiers containsObject:identifier]) {
      continue;
    }
    [identifiers addObject:identifier];
  }
  return [NSArray arrayWithArray:identifiers];
}

- (void)renderExportPayload:(NSDictionary *)payload {
  NSString *filename = AUTrimmedString(payload[@"filename"]);
  if ([filename length] > 0) {
    [self.context.response setHeader:@"Content-Disposition" value:[NSString stringWithFormat:@"attachment; filename=\"%@\"", filename]];
  }
  [self renderData:[payload[@"bodyData"] isKindOfClass:[NSData class]] ? payload[@"bodyData"] : [NSData data]
       contentType:AUTrimmedString(payload[@"contentType"])];
}

- (id)dashboard:(ALNContext *)ctx {
  NSError *error = nil;
  NSDictionary *summary = [self.runtime dashboardSummaryWithError:&error] ?: @{};
  NSDictionary *currentUser = [self.authRuntime currentUserForContext:ctx error:NULL] ?: @{};
  BOOL rendered = [self renderTemplate:@"modules/admin-ui/dashboard/index"
                               context:[self pageContextWithTitle:self.runtime.dashboardTitle
                                                       heading:self.runtime.dashboardTitle
                                                       message:@""
                                                        errors:(error != nil)
                                                                   ? @[ @{ @"message" : error.localizedDescription ?: @"Failed loading dashboard" } ]
                                                                   : nil
                                                       current:currentUser
                                                      extraCtx:@{
                                                        @"summary" : summary ?: @{},
                                                      }]
                                layout:@"modules/admin-ui/layouts/main"
                                 error:NULL];
  if (!rendered) {
    [self setStatus:500];
    [self renderText:@"render failed\n"];
  }
  return nil;
}

- (id)renderResourceIndexForIdentifier:(NSString *)resourceID
                               context:(ALNContext *)ctx
                               message:(NSString *)message
                                errors:(NSArray *)errors {
  NSError *resourceError = nil;
  NSDictionary *resource = [self resourceMetadataForIdentifier:resourceID error:&resourceError];
  if (resource == nil) {
    [self renderResourceResultWithStatus:404
                                   title:@"Resource"
                                 heading:@"Resource not found"
                                 message:resourceError.localizedDescription ?: @"Resource not found."
                              actionPath:self.runtime.mountPrefix
                             actionLabel:@"Back to admin"];
    return nil;
  }
  if (![self ensureResourceOperation:@"list"
                          resourceID:resourceID
                            recordID:nil
                             context:ctx
                          errorBlock:^BOOL(NSError *error) {
                            [self renderResourceResultWithStatus:403
                                                           title:resource[@"label"]
                                                         heading:@"Access denied"
                                                         message:error.localizedDescription ?: @"Access denied."
                                                      actionPath:self.runtime.mountPrefix
                                                     actionLabel:@"Back to admin"];
                            return NO;
                          }]) {
    return nil;
  }
  NSDictionary *parameters = [self requestParameters];
  NSError *listError = nil;
  NSDictionary *listContext = [self listContextForResource:resource identifier:resourceID parameters:parameters error:&listError] ?: @{};
  NSDictionary *currentUser = [self.authRuntime currentUserForContext:ctx error:NULL] ?: @{};
  NSMutableArray *allErrors = [NSMutableArray array];
  for (NSDictionary *entry in [errors isKindOfClass:[NSArray class]] ? errors : @[]) {
    [allErrors addObject:entry];
  }
  if (listError != nil) {
    [allErrors addObject:@{ @"message" : listError.localizedDescription ?: @"Failed loading records" }];
  }
  BOOL rendered = [self renderTemplate:@"modules/admin-ui/resources/index"
                               context:[self pageContextWithTitle:resource[@"label"]
                                                       heading:resource[@"label"]
                                                       message:message ?: @""
                                                        errors:([allErrors count] > 0) ? allErrors : nil
                                                       current:currentUser
                                                      extraCtx:@{
                                                        @"resource" : resource,
                                                        @"records" : listContext[@"records"] ?: @[],
                                                        @"query" : AUTrimmedString(parameters[@"q"]),
                                                        @"parameters" : parameters ?: @{},
                                                        @"pagination" : listContext[@"pagination"] ?: @{},
                                                      }]
                                layout:@"modules/admin-ui/layouts/main"
                                 error:NULL];
  if (!rendered) {
    [self setStatus:500];
    [self renderText:@"render failed\n"];
  }
  return nil;
}

- (id)renderResourceIndexForIdentifier:(NSString *)resourceID context:(ALNContext *)ctx {
  return [self renderResourceIndexForIdentifier:resourceID context:ctx message:nil errors:nil];
}

- (id)resourceIndex:(ALNContext *)ctx {
  return [self renderResourceIndexForIdentifier:[self paramValueForName:@"resource"] context:ctx];
}

- (id)usersIndex:(ALNContext *)ctx {
  return [self renderResourceIndexForIdentifier:@"users" context:ctx];
}

- (id)renderResourceDetailForIdentifier:(NSString *)resourceID
                               recordID:(NSString *)recordID
                                context:(ALNContext *)ctx
                                message:(NSString *)message
                                 errors:(NSArray *)errors {
  NSError *resourceError = nil;
  NSDictionary *resource = [self resourceMetadataForIdentifier:resourceID error:&resourceError];
  if (resource == nil) {
    [self renderResourceResultWithStatus:404
                                   title:@"Resource"
                                 heading:@"Resource not found"
                                 message:resourceError.localizedDescription ?: @"Resource not found."
                              actionPath:self.runtime.mountPrefix
                             actionLabel:@"Back to admin"];
    return nil;
  }
  if (![self ensureResourceOperation:@"detail"
                          resourceID:resourceID
                            recordID:recordID
                             context:ctx
                          errorBlock:^BOOL(NSError *error) {
                            [self renderResourceResultWithStatus:403
                                                           title:resource[@"label"]
                                                         heading:@"Access denied"
                                                         message:error.localizedDescription ?: @"Access denied."
                                                      actionPath:self.runtime.mountPrefix
                                                     actionLabel:@"Back to admin"];
                            return NO;
                          }]) {
    return nil;
  }
  NSError *detailError = nil;
  NSDictionary *record = [self.runtime recordDetailForResourceIdentifier:resourceID recordID:recordID error:&detailError];
  if (record == nil) {
    [self renderResourceResultWithStatus:404
                                   title:resource[@"singularLabel"]
                                 heading:[NSString stringWithFormat:@"%@ not found", resource[@"singularLabel"] ?: @"Record"]
                                 message:detailError.localizedDescription ?: @"The requested record could not be found."
                              actionPath:[resource[@"paths"] isKindOfClass:[NSDictionary class]] ? resource[@"paths"][@"html_index"] : self.runtime.mountPrefix
                             actionLabel:[NSString stringWithFormat:@"Back to %@", AULowerTrimmedString(resource[@"label"])]];
    return nil;
  }
  NSDictionary *currentUser = [self.authRuntime currentUserForContext:ctx error:NULL] ?: @{};
  BOOL rendered = [self renderTemplate:@"modules/admin-ui/resources/show"
                               context:[self pageContextWithTitle:resource[@"singularLabel"]
                                                       heading:AUTrimmedString(record[resource[@"primaryField"] ?: @"id"])
                                                       message:message ?: @""
                                                        errors:errors
                                                       current:currentUser
                                                      extraCtx:@{
                                                        @"resource" : resource,
                                                        @"record" : record,
                                                      }]
                                layout:@"modules/admin-ui/layouts/main"
                                 error:NULL];
  if (!rendered) {
    [self setStatus:500];
    [self renderText:@"render failed\n"];
  }
  return nil;
}

- (id)resourceDetail:(ALNContext *)ctx {
  return [self renderResourceDetailForIdentifier:[self paramValueForName:@"resource"]
                                        recordID:[self paramValueForName:@"identifier"]
                                         context:ctx
                                         message:nil
                                          errors:nil];
}

- (id)userDetail:(ALNContext *)ctx {
  return [self renderResourceDetailForIdentifier:@"users"
                                        recordID:[self paramValueForName:@"identifier"]
                                         context:ctx
                                         message:nil
                                          errors:nil];
}

- (id)updateResourceHTMLForIdentifier:(NSString *)resourceID recordID:(NSString *)recordID context:(ALNContext *)ctx {
  if (![self ensureResourceOperation:@"update"
                          resourceID:resourceID
                            recordID:recordID
                             context:ctx
                          errorBlock:^BOOL(NSError *error) {
                            [self renderResourceResultWithStatus:403
                                                           title:@"Access denied"
                                                         heading:@"Access denied"
                                                         message:error.localizedDescription ?: @"Access denied."
                                                      actionPath:self.runtime.mountPrefix
                                                     actionLabel:@"Back to admin"];
                            return NO;
                          }]) {
    return nil;
  }
  NSError *error = nil;
  NSDictionary *record = [self.runtime updateRecordForResourceIdentifier:resourceID
                                                                recordID:recordID
                                                              parameters:[self requestParameters]
                                                                   error:&error];
  if (record == nil) {
    [self setStatus:(error.code == ALNAdminUIModuleErrorNotFound) ? 404 : 422];
    return [self renderResourceDetailForIdentifier:resourceID
                                          recordID:recordID
                                           context:ctx
                                           message:@""
                                            errors:@[ @{ @"message" : error.localizedDescription ?: @"Update failed" } ]];
  }
  NSString *detailPath =
      [NSString stringWithFormat:@"%@/%@",
                                 [self.runtime resourceMetadataForIdentifier:resourceID][@"paths"][@"html_index"] ?: self.runtime.mountPrefix,
                                 AUTrimmedString(recordID)];
  [self redirectTo:detailPath status:302];
  return nil;
}

- (id)updateResourceHTML:(ALNContext *)ctx {
  return [self updateResourceHTMLForIdentifier:[self paramValueForName:@"resource"]
                                      recordID:[self paramValueForName:@"identifier"]
                                       context:ctx];
}

- (id)updateUserHTML:(ALNContext *)ctx {
  return [self updateResourceHTMLForIdentifier:@"users" recordID:[self paramValueForName:@"identifier"] context:ctx];
}

- (id)performResourceActionHTMLForIdentifier:(NSString *)resourceID
                                    recordID:(NSString *)recordID
                                  actionName:(NSString *)actionName
                                     context:(ALNContext *)ctx {
  NSString *operation = [NSString stringWithFormat:@"action:%@", AULowerTrimmedString(actionName)];
  if (![self ensureResourceOperation:operation
                          resourceID:resourceID
                            recordID:recordID
                             context:ctx
                          errorBlock:^BOOL(NSError *error) {
                            [self renderResourceResultWithStatus:403
                                                           title:@"Access denied"
                                                         heading:@"Access denied"
                                                         message:error.localizedDescription ?: @"Access denied."
                                                      actionPath:self.runtime.mountPrefix
                                                     actionLabel:@"Back to admin"];
                            return NO;
                          }]) {
    return nil;
  }
  NSError *error = nil;
  NSDictionary *result = [self.runtime performActionNamed:actionName
                                    forResourceIdentifier:resourceID
                                                 recordID:recordID
                                               parameters:[self requestParameters]
                                                    error:&error];
  if (result == nil) {
    [self renderResourceResultWithStatus:(error.code == ALNAdminUIModuleErrorNotFound) ? 404 : 422
                                   title:@"Action failed"
                                 heading:@"Action failed"
                                 message:error.localizedDescription ?: @"Action failed."
                              actionPath:self.runtime.mountPrefix
                             actionLabel:@"Back to admin"];
    return nil;
  }
  return [self renderResourceDetailForIdentifier:resourceID
                                        recordID:recordID
                                         context:ctx
                                         message:AUTrimmedString(result[@"message"])
                                          errors:nil];
}

- (id)resourceActionHTML:(ALNContext *)ctx {
  return [self performResourceActionHTMLForIdentifier:[self paramValueForName:@"resource"]
                                             recordID:[self paramValueForName:@"identifier"]
                                           actionName:[self paramValueForName:@"action"]
                                              context:ctx];
}

- (id)userActionHTML:(ALNContext *)ctx {
  return [self performResourceActionHTMLForIdentifier:@"users"
                                             recordID:[self paramValueForName:@"identifier"]
                                           actionName:[self paramValueForName:@"action"]
                                              context:ctx];
}

- (id)performResourceBulkActionHTMLForIdentifier:(NSString *)resourceID
                                      actionName:(NSString *)actionName
                                         context:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSArray<NSString *> *recordIDs = [self selectedRecordIDsFromParameters:parameters];
  if ([recordIDs count] == 0) {
    [self setStatus:422];
    return [self renderResourceIndexForIdentifier:resourceID
                                          context:ctx
                                          message:@""
                                           errors:@[ @{ @"message" : @"Select at least one record before running a bulk action." } ]];
  }
  NSString *operation = [NSString stringWithFormat:@"action:%@", AULowerTrimmedString(actionName)];
  for (NSString *recordID in recordIDs) {
    if (![self ensureResourceOperation:operation
                            resourceID:resourceID
                              recordID:recordID
                               context:ctx
                            errorBlock:^BOOL(NSError *error) {
                              [self renderResourceResultWithStatus:403
                                                             title:@"Access denied"
                                                           heading:@"Access denied"
                                                           message:error.localizedDescription ?: @"Access denied."
                                                        actionPath:self.runtime.mountPrefix
                                                       actionLabel:@"Back to admin"];
                              return NO;
                            }]) {
      return nil;
    }
  }
  NSError *error = nil;
  NSDictionary *result = [self.runtime performBulkActionNamed:actionName
                                        forResourceIdentifier:resourceID
                                                    recordIDs:recordIDs
                                                   parameters:parameters
                                                        error:&error];
  if (result == nil) {
    [self setStatus:(error.code == ALNAdminUIModuleErrorNotFound) ? 404 : 422];
    return [self renderResourceIndexForIdentifier:resourceID
                                          context:ctx
                                          message:@""
                                           errors:@[ @{ @"message" : error.localizedDescription ?: @"Bulk action failed" } ]];
  }
  return [self renderResourceIndexForIdentifier:resourceID
                                        context:ctx
                                        message:AUTrimmedString(result[@"message"])
                                         errors:nil];
}

- (id)resourceBulkActionHTML:(ALNContext *)ctx {
  return [self performResourceBulkActionHTMLForIdentifier:[self paramValueForName:@"resource"]
                                               actionName:[self paramValueForName:@"action"]
                                                  context:ctx];
}

- (id)userBulkActionHTML:(ALNContext *)ctx {
  return [self performResourceBulkActionHTMLForIdentifier:@"users"
                                               actionName:[self paramValueForName:@"action"]
                                                  context:ctx];
}

- (id)exportResourceHTMLForIdentifier:(NSString *)resourceID
                               format:(NSString *)format
                              context:(ALNContext *)ctx {
  if (![self ensureResourceOperation:@"list"
                          resourceID:resourceID
                            recordID:nil
                             context:ctx
                          errorBlock:^BOOL(NSError *error) {
                            [self renderResourceResultWithStatus:403
                                                           title:@"Access denied"
                                                         heading:@"Access denied"
                                                         message:error.localizedDescription ?: @"Access denied."
                                                      actionPath:self.runtime.mountPrefix
                                                     actionLabel:@"Back to admin"];
                            return NO;
                          }]) {
    return nil;
  }
  NSError *error = nil;
  NSDictionary *payload = [self.runtime exportPayloadForResourceIdentifier:resourceID
                                                                    format:format
                                                                parameters:[self requestParameters]
                                                                     error:&error];
  if (payload == nil) {
    [self renderResourceResultWithStatus:(error.code == ALNAdminUIModuleErrorNotFound) ? 404 : 422
                                   title:@"Export failed"
                                 heading:@"Export failed"
                                 message:error.localizedDescription ?: @"Export failed."
                              actionPath:self.runtime.mountPrefix
                             actionLabel:@"Back to admin"];
    return nil;
  }
  [self renderExportPayload:payload];
  return nil;
}

- (id)resourceExportHTML:(ALNContext *)ctx {
  return [self exportResourceHTMLForIdentifier:[self paramValueForName:@"resource"]
                                        format:[self paramValueForName:@"format"]
                                       context:ctx];
}

- (id)userExportHTML:(ALNContext *)ctx {
  return [self exportResourceHTMLForIdentifier:@"users" format:[self paramValueForName:@"format"] context:ctx];
}

- (id)apiSession:(ALNContext *)ctx {
  NSDictionary *session = [self.authRuntime sessionPayloadForContext:ctx includeUser:YES error:NULL] ?: @{};
  NSDictionary *dashboard = [self.runtime dashboardSummaryWithError:NULL] ?: @{};
  return @{
    @"session" : session,
    @"module" : [self.runtime resolvedConfigSummary],
    @"dashboard" : dashboard,
    @"resources" : [self.runtime registeredResources],
  };
}

- (id)apiResourcesIndex:(ALNContext *)ctx {
  (void)ctx;
  return @{
    @"status" : @"ok",
    @"resources" : [self.runtime registeredResources],
  };
}

- (id)apiResourceMetadata:(ALNContext *)ctx {
  NSDictionary *resource = [self.runtime resourceMetadataForIdentifier:[self paramValueForName:@"resource"]];
  if (resource == nil) {
    [self setStatus:404];
    return @{
      @"status" : @"error",
      @"message" : @"Resource not found",
    };
  }
  return @{
    @"status" : @"ok",
    @"resource" : resource,
  };
}

- (id)apiResourceItemsIndexForIdentifier:(NSString *)resourceID context:(ALNContext *)ctx {
  if (![self ensureResourceOperation:@"list"
                          resourceID:resourceID
                            recordID:nil
                             context:ctx
                          errorBlock:^BOOL(NSError *error) {
                            [self setStatus:403];
                            return NO;
                          }]) {
    return @{
      @"status" : @"error",
      @"message" : @"Access denied",
    };
  }
  NSDictionary *resource = [self.runtime resourceMetadataForIdentifier:resourceID] ?: @{};
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSDictionary *listContext = [self listContextForResource:resource identifier:resourceID parameters:parameters error:&error];
  if (listContext == nil) {
    [self setStatus:500];
    return @{
      @"status" : @"error",
      @"message" : error.localizedDescription ?: @"Failed loading records",
    };
  }
  return @{
    @"status" : @"ok",
    @"resource" : resource,
    @"items" : listContext[@"records"] ?: @[],
    @"query" : AUTrimmedString(parameters[@"q"]),
    @"parameters" : parameters ?: @{},
    @"pagination" : listContext[@"pagination"] ?: @{},
  };
}

- (id)apiResourceItemsIndex:(ALNContext *)ctx {
  return [self apiResourceItemsIndexForIdentifier:[self paramValueForName:@"resource"] context:ctx];
}

- (id)apiUsersIndex:(ALNContext *)ctx {
  return [self apiResourceItemsIndexForIdentifier:@"users" context:ctx];
}

- (id)apiResourceItemDetailForIdentifier:(NSString *)resourceID
                                recordID:(NSString *)recordID
                                 context:(ALNContext *)ctx {
  if (![self ensureResourceOperation:@"detail"
                          resourceID:resourceID
                            recordID:recordID
                             context:ctx
                          errorBlock:^BOOL(NSError *error) {
                            [self setStatus:403];
                            return NO;
                          }]) {
    return @{
      @"status" : @"error",
      @"message" : @"Access denied",
    };
  }
  NSError *error = nil;
  NSDictionary *record = [self.runtime recordDetailForResourceIdentifier:resourceID recordID:recordID error:&error];
  if (record == nil) {
    [self setStatus:404];
    return @{
      @"status" : @"error",
      @"message" : error.localizedDescription ?: @"Record not found",
    };
  }
  return @{
    @"status" : @"ok",
    @"resource" : [self.runtime resourceMetadataForIdentifier:resourceID] ?: @{},
    @"item" : record,
  };
}

- (id)apiResourceItemDetail:(ALNContext *)ctx {
  return [self apiResourceItemDetailForIdentifier:[self paramValueForName:@"resource"]
                                         recordID:[self paramValueForName:@"identifier"]
                                          context:ctx];
}

- (id)apiUserDetail:(ALNContext *)ctx {
  return [self apiResourceItemDetailForIdentifier:@"users" recordID:[self paramValueForName:@"identifier"] context:ctx];
}

- (id)apiResourceItemUpdateForIdentifier:(NSString *)resourceID
                                recordID:(NSString *)recordID
                                 context:(ALNContext *)ctx {
  if (![self ensureResourceOperation:@"update"
                          resourceID:resourceID
                            recordID:recordID
                             context:ctx
                          errorBlock:^BOOL(NSError *error) {
                            [self setStatus:403];
                            return NO;
                          }]) {
    return @{
      @"status" : @"error",
      @"message" : @"Access denied",
    };
  }
  NSError *error = nil;
  NSDictionary *record = [self.runtime updateRecordForResourceIdentifier:resourceID
                                                                recordID:recordID
                                                              parameters:[self requestParameters]
                                                                   error:&error];
  if (record == nil) {
    [self setStatus:(error.code == ALNAdminUIModuleErrorNotFound) ? 404 : 422];
    return @{
      @"status" : @"error",
      @"message" : error.localizedDescription ?: @"Update failed",
      @"field" : AUTrimmedString(error.userInfo[@"field"]),
    };
  }
  return @{
    @"status" : @"ok",
    @"resource" : [self.runtime resourceMetadataForIdentifier:resourceID] ?: @{},
    @"item" : record,
  };
}

- (id)apiResourceItemUpdate:(ALNContext *)ctx {
  return [self apiResourceItemUpdateForIdentifier:[self paramValueForName:@"resource"]
                                         recordID:[self paramValueForName:@"identifier"]
                                          context:ctx];
}

- (id)apiUserUpdate:(ALNContext *)ctx {
  return [self apiResourceItemUpdateForIdentifier:@"users" recordID:[self paramValueForName:@"identifier"] context:ctx];
}

- (id)apiResourceItemActionForIdentifier:(NSString *)resourceID
                                recordID:(NSString *)recordID
                              actionName:(NSString *)actionName
                                 context:(ALNContext *)ctx {
  NSString *operation = [NSString stringWithFormat:@"action:%@", AULowerTrimmedString(actionName)];
  if (![self ensureResourceOperation:operation
                          resourceID:resourceID
                            recordID:recordID
                             context:ctx
                          errorBlock:^BOOL(NSError *error) {
                            [self setStatus:403];
                            return NO;
                          }]) {
    return @{
      @"status" : @"error",
      @"message" : @"Access denied",
    };
  }
  NSError *error = nil;
  NSDictionary *result = [self.runtime performActionNamed:actionName
                                    forResourceIdentifier:resourceID
                                                 recordID:recordID
                                               parameters:[self requestParameters]
                                                    error:&error];
  if (result == nil) {
    [self setStatus:(error.code == ALNAdminUIModuleErrorNotFound) ? 404 : 422];
    return @{
      @"status" : @"error",
      @"message" : error.localizedDescription ?: @"Action failed",
    };
  }
  return @{
    @"status" : @"ok",
    @"resource" : [self.runtime resourceMetadataForIdentifier:resourceID] ?: @{},
    @"result" : result,
  };
}

- (id)apiResourceItemAction:(ALNContext *)ctx {
  return [self apiResourceItemActionForIdentifier:[self paramValueForName:@"resource"]
                                         recordID:[self paramValueForName:@"identifier"]
                                       actionName:[self paramValueForName:@"action"]
                                          context:ctx];
}

- (id)apiUserAction:(ALNContext *)ctx {
  return [self apiResourceItemActionForIdentifier:@"users"
                                         recordID:[self paramValueForName:@"identifier"]
                                       actionName:[self paramValueForName:@"action"]
                                          context:ctx];
}

- (id)apiResourceBulkActionForIdentifier:(NSString *)resourceID
                              actionName:(NSString *)actionName
                                 context:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSArray<NSString *> *recordIDs = [self selectedRecordIDsFromParameters:parameters];
  if ([recordIDs count] == 0) {
    [self setStatus:422];
    return @{
      @"status" : @"error",
      @"message" : @"At least one identifier is required",
    };
  }
  NSString *operation = [NSString stringWithFormat:@"action:%@", AULowerTrimmedString(actionName)];
  for (NSString *recordID in recordIDs) {
    if (![self ensureResourceOperation:operation
                            resourceID:resourceID
                              recordID:recordID
                               context:ctx
                            errorBlock:^BOOL(NSError *error) {
                              [self setStatus:403];
                              return NO;
                            }]) {
      return @{
        @"status" : @"error",
        @"message" : @"Access denied",
      };
    }
  }
  NSError *error = nil;
  NSDictionary *result = [self.runtime performBulkActionNamed:actionName
                                        forResourceIdentifier:resourceID
                                                    recordIDs:recordIDs
                                                   parameters:parameters
                                                        error:&error];
  if (result == nil) {
    [self setStatus:(error.code == ALNAdminUIModuleErrorNotFound) ? 404 : 422];
    return @{
      @"status" : @"error",
      @"message" : error.localizedDescription ?: @"Bulk action failed",
    };
  }
  return @{
    @"status" : @"ok",
    @"resource" : [self.runtime resourceMetadataForIdentifier:resourceID] ?: @{},
    @"result" : result,
  };
}

- (id)apiResourceBulkAction:(ALNContext *)ctx {
  return [self apiResourceBulkActionForIdentifier:[self paramValueForName:@"resource"]
                                       actionName:[self paramValueForName:@"action"]
                                          context:ctx];
}

- (id)apiUsersBulkAction:(ALNContext *)ctx {
  return [self apiResourceBulkActionForIdentifier:@"users"
                                       actionName:[self paramValueForName:@"action"]
                                          context:ctx];
}

- (id)apiResourceExportForIdentifier:(NSString *)resourceID
                              format:(NSString *)format
                             context:(ALNContext *)ctx {
  if (![self ensureResourceOperation:@"list"
                          resourceID:resourceID
                            recordID:nil
                             context:ctx
                          errorBlock:^BOOL(NSError *error) {
                            [self setStatus:403];
                            return NO;
                          }]) {
    return @{
      @"status" : @"error",
      @"message" : @"Access denied",
    };
  }
  NSError *error = nil;
  NSDictionary *payload = [self.runtime exportPayloadForResourceIdentifier:resourceID
                                                                    format:format
                                                                parameters:[self requestParameters]
                                                                     error:&error];
  if (payload == nil) {
    [self setStatus:(error.code == ALNAdminUIModuleErrorNotFound) ? 404 : 422];
    return @{
      @"status" : @"error",
      @"message" : error.localizedDescription ?: @"Export failed",
    };
  }
  [self renderExportPayload:payload];
  return nil;
}

- (id)apiResourceExport:(ALNContext *)ctx {
  return [self apiResourceExportForIdentifier:[self paramValueForName:@"resource"]
                                       format:[self paramValueForName:@"format"]
                                      context:ctx];
}

- (id)apiUsersExport:(ALNContext *)ctx {
  return [self apiResourceExportForIdentifier:@"users" format:[self paramValueForName:@"format"] context:ctx];
}

- (id)apiResourceAutocompleteForIdentifier:(NSString *)resourceID
                                 fieldName:(NSString *)fieldName
                                   context:(ALNContext *)ctx {
  if (![self ensureResourceOperation:@"list"
                          resourceID:resourceID
                            recordID:nil
                             context:ctx
                          errorBlock:^BOOL(NSError *error) {
                            [self setStatus:403];
                            return NO;
                          }]) {
    return @{
      @"status" : @"error",
      @"message" : @"Access denied",
    };
  }
  NSDictionary *parameters = [self requestParameters];
  NSUInteger limit = [parameters[@"limit"] respondsToSelector:@selector(unsignedIntegerValue)]
                         ? [parameters[@"limit"] unsignedIntegerValue]
                         : 10U;
  NSError *error = nil;
  NSArray *suggestions = [self.runtime autocompleteSuggestionsForResourceIdentifier:resourceID
                                                                          fieldName:fieldName
                                                                              query:parameters[@"q"]
                                                                              limit:limit
                                                                              error:&error];
  if (suggestions == nil) {
    [self setStatus:(error.code == ALNAdminUIModuleErrorNotFound) ? 404 : 422];
    return @{
      @"status" : @"error",
      @"message" : error.localizedDescription ?: @"Autocomplete failed",
    };
  }
  return @{
    @"status" : @"ok",
    @"resource" : [self.runtime resourceMetadataForIdentifier:resourceID] ?: @{},
    @"field" : AULowerTrimmedString(fieldName),
    @"suggestions" : suggestions,
  };
}

- (id)apiResourceAutocomplete:(ALNContext *)ctx {
  return [self apiResourceAutocompleteForIdentifier:[self paramValueForName:@"resource"]
                                          fieldName:[self paramValueForName:@"field"]
                                            context:ctx];
}

- (id)apiUsersAutocomplete:(ALNContext *)ctx {
  return [self apiResourceAutocompleteForIdentifier:@"users"
                                          fieldName:[self paramValueForName:@"field"]
                                            context:ctx];
}

@end

@implementation ALNAdminUIModule

- (NSString *)moduleIdentifier {
  return @"admin-ui";
}

- (BOOL)registerWithApplication:(ALNApplication *)application
                          error:(NSError **)error {
  ALNAdminUIModuleRuntime *runtime = [ALNAdminUIModuleRuntime sharedRuntime];
  if (![runtime configureWithApplication:application error:error]) {
    return NO;
  }

  ALNApplication *child = runtime.mountedApplication;
  if (child == nil) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorMountFailed, @"failed creating mounted admin application", nil);
    }
    return NO;
  }

  [child beginRouteGroupWithPrefix:@"/" guardAction:@"requireAdminHTML" formats:nil];
  [child registerRouteMethod:@"GET"
                        path:@"/"
                        name:@"admin_dashboard"
             controllerClass:[ALNAdminUIController class]
                      action:@"dashboard"];
  [child registerRouteMethod:@"GET"
                        path:@"/resources/:resource"
                        name:@"admin_resource_index"
             controllerClass:[ALNAdminUIController class]
                      action:@"resourceIndex"];
  [child registerRouteMethod:@"GET"
                        path:@"/resources/:resource/:identifier"
                        name:@"admin_resource_detail"
             controllerClass:[ALNAdminUIController class]
                      action:@"resourceDetail"];
  [child registerRouteMethod:@"POST"
                        path:@"/resources/:resource/:identifier"
                        name:@"admin_resource_update"
             controllerClass:[ALNAdminUIController class]
                      action:@"updateResourceHTML"];
  [child registerRouteMethod:@"POST"
                        path:@"/resources/:resource/:identifier/actions/:action"
                        name:@"admin_resource_action"
             controllerClass:[ALNAdminUIController class]
                      action:@"resourceActionHTML"];
  [child registerRouteMethod:@"POST"
                        path:@"/resources/:resource/bulk-actions/:action"
                        name:@"admin_resource_bulk_action"
             controllerClass:[ALNAdminUIController class]
                      action:@"resourceBulkActionHTML"];
  [child registerRouteMethod:@"GET"
                        path:@"/resources/:resource/export/:format"
                        name:@"admin_resource_export"
             controllerClass:[ALNAdminUIController class]
                      action:@"resourceExportHTML"];
  [child registerRouteMethod:@"GET"
                        path:@"/users"
                        name:@"admin_users"
             controllerClass:[ALNAdminUIController class]
                      action:@"usersIndex"];
  [child registerRouteMethod:@"GET"
                        path:@"/users/:identifier"
                        name:@"admin_user_detail"
             controllerClass:[ALNAdminUIController class]
                      action:@"userDetail"];
  [child registerRouteMethod:@"POST"
                        path:@"/users/:identifier"
                        name:@"admin_user_update"
             controllerClass:[ALNAdminUIController class]
                      action:@"updateUserHTML"];
  [child registerRouteMethod:@"POST"
                        path:@"/users/:identifier/actions/:action"
                        name:@"admin_user_action"
             controllerClass:[ALNAdminUIController class]
                      action:@"userActionHTML"];
  [child registerRouteMethod:@"POST"
                        path:@"/users/bulk-actions/:action"
                        name:@"admin_user_bulk_action"
             controllerClass:[ALNAdminUIController class]
                      action:@"userBulkActionHTML"];
  [child registerRouteMethod:@"GET"
                        path:@"/users/export/:format"
                        name:@"admin_user_export"
             controllerClass:[ALNAdminUIController class]
                      action:@"userExportHTML"];
  [child registerRouteMethod:@"GET"
                        path:@"/:resource/export/:format"
                        name:@"admin_resource_legacy_export"
             controllerClass:[ALNAdminUIController class]
                      action:@"resourceExportHTML"];
  [child registerRouteMethod:@"POST"
                        path:@"/:resource/bulk-actions/:action"
                        name:@"admin_resource_legacy_bulk_action"
             controllerClass:[ALNAdminUIController class]
                      action:@"resourceBulkActionHTML"];
  [child registerRouteMethod:@"POST"
                        path:@"/:resource/:identifier/actions/:action"
                        name:@"admin_resource_legacy_action"
             controllerClass:[ALNAdminUIController class]
                      action:@"resourceActionHTML"];
  [child registerRouteMethod:@"GET"
                        path:@"/:resource/:identifier"
                        name:@"admin_resource_legacy_detail"
             controllerClass:[ALNAdminUIController class]
                      action:@"resourceDetail"];
  [child registerRouteMethod:@"POST"
                        path:@"/:resource/:identifier"
                        name:@"admin_resource_legacy_update"
             controllerClass:[ALNAdminUIController class]
                      action:@"updateResourceHTML"];
  [child registerRouteMethod:@"GET"
                        path:@"/:resource"
                        name:@"admin_resource_legacy_index"
             controllerClass:[ALNAdminUIController class]
                      action:@"resourceIndex"];
  [child endRouteGroup];

  [child beginRouteGroupWithPrefix:runtime.apiPrefix guardAction:nil formats:nil];
  [child registerRouteMethod:@"GET"
                        path:@"/session"
                        name:@"admin_api_session"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiSession"];
  [child registerRouteMethod:@"GET"
                        path:@"/resources"
                        name:@"admin_api_resources"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiResourcesIndex"];
  [child registerRouteMethod:@"GET"
                        path:@"/resources/:resource"
                        name:@"admin_api_resource_metadata"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiResourceMetadata"];
  [child registerRouteMethod:@"GET"
                        path:@"/resources/:resource/items"
                        name:@"admin_api_resource_items"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiResourceItemsIndex"];
  [child registerRouteMethod:@"GET"
                        path:@"/resources/:resource/items/:identifier"
                        name:@"admin_api_resource_item_detail"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiResourceItemDetail"];
  [child registerRouteMethod:@"POST"
                        path:@"/resources/:resource/items/:identifier"
                        name:@"admin_api_resource_item_update"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiResourceItemUpdate"];
  [child registerRouteMethod:@"POST"
                        path:@"/resources/:resource/items/:identifier/actions/:action"
                        name:@"admin_api_resource_item_action"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiResourceItemAction"];
  [child registerRouteMethod:@"POST"
                        path:@"/resources/:resource/bulk-actions/:action"
                        name:@"admin_api_resource_bulk_action"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiResourceBulkAction"];
  [child registerRouteMethod:@"GET"
                        path:@"/resources/:resource/export/:format"
                        name:@"admin_api_resource_export"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiResourceExport"];
  [child registerRouteMethod:@"GET"
                        path:@"/resources/:resource/autocomplete/:field"
                        name:@"admin_api_resource_autocomplete"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiResourceAutocomplete"];
  [child registerRouteMethod:@"GET"
                        path:@"/users"
                        name:@"admin_api_users"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiUsersIndex"];
  [child registerRouteMethod:@"GET"
                        path:@"/users/:identifier"
                        name:@"admin_api_user_detail"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiUserDetail"];
  [child registerRouteMethod:@"POST"
                        path:@"/users/:identifier"
                        name:@"admin_api_user_update"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiUserUpdate"];
  [child registerRouteMethod:@"POST"
                        path:@"/users/:identifier/actions/:action"
                        name:@"admin_api_user_action"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiUserAction"];
  [child registerRouteMethod:@"POST"
                        path:@"/users/bulk-actions/:action"
                        name:@"admin_api_users_bulk_action"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiUsersBulkAction"];
  [child registerRouteMethod:@"GET"
                        path:@"/users/export/:format"
                        name:@"admin_api_users_export"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiUsersExport"];
  [child registerRouteMethod:@"GET"
                        path:@"/users/autocomplete/:field"
                        name:@"admin_api_users_autocomplete"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiUsersAutocomplete"];
  [child registerRouteMethod:@"GET"
                        path:@"/:resource/export/:format"
                        name:@"admin_api_resource_legacy_export"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiResourceExport"];
  [child registerRouteMethod:@"GET"
                        path:@"/:resource/autocomplete/:field"
                        name:@"admin_api_resource_legacy_autocomplete"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiResourceAutocomplete"];
  [child registerRouteMethod:@"POST"
                        path:@"/:resource/bulk-actions/:action"
                        name:@"admin_api_resource_legacy_bulk_action"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiResourceBulkAction"];
  [child registerRouteMethod:@"POST"
                        path:@"/:resource/:identifier/actions/:action"
                        name:@"admin_api_resource_legacy_action"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiResourceItemAction"];
  [child registerRouteMethod:@"GET"
                        path:@"/:resource/:identifier"
                        name:@"admin_api_resource_legacy_detail"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiResourceItemDetail"];
  [child registerRouteMethod:@"POST"
                        path:@"/:resource/:identifier"
                        name:@"admin_api_resource_legacy_update"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiResourceItemUpdate"];
  [child registerRouteMethod:@"GET"
                        path:@"/:resource"
                        name:@"admin_api_resource_legacy_items"
             controllerClass:[ALNAdminUIController class]
                      action:@"apiResourceItemsIndex"];
  [child endRouteGroup];

  NSDictionary *security = [application.config[@"security"] isKindOfClass:[NSDictionary class]]
                                ? application.config[@"security"]
                                : @{};
  NSDictionary *routePolicies = [security[@"routePolicies"] isKindOfClass:[NSDictionary class]]
                                     ? security[@"routePolicies"]
                                     : @{};
  BOOL attachAdminPolicy = [routePolicies[@"admin"] isKindOfClass:[NSDictionary class]];
  if (attachAdminPolicy) {
    NSError *policyError = nil;
    for (ALNRoute *route in [child.router allRoutes]) {
      if ([route.name length] == 0) {
        continue;
      }
      if (![child configureRoutePoliciesForRouteNamed:route.name
                                             policies:@[ @"admin" ]
                                                error:&policyError]) {
        if (error != NULL) {
          *error = policyError;
        }
        return NO;
      }
    }
  }

  NSError *routeError = nil;
  NSMutableDictionary *routeSchemas = [NSMutableDictionary dictionaryWithDictionary:@{
    @"admin_api_session" : @{ @"request" : [NSNull null], @"response" : @{ @"type" : @"object" } },
    @"admin_api_resources" : @{ @"request" : [NSNull null], @"response" : @{ @"type" : @"object" } },
    @"admin_api_resource_metadata" : @{
      @"request" : AUAdminMetadataPathSchema(@"admin resource identifier", @"Admin resource metadata path parameters"),
      @"response" : @{ @"type" : @"object" },
    },
    @"admin_api_resource_items" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"resource" : @{ @"type" : @"string", @"source" : @"path" },
          @"q" : @{ @"type" : @"string", @"source" : @"query" },
        },
        @"required" : @[ @"resource" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"admin_api_resource_item_detail" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"resource" : @{ @"type" : @"string", @"source" : @"path" },
          @"identifier" : @{ @"type" : @"string", @"source" : @"path" },
        },
        @"required" : @[ @"resource", @"identifier" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"admin_api_resource_item_update" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"resource" : @{ @"type" : @"string", @"source" : @"path" },
          @"identifier" : @{ @"type" : @"string", @"source" : @"path" },
          @"display_name" : @{ @"type" : @"string", @"source" : @"body" },
        },
        @"required" : @[ @"resource", @"identifier" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"admin_api_resource_item_action" : @{
      @"request" : AUAdminMetadataActionSchema(),
      @"response" : @{ @"type" : @"object" },
    },
    @"admin_api_resource_bulk_action" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"resource" : @{ @"type" : @"string", @"source" : @"path" },
          @"action" : @{ @"type" : @"string", @"source" : @"path" },
          @"identifiers" : @{ @"type" : @"array", @"items" : @{ @"type" : @"string" }, @"source" : @"body" },
        },
        @"required" : @[ @"resource", @"action" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"admin_api_resource_export" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"resource" : @{ @"type" : @"string", @"source" : @"path" },
          @"format" : @{ @"type" : @"string", @"source" : @"path" },
        },
        @"required" : @[ @"resource", @"format" ],
      },
      @"response" : @{ @"type" : @"string" },
    },
    @"admin_api_resource_autocomplete" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"resource" : @{ @"type" : @"string", @"source" : @"path" },
          @"field" : @{ @"type" : @"string", @"source" : @"path" },
          @"q" : @{ @"type" : @"string", @"source" : @"query" },
          @"limit" : @{ @"type" : @"integer", @"source" : @"query" },
        },
        @"required" : @[ @"resource", @"field" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"admin_api_users" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{ @"q" : @{ @"type" : @"string", @"source" : @"query" } },
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"admin_api_user_detail" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{ @"identifier" : @{ @"type" : @"string", @"source" : @"path" } },
        @"required" : @[ @"identifier" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"admin_api_user_update" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"identifier" : @{ @"type" : @"string", @"source" : @"path" },
          @"display_name" : @{ @"type" : @"string", @"source" : @"body" },
        },
        @"required" : @[ @"identifier" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"admin_api_user_action" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"identifier" : @{ @"type" : @"string", @"source" : @"path" },
          @"action" : @{ @"type" : @"string", @"source" : @"path" },
        },
        @"required" : @[ @"identifier", @"action" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"admin_api_users_bulk_action" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"action" : @{ @"type" : @"string", @"source" : @"path" },
          @"identifiers" : @{ @"type" : @"array", @"items" : @{ @"type" : @"string" }, @"source" : @"body" },
        },
        @"required" : @[ @"action" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
    @"admin_api_users_export" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"format" : @{ @"type" : @"string", @"source" : @"path" },
        },
        @"required" : @[ @"format" ],
      },
      @"response" : @{ @"type" : @"string" },
    },
    @"admin_api_users_autocomplete" : @{
      @"request" : @{
        @"type" : @"object",
        @"properties" : @{
          @"field" : @{ @"type" : @"string", @"source" : @"path" },
          @"q" : @{ @"type" : @"string", @"source" : @"query" },
          @"limit" : @{ @"type" : @"integer", @"source" : @"query" },
        },
        @"required" : @[ @"field" ],
      },
      @"response" : @{ @"type" : @"object" },
    },
  }];
  routeSchemas[@"admin_api_resource_legacy_items"] = routeSchemas[@"admin_api_resource_items"];
  routeSchemas[@"admin_api_resource_legacy_detail"] = routeSchemas[@"admin_api_resource_item_detail"];
  routeSchemas[@"admin_api_resource_legacy_update"] = routeSchemas[@"admin_api_resource_item_update"];
  routeSchemas[@"admin_api_resource_legacy_action"] = routeSchemas[@"admin_api_resource_item_action"];
  routeSchemas[@"admin_api_resource_legacy_bulk_action"] = routeSchemas[@"admin_api_resource_bulk_action"];
  routeSchemas[@"admin_api_resource_legacy_export"] = routeSchemas[@"admin_api_resource_export"];
  routeSchemas[@"admin_api_resource_legacy_autocomplete"] = routeSchemas[@"admin_api_resource_autocomplete"];

  NSArray<NSString *> *apiRouteNames = [routeSchemas allKeys];
  for (NSString *routeName in apiRouteNames) {
    NSDictionary *schema = routeSchemas[routeName];
    NSDictionary *requestSchema = [schema[@"request"] isKindOfClass:[NSDictionary class]] ? schema[@"request"] : nil;
    NSDictionary *responseSchema = [schema[@"response"] isKindOfClass:[NSDictionary class]] ? schema[@"response"] : nil;
    if (![child configureRouteNamed:routeName
                      requestSchema:requestSchema
                     responseSchema:responseSchema
                            summary:@"Admin API route"
                        operationID:routeName
                               tags:@[ @"admin-ui" ]
                      requiredScopes:nil
                       requiredRoles:@[ @"admin" ]
                     includeInOpenAPI:YES
                               error:&routeError]) {
      if (error != NULL) {
        *error = routeError;
      }
      return NO;
    }
    if (![child configureAuthAssuranceForRouteNamed:routeName
                         minimumAuthAssuranceLevel:2
                   maximumAuthenticationAgeSeconds:0
                                        stepUpPath:[[ALNAuthModuleRuntime sharedRuntime] totpPath]
                                             error:&routeError]) {
      if (error != NULL) {
        *error = routeError;
      }
      return NO;
    }
  }

  if (![application mountApplication:child atPrefix:runtime.mountPrefix]) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorMountFailed,
                       [NSString stringWithFormat:@"failed mounting admin-ui at %@", runtime.mountPrefix ?: @"/admin"],
                       nil);
    }
    return NO;
  }
  return YES;
}

@end

#import "ALNAdminUIModule.h"

#import "../../auth/Sources/ALNAuthModule.h"

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNPg.h"
#import "ALNRequest.h"

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

static NSArray<NSDictionary *> *AUNormalizedFieldArray(id rawFields) {
  NSArray *fields = [rawFields isKindOfClass:[NSArray class]] ? rawFields : @[];
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
    [normalized addObject:@{
      @"name" : name,
      @"label" : ([AUTrimmedString(entry[@"label"]) length] > 0) ? AUTrimmedString(entry[@"label"]) : AUTitleCaseIdentifier(name),
      @"kind" : ([AULowerTrimmedString(entry[@"kind"]) length] > 0) ? AULowerTrimmedString(entry[@"kind"]) : @"string",
      @"list" : @(AUBoolValue(entry[@"list"], YES)),
      @"detail" : @(AUBoolValue(entry[@"detail"], YES)),
      @"editable" : @(AUBoolValue(entry[@"editable"], NO)),
    }];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSArray<NSDictionary *> *AUNormalizedFilterArray(id rawFilters) {
  NSArray *filters = [rawFilters isKindOfClass:[NSArray class]] ? rawFilters : @[];
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
      @"placeholder" : AUTrimmedString(entry[@"placeholder"]),
    }];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSArray<NSDictionary *> *AUNormalizedSortArray(id rawSorts) {
  NSArray *sorts = [rawSorts isKindOfClass:[NSArray class]] ? rawSorts : @[];
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
    }];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSArray<NSDictionary *> *AUNormalizedActionArray(id rawActions) {
  NSArray *actions = [rawActions isKindOfClass:[NSArray class]] ? rawActions : @[];
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
@property(nonatomic, copy, readwrite) NSString *mountPrefix;
@property(nonatomic, copy, readwrite) NSString *apiPrefix;
@property(nonatomic, copy, readwrite) NSString *dashboardTitle;
@property(nonatomic, strong, readwrite) ALNApplication *mountedApplication;
@property(nonatomic, copy) NSArray<ALNAdminUIResourceDescriptor *> *resourceDescriptors;
@property(nonatomic, copy) NSDictionary<NSString *, ALNAdminUIResourceDescriptor *> *resourceDescriptorMap;

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
    @"fields" : @[
      @{ @"name" : @"email", @"label" : @"Email", @"kind" : @"email", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"display_name", @"label" : @"Display", @"kind" : @"string", @"list" : @YES, @"detail" : @YES, @"editable" : @YES },
      @{ @"name" : @"roles", @"label" : @"Roles", @"kind" : @"array", @"list" : @YES, @"detail" : @YES },
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
    ],
    @"sorts" : @[ @{ @"name" : @"created_at_desc", @"label" : @"Newest first", @"default" : @YES } ],
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
  if (self.runtime.database == nil) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorDatabaseUnavailable, @"admin-ui database is not configured", nil);
    }
    return nil;
  }
  NSString *search = AULowerTrimmedString(query);
  NSString *like = ([search length] > 0) ? [NSString stringWithFormat:@"%%%@%%", search] : @"";
  NSArray *rows = [self.runtime.database
      executeQuery:@"SELECT u.id::text AS id, u.subject, u.email, "
                   "COALESCE(u.display_name, '') AS display_name, "
                   "COALESCE(u.roles_json, '[]') AS roles_json, "
                   "CASE WHEN u.email_verified_at IS NULL THEN 'f' ELSE 't' END AS email_verified, "
                   "CASE WHEN EXISTS (SELECT 1 FROM auth_mfa_enrollments m WHERE m.user_id = u.id AND m.enabled = TRUE) "
                   "THEN 't' ELSE 'f' END AS mfa_enabled, "
                   "(SELECT COUNT(*)::text FROM auth_provider_identities p WHERE p.user_id = u.id) AS provider_identity_count, "
                   "COALESCE(u.created_at::text, '') AS created_at, "
                   "COALESCE(u.updated_at::text, '') AS updated_at "
                   "FROM auth_users u "
                   "WHERE ($1 = '' OR lower(u.email) LIKE $2 OR lower(COALESCE(u.display_name, '')) LIKE $2 "
                   "       OR lower(u.subject) LIKE $2) "
                   "ORDER BY u.created_at DESC, u.id DESC LIMIT $3 OFFSET $4"
        parameters:@[ search ?: @"", like ?: @"", @(limit), @(offset) ]
             error:error];
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
  NSString *htmlIndexPath = ([legacyPath length] > 0) ? [self mountedPathForChildPath:legacyPath]
                                                      : [self mountedPathForChildPath:[NSString stringWithFormat:@"resources/%@", identifier]];
  NSString *htmlIndexGenericPath = [self mountedPathForChildPath:[NSString stringWithFormat:@"resources/%@", identifier]];
  NSString *apiMetadataPath = [self mountedPathForChildPath:[NSString stringWithFormat:@"%@/resources/%@", self.apiPrefix, identifier]];
  NSString *apiItemsPath = [self mountedPathForChildPath:[NSString stringWithFormat:@"%@/resources/%@/items", self.apiPrefix, identifier]];
  NSMutableDictionary *paths = [NSMutableDictionary dictionaryWithDictionary:@{
    @"html_index" : htmlIndexPath,
    @"html_index_generic" : htmlIndexGenericPath,
    @"html_detail_template" : [NSString stringWithFormat:@"%@/:identifier", htmlIndexPath],
    @"api_metadata" : apiMetadataPath,
    @"api_items" : apiItemsPath,
    @"api_item_template" : [NSString stringWithFormat:@"%@/:identifier", apiItemsPath],
    @"api_action_template" : [NSString stringWithFormat:@"%@/:identifier/actions/:action", apiItemsPath],
  }];
  if ([legacyPath length] > 0) {
    paths[@"legacy_html_index"] = htmlIndexPath;
    paths[@"legacy_api_items"] = [self mountedPathForChildPath:[NSString stringWithFormat:@"%@/%@", self.apiPrefix, legacyPath]];
  }
  return @{
    @"identifier" : identifier,
    @"label" : label,
    @"singularLabel" : singularLabel,
    @"summary" : summary ?: @"",
    @"identifierField" : identifierField,
    @"primaryField" : primaryField,
    @"fields" : AUNormalizedFieldArray(rawMetadata[@"fields"]),
    @"filters" : AUNormalizedFilterArray(rawMetadata[@"filters"]),
    @"sorts" : AUNormalizedSortArray(rawMetadata[@"sorts"]),
    @"actions" : AUNormalizedActionArray(rawMetadata[@"actions"]),
    @"pageSize" : @([rawMetadata[@"pageSize"] respondsToSelector:@selector(integerValue)] ? [rawMetadata[@"pageSize"] integerValue] : 50),
    @"legacyPath" : legacyPath ?: @"",
    @"paths" : paths,
  };
}

- (BOOL)loadResourceRegistryWithError:(NSError **)error {
  NSMutableArray<id<ALNAdminUIResource>> *resources = [NSMutableArray array];
  [resources addObject:[[ALNAdminUIUsersResource alloc] initWithRuntime:self]];

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
  }
  self.resourceDescriptors = [NSArray arrayWithArray:descriptors];
  self.resourceDescriptorMap = [NSDictionary dictionaryWithDictionary:map];
  return YES;
}

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError **)error {
  NSDictionary *moduleConfig = [application.config[@"adminUI"] isKindOfClass:[NSDictionary class]]
                                   ? application.config[@"adminUI"]
                                   : @{};
  self.moduleConfig = moduleConfig;

  NSDictionary *paths = [moduleConfig[@"paths"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"paths"] : @{};
  self.mountPrefix = AUPathJoin(AUTrimmedString(paths[@"prefix"]), @"");
  self.apiPrefix = AUPathJoin(AUTrimmedString(paths[@"apiPrefix"]), @"");
  NSString *dashboardTitle = AUTrimmedString(moduleConfig[@"title"]);
  self.dashboardTitle = ([dashboardTitle length] > 0) ? dashboardTitle : @"Arlen Admin";

  NSDictionary *database = [application.config[@"database"] isKindOfClass:[NSDictionary class]]
                               ? application.config[@"database"]
                               : @{};
  NSString *connectionString = AUTrimmedString(database[@"connectionString"]);
  if ([connectionString length] == 0) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorInvalidConfiguration,
                       @"admin-ui module requires database.connectionString",
                       @{ @"key_path" : @"database.connectionString" });
    }
    return NO;
  }
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

  NSMutableDictionary *childConfig = [NSMutableDictionary dictionary];
  childConfig[@"environment"] = application.environment ?: @"development";
  childConfig[@"logFormat"] = [application.config[@"logFormat"] isKindOfClass:[NSString class]]
                                  ? application.config[@"logFormat"]
                                  : @"text";
  if ([application.config[@"runtimeInvocationMode"] isKindOfClass:[NSString class]]) {
    childConfig[@"runtimeInvocationMode"] = application.config[@"runtimeInvocationMode"];
  }
  for (NSString *key in @[ @"session", @"csrf", @"database", @"securityHeaders", @"observability", @"services" ]) {
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
  return self.resourceDescriptorMap[AULowerTrimmedString(identifier)];
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
  ALNAdminUIResourceDescriptor *descriptor = [self descriptorForIdentifier:identifier];
  if (descriptor == nil) {
    if (error != NULL) {
      *error = AUError(ALNAdminUIModuleErrorNotFound,
                       [NSString stringWithFormat:@"unknown admin resource %@", identifier ?: @""],
                       @{ @"resource" : AUTrimmedString(identifier) });
    }
    return nil;
  }
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
  return [descriptor.resource adminUIUpdateRecordWithIdentifier:recordID parameters:(parameters ?: @{}) error:error];
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
  return [descriptor.resource adminUIPerformActionNamed:actionName identifier:recordID parameters:(parameters ?: @{}) error:error];
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

- (id)renderResourceIndexForIdentifier:(NSString *)resourceID context:(ALNContext *)ctx {
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
  NSString *query = AUTrimmedString(parameters[@"q"]);
  NSUInteger limit = [resource[@"pageSize"] respondsToSelector:@selector(unsignedIntegerValue)] ? [resource[@"pageSize"] unsignedIntegerValue] : 50U;
  NSError *listError = nil;
  NSArray *records = [self.runtime listRecordsForResourceIdentifier:resourceID query:query limit:limit offset:0 error:&listError] ?: @[];
  NSDictionary *currentUser = [self.authRuntime currentUserForContext:ctx error:NULL] ?: @{};
  BOOL rendered = [self renderTemplate:@"modules/admin-ui/resources/index"
                               context:[self pageContextWithTitle:resource[@"label"]
                                                       heading:resource[@"label"]
                                                       message:@""
                                                        errors:(listError != nil)
                                                                   ? @[ @{ @"message" : listError.localizedDescription ?: @"Failed loading records" } ]
                                                                   : nil
                                                       current:currentUser
                                                      extraCtx:@{
                                                        @"resource" : resource,
                                                        @"records" : records ?: @[],
                                                        @"query" : query ?: @"",
                                                      }]
                                layout:@"modules/admin-ui/layouts/main"
                                 error:NULL];
  if (!rendered) {
    [self setStatus:500];
    [self renderText:@"render failed\n"];
  }
  return nil;
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
  NSString *query = AUTrimmedString(parameters[@"q"]);
  NSUInteger limit = [resource[@"pageSize"] respondsToSelector:@selector(unsignedIntegerValue)] ? [resource[@"pageSize"] unsignedIntegerValue] : 50U;
  NSError *error = nil;
  NSArray *records = [self.runtime listRecordsForResourceIdentifier:resourceID query:query limit:limit offset:0 error:&error];
  if (records == nil) {
    [self setStatus:500];
    return @{
      @"status" : @"error",
      @"message" : error.localizedDescription ?: @"Failed loading records",
    };
  }
  return @{
    @"status" : @"ok",
    @"resource" : resource,
    @"items" : records,
    @"query" : query ?: @"",
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
  [child endRouteGroup];

  NSError *routeError = nil;
  NSDictionary *routeSchemas = @{
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
  };

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

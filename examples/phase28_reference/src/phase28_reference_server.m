#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdlib.h>

#import "ArlenServer.h"

static NSString *P28EnvValue(const char *name) {
  const char *value = getenv(name);
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

static NSString *P28ResolveAppRoot(void) {
  NSString *override = P28EnvValue("ARLEN_APP_ROOT");
  NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
  if ([override length] == 0) {
    return cwd;
  }
  if ([override hasPrefix:@"/"]) {
    return [override stringByStandardizingPath];
  }
  return [[cwd stringByAppendingPathComponent:override] stringByStandardizingPath];
}

static NSString *P28TrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [(NSString *)value
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return [trimmed length] > 0 ? trimmed : nil;
}

static NSString *P28ISO8601StringFromDate(NSDate *date) {
  static NSDateFormatter *formatter = nil;
  if (formatter == nil) {
    formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
  }
  return [formatter stringFromDate:date ?: [NSDate date]] ?: @"";
}

static NSString *P28NextUserIdentifier(NSUInteger ordinal) {
  return [NSString stringWithFormat:@"00000000-0000-0000-0000-%012lu", (unsigned long)ordinal];
}

@interface Phase28FixtureStore : NSObject

@property(nonatomic, strong) NSDate *startedAt;
@property(nonatomic, strong) NSMutableArray<NSMutableDictionary *> *users;
@property(nonatomic, assign) NSUInteger nextUserOrdinal;

+ (instancetype)sharedStore;
- (NSDictionary *)sessionPayloadWithCSRFToken:(NSString *)csrfToken;
- (NSDictionary *)listUsersWithLimit:(NSUInteger)limit;
- (nullable NSDictionary *)detailForUserID:(NSString *)userID includePosts:(BOOL)includePosts;
- (NSDictionary *)createUserWithEmail:(NSString *)email
                          displayName:(nullable NSString *)displayName
                                 role:(nullable NSString *)role;
- (nullable NSDictionary *)updateUserWithID:(NSString *)userID
                                displayName:(nullable NSString *)displayName
                                     active:(nullable NSNumber *)active;
- (NSDictionary *)opsSummaryPayload;
- (NSDictionary *)searchCapabilitiesPayload;

@end

@implementation Phase28FixtureStore

+ (instancetype)sharedStore {
  static Phase28FixtureStore *store = nil;
  @synchronized(self) {
    if (store == nil) {
      store = [[Phase28FixtureStore alloc] init];
    }
  }
  return store;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _startedAt = [NSDate date];
    _nextUserOrdinal = 3;
    _users = [NSMutableArray arrayWithArray:@[
      [@{
        @"id" : P28NextUserIdentifier(1),
        @"email" : @"admin@example.com",
        @"displayName" : @"Admin Operator",
        @"active" : @YES,
        @"lastSeenAt" : @"2026-04-02T16:00:00Z",
        @"profile" : @{
          @"bio" : @"Back-office owner for the live Phase 28 reference.",
        },
        @"posts" : @[
          @{
            @"id" : @"10000000-0000-0000-0000-000000000001",
            @"title" : @"Ship the validator bridge",
          },
          @{
            @"id" : @"10000000-0000-0000-0000-000000000002",
            @"title" : @"Audit the live contract lane",
          },
        ],
      } mutableCopy],
      [@{
        @"id" : P28NextUserIdentifier(2),
        @"email" : @"customer@example.com",
        @"displayName" : @"Customer Success",
        @"active" : @YES,
        @"lastSeenAt" : @"2026-04-02T18:30:00Z",
        @"profile" : @{
          @"bio" : @"Customer-facing profile with seeded detail content.",
        },
        @"posts" : @[
          @{
            @"id" : @"20000000-0000-0000-0000-000000000001",
            @"title" : @"Reference dashboard launch",
          },
        ],
      } mutableCopy],
    ]];
  }
  return self;
}

- (NSMutableDictionary *)mutableUserWithID:(NSString *)userID {
  NSString *target = P28TrimmedString(userID);
  if ([target length] == 0) {
    return nil;
  }
  for (NSMutableDictionary *candidate in self.users) {
    NSString *candidateID = P28TrimmedString(candidate[@"id"]);
    if ([candidateID isEqualToString:target]) {
      return candidate;
    }
  }
  return nil;
}

- (NSDictionary *)listItemForUser:(NSDictionary *)user {
  NSString *lastSeenAt = P28TrimmedString(user[@"lastSeenAt"]) ?: @"";
  NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:@{
    @"id" : user[@"id"] ?: @"",
    @"email" : user[@"email"] ?: @"",
  }];
  if (user[@"displayName"] != nil) {
    item[@"displayName"] = user[@"displayName"];
  }
  item[@"meta"] = @{
    @"lastSeenAt" : lastSeenAt,
  };
  return item;
}

- (NSDictionary *)detailPayloadForUser:(NSDictionary *)user includePosts:(BOOL)includePosts {
  NSMutableDictionary *data = [NSMutableDictionary dictionaryWithDictionary:@{
    @"id" : user[@"id"] ?: @"",
    @"email" : user[@"email"] ?: @"",
  }];
  if (user[@"displayName"] != nil) {
    data[@"displayName"] = user[@"displayName"];
  }
  NSDictionary *profile = [user[@"profile"] isKindOfClass:[NSDictionary class]] ? user[@"profile"] : nil;
  if (profile != nil) {
    data[@"profile"] = profile;
  }
  if (includePosts) {
    NSArray *posts = [user[@"posts"] isKindOfClass:[NSArray class]] ? user[@"posts"] : @[];
    data[@"posts"] = posts;
  }
  return @{
    @"data" : data,
  };
}

- (NSDictionary *)sessionPayloadWithCSRFToken:(NSString *)csrfToken {
  NSDictionary *user = [self.users firstObject] ?: @{};
  return @{
    @"authenticated" : @YES,
    @"session" : @{
      @"csrfToken" : P28TrimmedString(csrfToken) ?: @"phase28-csrf-token",
    },
    @"user" : @{
      @"id" : user[@"id"] ?: @"",
      @"email" : user[@"email"] ?: @"",
    },
  };
}

- (NSDictionary *)listUsersWithLimit:(NSUInteger)limit {
  NSUInteger effectiveLimit = (limit == 0) ? 25 : limit;
  NSMutableArray *items = [NSMutableArray array];
  @synchronized(self) {
    NSUInteger count = MIN(effectiveLimit, [self.users count]);
    for (NSUInteger idx = 0; idx < count; idx++) {
      [items addObject:[self listItemForUser:self.users[idx]]];
    }
    return @{
      @"items" : items,
      @"nextCursor" : [NSNull null],
      @"totalCount" : @([self.users count]),
    };
  }
}

- (NSDictionary *)detailForUserID:(NSString *)userID includePosts:(BOOL)includePosts {
  @synchronized(self) {
    NSMutableDictionary *user = [self mutableUserWithID:userID];
    if (user == nil) {
      return nil;
    }
    return [self detailPayloadForUser:user includePosts:includePosts];
  }
}

- (NSDictionary *)createUserWithEmail:(NSString *)email
                          displayName:(NSString *)displayName
                                 role:(NSString *)role {
  (void)role;
  @synchronized(self) {
    NSString *identifier = P28NextUserIdentifier(self.nextUserOrdinal++);
    NSMutableDictionary *user = [NSMutableDictionary dictionaryWithDictionary:@{
      @"id" : identifier,
      @"email" : email ?: @"",
      @"displayName" : displayName ?: [NSNull null],
      @"active" : @YES,
      @"lastSeenAt" : P28ISO8601StringFromDate([NSDate date]),
      @"profile" : @{
        @"bio" : [NSString stringWithFormat:@"Generated profile for %@.", email ?: @"new user"],
      },
      @"posts" : @[],
    }];
    [self.users addObject:user];
    return @{
      @"data" : @{
        @"id" : identifier,
        @"email" : email ?: @"",
        @"displayName" : displayName ?: [NSNull null],
      },
      @"meta" : @{
        @"created" : @YES,
      },
    };
  }
}

- (NSDictionary *)updateUserWithID:(NSString *)userID
                        displayName:(NSString *)displayName
                             active:(NSNumber *)active {
  @synchronized(self) {
    NSMutableDictionary *user = [self mutableUserWithID:userID];
    if (user == nil) {
      return nil;
    }
    if (displayName != nil) {
      user[@"displayName"] = displayName;
    }
    if (active != nil) {
      user[@"active"] = active;
    }
    user[@"lastSeenAt"] = P28ISO8601StringFromDate([NSDate date]);
    return @{
      @"data" : @{
        @"id" : user[@"id"] ?: @"",
        @"email" : user[@"email"] ?: @"",
        @"displayName" : user[@"displayName"] ?: [NSNull null],
      },
      @"meta" : @{
        @"updated" : @YES,
      },
    };
  }
}

- (NSDictionary *)opsSummaryPayload {
  NSTimeInterval uptime = MAX(0.0, [[NSDate date] timeIntervalSinceDate:self.startedAt ?: [NSDate date]]);
  return @{
    @"status" : @"ok",
    @"uptimeSeconds" : @(uptime),
  };
}

- (NSDictionary *)searchCapabilitiesPayload {
  return @{
    @"supportsHighlighting" : @YES,
    @"supportedModes" : @[ @"fulltext", @"prefix" ],
  };
}

@end

@interface Phase28SessionController : ALNController
@end

@implementation Phase28SessionController

- (id)bootstrap:(ALNContext *)ctx {
  (void)ctx;
  return [[Phase28FixtureStore sharedStore] sessionPayloadWithCSRFToken:[self csrfToken]];
}

@end

@interface Phase28UsersController : ALNController
@end

@implementation Phase28UsersController

- (id)listUsers:(ALNContext *)ctx {
  (void)ctx;
  NSNumber *limit = [self validatedValueForName:@"limit"];
  NSUInteger resolvedLimit =
      [limit respondsToSelector:@selector(unsignedIntegerValue)] ? [limit unsignedIntegerValue] : 25;
  return [[Phase28FixtureStore sharedStore] listUsersWithLimit:resolvedLimit];
}

- (id)createUser:(ALNContext *)ctx {
  (void)ctx;
  NSString *email = P28TrimmedString([self validatedValueForName:@"email"]) ?: @"";
  NSString *displayName = P28TrimmedString([self validatedValueForName:@"displayName"]);
  NSString *role = P28TrimmedString([self validatedValueForName:@"role"]);
  return [[Phase28FixtureStore sharedStore] createUserWithEmail:email
                                                    displayName:displayName
                                                           role:role];
}

- (id)getUser:(ALNContext *)ctx {
  (void)ctx;
  NSString *userID = P28TrimmedString([self validatedValueForName:@"id"]);
  BOOL includePosts = [[self validatedValueForName:@"includePosts"] respondsToSelector:@selector(boolValue)] &&
                      [[self validatedValueForName:@"includePosts"] boolValue];
  NSDictionary *payload = [[Phase28FixtureStore sharedStore] detailForUserID:userID includePosts:includePosts];
  if (payload != nil) {
    return payload;
  }
  [self setStatus:404];
  return @{
    @"error" : @{
      @"code" : @"not_found",
      @"message" : @"User not found",
    },
  };
}

- (id)updateUser:(ALNContext *)ctx {
  (void)ctx;
  NSString *userID = P28TrimmedString([self validatedValueForName:@"id"]);
  NSString *displayName = P28TrimmedString([self validatedValueForName:@"displayName"]);
  NSNumber *active = [[self validatedValueForName:@"active"] respondsToSelector:@selector(boolValue)]
                         ? @([[self validatedValueForName:@"active"] boolValue])
                         : nil;
  NSDictionary *payload = [[Phase28FixtureStore sharedStore] updateUserWithID:userID
                                                                   displayName:displayName
                                                                        active:active];
  if (payload != nil) {
    return payload;
  }
  [self setStatus:404];
  return @{
    @"error" : @{
      @"code" : @"not_found",
      @"message" : @"User not found",
    },
  };
}

@end

@interface Phase28OpsController : ALNController
@end

@implementation Phase28OpsController

- (id)summary:(ALNContext *)ctx {
  (void)ctx;
  return [[Phase28FixtureStore sharedStore] opsSummaryPayload];
}

@end

@interface Phase28SearchController : ALNController
@end

@implementation Phase28SearchController

- (id)capabilities:(ALNContext *)ctx {
  (void)ctx;
  return [[Phase28FixtureStore sharedStore] searchCapabilitiesPayload];
}

@end

@interface Phase28HealthController : ALNController
@end

@implementation Phase28HealthController

- (id)health:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"ok\n"];
  return nil;
}

@end

static BOOL P28ConfigureRoute(ALNApplication *app,
                              NSString *routeName,
                              NSDictionary *requestSchema,
                              NSDictionary *responseSchema,
                              NSString *summary,
                              NSString *operationID,
                              NSArray *tags) {
  NSError *error = nil;
  BOOL configured = [app configureRouteNamed:routeName
                               requestSchema:requestSchema
                              responseSchema:responseSchema
                                     summary:summary
                                 operationID:operationID
                                        tags:tags
                               requiredScopes:nil
                                requiredRoles:nil
                              includeInOpenAPI:YES
                                      error:&error];
  if (!configured) {
    fprintf(stderr, "phase28-reference-server: failed configuring route %s: %s\n",
            [routeName UTF8String], [[error localizedDescription] UTF8String]);
  }
  return configured;
}

static ALNApplication *BuildApplication(NSString *environment, NSString *appRoot) {
  NSError *error = nil;
  ALNApplication *app = [[ALNApplication alloc] initWithEnvironment:environment
                                                         configRoot:appRoot
                                                              error:&error];
  if (app == nil) {
    fprintf(stderr, "phase28-reference-server: failed loading config from %s: %s\n",
            [appRoot UTF8String], [[error localizedDescription] UTF8String]);
    return nil;
  }

  [app registerRouteMethod:@"GET"
                      path:@"/healthz"
                      name:@"phase28_health"
           controllerClass:[Phase28HealthController class]
                    action:@"health"];
  [app registerRouteMethod:@"GET"
                      path:@"/api/session"
                      name:@"phase28_session_bootstrap"
           controllerClass:[Phase28SessionController class]
                    action:@"bootstrap"];
  [app registerRouteMethod:@"GET"
                      path:@"/api/users"
                      name:@"phase28_users_list"
           controllerClass:[Phase28UsersController class]
                    action:@"listUsers"];
  [app registerRouteMethod:@"POST"
                      path:@"/api/users"
                      name:@"phase28_users_create"
           controllerClass:[Phase28UsersController class]
                    action:@"createUser"];
  [app registerRouteMethod:@"GET"
                      path:@"/api/users/:id"
                      name:@"phase28_users_get"
           controllerClass:[Phase28UsersController class]
                    action:@"getUser"];
  [app registerRouteMethod:@"PATCH"
                      path:@"/api/users/:id"
                      name:@"phase28_users_update"
           controllerClass:[Phase28UsersController class]
                    action:@"updateUser"];
  [app registerRouteMethod:@"GET"
                      path:@"/ops/api/summary"
                      name:@"phase28_ops_summary"
           controllerClass:[Phase28OpsController class]
                    action:@"summary"];
  [app registerRouteMethod:@"GET"
                      path:@"/search/api/capabilities"
                      name:@"phase28_search_capabilities"
           controllerClass:[Phase28SearchController class]
                    action:@"capabilities"];

  if (!P28ConfigureRoute(
          app,
          @"phase28_session_bootstrap",
          nil,
          @{
            @"type" : @"object",
            @"properties" : @{
              @"authenticated" : @{ @"type" : @"boolean" },
              @"session" : @{
                @"type" : @"object",
                @"properties" : @{
                  @"csrfToken" : @{ @"type" : @"string" },
                },
                @"required" : @[ @"csrfToken" ],
              },
              @"user" : @{
                @"type" : @"object",
                @"properties" : @{
                  @"id" : @{ @"type" : @"string", @"format" : @"uuid" },
                  @"email" : @{ @"type" : @"string", @"format" : @"email" },
                },
                @"required" : @[ @"id", @"email" ],
              },
            },
            @"required" : @[ @"authenticated", @"session" ],
          },
          @"Get session bootstrap",
          @"get_session",
          @[ @"auth", @"session" ])) {
    return nil;
  }

  if (!P28ConfigureRoute(
          app,
          @"phase28_users_list",
          @{
            @"type" : @"object",
            @"properties" : @{
              @"cursor" : @{
                @"type" : @"string",
                @"source" : @"query",
              },
              @"limit" : @{
                @"type" : @"integer",
                @"source" : @"query",
              },
              @"x-tenant-id" : @{
                @"type" : @"string",
                @"source" : @"header",
              },
            },
          },
          @{
            @"type" : @"object",
            @"properties" : @{
                @"items" : @{
                  @"type" : @"array",
                  @"items" : @{
                    @"type" : @"object",
                    @"properties" : @{
                      @"id" : @{ @"type" : @"string", @"format" : @"uuid" },
                      @"email" : @{ @"type" : @"string", @"format" : @"email" },
                      @"displayName" : @{ @"type" : @"string" },
                      @"meta" : @{
                        @"type" : @"object",
                        @"properties" : @{
                          @"lastSeenAt" : @{ @"type" : @"string", @"format" : @"date-time" },
                        },
                      },
                    },
                  @"required" : @[ @"id", @"email" ],
                },
              },
              @"totalCount" : @{ @"type" : @"integer" },
              @"nextCursor" : @{ @"type" : @"string" },
            },
            @"required" : @[ @"items" ],
          },
          @"List users",
          @"list_users",
          @[ @"users" ])) {
    return nil;
  }

  if (!P28ConfigureRoute(
          app,
          @"phase28_users_create",
          @{
            @"type" : @"object",
            @"properties" : @{
              @"email" : @{
                @"type" : @"string",
                @"format" : @"email",
                @"source" : @"body",
                @"required" : @YES,
              },
              @"displayName" : @{
                @"type" : @"string",
                @"source" : @"body",
              },
              @"role" : @{
                @"type" : @"string",
                @"source" : @"body",
                @"enum" : @[ @"author", @"admin" ],
              },
            },
          },
          @{
            @"type" : @"object",
            @"properties" : @{
              @"data" : @{
                @"type" : @"object",
                @"properties" : @{
                  @"id" : @{ @"type" : @"string", @"format" : @"uuid" },
                  @"email" : @{ @"type" : @"string", @"format" : @"email" },
                  @"displayName" : @{ @"type" : @"string" },
                },
                @"required" : @[ @"id", @"email" ],
              },
              @"meta" : @{
                @"type" : @"object",
                @"properties" : @{
                  @"created" : @{ @"type" : @"boolean" },
                },
              },
            },
            @"required" : @[ @"data" ],
          },
          @"Create user",
          @"create_user",
          @[ @"users" ])) {
    return nil;
  }

  if (!P28ConfigureRoute(
          app,
          @"phase28_users_get",
          @{
            @"type" : @"object",
            @"properties" : @{
              @"id" : @{
                @"type" : @"string",
                @"format" : @"uuid",
                @"source" : @"path",
                @"required" : @YES,
              },
              @"includePosts" : @{
                @"type" : @"boolean",
                @"source" : @"query",
              },
            },
          },
          @{
            @"type" : @"object",
            @"properties" : @{
              @"data" : @{
                @"type" : @"object",
                @"properties" : @{
                  @"id" : @{ @"type" : @"string", @"format" : @"uuid" },
                  @"email" : @{ @"type" : @"string", @"format" : @"email" },
                  @"displayName" : @{ @"type" : @"string" },
                  @"profile" : @{
                    @"type" : @"object",
                    @"properties" : @{
                      @"bio" : @{ @"type" : @"string" },
                    },
                  },
                  @"posts" : @{
                    @"type" : @"array",
                    @"items" : @{
                      @"type" : @"object",
                      @"properties" : @{
                        @"id" : @{ @"type" : @"string", @"format" : @"uuid" },
                        @"title" : @{ @"type" : @"string" },
                      },
                      @"required" : @[ @"id", @"title" ],
                    },
                  },
                },
                @"required" : @[ @"id", @"email" ],
              },
            },
            @"required" : @[ @"data" ],
          },
          @"Get user",
          @"get_user",
          @[ @"users" ])) {
    return nil;
  }

  if (!P28ConfigureRoute(
          app,
          @"phase28_users_update",
          @{
            @"type" : @"object",
            @"properties" : @{
              @"id" : @{
                @"type" : @"string",
                @"format" : @"uuid",
                @"source" : @"path",
                @"required" : @YES,
              },
              @"displayName" : @{
                @"type" : @"string",
                @"source" : @"body",
              },
              @"active" : @{
                @"type" : @"boolean",
                @"source" : @"body",
              },
            },
          },
          @{
            @"type" : @"object",
            @"properties" : @{
              @"data" : @{
                @"type" : @"object",
                @"properties" : @{
                  @"id" : @{ @"type" : @"string", @"format" : @"uuid" },
                  @"email" : @{ @"type" : @"string", @"format" : @"email" },
                  @"displayName" : @{ @"type" : @"string" },
                },
                @"required" : @[ @"id", @"email" ],
              },
              @"meta" : @{
                @"type" : @"object",
                @"properties" : @{
                  @"updated" : @{ @"type" : @"boolean" },
                },
              },
            },
            @"required" : @[ @"data" ],
          },
          @"Update user",
          @"update_user",
          @[ @"users" ])) {
    return nil;
  }

  if (!P28ConfigureRoute(
          app,
          @"phase28_ops_summary",
          nil,
          @{
            @"type" : @"object",
            @"properties" : @{
              @"status" : @{ @"type" : @"string" },
              @"uptimeSeconds" : @{ @"type" : @"number" },
            },
            @"required" : @[ @"status", @"uptimeSeconds" ],
          },
          @"Get ops summary",
          @"ops_summary",
          @[ @"ops" ])) {
    return nil;
  }

  if (!P28ConfigureRoute(
          app,
          @"phase28_search_capabilities",
          nil,
          @{
            @"type" : @"object",
            @"properties" : @{
              @"supportsHighlighting" : @{ @"type" : @"boolean" },
              @"supportedModes" : @{
                @"type" : @"array",
                @"items" : @{
                  @"type" : @"string",
                  @"enum" : @[ @"fulltext", @"prefix" ],
                },
              },
            },
            @"required" : @[ @"supportsHighlighting", @"supportedModes" ],
          },
          @"Get search capabilities",
          @"search_capabilities",
          @[ @"search" ])) {
    return nil;
  }

  return app;
}

static void PrintUsage(void) {
  fprintf(stdout,
          "Usage: phase28-reference-server [--port <port>] [--host <addr>] [--env <env>] [--once] [--print-routes]\n");
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    int portOverride = 0;
    NSString *host = nil;
    NSString *environment = @"development";
    BOOL once = NO;
    BOOL printRoutes = NO;

    for (int idx = 1; idx < argc; idx++) {
      NSString *arg = [NSString stringWithUTF8String:argv[idx]];
      if ([arg isEqualToString:@"--port"]) {
        if (idx + 1 >= argc) {
          PrintUsage();
          return 2;
        }
        portOverride = atoi(argv[++idx]);
      } else if ([arg isEqualToString:@"--host"]) {
        if (idx + 1 >= argc) {
          PrintUsage();
          return 2;
        }
        host = [NSString stringWithUTF8String:argv[++idx]];
      } else if ([arg isEqualToString:@"--env"]) {
        if (idx + 1 >= argc) {
          PrintUsage();
          return 2;
        }
        environment = [NSString stringWithUTF8String:argv[++idx]];
      } else if ([arg isEqualToString:@"--once"]) {
        once = YES;
      } else if ([arg isEqualToString:@"--print-routes"]) {
        printRoutes = YES;
      } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
        PrintUsage();
        return 0;
      } else {
        fprintf(stderr, "Unknown argument: %s\n", argv[idx]);
        return 2;
      }
    }

    NSString *appRoot = P28ResolveAppRoot();
    ALNApplication *app = BuildApplication(environment, appRoot);
    if (app == nil) {
      return 1;
    }

    NSString *publicRoot = [appRoot stringByAppendingPathComponent:@"public"];
    ALNHTTPServer *server = [[ALNHTTPServer alloc] initWithApplication:app publicRoot:publicRoot];
    server.serverName = @"phase28-reference-server";

    if (printRoutes) {
      [server printRoutesToFile:stdout];
      return 0;
    }

    return [server runWithHost:host portOverride:portOverride once:once];
  }
}

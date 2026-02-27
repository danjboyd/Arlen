#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

#import "ArlenServer.h"
#import "ALNJSONSerialization.h"

static NSString *EnvString(const char *name) {
  const char *raw = getenv(name);
  if (raw == NULL || raw[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:raw];
}

static NSString *TrimmedStringValue(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  NSString *trimmed = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return trimmed ?: @"";
}

static BOOL ParseStrictIntegerValue(id value, NSInteger *parsedOut) {
  if ([value isKindOfClass:[NSNumber class]]) {
    if (parsedOut != NULL) {
      *parsedOut = [(NSNumber *)value integerValue];
    }
    return YES;
  }
  if (![value isKindOfClass:[NSString class]]) {
    return NO;
  }
  NSString *trimmed =
      [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0) {
    return NO;
  }
  NSScanner *scanner = [NSScanner scannerWithString:trimmed];
  NSInteger parsed = 0;
  if (![scanner scanInteger:&parsed] || ![scanner isAtEnd]) {
    return NO;
  }
  if (parsedOut != NULL) {
    *parsedOut = parsed;
  }
  return YES;
}

static NSString *NormalizedDBIdentifier(NSString *value, NSString *fallback) {
  NSString *trimmed = TrimmedStringValue(value);
  if ([trimmed length] == 0) {
    return fallback ?: @"";
  }
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:
                           @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
  if ([[trimmed stringByTrimmingCharactersInSet:allowed] length] > 0) {
    return fallback ?: @"";
  }
  return trimmed;
}

static NSString *BenchmarkDBSchema(void) {
  return NormalizedDBIdentifier(EnvString("ARLEN_BENCH_DB_SCHEMA"), @"bench");
}

static NSString *BenchmarkDBTable(void) {
  return NormalizedDBIdentifier(EnvString("ARLEN_BENCH_DB_TABLE"), @"items");
}

static NSUInteger BenchmarkDBPoolSize(void) {
  NSInteger parsed = 8;
  NSString *raw = EnvString("ARLEN_BENCH_DB_POOL_SIZE");
  if ([raw length] > 0) {
    parsed = [raw integerValue];
  }
  if (parsed < 1 || parsed > 128) {
    return 8;
  }
  return (NSUInteger)parsed;
}

static NSString *BenchmarkDBConnectionString(void) {
  NSString *explicit = EnvString("ARLEN_BENCH_DB_URL");
  if ([explicit length] > 0) {
    return explicit;
  }
  explicit = EnvString("ARLEN_DATABASE_URL");
  if ([explicit length] > 0) {
    return explicit;
  }

  NSMutableArray *parts = [NSMutableArray array];
  NSString *host = TrimmedStringValue(EnvString("PGHOST"));
  if ([host length] > 0) {
    [parts addObject:[NSString stringWithFormat:@"host=%@", host]];
  }

  NSString *port = TrimmedStringValue(EnvString("PGPORT"));
  if ([port length] == 0) {
    port = @"5432";
  }
  [parts addObject:[NSString stringWithFormat:@"port=%@", port]];

  NSString *user = TrimmedStringValue(EnvString("PGUSER"));
  if ([user length] == 0) {
    user = TrimmedStringValue(EnvString("USER"));
  }
  if ([user length] > 0) {
    [parts addObject:[NSString stringWithFormat:@"user=%@", user]];
  }

  NSString *password = TrimmedStringValue(EnvString("PGPASSWORD"));
  if ([password length] > 0) {
    [parts addObject:[NSString stringWithFormat:@"password=%@", password]];
  }

  NSString *database = TrimmedStringValue(EnvString("PGDATABASE"));
  if ([database length] == 0) {
    database = @"arlen_bench_local";
  }
  [parts addObject:[NSString stringWithFormat:@"dbname=%@", database]];

  return [parts componentsJoinedByString:@" "];
}

static ALNPg *BenchmarkDBAdapter(NSError **error) {
  static ALNPg *adapter = nil;
  @synchronized([ALNPg class]) {
    if (adapter != nil) {
      return adapter;
    }
    NSString *connectionString = BenchmarkDBConnectionString();
    ALNPg *candidate = [[ALNPg alloc] initWithConnectionString:connectionString
                                                 maxConnections:BenchmarkDBPoolSize()
                                                          error:error];
    if (candidate != nil) {
      adapter = candidate;
    }
    return adapter;
  }
}

static NSDictionary *BenchmarkDBErrorPayload(NSString *code, NSString *message) {
  return @{
    @"error" : @{
      @"code" : code ?: @"error",
      @"message" : message ?: @"request failed",
    }
  };
}

static NSUInteger BenchmarkBlobDefaultSize(void) {
  return 262144;
}

static NSUInteger BenchmarkBlobMaximumSize(void) {
  return 2097152;
}

static NSCache *BenchmarkBlobPayloadCache(void) {
  static NSCache *cache = nil;
  static NSLock *lock = nil;
  if (cache != nil) {
    return cache;
  }
  @synchronized([NSProcessInfo processInfo]) {
    if (lock == nil) {
      lock = [[NSLock alloc] init];
    }
  }
  [lock lock];
  if (cache == nil) {
    cache = [[NSCache alloc] init];
    cache.countLimit = 32;
    cache.totalCostLimit = 64 * 1024 * 1024;
  }
  [lock unlock];
  return cache;
}

static NSData *BenchmarkBlobPayloadData(NSUInteger size) {
  NSCache *cache = BenchmarkBlobPayloadCache();
  NSNumber *key = @(size);
  NSData *cached = [cache objectForKey:key];
  if (cached != nil) {
    return cached;
  }

  NSMutableData *payload = [NSMutableData dataWithLength:size];
  if (payload != nil && size > 0) {
    memset([payload mutableBytes], 'x', size);
  }
  NSData *finalPayload = [NSData dataWithData:(payload ?: [NSMutableData data])];
  [cache setObject:finalPayload forKey:key cost:size];
  return finalPayload;
}

static NSString *BenchmarkBlobCacheDirectory(void) {
  NSString *directory =
      [NSTemporaryDirectory() stringByAppendingPathComponent:@"arlen-boomhauer-blob-cache"];
  NSError *error = nil;
  BOOL ok = [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&error];
  if (!ok || error != nil) {
    return nil;
  }
  return directory;
}

static NSString *BenchmarkBlobFilePath(NSUInteger size) {
  NSString *cacheDirectory = BenchmarkBlobCacheDirectory();
  if ([cacheDirectory length] == 0) {
    return nil;
  }
  NSString *path =
      [cacheDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"blob-%lu.bin",
                                                                                (unsigned long)size]];
  struct stat existingStat;
  if (stat([path fileSystemRepresentation], &existingStat) == 0 && S_ISREG(existingStat.st_mode) &&
      (unsigned long long)existingStat.st_size == (unsigned long long)size) {
    return path;
  }

  NSData *payload = BenchmarkBlobPayloadData(size);
  NSError *error = nil;
  BOOL wrote = [payload writeToFile:path options:NSDataWritingAtomic error:&error];
  if (!wrote || error != nil) {
    return nil;
  }
  return path;
}

static NSDictionary *BenchmarkDBParseRequestObject(ALNContext *ctx, NSError **error) {
  NSData *body = [ctx.request.body isKindOfClass:[NSData class]] ? ctx.request.body : [NSData data];
  if ([body length] == 0) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Boomhauer.DB.API"
                                   code:1
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"request body must be a JSON object"
                               }];
    }
    return nil;
  }
  id parsed = [ALNJSONSerialization JSONObjectWithData:body options:0 error:error];
  if (![parsed isKindOfClass:[NSDictionary class]]) {
    if (error != NULL && *error == nil) {
      *error = [NSError errorWithDomain:@"Boomhauer.DB.API"
                                   code:2
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"request body must be a JSON object"
                               }];
    }
    return nil;
  }
  return parsed;
}

@interface HomeController : ALNController
@end

@implementation HomeController

- (id)index:(ALNContext *)ctx {
  NSDictionary *viewContext = @{
    @"title" : @"Arlen EOC Dev Server",
    @"items" : @[
      @"render pipeline ok",
      [NSString stringWithFormat:@"request path: %@", ctx.request.path ?: @"/"],
      @"unsafe sample: <unsafe>"
    ]
  };

  NSError *error = nil;
  BOOL rendered = [self renderTemplate:@"index" context:viewContext error:&error];
  if (!rendered) {
    [self setStatus:500];
    [self renderText:[NSString stringWithFormat:@"render failed: %@",
                                                error.localizedDescription ?: @"unknown"]];
  }
  return nil;
}

- (id)about:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"Arlen Phase 1 server\n"];
  return nil;
}

@end

@interface ApiController : ALNController
@end

@implementation ApiController

- (id)status:(ALNContext *)ctx {
  (void)ctx;
  return @{
    @"ok" : @(YES),
    @"server" : @"boomhauer",
    @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
  };
}

- (id)echo:(ALNContext *)ctx {
  NSString *name = ctx.params[@"name"] ?: @"unknown";
  return @{
    @"name" : name,
    @"path" : ctx.request.path ?: @"",
  };
}

- (id)requestMeta:(ALNContext *)ctx {
  return @{
    @"remoteAddress" : ctx.request.remoteAddress ?: @"",
    @"effectiveRemoteAddress" : ctx.request.effectiveRemoteAddress ?: @"",
    @"scheme" : ctx.request.scheme ?: @"http",
  };
}

- (id)sleep:(ALNContext *)ctx {
  NSInteger delayMs = 250;
  NSNumber *requested = [ctx queryIntegerForName:@"ms"];
  if (requested != nil) {
    NSInteger parsed = [requested integerValue];
    if (parsed >= 0 && parsed <= 10000) {
      delayMs = parsed;
    }
  }
  if (delayMs > 0) {
    [NSThread sleepForTimeInterval:((double)delayMs) / 1000.0];
  }
  return @{
    @"ok" : @(YES),
    @"sleep_ms" : @(delayMs),
  };
}

- (id)blob:(ALNContext *)ctx {
  NSInteger size = (NSInteger)BenchmarkBlobDefaultSize();
  NSNumber *requested = [ctx queryIntegerForName:@"size"];
  if (requested != nil) {
    NSInteger parsed = [requested integerValue];
    if (parsed > 0 && parsed <= (NSInteger)BenchmarkBlobMaximumSize()) {
      size = parsed;
    }
  }

  NSString *mode = [[ctx queryValueForName:@"mode"] lowercaseString];
  BOOL useSendfileMode = [mode isEqualToString:@"sendfile"] || [mode isEqualToString:@"file"];
  if (useSendfileMode) {
    NSString *path = BenchmarkBlobFilePath((NSUInteger)size);
    if ([path length] == 0) {
      [self setStatus:500];
      [self renderText:@"blob cache write failed\n"];
      return nil;
    }

    struct stat fileStat;
    if (stat([path fileSystemRepresentation], &fileStat) != 0 || !S_ISREG(fileStat.st_mode)) {
      [self setStatus:500];
      [self renderText:@"blob cache stat failed\n"];
      return nil;
    }

    ctx.response.statusCode = 200;
    [ctx.response setHeader:@"Content-Type" value:@"application/octet-stream"];
    [ctx.response setHeader:@"Cache-Control" value:@"no-store"];
    ctx.response.fileBodyPath = path;
    ctx.response.fileBodyLength = (unsigned long long)fileStat.st_size;
    ctx.response.fileBodyDevice = (unsigned long long)fileStat.st_dev;
    ctx.response.fileBodyInode = (unsigned long long)fileStat.st_ino;
    ctx.response.fileBodyMTimeSeconds = (long long)fileStat.st_mtime;
#if defined(__APPLE__) || defined(__MACH__)
    ctx.response.fileBodyMTimeNanoseconds = fileStat.st_mtimespec.tv_nsec;
#elif defined(__linux__)
    ctx.response.fileBodyMTimeNanoseconds = fileStat.st_mtim.tv_nsec;
#else
    ctx.response.fileBodyMTimeNanoseconds = 0;
#endif
    ctx.response.committed = YES;
    return nil;
  }

  NSString *impl = [[ctx queryValueForName:@"impl"] lowercaseString];
  if ([impl isEqualToString:@"legacy-string"]) {
    static NSString *chunk =
        @"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
    NSMutableString *payload = [NSMutableString stringWithCapacity:(NSUInteger)size];
    while ((NSInteger)[payload length] < size) {
      NSInteger remaining = size - (NSInteger)[payload length];
      if (remaining >= (NSInteger)[chunk length]) {
        [payload appendString:chunk];
      } else {
        [payload appendString:[chunk substringToIndex:(NSUInteger)remaining]];
      }
    }
    return payload;
  }

  return BenchmarkBlobPayloadData((NSUInteger)size);
}

- (id)dbItemsRead:(ALNContext *)ctx {
  (void)ctx;
  NSString *category = TrimmedStringValue([self queryValueForName:@"category"]);
  if ([category length] == 0) {
    [self setStatus:400];
    return BenchmarkDBErrorPayload(@"bad_request", @"category is required");
  }

  NSInteger limit = 50;
  NSNumber *requestedLimit = [self queryIntegerForName:@"limit"];
  if (requestedLimit != nil) {
    limit = [requestedLimit integerValue];
  }
  if (limit < 1 || limit > 1000) {
    [self setStatus:400];
    return BenchmarkDBErrorPayload(@"bad_request", @"limit must be between 1 and 1000");
  }

  NSError *dbError = nil;
  ALNPg *database = BenchmarkDBAdapter(&dbError);
  if (database == nil) {
    [self setStatus:500];
    return BenchmarkDBErrorPayload(@"db_unavailable", @"database connection unavailable");
  }

  NSString *sql = [NSString stringWithFormat:
                                @"select id, name, amount, category, "
                                 "to_char(updated_at at time zone 'UTC', "
                                 "'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"') as created "
                                 "from \"%@\".\"%@\" "
                                 "where category = $1 "
                                 "order by id asc "
                                 "limit $2",
                                 BenchmarkDBSchema(),
                                 BenchmarkDBTable()];
  NSArray *rows = [database executeQuery:sql parameters:@[ category, @(limit) ] error:&dbError];
  if (rows == nil) {
    [self setStatus:500];
    return BenchmarkDBErrorPayload(@"db_error", @"database query failed");
  }

  NSMutableArray *items = [NSMutableArray arrayWithCapacity:[rows count]];
  for (id value in rows) {
    NSDictionary *row = [value isKindOfClass:[NSDictionary class]] ? value : @{};
    NSInteger itemID = [row[@"id"] respondsToSelector:@selector(integerValue)]
                           ? [row[@"id"] integerValue]
                           : 0;
    NSInteger amount = [row[@"amount"] respondsToSelector:@selector(integerValue)]
                           ? [row[@"amount"] integerValue]
                           : 0;
    NSString *name = [row[@"name"] isKindOfClass:[NSString class]] ? row[@"name"] : @"";
    NSString *itemCategory =
        [row[@"category"] isKindOfClass:[NSString class]] ? row[@"category"] : @"";
    NSString *created = [row[@"created"] isKindOfClass:[NSString class]] ? row[@"created"] : @"";
    [items addObject:@{
      @"id" : @(itemID),
      @"name" : name,
      @"amount" : @(amount),
      @"category" : itemCategory,
      @"created" : created,
    }];
  }

  return @{
    @"items" : items,
    @"count" : @([items count]),
    @"category" : category,
    @"limit" : @(limit),
  };
}

- (id)dbItemsWrite:(ALNContext *)ctx {
  NSError *parseError = nil;
  NSDictionary *payload = BenchmarkDBParseRequestObject(ctx, &parseError);
  if (payload == nil) {
    [self setStatus:400];
    return BenchmarkDBErrorPayload(@"bad_request", @"request body must be a JSON object");
  }

  NSString *name = TrimmedStringValue(payload[@"name"]);
  NSString *category = TrimmedStringValue(payload[@"category"]);
  NSInteger amount = 0;
  BOOL amountOK = ParseStrictIntegerValue(payload[@"amount"], &amount);

  if ([name length] == 0 || [category length] == 0 || !amountOK) {
    [self setStatus:400];
    return BenchmarkDBErrorPayload(@"bad_request",
                                   @"name/category/amount are required and amount must be integer");
  }
  if (amount < -1000000 || amount > 1000000) {
    [self setStatus:400];
    return BenchmarkDBErrorPayload(@"bad_request", @"amount must be between -1000000 and 1000000");
  }

  NSError *dbError = nil;
  ALNPg *database = BenchmarkDBAdapter(&dbError);
  if (database == nil) {
    [self setStatus:500];
    return BenchmarkDBErrorPayload(@"db_unavailable", @"database connection unavailable");
  }

  NSString *sql = [NSString stringWithFormat:
                                @"insert into \"%@\".\"%@\" (name, amount, category) "
                                 "values ($1, $2, $3) "
                                 "returning id, name, amount, category, "
                                 "to_char(updated_at at time zone 'UTC', "
                                 "'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"') as created",
                                 BenchmarkDBSchema(),
                                 BenchmarkDBTable()];
  NSArray *rows = [database executeQuery:sql
                              parameters:@[ name, @(amount), category ]
                                   error:&dbError];
  if ([rows count] == 0) {
    [self setStatus:500];
    return BenchmarkDBErrorPayload(@"db_error", @"database insert failed");
  }

  NSDictionary *row = [rows[0] isKindOfClass:[NSDictionary class]] ? rows[0] : @{};
  NSInteger itemID = [row[@"id"] respondsToSelector:@selector(integerValue)]
                         ? [row[@"id"] integerValue]
                         : 0;
  NSInteger storedAmount = [row[@"amount"] respondsToSelector:@selector(integerValue)]
                               ? [row[@"amount"] integerValue]
                               : amount;
  NSString *storedName = [row[@"name"] isKindOfClass:[NSString class]] ? row[@"name"] : name;
  NSString *storedCategory =
      [row[@"category"] isKindOfClass:[NSString class]] ? row[@"category"] : category;
  NSString *created = [row[@"created"] isKindOfClass:[NSString class]] ? row[@"created"] : @"";

  [self setStatus:201];
  return @{
    @"id" : @(itemID),
    @"name" : storedName,
    @"amount" : @(storedAmount),
    @"category" : storedCategory,
    @"created" : created,
  };
}

@end

@interface RealtimeController : ALNController
@end

@implementation RealtimeController

- (id)wsEcho:(ALNContext *)ctx {
  (void)ctx;
  [self acceptWebSocketEcho];
  return nil;
}

- (id)wsChannel:(ALNContext *)ctx {
  NSString *channel = [self stringParamForName:@"channel"] ?: @"default";
  [self acceptWebSocketChannel:channel];
  return nil;
}

- (id)sseTicker:(ALNContext *)ctx {
  NSInteger count = 3;
  NSString *rawCount = [self stringParamForName:@"count"];
  if ([rawCount length] > 0) {
    NSInteger parsed = [rawCount integerValue];
    if (parsed > 0 && parsed <= 12) {
      count = parsed;
    }
  }

  NSMutableArray *events = [NSMutableArray array];
  for (NSInteger idx = 0; idx < count; idx++) {
    [events addObject:@{
      @"id" : [NSString stringWithFormat:@"%ld", (long)(idx + 1)],
      @"event" : @"tick",
      @"data" : @{
        @"index" : @(idx + 1),
        @"source" : @"boomhauer",
      },
      @"retry" : @(1000),
    }];
  }
  [self renderSSEEvents:events];
  return nil;
}

@end

@interface EmbeddedController : ALNController
@end

@implementation EmbeddedController

- (id)status:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"embedded-ok\n"];
  return nil;
}

- (id)apiStatus:(ALNContext *)ctx {
  (void)ctx;
  return @{
    @"ok" : @(YES),
    @"mounted" : @(YES),
    @"name" : @"embedded-app",
  };
}

@end

@interface ServicesController : ALNController
@end

@implementation ServicesController

- (id)cacheProbe:(ALNContext *)ctx {
  (void)ctx;
  id<ALNCacheAdapter> cache = [self cacheAdapter];
  if (cache == nil) {
    return @{
      @"ok" : @(NO),
      @"error" : @"cache adapter unavailable",
    };
  }

  NSString *key = [self stringParamForName:@"key"] ?: @"phase3e.cache";
  NSString *value = [self stringParamForName:@"value"] ?: @"cache-ok";
  NSError *error = nil;
  BOOL stored = [cache setObject:value forKey:key ttlSeconds:30 error:&error];
  id cached = [cache objectForKey:key atTime:[NSDate date] error:NULL];
  return @{
    @"ok" : @(stored && cached != nil),
    @"adapter" : [cache adapterName] ?: @"",
    @"key" : key ?: @"",
    @"value" : cached ?: @"",
    @"error" : error.localizedDescription ?: @"",
  };
}

- (id)jobsProbe:(ALNContext *)ctx {
  (void)ctx;
  id<ALNJobAdapter> jobs = [self jobsAdapter];
  if (jobs == nil) {
    return @{
      @"ok" : @(NO),
      @"error" : @"jobs adapter unavailable",
    };
  }

  NSString *name = [self stringParamForName:@"name"] ?: @"boomhauer.jobs.demo";
  NSError *error = nil;
  NSString *jobID = [jobs enqueueJobNamed:name
                                  payload:@{
                                    @"source" : @"boomhauer",
                                  }
                                  options:@{
                                    @"maxAttempts" : @2,
                                  }
                                    error:&error];
  ALNJobEnvelope *leased = [jobs dequeueDueJobAt:[NSDate date] error:NULL];
  if (leased != nil) {
    (void)[jobs acknowledgeJobID:leased.jobID error:NULL];
  }

  return @{
    @"ok" : @([jobID length] > 0),
    @"adapter" : [jobs adapterName] ?: @"",
    @"enqueuedJobID" : jobID ?: @"",
    @"dequeuedJobID" : leased.jobID ?: @"",
    @"pending" : @([[jobs pendingJobsSnapshot] count]),
    @"error" : error.localizedDescription ?: @"",
  };
}

- (id)i18nProbe:(ALNContext *)ctx {
  (void)ctx;
  id<ALNLocalizationAdapter> localization = [self localizationAdapter];
  if (localization == nil) {
    return @{
      @"ok" : @(NO),
      @"error" : @"i18n adapter unavailable",
    };
  }

  NSString *locale = [self stringParamForName:@"locale"] ?: @"en";
  NSString *name = [self stringParamForName:@"name"] ?: @"Arlen";
  NSString *message = [self localizedStringForKey:@"phase3e.greeting"
                                           locale:locale
                                   fallbackLocale:nil
                                     defaultValue:@"Hello %{name}"
                                        arguments:@{
                                          @"name" : name ?: @"Arlen",
                                        }];
  return @{
    @"ok" : @([message length] > 0),
    @"adapter" : [localization adapterName] ?: @"",
    @"locale" : locale ?: @"",
    @"message" : message ?: @"",
  };
}

- (id)mailProbe:(ALNContext *)ctx {
  (void)ctx;
  id<ALNMailAdapter> mail = [self mailAdapter];
  if (mail == nil) {
    return @{
      @"ok" : @(NO),
      @"error" : @"mail adapter unavailable",
    };
  }

  ALNMailMessage *message = [[ALNMailMessage alloc] initWithFrom:@"noreply@arlen.dev"
                                                               to:@[ @"ops@arlen.dev" ]
                                                               cc:nil
                                                              bcc:nil
                                                          subject:@"Phase3E mail probe"
                                                         textBody:@"boomhauer mail probe"
                                                         htmlBody:nil
                                                          headers:@{
                                                            @"X-Arlen-Server" : @"boomhauer",
                                                          }
                                                         metadata:@{
                                                           @"route" : @"services_mail",
                                                         }];
  NSError *error = nil;
  NSString *deliveryID = [mail deliverMessage:message error:&error];
  NSArray *deliveries = [mail deliveriesSnapshot];
  return @{
    @"ok" : @([deliveryID length] > 0),
    @"adapter" : [mail adapterName] ?: @"",
    @"deliveryID" : deliveryID ?: @"",
    @"deliveries" : @([deliveries count]),
    @"error" : error.localizedDescription ?: @"",
  };
}

- (id)attachmentProbe:(ALNContext *)ctx {
  (void)ctx;
  id<ALNAttachmentAdapter> attachments = [self attachmentAdapter];
  if (attachments == nil) {
    return @{
      @"ok" : @(NO),
      @"error" : @"attachment adapter unavailable",
    };
  }

  NSString *content = [self stringParamForName:@"content"] ?: @"attachment-ok";
  NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  NSError *error = nil;
  NSString *attachmentID =
      [attachments saveAttachmentNamed:@"boomhauer-phase3e.txt"
                           contentType:@"text/plain"
                                  data:data
                              metadata:@{
                                @"route" : @"services_attachments",
                              }
                                 error:&error];
  NSDictionary *metadata = nil;
  NSData *readBack =
      [attachments attachmentDataForID:attachmentID ?: @"" metadata:&metadata error:NULL];
  NSString *readText = [[NSString alloc] initWithData:readBack ?: [NSData data]
                                             encoding:NSUTF8StringEncoding] ?: @"";
  return @{
    @"ok" : @([attachmentID length] > 0 && [readText isEqualToString:content]),
    @"adapter" : [attachments adapterName] ?: @"",
    @"attachmentID" : attachmentID ?: @"",
    @"content" : readText ?: @"",
    @"sizeBytes" : metadata[@"sizeBytes"] ?: @(0),
    @"error" : error.localizedDescription ?: @"",
  };
}

@end

static NSString *ReadTextFile(NSString *path) {
  if ([path length] == 0) {
    return @"";
  }
  NSError *error = nil;
  NSString *content = [NSString stringWithContentsOfFile:path
                                                encoding:NSUTF8StringEncoding
                                                   error:&error];
  if (content != nil) {
    return content;
  }

  NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
  if (data == nil) {
    return @"";
  }
  NSString *fallback = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  return fallback ?: @"";
}

static NSString *EscapeHTML(NSString *value) {
  NSString *safe = value ?: @"";
  safe = [safe stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
  safe = [safe stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
  safe = [safe stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
  safe = [safe stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
  return [safe stringByReplacingOccurrencesOfString:@"'" withString:@"&#39;"];
}

static NSDictionary *ParseMetadataFile(NSString *path) {
  NSString *content = ReadTextFile(path);
  if ([content length] == 0) {
    return @{};
  }

  NSMutableDictionary *out = [NSMutableDictionary dictionary];
  NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  for (NSString *line in lines) {
    NSRange equals = [line rangeOfString:@"="];
    if (equals.location == NSNotFound) {
      continue;
    }
    NSString *key = [[line substringToIndex:equals.location]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *value = [[line substringFromIndex:equals.location + 1]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([key length] == 0) {
      continue;
    }
    out[key] = value ?: @"";
  }
  return out;
}

static NSDictionary *ExtractPrimaryDiagnostic(NSString *output) {
  if ([output length] == 0) {
    return @{};
  }

  NSRegularExpression *regex =
      [NSRegularExpression regularExpressionWithPattern:@"^(.+?):([0-9]+):([0-9]+):\\s*(fatal error|error|warning):\\s*(.+)$"
                                                options:NSRegularExpressionAnchorsMatchLines
                                                  error:nil];
  NSArray *matches = [regex matchesInString:output
                                    options:0
                                      range:NSMakeRange(0, [output length])];
  if ([matches count] == 0) {
    return @{};
  }

  NSTextCheckingResult *best = nil;
  for (NSTextCheckingResult *candidate in matches) {
    if ([candidate numberOfRanges] < 6) {
      continue;
    }
    NSRange severityRange = [candidate rangeAtIndex:4];
    NSString *severity = [[output substringWithRange:severityRange] lowercaseString];
    if ([severity isEqualToString:@"warning"]) {
      if (best == nil) {
        best = candidate;
      }
      continue;
    }
    best = candidate;
    break;
  }

  if (best == nil || [best numberOfRanges] < 6) {
    return @{};
  }

  NSString *file = [output substringWithRange:[best rangeAtIndex:1]];
  NSString *line = [output substringWithRange:[best rangeAtIndex:2]];
  NSString *column = [output substringWithRange:[best rangeAtIndex:3]];
  NSString *severity = [output substringWithRange:[best rangeAtIndex:4]];
  NSString *message = [output substringWithRange:[best rangeAtIndex:5]];
  return @{
    @"file" : file ?: @"",
    @"line" : @([line integerValue]),
    @"column" : @([column integerValue]),
    @"severity" : severity ?: @"",
    @"message" : message ?: @"",
  };
}

static NSString *SourceSnippetForDiagnostic(NSDictionary *diagnostic) {
  NSString *file = [diagnostic[@"file"] isKindOfClass:[NSString class]] ? diagnostic[@"file"] : nil;
  NSInteger line = [diagnostic[@"line"] respondsToSelector:@selector(integerValue)]
                       ? [diagnostic[@"line"] integerValue]
                       : 0;
  if ([file length] == 0 || line <= 0) {
    return @"";
  }

  NSString *content = ReadTextFile(file);
  if ([content length] == 0) {
    return @"";
  }

  NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  NSInteger idx = line - 1;
  if (idx < 0 || idx >= (NSInteger)[lines count]) {
    return @"";
  }

  NSInteger start = MAX(0, idx - 1);
  NSInteger end = MIN((NSInteger)[lines count] - 1, idx + 1);
  NSMutableString *snippet = [NSMutableString string];
  for (NSInteger current = start; current <= end; current++) {
    NSString *prefix = (current == idx) ? @">" : @" ";
    [snippet appendFormat:@"%@ %ld | %@\n", prefix, (long)(current + 1), lines[(NSUInteger)current]];
  }
  return snippet;
}

static NSArray *WarningLines(NSString *output) {
  if ([output length] == 0) {
    return @[];
  }
  NSMutableArray *warnings = [NSMutableArray array];
  NSArray *lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  for (NSString *line in lines) {
    if ([[line lowercaseString] containsString:@"warning:"]) {
      [warnings addObject:line];
    }
  }
  return warnings;
}

static NSDictionary *BuildFailurePayload(NSString *requestID) {
  NSString *metaFile = EnvString("ARLEN_BOOMHAUER_BUILD_ERROR_META_FILE");
  NSString *outputFile = EnvString("ARLEN_BOOMHAUER_BUILD_ERROR_FILE");

  NSDictionary *meta = ParseMetadataFile(metaFile);
  NSString *stage = [meta[@"stage"] isKindOfClass:[NSString class]] ? meta[@"stage"] : @"compile";
  NSString *command = [meta[@"command"] isKindOfClass:[NSString class]] ? meta[@"command"] : @"";
  NSInteger exitCode = [meta[@"exit_code"] respondsToSelector:@selector(integerValue)]
                           ? [meta[@"exit_code"] integerValue]
                           : 1;

  NSString *output = ReadTextFile(outputFile);
  NSDictionary *diagnostic = ExtractPrimaryDiagnostic(output);
  NSString *snippet = SourceSnippetForDiagnostic(diagnostic);
  NSArray *warnings = WarningLines(output);

  NSMutableDictionary *details = [NSMutableDictionary dictionary];
  details[@"stage"] = stage ?: @"compile";
  details[@"command"] = command ?: @"";
  details[@"exit_code"] = @(exitCode);
  if ([diagnostic count] > 0) {
    [details addEntriesFromDictionary:diagnostic];
  }
  if ([snippet length] > 0) {
    details[@"snippet"] = snippet;
  }
  if ([warnings count] > 0) {
    details[@"warnings"] = warnings;
  }
  if ([output length] > 0) {
    NSUInteger limit = MIN((NSUInteger)16000, [output length]);
    details[@"output"] = [output substringToIndex:limit];
  }

  return @{
    @"error" : @{
      @"code" : @"dev_build_failed",
      @"message" : @"Build failed while reloading app",
      @"request_id" : requestID ?: @"",
      @"correlation_id" : requestID ?: @"",
    },
    @"details" : details
  };
}

static BOOL RequestPrefersJSON(ALNRequest *request) {
  NSString *accept = [request.headers[@"accept"] isKindOfClass:[NSString class]]
                         ? [request.headers[@"accept"] lowercaseString]
                         : @"";
  if ([accept containsString:@"application/json"] || [accept containsString:@"text/json"]) {
    return YES;
  }
  NSString *path = request.path ?: @"";
  if ([path hasPrefix:@"/api/"] || [path isEqualToString:@"/api"] ||
      [path hasPrefix:@"/api/dev/"]) {
    return YES;
  }
  return NO;
}

static NSString *BuildFailureHTML(NSDictionary *payload) {
  NSDictionary *error = [payload[@"error"] isKindOfClass:[NSDictionary class]] ? payload[@"error"] : @{};
  NSDictionary *details = [payload[@"details"] isKindOfClass:[NSDictionary class]] ? payload[@"details"] : @{};
  NSString *requestID = [error[@"request_id"] isKindOfClass:[NSString class]] ? error[@"request_id"] : @"";
  NSString *message = [error[@"message"] isKindOfClass:[NSString class]] ? error[@"message"] : @"Build failed";

  NSMutableString *html = [NSMutableString string];
  [html appendString:@"<!doctype html><html><head><meta charset='utf-8'>"];
  [html appendString:@"<title>Boomhauer Build Error</title>"];
  [html appendString:@"<style>body{font-family:Menlo,Consolas,monospace;background:#111;color:#eee;padding:24px;}h1{margin-top:0;}pre{background:#1b1b1b;border:1px solid #333;padding:12px;overflow:auto;}code{background:#1b1b1b;padding:2px 4px;}table{border-collapse:collapse;width:100%;}td{border:1px solid #333;padding:6px;vertical-align:top;}details{margin-top:12px;}</style>"];
  [html appendString:@"</head><body>"];
  [html appendString:@"<h1>Boomhauer Build Failed</h1>"];
  [html appendFormat:@"<p>%@</p>", EscapeHTML(message)];
  [html appendFormat:@"<p><strong>Request ID:</strong> <code>%@</code></p>", EscapeHTML(requestID)];
  [html appendString:@"<table>"];

  NSArray *orderedKeys = @[ @"stage", @"command", @"exit_code", @"file", @"line", @"column", @"message" ];
  for (NSString *key in orderedKeys) {
    id value = details[key];
    if (value == nil) {
      continue;
    }
    NSString *rendered = [value description] ?: @"";
    [html appendFormat:@"<tr><td><strong>%@</strong></td><td><pre>%@</pre></td></tr>",
                       EscapeHTML(key), EscapeHTML(rendered)];
  }

  NSString *snippet = [details[@"snippet"] isKindOfClass:[NSString class]] ? details[@"snippet"] : @"";
  if ([snippet length] > 0) {
    [html appendFormat:@"<tr><td><strong>snippet</strong></td><td><pre>%@</pre></td></tr>",
                       EscapeHTML(snippet)];
  }

  NSString *output = [details[@"output"] isKindOfClass:[NSString class]] ? details[@"output"] : @"";
  if ([output length] > 0) {
    [html appendFormat:@"<tr><td><strong>output</strong></td><td><pre>%@</pre></td></tr>",
                       EscapeHTML(output)];
  }
  [html appendString:@"</table>"];

  NSArray *warnings = [details[@"warnings"] isKindOfClass:[NSArray class]] ? details[@"warnings"] : @[];
  if ([warnings count] > 0) {
    NSString *warningText = [warnings componentsJoinedByString:@"\n"];
    [html appendFormat:@"<details><summary>Warnings (%lu)</summary><pre>%@</pre></details>",
                       (unsigned long)[warnings count],
                       EscapeHTML(warningText)];
  }

  [html appendString:@"</body></html>"];
  return html;
}

@interface BuildErrorController : ALNController
@end

@implementation BuildErrorController

- (id)health:(ALNContext *)ctx {
  (void)ctx;
  [self setStatus:200];
  [self renderText:@"degraded\n"];
  return nil;
}

- (id)json:(ALNContext *)ctx {
  NSString *requestID = [ctx.stash[@"request_id"] isKindOfClass:[NSString class]]
                            ? ctx.stash[@"request_id"]
                            : @"";
  NSDictionary *payload = BuildFailurePayload(requestID);
  NSError *error = nil;
  if (![self renderJSON:payload error:&error]) {
    [self setStatus:500];
    [self renderText:[NSString stringWithFormat:@"render failed: %@", error.localizedDescription ?: @"unknown"]];
    return nil;
  }
  [self setStatus:500];
  return nil;
}

- (id)show:(ALNContext *)ctx {
  NSString *requestID = [ctx.stash[@"request_id"] isKindOfClass:[NSString class]]
                            ? ctx.stash[@"request_id"]
                            : @"";
  NSDictionary *payload = BuildFailurePayload(requestID);

  if (RequestPrefersJSON(ctx.request)) {
    return [self json:ctx];
  }

  NSString *html = BuildFailureHTML(payload);
  [self setStatus:500];
  [ctx.response setHeader:@"Content-Type" value:@"text/html; charset=utf-8"];
  [ctx.response setTextBody:html ?: @"Build failed\n"];
  ctx.response.committed = YES;
  return nil;
}

@end

static ALNApplication *BuildApplication(NSString *environment) {
  NSError *error = nil;
  ALNApplication *app = [[ALNApplication alloc] initWithEnvironment:environment
                                                         configRoot:[[NSFileManager defaultManager]
                                                                       currentDirectoryPath]
                                                              error:&error];
  if (app == nil) {
    fprintf(stderr, "boomhauer: failed loading config: %s\n", [[error localizedDescription] UTF8String]);
    return nil;
  }

  (void)[app.localizationAdapter registerTranslations:@{
    @"phase3e.greeting" : @"Hello %{name}",
  }
                                                locale:@"en"
                                                 error:NULL];
  (void)[app.localizationAdapter registerTranslations:@{
    @"phase3e.greeting" : @"Hola %{name}",
  }
                                                locale:@"es"
                                                 error:NULL];

  [app registerRouteMethod:@"GET"
                      path:@"/"
                      name:@"home"
           controllerClass:[HomeController class]
                    action:@"index"];
  [app registerRouteMethod:@"GET"
                      path:@"/about"
                      name:@"about"
           controllerClass:[HomeController class]
                    action:@"about"];
  [app registerRouteMethod:@"GET"
                      path:@"/api/status"
                      name:@"api_status"
           controllerClass:[ApiController class]
                    action:@"status"];
  [app registerRouteMethod:@"GET"
                      path:@"/api/echo/:name"
                      name:@"api_echo"
           controllerClass:[ApiController class]
                    action:@"echo"];
  [app registerRouteMethod:@"GET"
                      path:@"/api/request-meta"
                      name:@"api_request_meta"
           controllerClass:[ApiController class]
                    action:@"requestMeta"];
  [app registerRouteMethod:@"GET"
                      path:@"/api/sleep"
                      name:@"api_sleep"
           controllerClass:[ApiController class]
                    action:@"sleep"];
  [app registerRouteMethod:@"GET"
                      path:@"/api/blob"
                      name:@"api_blob"
           controllerClass:[ApiController class]
                    action:@"blob"];
  [app registerRouteMethod:@"GET"
                      path:@"/api/db/items"
                      name:@"api_db_items_read"
           controllerClass:[ApiController class]
                    action:@"dbItemsRead"];
  [app registerRouteMethod:@"POST"
                      path:@"/api/db/items"
                      name:@"api_db_items_write"
           controllerClass:[ApiController class]
                    action:@"dbItemsWrite"];
  [app registerRouteMethod:@"GET"
                      path:@"/ws/echo"
                      name:@"ws_echo"
           controllerClass:[RealtimeController class]
                    action:@"wsEcho"];
  [app registerRouteMethod:@"GET"
                      path:@"/ws/channel/:channel"
                      name:@"ws_channel"
           controllerClass:[RealtimeController class]
                    action:@"wsChannel"];
  [app registerRouteMethod:@"GET"
                      path:@"/sse/ticker"
                      name:@"sse_ticker"
           controllerClass:[RealtimeController class]
                    action:@"sseTicker"];
  [app registerRouteMethod:@"GET"
                      path:@"/services/cache"
                      name:@"services_cache"
           controllerClass:[ServicesController class]
                    action:@"cacheProbe"];
  [app registerRouteMethod:@"GET"
                      path:@"/services/jobs"
                      name:@"services_jobs"
           controllerClass:[ServicesController class]
                    action:@"jobsProbe"];
  [app registerRouteMethod:@"GET"
                      path:@"/services/i18n"
                      name:@"services_i18n"
           controllerClass:[ServicesController class]
                    action:@"i18nProbe"];
  [app registerRouteMethod:@"GET"
                      path:@"/services/mail"
                      name:@"services_mail"
           controllerClass:[ServicesController class]
                    action:@"mailProbe"];
  [app registerRouteMethod:@"GET"
                      path:@"/services/attachments"
                      name:@"services_attachments"
           controllerClass:[ServicesController class]
                    action:@"attachmentProbe"];
  ALNApplication *embeddedApp = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : environment ?: @"development",
    @"logFormat" : @"text",
    @"performanceLogging" : @(YES),
    @"apiOnly" : @(NO),
    @"serveStatic" : @(NO),
    @"openapi" : @{
      @"enabled" : @(NO),
      @"docsUIEnabled" : @(NO),
    },
  }];
  [embeddedApp registerRouteMethod:@"GET"
                              path:@"/status"
                              name:@"embedded_status"
                   controllerClass:[EmbeddedController class]
                            action:@"status"];
  [embeddedApp registerRouteMethod:@"GET"
                              path:@"/api/status"
                              name:@"embedded_api_status"
                   controllerClass:[EmbeddedController class]
                            action:@"apiStatus"];
  (void)[app mountApplication:embeddedApp atPrefix:@"/embedded"];
  return app;
}

static ALNApplication *BuildBuildErrorApplication(void) {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"development",
    @"logFormat" : @"text",
    @"performanceLogging" : @(NO),
    @"serveStatic" : @(NO),
  }];

  [app registerRouteMethod:@"ANY"
                      path:@"/healthz"
                      name:@"dev_error_health"
           controllerClass:[BuildErrorController class]
                    action:@"health"];
  [app registerRouteMethod:@"ANY"
                      path:@"/api/dev/build-error"
                      name:@"dev_error_json"
           controllerClass:[BuildErrorController class]
                    action:@"json"];
  [app registerRouteMethod:@"ANY"
                      path:@"/*path"
                      name:@"dev_error_show"
           controllerClass:[BuildErrorController class]
                    action:@"show"];
  return app;
}

static void PrintUsage(void) {
  fprintf(stdout,
          "Usage: boomhauer [--port <port>] [--host <addr>] [--env <env>] [--once] [--print-routes]\n");
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

    BOOL buildErrorMode = ([EnvString("ARLEN_BOOMHAUER_BUILD_ERROR_FILE") length] > 0);
    ALNApplication *app = buildErrorMode ? BuildBuildErrorApplication() : BuildApplication(environment);
    if (app == nil) {
      return 1;
    }

    NSString *publicRoot = [[[NSFileManager defaultManager] currentDirectoryPath]
        stringByAppendingPathComponent:@"public"];
    ALNHTTPServer *server = [[ALNHTTPServer alloc] initWithApplication:app publicRoot:publicRoot];
    server.serverName = @"boomhauer";

    if (printRoutes) {
      [server printRoutesToFile:stdout];
      return 0;
    }

    return [server runWithHost:host portOverride:portOverride once:once];
  }
}

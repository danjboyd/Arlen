#import "ALNGDL2Adapter.h"

#import "ALNPg.h"

@interface ALNGDL2Adapter ()

@property(nonatomic, strong, readwrite) ALNPg *fallbackAdapter;
@property(nonatomic, copy, readwrite) NSString *migrationMode;

@end

@implementation ALNGDL2Adapter

+ (NSDictionary<NSString *, id> *)capabilityMetadata {
  NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithDictionary:[ALNPg capabilityMetadata]];
  metadata[@"adapter"] = @"gdl2";
  metadata[@"dialect"] = @"compat_fallback_pg";
  metadata[@"compatibility_mode"] = @"fallback_pg";
  return [NSDictionary dictionaryWithDictionary:metadata];
}

- (NSDictionary<NSString *, id> *)capabilityMetadata {
  NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithDictionary:[[self class] capabilityMetadata]];
  metadata[@"migration_mode"] = self.migrationMode ?: @"compat_fallback_pg";
  metadata[@"supports_native_gdl2_runtime"] = @([[self class] isNativeGDL2RuntimeAvailable]);
  if (self.fallbackAdapter != nil) {
    metadata[@"fallback_adapter"] = [self.fallbackAdapter adapterName] ?: @"";
  }
  return [NSDictionary dictionaryWithDictionary:metadata];
}

- (instancetype)initWithConnectionString:(NSString *)connectionString
                           maxConnections:(NSUInteger)maxConnections
                                    error:(NSError **)error {
  NSError *pgError = nil;
  ALNPg *adapter = [[ALNPg alloc] initWithConnectionString:connectionString
                                             maxConnections:maxConnections
                                                      error:&pgError];
  if (adapter == nil) {
    if (error != NULL) {
      *error = pgError;
    }
    return nil;
  }
  return [self initWithFallbackAdapter:adapter];
}

- (instancetype)initWithFallbackAdapter:(ALNPg *)fallbackAdapter {
  self = [super init];
  if (self) {
    _fallbackAdapter = fallbackAdapter;
    _migrationMode = @"compat_fallback_pg";
  }
  return self;
}

+ (BOOL)isNativeGDL2RuntimeAvailable {
  return (NSClassFromString(@"EOEditingContext") != Nil);
}

- (NSString *)adapterName {
  return @"gdl2";
}

- (id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError **)error {
  return (id<ALNDatabaseConnection>)[self.fallbackAdapter acquireConnection:error];
}

- (void)releaseAdapterConnection:(id<ALNDatabaseConnection>)connection {
  if ([connection isKindOfClass:[ALNPgConnection class]]) {
    [self.fallbackAdapter releaseConnection:(ALNPgConnection *)connection];
  }
}

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  return [self.fallbackAdapter executeQuery:sql parameters:parameters error:error];
}

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError **)error {
  return [self.fallbackAdapter executeCommand:sql parameters:parameters error:error];
}

- (BOOL)withTransactionUsingBlock:(BOOL (^)(id<ALNDatabaseConnection> connection,
                                            NSError **error))block
                            error:(NSError **)error {
  return [self.fallbackAdapter withTransactionUsingBlock:block error:error];
}

@end

#ifndef ALN_POSTGRES_JOB_ADAPTER_H
#define ALN_POSTGRES_JOB_ADAPTER_H

#import "ALNServices.h"
#import "ALNPg.h"

NS_ASSUME_NONNULL_BEGIN

// PostgreSQL-backed queue. Schema installation is explicit; runtime operations never run DDL.
@interface ALNPostgresJobAdapter : NSObject <ALNDurableJobAdapter>
@property(nonatomic, strong, readonly) ALNPg *database;
@property(nonatomic, copy, readonly) NSString *namespaceName;
@property(nonatomic, assign, readonly) NSTimeInterval leaseDurationSeconds;
- (nullable instancetype)initWithDatabase:(ALNPg *)database
                               namespace:(NSString *)namespaceName
                    leaseDurationSeconds:(NSTimeInterval)leaseDurationSeconds
                                   error:(NSError *_Nullable *_Nullable)error;
+ (NSArray<NSString *> *)schemaStatements;
- (BOOL)installSchemaWithError:(NSError *_Nullable *_Nullable)error;
// The caller owns BEGIN/COMMIT/ROLLBACK on this connection to the same database.
- (nullable NSString *)enqueueJobNamed:(NSString *)name
                             payload:(nullable NSDictionary *)payload
                             options:(nullable NSDictionary *)options
                        onConnection:(id<ALNDatabaseConnection>)connection
                               error:(NSError *_Nullable *_Nullable)error;
- (nullable NSArray<ALNJobEnvelope *> *)jobsWithState:(NSString *)state
                                              error:(NSError *_Nullable *_Nullable)error;
- (NSArray *)leasedJobsSnapshot;
// Explicit destructive maintenance, scoped to this namespace. Never called by workers.
- (BOOL)resetWithError:(NSError *_Nullable *_Nullable)error;
@end

NS_ASSUME_NONNULL_END
#endif

#ifndef ALN_PG_H
#define ALN_PG_H

#import <Foundation/Foundation.h>
#import "ALNDatabaseAdapter.h"

NS_ASSUME_NONNULL_BEGIN

@class ALNSQLBuilder;

extern NSString *const ALNPgErrorDomain;
extern NSString *const ALNPgErrorDiagnosticsKey;
extern NSString *const ALNPgErrorSQLStateKey;
extern NSString *const ALNPgErrorServerDetailKey;
extern NSString *const ALNPgErrorServerHintKey;
extern NSString *const ALNPgErrorServerPositionKey;
extern NSString *const ALNPgErrorServerWhereKey;
extern NSString *const ALNPgErrorServerTableKey;
extern NSString *const ALNPgErrorServerColumnKey;
extern NSString *const ALNPgErrorServerConstraintKey;

extern NSString *const ALNPgQueryStageCompile;
extern NSString *const ALNPgQueryStageExecute;
extern NSString *const ALNPgQueryStageResult;
extern NSString *const ALNPgQueryStageError;

extern NSString *const ALNPgQueryEventStageKey;
extern NSString *const ALNPgQueryEventSourceKey;
extern NSString *const ALNPgQueryEventOperationKey;
extern NSString *const ALNPgQueryEventExecutionModeKey;
extern NSString *const ALNPgQueryEventCacheHitKey;
extern NSString *const ALNPgQueryEventCacheFullKey;
extern NSString *const ALNPgQueryEventSQLHashKey;
extern NSString *const ALNPgQueryEventSQLLengthKey;
extern NSString *const ALNPgQueryEventSQLTokenKey;
extern NSString *const ALNPgQueryEventParameterCountKey;
extern NSString *const ALNPgQueryEventPreparedStatementKey;
extern NSString *const ALNPgQueryEventDurationMSKey;
extern NSString *const ALNPgQueryEventRowCountKey;
extern NSString *const ALNPgQueryEventAffectedRowsKey;
extern NSString *const ALNPgQueryEventErrorDomainKey;
extern NSString *const ALNPgQueryEventErrorCodeKey;
extern NSString *const ALNPgQueryEventSQLKey;

// userInfo key (NSNumber YES) on an ALNPgErrorConnectionFailed error raised
// because the server closed the connection while a statement ran on it.
extern NSString *const ALNPgErrorConnectionLostKey;
// userInfo key (NSNumber YES), alongside ALNPgErrorConnectionLostKey, when the
// connection was found closed before the statement was sent, so it never ran.
extern NSString *const ALNPgErrorStatementNotSentKey;

typedef NS_ENUM(NSInteger, ALNPgErrorCode) {
  ALNPgErrorConnectionFailed = 1,
  ALNPgErrorQueryFailed = 2,
  ALNPgErrorPoolExhausted = 3,
  ALNPgErrorInvalidArgument = 4,
  ALNPgErrorTransactionFailed = 5,
};

typedef NS_ENUM(NSInteger, ALNPgPreparedStatementReusePolicy) {
  ALNPgPreparedStatementReusePolicyDisabled = 0,
  ALNPgPreparedStatementReusePolicyAuto = 1,
  ALNPgPreparedStatementReusePolicyAlways = 2,
};

/// What the pool resets when a connection is released, so one borrower's
/// session state never reaches the next. A connection released inside a
/// transaction is always closed, whatever the policy. A connection that only
/// ran SQL the pool generated itself (builder statements without trusted
/// expressions) is reused without a reset.
typedef NS_ENUM(NSInteger, ALNPgSessionResetPolicy) {
  /// Default. One round trip: `RESET ALL`, `SET SESSION AUTHORIZATION
  /// DEFAULT`, `CLOSE ALL`, `DISCARD TEMP`, `DISCARD SEQUENCES`, `UNLISTEN *`
  /// and `pg_advisory_unlock_all()`, plus a check of the pool's cached
  /// prepared statements against `pg_prepared_statements`; they are kept
  /// unless one was replaced, in which case all are deallocated.
  ALNPgSessionResetPolicySession = 0,
  /// `DISCARD ALL`, which also drops every prepared statement (the pool's
  /// statement cache is cleared to match).
  ALNPgSessionResetPolicyDiscardAll = 1,
  /// No reset (queued notifications are still dropped). Only for code that
  /// manages session state itself.
  ALNPgSessionResetPolicyNone = 2,
};

typedef void (^ALNPgQueryDiagnosticsListener)(NSDictionary<NSString *, id> *event);

@interface ALNPgConnection : NSObject <ALNDatabaseConnection>

@property(nonatomic, copy, readonly) NSString *connectionString;
@property(nonatomic, assign, readonly, getter=isOpen) BOOL open;
@property(nonatomic, assign) ALNPgPreparedStatementReusePolicy preparedStatementReusePolicy;
@property(nonatomic, assign) NSUInteger preparedStatementCacheLimit;
@property(nonatomic, assign) NSUInteger builderCompilationCacheLimit;
@property(nonatomic, assign) BOOL includeSQLInDiagnosticsEvents;
@property(nonatomic, assign) BOOL emitDiagnosticsEventsToStderr;
@property(nonatomic, copy, nullable) ALNPgQueryDiagnosticsListener queryDiagnosticsListener;

- (nullable instancetype)initWithConnectionString:(NSString *)connectionString
                                            error:(NSError *_Nullable *_Nullable)error;

- (void)close;

// Returns PostgreSQL notifications for channels this connection has LISTENed on
// (@{ channel, payload, pid }), waiting up to `timeout` seconds when none are
// queued. An empty array means the timeout passed; nil means the connection
// failed and should be reopened. Use a dedicated connection, not a pooled one.
- (nullable NSArray<NSDictionary *> *)waitForNotificationsWithTimeout:(NSTimeInterval)timeout
                                                                error:(NSError *_Nullable *_Nullable)error;

- (BOOL)prepareStatementNamed:(NSString *)name
                          sql:(NSString *)sql
               parameterCount:(NSInteger)parameterCount
                        error:(NSError *_Nullable *_Nullable)error;

- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                                         parameters:(NSArray *)parameters
                                              error:(NSError *_Nullable *_Nullable)error;
- (nullable ALNDatabaseResult *)executeQueryResult:(NSString *)sql
                                        parameters:(NSArray *)parameters
                                             error:(NSError *_Nullable *_Nullable)error;

- (nullable NSDictionary *)executeQueryOne:(NSString *)sql
                                parameters:(NSArray *)parameters
                                     error:(NSError *_Nullable *_Nullable)error;

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError *_Nullable *_Nullable)error;
- (NSInteger)executeCommandBatch:(NSString *)sql
                   parameterSets:(NSArray<NSArray *> *)parameterSets
                           error:(NSError *_Nullable *_Nullable)error;

- (nullable NSArray<NSDictionary *> *)executePreparedQueryNamed:(NSString *)name
                                                     parameters:(NSArray *)parameters
                                                          error:(NSError *_Nullable *_Nullable)error;

- (NSInteger)executePreparedCommandNamed:(NSString *)name
                              parameters:(NSArray *)parameters
                                   error:(NSError *_Nullable *_Nullable)error;

- (BOOL)beginTransaction:(NSError *_Nullable *_Nullable)error;
- (BOOL)commitTransaction:(NSError *_Nullable *_Nullable)error;
- (BOOL)rollbackTransaction:(NSError *_Nullable *_Nullable)error;
- (BOOL)createSavepointNamed:(NSString *)name error:(NSError *_Nullable *_Nullable)error;
- (BOOL)rollbackToSavepointNamed:(NSString *)name error:(NSError *_Nullable *_Nullable)error;
- (BOOL)releaseSavepointNamed:(NSString *)name error:(NSError *_Nullable *_Nullable)error;
- (BOOL)withSavepointNamed:(NSString *)name
                usingBlock:(BOOL (^)(NSError *_Nullable *_Nullable error))block
                     error:(NSError *_Nullable *_Nullable)error;

- (nullable NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder
                                                     error:(NSError *_Nullable *_Nullable)error;
- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder
                              error:(NSError *_Nullable *_Nullable)error;
- (void)resetExecutionCaches;

@end

@interface ALNPg : NSObject <ALNDatabaseAdapter>

@property(nonatomic, copy, readonly) NSString *connectionString;
@property(nonatomic, assign, readonly) NSUInteger maxConnections;
@property(nonatomic, assign) ALNPgPreparedStatementReusePolicy preparedStatementReusePolicy;
@property(nonatomic, assign) NSUInteger preparedStatementCacheLimit;
@property(nonatomic, assign) NSUInteger builderCompilationCacheLimit;
@property(nonatomic, assign) BOOL connectionLivenessChecksEnabled;
/// With `connectionLivenessChecksEnabled`, only a pooled connection that has
/// been idle for at least this many seconds runs the `SELECT 1` probe before
/// it is reused. Default `30`. `0` or less probes on every reuse. Every reused
/// connection still gets the free libpq status check.
@property(nonatomic, assign) NSTimeInterval connectionLivenessCheckIdleThreshold;
@property(nonatomic, assign) BOOL includeSQLInDiagnosticsEvents;
@property(nonatomic, assign) BOOL emitDiagnosticsEventsToStderr;
@property(nonatomic, copy, nullable) ALNPgQueryDiagnosticsListener queryDiagnosticsListener;
/// Seconds `acquireConnection:` waits for a connection to be released when all
/// `maxConnections` are checked out. `0` (the default) fails immediately with
/// `ALNPgErrorPoolExhausted`; a positive value fails with the same error once
/// the wait runs out.
@property(nonatomic, assign) NSTimeInterval acquireTimeout;
/// Session state reset applied when a connection goes back to the pool.
/// Default `ALNPgSessionResetPolicySession`.
@property(nonatomic, assign) ALNPgSessionResetPolicy sessionResetPolicy;

+ (NSDictionary<NSString *, id> *)capabilityMetadata;

- (nullable instancetype)initWithConnectionString:(NSString *)connectionString
                                    maxConnections:(NSUInteger)maxConnections
                                             error:(NSError *_Nullable *_Nullable)error;

- (nullable ALNPgConnection *)acquireConnection:(NSError *_Nullable *_Nullable)error;
/// Returns a connection to the pool. A connection still inside a transaction
/// (begun with `-beginTransaction:` or by sending `BEGIN`) is closed rather
/// than re-pooled; otherwise its session state is reset per
/// `sessionResetPolicy`, and it is closed if the reset fails.
- (void)releaseConnection:(ALNPgConnection *)connection;
/// Pool occupancy and wait counters: `max_connections`, `in_use_connections`,
/// `idle_connections`, `acquire_timeout_seconds`, `acquire_wait_count`,
/// `acquire_wait_seconds_total`, `pool_exhausted_count`,
/// `connection_retry_count` (statements retried after a pooled connection
/// turned out to have been closed by the server),
/// `released_in_transaction_count` (connections closed because they were
/// released inside a transaction), `session_reset_count` (releases that ran
/// the reset round trip), and `session_reset_failure_count`.
- (NSDictionary<NSString *, id> *)poolDiagnostics;

- (nullable id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError *_Nullable *_Nullable)error;
- (void)releaseAdapterConnection:(id<ALNDatabaseConnection>)connection;

- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                                         parameters:(NSArray *)parameters
                                              error:(NSError *_Nullable *_Nullable)error;
- (nullable ALNDatabaseResult *)executeQueryResult:(NSString *)sql
                                        parameters:(NSArray *)parameters
                                             error:(NSError *_Nullable *_Nullable)error;
- (nullable NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder
                                                     error:(NSError *_Nullable *_Nullable)error;

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError *_Nullable *_Nullable)error;
- (NSInteger)executeCommandBatch:(NSString *)sql
                   parameterSets:(NSArray<NSArray *> *)parameterSets
                           error:(NSError *_Nullable *_Nullable)error;
- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder
                              error:(NSError *_Nullable *_Nullable)error;

// Runs `block` in a transaction on one pooled connection. If BEGIN fails
// because the server had closed an idle connection, it restarts once on a new
// connection (nothing has run yet). If the connection is lost inside the block
// or at COMMIT, the server rolled back what ran and the connection-lost error
// (ALNPgErrorConnectionLostKey) is returned; the block is not run again.
- (BOOL)withTransaction:(BOOL (^)(ALNPgConnection *connection,
                                  NSError *_Nullable *_Nullable error))block
                  error:(NSError *_Nullable *_Nullable)error;
// Like withTransaction:, but when the connection is lost inside the block or
// at COMMIT, runs the whole block again from BEGIN on a new connection, once.
// Use it only for blocks that are safe to run twice (idempotent or guarded by
// compare-and-set), since a lost connection at COMMIT may follow a commit.
- (BOOL)withTransactionReplayingOnConnectionLoss:(BOOL (^)(ALNPgConnection *connection,
                                                           NSError *_Nullable *_Nullable error))block
                                           error:(NSError *_Nullable *_Nullable)error;
- (BOOL)withTransactionUsingBlock:
            (BOOL (^)(id<ALNDatabaseConnection> connection,
                      NSError *_Nullable *_Nullable error))block
                            error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif

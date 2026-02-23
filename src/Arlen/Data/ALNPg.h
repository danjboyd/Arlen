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

- (BOOL)prepareStatementNamed:(NSString *)name
                          sql:(NSString *)sql
               parameterCount:(NSInteger)parameterCount
                        error:(NSError *_Nullable *_Nullable)error;

- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                                         parameters:(NSArray *)parameters
                                              error:(NSError *_Nullable *_Nullable)error;

- (nullable NSDictionary *)executeQueryOne:(NSString *)sql
                                parameters:(NSArray *)parameters
                                     error:(NSError *_Nullable *_Nullable)error;

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
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
@property(nonatomic, assign) BOOL includeSQLInDiagnosticsEvents;
@property(nonatomic, assign) BOOL emitDiagnosticsEventsToStderr;
@property(nonatomic, copy, nullable) ALNPgQueryDiagnosticsListener queryDiagnosticsListener;

+ (NSDictionary<NSString *, id> *)capabilityMetadata;

- (nullable instancetype)initWithConnectionString:(NSString *)connectionString
                                    maxConnections:(NSUInteger)maxConnections
                                             error:(NSError *_Nullable *_Nullable)error;

- (nullable ALNPgConnection *)acquireConnection:(NSError *_Nullable *_Nullable)error;
- (void)releaseConnection:(ALNPgConnection *)connection;

- (nullable id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError *_Nullable *_Nullable)error;
- (void)releaseAdapterConnection:(id<ALNDatabaseConnection>)connection;

- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                                         parameters:(NSArray *)parameters
                                              error:(NSError *_Nullable *_Nullable)error;
- (nullable NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder
                                                     error:(NSError *_Nullable *_Nullable)error;

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError *_Nullable *_Nullable)error;
- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder
                              error:(NSError *_Nullable *_Nullable)error;

- (BOOL)withTransaction:(BOOL (^)(ALNPgConnection *connection,
                                  NSError *_Nullable *_Nullable error))block
                  error:(NSError *_Nullable *_Nullable)error;
- (BOOL)withTransactionUsingBlock:
            (BOOL (^)(id<ALNDatabaseConnection> connection,
                      NSError *_Nullable *_Nullable error))block
                            error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif

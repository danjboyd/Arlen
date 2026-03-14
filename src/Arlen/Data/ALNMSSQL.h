#ifndef ALN_MSSQL_H
#define ALN_MSSQL_H

#import <Foundation/Foundation.h>

#import "ALNDatabaseAdapter.h"

NS_ASSUME_NONNULL_BEGIN

@class ALNSQLBuilder;

extern NSString *const ALNMSSQLErrorDomain;
extern NSString *const ALNMSSQLErrorDiagnosticsKey;
extern NSString *const ALNMSSQLErrorSQLStateKey;
extern NSString *const ALNMSSQLErrorNativeCodeKey;

typedef NS_ENUM(NSInteger, ALNMSSQLErrorCode) {
  ALNMSSQLErrorConnectionFailed = 1,
  ALNMSSQLErrorQueryFailed = 2,
  ALNMSSQLErrorPoolExhausted = 3,
  ALNMSSQLErrorInvalidArgument = 4,
  ALNMSSQLErrorTransactionFailed = 5,
  ALNMSSQLErrorTransportUnavailable = 6,
};

@interface ALNMSSQLConnection : NSObject <ALNDatabaseConnection>

@property(nonatomic, copy, readonly) NSString *connectionString;
@property(nonatomic, assign, readonly, getter=isOpen) BOOL open;

- (nullable instancetype)initWithConnectionString:(NSString *)connectionString
                                            error:(NSError *_Nullable *_Nullable)error;

- (void)close;
- (BOOL)beginTransaction:(NSError *_Nullable *_Nullable)error;
- (BOOL)commitTransaction:(NSError *_Nullable *_Nullable)error;
- (BOOL)rollbackTransaction:(NSError *_Nullable *_Nullable)error;
- (nullable NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder
                                                    error:(NSError *_Nullable *_Nullable)error;
- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder
                             error:(NSError *_Nullable *_Nullable)error;

@end

@interface ALNMSSQL : NSObject <ALNDatabaseAdapter>

@property(nonatomic, copy, readonly) NSString *connectionString;
@property(nonatomic, assign, readonly) NSUInteger maxConnections;

+ (NSDictionary<NSString *, id> *)capabilityMetadata;

- (nullable instancetype)initWithConnectionString:(NSString *)connectionString
                                    maxConnections:(NSUInteger)maxConnections
                                             error:(NSError *_Nullable *_Nullable)error;

- (nullable ALNMSSQLConnection *)acquireConnection:(NSError *_Nullable *_Nullable)error;
- (void)releaseConnection:(ALNMSSQLConnection *)connection;

- (nullable NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder
                                                    error:(NSError *_Nullable *_Nullable)error;
- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder
                             error:(NSError *_Nullable *_Nullable)error;
- (BOOL)withTransaction:(BOOL (^)(ALNMSSQLConnection *connection,
                                  NSError *_Nullable *_Nullable error))block
                  error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif

#ifndef ALN_DATABASE_ADAPTER_H
#define ALN_DATABASE_ADAPTER_H

#import <Foundation/Foundation.h>

#import "ALNSQLDialect.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNDatabaseAdapterErrorDomain;

typedef NS_ENUM(NSInteger, ALNDatabaseAdapterErrorCode) {
  ALNDatabaseAdapterErrorInvalidArgument = 1,
  ALNDatabaseAdapterErrorUnsupported = 2,
  ALNDatabaseAdapterErrorConformanceFailed = 3,
  ALNDatabaseAdapterErrorInvalidResult = 4,
};

@interface ALNDatabaseJSONValue : NSObject

@property(nonatomic, strong, readonly) id object;

+ (instancetype)valueWithObject:(nullable id)object;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithObject:(nullable id)object NS_DESIGNATED_INITIALIZER;

@end

@interface ALNDatabaseArrayValue : NSObject

@property(nonatomic, copy, readonly) NSArray *items;

+ (instancetype)valueWithItems:(nullable NSArray *)items;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithItems:(nullable NSArray *)items NS_DESIGNATED_INITIALIZER;

@end

@protocol ALNDatabaseConnection <NSObject>

- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                                        parameters:(NSArray *)parameters
                                             error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)executeQueryOne:(NSString *)sql
                                parameters:(NSArray *)parameters
                                     error:(NSError *_Nullable *_Nullable)error;
- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError *_Nullable *_Nullable)error;

@end

@protocol ALNDatabaseAdapter <NSObject>

- (NSString *)adapterName;
- (nullable id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError *_Nullable *_Nullable)error;
- (void)releaseAdapterConnection:(id<ALNDatabaseConnection>)connection;

- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                                        parameters:(NSArray *)parameters
                                             error:(NSError *_Nullable *_Nullable)error;
- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError *_Nullable *_Nullable)error;

- (BOOL)withTransactionUsingBlock:
            (BOOL (^)(id<ALNDatabaseConnection> connection,
                      NSError *_Nullable *_Nullable error))block
                            error:(NSError *_Nullable *_Nullable)error;

@optional

- (nullable id<ALNSQLDialect>)sqlDialect;
- (NSDictionary<NSString *, id> *)capabilityMetadata;

@end

FOUNDATION_EXPORT NSError *ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorCode code,
                                                       NSString *message,
                                                       NSDictionary *_Nullable userInfo);
FOUNDATION_EXPORT BOOL ALNDatabaseErrorIsConnectivityFailure(NSError *_Nullable error);
FOUNDATION_EXPORT ALNDatabaseJSONValue *ALNDatabaseJSONParameter(id _Nullable object);
FOUNDATION_EXPORT ALNDatabaseArrayValue *ALNDatabaseArrayParameter(NSArray *_Nullable items);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *_Nullable ALNDatabaseFirstRow(
    NSArray<NSDictionary *> *_Nullable rows);
FOUNDATION_EXPORT id _Nullable ALNDatabaseScalarValueFromRow(
    NSDictionary<NSString *, id> *_Nullable row,
    NSString *_Nullable columnName,
    NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT id _Nullable ALNDatabaseScalarValueFromRows(
    NSArray<NSDictionary *> *_Nullable rows,
    NSString *_Nullable columnName,
    NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT id _Nullable ALNDatabaseExecuteScalarQuery(id<ALNDatabaseConnection> connection,
                                                             NSString *sql,
                                                             NSArray *_Nullable parameters,
                                                             NSString *_Nullable columnName,
                                                             NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END

#endif

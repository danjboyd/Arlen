#ifndef ALN_DATABASE_ADAPTER_H
#define ALN_DATABASE_ADAPTER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNDatabaseAdapterErrorDomain;

typedef NS_ENUM(NSInteger, ALNDatabaseAdapterErrorCode) {
  ALNDatabaseAdapterErrorInvalidArgument = 1,
  ALNDatabaseAdapterErrorUnsupported = 2,
  ALNDatabaseAdapterErrorConformanceFailed = 3,
};

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

@end

FOUNDATION_EXPORT NSError *ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorCode code,
                                                       NSString *message,
                                                       NSDictionary *_Nullable userInfo);

NS_ASSUME_NONNULL_END

#endif

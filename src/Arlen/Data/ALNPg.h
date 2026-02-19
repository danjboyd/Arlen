#ifndef ALN_PG_H
#define ALN_PG_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNPgErrorDomain;

typedef NS_ENUM(NSInteger, ALNPgErrorCode) {
  ALNPgErrorConnectionFailed = 1,
  ALNPgErrorQueryFailed = 2,
  ALNPgErrorPoolExhausted = 3,
  ALNPgErrorInvalidArgument = 4,
  ALNPgErrorTransactionFailed = 5,
};

@interface ALNPgConnection : NSObject

@property(nonatomic, copy, readonly) NSString *connectionString;
@property(nonatomic, assign, readonly, getter=isOpen) BOOL open;

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

@end

@interface ALNPg : NSObject

@property(nonatomic, copy, readonly) NSString *connectionString;
@property(nonatomic, assign, readonly) NSUInteger maxConnections;

- (nullable instancetype)initWithConnectionString:(NSString *)connectionString
                                    maxConnections:(NSUInteger)maxConnections
                                             error:(NSError *_Nullable *_Nullable)error;

- (nullable ALNPgConnection *)acquireConnection:(NSError *_Nullable *_Nullable)error;
- (void)releaseConnection:(ALNPgConnection *)connection;

- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                                         parameters:(NSArray *)parameters
                                              error:(NSError *_Nullable *_Nullable)error;

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError *_Nullable *_Nullable)error;

- (BOOL)withTransaction:(BOOL (^)(ALNPgConnection *connection,
                                  NSError *_Nullable *_Nullable error))block
                  error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif

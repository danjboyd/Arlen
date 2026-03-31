#ifndef ALN_DATAVERSE_TEST_SUPPORT_H
#define ALN_DATAVERSE_TEST_SUPPORT_H

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNDataverseClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNFakeDataverseTransport : NSObject <ALNDataverseTransport>

@property(nonatomic, strong, readonly) NSMutableArray *queuedResults;
@property(nonatomic, strong, readonly) NSMutableArray<ALNDataverseRequest *> *capturedRequests;

- (void)enqueueResponse:(nullable ALNDataverseResponse *)response;
- (void)enqueueError:(nullable NSError *)error;

@end

@interface ALNFakeDataverseTokenProvider : NSObject <ALNDataverseTokenProvider>

@property(nonatomic, copy) NSString *token;
@property(nonatomic, assign) NSUInteger requestCount;
@property(nonatomic, strong, nullable) NSError *queuedError;

@end

@interface ALNDataverseTestCase : XCTestCase

- (ALNDataverseTarget *)targetWithError:(NSError *_Nullable *_Nullable)error;
- (ALNDataverseTarget *)targetNamed:(nullable NSString *)targetName
                         maxRetries:(NSUInteger)maxRetries
                           pageSize:(NSUInteger)pageSize
                              error:(NSError *_Nullable *_Nullable)error;
- (ALNDataverseClient *)clientWithTransport:(nullable id<ALNDataverseTransport>)transport
                              tokenProvider:(nullable id<ALNDataverseTokenProvider>)tokenProvider
                                 targetName:(nullable NSString *)targetName
                                 maxRetries:(NSUInteger)maxRetries
                                   pageSize:(NSUInteger)pageSize
                                      error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)applicationConfig;
- (nullable NSString *)environmentValueForName:(NSString *)name;
- (void)setEnvironmentValue:(nullable NSString *)value forName:(NSString *)name;
- (NSDictionary<NSString *, NSString *> *)snapshotEnvironmentForNames:(NSArray<NSString *> *)names;
- (void)restoreEnvironmentSnapshot:(NSDictionary<NSString *, NSString *> *)snapshot
                             names:(NSArray<NSString *> *)names;
- (ALNDataverseResponse *)responseWithStatus:(NSInteger)status
                                     headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                                  JSONObject:(nullable id)object;
- (nullable NSDictionary *)JSONObjectFromRequestBody:(ALNDataverseRequest *)request;

@end

NS_ASSUME_NONNULL_END

#endif

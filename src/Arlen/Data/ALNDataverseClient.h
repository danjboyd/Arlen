#ifndef ALN_DATAVERSE_CLIENT_H
#define ALN_DATAVERSE_CLIENT_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ALNDataverseQuery;
@class ALNDataverseRequest;
@class ALNDataverseResponse;
@class ALNDataverseRecord;
@class ALNDataverseEntityPage;
@class ALNDataverseBatchRequest;
@class ALNDataverseBatchResponse;

extern NSString *const ALNDataverseErrorDomain;
extern NSString *const ALNDataverseErrorDiagnosticsKey;
extern NSString *const ALNDataverseErrorHTTPStatusKey;
extern NSString *const ALNDataverseErrorRequestURLKey;
extern NSString *const ALNDataverseErrorRequestMethodKey;
extern NSString *const ALNDataverseErrorRequestHeadersKey;
extern NSString *const ALNDataverseErrorResponseHeadersKey;
extern NSString *const ALNDataverseErrorResponseBodyKey;
extern NSString *const ALNDataverseErrorRetryAfterKey;
extern NSString *const ALNDataverseErrorCorrelationIDKey;
extern NSString *const ALNDataverseErrorTargetNameKey;

typedef NS_ENUM(NSInteger, ALNDataverseErrorCode) {
  ALNDataverseErrorInvalidArgument = 1,
  ALNDataverseErrorInvalidConfiguration = 2,
  ALNDataverseErrorAuthenticationFailed = 3,
  ALNDataverseErrorTransportFailed = 4,
  ALNDataverseErrorRequestFailed = 5,
  ALNDataverseErrorThrottled = 6,
  ALNDataverseErrorInvalidResponse = 7,
  ALNDataverseErrorUnsupportedOperation = 8,
};

@interface ALNDataverseTarget : NSObject <NSCopying>

@property(nonatomic, copy, readonly) NSString *serviceRootURLString;
@property(nonatomic, copy, readonly) NSString *environmentURLString;
@property(nonatomic, copy, readonly) NSString *tenantID;
@property(nonatomic, copy, readonly) NSString *clientID;
@property(nonatomic, copy, readonly) NSString *clientSecret;
@property(nonatomic, copy, readonly) NSString *targetName;
@property(nonatomic, assign, readonly) NSTimeInterval timeoutInterval;
@property(nonatomic, assign, readonly) NSUInteger maxRetries;
@property(nonatomic, assign, readonly) NSUInteger pageSize;

+ (nullable NSString *)normalizedEnvironmentURLStringFromServiceRootURLString:
    (NSString *)serviceRootURLString;
+ (NSArray<NSString *> *)configuredTargetNamesFromConfig:(nullable NSDictionary *)config;
+ (nullable NSDictionary<NSString *, id> *)configurationNamed:(nullable NSString *)targetName
                                                   fromConfig:(nullable NSDictionary *)config;
+ (nullable instancetype)targetNamed:(nullable NSString *)targetName
                          fromConfig:(nullable NSDictionary *)config
                               error:(NSError *_Nullable *_Nullable)error;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithServiceRootURLString:(NSString *)serviceRootURLString
                                             tenantID:(NSString *)tenantID
                                             clientID:(NSString *)clientID
                                         clientSecret:(NSString *)clientSecret
                                            targetName:(nullable NSString *)targetName
                                       timeoutInterval:(NSTimeInterval)timeoutInterval
                                            maxRetries:(NSUInteger)maxRetries
                                              pageSize:(NSUInteger)pageSize
                                                 error:(NSError *_Nullable *_Nullable)error NS_DESIGNATED_INITIALIZER;

@end

@interface ALNDataverseLookupBinding : NSObject <NSCopying>

@property(nonatomic, copy, readonly) NSString *bindPath;

+ (instancetype)bindingWithBindPath:(NSString *)bindPath;
+ (nullable instancetype)bindingWithEntitySetName:(NSString *)entitySetName
                                         recordID:(NSString *)recordID
                                            error:(NSError *_Nullable *_Nullable)error;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithBindPath:(NSString *)bindPath NS_DESIGNATED_INITIALIZER;

@end

@interface ALNDataverseChoiceValue : NSObject <NSCopying>

@property(nonatomic, copy, readonly) NSNumber *numericValue;

+ (instancetype)valueWithIntegerValue:(NSNumber *)integerValue;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithIntegerValue:(NSNumber *)integerValue NS_DESIGNATED_INITIALIZER;

@end

@interface ALNDataverseRequest : NSObject

@property(nonatomic, copy, readonly) NSString *method;
@property(nonatomic, copy, readonly) NSString *URLString;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *headers;
@property(nonatomic, copy, readonly, nullable) NSData *bodyData;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithMethod:(NSString *)method
                     URLString:(NSString *)URLString
                       headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                      bodyData:(nullable NSData *)bodyData NS_DESIGNATED_INITIALIZER;

@end

@interface ALNDataverseResponse : NSObject

@property(nonatomic, assign, readonly) NSInteger statusCode;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *headers;
@property(nonatomic, copy, readonly) NSData *bodyData;
@property(nonatomic, copy, readonly) NSString *bodyText;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStatusCode:(NSInteger)statusCode
                           headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                          bodyData:(nullable NSData *)bodyData NS_DESIGNATED_INITIALIZER;
- (nullable NSString *)headerValueForName:(NSString *)name;
- (nullable id)JSONObject:(NSError *_Nullable *_Nullable)error;

@end

@protocol ALNDataverseTransport <NSObject>

- (nullable ALNDataverseResponse *)executeRequest:(ALNDataverseRequest *)request
                                            error:(NSError *_Nullable *_Nullable)error;

@end

@protocol ALNDataverseTokenProvider <NSObject>

- (nullable NSString *)accessTokenForTarget:(ALNDataverseTarget *)target
                                  transport:(id<ALNDataverseTransport>)transport
                                      error:(NSError *_Nullable *_Nullable)error;

@end

@interface ALNDataverseCurlTransport : NSObject <ALNDataverseTransport>

@property(nonatomic, assign, readonly) NSTimeInterval timeoutInterval;

- (instancetype)init;
- (instancetype)initWithTimeoutInterval:(NSTimeInterval)timeoutInterval NS_DESIGNATED_INITIALIZER;

@end

@interface ALNDataverseClientCredentialsTokenProvider : NSObject <ALNDataverseTokenProvider>

- (instancetype)init;

@end

@interface ALNDataverseRecord : NSObject

@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *values;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *formattedValues;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *annotations;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *rawDictionary;
@property(nonatomic, copy, readonly, nullable) NSString *etag;

+ (nullable instancetype)recordWithDictionary:(NSDictionary<NSString *, id> *)dictionary
                                        error:(NSError *_Nullable *_Nullable)error;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithDictionary:(NSDictionary<NSString *, id> *)dictionary
                                      error:(NSError *_Nullable *_Nullable)error NS_DESIGNATED_INITIALIZER;

@end

@interface ALNDataverseEntityPage : NSObject

@property(nonatomic, copy, readonly) NSArray<ALNDataverseRecord *> *records;
@property(nonatomic, copy, readonly, nullable) NSString *nextLinkURLString;
@property(nonatomic, copy, readonly, nullable) NSString *deltaLinkURLString;
@property(nonatomic, strong, readonly, nullable) NSNumber *totalCount;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *rawPayload;

+ (nullable instancetype)pageWithPayload:(NSDictionary<NSString *, id> *)payload
                                   error:(NSError *_Nullable *_Nullable)error;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithPayload:(NSDictionary<NSString *, id> *)payload
                                   error:(NSError *_Nullable *_Nullable)error NS_DESIGNATED_INITIALIZER;

@end

@interface ALNDataverseBatchRequest : NSObject

@property(nonatomic, copy, readonly) NSString *method;
@property(nonatomic, copy, readonly) NSString *relativePath;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *headers;
@property(nonatomic, strong, readonly, nullable) id bodyObject;
@property(nonatomic, copy, readonly, nullable) NSString *contentID;

+ (instancetype)requestWithMethod:(NSString *)method
                     relativePath:(NSString *)relativePath
                          headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                       bodyObject:(nullable id)bodyObject
                        contentID:(nullable NSString *)contentID;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithMethod:(NSString *)method
                  relativePath:(NSString *)relativePath
                       headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                    bodyObject:(nullable id)bodyObject
                     contentID:(nullable NSString *)contentID NS_DESIGNATED_INITIALIZER;

@end

@interface ALNDataverseBatchResponse : NSObject

@property(nonatomic, assign, readonly) NSInteger statusCode;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *headers;
@property(nonatomic, strong, readonly, nullable) id bodyObject;
@property(nonatomic, copy, readonly) NSString *bodyText;
@property(nonatomic, copy, readonly, nullable) NSString *contentID;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStatusCode:(NSInteger)statusCode
                           headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                        bodyObject:(nullable id)bodyObject
                          bodyText:(nullable NSString *)bodyText
                         contentID:(nullable NSString *)contentID NS_DESIGNATED_INITIALIZER;

@end

@interface ALNDataverseClient : NSObject

@property(nonatomic, strong, readonly) ALNDataverseTarget *target;
@property(nonatomic, strong, readonly) id<ALNDataverseTransport> transport;
@property(nonatomic, strong, readonly) id<ALNDataverseTokenProvider> tokenProvider;

+ (NSDictionary<NSString *, id> *)capabilityMetadata;
+ (nullable NSString *)recordPathForEntitySet:(NSString *)entitySetName
                                     recordID:(NSString *)recordID
                                        error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSString *)recordPathForEntitySet:(NSString *)entitySetName
                            alternateKeyValues:(NSDictionary<NSString *, id> *)alternateKeyValues
                                         error:(NSError *_Nullable *_Nullable)error;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithTarget:(ALNDataverseTarget *)target
                                  error:(NSError *_Nullable *_Nullable)error;
- (nullable instancetype)initWithTarget:(ALNDataverseTarget *)target
                              transport:(nullable id<ALNDataverseTransport>)transport
                          tokenProvider:(nullable id<ALNDataverseTokenProvider>)tokenProvider
                                  error:(NSError *_Nullable *_Nullable)error NS_DESIGNATED_INITIALIZER;

- (nullable NSDictionary<NSString *, id> *)ping:(NSError *_Nullable *_Nullable)error;
- (nullable ALNDataverseResponse *)performRequestWithMethod:(NSString *)method
                                                       path:(NSString *)path
                                                      query:(nullable NSDictionary<NSString *, NSString *> *)query
                                                    headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                                                 bodyObject:(nullable id)bodyObject
                                     includeFormattedValues:(BOOL)includeFormattedValues
                                       returnRepresentation:(BOOL)returnRepresentation
                                           consistencyCount:(BOOL)consistencyCount
                                                      error:(NSError *_Nullable *_Nullable)error;
- (nullable ALNDataverseEntityPage *)fetchPageForQuery:(ALNDataverseQuery *)query
                                                 error:(NSError *_Nullable *_Nullable)error;
- (nullable ALNDataverseEntityPage *)fetchNextPageWithURLString:(NSString *)URLString
                                                          error:(NSError *_Nullable *_Nullable)error;
- (nullable ALNDataverseRecord *)retrieveRecordInEntitySet:(NSString *)entitySetName
                                                  recordID:(NSString *)recordID
                                              selectFields:(nullable NSArray<NSString *> *)selectFields
                                                    expand:(nullable NSDictionary<NSString *, id> *)expand
                                    includeFormattedValues:(BOOL)includeFormattedValues
                                                     error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary<NSString *, id> *)createRecordInEntitySet:(NSString *)entitySetName
                                                            values:(NSDictionary<NSString *, id> *)values
                                               returnRepresentation:(BOOL)returnRepresentation
                                                             error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary<NSString *, id> *)updateRecordInEntitySet:(NSString *)entitySetName
                                                          recordID:(NSString *)recordID
                                                            values:(NSDictionary<NSString *, id> *)values
                                                           ifMatch:(nullable NSString *)ifMatch
                                               returnRepresentation:(BOOL)returnRepresentation
                                                             error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary<NSString *, id> *)upsertRecordInEntitySet:(NSString *)entitySetName
                                                alternateKeyValues:(NSDictionary<NSString *, id> *)alternateKeyValues
                                                            values:(NSDictionary<NSString *, id> *)values
                                                         createOnly:(BOOL)createOnly
                                                         updateOnly:(BOOL)updateOnly
                                                returnRepresentation:(BOOL)returnRepresentation
                                                             error:(NSError *_Nullable *_Nullable)error;
- (BOOL)deleteRecordInEntitySet:(NSString *)entitySetName
                       recordID:(NSString *)recordID
                        ifMatch:(nullable NSString *)ifMatch
                          error:(NSError *_Nullable *_Nullable)error;
- (nullable id)invokeActionNamed:(NSString *)actionName
                        boundPath:(nullable NSString *)boundPath
                       parameters:(nullable NSDictionary<NSString *, id> *)parameters
                            error:(NSError *_Nullable *_Nullable)error;
- (nullable id)invokeFunctionNamed:(NSString *)functionName
                          boundPath:(nullable NSString *)boundPath
                         parameters:(nullable NSDictionary<NSString *, id> *)parameters
                              error:(NSError *_Nullable *_Nullable)error;
- (nullable NSArray<ALNDataverseBatchResponse *> *)executeBatchRequests:
                                                    (NSArray<ALNDataverseBatchRequest *> *)requests
                                                             error:(NSError *_Nullable *_Nullable)error;

@end

FOUNDATION_EXPORT NSError *ALNDataverseMakeError(ALNDataverseErrorCode code,
                                                 NSString *message,
                                                 NSDictionary *_Nullable userInfo);

NS_ASSUME_NONNULL_END

#endif

#ifndef ALN_EVENT_STREAM_H
#define ALN_EVENT_STREAM_H

#import <Foundation/Foundation.h>

@class ALNContext;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNEventStreamErrorDomain;

typedef NS_ENUM(NSInteger, ALNEventStreamErrorCode) {
  ALNEventStreamErrorInvalidArgument = 1,
  ALNEventStreamErrorInvalidEnvelope = 2,
  ALNEventStreamErrorIdempotencyConflict = 3,
  ALNEventStreamErrorUnauthorized = 4,
  ALNEventStreamErrorResyncRequired = 5,
};

@interface ALNEventStreamCursor : NSObject <NSCopying>

@property(nonatomic, copy, readonly) NSString *streamID;
@property(nonatomic, assign, readonly) NSUInteger sequence;

- (instancetype)initWithStreamID:(NSString *)streamID sequence:(NSUInteger)sequence;
- (NSDictionary *)dictionaryRepresentation;

@end

@interface ALNEventEnvelope : NSObject <NSCopying>

@property(nonatomic, copy, readonly) NSString *streamID;
@property(nonatomic, assign, readonly) NSUInteger sequence;
@property(nonatomic, copy, readonly) NSString *eventID;
@property(nonatomic, copy, readonly) NSString *eventType;
@property(nonatomic, copy, readonly) NSString *occurredAt;
@property(nonatomic, copy, readonly) NSDictionary *payload;
@property(nonatomic, copy, readonly, nullable) NSString *idempotencyKey;
@property(nonatomic, copy, readonly, nullable) NSDictionary *actor;
@property(nonatomic, copy, readonly, nullable) NSDictionary *metadata;

- (instancetype)initWithStreamID:(NSString *)streamID
                        sequence:(NSUInteger)sequence
                         eventID:(NSString *)eventID
                       eventType:(NSString *)eventType
                      occurredAt:(NSString *)occurredAt
                         payload:(NSDictionary *)payload
                  idempotencyKey:(nullable NSString *)idempotencyKey
                           actor:(nullable NSDictionary *)actor
                        metadata:(nullable NSDictionary *)metadata;
- (NSDictionary *)dictionaryRepresentation;

@end

@interface ALNEventStreamAppendResult : NSObject

@property(nonatomic, strong, readonly) ALNEventEnvelope *committedEvent;
@property(nonatomic, assign, readonly) BOOL livePublishAttempted;
@property(nonatomic, assign, readonly) BOOL livePublishSucceeded;
@property(nonatomic, strong, readonly, nullable) NSError *livePublishError;

- (instancetype)initWithCommittedEvent:(ALNEventEnvelope *)committedEvent
                  livePublishAttempted:(BOOL)livePublishAttempted
                  livePublishSucceeded:(BOOL)livePublishSucceeded
                      livePublishError:(nullable NSError *)livePublishError;

@end

@interface ALNEventStreamReplayResult : NSObject

@property(nonatomic, copy, readonly) NSString *streamID;
@property(nonatomic, copy, readonly) NSArray<ALNEventEnvelope *> *events;
@property(nonatomic, strong, readonly) ALNEventStreamCursor *latestCursor;
@property(nonatomic, strong, readonly, nullable) NSNumber *requestedAfterSequence;
@property(nonatomic, assign, readonly) NSUInteger replayLimit;
@property(nonatomic, assign, readonly) NSUInteger replayWindow;
@property(nonatomic, assign, readonly) BOOL resyncRequired;

- (instancetype)initWithStreamID:(NSString *)streamID
                          events:(NSArray<ALNEventEnvelope *> *)events
                    latestCursor:(ALNEventStreamCursor *)latestCursor
           requestedAfterSequence:(nullable NSNumber *)requestedAfterSequence
                     replayLimit:(NSUInteger)replayLimit
                    replayWindow:(NSUInteger)replayWindow
                  resyncRequired:(BOOL)resyncRequired;
- (NSDictionary *)dictionaryRepresentation;

@end

@interface ALNEventStreamRequestContext : NSObject <NSCopying>

@property(nonatomic, copy, readonly) NSString *requestMethod;
@property(nonatomic, copy, readonly) NSString *requestPath;
@property(nonatomic, copy, readonly) NSString *requestQueryString;
@property(nonatomic, copy, readonly) NSString *routeName;
@property(nonatomic, copy, readonly) NSString *controllerName;
@property(nonatomic, copy, readonly) NSString *actionName;
@property(nonatomic, copy, readonly, nullable) NSString *authSubject;
@property(nonatomic, copy, readonly) NSArray *authScopes;
@property(nonatomic, copy, readonly) NSArray *authRoles;
@property(nonatomic, copy, readonly, nullable) NSDictionary *authClaims;
@property(nonatomic, copy, readonly, nullable) NSString *authSessionIdentifier;
@property(nonatomic, assign, readonly) BOOL liveRequest;

+ (instancetype)requestContextWithContext:(ALNContext *)context;
- (instancetype)initWithRequestMethod:(NSString *)requestMethod
                          requestPath:(NSString *)requestPath
                   requestQueryString:(nullable NSString *)requestQueryString
                            routeName:(nullable NSString *)routeName
                       controllerName:(nullable NSString *)controllerName
                           actionName:(nullable NSString *)actionName
                          authSubject:(nullable NSString *)authSubject
                           authScopes:(nullable NSArray *)authScopes
                            authRoles:(nullable NSArray *)authRoles
                           authClaims:(nullable NSDictionary *)authClaims
                authSessionIdentifier:(nullable NSString *)authSessionIdentifier
                          liveRequest:(BOOL)liveRequest;
- (NSDictionary *)dictionaryRepresentation;

@end

@protocol ALNEventStreamStore <NSObject>

- (NSString *)adapterName;
- (nullable ALNEventEnvelope *)appendEvent:(NSDictionary *)event
                                  toStream:(NSString *)streamID
                                     error:(NSError *_Nullable *_Nullable)error;
- (nullable NSArray<ALNEventEnvelope *> *)eventsForStream:(NSString *)streamID
                                            afterSequence:(nullable NSNumber *)sequence
                                                    limit:(NSUInteger)limit
                                                    error:(NSError *_Nullable *_Nullable)error;
- (nullable ALNEventStreamCursor *)latestCursorForStream:(NSString *)streamID
                                                   error:(NSError *_Nullable *_Nullable)error;

@optional
- (void)reset;

@end

@protocol ALNEventStreamLiveSubscriber <NSObject>

- (void)receiveCommittedEvent:(ALNEventEnvelope *)event onStream:(NSString *)streamID;

@end

@interface ALNEventStreamBrokerSubscription : NSObject

@property(nonatomic, copy, readonly) NSString *streamID;
@property(nonatomic, strong, readonly) id<ALNEventStreamLiveSubscriber> subscriber;

- (instancetype)initWithStreamID:(NSString *)streamID
                      subscriber:(id<ALNEventStreamLiveSubscriber>)subscriber;

@end

@protocol ALNEventStreamBroker <NSObject>

- (NSString *)adapterName;
- (BOOL)publishCommittedEvent:(ALNEventEnvelope *)event
                     onStream:(NSString *)streamID
                        error:(NSError *_Nullable *_Nullable)error;
- (nullable ALNEventStreamBrokerSubscription *)subscribeToStream:(NSString *)streamID
                                                      subscriber:(id<ALNEventStreamLiveSubscriber>)subscriber
                                                           error:(NSError *_Nullable *_Nullable)error;
- (void)unsubscribe:(nullable ALNEventStreamBrokerSubscription *)subscription;

@optional
- (void)reset;

@end

@protocol ALNEventStreamAuthorizationHook <NSObject>

- (BOOL)authorizeEventStreamAppendToStream:(NSString *)streamID
                                     event:(NSDictionary *)event
                            requestContext:(ALNEventStreamRequestContext *)requestContext
                                     error:(NSError *_Nullable *_Nullable)error;
- (BOOL)authorizeEventStreamReplayOfStream:(NSString *)streamID
                             afterSequence:(nullable NSNumber *)sequence
                            requestContext:(ALNEventStreamRequestContext *)requestContext
                                     error:(NSError *_Nullable *_Nullable)error;
- (BOOL)authorizeEventStreamSubscribeToStream:(NSString *)streamID
                               requestContext:(ALNEventStreamRequestContext *)requestContext
                                        error:(NSError *_Nullable *_Nullable)error;

@end

@interface ALNInMemoryEventStreamStore : NSObject <ALNEventStreamStore>

- (instancetype)initWithAdapterName:(nullable NSString *)adapterName;

@end

@interface ALNInMemoryEventStreamBroker : NSObject <ALNEventStreamBroker>

- (instancetype)initWithAdapterName:(nullable NSString *)adapterName;

@end

@interface ALNEventStreamService : NSObject

@property(nonatomic, strong, readonly) id<ALNEventStreamStore> store;
@property(nonatomic, strong, readonly, nullable) id<ALNEventStreamBroker> broker;

- (instancetype)initWithStore:(id<ALNEventStreamStore>)store
                       broker:(nullable id<ALNEventStreamBroker>)broker;
- (nullable ALNEventStreamAppendResult *)appendEvent:(NSDictionary *)event
                                            toStream:(NSString *)streamID
                                               error:(NSError *_Nullable *_Nullable)error;
- (nullable ALNEventStreamReplayResult *)replayStream:(NSString *)streamID
                                        afterSequence:(nullable NSNumber *)sequence
                                                limit:(NSUInteger)limit
                                         replayWindow:(NSUInteger)replayWindow
                                                error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif

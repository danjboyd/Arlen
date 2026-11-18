#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNEventStream.h"

// The optional keepalive re-authorization of a live SSE subscription: default YES, the hook's answer when it
// implements the method, NO when the hook raises.

@interface ReauthBaseHook : NSObject <ALNEventStreamAuthorizationHook>
@end
@implementation ReauthBaseHook
- (BOOL)authorizeEventStreamAppendToStream:(NSString *)streamID event:(NSDictionary *)event
                            requestContext:(ALNEventStreamRequestContext *)requestContext error:(NSError **)error { return YES; }
- (BOOL)authorizeEventStreamReplayOfStream:(NSString *)streamID afterSequence:(NSNumber *)sequence
                            requestContext:(ALNEventStreamRequestContext *)requestContext error:(NSError **)error { return YES; }
- (BOOL)authorizeEventStreamSubscribeToStream:(NSString *)streamID
                               requestContext:(ALNEventStreamRequestContext *)requestContext error:(NSError **)error { return YES; }
@end

@interface ReauthAnsweringHook : ReauthBaseHook
@property(nonatomic, assign) BOOL answer;
@property(nonatomic, assign) BOOL raises;
@property(nonatomic, assign) NSUInteger calls;
@property(nonatomic, copy) NSString *lastStream;
@end
@implementation ReauthAnsweringHook
- (BOOL)eventStreamSubscriptionStillAuthorizedToStream:(NSString *)streamID
                                        requestContext:(ALNEventStreamRequestContext *)requestContext {
  self.calls += 1;
  self.lastStream = streamID;
  if (self.raises) [NSException raise:@"ReauthTest" format:@"hook failure"];
  return self.answer;
}
@end

@interface EventStreamReauthTests : XCTestCase
@end

@implementation EventStreamReauthTests

- (ALNApplication *)application {
  return [[ALNApplication alloc] initWithConfig:@{}];
}

- (ALNEventStreamRequestContext *)requestContext {
  return [[ALNEventStreamRequestContext alloc] initWithRequestMethod:@"GET" requestPath:@"/events/stream" requestQueryString:@""
                                                           routeName:@"events" controllerName:@"Events" actionName:@"stream"
                                                         authSubject:@"phone:test" authScopes:@[@"phone"] authRoles:@[]
                                                          authClaims:@{@"jti": @"device-1"} authSessionIdentifier:nil liveRequest:YES];
}

- (void)testDefaultsToYesWithoutAHook {
  XCTAssertTrue([[self application] eventStreamSubscriptionStillAuthorizedToStream:@"s" requestContext:[self requestContext]]);
}

- (void)testHooksWithoutTheOptionalMethodKeepTheOldBehaviour {
  ALNApplication *app = [self application];
  [app setEventStreamAuthorizationHook:[ReauthBaseHook new]];
  XCTAssertTrue([app eventStreamSubscriptionStillAuthorizedToStream:@"s" requestContext:[self requestContext]]);
}

- (void)testTheHooksAnswerIsUsed {
  ALNApplication *app = [self application];
  ReauthAnsweringHook *hook = [ReauthAnsweringHook new];
  [app setEventStreamAuthorizationHook:hook];
  hook.answer = YES;
  XCTAssertTrue([app eventStreamSubscriptionStillAuthorizedToStream:@"s1" requestContext:[self requestContext]]);
  hook.answer = NO;
  XCTAssertFalse([app eventStreamSubscriptionStillAuthorizedToStream:@"s1" requestContext:[self requestContext]]);
  XCTAssertEqual(hook.calls, (NSUInteger)2);
  XCTAssertEqualObjects(hook.lastStream, @"s1");
}

- (void)testARaisingHookCannotVouchForTheSubscription {
  ALNApplication *app = [self application];
  ReauthAnsweringHook *hook = [ReauthAnsweringHook new];
  hook.raises = YES;
  [app setEventStreamAuthorizationHook:hook];
  XCTAssertFalse([app eventStreamSubscriptionStillAuthorizedToStream:@"s" requestContext:[self requestContext]]);
}

- (void)testNoRequestContextKeepsTheSubscription {
  ALNApplication *app = [self application];
  ReauthAnsweringHook *hook = [ReauthAnsweringHook new];
  [app setEventStreamAuthorizationHook:hook];
  XCTAssertTrue([app eventStreamSubscriptionStillAuthorizedToStream:@"s" requestContext:nil]);
  XCTAssertEqual(hook.calls, (NSUInteger)0);
}

@end

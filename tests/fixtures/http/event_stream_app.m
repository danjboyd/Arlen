#import <Foundation/Foundation.h>
#import "ArlenServer.h"
#import "ALNAppRunner.h"
#import "ALNController.h"
#import "ALNContext.h"
#import "ALNEventStream.h"
#import "ALNRequest.h"

// GitHub issue 240 fixture: in-memory event streams with an allow-all hook,
// an append route and an SSE route.
@interface EventStreamFixtureHook : NSObject <ALNEventStreamAuthorizationHook>
@end
@implementation EventStreamFixtureHook
- (BOOL)authorizeEventStreamAppendToStream:(NSString *)streamID
                                     event:(NSDictionary *)event
                            requestContext:(ALNEventStreamRequestContext *)requestContext
                                     error:(NSError **)error {
  return YES;
}
- (BOOL)authorizeEventStreamReplayOfStream:(NSString *)streamID
                             afterSequence:(NSNumber *)sequence
                            requestContext:(ALNEventStreamRequestContext *)requestContext
                                     error:(NSError **)error {
  return YES;
}
- (BOOL)authorizeEventStreamSubscribeToStream:(NSString *)streamID
                               requestContext:(ALNEventStreamRequestContext *)requestContext
                                        error:(NSError **)error {
  return YES;
}
@end

@interface EventStreamFixtureController : ALNController
@end
@implementation EventStreamFixtureController
// GET /append?stream=s&n=20 appends n events and reports the last sequence.
- (id)append:(ALNContext *)ctx {
  NSString *stream = ctx.request.queryParams[@"stream"] ?: @"s1";
  NSUInteger count = (NSUInteger)[ctx.request.queryParams[@"n"] integerValue];
  NSUInteger last = 0;
  for (NSUInteger idx = 0; idx < MAX(count, (NSUInteger)1); idx++) {
    NSError *error = nil;
    ALNEventStreamAppendResult *result =
        [self appendEventStreamEvent:@{ @"event_type" : @"tick", @"payload" : @{ @"i" : @(idx) } }
                            toStream:stream
                               error:&error];
    last = result.committedEvent.sequence;
  }
  [self renderText:[NSString stringWithFormat:@"last=%lu\n", (unsigned long)last]];
  return nil;
}
// GET /sse?stream=s[&after=N]; without after, a Last-Event-ID header resumes.
- (id)sse:(ALNContext *)ctx {
  NSString *stream = ctx.request.queryParams[@"stream"] ?: @"s1";
  NSString *after = ctx.request.queryParams[@"after"];
  NSError *error = nil;
  if (![self renderSSEStream:stream
               afterSequence:(after != nil ? @([after integerValue]) : nil)
                       limit:1000
                replayWindow:1000
                       error:&error]) {
    [self setStatus:403];
    [self renderText:error.localizedDescription ?: @"denied"];
  }
  return nil;
}
@end

static void RegisterRoutes(ALNApplication *app) {
  Class controller = [EventStreamFixtureController class];
  [app registerRouteMethod:@"GET" path:@"/append" name:nil controllerClass:controller action:@"append"];
  [app registerRouteMethod:@"GET" path:@"/sse" name:nil controllerClass:controller action:@"sse"];
  [app setEventStreamAuthorizationHook:[[EventStreamFixtureHook alloc] init]];
  [app setEventStreamStore:[[ALNInMemoryEventStreamStore alloc] initWithAdapterName:nil]];
  [app setEventStreamBroker:[[ALNInMemoryEventStreamBroker alloc] initWithAdapterName:nil]];
}

int main(int argc, const char *argv[]) {
  @autoreleasepool { return ALNRunAppMain(argc, argv, &RegisterRoutes); }
}

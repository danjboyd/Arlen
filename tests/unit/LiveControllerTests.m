#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNContext.h"
#import "ALNController.h"
#import "ALNEOCRuntime.h"
#import "ALNLive.h"
#import "ALNLogger.h"
#import "ALNPerf.h"
#import "ALNRealtime.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "../shared/ALNWebTestSupport.h"

static NSString *RenderLivePanel(id ctx, NSError **error) {
  (void)ctx;
  (void)error;
  return @"<section class=\"panel\">Ready</section>";
}

static NSString *RenderLiveFeedItem(id ctx, NSError **error) {
  (void)error;
  NSString *key = [ctx isKindOfClass:[NSDictionary class]] ? ctx[@"key"] : @"";
  NSString *label = [ctx isKindOfClass:[NSDictionary class]] ? ctx[@"label"] : @"";
  return [NSString stringWithFormat:@"<li data-arlen-live-key=\"%@\">%@</li>",
                                    key ?: @"",
                                    label ?: @""];
}

@interface LiveControllerHarness : ALNController
@end

@implementation LiveControllerHarness
@end

@interface LiveControllerSubscriber : NSObject <ALNRealtimeSubscriber>

@property(nonatomic, strong) NSMutableArray<NSString *> *messages;

@end

@implementation LiveControllerSubscriber

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _messages = [NSMutableArray array];
  }
  return self;
}

- (void)receiveRealtimeMessage:(NSString *)message onChannel:(NSString *)channel {
  (void)channel;
  [self.messages addObject:message ?: @""];
}

@end

@interface LiveControllerTests : XCTestCase
@end

@implementation LiveControllerTests

- (void)setUp {
  [super setUp];
  ALNEOCClearTemplateRegistry();
  [[ALNRealtimeHub sharedHub] reset];
}

- (void)tearDown {
  [[ALNRealtimeHub sharedHub] reset];
  ALNEOCClearTemplateRegistry();
  [super tearDown];
}

- (ALNContext *)freshContextWithHeaders:(NSDictionary *)headers {
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"POST"
                                                      path:@"/live/items"
                                               queryString:@""
                                                   headers:headers ?: @{}
                                                      body:[NSData data]];
  ALNResponse *response = [[ALNResponse alloc] init];
  ALNLogger *logger = [[ALNLogger alloc] initWithFormat:@"json"];
  ALNPerfTrace *trace = [[ALNPerfTrace alloc] initWithEnabled:NO];
  NSMutableDictionary *stash = [NSMutableDictionary dictionary];
  stash[@"request_id"] = @"req-live-controller";
  stash[@"aln.trace_id"] = @"trace-live-controller";
  return [[ALNContext alloc] initWithRequest:request
                                    response:response
                                      params:@{}
                                       stash:stash
                                      logger:logger
                                   perfTrace:trace
                                   routeName:@"live_items"
                              controllerName:@"LiveControllerHarness"
                                  actionName:@"updatePanel"];
}

- (LiveControllerHarness *)freshControllerWithHeaders:(NSDictionary *)headers {
  LiveControllerHarness *controller = [[LiveControllerHarness alloc] init];
  controller.context = [self freshContextWithHeaders:headers];
  return controller;
}

- (void)testContextAndControllerDetectLiveRequest {
  NSDictionary *headers = @{
    @"X-Arlen-Live" : @"true",
    @"X-Arlen-Live-Target" : @"#panel",
    @"X-Arlen-Live-Swap" : @"update",
    @"X-Arlen-Live-Component" : @"orders-panel",
    @"X-Arlen-Live-Event" : @"submit",
  };
  LiveControllerHarness *controller = [self freshControllerWithHeaders:headers];

  XCTAssertTrue([controller.context isLiveRequest]);
  XCTAssertTrue([controller isLiveRequest]);
  XCTAssertEqualObjects(@"#panel", [controller liveMetadata][@"target"]);
  XCTAssertEqualObjects(@"orders-panel", [controller.context liveMetadata][@"component"]);
}

- (void)testRenderLiveTemplateWrapsRenderedHTMLInOperation {
  ALNEOCRegisterTemplate(@"widgets/panel.html.eoc", &RenderLivePanel);
  LiveControllerHarness *controller =
      [self freshControllerWithHeaders:@{ @"X-Arlen-Live" : @"true" }];

  NSError *error = nil;
  BOOL ok = [controller renderLiveTemplate:@"widgets/panel"
                                    target:@"#panel"
                                    action:@"update"
                                   context:@{}
                                     error:&error];

  XCTAssertTrue(ok);
  XCTAssertNil(error);
  XCTAssertEqualObjects([ALNLive contentType],
                        [controller.context.response headerForName:@"Content-Type"]);

  NSDictionary *payload = ALNTestJSONDictionaryFromResponse(controller.context.response, &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"update", payload[@"operations"][0][@"op"]);
  XCTAssertEqualObjects(@"#panel", payload[@"operations"][0][@"target"]);
  XCTAssertEqualObjects(@"<section class=\"panel\">Ready</section>",
                        payload[@"operations"][0][@"html"]);
  XCTAssertEqualObjects(@"live_items", payload[@"meta"][@"route"]);
  XCTAssertEqualObjects(@"POST", payload[@"meta"][@"method"]);
}

- (void)testRenderLiveTemplateUsesRequestMetadataDefaults {
  ALNEOCRegisterTemplate(@"widgets/panel.html.eoc", &RenderLivePanel);
  LiveControllerHarness *controller = [self freshControllerWithHeaders:@{
    @"X-Arlen-Live" : @"true",
    @"X-Arlen-Live-Target" : @"#panel",
    @"X-Arlen-Live-Swap" : @"prepend",
  }];

  NSError *error = nil;
  BOOL ok = [controller renderLiveTemplate:@"widgets/panel"
                                    target:nil
                                    action:nil
                                   context:@{}
                                     error:&error];

  XCTAssertTrue(ok);
  XCTAssertNil(error);

  NSDictionary *payload = ALNTestJSONDictionaryFromResponse(controller.context.response, &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"prepend", payload[@"operations"][0][@"op"]);
  XCTAssertEqualObjects(@"#panel", payload[@"operations"][0][@"target"]);
}

- (void)testRenderLiveKeyedTemplateUsesKeyedCollectionOperation {
  ALNEOCRegisterTemplate(@"widgets/feed_item.html.eoc", &RenderLiveFeedItem);
  LiveControllerHarness *controller = [self freshControllerWithHeaders:@{
    @"X-Arlen-Live" : @"true",
    @"X-Arlen-Live-Container" : @"#feed",
    @"X-Arlen-Live-Key" : @"row-alpha",
  }];

  NSError *error = nil;
  BOOL ok = [controller renderLiveKeyedTemplate:@"widgets/feed_item"
                                      container:nil
                                            key:nil
                                        prepend:YES
                                        context:@{
                                          @"key" : @"row-alpha",
                                          @"label" : @"Alpha",
                                        }
                                          error:&error];

  XCTAssertTrue(ok);
  XCTAssertNil(error);

  NSDictionary *payload = ALNTestJSONDictionaryFromResponse(controller.context.response, &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"upsert", payload[@"operations"][0][@"op"]);
  XCTAssertEqualObjects(@"#feed", payload[@"operations"][0][@"container"]);
  XCTAssertEqualObjects(@"row-alpha", payload[@"operations"][0][@"key"]);
  XCTAssertEqualObjects(@(YES), payload[@"operations"][0][@"prepend"]);
  XCTAssertEqualObjects(@"#feed [data-arlen-live-key=\"row-alpha\"]",
                        payload[@"operations"][0][@"target"]);
  XCTAssertEqualObjects(@"#feed", payload[@"meta"][@"live"][@"container"]);
  XCTAssertEqualObjects(@"row-alpha", payload[@"meta"][@"live"][@"key"]);
}

- (void)testRenderLiveNavigateToBuildsNavigateOperation {
  LiveControllerHarness *controller =
      [self freshControllerWithHeaders:@{ @"X-Arlen-Live" : @"true" }];

  [controller renderLiveNavigateTo:@"/orders/42" replace:YES];

  NSError *error = nil;
  NSDictionary *payload = ALNTestJSONDictionaryFromResponse(controller.context.response, &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"navigate", payload[@"operations"][0][@"op"]);
  XCTAssertEqualObjects(@"/orders/42", payload[@"operations"][0][@"location"]);
  XCTAssertEqualObjects(@(YES), payload[@"operations"][0][@"replace"]);
}

- (void)testPublishLiveOperationsPublishesPayloadToChannel {
  LiveControllerHarness *controller =
      [self freshControllerWithHeaders:@{ @"X-Arlen-Live" : @"true" }];
  LiveControllerSubscriber *subscriber = [[LiveControllerSubscriber alloc] init];
  ALNRealtimeSubscription *subscription =
      [[ALNRealtimeHub sharedHub] subscribeChannel:@"live.feed" subscriber:subscriber];
  XCTAssertNotNil(subscription);

  NSError *error = nil;
  NSUInteger delivered = [controller publishLiveOperations:@[
    [ALNLive appendOperationForTarget:@"#feed" html:@"<li>One</li>"]
  ]
                                                  onChannel:@"live.feed"
                                                      error:&error];

  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, delivered);
  XCTAssertEqual((NSUInteger)1, [subscriber.messages count]);

  NSData *messageData = [subscriber.messages[0] dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:messageData
                                                          options:0
                                                            error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects([ALNLive protocolVersion], payload[@"version"]);
  XCTAssertEqualObjects(@"append", payload[@"operations"][0][@"op"]);
  XCTAssertEqualObjects(@"#feed", payload[@"operations"][0][@"target"]);
}

- (void)testPublishLiveKeyedTemplatePublishesPayloadToChannel {
  ALNEOCRegisterTemplate(@"widgets/feed_item.html.eoc", &RenderLiveFeedItem);
  LiveControllerHarness *controller = [self freshControllerWithHeaders:@{
    @"X-Arlen-Live" : @"true",
    @"X-Arlen-Live-Container" : @"#feed",
    @"X-Arlen-Live-Key" : @"row-gamma",
  }];
  LiveControllerSubscriber *subscriber = [[LiveControllerSubscriber alloc] init];
  ALNRealtimeSubscription *subscription =
      [[ALNRealtimeHub sharedHub] subscribeChannel:@"live.feed" subscriber:subscriber];
  XCTAssertNotNil(subscription);

  NSError *error = nil;
  NSUInteger delivered = [controller publishLiveKeyedTemplate:@"widgets/feed_item"
                                                    container:nil
                                                          key:nil
                                                      prepend:NO
                                                      context:@{
                                                        @"key" : @"row-gamma",
                                                        @"label" : @"Gamma",
                                                      }
                                                    onChannel:@"live.feed"
                                                        error:&error];

  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, delivered);
  XCTAssertEqual((NSUInteger)1, [subscriber.messages count]);

  NSData *messageData = [subscriber.messages[0] dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:messageData
                                                          options:0
                                                            error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"upsert", payload[@"operations"][0][@"op"]);
  XCTAssertEqualObjects(@"#feed", payload[@"operations"][0][@"container"]);
  XCTAssertEqualObjects(@"row-gamma", payload[@"operations"][0][@"key"]);
}

- (void)testRenderLiveTemplateRejectsUnsupportedAction {
  ALNEOCRegisterTemplate(@"widgets/panel.html.eoc", &RenderLivePanel);
  LiveControllerHarness *controller =
      [self freshControllerWithHeaders:@{ @"X-Arlen-Live" : @"true" }];

  NSError *error = nil;
  BOOL ok = [controller renderLiveTemplate:@"widgets/panel"
                                    target:@"#panel"
                                    action:@"remove"
                                   context:@{}
                                     error:&error];

  XCTAssertFalse(ok);
  XCTAssertNotNil(error);
  XCTAssertTrue([error.localizedDescription containsString:@"replace, update, append, or prepend"]);
}

@end

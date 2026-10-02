#import <Foundation/Foundation.h>
#import "ArlenServer.h"
#import "ALNAppRunner.h"
#import "ALNController.h"
#import "ALNContext.h"
#import "ALNResponse.h"
#import "ALNRequest.h"

@interface CookieFixtureController : ALNController
@end
@implementation CookieFixtureController
- (id)issue:(ALNContext *)ctx {
  [self session][@"user"] = @"fixture";
  [ctx.response appendHeader:@"Set-Cookie"
                      value:@"remember=device; Domain=127.0.0.1; Path=/account; HttpOnly; Expires=Wed, 09 Jun 2032 10:18:14 GMT"];
  [ctx.response appendHeader:@"Set-Cookie" value:@"bad=1\r\nX-Injected: yes"];
  [self renderText:@"issued"];
  // Prime the cache before didProcessContext appends the session cookie.
  (void)[ctx.response serializedHeaderData];
  return nil;
}
- (id)legacy:(ALNContext *)ctx {
  [ctx.response appendHeader:@"Set-Cookie" value:@"legacy=old; Path=/; HttpOnly"];
  [self renderText:@"legacy issued"];
  return nil;
}
- (id)logout:(ALNContext *)ctx {
  [[self session] removeAllObjects];
  [ctx.response appendHeader:@"Set-Cookie"
                      value:@"remember=; Domain=127.0.0.1; Path=/account; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT"];
  [ctx.response appendHeader:@"set-cookie"
                      value:@"legacy=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT"];
  [self renderText:@"logged out"];
  (void)[ctx.response serializedHeaderData];
  return nil;
}
- (id)inspect:(ALNContext *)ctx {
  return @{ @"cookies":ctx.request.cookies, @"user":[ctx session][@"user"] ?: @"" };
}
@end
static void RegisterRoutes(ALNApplication *app) {
  for (NSString *method in @[@"GET", @"HEAD"]) {
    [app registerRouteMethod:method path:@"/issue" name:nil controllerClass:[CookieFixtureController class] action:@"issue"];
    [app registerRouteMethod:method path:@"/account/logout" name:nil controllerClass:[CookieFixtureController class] action:@"logout"];
  }
  [app registerRouteMethod:@"GET" path:@"/legacy" name:nil controllerClass:[CookieFixtureController class] action:@"legacy"];
  [app registerRouteMethod:@"GET" path:@"/account/check" name:nil controllerClass:[CookieFixtureController class] action:@"inspect"];
  [app registerRouteMethod:@"GET" path:@"/outside" name:nil controllerClass:[CookieFixtureController class] action:@"inspect"];
}
int main(int argc, const char *argv[]) {
  @autoreleasepool { return ALNRunAppMain(argc, argv, &RegisterRoutes); }
}

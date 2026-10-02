#import <Foundation/Foundation.h>
#import "ArlenServer.h"
#import "ALNAppRunner.h"
#import "ALNController.h"
#import "ALNContext.h"

@interface SPAFixtureController : ALNController
@end
@implementation SPAFixtureController
- (id)ping:(ALNContext *)ctx {
  (void)ctx;
  return @{ @"pong" : @YES };
}
@end
static void RegisterRoutes(ALNApplication *app) {
  [app registerRouteMethod:@"GET" path:@"/api/ping" name:nil controllerClass:[SPAFixtureController class] action:@"ping"];
}
int main(int argc, const char *argv[]) {
  @autoreleasepool { return ALNRunAppMain(argc, argv, &RegisterRoutes); }
}

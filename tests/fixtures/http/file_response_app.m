#import <Foundation/Foundation.h>
#import "ArlenServer.h"
#import "ALNAppRunner.h"
#import "ALNController.h"
#import "ALNContext.h"

// GitHub issue 67 fixture: authenticated-style media served through renderFileAtPath:.
@interface FileResponseFixtureController : ALNController
@end
@implementation FileResponseFixtureController
- (id)media:(ALNContext *)ctx {
  NSString *path = [[[NSProcessInfo processInfo] environment][@"ARLEN_TEST_MEDIA_FILE"] copy] ?: @"";
  [self renderFileAtPath:path contentType:@"audio/mpeg" options:nil];
  return nil;
}
@end
static void RegisterRoutes(ALNApplication *app) {
  for (NSString *method in @[ @"GET", @"HEAD" ]) {
    [app registerRouteMethod:method path:@"/media/voice-note" name:nil
             controllerClass:[FileResponseFixtureController class] action:@"media"];
  }
}
int main(int argc, const char *argv[]) {
  @autoreleasepool { return ALNRunAppMain(argc, argv, &RegisterRoutes); }
}

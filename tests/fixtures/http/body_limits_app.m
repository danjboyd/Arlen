#import <Foundation/Foundation.h>
#import "ArlenServer.h"
#import "ALNAppRunner.h"
#import "ALNController.h"
#import "ALNContext.h"
#import "ALNRequest.h"
#import "ALNRoute.h"

// GitHub issue 87 fixture: a small default body limit with one large upload route.
@interface BodyLimitsFixtureController : ALNController
@end
@implementation BodyLimitsFixtureController
- (id)small:(ALNContext *)ctx {
  return @{ @"bodyLength" : @(ctx.request.body.length) };
}
- (id)upload:(ALNContext *)ctx {
  NSMutableArray *uploads = [NSMutableArray array];
  for (ALNUpload *upload in ctx.request.uploads) {
    NSData *data = upload.data;
    const uint8_t *bytes = data.bytes;
    uint32_t hash = 2166136261u;  // FNV-1a over every byte, NULs included
    for (NSUInteger i = 0; i < data.length; i++) {
      hash = (hash ^ bytes[i]) * 16777619u;
    }
    [uploads addObject:@{ @"size" : @(upload.size), @"fnv" : @(hash),
                          @"spooled" : @(upload.temporaryFilePath != nil) }];
  }
  return @{ @"uploads" : uploads };
}
- (id)explode:(ALNContext *)ctx {
  (void)ctx.request.uploads;
  [NSException raise:@"BodyLimitsFixture" format:@"handler failed after spooling"];
  return nil;
}
@end
static void RegisterRoutes(ALNApplication *app) {
  Class controller = [BodyLimitsFixtureController class];
  [app registerRouteMethod:@"POST" path:@"/small" name:nil controllerClass:controller action:@"small"];
  ALNRoute *upload = [app registerRouteMethod:@"POST" path:@"/upload" name:nil controllerClass:controller action:@"upload"];
  upload.maxBodyBytes = 25 * 1024 * 1024;
  ALNRoute *explode = [app registerRouteMethod:@"POST" path:@"/explode" name:nil controllerClass:controller action:@"explode"];
  explode.maxBodyBytes = 25 * 1024 * 1024;
}
int main(int argc, const char *argv[]) {
  @autoreleasepool { return ALNRunAppMain(argc, argv, &RegisterRoutes); }
}

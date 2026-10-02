#import <Foundation/Foundation.h>
#import "ArlenServer.h"
#import "ALNAppRunner.h"
#import "ALNController.h"
#import "ALNContext.h"
#import "ALNRequest.h"

// GitHub issue 64 fixture: reports what is spooled while a request is in flight.
@interface SpoolFixtureController : ALNController
@end
@implementation SpoolFixtureController
- (id)upload:(ALNContext *)ctx {
  NSString *spoolDirectory = [[NSProcessInfo processInfo] environment][@"ARLEN_TEST_SPOOL_DIR"] ?: @"";
  NSUInteger bodyFiles = 0, uploadDirectories = 0;
  for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:spoolDirectory error:NULL]) {
    if ([name hasPrefix:@"arlen-body-"]) bodyFiles++;
    if ([name hasPrefix:@"arlen-upload-"]) uploadDirectories++;
  }
  NSMutableArray *uploads = [NSMutableArray array];
  for (ALNUpload *upload in ctx.request.uploads) {
    NSData *data = upload.data;
    const uint8_t *bytes = data.bytes;
    uint32_t sum = 0;
    for (NSUInteger i = 0; i < data.length; i++) sum += bytes[i];
    [uploads addObject:@{ @"size" : @(upload.size), @"sum" : @(sum),
                          @"spooled" : @(upload.temporaryFilePath != nil) }];
  }
  return @{ @"bodyLength" : @(ctx.request.body.length), @"bodyFiles" : @(bodyFiles),
            @"uploadDirectories" : @(uploadDirectories), @"uploads" : uploads,
            @"field" : ctx.request.formParams[@"note"] ?: @"" };
}
@end
static void RegisterRoutes(ALNApplication *app) {
  [app registerRouteMethod:@"POST" path:@"/upload" name:nil controllerClass:[SpoolFixtureController class] action:@"upload"];
}
int main(int argc, const char *argv[]) {
  @autoreleasepool { return ALNRunAppMain(argc, argv, &RegisterRoutes); }
}

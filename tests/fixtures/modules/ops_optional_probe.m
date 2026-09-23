#import <Foundation/Foundation.h>
#import "ALNApplication.h"
#import "ALNOpsModule.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

int main(void) {
  @autoreleasepool {
    // This executable must not link the absent modules, even through another module.
    if (NSClassFromString(@"ALNStorageModuleRuntime") ||
        NSClassFromString(@"ALNNotificationsModuleRuntime")) return 1;
    ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
      @"environment": @"test", @"csrf": @{ @"enabled": @NO }
    }];
    NSError *error = nil;
    if (![[[ALNOpsModule alloc] init] registerWithApplication:app error:&error]) return 2;
    NSDictionary *summary = [[ALNOpsModuleRuntime sharedRuntime] dashboardSummary];
    for (NSString *name in @[ @"jobs", @"notifications", @"storage", @"search" ]) {
      if (![summary[name][@"available"] isEqual:@NO] ||
          ![summary[name][@"status"] isEqual:@"informational"]) return 3;
    }
    // Omitting auth must never make the ops surface public.
    ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"GET" path:@"/ops/api/summary"
                                              queryString:@"" headers:@{} body:[NSData data]];
    ALNResponse *response = [app dispatchRequest:request];
    if (response.statusCode != 401 && response.statusCode != 302) return 4;
    puts("ops optional modules: ok");
  }
  return 0;
}

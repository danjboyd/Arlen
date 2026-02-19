#import <Foundation/Foundation.h>

#import "ALNEOCRuntime.h"

static NSDictionary *BuildSmokeContext(void) {
  return @{
    @"title" : @"EOC Smoke Test",
    @"items" : @[ @"alpha", @"beta", @"gamma <unsafe>" ]
  };
}

int main(int argc, const char *argv[]) {
  (void)argc;
  (void)argv;

  @autoreleasepool {
    NSError *error = nil;
    NSString *rendered = ALNEOCRenderTemplate(@"index.html.eoc", BuildSmokeContext(), &error);
    if (rendered == nil) {
      fprintf(stderr, "eoc-smoke-render: render failed: %s\n",
              [[error localizedDescription] UTF8String]);
      return 1;
    }

    fprintf(stdout, "%s\n", [rendered UTF8String]);
    return 0;
  }
}

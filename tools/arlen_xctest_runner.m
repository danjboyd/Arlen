#import <Foundation/Foundation.h>
#import <XCTest/GSXCTestRunner.h>
#include <stdio.h>

static void PrintUsage(void) {
  fprintf(stderr, "Usage: arlen-xctest-runner <bundle-path>\n");
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc != 2) {
      PrintUsage();
      return 2;
    }

    NSString *bundlePath = [NSString stringWithUTF8String:argv[1]];
    if (![bundlePath length]) {
      PrintUsage();
      return 2;
    }

    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    if (bundle == nil) {
      fprintf(stderr, "arlen-xctest-runner: invalid bundle path: %s\n", argv[1]);
      return 1;
    }
    if (![bundle load]) {
      fprintf(stderr, "arlen-xctest-runner: failed to load bundle: %s\n", argv[1]);
      return 1;
    }

    BOOL passed = [[GSXCTestRunner sharedRunner] runAll];
    return passed ? 0 : 1;
  }
}

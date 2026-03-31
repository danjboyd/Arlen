#import <Foundation/Foundation.h>
#import <objc/message.h>
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

    Class runnerClass = NSClassFromString(@"GSXCTestRunner");
    if (runnerClass == Nil) {
      fprintf(stderr, "arlen-xctest-runner: GSXCTestRunner class not available after bundle load\n");
      return 1;
    }

    id runner = nil;
    SEL sharedRunnerSelector = @selector(sharedRunner);
    if ([runnerClass respondsToSelector:sharedRunnerSelector]) {
      id (*sharedRunnerImp)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
      runner = sharedRunnerImp(runnerClass, sharedRunnerSelector);
    }
    if (runner == nil) {
      runner = [[runnerClass alloc] init];
    }
    if (runner == nil || ![runner respondsToSelector:@selector(runAll)]) {
      fprintf(stderr, "arlen-xctest-runner: GSXCTestRunner does not expose runAll\n");
      return 1;
    }

    BOOL (*runAllImp)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
    BOOL passed = runAllImp(runner, @selector(runAll));
    return passed ? 0 : 1;
  }
}

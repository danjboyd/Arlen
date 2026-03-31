#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>

static void PrintUsage(void) {
  fprintf(stderr, "Usage: arlen-xctest-runner [bundle-path]\n");
}

static BOOL ALNRunnerClassIsKindOfClass(Class candidate, Class ancestor) {
  Class cursor = candidate;
  while (cursor != Nil) {
    if (cursor == ancestor) {
      return YES;
    }
    cursor = class_getSuperclass(cursor);
  }
  return NO;
}

static NSUInteger ALNRunnerDiscoveredTestMethodCount(void) {
  Class testCaseClass = NSClassFromString(@"XCTestCase");
  if (testCaseClass == Nil) {
    return 0;
  }

  int classCount = objc_getClassList(NULL, 0);
  if (classCount <= 0) {
    return 0;
  }

  Class __unsafe_unretained *classes =
      (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
  if (classes == NULL) {
    return 0;
  }

  classCount = objc_getClassList(classes, classCount);
  NSUInteger discoveredCount = 0;
  for (int idx = 0; idx < classCount; idx++) {
    Class candidate = classes[idx];
    if (candidate == Nil || candidate == testCaseClass ||
        !ALNRunnerClassIsKindOfClass(candidate, testCaseClass)) {
      continue;
    }

    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(candidate, &methodCount);
    if (methods == NULL) {
      continue;
    }
    for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
      SEL selector = method_getName(methods[methodIndex]);
      const char *selectorName = (selector != NULL) ? sel_getName(selector) : NULL;
      if (selectorName != NULL && strncmp(selectorName, "test", 4) == 0) {
        discoveredCount += 1;
      }
    }
    free(methods);
  }

  free(classes);
  return discoveredCount;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc > 2) {
      PrintUsage();
      return 2;
    }

    if (argc == 2) {
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
    } else {
      fprintf(stdout, "arlen-xctest-runner: using linked-in XCTest classes\n");
    }

    NSUInteger discoveredTests = ALNRunnerDiscoveredTestMethodCount();
    if (discoveredTests == 0) {
      fprintf(stderr, "arlen-xctest-runner: no XCTest methods were discovered\n");
      return 1;
    }
    fprintf(stdout, "arlen-xctest-runner: discovered %lu XCTest methods\n",
            (unsigned long)discoveredTests);

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

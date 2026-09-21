// Foundation-only reproducer and positive control. Never linked into Arlen.
#import <Foundation/Foundation.h>
#include <pthread.h>
#include <string.h>

static NSObject *monitor;
static NSLock *lock;
static NSArray *values;
static const char *mode;
static int protectedCounter;
volatile int ALNTSANCanaryCounter;

static void *worker(void *unused) {
  @autoreleasepool {
    for (int i = 0; i < 100; i++) {
      if (strcmp(mode, "monitor") == 0) {
        @synchronized(monitor) { protectedCounter++; }
      } else if (strcmp(mode, "lock") == 0) {
        [lock lock];
        protectedCounter++;
        [lock unlock];
      } else {
        // Deliberate race through a Foundation callback: library-wide race
        // suppressions must not hide application-owned memory accesses here.
        [values enumerateObjectsUsingBlock:^(id value, NSUInteger index, BOOL *stop) {
          ALNTSANCanaryCounter++;
        }];
      }
    }
  }
  return NULL;
}

int main(int argc, char **argv) {
  @autoreleasepool {
    mode = argc > 1 ? argv[1] : "startup";
    if (strcmp(mode, "startup") == 0) {
      puts("probe-complete:startup");
      return 0;
    }
    monitor = [NSObject new];
    lock = [NSLock new];
    values = @[ @"value" ];
    if (strcmp(mode, "queue") == 0) {
      NSOperationQueue *queue = [NSOperationQueue new];
      [queue setMaxConcurrentOperationCount:4];
      for (int i = 0; i < 16; i++) {
        [queue addOperationWithBlock:^{
          [lock lock];
          protectedCounter++;
          [lock unlock];
        }];
      }
      [queue waitUntilAllOperationsAreFinished];
      printf("probe-complete:queue protected=%d\n", protectedCounter);
      return protectedCounter == 16 ? 0 : 4;
    }
    pthread_t thread;
    if (pthread_create(&thread, NULL, worker, NULL) != 0) { return 2; }
    worker(NULL);
    if (pthread_join(thread, NULL) != 0) { return 3; }
    printf("probe-complete:%s protected=%d\n", mode, protectedCounter);
    if (strcmp(mode, "canary") != 0 && protectedCounter != 200) { return 4; }
  }
  return 0;
}

// Foundation-only reproducer and positive control. Never linked into Arlen.
#import <Foundation/Foundation.h>
#include <pthread.h>
#include <dispatch/dispatch.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <objc/runtime.h>
#include <objc/slot.h>
#include <GNUstepBase/GSObjCRuntime.h>

@interface ALNTSANKVCProbe : NSObject
- (NSNumber *)value;
@end
@implementation ALNTSANKVCProbe
- (NSNumber *)value { return @42; }
@end
static id ALNTSANKVCReplacement(id object, SEL selector) { return @42; }
static ALNTSANKVCProbe *kvcProbe;

static NSObject *monitor;
static NSLock *lock;
static NSArray *values;
static const char *mode;
static int protectedCounter;
static NSString *sharedString;
static dispatch_once_t valueOnce;
static dispatch_semaphore_t semaphore;
static NSNumber *onceValue;
volatile int ALNTSANCanaryCounter;

static void *worker(void *unused) {
  @autoreleasepool {
    for (int i = 0; i < ((strcmp(mode, "semaphore") == 0 || strcmp(mode, "task-signal") == 0 || strcmp(mode, "kvc") == 0) ? 10000 : 100); i++) {
      if (strcmp(mode, "buffer") == 0) {
        unsigned char *bytes = GSAutoreleasedBuffer(64);
        if (!bytes) return (void *)1;
        memset(bytes, 0xa5, 64);
        if (bytes[63] != 0xa5) return (void *)1;
        [lock lock]; protectedCounter++; [lock unlock];
      } else if (strcmp(mode, "kvc") == 0) {
        if ([[kvcProbe valueForKey:@"value"] intValue] != 42) return (void *)1;
      } else if (strcmp(mode, "task-signal") == 0) {
        raise(SIGCHLD);
      } else if (strcmp(mode, "monitor") == 0) {
        @synchronized(monitor) { protectedCounter++; }
      } else if (strcmp(mode, "lock") == 0) {
        [lock lock];
        protectedCounter++;
        [lock unlock];
      } else if (strcmp(mode, "semaphore") == 0) {
        while (dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) != 0) {}
        protectedCounter++;
        dispatch_semaphore_signal(semaphore);
      } else if (strcmp(mode, "foundation") == 0) {
        dispatch_once(&valueOnce, ^{ onceValue = @42; });
        if ([onceValue intValue] != 42 || [[NSData data] length] != 0 ||
            [sharedString hash] != [@"shared-123" hash] ||
            ![sharedString isEqualToString:@"shared-123"] ||
            [[NSString stringWithFormat:@"%g", 1.2] length] == 0 ||
            [@"2026-10-21" rangeOfString:@"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
                                options:NSRegularExpressionSearch].location == NSNotFound) {
          return (void *)1;
        }
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
    semaphore = dispatch_semaphore_create(1);
    values = @[ @"value" ];
    sharedString = [NSString stringWithFormat:@"shared-%d", 123];
    if (strcmp(mode, "serial-queue") == 0) {
      dispatch_queue_t queue = dispatch_queue_create("arlen.tsan.serial", DISPATCH_QUEUE_SERIAL);
      for (int i = 0; i < 10000; i++) {
        dispatch_async(queue, ^{ protectedCounter++; });
        // Alternate enqueueing with drains so worker reference-count releases
        // overlap the producer's global-object checks on subsequent pushes.
        dispatch_sync(queue, ^{});
      }
      printf("probe-complete:serial-queue protected=%d\n", protectedCounter);
      return protectedCounter == 10000 ? 0 : 4;
    }
    if (strcmp(mode, "kvc") == 0) {
      kvcProbe = [ALNTSANKVCProbe new];
      Method method = class_getInstanceMethod([ALNTSANKVCProbe class], @selector(value));
      IMP original = method_getImplementation(method);
      const char *types = method_getTypeEncoding(method);
      pthread_t reader;
      if (pthread_create(&reader, NULL, worker, NULL) != 0) return 2;
      for (int i = 0; i < 10000; i++) {
        class_replaceMethod([ALNTSANKVCProbe class], @selector(value),
            i % 2 ? original : (IMP)ALNTSANKVCReplacement, types);
        // Exercise the cache invalidation epoch used by dynamic class updates.
        __c11_atomic_fetch_add(&objc_method_cache_version, 1, __ATOMIC_SEQ_CST);
        if ([[kvcProbe valueForKey:@"value"] intValue] != 42) return 4;
      }
      void *result = NULL;
      if (pthread_join(reader, &result) != 0 || result) return 4;
      puts("probe-complete:kvc");
      return 0;
    }
    if (strcmp(mode, "task-signal") == 0) {
      // Initialize NSTask's handler before concurrently delivering SIGCHLD.
      (void)[NSTask new];
      pthread_t signalThread;
      if (pthread_create(&signalThread, NULL, worker, NULL) != 0) return 2;
      for (int i = 0; i < 32; i++) {
        NSTask *task = [NSTask new];
        task.launchPath = @"/bin/true";
        [task launch];
        [task waitUntilExit];
        if (task.terminationStatus != 0) return 4;
      }
      if (pthread_join(signalThread, NULL) != 0) return 3;
      puts("probe-complete:task-signal");
      return 0;
    }
    if (strcmp(mode, "group") == 0 || strcmp(mode, "group-notify") == 0) {
      for (int trial = 0; trial < 100; trial++) {
        int *results = calloc(9, sizeof(int));
        if (!results) return 2;
        dispatch_group_t group = dispatch_group_create();
        for (int i = 0; i < 8; i++) {
          dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            results[i] = i + 1;
          });
        }
        dispatch_semaphore_t notified = dispatch_semaphore_create(0);
        if (strcmp(mode, "group-notify") == 0) {
          dispatch_group_notify(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            for (int i = 0; i < 8; i++) results[8] += results[i];
            dispatch_semaphore_signal(notified);
          });
        }
        if (dispatch_group_wait(group, DISPATCH_TIME_FOREVER) != 0) return 4;
        if (strcmp(mode, "group-notify") == 0) {
          if (dispatch_semaphore_wait(notified, DISPATCH_TIME_FOREVER) != 0 || results[8] != 36) return 4;
        }
        for (int i = 0; i < 8; i++) if (results[i] != i + 1) return 4;
        // Completed groups also exercise the immediate-return acquire path.
        if (dispatch_group_wait(group, DISPATCH_TIME_NOW) != 0) return 4;
        free(results);
      }
      printf("probe-complete:%s\n", mode);
      return 0;
    }
    if (strcmp(mode, "dispatch") == 0) {
      dispatch_apply(64, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
        dispatch_once(&valueOnce, ^{ onceValue = @42; });
        [lock lock];
        if ([onceValue intValue] == 42) protectedCounter++;
        [lock unlock];
      });
      printf("probe-complete:dispatch protected=%d\n", protectedCounter);
      return protectedCounter == 64 ? 0 : 4;
    }
    if (strcmp(mode, "queue") == 0 || strcmp(mode, "queue-idle") == 0) {
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
      if (strcmp(mode, "queue-idle") == 0) {
        // GNUstep retires idle queue workers after five seconds. Crossing that
        // boundary exercises its condition-lock versus queue-lock ordering.
        NSCondition *idle = [NSCondition new];
        [idle lock];
        [idle waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:6.0]];
        [idle unlock];
        [queue addOperationWithBlock:^{
          [lock lock]; protectedCounter++; [lock unlock];
        }];
        [queue waitUntilAllOperationsAreFinished];
      }
      printf("probe-complete:%s protected=%d\n", mode, protectedCounter);
      return protectedCounter == (strcmp(mode, "queue-idle") == 0 ? 17 : 16) ? 0 : 4;
    }
    pthread_t thread;
    if (pthread_create(&thread, NULL, worker, NULL) != 0) { return 2; }
    void *mainResult = worker(NULL);
    void *threadResult = NULL;
    if (pthread_join(thread, &threadResult) != 0) { return 3; }
    if (mainResult || threadResult) { return 4; }
    printf("probe-complete:%s protected=%d\n", mode, protectedCounter);
    if (strcmp(mode, "canary") != 0 && protectedCounter != (strcmp(mode, "semaphore") == 0 ? 20000 : 200)) { return 4; }
  }
  return 0;
}

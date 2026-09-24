#import <Foundation/Foundation.h>
#import <pthread.h>
#import <stdint.h>
#import <stdio.h>
#import <stdlib.h>

#import "ALNSQLBuilder.h"

// Regression probe for issue #49: ALNSQLBuilder's placeholder/identifier
// regexes and operator sets are process-wide lazy statics. If two threads race
// to create one, the losing store releases an object the other thread is still
// using (use-after-free in ICU). Each process gets exactly one first use, so
// the test runs this probe in many fresh processes with every thread released
// onto its first build at once.

enum { ALNProbeMaxThreads = 64, ALNProbeBuildsPerThread = 20 };

static pthread_mutex_t gGateLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t gGateCondition = PTHREAD_COND_INITIALIZER;
static unsigned gArrived = 0;
static unsigned gParticipants = 0;
static NSString *gResults[ALNProbeMaxThreads];

static void WaitForAll(void) {
  pthread_mutex_lock(&gGateLock);
  if (++gArrived == gParticipants) {
    pthread_cond_broadcast(&gGateCondition);
  } else {
    while (gArrived < gParticipants) pthread_cond_wait(&gGateCondition, &gGateLock);
  }
  pthread_mutex_unlock(&gGateLock);
}

static NSString *BuildOnce(void) {
  // Touches both regexes (identifier tokens and $N placeholders) plus the
  // comparison and join operator sets.
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"accounts" alias:@"a" columns:@[ @"a.id" ]];
  [builder joinTable:@"profiles"
               alias:@"p"
         onLeftField:@"a.id"
            operator:@"="
        onRightField:@"p.account_id"];
  [builder whereExpression:@"{{col}} = $1 AND a.id > $2"
        identifierBindings:@{ @"col" : @"a.email" }
                parameters:@[ @"person@example.com", @7 ]];
  [builder whereField:@"a.status" operator:@"!=" value:@"closed"];
  NSError *error = nil;
  NSString *sql = [builder buildSQL:&error];
  if (sql == nil) {
    // Only the code: -description can itself deadlock in class initialization
    // while other threads are still starting up.
    fprintf(stderr, "build failed: code %ld\n", (long)[error code]);
  }
  return sql;
}

static void *Run(void *argument) {
  unsigned index = (unsigned)(uintptr_t)argument;
  WaitForAll();
  NSString *first = nil;
  for (unsigned build = 0; build < ALNProbeBuildsPerThread; build++) {
    @autoreleasepool {
      NSString *sql = BuildOnce();
      if (sql == nil || (first != nil && ![first isEqualToString:sql])) {
        return NULL;
      }
      if (first == nil) first = [sql copy];
    }
  }
  gResults[index] = first;
  return NULL;
}

int main(int argc, char **argv) {
  @autoreleasepool {
    int requestedThreads = argc >= 2 ? atoi(argv[1]) : 32;
    if (requestedThreads < 1 || requestedThreads > ALNProbeMaxThreads) {
      fprintf(stderr, "usage: %s [threads 1..%d]\n", argv[0], ALNProbeMaxThreads);
      return 2;
    }

    unsigned threads = (unsigned)requestedThreads;
    gParticipants = threads;
    pthread_t handles[ALNProbeMaxThreads];
    for (unsigned index = 0; index < threads; index++) {
      if (pthread_create(&handles[index], NULL, Run, (void *)(uintptr_t)index) != 0) return 3;
    }
    for (unsigned index = 0; index < threads; index++) {
      pthread_join(handles[index], NULL);
    }
    for (unsigned index = 0; index < threads; index++) {
      if (gResults[index] == nil || ![gResults[index] isEqualToString:gResults[0]]) {
        fprintf(stderr, "lazy static first-use probe failed on thread %u\n", index);
        return 1;
      }
    }
    printf("lazy static first-use probe passed: %u threads\n", threads);
  }
  return 0;
}

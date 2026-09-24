#import <Foundation/Foundation.h>
#import <pthread.h>
#import <stdint.h>
#import <stdio.h>
#import <stdlib.h>

#import "ALNMetrics.h"
#import "ALNPg.h"

// Regression probe for gnustep/libobjc2#424: the first @synchronized on an
// instance publishes its lock before initializing it, so concurrent first use
// can hang, lose mutual exclusion, or abort in glibc. Every round creates fresh
// objects and releases all threads at once onto their first lock acquisition.

enum { ALNProbeMaxThreads = 64 };

static pthread_mutex_t gBarrierLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t gBarrierCondition = PTHREAD_COND_INITIALIZER;
static unsigned gArrived = 0;
static unsigned gGeneration = 0;
static unsigned gParticipants = 0;
static unsigned gWorkers = 0;
static unsigned gRounds = 0;

static ALNMetricsRegistry *gRegistry = nil;
static ALNPg *gPool = nil;
static BOOL gInvalid[ALNProbeMaxThreads];

static void WaitForAll(void) {
  pthread_mutex_lock(&gBarrierLock);
  unsigned current = gGeneration;
  if (++gArrived == gParticipants) {
    gArrived = 0;
    gGeneration++;
    pthread_cond_broadcast(&gBarrierCondition);
  } else {
    while (current == gGeneration) pthread_cond_wait(&gBarrierCondition, &gBarrierLock);
  }
  pthread_mutex_unlock(&gBarrierLock);
}

static void *Run(void *argument) {
  unsigned index = (unsigned)(uintptr_t)argument;
  for (unsigned round = 0; round < gRounds; round++) {
    // Thread 0 publishes this round's fresh objects between the two barriers.
    WaitForAll();
    WaitForAll();
    @autoreleasepool {
      if ((index % 2) == 0) {
        [gRegistry addGauge:@"first_use" delta:1.0];
      } else {
        [gRegistry incrementCounter:@"first_use"];
      }
      NSError *error = nil;
      ALNPgConnection *connection = [gPool acquireConnection:&error];
      if (connection != nil || error == nil) {
        gInvalid[index] = YES;
      }
    }
    WaitForAll();
    if (index == 0) {
      @autoreleasepool {
        NSDictionary *snapshot = [gRegistry snapshot];
        double gauge = [snapshot[@"gauges"][@"first_use"] doubleValue];
        double counter = [snapshot[@"counters"][@"first_use"] doubleValue];
        unsigned evens = (gWorkers + 1) / 2;
        if (gauge != (double)evens || counter != (double)(gWorkers - evens)) {
          fprintf(stderr, "lost update in round %u: gauge=%.0f counter=%.0f\n", round, gauge, counter);
          gInvalid[index] = YES;
        }
      }
    }
  }
  return NULL;
}

static void *RunCoordinator(void *argument) {
  (void)argument;
  for (unsigned round = 0; round < gRounds; round++) {
    WaitForAll();
    @autoreleasepool {
      gRegistry = [[ALNMetricsRegistry alloc] init];
      NSError *error = nil;
      // A missing Unix socket directory fails fast without a live server, but
      // still exercises the pool lock on every acquire.
      gPool = [[ALNPg alloc] initWithConnectionString:@"host=/nonexistent/arlen-probe connect_timeout=1"
                                       maxConnections:4
                                                error:&error];
    }
    WaitForAll();
    WaitForAll();
  }
  return NULL;
}

int main(int argc, char **argv) {
  @autoreleasepool {
    int requestedWorkers = argc >= 2 ? atoi(argv[1]) : 16;
    int requestedRounds = argc >= 3 ? atoi(argv[2]) : 2000;
    if (requestedWorkers < 1 || requestedWorkers > ALNProbeMaxThreads || requestedRounds < 1) {
      fprintf(stderr, "usage: %s [threads 1..%d] [rounds]\n", argv[0], ALNProbeMaxThreads);
      return 2;
    }

    // The coordinator is an extra barrier participant that never takes the
    // locks under test.
    unsigned workers = (unsigned)requestedWorkers;
    gWorkers = workers;
    gRounds = (unsigned)requestedRounds;
    gParticipants = workers + 1;
    pthread_t threads[ALNProbeMaxThreads + 1];
    for (unsigned index = 0; index < workers; index++) {
      if (pthread_create(&threads[index], NULL, Run, (void *)(uintptr_t)index) != 0) return 3;
    }
    if (pthread_create(&threads[workers], NULL, RunCoordinator, NULL) != 0) return 3;
    for (unsigned index = 0; index <= workers; index++) {
      pthread_join(threads[index], NULL);
    }
    for (unsigned index = 0; index < workers; index++) {
      if (gInvalid[index]) {
        fprintf(stderr, "instance lock first-use probe failed on thread %u\n", index);
        return 1;
      }
    }
    printf("instance lock first-use rounds passed: %u threads x %u rounds\n", workers, gRounds);
  }
  return 0;
}

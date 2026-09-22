// Compiled with freshly generated models by ORMCodegenTests, then exec'd for
// each trial so no earlier test or parent process can warm the descriptors.
#import <Foundation/Foundation.h>
#import <pthread.h>
#import <stdint.h>
#import <stdio.h>
#import <stdlib.h>
#import <unistd.h>
#import "ColdGeneratedModels.h"

static pthread_mutex_t gateLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t gateCondition = PTHREAD_COND_INITIALIZER;
static unsigned participants, arrived, generation;
static ALNORMModelDescriptor *retainedDescriptors[2][32];
static BOOL invalid[32];

static void WaitForAllThreads(void) {
  pthread_mutex_lock(&gateLock);
  unsigned current = generation;
  if (++arrived == participants) {
    arrived = 0;
    generation++;
    pthread_cond_broadcast(&gateCondition);
  } else {
    while (current == generation) pthread_cond_wait(&gateCondition, &gateLock);
  }
  pthread_mutex_unlock(&gateLock);
}

static void *UseDescriptors(void *argument) {
  NSUInteger index = (NSUInteger)(uintptr_t)argument;
  for (NSUInteger model = 0; model < 2; model++) {
    @autoreleasepool {
      // Every worker reaches the barrier without calling either descriptor.
      WaitForAllThreads();
      ALNORMModelDescriptor *descriptor = model == 0
          ? [ColdPublicWidgetsModel modelDescriptor] : [ColdPublicGadgetsModel modelDescriptor];
      retainedDescriptors[model][index] = descriptor;
      NSString *entity = model == 0 ? @"public.widgets" : @"public.gadgets";
      if (![descriptor.entityName isEqualToString:entity] || descriptor.fields.count != 1 ||
          ![descriptor.primaryKeyFieldNames isEqualToArray:@[@"id"]] ||
          ![[descriptor fieldNamed:@"id"].dataType isEqualToString:@"uuid"]) {
        invalid[index] = YES;
      }
      // Repeated reads must retain the same identity while other threads race.
      for (NSUInteger repeat = 0; repeat < 100; repeat++) {
        ALNORMModelDescriptor *again = model == 0
            ? [ColdPublicWidgetsModel modelDescriptor] : [ColdPublicGadgetsModel modelDescriptor];
        if (again != descriptor) invalid[index] = YES;
      }
    }
  }
  return NULL;
}

int main(int argc, char **argv) {
  @autoreleasepool {
#if !defined(_WIN32)
    alarm(30); // Turn a deadlock into an actionable subprocess test failure.
#endif
    participants = argc == 2 ? (unsigned)atoi(argv[1]) : 32;
    if (participants != 1 && participants != 32) return 2;
    pthread_t threads[32];
    for (unsigned index = 0; index < participants; index++) {
      if (pthread_create(&threads[index], NULL, UseDescriptors, (void *)(uintptr_t)index) != 0) return 3;
    }
    for (unsigned index = 0; index < participants; index++) pthread_join(threads[index], NULL);
    // References remain strongly held after all worker autorelease pools drain.
    for (unsigned index = 0; index < participants; index++) {
      for (unsigned model = 0; model < 2; model++) {
        if (invalid[index] || retainedDescriptors[model][index] == nil ||
            retainedDescriptors[model][index] != retainedDescriptors[model][0]) {
          fprintf(stderr, "descriptor identity/contents mismatch: model=%u worker=%u\n", model, index);
          return 4;
        }
      }
    }
    if (retainedDescriptors[0][0] == retainedDescriptors[1][0] ||
        [ColdPublicWidgetsModel modelDescriptor] != retainedDescriptors[0][0] ||
        [ColdPublicGadgetsModel modelDescriptor] != retainedDescriptors[1][0]) return 5;
    puts("cold descriptor identity and ownership passed");
  }
  return 0;
}

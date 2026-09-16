#import <Foundation/Foundation.h>
#import "ALNPostgresJobAdapter.h"
#include <unistd.h>

int main(int argc, const char **argv) {
  @autoreleasepool {
    if (argc < 3) return 2;
    NSString *action = @(argv[1]);
    NSError *error = nil;
    ALNPg *db = [[ALNPg alloc] initWithConnectionString:[NSProcessInfo processInfo].environment[@"ARLEN_PG_TEST_DSN"]
                                       maxConnections:2 error:&error];
    ALNPostgresJobAdapter *adapter = [[ALNPostgresJobAdapter alloc] initWithDatabase:db namespace:@(argv[2])
        leaseDurationSeconds:2 error:&error];
    if (!adapter) { fprintf(stderr,"%s\n",error.description.UTF8String); return 3; }
    if ([action isEqual:@"produce"]) {
      for (int i=0; i<25; i++) {
        NSString *jobID = [adapter enqueueJobNamed:@"synthetic" payload:@{@"index":@(i)} options:nil error:&error];
        if (!jobID) { fprintf(stderr,"%s\n",error.description.UTF8String); return 4; }
        printf("%s\n",jobID.UTF8String);
      }
    } else if ([action isEqual:@"duplicate"]) {
      NSString *jobID = [adapter enqueueJobNamed:@"synthetic" payload:@{} options:@{@"idempotencyKey":@"shared-key"} error:&error];
      if (!jobID) return 4;
      printf("%s\n",jobID.UTF8String);
    } else if ([action isEqual:@"consume"] || [action isEqual:@"crash"]) {
      for (int i=0; i<200; i++) {
        ALNJobLease *job = (ALNJobLease *)[adapter dequeueDueJobAt:[NSDate date] error:&error];
        if (error) { fprintf(stderr,"%s\n",error.description.UTF8String); return 5; }
        if (!job) break;
        if ([action isEqual:@"crash"]) {
          printf("%s\n",job.jobID.UTF8String); fflush(stdout);
          for (;;) pause();
        }
        if (![adapter completeJob:job result:@{@"process":@((int)getpid())} error:&error]) return 6;
        printf("%s\n",job.jobID.UTF8String);
      }
    } else return 2;
    return 0;
  }
}

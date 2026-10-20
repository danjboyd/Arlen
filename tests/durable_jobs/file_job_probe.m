#import <Foundation/Foundation.h>
#import "ALNServices.h"

int main(int argc, const char **argv) {
  @autoreleasepool {
    if (argc != 3) return 2;
    NSError *error = nil;
    ALNFileJobAdapter *adapter = [[ALNFileJobAdapter alloc] initWithStoragePath:@(argv[2])
                                                               adapterName:nil error:&error];
    if (!adapter) { fprintf(stderr, "%s: %s\n", argv[2], error.description.UTF8String); return 3; }
    if ([@(argv[1]) isEqualToString:@"produce"]) {
      for (NSUInteger i = 0; i < 50; i++) {
        NSString *jobID = [adapter enqueueJobNamed:@"test" payload:@{} options:nil error:&error];
        if (!jobID) return 4;
        printf("%s\n", jobID.UTF8String);
      }
    } else if ([@(argv[1]) isEqualToString:@"consume"]) {
      for (;;) {
        ALNJobEnvelope *job = [adapter dequeueDueJobAt:[NSDate dateWithTimeIntervalSinceNow:1] error:&error];
        if (error) return 5;
        if (!job) break;
        if (![adapter acknowledgeJobID:job.jobID error:&error]) return 6;
        printf("%s\n", job.jobID.UTF8String);
      }
    } else return 2;
    return 0;
  }
}

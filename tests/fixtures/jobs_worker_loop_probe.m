#import <Foundation/Foundation.h>
#import "ALNAppRunner.h"
#import "ALNApplication.h"

// A separate process supplies only the runtime protocol used by the CLI loop.
// It links the real framework archive, not the jobs module or a copied loop.
static NSString *scenario;
static NSUInteger created, destroyed, polls, ticks, previousIterationObjects;
static BOOL missedDrain;

@interface LoopLifetimeMarker : NSObject
@end
@implementation LoopLifetimeMarker
- (instancetype)init {
  if ((self = [super init])) created++;
  return self;
}
- (void)dealloc { destroyed++; }
@end

static void AutoreleaseMarker(void) {
  // Volatile makes the autoreleasing store observable under optimized ARC.
  // The marker must stay in the current pool after this function returns.
  __autoreleasing id volatile marker = [[LoopLifetimeMarker alloc] init];
  (void)marker;
}

static void CheckPreviousIteration(void) {
  if (destroyed < previousIterationObjects) missedDrain = YES;
}

@interface ALNJobsModuleRuntime : NSObject
@property(nonatomic, strong) ALNApplication *application;
+ (instancetype)sharedRuntime;
@end

@implementation ALNJobsModuleRuntime
+ (instancetype)sharedRuntime {
  static ALNJobsModuleRuntime *runtime;
  if (runtime == nil) runtime = [[self alloc] init];
  return runtime;
}
- (NSDictionary *)runSchedulerAt:(NSDate *)date error:(NSError **)error {
  (void)date;
  CheckPreviousIteration();
  ticks++;
  AutoreleaseMarker();
  if ([scenario isEqualToString:@"scheduler-error"]) {
    if (error) *error = [NSError errorWithDomain:@"loop-probe" code:1
                                      userInfo:@{NSLocalizedDescriptionKey: @"scheduler fixture failure"}];
    return nil;
  }
  return @{};
}
- (NSDictionary *)runWorkerAt:(NSDate *)date limit:(NSUInteger)limit error:(NSError **)error {
  (void)date;
  (void)limit;
  CheckPreviousIteration();
  polls++;
  AutoreleaseMarker();
  previousIterationObjects = created;
  if (polls == 4 || [scenario isEqualToString:@"worker-error"]) {
    if (error) *error = [NSError errorWithDomain:@"loop-probe" code:2
                                      userInfo:@{NSLocalizedDescriptionKey: @"worker fixture stop"}];
    return nil;
  }
  return @{ @"acknowledgedCount": @([scenario isEqualToString:@"busy"] ? 1 : 0),
            @"reachedRunLimit": @([scenario isEqualToString:@"limit"]) };
}
@end

static void RegisterApplication(ALNApplication *application) {
  [ALNJobsModuleRuntime sharedRuntime].application = application;
}

int main(int argc, const char **argv) {
  @autoreleasepool {
    if (argc != 2) return 2;
    scenario = [NSString stringWithUTF8String:argv[1]];
    BOOL once = [scenario isEqualToString:@"once"];
    BOOL scheduler = [scenario isEqualToString:@"scheduler"] ||
                     [scenario isEqualToString:@"scheduler-error"];
    const char *args[12] = {"loop-probe", "--env", "test", "--jobs-worker",
                           "--jobs-worker-poll-interval-seconds", "0"};
    int count = 6;
    if (once) args[count++] = "--jobs-worker-once";
    if (scheduler) {
      args[count++] = "--jobs-worker-run-scheduler";
      args[count++] = "--jobs-worker-scheduler-interval-seconds";
      args[count++] = "0";
    }
    int status = ALNRunAppMain(count, args, &RegisterApplication);
    printf("{\"status\":%d,\"polls\":%lu,\"ticks\":%lu,\"created\":%lu,"
           "\"destroyed\":%lu,\"missedDrain\":%s}\n", status, (unsigned long)polls,
           (unsigned long)ticks, (unsigned long)created, (unsigned long)destroyed,
           missedDrain ? "true" : "false");
    return status == (once ? 0 : 1) && created > 0 && created == destroyed && !missedDrain ? 0 : 70;
  }
}

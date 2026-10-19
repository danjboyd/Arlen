#ifndef ALN_TEST_PROCESS_CHECKPOINT_H
#define ALN_TEST_PROCESS_CHECKPOINT_H

#import "ALNTestWait.h"
#if !defined(_WIN32)
#include <signal.h>
#endif

// Files avoid blocking pipe reads and pipe-capacity/SIGPIPE failure modes.
// Every wait is bounded; unique fixture directories prevent stale signals.
static BOOL ALNTestSignalCheckpoint(NSString *path, NSString *name) {
  return [@"ready" writeToFile:[path stringByAppendingFormat:@".%@", name]
                   atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}
static BOOL ALNTestWaitCheckpoint(NSString *path, NSString *name) {
  NSString *checkpoint = [path stringByAppendingFormat:@".%@", name];
  return ALNTestWaitUntil(15.0, 0.02, ^BOOL {
    return [[NSFileManager defaultManager] fileExistsAtPath:checkpoint];
  });
}
static BOOL ALNTestReapChild(NSTask *task) {
  @try {
    if (!task.isRunning) return ALNTestWaitForTaskExit(task, 1.0);
    [task terminate];
    if (ALNTestWaitForTaskExit(task, 2.0)) return YES;
#if !defined(_WIN32)
    kill(task.processIdentifier, SIGKILL);
#else
    [task terminate];
#endif
    return ALNTestWaitForTaskExit(task, 3.0);
  } @catch (NSException *exception) {
    return NO;
  }
}

#endif

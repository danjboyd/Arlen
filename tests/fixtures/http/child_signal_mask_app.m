#import <Foundation/Foundation.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
#import "ArlenServer.h"
#import "ALNAppRunner.h"
#import "ALNController.h"
#import "ALNContext.h"
#import "ALNResponse.h"

extern char **environ;

// Reports which stop signals a child process started from a request thread has
// blocked. posix_spawn is what glibc's system() and popen() use, and it runs
// no pthread_atfork handlers, so the child inherits the request thread's mask.
// grep is spawned directly: dash resets the mask when `sh -c` execs a single
// command in place, which would hide the inherited mask.
@interface ChildSignalMaskController : ALNController
@end
@implementation ChildSignalMaskController
- (id)childMask:(ALNContext *)ctx {
  (void)ctx;
  int pipeFDs[2];
  if (pipe(pipeFDs) != 0) {
    return @{ @"error" : @"pipe" };
  }
  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  posix_spawn_file_actions_adddup2(&actions, pipeFDs[1], STDOUT_FILENO);
  posix_spawn_file_actions_addclose(&actions, pipeFDs[0]);
  char *argv[] = { "grep", "^SigBlk:", "/proc/self/status", NULL };
  pid_t pid = 0;
  int rc = posix_spawnp(&pid, "grep", &actions, NULL, argv, environ);
  posix_spawn_file_actions_destroy(&actions);
  close(pipeFDs[1]);
  NSMutableData *output = [NSMutableData data];
  uint8_t buffer[256];
  ssize_t count = 0;
  while ((count = read(pipeFDs[0], buffer, sizeof(buffer))) > 0) {
    [output appendBytes:buffer length:(NSUInteger)count];
  }
  close(pipeFDs[0]);
  if (rc != 0) {
    return @{ @"error" : @"spawn" };
  }
  int status = 0;
  (void)waitpid(pid, &status, 0);
  NSString *line = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] ?: @"";
  NSString *hex = [[line stringByReplacingOccurrencesOfString:@"SigBlk:" withString:@""]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  unsigned long long mask = strtoull([hex UTF8String], NULL, 16);
  sigset_t threadMask;
  pthread_sigmask(SIG_SETMASK, NULL, &threadMask);
  return @{
    @"request_thread_sigterm_blocked" : @(sigismember(&threadMask, SIGTERM) == 1 ? 1 : 0),
    @"request_thread_is_main" : @([NSThread isMainThread] ? 1 : 0),
    @"sigblk" : hex,
    @"sigint_blocked" : @((mask >> (SIGINT - 1)) & 1ULL),
    @"sigterm_blocked" : @((mask >> (SIGTERM - 1)) & 1ULL),
  };
}
@end

static void RegisterRoutes(ALNApplication *app) {
  [app registerRouteMethod:@"GET"
                      path:@"/child-mask"
                      name:nil
           controllerClass:[ChildSignalMaskController class]
                    action:@"childMask"];
}

int main(int argc, const char *argv[]) {
  @autoreleasepool { return ALNRunAppMain(argc, argv, &RegisterRoutes); }
}

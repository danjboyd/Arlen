// CI-only executable: the normal boomhauer binary has no publishing control pipe.
#define main ArlenConcurrencyFixtureServerMain
#include "boomhauer.m"
#undef main
#import "ALNRealtime.h"
#include <pthread.h>
#include <unistd.h>
#include <errno.h>
#include <limits.h>

static void *PublishFromTrustedPipe(void *context) {
  int fd = *(int *)context;
  free(context);
  unsigned char command;
  for (;;) {
    ssize_t count = read(fd, &command, 1);
    if (count < 0 && errno == EINTR) continue;
    if (count != 1) break;
    if (command == 'P') {
      @autoreleasepool {
        [[ALNRealtimeHub sharedHub] publishMessage:@"runtime-server-fanout"
                                       onChannel:@"runtime-gate"];
      }
    }
  }
  close(fd);
  return NULL;
}

int main(int argc, const char *argv[]) {
  const char *raw = getenv("ARLEN_CONCURRENCY_PUBLISH_FD");
  char *end = NULL;
  long value = raw ? strtol(raw, &end, 10) : -1;
  if (!raw || end == raw || *end || value < 3 || value > INT_MAX) return 2;
  int *fd = malloc(sizeof(*fd));
  if (!fd) return 2;
  *fd = (int)value;
  pthread_t producer;
  if (pthread_create(&producer, NULL, PublishFromTrustedPipe, fd) != 0) {
    free(fd);
    return 2;
  }
  pthread_detach(producer);
  return ArlenConcurrencyFixtureServerMain(argc, argv);
}

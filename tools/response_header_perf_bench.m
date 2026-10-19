#import <Foundation/Foundation.h>
#import "ALNContext.h"
#import "ALNResponse.h"
#import "ALNSecurityHeadersMiddleware.h"
#include <stdlib.h>
#include <time.h>
#ifdef _WIN32
#include <windows.h>
#endif

static double Seconds(void) {
#ifdef _WIN32
  LARGE_INTEGER now, frequency;
  QueryPerformanceCounter(&now);
  QueryPerformanceFrequency(&frequency);
  return (double)now.QuadPart / (double)frequency.QuadPart;
#else
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (double)now.tv_sec + (double)now.tv_nsec / 1e9;
#endif
}

int main(int argc, const char **argv) {
  @autoreleasepool {
    NSUInteger iterations = argc > 1 ? (NSUInteger)strtoull(argv[1], NULL, 10) : 100000;
    if (iterations == 0) return 2;
    ALNSecurityHeadersMiddleware *middleware = [[ALNSecurityHeadersMiddleware alloc]
        initWithContentSecurityPolicy:@"default-src 'self'; img-src 'self' data:"];
    for (NSString *mode in @[@"middleware", @"dynamic32"]) {
      NSMutableArray *names = [NSMutableArray array];
      for (NSUInteger index = 0; index < 32; index++) {
        [names addObject:[NSString stringWithFormat:@"X-Bench-%02lu", (unsigned long)(31 - index)]];
      }
      NSUInteger bytes = 0;
      double start = 0;
      for (NSUInteger index = 0; index < iterations + 2000; index++) {
        if (index == 2000) start = Seconds();
        @autoreleasepool {
          ALNResponse *response = [[ALNResponse alloc] init];
          if ([mode isEqualToString:@"middleware"]) {
            ALNContext *context = [[ALNContext alloc] initWithRequest:nil response:response
                params:@{} stash:[NSMutableDictionary dictionary] logger:nil perfTrace:nil
                routeName:nil controllerName:nil actionName:nil];
            [middleware processContext:context error:NULL];
          } else {
            for (NSString *name in names) [response setHeader:name value:@"safe unicode caf\u00e9"];
          }
          NSUInteger length = [[response serializedHeaderData] length];
          if (index >= 2000) bytes += length;
        }
      }
      double elapsed = Seconds() - start;
      printf("%s iterations=%lu us_per_response=%.3f bytes=%lu\n", [mode UTF8String],
             (unsigned long)iterations, elapsed * 1e6 / iterations, (unsigned long)bytes);
    }
  }
  return 0;
}

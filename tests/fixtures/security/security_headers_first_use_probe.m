#import <Foundation/Foundation.h>
#import <pthread.h>
#import <stdint.h>
#import <stdio.h>
#import <stdlib.h>

#import "ALNContext.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNSecurityHeadersMiddleware.h"

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t condition = PTHREAD_COND_INITIALIZER;
static unsigned arrived = 0;
static unsigned generation = 0;
static unsigned participants = 0;
static ALNSecurityHeadersMiddleware *middleware = nil;
static ALNSecurityHeadersMiddleware *customMiddleware = nil;
static NSDictionary *expectedHeaders = nil;
static ALNContext *contexts[32];
static ALNResponse *responses[32];
static BOOL invalid[32];

static void WaitForAll(void) {
  pthread_mutex_lock(&lock);
  unsigned current = generation;
  if (++arrived == participants) {
    arrived = 0;
    generation++;
    pthread_cond_broadcast(&condition);
  } else {
    while (current == generation) pthread_cond_wait(&condition, &lock);
  }
  pthread_mutex_unlock(&lock);
}

static void *Run(void *argument) {
  unsigned index = (unsigned)(uintptr_t)argument;
  @autoreleasepool {
    WaitForAll();
    NSError *error = nil;
    if (![middleware processContext:contexts[index] error:&error] || error != nil) invalid[index] = YES;
    for (NSString *name in expectedHeaders) {
      if (![[responses[index] headerForName:name] isEqual:expectedHeaders[name]]) invalid[index] = YES;
    }
    if (![[responses[index] headerForName:@"Content-Security-Policy"] isEqual:@"default-src 'self'"]) invalid[index] = YES;
    // Explicit app response headers must survive both middleware configurations.
    [responses[index] setHeader:@"X-Frame-Options" value:@"DENY"];
    [responses[index] removeHeaderForName:@"Content-Security-Policy"];
    if (![customMiddleware processContext:contexts[index] error:&error] || error != nil ||
        ![[responses[index] headerForName:@"Content-Security-Policy"] isEqual:@"default-src 'none'"] ||
        ![[responses[index] headerForName:@"X-Frame-Options"] isEqual:@"DENY"]) invalid[index] = YES;
    [responses[index] setHeader:@"Content-Security-Policy" value:@"script-src 'self'"];
    if (![middleware processContext:contexts[index] error:&error] || error != nil ||
        ![[responses[index] headerForName:@"Content-Security-Policy"] isEqual:@"script-src 'self'"]) invalid[index] = YES;
  }
  return NULL;
}

int main(int argc, char **argv) {
  @autoreleasepool {
    participants = argc == 2 ? (unsigned)atoi(argv[1]) : 32;
    if (participants != 1 && participants != 32) return 2;
    middleware = [[ALNSecurityHeadersMiddleware alloc] initWithContentSecurityPolicy:nil];
    customMiddleware = [[ALNSecurityHeadersMiddleware alloc] initWithContentSecurityPolicy:@"default-src 'none'"];
    expectedHeaders = @{
      @"X-Content-Type-Options": @"nosniff", @"X-Frame-Options": @"SAMEORIGIN",
      @"Referrer-Policy": @"strict-origin-when-cross-origin",
      @"Cross-Origin-Opener-Policy": @"same-origin",
      @"Cross-Origin-Resource-Policy": @"same-site",
      @"X-Permitted-Cross-Domain-Policies": @"none",
    };
    for (unsigned index = 0; index < participants; index++) {
      ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"GET" path:@"/"
          queryString:@"" headers:@{} body:[NSData data]];
      responses[index] = [[ALNResponse alloc] init];
      contexts[index] = [[ALNContext alloc] initWithRequest:request response:responses[index]
          params:@{} stash:[NSMutableDictionary dictionary] logger:nil perfTrace:nil
          routeName:@"probe" controllerName:@"probe" actionName:@"probe"];
    }
    pthread_t threads[32];
    for (unsigned index = 0; index < participants; index++) {
      if (pthread_create(&threads[index], NULL, Run, (void *)(uintptr_t)index) != 0) return 3;
    }
    for (unsigned index = 0; index < participants; index++) pthread_join(threads[index], NULL);
    for (unsigned index = 0; index < participants; index++) if (invalid[index]) return 4;
    puts("security header first-use requests passed");
  }
  return 0;
}

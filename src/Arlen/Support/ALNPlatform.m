#import "ALNPlatform.h"

NSString *ALNPlatformName(void) {
#if defined(__APPLE__)
  return @"apple";
#elif defined(__linux__)
  return @"linux";
#else
  return @"unknown";
#endif
}

BOOL ALNPlatformUsesAppleFoundation(void) {
#if defined(__APPLE__)
  return YES;
#else
  return NO;
#endif
}

BOOL ALNPlatformUsesGNUstepFoundation(void) {
#if defined(GNUSTEP)
  return YES;
#else
  return NO;
#endif
}

NSArray<NSString *> *ALNDefaultLibpqCandidatePaths(void) {
  NSMutableArray<NSString *> *candidates = [NSMutableArray array];

#if defined(__APPLE__)
  [candidates addObject:@"/opt/homebrew/opt/libpq/lib/libpq.5.dylib"];
  [candidates addObject:@"/opt/homebrew/opt/libpq/lib/libpq.dylib"];
  [candidates addObject:@"/opt/homebrew/opt/postgresql/lib/libpq.5.dylib"];
  [candidates addObject:@"/opt/homebrew/opt/postgresql/lib/libpq.dylib"];
  [candidates addObject:@"/usr/local/opt/libpq/lib/libpq.5.dylib"];
  [candidates addObject:@"/usr/local/opt/libpq/lib/libpq.dylib"];
  [candidates addObject:@"/usr/local/opt/postgresql/lib/libpq.5.dylib"];
  [candidates addObject:@"/usr/local/opt/postgresql/lib/libpq.dylib"];
  [candidates addObject:@"libpq.5.dylib"];
  [candidates addObject:@"libpq.dylib"];
#else
  [candidates addObject:@"/usr/lib/x86_64-linux-gnu/libpq.so.5"];
  [candidates addObject:@"libpq.so.5"];
  [candidates addObject:@"libpq.so"];
#endif

  return candidates;
}

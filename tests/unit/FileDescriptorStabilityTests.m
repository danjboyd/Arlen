#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNDataverseClient.h"

#include <limits.h>
#include <unistd.h>

// GitHub issue 67 / ARLEN-BUG-024: framework runtime paths must not accumulate
// descriptors (the incident was ~970 leaked /dev/null descriptors per worker).
// The one subprocess launched by runtime code is the Dataverse curl transport.
@interface FileDescriptorStabilityTests : XCTestCase
@end

@implementation FileDescriptorStabilityTests

// @{ total, dev_null } for this process, or nil where /proc is unavailable.
- (NSDictionary *)descriptorCounts {
  NSArray *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/proc/self/fd" error:NULL];
  if (entries == nil) {
    return nil;
  }
  NSUInteger devNull = 0;
  for (NSString *entry in entries) {
    char target[PATH_MAX];
    NSString *link = [@"/proc/self/fd" stringByAppendingPathComponent:entry];
    ssize_t length = readlink([link fileSystemRepresentation], target, sizeof(target) - 1);
    if (length > 0) {
      target[length] = '\0';
      if (strcmp(target, "/dev/null") == 0) {
        devNull++;
      }
    }
  }
  return @{ @"total" : @([entries count]), @"dev_null" : @(devNull) };
}

- (void)testDataverseCurlTransportReleasesItsDescriptors {
  if ([self descriptorCounts] == nil || ![[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/bin/curl"]) {
    return;  // Linux /proc and curl required.
  }
  ALNDataverseCurlTransport *transport = [[ALNDataverseCurlTransport alloc] initWithTimeoutInterval:2.0];
  ALNDataverseRequest *request = [[ALNDataverseRequest alloc] initWithMethod:@"POST"
                                                                   URLString:@"http://127.0.0.1:1/api/data/v9.2/accounts"
                                                                     headers:@{ @"Accept" : @"application/json" }
                                                                    bodyData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]];
  // Warm up once so lazily created runtime descriptors are not counted as leaks.
  @autoreleasepool {
    (void)[transport executeRequest:request error:NULL];
  }
  NSDictionary *before = [self descriptorCounts];
  for (NSUInteger i = 0; i < 40; i++) {
    @autoreleasepool {
      NSError *error = nil;
      XCTAssertNil([transport executeRequest:request error:&error]);  // connection refused
      XCTAssertNotNil(error);
    }
  }
  NSDictionary *after = [self descriptorCounts];
  XCTAssertLessThanOrEqual([after[@"dev_null"] integerValue], [before[@"dev_null"] integerValue],
                           @"/dev/null descriptors grew: %@ -> %@", before, after);
  XCTAssertLessThanOrEqual([after[@"total"] integerValue], [before[@"total"] integerValue] + 2,
                           @"descriptors grew over 40 launches: %@ -> %@", before, after);
}

@end

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNPlatform.h"
#import "../shared/ALNTestSupport.h"

// ALNPlatformMappedFileData backs spooled request bodies and uploads, and
// ALNPlatformRemoveItemWhenUnmapped removes their spool files. On Windows the
// mapping is CreateFileMappingW/MapViewOfFile (gnustep-base there is built
// without HAVE_MMAP), and a mapped file cannot be deleted until its view is
// released; on POSIX unlink just drops the name.
@interface PlatformMappedFileTests : XCTestCase
@end

@implementation PlatformMappedFileTests

- (NSString *)writeFileOfLength:(NSUInteger)length named:(NSString *)name inDirectory:(NSString *)directory {
  NSMutableData *contents = [NSMutableData dataWithLength:length];
  unsigned char *bytes = contents.mutableBytes;
  for (NSUInteger i = 0; i < length; i++) {
    bytes[i] = (unsigned char)(i * 31 + 7);
  }
  NSString *path = [directory stringByAppendingPathComponent:name];
  XCTAssertTrue([contents writeToFile:path atomically:NO]);
  return path;
}

- (void)testMappedDataHasTheFileContents {
  NSString *directory = ALNTestTemporaryDirectory(@"mapped-contents");
  XCTAssertNotNil(directory);
  NSString *path = [self writeFileOfLength:3 * 65536 + 17 named:@"body" inDirectory:directory];
  NSError *error = nil;
  NSData *mapped = ALNPlatformMappedFileData(path, &error);
  XCTAssertNotNil(mapped, @"%@", error);
  XCTAssertEqualObjects([NSData dataWithContentsOfFile:path], mapped);
  mapped = nil;
  [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

- (void)testEmptyFileMapsToEmptyDataAndMissingFileFails {
  NSString *directory = ALNTestTemporaryDirectory(@"mapped-edges");
  XCTAssertNotNil(directory);
  NSString *empty = [self writeFileOfLength:0 named:@"empty" inDirectory:directory];
  NSError *error = nil;
  NSData *mapped = ALNPlatformMappedFileData(empty, &error);
  XCTAssertNotNil(mapped, @"%@", error);
  XCTAssertEqual((NSUInteger)0, mapped.length);
  error = nil;
  XCTAssertNil(ALNPlatformMappedFileData([directory stringByAppendingPathComponent:@"missing"], &error));
  XCTAssertNotNil(error);
  [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

// Request cleanup removes a spool directory while an upload's data still maps
// a file in it. The data must stay readable, and once it is released both the
// file and the directory must be gone on every platform.
- (void)testRemovingAMappedSpoolDirectoryFinishesWhenTheDataIsReleased {
  NSString *directory = ALNTestTemporaryDirectory(@"mapped-removal");
  XCTAssertNotNil(directory);
  NSString *path = [self writeFileOfLength:200000 named:@"part-0" inDirectory:directory];
  NSData *expected = [NSData dataWithContentsOfFile:path];
  @autoreleasepool {
    NSData *mapped = ALNPlatformMappedFileData(path, NULL);
    XCTAssertNotNil(mapped);
    ALNPlatformRemoveItemWhenUnmapped(directory);
#if defined(_WIN32)
    // Windows refuses to delete a mapped file: it waits for the release.
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:path]);
#else
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:path]);
#endif
    XCTAssertEqualObjects(expected, mapped, @"mapped bytes must stay readable after the removal request");
    mapped = nil;
  }
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:path]);
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:directory]);
}

@end

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#if defined(_WIN32)
#include <windows.h>
#include <aclapi.h>
#else
#include <sys/stat.h>
#endif

// Internal sink used by the socket reader. Keep collision tests independent
// of unpredictable server-generated filenames and of the selected backend.
@interface ALNChunkedReadState : NSObject
- (instancetype)initWithLimit:(NSUInteger)limit threshold:(NSUInteger)threshold path:(NSString *)path;
- (BOOL)appendBytes:(const void *)bytes length:(NSUInteger)length;
- (BOOL)finish;
- (void)discard;
@end

@interface HTTPBodyStreamingTests : XCTestCase
@end

@implementation HTTPBodyStreamingTests
- (NSString *)freshPath {
  return [NSTemporaryDirectory() stringByAppendingPathComponent:
      [@"arlen-body-sink-test-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
}

- (void)testSpoolCollisionPreservesExistingFile {
  NSString *path = [self freshPath];
  NSData *original = [@"existing private contents" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertTrue([original writeToFile:path atomically:NO]);
  @try {
    ALNChunkedReadState *sink = [[ALNChunkedReadState alloc] initWithLimit:32 threshold:1 path:path];
    XCTAssertFalse([sink appendBytes:"new" length:3]);
    XCTAssertEqualObjects(original, [NSData dataWithContentsOfFile:path]);
    [sink discard];
    [sink discard];
    XCTAssertEqualObjects(original, [NSData dataWithContentsOfFile:path]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
  }
}

- (void)testSpooledBinaryBodyIsExactAndDiscardRemovesOwnedFile {
  NSString *path = [self freshPath];
  const unsigned char bytes[] = {0, 255, 13, 10, 128, 1, 2, 3};
  NSData *expected = [NSData dataWithBytes:bytes length:sizeof(bytes)];
  ALNChunkedReadState *sink = [[ALNChunkedReadState alloc] initWithLimit:16 threshold:3 path:path];
  @try {
    XCTAssertTrue([sink appendBytes:bytes length:3]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:path]);
    XCTAssertTrue([sink appendBytes:bytes + 3 length:sizeof(bytes) - 3]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:path]);
    // An oversized segment must not append any of its bytes to the spool.
    XCTAssertFalse([sink appendBytes:"0123456789" length:10]);
    XCTAssertFalse([sink finish]);
    XCTAssertEqualObjects(expected, [NSData dataWithContentsOfFile:path]);
    [sink discard];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:path]);
  } @finally {
    [sink discard];
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
  }
}

- (void)testDecodedLimitRejectsBeforeSpoolCreation {
  NSString *path = [self freshPath];
  ALNChunkedReadState *sink = [[ALNChunkedReadState alloc] initWithLimit:3 threshold:3 path:path];
  XCTAssertTrue([sink appendBytes:"abc" length:3]);
  XCTAssertFalse([sink appendBytes:"d" length:1]);
  [sink discard];
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:path]);
}

- (void)testSpoolIsPrivateBeforeBodyCompletes {
  // Unicode also exercises the native UTF-16 path conversion.
  NSString *path = [[self freshPath] stringByAppendingString:@"-\u03bb"];
  ALNChunkedReadState *sink = [[ALNChunkedReadState alloc] initWithLimit:32 threshold:1 path:path];
  @try {
    XCTAssertTrue([sink appendBytes:"abc" length:3]);
#if defined(_WIN32)
    NSMutableData *wide = [[[path stringByReplacingOccurrencesOfString:@"/" withString:@"\\"]
        dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy];
    [wide appendBytes:"\0\0" length:2];
    PSECURITY_DESCRIPTOR security = NULL;
    PACL acl = NULL;
    DWORD result = GetNamedSecurityInfoW((LPWSTR)wide.mutableBytes, SE_FILE_OBJECT,
        DACL_SECURITY_INFORMATION, NULL, NULL, &acl, NULL, &security);
    XCTAssertEqual((DWORD)ERROR_SUCCESS, result);
    HANDLE token = NULL;
    @try {
      if (result != ERROR_SUCCESS) return;
      SECURITY_DESCRIPTOR_CONTROL control = 0;
      DWORD revision = 0;
      XCTAssertTrue(GetSecurityDescriptorControl(security, &control, &revision));
      XCTAssertTrue((control & SE_DACL_PROTECTED) != 0);
      XCTAssertTrue(acl != NULL);
      if (acl == NULL) return;
      XCTAssertEqual((WORD)1, acl->AceCount);
      XCTAssertTrue(OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token));
      if (token == NULL) return;
      DWORD size = 0;
      GetTokenInformation(token, TokenUser, NULL, 0, &size);
      NSMutableData *user = [NSMutableData dataWithLength:size];
      XCTAssertTrue(GetTokenInformation(token, TokenUser, user.mutableBytes, size, &size));
      void *rawAce = NULL;
      XCTAssertTrue(GetAce(acl, 0, &rawAce));
      if (rawAce == NULL) return;
      ACCESS_ALLOWED_ACE *ace = rawAce;
      XCTAssertEqual((BYTE)ACCESS_ALLOWED_ACE_TYPE, ace->Header.AceType);
      XCTAssertEqual((BYTE)0, ace->Header.AceFlags);
      XCTAssertEqual((DWORD)FILE_ALL_ACCESS, ace->Mask);
      XCTAssertTrue(EqualSid(&ace->SidStart, ((TOKEN_USER *)user.mutableBytes)->User.Sid));
    } @finally {
      if (token != NULL) CloseHandle(token);
      if (security != NULL) LocalFree(security);
    }
#else
    struct stat info;
    XCTAssertEqual(0, stat([path fileSystemRepresentation], &info));
    XCTAssertEqual((mode_t)0600, info.st_mode & 0777);
#endif
    XCTAssertTrue([sink finish]);
  } @finally {
    [sink discard];
  }
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:path]);
}
@end

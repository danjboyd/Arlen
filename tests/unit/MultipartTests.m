#import <XCTest/XCTest.h>
#import "ALNRequest.h"
#import "ALNApplication.h"
#import "ALNResponse.h"
@interface MultipartTests : XCTestCase
@end
@implementation MultipartTests
- (NSData *)body {
  NSMutableData *body = [NSMutableData data];
  [body appendData:[@"--Aa\r\nContent-Disposition: form-data; name=\"tag\"\r\n\r\none\r\n--Aa\r\nContent-Disposition: form-data; name=\"tag\"\r\n\r\n\r\n--Aa\r\nContent-Disposition: form-data; name=\"doc\"; filename=\"../a\\\"b.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
  [body appendData:[self binary]];
  [body appendData:[@"\r\n--Aa\r\nContent-Disposition: form-data; name=\"doc\"; filename=\"\"\r\n\r\n\r\n--Aa--\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
  return body;
}
- (NSData *)binary {
  const unsigned char bytes[] = {0, 255, 128, 13, 10, '-', '-', 'A', 'a', 'X', 13, 10, '-', '-', 'A', 'a', '-', '-', 'X', 1};
  return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}
- (ALNRequest *)request:(NSData *)body {
  return [[ALNRequest alloc] initWithMethod:@"POST" path:@"/" queryString:@""
      headers:@{@"Content-Type":@"multipart/form-data; boundary=\"Aa\""} body:body];
}
- (void)testOrderedFieldsBinaryUploadsAndExplicitFileWrite {
  ALNRequest *request = [self request:self.body];
  XCTAssertEqualObjects(request.body, self.body);
  XCTAssertEqualObjects(request.formParams, (@{@"tag":@""}));
  XCTAssertEqualObjects(request.formValues[@"tag"], (@[@"one", @""]));
  XCTAssertEqual(request.multipartParts.count, 4u);
  XCTAssertEqual(request.uploads.count, 2u);
  ALNUpload *upload = [request uploadsForName:@"doc"][0];
  XCTAssertEqualObjects(upload.data, self.binary);
  XCTAssertEqual(upload.size, self.binary.length);
  XCTAssertEqualObjects(upload.fieldName, @"doc");
  XCTAssertEqualObjects(upload.originalFilename, @"../a\"b.bin");
  XCTAssertEqualObjects(upload.contentType, @"application/octet-stream");
  XCTAssertEqual(request.uploads[1].size, 0u);
  XCTAssertNil(request.multipartError);
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
  @try {
    NSError *error = nil;
    XCTAssertTrue([upload writeToFile:path error:&error]);
    XCTAssertEqualObjects([NSData dataWithContentsOfFile:path], self.binary);
  } @finally { [[NSFileManager defaultManager] removeItemAtPath:path error:NULL]; }
}
- (void)testEachLimitAndAtomicFailure {
  for (NSString *key in [ALNMultipart defaultLimits]) {
    ALNRequest *request = [self request:self.body];
    NSError *error = nil;
    XCTAssertFalse([request parseMultipartFormWithLimits:@{key:@1} error:&error], @"%@", key);
    XCTAssertEqualObjects(error.domain, ALNMultipartErrorDomain);
    XCTAssertEqual(error.code, ALNMultipartErrorLimitExceeded);
    XCTAssertEqual(request.uploads.count, 0u);
    XCTAssertEqual(request.formParams.count, 0u);
    XCTAssertFalse([request parseMultipartFormWithLimits:@{key:@1} error:&error]);
    XCTAssertTrue([request parseMultipartFormWithLimits:nil error:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(request.uploads.count, 2u);
  }
  NSError *error = nil;
  ALNRequest *request = [self request:self.body];
  XCTAssertTrue(([request parseMultipartFormWithLimits:@{@"maxBodyBytes":@(self.body.length),
      @"maxMultipartParts":@4, @"maxMultipartFieldBytes":@3,
      @"maxMultipartFileBytes":@(self.binary.length)} error:&error]));
}
- (void)testMalformedAndTruncatedBodiesExposeNoPartialResults {
  NSData *valid = self.body;
  for (NSUInteger n = 0; n < valid.length-2; n++) {
    @autoreleasepool {
      NSData *prefix = [valid subdataWithRange:NSMakeRange(0,n)];
      // Cutting boundary-like file bytes immediately after "--" creates a legal close.
      NSData *closing = [@"--Aa--" dataUsingEncoding:NSUTF8StringEncoding];
      if (n >= closing.length && [[prefix subdataWithRange:NSMakeRange(n-closing.length, closing.length)] isEqual:closing]) continue;
      ALNRequest *request = [self request:prefix];
      XCTAssertNotNil(request.multipartError, @"length %lu", (unsigned long)n);
      XCTAssertEqual(request.multipartParts.count, 0u);
    }
  }
  for (NSString *type in @[@"multipart/form-data", @"multipart/form-data; boundary=\"Aa",
                           @"multipart/form-data; boundary=Aa; boundary=Bb"]) {
    NSError *error = nil;
    XCTAssertNil([ALNMultipart parseBody:valid contentType:type limits:@{} error:&error]);
    XCTAssertEqual(error.code, ALNMultipartErrorMalformed);
  }
  NSString *bad = @"--Aa\r\nContent-Disposition: form-data; name=x\r\nContent-Disposition: form-data; name=y\r\n\r\nx\r\n--Aa--";
  XCTAssertEqual([self request:[bad dataUsingEncoding:NSUTF8StringEncoding]].multipartError.code, ALNMultipartErrorMalformed);
}
- (void)testOrdinaryFormsAndJSONRemainUnchanged {
  ALNRequest *form = [[ALNRequest alloc] initWithMethod:@"POST" path:@"/" queryString:@""
      headers:@{@"content-type":@"application/x-www-form-urlencoded"}
      body:[@"x=one&x=two+words&empty=" dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertEqualObjects(form.formParams, (@{@"x":@"two words", @"empty":@""}));
  XCTAssertEqualObjects(form.formValues[@"x"], (@[@"one", @"two words"]));
  NSData *json = [@"{\"ok\":true}" dataUsingEncoding:NSUTF8StringEncoding];
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"POST" path:@"/" queryString:@""
      headers:@{@"content-type":@"application/json"} body:json];
  XCTAssertEqualObjects(request.body, json);
  XCTAssertEqual(request.formParams.count, 0u);
  XCTAssertEqual(request.uploads.count, 0u);
  XCTAssertNil(request.multipartError);
}
- (void)testBothHTTPBackendsPreserveUploadBytes {
  NSData *body = self.body;
  NSMutableData *wire = [[[NSString stringWithFormat:
      @"POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Type: multipart/form-data; boundary=\"Aa\"\r\nContent-Length: %lu\r\n\r\n",
      (unsigned long)body.length] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
  [wire appendData:body];
  for (NSNumber *backend in @[@(ALNHTTPParserBackendLLHTTP), @(ALNHTTPParserBackendLegacy)]) {
    NSError *error = nil;
    ALNRequest *request = [ALNRequest requestFromRawData:wire backend:backend.unsignedIntegerValue error:&error];
    XCTAssertNotNil(request);
    XCTAssertNil(error);
    XCTAssertEqualObjects(request.body, body);
    XCTAssertEqualObjects(request.uploads[0].data, self.binary);
  }
}
- (void)testQuotedParametersAndInvalidText {
  NSString *body = @"--a:b\r\nContent-Disposition: form-data; name=\"a;b\"; filename=\"c;d\\\".bin\"\r\n\r\n\r\n--a:b--";
  NSError *error = nil;
  NSArray *parts = [ALNMultipart parseBody:[body dataUsingEncoding:NSUTF8StringEncoding]
      contentType:@"Multipart/Form-Data; boundary=\"a:b\"" limits:@{} error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(parts.count, 1u);
  XCTAssertEqualObjects([parts[0] fieldName], @"a;b");
  XCTAssertEqualObjects([parts[0] originalFilename], @"c;d\".bin");
  NSMutableData *invalid = [[@"--Aa\r\nContent-Disposition: form-data; name=x\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
  [invalid appendData:self.binary];
  [invalid appendData:[@"\r\n--Aa--" dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertEqual([self request:invalid].multipartError.code, ALNMultipartErrorMalformed);
}
- (void)testApplicationRejectsMalformedAndConfiguredLimits {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{@"requestLimits":@{@"maxMultipartParts":@1}}];
  XCTAssertEqual([app dispatchRequest:[self request:self.body]].statusCode, 413);
  app = [[ALNApplication alloc] initWithConfig:@{}];
  XCTAssertEqual([app dispatchRequest:[self request:[NSData data]]].statusCode, 400);
}
@end

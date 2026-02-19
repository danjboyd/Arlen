#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNRequest.h"

@interface RequestTests : XCTestCase
@end

@implementation RequestTests

- (void)testParsesRequestLineAndQueryParams {
  NSString *raw = @"GET /items/list?name=Peggy+Hill&city=Arlen HTTP/1.1\r\n"
                  "Host: localhost\r\n"
                  "X-Test: 1\r\n\r\n";
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];

  NSError *error = nil;
  ALNRequest *request = [ALNRequest requestFromRawData:data error:&error];

  XCTAssertNil(error);
  XCTAssertEqualObjects(@"GET", request.method);
  XCTAssertEqualObjects(@"/items/list", request.path);
  XCTAssertEqualObjects(@"Peggy Hill", request.queryParams[@"name"]);
  XCTAssertEqualObjects(@"Arlen", request.queryParams[@"city"]);
  XCTAssertEqualObjects(@"1", request.headers[@"x-test"]);
}

- (void)testPreservesBinaryBodyBytes {
  NSString *header = @"POST /upload HTTP/1.1\r\n"
                     "Host: localhost\r\n"
                     "Content-Length: 4\r\n\r\n";
  NSMutableData *raw = [NSMutableData dataWithData:[header dataUsingEncoding:NSUTF8StringEncoding]];
  unsigned char bytes[4] = {0x00, 0xFF, 0x10, 0x7F};
  [raw appendBytes:bytes length:4];

  NSError *error = nil;
  ALNRequest *request = [ALNRequest requestFromRawData:raw error:&error];

  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)4, [request.body length]);
  const unsigned char *bodyBytes = [request.body bytes];
  XCTAssertEqual((unsigned char)0x00, bodyBytes[0]);
  XCTAssertEqual((unsigned char)0xFF, bodyBytes[1]);
  XCTAssertEqual((unsigned char)0x10, bodyBytes[2]);
  XCTAssertEqual((unsigned char)0x7F, bodyBytes[3]);
}

- (void)testInvalidHeaderEncodingReturnsError {
  NSMutableData *raw = [NSMutableData data];
  unsigned char invalidHeader[3] = {0xC3, 0x28, 0x0A};
  [raw appendBytes:invalidHeader length:3];

  NSError *error = nil;
  ALNRequest *request = [ALNRequest requestFromRawData:raw error:&error];

  XCTAssertNil(request);
  XCTAssertNotNil(error);
}

- (void)testParsesCookiesFromHeader {
  NSString *raw = @"GET / HTTP/1.1\r\n"
                  "Host: localhost\r\n"
                  "Cookie: a=1; b=two\r\n\r\n";
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  ALNRequest *request = [ALNRequest requestFromRawData:data error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"1", request.cookies[@"a"]);
  XCTAssertEqualObjects(@"two", request.cookies[@"b"]);
}

@end

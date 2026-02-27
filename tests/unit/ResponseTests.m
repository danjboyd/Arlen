#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNResponse.h"

@interface ResponseTests : XCTestCase
@end

@implementation ResponseTests

- (void)testSerializedHeaderDataOmitsBodyBytes {
  ALNResponse *response = [[ALNResponse alloc] init];
  response.statusCode = 200;
  [response setHeader:@"X-Test" value:@"one"];
  [response appendText:@"hello"];

  NSData *headerData = [response serializedHeaderData];
  NSString *headerText = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding];
  XCTAssertNotNil(headerText);
  XCTAssertTrue([headerText hasPrefix:@"HTTP/1.1 200 OK\r\n"]);
  XCTAssertTrue([headerText containsString:@"Content-Length: 5\r\n"]);
  XCTAssertTrue([headerText containsString:@"X-Test: one\r\n"]);
  XCTAssertTrue([headerText hasSuffix:@"\r\n\r\n"]);
  XCTAssertFalse([headerText containsString:@"hello"]);
}

- (void)testSerializedDataStillIncludesBody {
  ALNResponse *response = [[ALNResponse alloc] init];
  response.statusCode = 404;
  [response appendText:@"missing"];

  NSData *serialized = [response serializedData];
  NSString *text = [[NSString alloc] initWithData:serialized encoding:NSUTF8StringEncoding];
  XCTAssertNotNil(text);
  XCTAssertTrue([text hasPrefix:@"HTTP/1.1 404 Not Found\r\n"]);
  XCTAssertTrue([text containsString:@"Content-Length: 7\r\n"]);
  XCTAssertTrue([text hasSuffix:@"\r\n\r\nmissing"]);
}

- (void)testSerializedHeaderUsesFileBodyLengthWhenPresent {
  ALNResponse *response = [[ALNResponse alloc] init];
  response.statusCode = 200;
  response.fileBodyPath = @"/tmp/static.txt";
  response.fileBodyLength = 321;

  NSData *headerData = [response serializedHeaderData];
  NSString *headerText = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding];
  XCTAssertNotNil(headerText);
  XCTAssertTrue([headerText containsString:@"Content-Length: 321\r\n"]);
}

- (void)testSerializedHeaderCacheInvalidatesOnMutation {
  ALNResponse *response = [[ALNResponse alloc] init];
  [response appendText:@"hello"];

  NSData *first = [response serializedHeaderData];
  NSData *second = [response serializedHeaderData];
  XCTAssertTrue(first == second);

  [response setHeader:@"X-Test" value:@"1"];
  NSData *third = [response serializedHeaderData];
  NSString *headerText = [[NSString alloc] initWithData:third encoding:NSUTF8StringEncoding];
  XCTAssertFalse(second == third);
  XCTAssertTrue([headerText containsString:@"X-Test: 1\r\n"]);
}

- (void)testSerializedHeaderOrderIsDeterministicForStableLayout {
  ALNResponse *response = [[ALNResponse alloc] init];
  [response appendText:@"ok"];
  [response setHeader:@"X-Zeta" value:@"z"];
  [response setHeader:@"X-Alpha" value:@"a"];
  [response setHeader:@"X-Mid" value:@"m"];

  NSData *headerData = [response serializedHeaderData];
  NSString *headerText = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding];
  XCTAssertNotNil(headerText);
  if (headerText == nil) {
    return;
  }

  NSRange alpha = [headerText rangeOfString:@"X-Alpha: a\r\n"];
  NSRange mid = [headerText rangeOfString:@"X-Mid: m\r\n"];
  NSRange zeta = [headerText rangeOfString:@"X-Zeta: z\r\n"];
  XCTAssertNotEqual((NSUInteger)NSNotFound, alpha.location);
  XCTAssertNotEqual((NSUInteger)NSNotFound, mid.location);
  XCTAssertNotEqual((NSUInteger)NSNotFound, zeta.location);
  XCTAssertTrue(alpha.location < mid.location);
  XCTAssertTrue(mid.location < zeta.location);
}

- (void)testSettingSameHeaderValueDoesNotInvalidateSerializedHeaderCache {
  ALNResponse *response = [[ALNResponse alloc] init];
  [response appendText:@"ok"];
  [response setHeader:@"X-Test" value:@"same"];

  NSData *first = [response serializedHeaderData];
  [response setHeader:@"X-Test" value:@"same"];
  NSData *second = [response serializedHeaderData];
  XCTAssertTrue(first == second);
}

- (void)testSetDataBodySetsBinaryContentTypeAndLength {
  ALNResponse *response = [[ALNResponse alloc] init];
  const unsigned char bytes[] = { 0x01, 0x02, 0x03, 0x04 };
  NSData *payload = [NSData dataWithBytes:bytes length:sizeof(bytes)];
  [response setDataBody:payload contentType:nil];

  XCTAssertEqualObjects(@"application/octet-stream", [response headerForName:@"Content-Type"]);
  XCTAssertEqual((NSUInteger)4, [response.bodyData length]);

  NSData *header = [response serializedHeaderData];
  NSString *headerText = [[NSString alloc] initWithData:header encoding:NSUTF8StringEncoding];
  XCTAssertTrue([headerText containsString:@"Content-Length: 4\r\n"]);
}

- (void)testSetDataBodyClearsFileBodyState {
  ALNResponse *response = [[ALNResponse alloc] init];
  response.fileBodyPath = @"/tmp/example.bin";
  response.fileBodyLength = 2048;
  [response setDataBody:[@"ok" dataUsingEncoding:NSUTF8StringEncoding]
            contentType:@"application/custom"];

  XCTAssertNil(response.fileBodyPath);
  XCTAssertEqual((unsigned long long)0, response.fileBodyLength);
  XCTAssertEqualObjects(@"application/custom", [response headerForName:@"Content-Type"]);
}

@end

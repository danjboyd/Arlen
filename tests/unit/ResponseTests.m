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

@end

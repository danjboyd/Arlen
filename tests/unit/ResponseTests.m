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

@end

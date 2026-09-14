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

- (void)testSharedSerializedHeaderCacheReusesStandardHeaderBlocksAcrossResponses {
  ALNResponse *first = [[ALNResponse alloc] init];
  [first appendText:@"ok"];
  [first setHeader:@"Connection" value:@"keep-alive"];

  ALNResponse *second = [[ALNResponse alloc] init];
  [second appendText:@"ok"];
  [second setHeader:@"Connection" value:@"keep-alive"];

  NSData *firstHeader = [first serializedHeaderData];
  NSData *secondHeader = [second serializedHeaderData];
  XCTAssertTrue(firstHeader == secondHeader);
}

- (void)testSharedSerializedHeaderCacheDoesNotApplyToCustomHeaderLayouts {
  ALNResponse *first = [[ALNResponse alloc] init];
  [first appendText:@"ok"];
  [first setHeader:@"Connection" value:@"keep-alive"];
  [first setHeader:@"X-Test" value:@"1"];

  ALNResponse *second = [[ALNResponse alloc] init];
  [second appendText:@"ok"];
  [second setHeader:@"Connection" value:@"keep-alive"];
  [second setHeader:@"X-Test" value:@"1"];

  NSData *firstHeader = [first serializedHeaderData];
  NSData *secondHeader = [second serializedHeaderData];
  XCTAssertFalse(firstHeader == secondHeader);
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

- (void)testSetDataBodyStillSupportsMutableBodyAccess {
  ALNResponse *response = [[ALNResponse alloc] init];
  NSData *payload = [@"ok" dataUsingEncoding:NSUTF8StringEncoding];
  [response setDataBody:payload contentType:@"text/plain; charset=utf-8"];

  [response.bodyData appendData:[@"!" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertEqual((NSUInteger)3, [response bodyLength]);
  NSString *body = [[NSString alloc] initWithData:[response bodyDataForTransmission]
                                         encoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(@"ok!", body);
}

- (void)testClearBodyRemovesDirectBodyStorage {
  ALNResponse *response = [[ALNResponse alloc] init];
  BOOL ok = [response setJSONBody:@{ @"ok" : @YES } options:0 error:NULL];
  XCTAssertTrue(ok);
  XCTAssertTrue([response bodyLength] > 0);

  [response clearBody];

  XCTAssertEqual((NSUInteger)0, [response bodyLength]);
  XCTAssertEqual((NSUInteger)0, [[response bodyDataForTransmission] length]);
}

- (void)testSetHeaderRejectsCRLFInjectionValue {
  ALNResponse *response = [[ALNResponse alloc] init];
  [response setHeader:@"X-Test" value:@"ok\r\nX-Evil: injected"];
  XCTAssertNil([response headerForName:@"X-Test"]);

  NSString *serialized =
      [[NSString alloc] initWithData:[response serializedHeaderData] encoding:NSUTF8StringEncoding];
  XCTAssertFalse([serialized containsString:@"X-Evil: injected"]);
}

- (void)testSetHeaderRejectsInvalidHeaderName {
  ALNResponse *response = [[ALNResponse alloc] init];
  [response setHeader:@"Bad Name" value:@"x"];
  XCTAssertNil([response headerForName:@"Bad Name"]);
}

- (void)testContentLengthHeaderIsCaseInsensitiveCanonicalized {
  ALNResponse *response = [[ALNResponse alloc] init];
  [response appendText:@"hello"];
  [response setHeader:@"content-length" value:@"5"];

  NSString *serialized =
      [[NSString alloc] initWithData:[response serializedHeaderData] encoding:NSUTF8StringEncoding];
  NSArray *lines = [serialized componentsSeparatedByString:@"\r\n"];
  NSUInteger contentLengthLineCount = 0;
  for (NSString *line in lines) {
    if ([[line lowercaseString] hasPrefix:@"content-length:"]) {
      contentLengthLineCount += 1;
    }
  }
  XCTAssertEqual((NSUInteger)1, contentLengthLineCount);
}

- (void)testRepeatedCookiesPreserveOrderingAndExpiresCommas {
  ALNResponse *response = [[ALNResponse alloc] init];
  NSString *first = @"session=abc; Path=/; HttpOnly";
  NSString *second = @"remember=xyz; Path=/account; Expires=Wed, 09 Jun 2032 10:18:14 GMT";
  [response setHeader:@"Set-Cookie" value:first];
  XCTAssertTrue([response appendHeader:@"sEt-CoOkIe" value:second]);
  XCTAssertEqualObjects([response headerValuesForName:@"SET-COOKIE"], (@[first, second]));
  XCTAssertEqualObjects([response headerForName:@"set-cookie"], first);
  XCTAssertEqualObjects(response.headers[@"set-cookie"], first);
  NSString *wire = [[NSString alloc] initWithData:response.serializedHeaderData encoding:NSUTF8StringEncoding];
  XCTAssertTrue(([wire containsString:[NSString stringWithFormat:@"Set-Cookie: %@\r\nSet-Cookie: %@\r\n", first, second]]));
}

- (void)testRepeatedHeaderCacheAppendReplacementRemovalAndReuse {
  ALNResponse *response = [[ALNResponse alloc] init];
  [response setTextBody:@"ok"];
  NSData *plain = response.serializedHeaderData;
  XCTAssertTrue([response appendHeader:@"Set-Cookie" value:@"a=1"]);
  NSData *one = response.serializedHeaderData;
  XCTAssertNotEqual(plain, one);
  XCTAssertEqual(one, response.serializedHeaderData);
  NSArray *snapshot = [response headerValuesForName:@"Set-Cookie"];
  XCTAssertTrue([response appendHeader:@"Set-Cookie" value:@"b=2"]);
  NSData *two = response.serializedHeaderData;
  XCTAssertNotEqual(one, two);
  XCTAssertEqualObjects(snapshot, (@[@"a=1"]));
  // Even replacement by the first existing value must discard the extras.
  [response setHeader:@"set-cookie" value:@"a=1"];
  XCTAssertEqualObjects([response headerValuesForName:@"Set-Cookie"], (@[@"a=1"]));
  NSString *replacement = [[NSString alloc] initWithData:response.serializedHeaderData encoding:NSUTF8StringEncoding];
  XCTAssertFalse([replacement containsString:@"b=2"]);
  XCTAssertTrue([replacement containsString:@"set-cookie: a=1\r\n"]);
  XCTAssertTrue([response appendHeader:@"Set-Cookie" value:@"c=3"]);
  (void)response.serializedHeaderData;
  [response removeHeaderForName:@"SET-COOKIE"];
  XCTAssertNil([response headerForName:@"Set-Cookie"]);
  XCTAssertEqual([response headerValuesForName:@"Set-Cookie"].count, 0u);
  XCTAssertEqualObjects(plain, response.serializedHeaderData);
  XCTAssertTrue([response appendHeader:@"Set-Cookie" value:@"fresh=4"]);
  XCTAssertEqualObjects([response headerValuesForName:@"Set-Cookie"], (@[@"fresh=4"]));
  XCTAssertTrue([response appendHeader:@"Set-Cookie" value:@"other=6"]);
  [response setHeadersIfMissing:@{@"set-cookie":@"ignored=5"}];
  XCTAssertEqualObjects([response headerValuesForName:@"Set-Cookie"], (@[@"fresh=4", @"other=6"]));
  [response removeHeaderForName:@"set-cookie"];
  NSData *removed = response.serializedHeaderData;
  [response setHeadersIfMissing:@{@"Set-Cookie\r\n":@"invalid=7"}];
  XCTAssertEqual(removed, response.serializedHeaderData);
}

- (void)testHeaderSpellingChangesInvalidateCache {
  ALNResponse *response = [[ALNResponse alloc] init];
  [response setHeader:@"X-Name" value:@"same"];
  NSData *before = response.serializedHeaderData;
  [response setHeader:@"x-name" value:@"same"];
  XCTAssertNotEqual(before, response.serializedHeaderData);
  NSString *wire = [[NSString alloc] initWithData:response.serializedHeaderData encoding:NSUTF8StringEncoding];
  XCTAssertTrue([wire containsString:@"x-name: same\r\n"]);
}

- (void)testRepeatedHeadersRejectInjectionWithoutMutation {
  ALNResponse *response = [[ALNResponse alloc] init];
  XCTAssertTrue([response appendHeader:@"Set-Cookie" value:@"safe=1"]);
  NSData *before = response.serializedHeaderData;
  unichar nul = 0;
  NSString *zero = [NSString stringWithCharacters:&nul length:1];
  for (NSString *bad in @[@"x\rInjected: yes", @"x\nInjected: yes", zero]) {
    XCTAssertFalse([response appendHeader:@"Set-Cookie" value:bad]);
    [response setHeader:@"Set-Cookie" value:bad];
    XCTAssertEqual(before, response.serializedHeaderData);
  }
  for (NSString *badName in @[@"Set-Cookie\r\n", @"Set-Cookie\n", [@"Set-Cookie" stringByAppendingString:zero], @"Bad Name"]) {
    XCTAssertFalse([response appendHeader:badName value:@"unsafe=2"]);
    [response setHeader:badName value:@"unsafe=2"];
    XCTAssertEqual(before, response.serializedHeaderData);
  }
  XCTAssertEqualObjects([response headerValuesForName:@"set-cookie"], (@[@"safe=1"]));
}

- (void)testAppendAllowlistKeepsFramingHeadersSingleton {
  ALNResponse *response = [[ALNResponse alloc] init];
  for (NSString *name in @[@"Content-Length", @"Transfer-Encoding", @"Connection", @"Host", @"Content-Type", @"Trailer", @"Location", @"X-Unregistered"]) {
    XCTAssertFalse([response appendHeader:name value:@"first"]);
    [response setHeader:name value:@"one"];
    XCTAssertFalse([response appendHeader:name.lowercaseString value:@"two"]);
    XCTAssertEqualObjects([response headerValuesForName:name], (@[@"one"]));
    [response removeHeaderForName:name];
  }
  for (NSString *name in @[@"WWW-Authenticate", @"Proxy-Authenticate", @"Link", @"Warning", @"Vary", @"Cache-Control"]) {
    XCTAssertTrue([response appendHeader:name value:@"one"]);
    XCTAssertTrue([response appendHeader:name value:@"two"]);
    XCTAssertEqualObjects([response headerValuesForName:name], (@[@"one", @"two"]));
  }
}

- (void)testHeaderValuesCopyMutableInputs {
  ALNResponse *response = [[ALNResponse alloc] init];
  NSMutableString *value = [@"a=1" mutableCopy];
  [response setHeader:@"Set-Cookie" value:value];
  XCTAssertTrue([response appendHeader:@"Set-Cookie" value:value]);
  [value appendString:@"\r\nInjected: yes"];
  XCTAssertEqualObjects([response headerValuesForName:@"Set-Cookie"], (@[@"a=1", @"a=1"]));
}

@end

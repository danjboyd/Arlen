#ifndef ALN_WEB_TEST_SUPPORT_H
#define ALN_WEB_TEST_SUPPORT_H

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "ALNExports.h"

#import "ALNApplication.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNRoute.h"

NS_ASSUME_NONNULL_BEGIN

ALN_EXPORT ALNRequest *ALNTestRequestWithMethod(NSString *method,
                                                NSString *path,
                                                NSString *queryString,
                                                NSDictionary *_Nullable headers,
                                                NSData *_Nullable body);
ALN_EXPORT ALNRequest *ALNTestJSONRequestWithMethod(NSString *method,
                                                    NSString *path,
                                                    NSString *queryString,
                                                    NSDictionary *_Nullable headers,
                                                    id _Nullable object);
ALN_EXPORT NSString *ALNTestStringFromResponse(ALNResponse *_Nullable response);
ALN_EXPORT id _Nullable ALNTestJSONObjectFromResponse(ALNResponse *_Nullable response,
                                                      NSError *_Nullable *_Nullable error);
ALN_EXPORT NSDictionary *_Nullable ALNTestJSONDictionaryFromResponse(
    ALNResponse *_Nullable response,
    NSError *_Nullable *_Nullable error);
ALN_EXPORT NSArray *_Nullable ALNTestJSONArrayFromResponse(ALNResponse *_Nullable response,
                                                           NSError *_Nullable *_Nullable error);
ALN_EXPORT NSString *ALNTestCookiePairFromSetCookie(NSString *_Nullable setCookie);

#define ALNAssertResponseStatus(response, expectedStatus)                                    \
  do {                                                                                       \
    ALNResponse *__aln_response_assert_status = (response);                                  \
    XCTAssertNotNil(__aln_response_assert_status);                                           \
    if (__aln_response_assert_status != nil) {                                               \
      XCTAssertEqual((NSInteger)(expectedStatus), __aln_response_assert_status.statusCode);  \
    }                                                                                        \
  } while (0)

#define ALNAssertResponseHeaderEquals(response, headerName, expectedValue)                   \
  do {                                                                                       \
    ALNResponse *__aln_response_assert_header = (response);                                  \
    XCTAssertNotNil(__aln_response_assert_header);                                           \
    if (__aln_response_assert_header != nil) {                                               \
      XCTAssertEqualObjects((expectedValue),                                                 \
                            [__aln_response_assert_header headerForName:(headerName)]);      \
    }                                                                                        \
  } while (0)

#define ALNAssertResponseHeaderContains(response, headerName, expectedSubstring)             \
  do {                                                                                       \
    ALNResponse *__aln_response_assert_header_contains = (response);                         \
    XCTAssertNotNil(__aln_response_assert_header_contains);                                  \
    if (__aln_response_assert_header_contains != nil) {                                      \
      NSString *__aln_response_header_value =                                                \
          [__aln_response_assert_header_contains headerForName:(headerName)] ?: @"";         \
      XCTAssertTrue([__aln_response_header_value containsString:(expectedSubstring)],        \
                    @"header %@ expected to contain %@ but was %@",                          \
                    (headerName),                                                            \
                    (expectedSubstring),                                                     \
                    __aln_response_header_value);                                            \
    }                                                                                        \
  } while (0)

#define ALNAssertResponseContentType(response, expectedSubstring)                            \
  ALNAssertResponseHeaderContains((response), @"Content-Type", (expectedSubstring))

#define ALNAssertResponseBodyContains(response, expectedSubstring)                           \
  do {                                                                                       \
    NSString *__aln_response_body = ALNTestStringFromResponse((response));                   \
    XCTAssertTrue([__aln_response_body containsString:(expectedSubstring)],                  \
                  @"response body expected to contain %@ but was %@",                        \
                  (expectedSubstring),                                                       \
                  __aln_response_body);                                                      \
  } while (0)

#define ALNAssertResponseRedirect(response, expectedStatus, expectedLocationSubstring)       \
  do {                                                                                       \
    ALNAssertResponseStatus((response), (expectedStatus));                                   \
    ALNAssertResponseHeaderContains((response), @"Location", (expectedLocationSubstring));   \
  } while (0)

@interface ALNWebTestHarness : NSObject

@property(nonatomic, strong, readonly) ALNApplication *application;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *recycledCookies;

- (instancetype)initWithApplication:(ALNApplication *)application;

+ (instancetype)harnessWithApplication:(ALNApplication *)application;
+ (instancetype)harnessWithConfig:(NSDictionary *)config
                      routeMethod:(NSString *)method
                             path:(NSString *)path
                        routeName:(nullable NSString *)routeName
                  controllerClass:(Class)controllerClass
                           action:(NSString *)action
                      middlewares:(nullable NSArray *)middlewares;

- (ALNResponse *)dispatchMethod:(NSString *)method path:(NSString *)path;
- (ALNResponse *)dispatchMethod:(NSString *)method
                           path:(NSString *)path
                    queryString:(NSString *)queryString
                        headers:(NSDictionary *_Nullable)headers
                           body:(NSData *_Nullable)body;
- (ALNResponse *)dispatchJSONMethod:(NSString *)method
                               path:(NSString *)path
                        queryString:(NSString *)queryString
                            headers:(NSDictionary *_Nullable)headers
                         JSONObject:(id _Nullable)object;
- (ALNResponse *)dispatchRequest:(ALNRequest *)request recycleCookies:(BOOL)recycleCookies;
- (void)recycleCookiesFromResponse:(ALNResponse *)response;
- (void)resetRecycledState;
- (NSString *)recycledCookieHeaderValue;
- (nullable ALNRoute *)routeNamed:(NSString *)name;
- (NSArray *)routeTable;
- (NSArray *)middlewares;
- (NSArray *)modules;

@end

NS_ASSUME_NONNULL_END

#endif

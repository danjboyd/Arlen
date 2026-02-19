#ifndef ALN_REQUEST_H
#define ALN_REQUEST_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNRequestErrorDomain;

@interface ALNRequest : NSObject

@property(nonatomic, copy, readonly) NSString *method;
@property(nonatomic, copy, readonly) NSString *path;
@property(nonatomic, copy, readonly) NSString *queryString;
@property(nonatomic, copy, readonly) NSDictionary *headers;
@property(nonatomic, strong, readonly) NSData *body;
@property(nonatomic, copy, readonly) NSDictionary *queryParams;
@property(nonatomic, copy, readonly) NSDictionary *cookies;
@property(nonatomic, copy) NSDictionary *routeParams;
@property(nonatomic, copy) NSString *remoteAddress;
@property(nonatomic, copy) NSString *effectiveRemoteAddress;
@property(nonatomic, copy) NSString *scheme;
@property(nonatomic, assign) double parseDurationMilliseconds;
@property(nonatomic, assign) double responseWriteDurationMilliseconds;

- (instancetype)initWithMethod:(NSString *)method
                          path:(NSString *)path
                   queryString:(NSString *)queryString
                       headers:(NSDictionary *)headers
                          body:(NSData *)body;

+ (nullable ALNRequest *)requestFromRawData:(NSData *)data
                                     error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif

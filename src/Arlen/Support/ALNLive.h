#ifndef ALN_LIVE_H
#define ALN_LIVE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ALNRequest;
@class ALNResponse;

@interface ALNLive : NSObject

+ (NSString *)contentType;
+ (NSString *)acceptContentType;
+ (NSString *)protocolVersion;

+ (NSDictionary *)replaceOperationForTarget:(NSString *)target
                                       html:(NSString *)html;
+ (NSDictionary *)updateOperationForTarget:(NSString *)target
                                      html:(NSString *)html;
+ (NSDictionary *)appendOperationForTarget:(NSString *)target
                                      html:(NSString *)html;
+ (NSDictionary *)prependOperationForTarget:(NSString *)target
                                       html:(NSString *)html;
+ (NSDictionary *)removeOperationForTarget:(NSString *)target;
+ (NSDictionary *)navigateOperationForLocation:(NSString *)location
                                       replace:(BOOL)replace;
+ (NSDictionary *)dispatchOperationForEvent:(NSString *)eventName
                                      detail:(nullable NSDictionary *)detail
                                      target:(nullable NSString *)target;

+ (BOOL)requestIsLive:(nullable ALNRequest *)request;
+ (NSDictionary *)requestMetadataForRequest:(nullable ALNRequest *)request;
+ (nullable NSDictionary *)validatedPayloadWithOperations:(NSArray *)operations
                                                     meta:(nullable NSDictionary *)meta
                                                    error:(NSError *_Nullable *_Nullable)error;
+ (BOOL)renderResponse:(ALNResponse *)response
            operations:(NSArray *)operations
                  meta:(nullable NSDictionary *)meta
                 error:(NSError *_Nullable *_Nullable)error;
+ (NSString *)runtimeJavaScript;

@end

NS_ASSUME_NONNULL_END

#endif

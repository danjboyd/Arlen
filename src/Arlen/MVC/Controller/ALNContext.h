#ifndef ALN_CONTEXT_H
#define ALN_CONTEXT_H

#import <Foundation/Foundation.h>

@class ALNRequest;
@class ALNResponse;
@class ALNLogger;
@class ALNPerfTrace;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNContextSessionStashKey;
extern NSString *const ALNContextSessionDirtyStashKey;
extern NSString *const ALNContextSessionHadCookieStashKey;
extern NSString *const ALNContextCSRFTokenStashKey;
extern NSString *const ALNContextValidationErrorsStashKey;

@interface ALNContext : NSObject

@property(nonatomic, strong, readonly) ALNRequest *request;
@property(nonatomic, strong, readonly) ALNResponse *response;
@property(nonatomic, copy, readonly) NSDictionary *params;
@property(nonatomic, strong, readonly) NSMutableDictionary *stash;
@property(nonatomic, strong, readonly) ALNLogger *logger;
@property(nonatomic, strong, readonly) ALNPerfTrace *perfTrace;
@property(nonatomic, copy, readonly) NSString *routeName;
@property(nonatomic, copy, readonly) NSString *controllerName;
@property(nonatomic, copy, readonly) NSString *actionName;

- (instancetype)initWithRequest:(ALNRequest *)request
                       response:(ALNResponse *)response
                         params:(NSDictionary *)params
                          stash:(NSMutableDictionary *)stash
                         logger:(ALNLogger *)logger
                      perfTrace:(ALNPerfTrace *)perfTrace
                      routeName:(NSString *)routeName
                 controllerName:(NSString *)controllerName
                     actionName:(NSString *)actionName;

- (NSMutableDictionary *)session;
- (void)markSessionDirty;
- (nullable NSString *)csrfToken;
- (NSDictionary *)allParams;
- (nullable id)paramValueForName:(NSString *)name;
- (nullable NSString *)stringParamForName:(NSString *)name;
- (BOOL)requireStringParam:(NSString *)name value:(NSString *_Nullable *_Nullable)value;
- (BOOL)requireIntegerParam:(NSString *)name value:(NSInteger *_Nullable)value;
- (void)addValidationErrorForField:(NSString *)field
                              code:(NSString *)code
                           message:(NSString *)message;
- (NSArray *)validationErrors;

@end

NS_ASSUME_NONNULL_END

#endif

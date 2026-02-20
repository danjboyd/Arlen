#ifndef ALN_CONTEXT_H
#define ALN_CONTEXT_H

#import <Foundation/Foundation.h>
#import "ALNServices.h"

@class ALNRequest;
@class ALNResponse;
@class ALNLogger;
@class ALNPerfTrace;
@class ALNPageState;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNContextSessionStashKey;
extern NSString *const ALNContextSessionDirtyStashKey;
extern NSString *const ALNContextSessionHadCookieStashKey;
extern NSString *const ALNContextCSRFTokenStashKey;
extern NSString *const ALNContextValidationErrorsStashKey;
extern NSString *const ALNContextEOCStrictLocalsStashKey;
extern NSString *const ALNContextEOCStrictStringifyStashKey;
extern NSString *const ALNContextRequestFormatStashKey;
extern NSString *const ALNContextValidatedParamsStashKey;
extern NSString *const ALNContextAuthClaimsStashKey;
extern NSString *const ALNContextAuthScopesStashKey;
extern NSString *const ALNContextAuthRolesStashKey;
extern NSString *const ALNContextAuthSubjectStashKey;
extern NSString *const ALNContextPageStateEnabledStashKey;
extern NSString *const ALNContextJobsAdapterStashKey;
extern NSString *const ALNContextCacheAdapterStashKey;
extern NSString *const ALNContextLocalizationAdapterStashKey;
extern NSString *const ALNContextMailAdapterStashKey;
extern NSString *const ALNContextAttachmentAdapterStashKey;
extern NSString *const ALNContextI18nDefaultLocaleStashKey;
extern NSString *const ALNContextI18nFallbackLocaleStashKey;

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
- (nullable NSString *)queryValueForName:(NSString *)name;
- (nullable NSString *)headerValueForName:(NSString *)name;
- (nullable NSNumber *)queryIntegerForName:(NSString *)name;
- (nullable NSNumber *)queryBooleanForName:(NSString *)name;
- (nullable NSNumber *)headerIntegerForName:(NSString *)name;
- (nullable NSNumber *)headerBooleanForName:(NSString *)name;
- (BOOL)requireStringParam:(NSString *)name value:(NSString *_Nullable *_Nullable)value;
- (BOOL)requireIntegerParam:(NSString *)name value:(NSInteger *_Nullable)value;
- (BOOL)applyETagAndReturnNotModifiedIfMatch:(NSString *)etag;
- (NSString *)requestFormat;
- (BOOL)wantsJSON;
- (void)addValidationErrorForField:(NSString *)field
                              code:(NSString *)code
                           message:(NSString *)message;
- (NSArray *)validationErrors;
- (NSDictionary *)validatedParams;
- (nullable id)validatedValueForName:(NSString *)name;
- (nullable NSDictionary *)authClaims;
- (NSArray *)authScopes;
- (NSArray *)authRoles;
- (nullable NSString *)authSubject;
- (nullable id<ALNJobAdapter>)jobsAdapter;
- (nullable id<ALNCacheAdapter>)cacheAdapter;
- (nullable id<ALNLocalizationAdapter>)localizationAdapter;
- (nullable id<ALNMailAdapter>)mailAdapter;
- (nullable id<ALNAttachmentAdapter>)attachmentAdapter;
- (NSString *)localizedStringForKey:(NSString *)key
                              locale:(nullable NSString *)locale
                      fallbackLocale:(nullable NSString *)fallbackLocale
                        defaultValue:(nullable NSString *)defaultValue
                           arguments:(nullable NSDictionary *)arguments;
- (ALNPageState *)pageStateForKey:(NSString *)pageKey;

@end

NS_ASSUME_NONNULL_END

#endif

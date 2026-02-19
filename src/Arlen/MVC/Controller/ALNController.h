#ifndef ALN_CONTROLLER_H
#define ALN_CONTROLLER_H

#import <Foundation/Foundation.h>

@class ALNContext;
@class ALNPageState;

NS_ASSUME_NONNULL_BEGIN

@interface ALNController : NSObject

@property(nonatomic, strong) ALNContext *context;

+ (NSJSONWritingOptions)jsonWritingOptions;

- (BOOL)renderTemplate:(NSString *)templateName
               context:(nullable NSDictionary *)context
                 error:(NSError *_Nullable *_Nullable)error;
- (BOOL)renderTemplate:(NSString *)templateName
               context:(nullable NSDictionary *)context
                layout:(nullable NSString *)layoutName
                 error:(NSError *_Nullable *_Nullable)error;
- (BOOL)renderTemplate:(NSString *)templateName
                 error:(NSError *_Nullable *_Nullable)error;
- (BOOL)renderTemplate:(NSString *)templateName
                layout:(nullable NSString *)layoutName
                 error:(NSError *_Nullable *_Nullable)error;
- (void)stashValue:(nullable id)value forKey:(NSString *)key;
- (void)stashValues:(NSDictionary *)values;
- (nullable id)stashValueForKey:(NSString *)key;
- (BOOL)renderNegotiatedTemplate:(NSString *)templateName
                          context:(nullable NSDictionary *)context
                       jsonObject:(nullable id)jsonObject
                            error:(NSError *_Nullable *_Nullable)error;
- (BOOL)renderJSON:(id)object error:(NSError *_Nullable *_Nullable)error;
- (void)renderText:(NSString *)text;
- (void)redirectTo:(NSString *)location status:(NSInteger)statusCode;
- (void)setStatus:(NSInteger)statusCode;
- (BOOL)hasRendered;
- (NSMutableDictionary *)session;
- (nullable NSString *)csrfToken;
- (void)markSessionDirty;
- (NSDictionary *)params;
- (nullable id)paramValueForName:(NSString *)name;
- (nullable NSString *)stringParamForName:(NSString *)name;
- (BOOL)requireStringParam:(NSString *)name value:(NSString *_Nullable *_Nullable)value;
- (BOOL)requireIntegerParam:(NSString *)name value:(NSInteger *_Nullable)value;
- (void)addValidationErrorForField:(NSString *)field
                              code:(NSString *)code
                           message:(NSString *)message;
- (NSArray *)validationErrors;
- (BOOL)renderValidationErrors;
- (NSDictionary *)validatedParams;
- (nullable id)validatedValueForName:(NSString *)name;
- (nullable NSDictionary *)authClaims;
- (NSArray *)authScopes;
- (NSArray *)authRoles;
- (nullable NSString *)authSubject;
- (ALNPageState *)pageStateForKey:(NSString *)pageKey;

@end

NS_ASSUME_NONNULL_END

#endif

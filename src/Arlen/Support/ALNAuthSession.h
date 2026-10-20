#ifndef ALN_AUTH_SESSION_H
#define ALN_AUTH_SESSION_H

#import <Foundation/Foundation.h>

@class ALNContext;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNAuthSessionErrorDomain;

typedef NS_ENUM(NSInteger, ALNAuthSessionErrorCode) {
  ALNAuthSessionErrorInvalidArgument = 1,
  ALNAuthSessionErrorMissingAuthenticatedSession = 2,
  ALNAuthSessionErrorRandomGenerationFailed = 3,
};

@interface ALNAuthSession : NSObject

+ (nullable NSString *)subjectFromContext:(ALNContext *)context;
+ (nullable NSString *)providerFromContext:(ALNContext *)context;
+ (NSArray *)authenticationMethodsFromContext:(ALNContext *)context;
+ (NSArray *)scopesFromContext:(ALNContext *)context;
+ (NSArray *)rolesFromContext:(ALNContext *)context;
+ (NSUInteger)assuranceLevelFromContext:(ALNContext *)context;
+ (nullable NSDate *)primaryAuthenticatedAtFromContext:(ALNContext *)context;
+ (nullable NSDate *)mfaAuthenticatedAtFromContext:(ALNContext *)context;
+ (nullable NSString *)sessionIdentifierFromContext:(ALNContext *)context;
+ (BOOL)isMFAAuthenticatedForContext:(ALNContext *)context;

+ (BOOL)context:(ALNContext *)context
    satisfiesMinimumAssuranceLevel:(NSUInteger)minimumAssuranceLevel
  maximumAuthenticationAgeSeconds:(NSUInteger)maximumAuthenticationAgeSeconds
                     referenceDate:(nullable NSDate *)referenceDate;

// Establishing or elevating a session starts a fresh session dictionary: only
// the auth state and `return_to` are kept. Everything else stored before,
// including `_csrf_token`, is dropped, and the next -[ALNContext csrfToken]
// read mints a new token.
+ (BOOL)establishAuthenticatedSessionForSubject:(NSString *)subject
                                       provider:(nullable NSString *)provider
                                        methods:(nullable NSArray *)methods
                                         scopes:(nullable NSArray *)scopes
                                          roles:(nullable NSArray *)roles
                                 assuranceLevel:(NSUInteger)assuranceLevel
                                authenticatedAt:(nullable NSDate *)authenticatedAt
                                        context:(ALNContext *)context
                                          error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)establishAuthenticatedSessionForSubject:(NSString *)subject
                                       provider:(nullable NSString *)provider
                                        methods:(nullable NSArray *)methods
                                 assuranceLevel:(NSUInteger)assuranceLevel
                                authenticatedAt:(nullable NSDate *)authenticatedAt
                                        context:(ALNContext *)context
                                          error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)elevateAuthenticatedSessionForMethod:(NSString *)method
                              assuranceLevel:(NSUInteger)assuranceLevel
                             authenticatedAt:(nullable NSDate *)authenticatedAt
                                     context:(ALNContext *)context
                                       error:(NSError *_Nullable *_Nullable)error;

+ (void)clearAuthenticatedSessionForContext:(ALNContext *)context;

@end

NS_ASSUME_NONNULL_END

#endif

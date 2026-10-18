#ifndef ALN_SECURITY_PRIMITIVES_H
#define ALN_SECURITY_PRIMITIVES_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSData *_Nullable ALNSecureRandomData(NSUInteger length);
NSString *_Nullable ALNBase64URLStringFromData(NSData *data);
NSData *_Nullable ALNDataFromBase64URLString(NSString *value);
BOOL ALNConstantTimeDataEquals(NSData *lhs, NSData *rhs);
NSData *_Nullable ALNHMACSHA1(NSData *input, NSData *key);
NSData *_Nullable ALNHMACSHA256(NSData *input, NSData *key);
NSData *_Nullable ALNSHA256(NSData *input);
NSString *_Nullable ALNLowercaseHexStringFromData(NSData *data);

// Signing secrets committed in the Arlen tree (example apps, env examples,
// tooling fixtures). Anyone can read these, so they must never sign production
// sessions or tokens. This is the single list of known values.
NSArray<NSString *> *ALNKnownPublishedSigningSecrets(void);

// Returns nil when `secret` is not a recognizable placeholder or published
// example value. Otherwise returns a reason code: "placeholder_secret" (contains
// replace-with / change-me / changeme / change_me / 0123456789ab, any case) or
// "published_example_secret" (equals an entry of
// ALNKnownPublishedSigningSecrets()). Length is not checked here.
NSString *_Nullable ALNInsecureSigningSecretReason(NSString *_Nullable secret);

// YES for the development and test environments, where placeholder and example
// secrets stay accepted so the example apps run unchanged.
BOOL ALNEnvironmentAllowsInsecureSigningSecrets(NSString *_Nullable environment);

NS_ASSUME_NONNULL_END

#endif

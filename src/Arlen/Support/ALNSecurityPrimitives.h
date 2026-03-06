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

NS_ASSUME_NONNULL_END

#endif

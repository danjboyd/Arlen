# ALNPasswordHash

- Kind: `interface`
- Header: `src/Arlen/Support/ALNPasswordHash.h`

Argon2id password hashing helpers that emit PHC strings, verify candidate passwords, and report when stored hashes should be rehashed.

## Typical Usage

```objc
NSError *error = nil;
ALNArgon2idOptions options = [ALNPasswordHash defaultArgon2idOptions];
NSString *encodedHash = [ALNPasswordHash hashPasswordString:@"correct horse battery staple"
                                                   options:options
                                                     error:&error];
if (encodedHash == nil) {
  NSLog(@"password hash failed: %@", error);
  return;
}

BOOL verified = [ALNPasswordHash verifyPasswordString:@"correct horse battery staple"
                                    againstEncodedHash:encodedHash
                                                 error:&error];
```

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `defaultArgon2idOptions` | `+ (ALNArgon2idOptions)defaultArgon2idOptions;` | Return Arlen's default Argon2id cost, salt-length, and digest-length policy. | Use as the baseline policy, then copy and raise costs to match deployment hardware. |
| `hashPasswordString:options:error:` | `+ (nullable NSString *)hashPasswordString:(NSString *)password options:(ALNArgon2idOptions)options error:(NSError *_Nullable *_Nullable)error;` | Hash a UTF-8 password string and return a PHC-formatted Argon2id string suitable for storage. | Store the returned PHC string directly; on `nil`, inspect the `NSError` for validation or hashing failures. |
| `hashPasswordData:options:error:` | `+ (nullable NSString *)hashPasswordData:(NSData *)passwordData options:(ALNArgon2idOptions)options error:(NSError *_Nullable *_Nullable)error;` | Hash raw password bytes and return a PHC-formatted Argon2id string. | Prefer this overload when your auth layer already manages password bytes as `NSData`. |
| `verifyPasswordString:againstEncodedHash:error:` | `+ (BOOL)verifyPasswordString:(NSString *)password againstEncodedHash:(NSString *)encodedHash error:(NSError *_Nullable *_Nullable)error;` | Verify a UTF-8 password string against a stored Argon2id PHC string. | Treat `NO` with `error == nil` as a normal password mismatch; inspect `NSError` only for malformed or unsupported stored hashes. |
| `verifyPasswordData:againstEncodedHash:error:` | `+ (BOOL)verifyPasswordData:(NSData *)passwordData againstEncodedHash:(NSString *)encodedHash error:(NSError *_Nullable *_Nullable)error;` | Verify raw password bytes against a stored Argon2id PHC string. | Use this overload when you want byte-level control over password handling in the caller. |
| `encodedHashNeedsRehash:options:error:` | `+ (BOOL)encodedHashNeedsRehash:(NSString *)encodedHash options:(ALNArgon2idOptions)options error:(NSError *_Nullable *_Nullable)error;` | Report whether a stored Argon2id PHC string is older or weaker than the supplied policy. | Call after a successful login and replace the stored hash when this returns `YES`. |
| `argon2Version` | `+ (NSString *)argon2Version;` | Return the vendored Argon2 upstream version identifier used by this Arlen build. | Use for diagnostics, support bundles, or build provenance reporting. |

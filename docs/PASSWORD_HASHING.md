# Password Hashing

Arlen exposes Argon2id password hashing through `ALNPasswordHash`.

This API is intentionally narrow:
- Argon2id only
- PHC string output (store the returned string directly)
- explicit rehash checks when your policy changes
- no account-management or login workflow opinion baked into the framework

## Default Policy

`[ALNPasswordHash defaultArgon2idOptions]` currently returns:
- `memoryKiB = 19456`
- `iterations = 2`
- `parallelism = 1`
- `saltLength = 16`
- `hashLength = 32`

These defaults are meant to be a practical baseline, not a universal target. Benchmark on deployment hardware and raise cost where interactive login latency remains acceptable.

## Basic Usage

```objc
NSError *error = nil;
ALNArgon2idOptions options = [ALNPasswordHash defaultArgon2idOptions];
NSString *storedHash = [ALNPasswordHash hashPasswordString:@"correct horse battery staple"
                                                  options:options
                                                    error:&error];
if (storedHash == nil) {
  NSLog(@"hash failed: %@", error);
  return;
}

BOOL verified = [ALNPasswordHash verifyPasswordString:@"correct horse battery staple"
                                    againstEncodedHash:storedHash
                                                 error:&error];
if (!verified && error != nil) {
  NSLog(@"verify failed: %@", error);
}
```

Wrong passwords return `NO` with `error == nil`.
Malformed or unsupported stored hashes return `NO` with an `NSError`.

## Rehash Flow

A common authentication flow is:
1. load the stored PHC string from the database
2. verify the candidate password
3. if verification succeeds, call `encodedHashNeedsRehash:options:error:`
4. if it returns `YES`, compute a new hash and replace the stored value

```objc
NSError *error = nil;
ALNArgon2idOptions currentPolicy = [ALNPasswordHash defaultArgon2idOptions];
BOOL verified = [ALNPasswordHash verifyPasswordString:submittedPassword
                                    againstEncodedHash:user.passwordHash
                                                 error:&error];
if (!verified || error != nil) {
  return;
}

if ([ALNPasswordHash encodedHashNeedsRehash:user.passwordHash
                                    options:currentPolicy
                                      error:&error]) {
  NSString *upgradedHash = [ALNPasswordHash hashPasswordString:submittedPassword
                                                       options:currentPolicy
                                                         error:&error];
  if (upgradedHash != nil) {
    user.passwordHash = upgradedHash;
  }
}
```

## String vs Data APIs

Use the `NSData` methods if your authentication layer already manages password bytes directly.
Use the `NSString` methods as UTF-8 convenience wrappers.

## Storage Guidance

Store the full PHC string returned by Arlen, for example:

```text
$argon2id$v=19$m=19456,t=2,p=1$...
```

Do not split the salt/hash into custom columns unless you have a specific interoperability requirement.

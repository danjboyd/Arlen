#ifndef ALN_TEST_SUPPORT_H
#define ALN_TEST_SUPPORT_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *ALNTestRepoRoot(void);
FOUNDATION_EXPORT NSString *ALNTestPathFromRepoRoot(NSString *relativePath);
FOUNDATION_EXPORT NSString *ALNTestShellQuote(NSString *value);
FOUNDATION_EXPORT NSString *ALNTestGNUstepSourceCommandForRepoRoot(NSString *_Nullable repoRoot);
FOUNDATION_EXPORT NSData *_Nullable ALNTestDataAtRelativePath(NSString *relativePath,
                                                              NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT id _Nullable ALNTestJSONObjectAtRelativePath(NSString *relativePath,
                                                               NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT id _Nullable ALNTestJSONObjectFromString(NSString *string,
                                                           NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT NSDictionary *_Nullable ALNTestJSONDictionaryAtRelativePath(
    NSString *relativePath,
    NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT NSDictionary *_Nullable ALNTestJSONDictionaryFromString(
    NSString *string,
    NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT NSString *_Nullable ALNTestEnvironmentString(NSString *name);
FOUNDATION_EXPORT NSString *ALNTestUniqueIdentifier(NSString *prefix);
FOUNDATION_EXPORT NSString *_Nullable ALNTestTemporaryDirectory(NSString *prefix);
FOUNDATION_EXPORT BOOL ALNTestWriteUTF8File(NSString *path,
                                            NSString *content,
                                            NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT NSString *ALNTestRunShellCapture(NSString *command, int *_Nullable exitCode);

NS_ASSUME_NONNULL_END

#endif

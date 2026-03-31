#ifndef ALN_TEST_SUPPORT_H
#define ALN_TEST_SUPPORT_H

#import <Foundation/Foundation.h>
#import "ALNExports.h"

NS_ASSUME_NONNULL_BEGIN

ALN_EXPORT NSString *ALNTestRepoRoot(void);
ALN_EXPORT NSString *ALNTestPathFromRepoRoot(NSString *relativePath);
ALN_EXPORT NSData *_Nullable ALNTestDataAtRelativePath(NSString *relativePath,
                                                       NSError *_Nullable *_Nullable error);
ALN_EXPORT id _Nullable ALNTestJSONObjectAtRelativePath(NSString *relativePath,
                                                        NSError *_Nullable *_Nullable error);
ALN_EXPORT id _Nullable ALNTestJSONObjectFromString(NSString *string,
                                                    NSError *_Nullable *_Nullable error);
ALN_EXPORT NSDictionary *_Nullable ALNTestJSONDictionaryAtRelativePath(
    NSString *relativePath,
    NSError *_Nullable *_Nullable error);
ALN_EXPORT NSDictionary *_Nullable ALNTestJSONDictionaryFromString(
    NSString *string,
    NSError *_Nullable *_Nullable error);
ALN_EXPORT NSString *_Nullable ALNTestEnvironmentString(NSString *name);
ALN_EXPORT NSString *ALNTestUniqueIdentifier(NSString *prefix);
ALN_EXPORT NSString *_Nullable ALNTestTemporaryDirectory(NSString *prefix);
ALN_EXPORT BOOL ALNTestWriteUTF8File(NSString *path,
                                     NSString *content,
                                     NSError *_Nullable *_Nullable error);
ALN_EXPORT NSString *ALNTestRunShellCapture(NSString *command, int *_Nullable exitCode);

NS_ASSUME_NONNULL_END

#endif

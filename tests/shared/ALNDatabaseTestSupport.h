#ifndef ALN_DATABASE_TEST_SUPPORT_H
#define ALN_DATABASE_TEST_SUPPORT_H

#import <Foundation/Foundation.h>
#import "ALNExports.h"

#import "ALNDatabaseAdapter.h"

NS_ASSUME_NONNULL_BEGIN

ALN_EXPORT NSString *_Nullable ALNTestRequiredEnvironmentString(
    NSString *environmentName,
    NSString *suiteName,
    NSString *testName,
    NSString *reason);
typedef NS_ENUM(NSUInteger, ALNTestWorkerOwnershipMode) {
  ALNTestWorkerOwnershipModeExplicitBorrowed = 0,
  ALNTestWorkerOwnershipModeSharedOwner = 1,
};

typedef BOOL (^ALNTestWorkerGroupBlock)(NSInteger workerIndex,
                                        NSDictionary<NSString *, id> *ownershipInfo,
                                        NSError *_Nullable *_Nullable error);

ALN_EXPORT NSString *ALNTestQuotedIdentifierForAdapterName(NSString *adapterName,
                                                           NSString *identifier);
ALN_EXPORT NSString *ALNTestMSSQLTemporaryTableName(NSString *prefix);
ALN_EXPORT NSString *ALNTestWorkerOwnershipModeName(ALNTestWorkerOwnershipMode mode);
ALN_EXPORT NSDictionary<NSString *, id> *ALNTestWorkerOwnershipInfo(
    ALNTestWorkerOwnershipMode mode,
    NSInteger workerIndex);
ALN_EXPORT BOOL ALNTestRunWorkerGroup(NSString *suiteName,
                                      NSString *testName,
                                      ALNTestWorkerOwnershipMode mode,
                                      NSInteger workerCount,
                                      NSTimeInterval timeoutSeconds,
                                      ALNTestWorkerGroupBlock block,
                                      NSError *_Nullable *_Nullable error);
ALN_EXPORT BOOL ALNTestWithDisposableSchema(
    id<ALNDatabaseAdapter> adapter,
    NSString *schemaPrefix,
    BOOL (^block)(NSString *schemaName, NSError *_Nullable *_Nullable error),
    NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END

#endif

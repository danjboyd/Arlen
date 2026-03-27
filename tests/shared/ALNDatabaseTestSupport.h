#ifndef ALN_DATABASE_TEST_SUPPORT_H
#define ALN_DATABASE_TEST_SUPPORT_H

#import <Foundation/Foundation.h>

#import "ALNDatabaseAdapter.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *_Nullable ALNTestRequiredEnvironmentString(
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

FOUNDATION_EXPORT NSString *ALNTestQuotedIdentifierForAdapterName(NSString *adapterName,
                                                                  NSString *identifier);
FOUNDATION_EXPORT NSString *ALNTestMSSQLTemporaryTableName(NSString *prefix);
FOUNDATION_EXPORT NSString *ALNTestWorkerOwnershipModeName(ALNTestWorkerOwnershipMode mode);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *ALNTestWorkerOwnershipInfo(
    ALNTestWorkerOwnershipMode mode,
    NSInteger workerIndex);
FOUNDATION_EXPORT BOOL ALNTestRunWorkerGroup(NSString *suiteName,
                                             NSString *testName,
                                             ALNTestWorkerOwnershipMode mode,
                                             NSInteger workerCount,
                                             NSTimeInterval timeoutSeconds,
                                             ALNTestWorkerGroupBlock block,
                                             NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT BOOL ALNTestWithDisposableSchema(
    id<ALNDatabaseAdapter> adapter,
    NSString *schemaPrefix,
    BOOL (^block)(NSString *schemaName, NSError *_Nullable *_Nullable error),
    NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END

#endif

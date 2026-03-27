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
FOUNDATION_EXPORT NSString *ALNTestQuotedIdentifierForAdapterName(NSString *adapterName,
                                                                  NSString *identifier);
FOUNDATION_EXPORT NSString *ALNTestMSSQLTemporaryTableName(NSString *prefix);
FOUNDATION_EXPORT BOOL ALNTestWithDisposableSchema(
    id<ALNDatabaseAdapter> adapter,
    NSString *schemaPrefix,
    BOOL (^block)(NSString *schemaName, NSError *_Nullable *_Nullable error),
    NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END

#endif

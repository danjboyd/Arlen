#ifndef ALN_ADAPTER_CONFORMANCE_H
#define ALN_ADAPTER_CONFORMANCE_H

#import <Foundation/Foundation.h>

#import "ALNDatabaseAdapter.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNAdapterConformanceErrorDomain;

typedef NS_ENUM(NSInteger, ALNAdapterConformanceErrorCode) {
  ALNAdapterConformanceErrorInvalidAdapter = 1,
  ALNAdapterConformanceErrorStepFailed = 2,
};

FOUNDATION_EXPORT BOOL ALNRunAdapterConformanceSuite(id<ALNDatabaseAdapter> adapter,
                                                     NSError *_Nullable *_Nullable error);

FOUNDATION_EXPORT NSDictionary *_Nullable
ALNAdapterConformanceReport(id<ALNDatabaseAdapter> adapter,
                            NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END

#endif

#ifndef ALN_ADAPTER_CONFORMANCE_H
#define ALN_ADAPTER_CONFORMANCE_H

#import <Foundation/Foundation.h>
#import "../ALNExports.h"

#import "ALNDatabaseAdapter.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNAdapterConformanceErrorDomain;

typedef NS_ENUM(NSInteger, ALNAdapterConformanceErrorCode) {
  ALNAdapterConformanceErrorInvalidAdapter = 1,
  ALNAdapterConformanceErrorStepFailed = 2,
};

ALN_EXPORT BOOL ALNRunAdapterConformanceSuite(id<ALNDatabaseAdapter> adapter,
                                              NSError *_Nullable *_Nullable error);

ALN_EXPORT NSDictionary *_Nullable
ALNAdapterConformanceReport(id<ALNDatabaseAdapter> adapter,
                            NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END

#endif

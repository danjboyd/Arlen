#ifndef ALN_LIVE_TEST_SUPPORT_H
#define ALN_LIVE_TEST_SUPPORT_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL ALNLiveRuntimeHarnessIsAvailable(void);
FOUNDATION_EXPORT NSDictionary *_Nullable ALNLiveRunRuntimeScenario(
    NSDictionary *_Nullable scenario,
    NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT NSDictionary *ALNLiveRuntimeResponse(NSInteger status,
                                                       NSDictionary *_Nullable headers,
                                                       NSString *_Nullable body,
                                                       NSString *_Nullable url,
                                                       BOOL redirected,
                                                       NSDictionary *_Nullable extras);
FOUNDATION_EXPORT NSDictionary *_Nullable ALNLiveRuntimeElementSnapshot(
    NSDictionary *_Nullable result,
    NSString *selector);
FOUNDATION_EXPORT NSArray<NSDictionary *> *ALNLiveRuntimeEventsNamed(NSDictionary *_Nullable result,
                                                                     NSString *name);
FOUNDATION_EXPORT NSArray<NSDictionary *> *ALNLiveRuntimeRequestsForTransport(
    NSDictionary *_Nullable result,
    NSString *transport);

NS_ASSUME_NONNULL_END

#endif

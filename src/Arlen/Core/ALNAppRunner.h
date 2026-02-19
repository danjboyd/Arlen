#ifndef ALN_APP_RUNNER_H
#define ALN_APP_RUNNER_H

#import <Foundation/Foundation.h>

@class ALNApplication;

NS_ASSUME_NONNULL_BEGIN

typedef void (*ALNRouteRegistrationCallback)(ALNApplication *app);

int ALNRunAppMain(int argc, const char * _Nonnull const * _Nonnull argv,
                  ALNRouteRegistrationCallback registerRoutes);

NS_ASSUME_NONNULL_END

#endif

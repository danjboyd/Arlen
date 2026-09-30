#ifndef ALN_APP_RUNNER_H
#define ALN_APP_RUNNER_H

#import <Foundation/Foundation.h>

@class ALNApplication;

NS_ASSUME_NONNULL_BEGIN

typedef void (*ALNRouteRegistrationCallback)(ALNApplication *app);

int ALNRunAppMain(int argc, const char * _Nonnull const * _Nonnull argv,
                  ALNRouteRegistrationCallback registerRoutes);

typedef int (*ALNAppMainFunction)(int argc, const char * _Nonnull const * _Nonnull argv);

// For app tests (see ALNTestClient): calls an app's `main` (renamed when compiled
// for tests) with ALNRunAppMain in capture mode, so it records the app's route
// registration callback and returns without loading config or starting a server.
// Returns NULL when `appMain` never calls ALNRunAppMain.
ALNRouteRegistrationCallback _Nullable ALNCaptureRouteRegistration(ALNAppMainFunction appMain);

NS_ASSUME_NONNULL_END

#endif

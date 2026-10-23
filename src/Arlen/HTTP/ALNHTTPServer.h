#ifndef ALN_HTTP_SERVER_H
#define ALN_HTTP_SERVER_H

#import <Foundation/Foundation.h>

@class ALNApplication;

NS_ASSUME_NONNULL_BEGIN

// Reports a startup failure (before the server accepts traffic) as
// "<prefix>: startup failed: <message>". Under propane, which sets
// ARLEN_STARTUP_FAILURE_FILE for each worker, the message goes to that file
// instead of stderr, so propane can print it once and back off; otherwise it
// is printed to stderr.
FOUNDATION_EXPORT void ALNReportStartupFailure(NSString *prefix, NSString *_Nullable message);

@interface ALNHTTPServer : NSObject

@property(nonatomic, strong, readonly) ALNApplication *application;
@property(nonatomic, copy, readonly) NSString *publicRoot;
@property(nonatomic, copy) NSString *serverName;

- (instancetype)initWithApplication:(ALNApplication *)application
                         publicRoot:(NSString *)publicRoot;

- (void)printRoutesToFile:(FILE *)stream;
// Returns after HTTP workers and the idle watcher have exited, including
// native thread-local cleanup. Active requests drain before application shutdown.
- (int)runWithHost:(nullable NSString *)host
      portOverride:(NSInteger)portOverride
              once:(BOOL)once;
// Requests shutdown without waiting; runWithHost:portOverride:once: drains workers.
- (void)requestStop;

@end

NS_ASSUME_NONNULL_END

#endif

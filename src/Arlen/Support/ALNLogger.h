#ifndef ALN_LOGGER_H
#define ALN_LOGGER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ALNLogLevel) {
  ALNLogLevelDebug = 0,
  ALNLogLevelInfo = 1,
  ALNLogLevelWarn = 2,
  ALNLogLevelError = 3,
};

@interface ALNLogger : NSObject

@property(nonatomic, copy, readonly) NSString *format;
@property(nonatomic, assign) ALNLogLevel minimumLevel;

// File descriptor log lines are written to. Defaults to STDERR_FILENO.
// Exposed primarily so tests can point emission at a controlled sink.
@property(nonatomic, assign) int outputFileDescriptor;

// Upper bound, in milliseconds, that a single log emission may wait for the
// output sink to accept bytes before the line is dropped. Guarantees the
// request path can never be blocked indefinitely by a stalled or full log
// consumer (ARLEN-BUG-033). Defaults to 100. A value <= 0 means never wait:
// emit only if the sink can accept the bytes immediately, otherwise drop.
@property(nonatomic, assign) NSInteger writeTimeoutMilliseconds;

// Count of log lines dropped because the output sink would not accept them
// within writeTimeoutMilliseconds. Monotonic for the lifetime of the logger.
@property(nonatomic, readonly) NSUInteger droppedMessageCount;

- (instancetype)initWithFormat:(NSString *)format;
- (BOOL)shouldLogLevel:(ALNLogLevel)level;
- (void)logLevel:(ALNLogLevel)level
         message:(NSString *)message
          fields:(nullable NSDictionary *)fields;
- (void)debug:(NSString *)message fields:(nullable NSDictionary *)fields;
- (void)info:(NSString *)message fields:(nullable NSDictionary *)fields;
- (void)warn:(NSString *)message fields:(nullable NSDictionary *)fields;
- (void)error:(NSString *)message fields:(nullable NSDictionary *)fields;

@end

NS_ASSUME_NONNULL_END

#endif

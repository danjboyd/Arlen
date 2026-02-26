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

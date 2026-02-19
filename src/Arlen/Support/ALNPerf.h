#ifndef ALN_PERF_H
#define ALN_PERF_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALNPerfTrace : NSObject

- (instancetype)initWithEnabled:(BOOL)enabled;
- (BOOL)isEnabled;
- (void)startStage:(NSString *)stage;
- (void)endStage:(NSString *)stage;
- (void)setStage:(NSString *)stage durationMilliseconds:(double)durationMs;
- (nullable NSNumber *)durationMillisecondsForStage:(NSString *)stage;
- (NSDictionary *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END

#endif

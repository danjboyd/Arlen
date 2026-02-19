#ifndef ALN_METRICS_H
#define ALN_METRICS_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALNMetricsRegistry : NSObject

- (void)incrementCounter:(NSString *)name;
- (void)incrementCounter:(NSString *)name by:(double)amount;
- (void)setGauge:(NSString *)name value:(double)value;
- (void)addGauge:(NSString *)name delta:(double)delta;
- (void)recordTiming:(NSString *)name milliseconds:(double)durationMilliseconds;
- (NSDictionary *)snapshot;
- (NSString *)prometheusText;

@end

NS_ASSUME_NONNULL_END

#endif

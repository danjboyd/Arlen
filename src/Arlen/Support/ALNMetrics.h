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
/// Records a completed request's counters and timings in one critical section.
/// A nil timing is omitted, matching disabled tracing.
- (void)recordHTTPResponseStatus:(NSInteger)status
              totalMilliseconds:(nullable NSNumber *)total
              routeMilliseconds:(nullable NSNumber *)route
         controllerMilliseconds:(nullable NSNumber *)controller;
- (NSDictionary *)snapshot;
- (NSString *)prometheusText;

@end

NS_ASSUME_NONNULL_END

#endif

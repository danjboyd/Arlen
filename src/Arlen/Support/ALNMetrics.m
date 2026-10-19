#import "ALNMetrics.h"

static NSString *ALNSanitizeMetricName(NSString *name) {
  if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
    return @"aln_metric";
  }

  NSMutableString *out = [NSMutableString string];
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                                                  @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_:"];
  for (NSUInteger idx = 0; idx < [name length]; idx++) {
    unichar ch = [name characterAtIndex:idx];
    if ([allowed characterIsMember:ch]) {
      [out appendFormat:@"%C", ch];
    } else {
      [out appendString:@"_"];
    }
  }

  if ([out length] == 0) {
    return @"aln_metric";
  }

  unichar first = [out characterAtIndex:0];
  BOOL validFirst =
      ((first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z') || first == '_' || first == ':');
  if (!validFirst) {
    [out insertString:@"_" atIndex:0];
  }
  return out;
}

static NSDictionary *ALNTimingEntry(double count, double sum, double min, double max) {
  double average = (count > 0.0) ? (sum / count) : 0.0;
  return @{
    @"count" : @(count),
    @"sum" : @(sum),
    @"min" : @(count > 0.0 ? min : 0.0),
    @"max" : @(count > 0.0 ? max : 0.0),
    @"avg" : @(average),
  };
}

// Numeric storage is mutated under the registry lock and boxed only when
// taking a snapshot, rather than allocating NSNumber objects per update.
@interface ALNMetricValue : NSObject {
@public
  double value, count, sum, minimum, maximum;
}
@end
@implementation ALNMetricValue
@end

static ALNMetricValue *ALNMetricCell(NSMutableDictionary *entries, NSString *name) {
  ALNMetricValue *cell = entries[name];
  if (cell == nil) {
    cell = [[ALNMetricValue alloc] init];
    entries[name] = cell;
  }
  return cell;
}

static void ALNMetricTiming(NSMutableDictionary *entries, NSString *name, double duration) {
  ALNMetricValue *cell = ALNMetricCell(entries, name);
  duration = MAX(0.0, duration);
  cell->minimum = cell->count > 0 ? MIN(cell->minimum, duration) : duration;
  cell->maximum = cell->count > 0 ? MAX(cell->maximum, duration) : duration;
  cell->count += 1;
  cell->sum += duration;
}

@interface ALNMetricsRegistry ()

@property(nonatomic, strong) NSMutableDictionary *counters;
@property(nonatomic, strong) NSMutableDictionary *gauges;
@property(nonatomic, strong) NSMutableDictionary *timings;
@property(nonatomic, strong) NSLock *lock;

@end

@implementation ALNMetricsRegistry

- (instancetype)init {
  self = [super init];
  if (self) {
    _counters = [NSMutableDictionary dictionary];
    _gauges = [NSMutableDictionary dictionary];
    _timings = [NSMutableDictionary dictionary];
    // Created before the registry is shared; avoids first-use @synchronized
    // races in libobjc2 (gnustep/libobjc2#424).
    _lock = [[NSLock alloc] init];
  }
  return self;
}

- (void)incrementCounter:(NSString *)name {
  [self incrementCounter:name by:1.0];
}

- (void)incrementCounter:(NSString *)name by:(double)amount {
  if ([name length] == 0) {
    return;
  }
  [self.lock lock];
  @try {
    ALNMetricCell(self.counters, name)->value += amount;
  } @finally {
    [self.lock unlock];
  }
}

- (void)setGauge:(NSString *)name value:(double)value {
  if ([name length] == 0) {
    return;
  }
  [self.lock lock];
  @try {
    ALNMetricCell(self.gauges, name)->value = value;
  } @finally {
    [self.lock unlock];
  }
}

- (void)addGauge:(NSString *)name delta:(double)delta {
  if ([name length] == 0) {
    return;
  }
  [self.lock lock];
  @try {
    ALNMetricCell(self.gauges, name)->value += delta;
  } @finally {
    [self.lock unlock];
  }
}

- (void)recordTiming:(NSString *)name milliseconds:(double)durationMilliseconds {
  if ([name length] == 0) {
    return;
  }

  double duration = durationMilliseconds;
  if (duration < 0.0) {
    duration = 0.0;
  }

  [self.lock lock];
  @try {
    ALNMetricTiming(self.timings, name, duration);
  } @finally {
    [self.lock unlock];
  }
}

- (void)recordHTTPResponseStatus:(NSInteger)status
              totalMilliseconds:(NSNumber *)total
              routeMilliseconds:(NSNumber *)route
         controllerMilliseconds:(NSNumber *)controller {
  NSString *statusName = [NSString stringWithFormat:@"http_status_%ld_total", (long)status];
  [self.lock lock];
  @try {
    ALNMetricCell(self.counters, @"http_requests_total")->value += 1;
    ALNMetricCell(self.counters, statusName)->value += 1;
    if (status >= 500) ALNMetricCell(self.counters, @"http_errors_total")->value += 1;
    if (total != nil) ALNMetricTiming(self.timings, @"http_request_duration_ms", total.doubleValue);
    if (route != nil) ALNMetricTiming(self.timings, @"http_route_duration_ms", route.doubleValue);
    if (controller != nil) ALNMetricTiming(self.timings, @"http_controller_duration_ms", controller.doubleValue);
  } @finally {
    [self.lock unlock];
  }
}

- (NSDictionary *)snapshot {
  [self.lock lock];
  @try {
    NSMutableDictionary *timingsSnapshot = [NSMutableDictionary dictionary];
    NSMutableDictionary *countersSnapshot = [NSMutableDictionary dictionary];
    NSMutableDictionary *gaugesSnapshot = [NSMutableDictionary dictionary];
    for (NSString *name in self.timings) {
      ALNMetricValue *cell = self.timings[name];
      timingsSnapshot[name] = ALNTimingEntry(cell->count, cell->sum, cell->minimum, cell->maximum);
    }
    for (NSString *name in self.counters) {
      ALNMetricValue *cell = self.counters[name];
      countersSnapshot[name] = @(cell->value);
    }
    for (NSString *name in self.gauges) {
      ALNMetricValue *cell = self.gauges[name];
      gaugesSnapshot[name] = @(cell->value);
    }
    return @{ @"counters" : countersSnapshot, @"gauges" : gaugesSnapshot, @"timings" : timingsSnapshot };
  } @finally {
    [self.lock unlock];
  }
}

- (NSString *)prometheusText {
  NSDictionary *snapshot = [self snapshot];
  NSDictionary *counters = [snapshot[@"counters"] isKindOfClass:[NSDictionary class]]
                               ? snapshot[@"counters"]
                               : @{};
  NSDictionary *gauges = [snapshot[@"gauges"] isKindOfClass:[NSDictionary class]]
                             ? snapshot[@"gauges"]
                             : @{};
  NSDictionary *timings = [snapshot[@"timings"] isKindOfClass:[NSDictionary class]]
                              ? snapshot[@"timings"]
                              : @{};

  NSMutableString *out = [NSMutableString string];

  NSArray *counterNames = [[counters allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *name in counterNames) {
    NSString *metricName = ALNSanitizeMetricName([NSString stringWithFormat:@"aln_%@", name]);
    [out appendFormat:@"# TYPE %@ counter\n", metricName];
    [out appendFormat:@"%@ %.3f\n", metricName, [counters[name] doubleValue]];
  }

  NSArray *gaugeNames = [[gauges allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *name in gaugeNames) {
    NSString *metricName = ALNSanitizeMetricName([NSString stringWithFormat:@"aln_%@", name]);
    [out appendFormat:@"# TYPE %@ gauge\n", metricName];
    [out appendFormat:@"%@ %.3f\n", metricName, [gauges[name] doubleValue]];
  }

  NSArray *timingNames = [[timings allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *name in timingNames) {
    NSDictionary *entry = timings[name];
    NSString *baseName = ALNSanitizeMetricName([NSString stringWithFormat:@"aln_%@", name]);
    [out appendFormat:@"# TYPE %@ summary\n", baseName];
    [out appendFormat:@"%@_count %.0f\n", baseName, [entry[@"count"] doubleValue]];
    [out appendFormat:@"%@_sum %.3f\n", baseName, [entry[@"sum"] doubleValue]];
    [out appendFormat:@"%@_min %.3f\n", baseName, [entry[@"min"] doubleValue]];
    [out appendFormat:@"%@_max %.3f\n", baseName, [entry[@"max"] doubleValue]];
    [out appendFormat:@"%@_avg %.3f\n", baseName, [entry[@"avg"] doubleValue]];
  }

  return out;
}

@end

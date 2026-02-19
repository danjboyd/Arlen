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

@interface ALNMetricsRegistry ()

@property(nonatomic, strong) NSMutableDictionary *counters;
@property(nonatomic, strong) NSMutableDictionary *gauges;
@property(nonatomic, strong) NSMutableDictionary *timings;

@end

@implementation ALNMetricsRegistry

- (instancetype)init {
  self = [super init];
  if (self) {
    _counters = [NSMutableDictionary dictionary];
    _gauges = [NSMutableDictionary dictionary];
    _timings = [NSMutableDictionary dictionary];
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
  @synchronized(self) {
    double current = [self.counters[name] respondsToSelector:@selector(doubleValue)]
                         ? [self.counters[name] doubleValue]
                         : 0.0;
    self.counters[name] = @(current + amount);
  }
}

- (void)setGauge:(NSString *)name value:(double)value {
  if ([name length] == 0) {
    return;
  }
  @synchronized(self) {
    self.gauges[name] = @(value);
  }
}

- (void)addGauge:(NSString *)name delta:(double)delta {
  if ([name length] == 0) {
    return;
  }
  @synchronized(self) {
    double current = [self.gauges[name] respondsToSelector:@selector(doubleValue)]
                         ? [self.gauges[name] doubleValue]
                         : 0.0;
    self.gauges[name] = @(current + delta);
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

  @synchronized(self) {
    NSMutableDictionary *entry =
        [self.timings[name] isKindOfClass:[NSMutableDictionary class]]
            ? self.timings[name]
            : [NSMutableDictionary dictionary];
    double count = [entry[@"count"] respondsToSelector:@selector(doubleValue)] ? [entry[@"count"] doubleValue] : 0.0;
    double sum = [entry[@"sum"] respondsToSelector:@selector(doubleValue)] ? [entry[@"sum"] doubleValue] : 0.0;
    double min = [entry[@"min"] respondsToSelector:@selector(doubleValue)] ? [entry[@"min"] doubleValue] : duration;
    double max = [entry[@"max"] respondsToSelector:@selector(doubleValue)] ? [entry[@"max"] doubleValue] : duration;

    count += 1.0;
    sum += duration;
    min = MIN(min, duration);
    max = MAX(max, duration);

    entry[@"count"] = @(count);
    entry[@"sum"] = @(sum);
    entry[@"min"] = @(min);
    entry[@"max"] = @(max);
    self.timings[name] = entry;
  }
}

- (NSDictionary *)snapshot {
  @synchronized(self) {
    NSMutableDictionary *timingsSnapshot = [NSMutableDictionary dictionary];
    for (NSString *name in self.timings) {
      NSDictionary *entry = self.timings[name];
      double count = [entry[@"count"] doubleValue];
      double sum = [entry[@"sum"] doubleValue];
      double min = [entry[@"min"] doubleValue];
      double max = [entry[@"max"] doubleValue];
      timingsSnapshot[name] = ALNTimingEntry(count, sum, min, max);
    }

    return @{
      @"counters" : [NSDictionary dictionaryWithDictionary:self.counters],
      @"gauges" : [NSDictionary dictionaryWithDictionary:self.gauges],
      @"timings" : timingsSnapshot,
    };
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

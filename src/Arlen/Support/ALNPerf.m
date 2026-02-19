#import "ALNPerf.h"

@interface ALNPerfTrace ()

@property(nonatomic, strong) NSMutableDictionary *startedAt;
@property(nonatomic, strong) NSMutableDictionary *durationsMs;
@property(nonatomic, assign) BOOL enabled;

@end

@implementation ALNPerfTrace

- (instancetype)init {
  return [self initWithEnabled:YES];
}

- (instancetype)initWithEnabled:(BOOL)enabled {
  self = [super init];
  if (self) {
    _enabled = enabled;
    _startedAt = [NSMutableDictionary dictionary];
    _durationsMs = [NSMutableDictionary dictionary];
  }
  return self;
}

- (BOOL)isEnabled {
  return self.enabled;
}

- (void)startStage:(NSString *)stage {
  if (!self.enabled) {
    return;
  }
  if ([stage length] == 0) {
    return;
  }
  self.startedAt[stage] = @([[NSDate date] timeIntervalSinceReferenceDate]);
}

- (void)endStage:(NSString *)stage {
  if (!self.enabled) {
    return;
  }
  NSNumber *start = self.startedAt[stage];
  if (start == nil) {
    return;
  }
  double now = [[NSDate date] timeIntervalSinceReferenceDate];
  double elapsedMs = (now - [start doubleValue]) * 1000.0;
  self.durationsMs[stage] = @(elapsedMs);
  [self.startedAt removeObjectForKey:stage];
}

- (void)setStage:(NSString *)stage durationMilliseconds:(double)durationMs {
  if (!self.enabled) {
    return;
  }
  if ([stage length] == 0) {
    return;
  }
  self.durationsMs[stage] = @(durationMs);
}

- (NSNumber *)durationMillisecondsForStage:(NSString *)stage {
  if (!self.enabled) {
    return nil;
  }
  return self.durationsMs[stage];
}

- (NSDictionary *)dictionaryRepresentation {
  if (!self.enabled) {
    return @{};
  }
  return [NSDictionary dictionaryWithDictionary:self.durationsMs];
}

@end

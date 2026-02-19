#import "ALNPerf.h"

@interface ALNPerfTrace ()

@property(nonatomic, strong) NSMutableDictionary *startedAt;
@property(nonatomic, strong) NSMutableDictionary *durationsMs;

@end

@implementation ALNPerfTrace

- (instancetype)init {
  self = [super init];
  if (self) {
    _startedAt = [NSMutableDictionary dictionary];
    _durationsMs = [NSMutableDictionary dictionary];
  }
  return self;
}

- (void)startStage:(NSString *)stage {
  if ([stage length] == 0) {
    return;
  }
  self.startedAt[stage] = @([[NSDate date] timeIntervalSinceReferenceDate]);
}

- (void)endStage:(NSString *)stage {
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
  if ([stage length] == 0) {
    return;
  }
  self.durationsMs[stage] = @(durationMs);
}

- (NSNumber *)durationMillisecondsForStage:(NSString *)stage {
  return self.durationsMs[stage];
}

- (NSDictionary *)dictionaryRepresentation {
  return [NSDictionary dictionaryWithDictionary:self.durationsMs];
}

@end

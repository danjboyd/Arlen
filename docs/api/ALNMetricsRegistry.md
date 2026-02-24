# ALNMetricsRegistry

- Kind: `interface`
- Header: `src/Arlen/Support/ALNMetrics.h`

In-memory metrics registry for counters, gauges, timings, snapshots, and Prometheus text output.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `incrementCounter:` | `- (void)incrementCounter:(NSString *)name;` | Increment counter metric by `1`. | Call for side effects; this method does not return a value. |
| `incrementCounter:by:` | `- (void)incrementCounter:(NSString *)name by:(double)amount;` | Increment counter metric by explicit amount. | Call for side effects; this method does not return a value. |
| `setGauge:value:` | `- (void)setGauge:(NSString *)name value:(double)value;` | Set gauge metric to an absolute value. | Call before downstream behavior that depends on this updated value. |
| `addGauge:delta:` | `- (void)addGauge:(NSString *)name delta:(double)delta;` | Add delta to existing gauge metric value. | Call during bootstrap/setup before this behavior is exercised. |
| `recordTiming:milliseconds:` | `- (void)recordTiming:(NSString *)name milliseconds:(double)durationMilliseconds;` | Record timing metric sample in milliseconds. | Call for side effects; this method does not return a value. |
| `snapshot` | `- (NSDictionary *)snapshot;` | Return in-memory metrics snapshot for programmatic inspection. | Read this value when you need current runtime/request state. |
| `prometheusText` | `- (NSString *)prometheusText;` | Render metrics snapshot in Prometheus exposition text format. | Read this value when you need current runtime/request state. |

# ALNPerfTrace

- Kind: `interface`
- Header: `src/Arlen/Support/ALNPerf.h`

Per-request performance stage recorder used for internal timing diagnostics and perf event export.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithEnabled:` | `- (instancetype)initWithEnabled:(BOOL)enabled;` | Initialize and return a new `ALNPerfTrace` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `isEnabled` | `- (BOOL)isEnabled;` | Return whether `ALNPerfTrace` currently satisfies this condition. | Check the return value to confirm the operation succeeded. |
| `startStage:` | `- (void)startStage:(NSString *)stage;` | Start timing for one named perf stage. | Call for side effects; this method does not return a value. |
| `endStage:` | `- (void)endStage:(NSString *)stage;` | End timing for one named perf stage. | Call for side effects; this method does not return a value. |
| `setStage:durationMilliseconds:` | `- (void)setStage:(NSString *)stage durationMilliseconds:(double)durationMs;` | Set an explicit duration for one perf stage. | Call before downstream behavior that depends on this updated value. |
| `durationMillisecondsForStage:` | `- (nullable NSNumber *)durationMillisecondsForStage:(NSString *)stage;` | Return recorded duration for one perf stage. | Capture the returned value and propagate errors/validation as needed. |
| `dictionaryRepresentation` | `- (NSDictionary *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |

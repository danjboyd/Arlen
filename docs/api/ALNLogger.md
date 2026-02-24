# ALNLogger

- Kind: `interface`
- Header: `src/Arlen/Support/ALNLogger.h`

Structured logger with configurable output format and level-specific convenience methods.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `format` | `NSString *` | `nonatomic, copy, readonly` | Public `format` property available on `ALNLogger`. |
| `minimumLevel` | `ALNLogLevel` | `nonatomic, assign` | Public `minimumLevel` property available on `ALNLogger`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithFormat:` | `- (instancetype)initWithFormat:(NSString *)format;` | Initialize and return a new `ALNLogger` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `logLevel:message:fields:` | `- (void)logLevel:(ALNLogLevel)level message:(NSString *)message fields:(nullable NSDictionary *)fields;` | Emit one structured log entry at the requested level. | Call for side effects; this method does not return a value. |
| `debug:fields:` | `- (void)debug:(NSString *)message fields:(nullable NSDictionary *)fields;` | Emit debug-level structured log entry. | Call for side effects; this method does not return a value. |
| `info:fields:` | `- (void)info:(NSString *)message fields:(nullable NSDictionary *)fields;` | Emit info-level structured log entry. | Call for side effects; this method does not return a value. |
| `warn:fields:` | `- (void)warn:(NSString *)message fields:(nullable NSDictionary *)fields;` | Emit warn-level structured log entry. | Call for side effects; this method does not return a value. |
| `error:fields:` | `- (void)error:(NSString *)message fields:(nullable NSDictionary *)fields;` | Emit error-level structured log entry. | Pass `NSError **` when you need detailed failure diagnostics. |

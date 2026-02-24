# ALNHTTPServer

- Kind: `interface`
- Header: `src/Arlen/HTTP/ALNHTTPServer.h`

HTTP server host that binds an `ALNApplication` to socket runtime and request loop execution.

## Typical Usage

```objc
ALNHTTPServer *server = [[ALNHTTPServer alloc] initWithApplication:app
                                                          publicRoot:@"public"];
int exitCode = [server runWithHost:@"127.0.0.1"
                      portOverride:3000
                              once:NO];
```

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `application` | `ALNApplication *` | `nonatomic, strong, readonly` | Public `application` property available on `ALNHTTPServer`. |
| `publicRoot` | `NSString *` | `nonatomic, copy, readonly` | Public `publicRoot` property available on `ALNHTTPServer`. |
| `serverName` | `NSString *` | `nonatomic, copy` | Public `serverName` property available on `ALNHTTPServer`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithApplication:publicRoot:` | `- (instancetype)initWithApplication:(ALNApplication *)application publicRoot:(NSString *)publicRoot;` | Initialize and return a new `ALNHTTPServer` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `printRoutesToFile:` | `- (void)printRoutesToFile:(FILE *)stream;` | Print route table to a stream for diagnostics. | Call for side effects; this method does not return a value. |
| `runWithHost:portOverride:once:` | `- (int)runWithHost:(nullable NSString *)host portOverride:(NSInteger)portOverride once:(BOOL)once;` | Run HTTP server loop with optional host/port overrides. | Use `once:YES` for single-request smoke tests; use `once:NO` for normal long-running server mode. |
| `requestStop` | `- (void)requestStop;` | Request graceful server shutdown. | Call for side effects; this method does not return a value. |

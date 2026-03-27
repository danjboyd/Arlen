# ALNPlugin

- Kind: `protocol`
- Header: `src/Arlen/Core/ALNApplication.h`

Plugin protocol for declarative app extension (registration + optional middleware contribution).

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `pluginName` | `- (NSString *)pluginName;` | Return the plugin's stable registration name. | Read this value when you need current runtime/request state. |
| `registerWithApplication:error:` | `- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError *_Nullable *_Nullable)error;` | Register plugin behavior and routes on an application instance. | Call during app bootstrap before server start. Return `NO` and fill `error` on invalid plugin configuration. |
| `middlewaresForApplication:` | `- (NSArray *)middlewaresForApplication:(ALNApplication *)application;` | Return middleware instances provided by this plugin. | Treat returned collection values as snapshots unless the API documents mutability. |

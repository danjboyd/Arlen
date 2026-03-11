# ALNModule

- Kind: `protocol`
- Header: `src/Arlen/Core/ALNModuleSystem.h`

Protocol contract exported as part of the `ALNModule` API surface.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `moduleIdentifier` | `- (NSString *)moduleIdentifier;` | Perform `module identifier` for `ALNModule`. | Read this value when you need current runtime/request state. |
| `registerWithApplication:error:` | `- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError *_Nullable *_Nullable)error;` | Register plugin behavior and routes on an application instance. | Call during app bootstrap before server start. Return `NO` and fill `error` on invalid plugin configuration. |
| `pluginsForApplication:` | `- (NSArray<id<ALNPlugin>> *)pluginsForApplication:(ALNApplication *)application;` | Perform `plugins for application` for `ALNModule`. | Treat returned collection values as snapshots unless the API documents mutability. |

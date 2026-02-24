# ALNLifecycleHook

- Kind: `protocol`
- Header: `src/Arlen/Core/ALNApplication.h`

Lifecycle callback protocol invoked around app startup and shutdown boundaries.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `applicationWillStart:error:` | `- (BOOL)applicationWillStart:(ALNApplication *)application error:(NSError *_Nullable *_Nullable)error;` | Lifecycle hook called before application startup completes. | Register hooks before `startWithError:`; returning `NO` aborts startup. |
| `applicationDidStart:` | `- (void)applicationDidStart:(ALNApplication *)application;` | Lifecycle hook called after startup succeeds. | Call for side effects; this method does not return a value. |
| `applicationWillStop:` | `- (void)applicationWillStop:(ALNApplication *)application;` | Lifecycle hook called before shutdown begins. | Call for side effects; this method does not return a value. |
| `applicationDidStop:` | `- (void)applicationDidStop:(ALNApplication *)application;` | Lifecycle hook called after shutdown finishes. | Call for side effects; this method does not return a value. |

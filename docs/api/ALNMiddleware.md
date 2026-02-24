# ALNMiddleware

- Kind: `protocol`
- Header: `src/Arlen/Core/ALNApplication.h`

Middleware protocol for pre-dispatch and optional post-dispatch request processing.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `processContext:error:` | `- (BOOL)processContext:(ALNContext *)context error:(NSError *_Nullable *_Nullable)error;` | Run middleware pre-processing for the current request context. | Return `NO` to short-circuit request handling. Populate `error` for deterministic middleware failures. |
| `didProcessContext:` | `- (void)didProcessContext:(ALNContext *)context;` | Run middleware post-processing after controller dispatch completes. | Call for side effects; this method does not return a value. |

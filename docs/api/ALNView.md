# ALNView

- Kind: `interface`
- Header: `src/Arlen/MVC/View/ALNView.h`

Template renderer that executes transpiled EOC templates with optional strict locals/stringify behavior.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `normalizeTemplateLogicalPath:` | `+ (NSString *)normalizeTemplateLogicalPath:(NSString *)templateName;` | Normalize template path to deterministic logical path key. | Call on the class type, not on an instance. |
| `renderTemplate:context:layout:error:` | `+ (nullable NSString *)renderTemplate:(NSString *)templateName context:(nullable NSDictionary *)context layout:(nullable NSString *)layoutName error:(NSError *_Nullable *_Nullable)error;` | Render a template with explicit context and layout. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. Call from controller action paths after selecting response status/headers. |
| `renderTemplate:context:layout:strictLocals:strictStringify:error:` | `+ (nullable NSString *)renderTemplate:(NSString *)templateName context:(nullable NSDictionary *)context layout:(nullable NSString *)layoutName strictLocals:(BOOL)strictLocals strictStringify:(BOOL)strictStringify error:(NSError *_Nullable *_Nullable)error;` | Render a response payload for the current request context. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. Call from controller action paths after selecting response status/headers. |

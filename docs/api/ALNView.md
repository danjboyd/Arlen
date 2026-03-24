# ALNView

- Kind: `interface`
- Header: `src/Arlen/MVC/View/ALNView.h`

EOC view renderer that normalizes logical template names, resolves default layouts, and can enforce strict locals/stringify behavior during render.

## Typical Usage

```objc
NSError *error = nil;
NSString *html = [ALNView renderTemplate:@"dashboard"
                                       context:@{ @"title": @"Home" }
                                        layout:nil
                          defaultLayoutEnabled:YES
                                  strictLocals:NO
                               strictStringify:NO
                                         error:&error];
if (html == nil) {
  NSLog(@"template render failed: %@", error);
}
```

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `normalizeTemplateLogicalPath:` | `+ (NSString *)normalizeTemplateLogicalPath:(NSString *)templateName;` | Normalize one logical template reference by stripping leading `/` characters and appending `.html.eoc` when needed. | Pass logical names such as `dashboard` or `layouts/main`; use this when you need the exact runtime key used for EOC registry lookups. |
| `renderTemplate:context:layout:error:` | `+ (nullable NSString *)renderTemplate:(NSString *)templateName context:(nullable NSDictionary *)context layout:(nullable NSString *)layoutName error:(NSError *_Nullable *_Nullable)error;` | Render one EOC template with explicit locals and either an explicit layout or the default layout resolved for that template. | Pass unsuffixed logical names for `templateName` and `layoutName`. Use `layout:nil` to allow the template's default static layout; when a layout renders, the body is also exposed through the `content` slot. |
| `renderTemplate:context:layout:defaultLayoutEnabled:strictLocals:strictStringify:error:` | `+ (nullable NSString *)renderTemplate:(NSString *)templateName context:(nullable NSDictionary *)context layout:(nullable NSString *)layoutName defaultLayoutEnabled:(BOOL)defaultLayoutEnabled strictLocals:(BOOL)strictLocals strictStringify:(BOOL)strictStringify error:(NSError *_Nullable *_Nullable)error;` | Render one EOC template with full control over default-layout lookup and strict locals/stringify runtime enforcement. | Set `defaultLayoutEnabled:NO` to suppress implicit layout resolution when `layoutName` is `nil`. Use `strictLocals:YES` to fail missing locals and `strictStringify:YES` to fail values that cannot be deterministically stringified. |
| `renderTemplate:context:layout:strictLocals:strictStringify:error:` | `+ (nullable NSString *)renderTemplate:(NSString *)templateName context:(nullable NSDictionary *)context layout:(nullable NSString *)layoutName strictLocals:(BOOL)strictLocals strictStringify:(BOOL)strictStringify error:(NSError *_Nullable *_Nullable)error;` | Render one EOC template with default-layout lookup enabled plus strict locals/stringify controls. | Use this overload when you want strict rendering checks but still want Arlen to resolve the template's default static layout when `layoutName` is `nil`. |

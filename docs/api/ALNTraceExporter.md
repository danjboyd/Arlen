# ALNTraceExporter

- Kind: `protocol`
- Header: `src/Arlen/Core/ALNApplication.h`

Trace-export protocol used to publish structured request spans to external observability sinks.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `exportTrace:request:response:routeName:controllerName:actionName:` | `- (void)exportTrace:(NSDictionary *)trace request:(ALNRequest *)request response:(ALNResponse *)response routeName:(NSString *)routeName controllerName:(NSString *)controllerName actionName:(NSString *)actionName;` | Export a completed request trace event. | Call for side effects; this method does not return a value. |

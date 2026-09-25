# ALNMIMETypes

- Kind: `interface`
- Header: `src/Arlen/HTTP/ALNMIMETypes.h`

HTTP request/response and server runtime primitives.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `defaultTypes` | `+ (NSDictionary<NSString *, NSString *> *)defaultTypes;` | Perform `default types` for `ALNMIMETypes`. | Call on the class type, not on an instance. |
| `typeForExtension:` | `+ (nullable NSString *)typeForExtension:(NSString *)extension;` | Perform `type for extension` for `ALNMIMETypes`. | Call on the class type, not on an instance. |
| `typeForExtension:overrides:` | `+ (nullable NSString *)typeForExtension:(NSString *)extension overrides:(nullable NSDictionary *)overrides;` | Perform `type for extension` for `ALNMIMETypes`. | Call on the class type, not on an instance. |
| `contentTypeForFilePath:` | `+ (NSString *)contentTypeForFilePath:(NSString *)filePath;` | Perform `content type for file path` for `ALNMIMETypes`. | Call on the class type, not on an instance. |
| `contentTypeForFilePath:overrides:` | `+ (NSString *)contentTypeForFilePath:(NSString *)filePath overrides:(nullable NSDictionary *)overrides;` | Perform `content type for file path` for `ALNMIMETypes`. | Call on the class type, not on an instance. |

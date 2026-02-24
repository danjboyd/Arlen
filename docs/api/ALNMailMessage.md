# ALNMailMessage

- Kind: `interface`
- Header: `src/Arlen/Support/ALNServices.h`

Mail payload model containing sender/recipients/content/headers/metadata fields.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `from` | `NSString *` | `nonatomic, copy, readonly` | Public `from` property available on `ALNMailMessage`. |
| `to` | `NSArray *` | `nonatomic, copy, readonly` | Public `to` property available on `ALNMailMessage`. |
| `cc` | `NSArray *` | `nonatomic, copy, readonly` | Public `cc` property available on `ALNMailMessage`. |
| `bcc` | `NSArray *` | `nonatomic, copy, readonly` | Public `bcc` property available on `ALNMailMessage`. |
| `subject` | `NSString *` | `nonatomic, copy, readonly` | Public `subject` property available on `ALNMailMessage`. |
| `textBody` | `NSString *` | `nonatomic, copy, readonly` | Public `textBody` property available on `ALNMailMessage`. |
| `htmlBody` | `NSString *` | `nonatomic, copy, readonly` | Public `htmlBody` property available on `ALNMailMessage`. |
| `headers` | `NSDictionary *` | `nonatomic, copy, readonly` | Public `headers` property available on `ALNMailMessage`. |
| `metadata` | `NSDictionary *` | `nonatomic, copy, readonly` | Public `metadata` property available on `ALNMailMessage`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithFrom:to:cc:bcc:subject:textBody:htmlBody:headers:metadata:` | `- (instancetype)initWithFrom:(NSString *)from to:(NSArray *)to cc:(nullable NSArray *)cc bcc:(nullable NSArray *)bcc subject:(NSString *)subject textBody:(nullable NSString *)textBody htmlBody:(nullable NSString *)htmlBody headers:(nullable NSDictionary *)headers metadata:(nullable NSDictionary *)metadata;` | Initialize and return a new `ALNMailMessage` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `dictionaryRepresentation` | `- (NSDictionary *)dictionaryRepresentation;` | Return this object as a stable dictionary payload. | Read this value when you need current runtime/request state. |

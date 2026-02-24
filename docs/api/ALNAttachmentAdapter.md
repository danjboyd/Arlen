# ALNAttachmentAdapter

- Kind: `protocol`
- Header: `src/Arlen/Support/ALNServices.h`

Attachment adapter protocol for save/read/delete/list operations on binary blobs + metadata.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `adapterName` | `- (NSString *)adapterName;` | Return the stable identifier for this plugin/adapter implementation. | Read this value when you need current runtime/request state. |
| `saveAttachmentNamed:contentType:data:metadata:error:` | `- (nullable NSString *)saveAttachmentNamed:(NSString *)name contentType:(NSString *)contentType data:(NSData *)data metadata:(nullable NSDictionary *)metadata error:(NSError *_Nullable *_Nullable)error;` | Save attachment payload and return generated attachment identifier. | Store business identifiers in `metadata` rather than encoding them into the attachment name. |
| `attachmentDataForID:metadata:error:` | `- (nullable NSData *)attachmentDataForID:(NSString *)attachmentID metadata:(NSDictionary *_Nullable *_Nullable)metadata error:(NSError *_Nullable *_Nullable)error;` | Load attachment bytes and optional metadata for an attachment ID. | Pass `NSError **` and treat a `nil` result as failure. |
| `attachmentMetadataForID:error:` | `- (nullable NSDictionary *)attachmentMetadataForID:(NSString *)attachmentID error:(NSError *_Nullable *_Nullable)error;` | Return metadata only for an attachment ID. | Pass `NSError **` and treat a `nil` result as failure. |
| `deleteAttachmentID:error:` | `- (BOOL)deleteAttachmentID:(NSString *)attachmentID error:(NSError *_Nullable *_Nullable)error;` | Delete one attachment by ID. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `listAttachmentMetadata` | `- (NSArray *)listAttachmentMetadata;` | Return metadata list for all stored attachments. | Read this value when you need current runtime/request state. |
| `reset` | `- (void)reset;` | Reset state to a clean baseline for testing or maintenance. | Call for side effects; this method does not return a value. |

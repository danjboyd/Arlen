# ALNDisplayGroup

- Kind: `interface`
- Header: `src/Arlen/Data/ALNDisplayGroup.h`

DisplayGroup-style query helper that builds list fetches from filter and sort descriptors.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `adapter` | `id<ALNDatabaseAdapter>` | `nonatomic, strong, readonly` | Public `adapter` property available on `ALNDisplayGroup`. |
| `tableName` | `NSString *` | `nonatomic, copy, readonly` | Public `tableName` property available on `ALNDisplayGroup`. |
| `fetchFields` | `NSArray<NSString *> *` | `nonatomic, copy` | Public `fetchFields` property available on `ALNDisplayGroup`. |
| `batchSize` | `NSUInteger` | `nonatomic, assign` | Public `batchSize` property available on `ALNDisplayGroup`. |
| `batchIndex` | `NSUInteger` | `nonatomic, assign` | Public `batchIndex` property available on `ALNDisplayGroup`. |
| `filters` | `NSDictionary *` | `nonatomic, copy, readonly` | Public `filters` property available on `ALNDisplayGroup`. |
| `sortOrder` | `NSArray *` | `nonatomic, copy, readonly` | Public `sortOrder` property available on `ALNDisplayGroup`. |
| `objects` | `NSArray<NSDictionary *> *` | `nonatomic, copy, readonly` | Public `objects` property available on `ALNDisplayGroup`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `initWithAdapter:tableName:` | `- (instancetype)initWithAdapter:(id<ALNDatabaseAdapter>)adapter tableName:(NSString *)tableName;` | Initialize and return a new `ALNDisplayGroup` instance. | Use as `[[Class alloc] init...]`; treat `nil` as initialization failure. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `setFilterValue:forField:` | `- (void)setFilterValue:(nullable id)value forField:(NSString *)field;` | Set or replace one display-group filter criterion. | Call before downstream behavior that depends on this updated value. |
| `removeFilterForField:` | `- (void)removeFilterForField:(NSString *)field;` | Remove one display-group filter criterion. | Call for side effects; this method does not return a value. |
| `clearFilters` | `- (void)clearFilters;` | Clear all active display-group filters. | Call for side effects; this method does not return a value. |
| `addSortField:descending:` | `- (void)addSortField:(NSString *)field descending:(BOOL)descending;` | Append one sort descriptor to display-group query order. | Call during bootstrap/setup before this behavior is exercised. |
| `clearSortOrder` | `- (void)clearSortOrder;` | Clear all configured display-group sort descriptors. | Call for side effects; this method does not return a value. |
| `fetch:` | `- (BOOL)fetch:(NSError *_Nullable *_Nullable)error;` | Execute display-group query using current filters/sort descriptors. | Check the return value to confirm the operation succeeded. |

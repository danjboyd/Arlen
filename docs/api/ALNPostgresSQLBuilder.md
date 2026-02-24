# ALNPostgresSQLBuilder

- Kind: `interface`
- Header: `src/Arlen/Data/ALNPostgresSQLBuilder.h`

PostgreSQL dialect extension for `ALNSQLBuilder` covering `ON CONFLICT` upsert behaviors.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `onConflictDoNothing` | `- (instancetype)onConflictDoNothing;` | Configure PostgreSQL `ON CONFLICT DO NOTHING` behavior. | This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `onConflictColumns:doUpdateSetFields:` | `- (instancetype)onConflictColumns:(nullable NSArray<NSString *> *)columns doUpdateSetFields:(NSArray<NSString *> *)fields;` | Configure PostgreSQL upsert conflict update using field names. | This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `onConflictColumns:doUpdateAssignments:` | `- (instancetype)onConflictColumns:(nullable NSArray<NSString *> *)columns doUpdateAssignments:(NSDictionary<NSString *, id> *)assignments;` | Configure PostgreSQL upsert conflict update using explicit assignments. | This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |
| `onConflictDoUpdateWhereExpression:parameters:` | `- (instancetype)onConflictDoUpdateWhereExpression:(NSString *)expression parameters:(nullable NSArray *)parameters;` | Configure conditional `DO UPDATE ... WHERE ...` clause for upsert. | This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |

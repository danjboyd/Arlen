# ALNMSSQLDialect

- Kind: `interface`
- Header: `src/Arlen/Data/ALNMSSQLDialect.h`

Data-layer APIs for SQL composition, adapters, and migration/runtime operations.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `sharedDialect` | `+ (instancetype)sharedDialect;` | Return the shared singleton instance. | Call on the class type, not on an instance. This method is chainable; continue composing and call `build`/`buildSQL` to finalize. |

# ALNSSEEvent

- Kind: `interface`
- Header: `src/Arlen/Support/ALNSSEReader.h`

Immutable generic SSE event with type, multiline data and persistent last-event ID. Created by ALNSSEReader; carries no vendor-specific completion meaning.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `eventType` | `NSString *` | `nonatomic, copy, readonly` | Last event field, or message when empty; reset after each blank line. |
| `data` | `NSString *` | `nonatomic, copy, readonly` | Joined data fields with the final appended LF removed. May be empty. |
| `lastEventID` | `NSString *` | `nonatomic, copy, readonly` | Latest valid ID, preserved across events; empty IDs reset it and NUL-containing IDs are ignored. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Unavailable; events are created by the reader. | Retain an event explicitly if needed after its synchronous callback. |

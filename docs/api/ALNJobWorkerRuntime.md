# ALNJobWorkerRuntime

- Kind: `protocol`
- Header: `src/Arlen/Support/ALNServices.h`

Worker runtime callback protocol that decides ack/retry/discard disposition for leased jobs.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `handleJob:error:` | `- (ALNJobWorkerDisposition)handleJob:(ALNJobEnvelope *)job error:(NSError *_Nullable *_Nullable)error;` | Handle one leased job and return worker disposition (`ack`, `retry`, or `discard`). | Pass `NSError **` when you need detailed failure diagnostics. |

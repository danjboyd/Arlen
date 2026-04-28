# StateCompulsoryPoolingAPI Report Reconciliation

Date: `2026-04-24`

This note records the upstream Arlen assessment of production file-response
reports from `StateCompulsoryPoolingAPI`.

Ownership rule:

- Arlen records upstream status only.
- `StateCompulsoryPoolingAPI` keeps app-level closure authority.
- Status below should be read as the upstream status/evidence trail.
  Downstream revalidation still belongs to `StateCompulsoryPoolingAPI`.

## Current Upstream Assessment

| StateCompulsoryPoolingAPI report | Upstream status | Evidence |
| --- | --- | --- |
| `ALNResponse.fileBodyPath` responses send headers with `Content-Length` but no body bytes when file streaming fails | fixed upstream; awaiting downstream revalidation | `src/Arlen/HTTP/ALNHTTPServer.m`, `tools/boomhauer.m`, `tests/integration/HTTPIntegrationTests.m::testCommittedFileBodyPathStreamsCompleteBody_ARLEN_BUG_023` |
| Long-lived workers accumulate `/dev/null` descriptors until PDF `GET` responses fail with `Failed to create pipe to handle perform in thread` | accepted as open Arlen-facing production reliability bug; root cause not yet isolated | `docs/OPEN_ISSUES.md::ISSUE-004`, `docs/PHASE38_ROADMAP.md`, Phase 10M soak `/dev/null` FD drift tripwire |

## Notes

### ARLEN-BUG-023: File-body response truncation

- Downstream observed `200 OK`, `Content-Type: application/pdf`,
  `Content-Length: 2114270`, and `Accept-Ranges: bytes`, but clients received
  zero body bytes and reported a truncated transfer.
- The same endpoint worked when the application replaced `fileBodyPath` with an
  in-memory `NSData` response, confirming that the file existed and the failure
  was in the Arlen file-body transmission path.
- Root cause:
  - Arlen serialized and sent success headers before proving that the
    `fileBodyPath` descriptor could be opened and validated.
  - If file preflight or streaming failed, the writer ignored the failure after
    the `200 OK` headers had already gone out.
- Current upstream behavior:
  - file-body responses are preflighted before success headers are sent
  - invalid file-body metadata now returns Arlen's fallback `500 Internal Server
    Error` before advertising the original successful response
  - `HEAD` requests preserve headers, including `Content-Length`, while omitting
    the file body
- Regression coverage:
  - `HTTPIntegrationTests::testCommittedFileBodyPathStreamsCompleteBody_ARLEN_BUG_023`
  - `HTTPIntegrationTests::testCommittedFileBodyPathHeadOmitsBody_ARLEN_BUG_023`
  - `HTTPIntegrationTests::testCommittedFileBodyPathPreflightFailureReturns500BeforeHeaders_ARLEN_BUG_023`

### ARLEN-BUG-024: `/dev/null` descriptor leak under uptime

- Downstream observed both production workers at `1023/1024` open descriptors.
- The dominant descriptor target was `/dev/null`, with roughly `970` entries in
  one worker and `967` in the other.
- Document metadata endpoints continued to work while full PDF `GET` responses
  failed after uptime; `HEAD` on the same PDF path could still succeed.
- The representative controller exception reason was
  `Failed to create pipe to handle perform in thread`, which is a GNUstep Base
  exception string surfaced after descriptor exhaustion.
- Arlen's visible file-response send path preflights and closes per-request
  file descriptors, and the static file descriptor cache is bounded, so the
  current investigation target is broader than a missing close in the
  `fileBodyPath` happy path.
- Upstream added a Phase 10M soak tripwire that tracks `/dev/null` descriptor
  drift during validated `fileBodyPath` traffic. That tripwire passed locally
  at short scale and does not yet reproduce the production failure.
- Phase 38 tracks the planned staging reproduction, tracing, root-cause fix,
  regression hardening, and operational diagnostics.

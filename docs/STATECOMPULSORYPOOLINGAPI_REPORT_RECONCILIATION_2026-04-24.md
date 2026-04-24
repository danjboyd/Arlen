# StateCompulsoryPoolingAPI Report Reconciliation

Date: `2026-04-24`

This note records the upstream Arlen assessment of the file streaming response
report from `StateCompulsoryPoolingAPI`.

Ownership rule:

- Arlen records upstream status only.
- `StateCompulsoryPoolingAPI` keeps app-level closure authority.
- Status below should be read as the upstream status/evidence trail.
  Downstream revalidation still belongs to `StateCompulsoryPoolingAPI`.

## Current Upstream Assessment

| StateCompulsoryPoolingAPI report | Upstream status | Evidence |
| --- | --- | --- |
| `ALNResponse.fileBodyPath` responses send headers with `Content-Length` but no body bytes when file streaming fails | fixed upstream; awaiting downstream revalidation | `src/Arlen/HTTP/ALNHTTPServer.m`, `tools/boomhauer.m`, `tests/integration/HTTPIntegrationTests.m::testCommittedFileBodyPathStreamsCompleteBody_ARLEN_BUG_023` |

## Notes

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

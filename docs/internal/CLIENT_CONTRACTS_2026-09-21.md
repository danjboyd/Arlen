# Downstream HTTP/data contract follow-up

Scope: GitHub issues #25, #26, #27, and #28, reviewed against main `ad14193`.
Three implementation groups cover four independently closeable upstream issues.
Downstream OT parity/adoption remains owned by OT.

## PostgreSQL precision (#28)

The public decode/rebind contract now targets 1900–2100 microsecond round trips
through NSDate, with scalar/array binding and negative epochs. Formatting splits
whole seconds from the fractional interval before rounding; it does not multiply
an epoch-sized double by one million. UTC normalization and timezone-free SQL
semantics are documented in ARLEN_DATA.md. Text selection with explicit SQL casts
is the lossless path for extended years, infinity, and values outside that range.

Local regression work also reproduced an exact-zero reference-date construction
problem on the installed GNUstep runtime. ALNPg uses Foundation NSCalendarDate
for that single interval and normalizes decoder construction through the same
helper. Do not remove this workaround without running the reference-epoch cases
on the supported GNUstep toolchain.

## Dataverse policies (#27)

The client owns one retry loop. A caller-supplied delay provider receives the
request, retry index, response or error. It controls eligibility and Retry-After
precedence; maxRetries remains the upper bound. A sleeper injection enables
captured-transport tests with exact attempt and delay assertions. Existing
status eligibility, linear fallback, error diagnostics, and batch routing remain
the defaults. DATAVERSE.md includes an explicit ordinary/batch policy example.

## HTTP result API (#25, #26)

Existing functions retain their contracts. The additive result API uses libcurl
on both GNUstep and Apple because the existing Apple NSURLSession surface does
not expose the actual received phrase. Apple links system libcurl. Manual
single-hop requests consume each response fully, enforce one chain deadline,
and preserve boundary bodies without replaying the boundary request. Origin
changes strip explicit authorization/cookies. HTTP_CLIENT.md defines redirect
methods, phrase absence, errors, and memory/cookie behavior.

## Evidence and closure

- GNUstep: PgTests against a mandatory disposable database, existing ORM and SQL
  builder suites, HTTPCompatTests, Dataverse focused suites, unit suite, and
  runtime concurrency gate.
- Apple: the existing confidence workflow adds the same HTTP/retry regressions
  and live timestamp test via Apple XCTest and a private PostgreSQL cluster.
- Existing required Linux quality, sanitizer, and docs jobs remain the merge gate.
- The upstream issues may close after implementation and platform evidence land;
  record OT as awaiting downstream revalidation until its owner adopts a clean
  export and reruns its provider/worker comparisons. No provider write is needed
  for upstream regression coverage.

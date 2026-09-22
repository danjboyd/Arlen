# Static files

Arlen's HTTP server serves configured static mounts before application dispatch.
With `serveStatic = YES`, the default `/static/` mount serves the application's
`public/` directory. Custom mounts retain their configured extension allowlists.
Static responses do not pass through application response middleware.

## Validators and conditional requests

Successful static GET and HEAD responses include `ETag`, `Last-Modified`, `Date`,
`Content-Type`, `Content-Length`, and `Accept-Ranges: bytes`. HEAD preserves the
full GET representation length and metadata while sending no body.

ETags are weak validators derived from file device, inode, size, modification time
and change time, including subsecond timestamps where the platform exposes them.
They avoid hashing or loading the entire file for each request. Treat the tag as
opaque: it is suitable for cache revalidation, not a content digest or a portable
identifier across machines. Deploy assets using atomic replacement; modifying a
file while it is being transmitted does not provide snapshot isolation.

`Last-Modified` uses whole-second HTTP date precision and never exceeds `Date`.

- `If-None-Match` uses weak comparison, accepts tag lists and `*`, and returns 304
  when a tag matches. Invalid tag syntax does not match.
- When `If-None-Match` is present, `If-Modified-Since` is ignored, even if the tag
  does not match. Otherwise, a valid date at or after the modification time yields
  304. Invalid dates are ignored.
- Matching conditional GET and HEAD responses have no body. A 304 includes the
  validators and Date and omits Content-Length.
- `If-Match` uses strong comparison (`*` succeeds for an existing asset; the weak
  static ETag cannot satisfy a tag comparison). Failure returns 412.
- `If-Unmodified-Since` is evaluated only when `If-Match` is absent; a file newer
  than a valid supplied date yields 412. These preconditions precede cache
  revalidation and range selection.

This ordering follows [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html#section-13.2.2).
In particular, a matching ETag combined with an older If-Modified-Since returns
304. This intentionally differs from the Mojolicious behavior reported in
[issue #30](https://github.com/danjboyd/Arlen/issues/30), which returned 200.

## Byte ranges

GET supports a single byte range, with inclusive byte offsets:

| Request | Behavior |
| --- | --- |
| `Range: bytes=0-3` | 206 containing the first four bytes |
| `Range: bytes=4-` | 206 containing the remainder from byte four |
| `Range: bytes=-4` | 206 containing the last four bytes |
| End beyond the file | Clamp the end to the last byte |
| Start beyond the file, or zero-length suffix | 416 with `Content-Range: bytes */<size>` |
| Range on an empty file | 416 with `Content-Range: bytes */0` |
| Malformed, overflowing, unknown-unit, or multiple ranges | Ignore Range and return the full 200 response |
| Range on HEAD | Ignore Range; preserve full representation metadata and send no body |

A 206 includes the selected Content-Length and
`Content-Range: bytes <start>-<end>/<full-size>`. Ranges are evaluated only after
preconditions; a matching cache validator still yields 304.

`If-Range` permits a partial response only with an exact matching Last-Modified
HTTP date at least 60 seconds older than the current response Date. Weak ETags,
nonmatching tags or dates, malformed values, and recent dates result in a full
200 response. The server's weak ETag cannot satisfy If-Range's strong comparison.
Without Range, If-Range has no effect.

Static transfers stream from disk, using sendfile where available and a bounded
read buffer otherwise. Range offsets and transfer lengths are separate from the
full file size used by file-identity checks. Canonical redirects, MIME selection,
allowlists, traversal checks and symlink protections apply before conditional
requests and ranges; validators never turn an inaccessible asset into a 304.

## Verification

The XCTest `HTTPIntegrationTests` suite includes wire-level coverage for both HTTP
parsers, sendfile fallback, disabled file-descriptor caching, concurrent ranges,
changed files, and persistent connections. Run with the repo-local runner:

```bash
source tools/source_gnustep_env.sh
make boomhauer
make test-integration-filter TEST=HTTPIntegrationTests
```

The existing Linux quality gate runs these integration tests. Downstream apps
must separately validate and adopt the pinned fix revision before claiming their
own static-file parity or deployment qualification.

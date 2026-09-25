# Static files

Arlen's HTTP server serves configured static mounts before application dispatch.
With `serveStatic = YES`, the default `/static/` mount serves the application's
`public/` directory. Custom mounts retain their configured extension allowlists.
Static responses do not pass through application response middleware.

## Content types

`Content-Type` comes from the shared `ALNMIMETypes` extension table, which
static mounts and controller file responses both use. It covers every extension
in the default allowlist (css, js, json, txt, html/htm, svg, png, jpg/jpeg, gif,
ico, webp, woff, woff2, map, xml) plus common documents (pdf, csv, mjs, wasm,
webmanifest), images (avif, heic), audio (mp3, m4a, aac, ogg/oga/opus, wav,
weba, flac) and video (mp4, m4v, webm, mov). Unknown extensions are served as
`application/octet-stream`. Adding an extension to `staticAllowExtensions` does
not by itself give it a type.

Apps can add or override entries with a top-level `mimeTypes` dictionary. Keys
are extensions, matched case-insensitively and without a leading dot:

```plist
mimeTypes = {
  glb = "model/gltf-binary";
  m4a = "audio/x-m4a";
};
```

Values that contain control characters or lack a `/` are ignored.

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

## Controller file responses

Static mounts run before routing and middleware, so they cannot serve private
files. Controllers that serve files behind session or auth checks should use:

```objc
- (id)show:(ALNContext *)ctx {
  NSString *path = [self.mediaRoot stringByAppendingPathComponent:record.storedName];
  [self renderFileAtPath:path
             contentType:record.contentType            // nil: use the extension table
                 options:@{
                   ALNFileResponseCacheControlOption : @"private, max-age=300",
                   ALNFileResponseDownloadNameOption : record.originalName, // optional
                 }];
  return nil;
}
```

`renderFileAtPath:contentType:options:` applies the same validators,
conditional requests, single byte ranges, HEAD handling and sendfile transfer as
static mounts. Safari and iOS need this for `<audio>` and `<video>`: they will
not play or seek media unless the server answers `Range: bytes=0-1` with a 206.
A missing or non-regular file renders a 404, and the method returns `NO`.

- The controller is responsible for authorizing access and for building the path.
  Never join an unvalidated request parameter onto a directory.
- `ALNFileResponseCacheControlOption` sets `Cache-Control`. Nothing is sent by
  default.
- `ALNFileResponseDownloadNameOption` sends `Content-Disposition: attachment`
  with an ASCII fallback filename and an RFC 5987 UTF-8 `filename*`.
- `ALNFileResponseETagOption` replaces the weak metadata ETag, for example with a
  stored content hash. A bare value is quoted. A strong caller-supplied ETag can
  satisfy `If-Range`, which the weak metadata ETag never can.
- `ALNFileResponseMIMETypesOption` overrides the app's `mimeTypes` for one call.
- HEAD needs a route of its own (`HEAD` or `ANY`), because routes do not fall
  back from HEAD to GET.

Code that builds a response outside a controller can call
`+[ALNFileResponse prepareResponse:forRequest:filePath:contentType:options:]`
directly.

## SPA history fallback

A single-page app owns client-side URLs such as `/explorers/3/map`. When the
browser reloads one of them, the server must answer with the app shell. Configure
`spaFallback` instead of writing a catch-all route:

```plist
staticMounts = ({ prefix = "/assets"; directory = "public/app/assets"; });
spaFallback = {
  file = "public/app/index.html";              // relative to the app root, or absolute
  excludePrefixes = ("/api", "/auth", "/media");
  // prefix = "/app";                          // limit the fallback to one subtree (default "/")
  // cacheControl = "no-cache";                // default
  // allowDottedPaths = NO;                    // default
};
```

The shell is served only when **all** of the following hold. Every other request
gets exactly the 404 it gets today.

- No route matched, and no built-in endpoint handled the request. Built-ins
  include `/openapi.json`, the OpenAPI docs pages and `/arlen/live.js`.
- The method is `GET` or `HEAD`.
- The path is under `prefix` and not under any `excludePrefixes` entry. Both
  match on segment boundaries: `/api` covers `/api/x`, but not `/apiary`.
- The request is an HTML navigation. `Accept` must contain `text/html`; a bare
  `*/*` (the `fetch()` and `curl` default) does not qualify. JSON-preferring
  requests and `apiOnly` apps never get the shell.
- The last path segment has no `.`, unless `allowDottedPaths = YES`. A missing
  `/assets/app-3f9a.js` therefore stays a 404 instead of returning HTML.

The shell is dispatched like a route (`arlen_spa_fallback`, handled by
`ALNSPAFallbackController`), so the app's middleware applies. It gets security
headers, the session and CSRF cookies, and rate limits. It is served with
ETag/304 and HEAD support and `Cache-Control: no-cache`, so a redeploy is picked
up on the next navigation. The status is always 200; the SPA renders its own
not-found view.

Precedence, from first to last:

1. static mounts (each owns its prefix, including 404s for missing files)
2. mounted child applications
3. `/healthz`, `/readyz`, `/livez`, `/metrics` and `/clusterz`
4. routes, including an app's own `/*path` wildcard, which therefore replaces
   the fallback (startup logs a warning)
5. route-miss built-ins
6. the SPA fallback
7. 404

Put hashed assets on a static mount; with `cacheControl` they can be cached
immutably.

A missing shell file logs a warning at startup rather than failing, because a
frontend dev server may be serving the app. Requests then get a 404 until the
build exists. Invalid values fail `startWithError:`. Code can configure the same
behavior with `-[ALNApplication setSPAFallbackFile:options:error:]`.

## Verification

The XCTest `HTTPIntegrationTests` suite includes wire-level coverage for both HTTP
parsers, sendfile fallback, disabled file-descriptor caching, concurrent ranges,
changed files, persistent connections, and content types. `FileResponseTests`
covers the MIME table and controller file responses behind session middleware.
Run with the repo-local runner:

```bash
source tools/source_gnustep_env.sh
make boomhauer
make test-integration-filter TEST=HTTPIntegrationTests
make test-unit-filter TEST=FileResponseTests
make test-unit-filter TEST=SPAFallbackTests
```

The existing Linux quality gate runs these integration tests. Downstream apps
must separately validate and adopt the pinned fix revision before claiming their
own static-file parity or deployment qualification.

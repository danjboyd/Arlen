# Outbound HTTP client

Import `ALNHTTPCompat.h` (also included by `Arlen.h`). Run synchronous requests on
a worker when blocking the caller would stall application request handling.

## Calling third-party APIs: ALNHTTPClient

For app code that calls vendor APIs, use `ALNHTTPClient` (`ALNHTTPClient.h`, also
in `Arlen.h`). It refuses to talk to any host you did not list:

```objc
NSError *error = nil;
ALNHTTPClient *client = [[ALNHTTPClient alloc] initWithConfiguration:@{
  @"allowedHosts" : @[ @"api.vendor.example", @"hooks.vendor.example:8443" ],
  @"timeoutSeconds" : @10,
} error:&error];
client.logger = application.logger; // optional

ALNHTTPClientResult *result =
    [client POSTJSONObject:@{ @"ticket" : @42 }
                     toURL:[NSURL URLWithString:@"https://api.vendor.example/v1/events"]
                   headers:@{ @"Authorization" : [@"Bearer " stringByAppendingString:token] }
                     error:&error];
```

| Key | Default | Meaning |
| --- | --- | --- |
| `allowedHosts` | required | Hostnames, optionally `host:port`. A bare host allows only the scheme's default port. Exact, case-insensitive; no wildcards. |
| `timeoutSeconds` | 10 (1–300) | One deadline for the whole request, redirects included. |
| `maxResponseBytes` | 1048576 (at most 64 MiB) | Response body limit, checked against `Content-Length` and while streaming. |
| `maxRedirects` | 0 (at most 10) | With 0 a 3xx is returned as the result (`stoppedAtRedirectLimit`). |
| `allowHTTP` | NO | Allow plain `http` URLs, for example a loopback service. |
| `idleTimeoutSeconds` | 30 (1–300) | Streaming only: maximum silence between incoming response bytes, including waiting for headers. |
| `streamingTimeoutSeconds` | 900 (1–86400) | Streaming only: one total deadline, redirects included. Buffered requests still use `timeoutSeconds`. |

The configuration is checked at construction; unknown keys and out-of-range
values are errors. Then, per request:

- The URL must be `https` (or `http` with `allowHTTP`), must not carry
  `user:password@`, and its host and port must be on the allowlist. Anything
  else fails with `ALNHTTPClientErrorHostNotAllowed` or
  `ALNHTTPClientErrorInvalidRequest` before a connection is made.
- Methods are GET, HEAD, POST, PUT, PATCH and DELETE. HTTP error statuses are
  results, not errors.
- Redirects are followed only up to `maxRedirects`, and every hop must also be
  on the allowlist (`ALNHTTPClientErrorRedirectNotAllowed` otherwise). A request
  carrying `Authorization` or `Cookie` is never redirected: the 3xx is
  returned, so a credential is not replayed to wherever a server points it.
  Other headers, such as an API-key header, go only to allowed hosts but are
  kept across allowed redirects.
- Errors (`ALNHTTPClientErrorDomain`) have fixed descriptions; they name at
  most the host and port, never headers, bodies, paths or query strings.
- With `logger` set, each request is logged once (`event=http_client.request`,
  info on success, warn on failure) with method, host, path, status, duration,
  byte count and redirect count. Headers, bodies and query strings are never
  logged.

Requests are synchronous and use the same libcurl transport as
`ALNSynchronousHTTPResult` on GNUstep and Apple (TLS verification on, no shared
cookie store, TLS and asynchronous DNS required). The allowlist checks host
names, not resolved addresses, so it does not defend against an allowed name
that resolves somewhere unexpected.

## Incremental response delivery

Use `streamRequest:cancellation:onResponse:onData:error:` for vendor streams,
SSE wire data, NDJSON, or downloads. It is synchronous: run it on an application
worker so it does not block request handling. Headers and data callbacks run
serially on that same worker, and none run after the method returns. The client
does not retain the response body or create an unbounded callback queue.

```objc
ALNHTTPClient *streamClient = [[ALNHTTPClient alloc] initWithConfiguration:@{
  @"allowedHosts" : @[ @"api.vendor.example" ],
  @"idleTimeoutSeconds" : @30,
  @"streamingTimeoutSeconds" : @900,
} error:&error];
ALNHTTPClientCancellation *stop = [ALNHTTPClientCancellation new];
// Keep `stop` in the app's operation state. A Stop button or browser disconnect
// can call [stop cancel] from another thread, even while the vendor is silent.
NSURLRequest *request = [NSURLRequest requestWithURL:
    [NSURL URLWithString:@"https://api.vendor.example/events"]];
NSFileHandle *output = [NSFileHandle fileHandleWithStandardOutput];
BOOL complete = [streamClient streamRequest:request cancellation:stop
    onResponse:^BOOL(NSHTTPURLResponse *response) {
      // Inspect status/headers once, before receiving any body bytes.
      return YES;
    } onData:^BOOL(NSData *data) {
      [output writeData:data];
      return YES;
    } error:&error];
if (!complete) {
  // Earlier bytes may already have been written. Mark this operation failed
  // or cancelled; do not treat that partial output as a complete response.
}
```

The streaming contract is:

- `onResponse` runs once for the final response. Interim responses, proxy CONNECT
  headers, followed redirects and their bodies, and trailers are not exposed.
  With redirects disabled, or with `Authorization`/`Cookie`, a 3xx is the final
  response, matching the buffered API. HTTP error statuses remain responses.
- `onData` receives arbitrary nonempty byte chunks in order. Chunks may divide
  UTF-8 characters, SSE lines/events, or JSON records. They are not HTTP chunk
  frames. Retain the `NSData` if it is needed after the callback. Arlen does not
  yet provide an SSE reader or automatic event reconnection.
- Return `NO` from either callback to stop with `ALNHTTPClientErrorCancelled`.
  The optional token is thread-safe and permanently cancelled once used; a
  pre-cancelled token prevents a connection. Cancellation is checked between
  callbacks and roughly every 100 ms while waiting on the transport. It cannot
  interrupt application code inside a callback; keep callbacks short. Slow
  callbacks naturally slow network consumption, and their time counts toward
  the deadlines.
- `idleTimeoutSeconds` measures silence between incoming header/body bytes,
  including connection setup and waiting for the first response. Outgoing
  uploads do not reset it. A stall fails with `ALNHTTPClientErrorIdleTimedOut`.
  `streamingTimeoutSeconds` caps the complete request chain and fails with
  `ALNHTTPClientErrorTimedOut`; heartbeats cannot extend it. Configuration values
  use the same integer/decimal-string validation as the other bounds.
- `maxResponseBytes` counts the running total of body bytes across all hops,
  including discarded redirect bodies, and rejects oversized `Content-Length`
  declarations. A chunk that would exceed the remaining budget is not delivered.
  TLS verification, host checks on every hop, credential redirect restrictions,
  and sanitized logging/errors match the existing client. Content encodings
  are not implicitly decoded.
- `YES` means the response completed. Disconnects, cancellation, timeouts and
  size failures return `NO` and a sanitized error after any earlier delivered
  data. Callback exceptions become `ALNHTTPClientErrorTransport` without exposing
  their names or descriptions. The caller owns partial-output cleanup.
- Set request bodies with `HTTPBody`; `HTTPBodyStream` is rejected before
  connecting. POST-to-GET redirects and 307/308 body replay retain the existing
  method rules. The buffered request methods and compatibility helpers retain
  their existing deadlines, buffering and error behavior.

## Existing helpers

`ALNSynchronousURLRequest` follows at most ten redirects.
`ALNSynchronousURLRequestFollowingRedirects` accepts an explicit budget. A zero
budget returns the initial response; exceeding a positive budget returns nil
with `NSURLErrorHTTPTooManyRedirects`. HTTP error statuses are responses, while
transport failures use `NSURLErrorDomain`. GNUstep uses libcurl; Apple uses
`NSURLSession`. These defaults have not changed.

## Received data and redirect boundaries

Use the additive result API to inspect the actual received HTTP/1.x reason phrase
or return a redirect response at the budget boundary:

```objc
NSError *error = nil;
ALNHTTPClientResult *result = ALNSynchronousHTTPResult(
    request, 3, ALNHTTPRedirectLimitReturnResponse, &error);
if (result != nil) {
  NSInteger status = result.response.statusCode;
  NSDictionary *headers = result.response.allHeaderFields;
  NSData *body = result.body;
  NSString *receivedPhrase = result.receivedReasonPhrase;
  BOOL stopped = result.stoppedAtRedirectLimit;
}
```

A budget of three permits four requests: the initial request and three followed
redirects. If the fourth response is still a redirect, the return policy returns
that response's status, URL, headers, and complete body without issuing another
request. `stoppedAtRedirectLimit` distinguishes that outcome from a normal final
response. With budget zero, either policy returns the initial response. Select
`ALNHTTPRedirectLimitError` to fail on exhaustion of a positive budget instead.

The phrase comes from the final response's status line, including its original
spacing. Interim responses and earlier redirect hops cannot supply it. An empty
HTTP/1.x phrase is `@""`; HTTP/2 and HTTP/3 have no transmitted phrase and produce
nil. No localized or canonical description is substituted. Display a fallback
separately if your application needs one.

## Transport contract

The result API uses libcurl on **both GNUstep and Apple**, allowing the received
phrase to remain available on Apple as well. Apple build scripts link the system
libcurl; custom embedders must link `-lcurl`. TLS and asynchronous DNS support are
required. Supported wire versions depend on the installed libcurl; the API does
not promise HTTP/3 availability. The older Apple helpers retain NSURLSession.

All request helpers validate retained headers before connecting. Header names
must be nonempty HTTP token strings, and values must be strings without CR, LF
or NUL. The compatibility helpers return `NSURLErrorDomain/NSURLErrorBadURL`
for invalid headers; `ALNHTTPClient` retains its `InvalidRequest` error contract.
Validation runs before both libcurl and Apple's NSURLSession transport and is
repeated for each libcurl hop.

Only HTTP/HTTPS are followed. TLS peer and hostname verification stay enabled.
There is no shared cookie store or automatic cookie persistence. Authorization
and explicit Cookie headers are removed when a redirect changes scheme, host,
or effective port; they are not restored on a later return to the original
origin. Other application headers may be forwarded: choose them accordingly.
POST becomes GET on 301/302; 303 becomes GET except for HEAD. 307/308 preserve
method and body. Request body streams are buffered once for replay.

The request timeout (60 seconds when unspecified/nonpositive) bounds the complete
chain, including reading boundary bodies. A timeout, disconnect, invalid redirect
protocol, or TLS failure returns nil and an error, never a successful partial
response. Bodies are buffered in memory. The bounded metadata helper remains a
separate API with its own size limits and redirect rejection.

`ALNBoundedJSONRequest` provides bounded GET and form POST for trusted JSON
endpoints, using the same libcurl implementation on GNUstep and Apple. It accepts URL, method, body, and timeout from `NSURLRequest`, sets
JSON Accept/form Content-Type headers, requires HTTP 200, rejects redirects,
and disables shared cookies. Its caller supplies a response byte limit. Errors
are sanitized; request secrets and response bodies are not included.

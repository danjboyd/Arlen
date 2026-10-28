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
  provide automatic event reconnection. For bounded SSE framing, use
  `ALNSSEReader` as described below.
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

## Bounded SSE reader

Import `ALNSSEReader.h` (also exported by `Arlen.h`) and create one reader per
response. Feed each `onData` chunk directly to `consumeData:onEvent:error:`.
Events are delivered inline on the caller's thread, before consumption returns;
the reader retains neither the input chunks nor an output queue. Keep callbacks
short and bound any application-owned event history. The reader is confined to
one caller; concurrent use and calls back into the reader from its handler are
unsupported. Reentrant calls fail permanently.

```objc
ALNSSEReader *reader = [ALNSSEReader new];
__block NSError *readerError = nil;
__block BOOL sawTerminal = NO;
__block BOOL acceptedResponse = NO;
NSError *httpError = nil;
BOOL httpComplete = [streamClient streamRequest:request cancellation:stop
    onResponse:^BOOL(NSHTTPURLResponse *response) {
      acceptedResponse = response.statusCode == 200 &&
          [[response.MIMEType lowercaseString] isEqualToString:@"text/event-stream"];
      return acceptedResponse;
    } onData:^BOOL(NSData *chunk) {
      return [reader consumeData:chunk onEvent:^BOOL(ALNSSEEvent *event) {
        // Decode/validate event.data and apply the app's own protocol here.
        // "app_done" is an example app-defined event, not an Arlen convention.
        if ([event.eventType isEqualToString:@"app_done"]) sawTerminal = YES;
        return YES;
      } error:&readerError];
    } error:&httpError];
BOOL framed = [reader finishWithError:&readerError];
BOOL complete = httpComplete && acceptedResponse && framed && sawTerminal;
if (!complete) {
  NSError *failure = readerError ?: httpError;
  // Mark output incomplete, including clean HTTP EOF without the app terminal.
  // `failure` can be nil in that clean-EOF case; report an app protocol failure.
}
```

Use an `Accept: text/event-stream` request header and require an encoding your
application can consume. HTTP content encodings are not decoded by either this
reader or the streaming transport. The HTTP client's cumulative body budget,
idle/total deadlines, allowlist and cancellation remain in force independently.
A parser failure returns `NO` from `onData`, so the HTTP client reports callback
cancellation; preserve the separate reader error for the actual parsing reason.

The framing rules follow the [SSE field and dispatch format](https://html.spec.whatwg.org/multipage/server-sent-events.html#parsing-an-event-stream),
with an explicit strict UTF-8 policy:

- CR, LF and CRLF terminate lines, including CRLF divided across chunks. UTF-8
  characters and the initial BOM may also span chunks. Exactly one leading BOM
  is ignored; BOMs elsewhere remain content. Malformed UTF-8 in a completed
  line fails with `ALNSSEReaderErrorInvalidUTF8`, rather than the replacement
  decoding used by browser `EventSource`.
- `data` fields join with LF; the final appended LF is removed at dispatch.
  A blank line dispatches only if at least one `data` field occurred. `data`
  without a colon is an empty data field and can dispatch an empty payload.
- The last `event` field wins; an empty or absent type becomes `message`.
  Type and data reset at each blank line, even when no event is dispatched.
  IDs persist across events; an empty `id` resets the ID and IDs containing NUL
  are ignored. `ALNSSEEvent` exposes immutable `eventType`, `data` and
  `lastEventID` strings. A colon splits only once, and only one leading ASCII
  space is removed from a field value. Names are case sensitive.
- Comments and unknown fields are ignored. `retry` is ignored: this helper does
  not schedule requests, retry, reconnect, or send `Last-Event-ID` headers.
- EOF never dispatches an unfinished line or event. `finishWithError:` discards
  it and closes the reader; repeated finish succeeds, but further consumption
  fails. Finish is a framing operation and does not certify protocol completion.

Default limits are **65536 raw UTF-8 bytes per line** (excluding its CR/LF,
including a leading BOM) and **1048576 accumulated data bytes per event**.
The event budget includes UTF-8 field values and one LF per data field, including
that final LF removed at dispatch. For example, `data: é` uses three event bytes.
Event type and persistent ID are each bounded by the line limit. Comments and
unknown fields are also line-bounded; repeated ignored fields do not accumulate.
These bounds limit reader storage even for a large input chunk. Use positive
limits with `initWithMaxLineBytes:maxEventBytes:error:` to change them; zero is
invalid. Limits are checked before extending the relevant buffer, and arithmetic
uses remaining capacity to avoid overflow.

Limit, decoding, invalid-state and handler-stop errors are permanent, use
`ALNSSEReaderErrorDomain`, and contain fixed descriptions without stream content.
Earlier events remain delivered. A handler returning `NO` stops with
`ALNSSEReaderErrorStopped`. A thrown handler exception propagates and permanently
stops the reader; inside the HTTP client's callback it becomes the client's
sanitized transport error. Create a fresh reader to process another response.

As HelpDesk's streaming validation demonstrated, **apps must require their own
terminal event**. HTTP success, clean EOF, a final blank line, and successful
reader finish do not prove that an application response finished. A connection
can end cleanly between complete SSE events while omitting the app's terminal
signal. Arlen assigns no vendor-specific terminal-event meaning; the app owns
payload validation, completion, partial-output handling, and any retry policy.

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

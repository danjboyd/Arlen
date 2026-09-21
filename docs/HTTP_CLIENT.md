# Synchronous HTTP client

Import `ALNHTTPCompat.h` (also included by `Arlen.h`). Run synchronous requests on
a worker when blocking the caller would stall application request handling.

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

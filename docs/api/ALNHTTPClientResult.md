# ALNHTTPClientResult

- Kind: `interface`
- Header: `src/Arlen/Support/ALNHTTPCompat.h`

Complete final HTTP response returned by `ALNSynchronousHTTPResult`, including received phrase availability and redirect-budget termination. See [HTTP client](../HTTP_CLIENT.md).

## Typical Usage

```objc
ALNHTTPClientResult *result = ALNSynchronousHTTPResult(request, 3, ALNHTTPRedirectLimitReturnResponse, &error);
if (result) {
  NSData *body = result.body;
  NSString *phrase = result.receivedReasonPhrase; // nil for HTTP/2 or HTTP/3
}
```

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `response` | `NSHTTPURLResponse *` | `nonatomic, strong, readonly` | Final response URL, numeric status, and headers. |
| `body` | `NSData *` | `nonatomic, copy, readonly` | Complete final response body, including a redirect body when stopped at its budget. |
| `receivedReasonPhrase` | `NSString *` | `nonatomic, copy, readonly, nullable` | Actual HTTP/1.x phrase including spacing; empty string for an empty phrase, nil when the protocol transmits none. Never synthesized. |
| `stoppedAtRedirectLimit` | `BOOL` | `nonatomic, assign, readonly` | YES when a followable redirect was returned because the configured redirect budget was exhausted. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `init` | `- (instancetype)init NS_UNAVAILABLE;` | Unavailable. Results are constructed by the synchronous transport. | Call `ALNSynchronousHTTPResult(request, maxRedirects, policy, &error)`. |

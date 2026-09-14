# Response headers and multiple cookies

Use `ALNResponse` header methods to validate values and keep serialized response
headers current. Header names are case-insensitive.

| Method | Behavior |
| --- | --- |
| `setHeader:value:` | Replace every value for a name with one value. Invalid input is ignored. |
| `appendHeader:value:` | Append a separate header line for a supported repeatable name. Return `YES` on success; `NO` leaves the response unchanged. |
| `headerValuesForName:` | Return an immutable array of all values in insertion order, or an empty array. |
| `headerForName:` | Return the first value, or `nil`. It never comma-joins values. |
| `removeHeaderForName:` | Remove all values for the name. Removing an absent name does nothing. |

The legacy `headers` dictionary contains the first value for each normalized
name. Direct dictionary writes are not a supported way to maintain validation,
repeated values, ordering, or serialization caches; use the methods above.

## Issue multiple cookies

```objc
[ctx.response appendHeader:@"Set-Cookie"
                     value:@"preference=compact; Path=/; HttpOnly; SameSite=Lax"];
[ctx.response appendHeader:@"Set-Cookie"
                     value:@"remember=device-token; Path=/account; HttpOnly; SameSite=Lax"];
NSArray<NSString *> *cookies = [ctx.response headerValuesForName:@"set-cookie"];
```

Each cookie is written on its own `Set-Cookie` line. Commas inside `Expires`
attributes remain intact. Cookie values must already be properly encoded for
cookie syntax; header methods do not encode or interpret them.

Session middleware appends its cookie after controller processing for session
issuance, refresh, and expiration. Application cookies already on the response
are preserved. Callers needing every cookie must use `headerValuesForName:`;
`headerForName:` can now return an application cookie before the session cookie.
Keep ownership of the session cookie with session middleware. Arlen does not
deduplicate cookies by name, path, or domain.

A later `setHeader:@"Set-Cookie" value:...` intentionally replaces all cookies
accumulated so far. Use append when adding independent cookies.

## Expire cookies during logout

An expiration must target the original cookie's name, path, and domain. For
example, clear the session and append expiration headers for two app cookies:

```objc
[[self session] removeAllObjects];
[ctx.response appendHeader:@"Set-Cookie"
                     value:@"remember=; Path=/account; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT"];
[ctx.response appendHeader:@"Set-Cookie"
                     value:@"legacy_remember=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT"];
```

If the incoming request carried the session cookie, session middleware appends
its expiration as the third `Set-Cookie` line. If a cookie was originally issued
with a Domain attribute, use that same domain for its expiration. HEAD responses
retain all response cookie lines while omitting body bytes.

## Repeated headers and framing

Append is supported for this explicit allowlist:

- `Set-Cookie`
- `WWW-Authenticate` and `Proxy-Authenticate`
- `Link`
- `Warning`
- `Vary`
- `Cache-Control`

Other names return `NO`, including when the header is absent. In particular,
`Content-Length`, `Transfer-Encoding`, `Connection`, `Trailer`, `Host`, and
`Content-Type` cannot acquire repeated values through append. Use replacement
for singleton fields. No header values are automatically comma-joined.

Wire output sorts normalized header names and preserves insertion order within
each name. Appending retains the display spelling established by the first
value; replacement updates that spelling. CR, LF, and NUL are rejected in names
and values, and names must use ASCII HTTP token characters after trimming outer
whitespace. Validated values are copied, so later mutable-string changes cannot
alter the response.

Append, replacement, and removal invalidate the response's serialized header
cache. Identical replacement of a single value with the same display spelling
retains the cache. Removing cookies also permits ordinary shared-header cache
reuse; cookie-bearing responses do not use the shared cache. Automatically
supplied `Content-Length` and `Content-Type` are restored during serialization
if removed.

# Route Policies

Route policies are named middleware checks for protecting route groups and
framework surfaces. They are intended for coarse access gates such as source IP
allowlists and must be paired with normal application authentication,
CSRF protection, audit logging, and rollback/revision controls for
administrative workflows.

## Configuration

```plist
security = {
  trustedProxies = (
    "127.0.0.1/32",
    "10.0.0.0/8",
    "::1/128"
  );

  routePolicies = {
    admin = {
      pathPrefixes = ("/admin");
      requireAuth = YES;
      trustForwardedClientIP = YES;
      sourceIPAllowlist = (
        "127.0.0.1/32",
        "10.0.0.0/8",
        "203.0.113.10/32"
      );
    };
  };
};
```

Policy names must start with a letter or underscore and then contain only
letters, digits, or underscores. Invalid names, invalid CIDR ranges,
unsupported fields, and route-side references to missing policy names fail
application startup.

Supported policy fields:

- `pathPrefixes`: paths protected by this policy.
- `sourceIPAllowlist`: IPv4 and IPv6 CIDR ranges. A bare IP is treated as an
  exact host match.
- `trustForwardedClientIP`: when true, the client IP comes from
  `X-Forwarded-For` (or `Forwarded`, see below), but only if the direct peer
  matches `security.trustedProxies`.
- `requireAuth`: deny when the resolved context has no authenticated subject.

`pathPrefixes` and `sourceIPAllowlist` are lists. A single string, such as
`sourceIPAllowlist = "10.0.0.0/8";`, counts as a one-element list. A list that
is present but empty, like `()` or `("")`, fails startup with `empty_list`.
Any other type fails with `invalid_type`. If a policy with an empty or mistyped
`sourceIPAllowlist` is reached anyway, the request is denied with
`invalid_policy_config`. The source-IP check is never skipped.

## Proxy Resolution

Default behavior is deterministic and fail-closed:

- With no trusted proxy configured, Arlen uses the direct socket peer IP.
- With trusted proxies configured, forwarded headers are used only when the
  immediate peer IP matches `security.trustedProxies`.
- If the immediate peer is not trusted, forwarded headers are ignored.
- The client is the **right-most** `X-Forwarded-For` hop that is not itself in
  `security.trustedProxies`. Proxies such as nginx
  (`$proxy_add_x_forwarded_for`), HAProxy (`option forwardfor`) and most load
  balancers append the peer they saw to whatever the client sent. So every hop
  left of the ones your proxies added is client-controlled and is never used.
  With several proxies in a chain, list all of them in `security.trustedProxies`
  and Arlen skips them from the right.
- Only one header is read. By default it is `X-Forwarded-For`, and a `Forwarded`
  header is ignored, because a proxy that sets only `X-Forwarded-For` passes a
  client's `Forwarded` header through untouched. If your proxy sets RFC 7239
  `Forwarded` instead, set `security.forwardedClientIPHeader = "Forwarded";`
  (the other accepted value is `"X-Forwarded-For"`; anything else fails
  startup). The server's `effectiveRemoteAddress`, and so the rate limiter,
  reads the same header. Repeated header lines are combined in order before
  the hops are read.
- If a protected allowlist check cannot resolve a usable client IP (no header,
  or a hop that is not an IP address where the client should be), the request
  is denied.

Behind nginx, configure `security.trustedProxies` to include only the private
address or subnet of the nginx peer that connects to Arlen. Do not include broad
public ranges. Clients can send any `X-Forwarded-For` value they like; Arlen
uses only the hops your trusted proxies appended.

## `/admin`

The admin UI is the first framework-owned route-policy consumer. If
`security.routePolicies.admin` is configured, every mounted admin route is
attached to the `admin` policy. Apps without `security.routePolicies.admin`
retain the existing admin behavior.

Local-only admin access:

```plist
security = {
  routePolicies = {
    admin = {
      sourceIPAllowlist = ("127.0.0.1/32", "::1/128");
    };
  };
};
```

LAN or private subnet access:

```plist
security = {
  routePolicies = {
    admin = {
      sourceIPAllowlist = ("10.0.0.0/8", "192.168.0.0/16");
    };
  };
};
```

Reverse-proxy access:

```plist
security = {
  trustedProxies = ("127.0.0.1/32");
  routePolicies = {
    admin = {
      trustForwardedClientIP = YES;
      sourceIPAllowlist = ("203.0.113.10/32");
    };
  };
};
```

`requireAuth` can be enabled for custom protected routes when the app has
session or bearer auth configured. Admin UI routes still keep their normal
admin-role and MFA checks; the route policy is an outer access gate, not a
replacement for those controls.

## Denial Diagnostics

Denied requests return `403`, set `X-Arlen-Policy-Denial-Reason`, and log
`route_policy.denied`.

Common denial reasons:

- `source_ip_denied`: client IP resolved, but it is outside the allowlist.
- `direct_peer_unresolved`: the direct remote address is not a valid IP.
- `forwarded_client_unresolved`: the direct peer is trusted, but forwarded
  client headers did not contain a valid IP.
- `authentication_required`: the policy requires an authenticated subject and
  none was available.
- `unknown_policy`: a route referenced a policy that is not configured.

Log fields include `policy`, `reason`, `route`, `path`, `client_ip`, and
`client_ip_source`.

## Verification

Run the focused confidence lane after changing route-policy behavior:

```bash
source tools/source_gnustep_env.sh
make phase35-confidence
```

Artifacts are written under `build/release_confidence/phase35/`.

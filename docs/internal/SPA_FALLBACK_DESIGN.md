# SPA History Fallback Design (GitHub issue 62, part 2)

Status: Draft for review
Last updated: 2026-09-25
Related: GitHub issue #62, PR #77 (static `cacheControl`, part 1), PR #70
(`ALNFileResponse`), `docs/STATIC_FILES.md`

## 1. Problem

A single-page app owns client-side URLs such as `/explorers/3/map`. When the
browser reloads one of them, the server must answer with the app shell
(`index.html`) instead of a 404. Today every Arlen SPA does this by hand. For
example, StateMap registers a wildcard `GET /*path` route in
`AppShellController`, then has to keep `/api`, `/auth` and `/media` out of it
and re-implement file serving.

The issue proposes putting this on a static mount:

```plist
staticMounts = ({ prefix = "/"; directory = "public/app"; spaFallback = "index.html";
                  spaFallbackExcludePrefixes = ("/api", "/auth", "/media"); });
```

That shape does not work with the current architecture.

## 2. Constraints found in the code

1. **Static mounts cannot use prefix `/`.** `ALNNormalizeMountPrefix` in
   `ALNApplication.m` returns nil for `/`, so a root mount is skipped with a
   "duplicate/invalid static mount entry" warning.
2. **A static mount owns its whole prefix.** `ALNStaticResponseForMount` runs in
   `ALNHTTPServer` before application dispatch. A request under the prefix that
   matches no file gets the mount's own 404. It never reaches routing, so a
   mount cannot know whether "no route matched".
3. **Static responses bypass middleware.** They get no security headers (CSP,
   frame options, and so on) and no session. An HTML app shell served from a
   mount has none of the headers the app configured. Route-miss 404s built in
   `-[ALNApplication dispatchRequest:]` also bypass middleware, because they
   are produced before the middleware chain runs.
4. **Some built-in endpoints are answered only on a route miss.**
   `ALNApplyBuiltInResponse` serves `/openapi.json`, `/.well-known/openapi.json`,
   `/openapi`, `/openapi/viewer`, `/openapi/swagger`, the `/docs/openapi*`
   aliases, and `/arlen/live.js` only after the router misses. A catch-all route
   registered in the router, which is what apps do today, silently shadows
   them. Only `/healthz`, `/readyz`, `/livez`, `/metrics` and `/clusterz` are
   reserved ahead of routing.
5. **Wildcard routes already rank last.** `ALNRouteShouldReplace` prefers route
   kind (static > param > wildcard), then more static segments, then earlier
   registration. That is fine for real routes, but it does not solve
   constraint 4.

## 3. Options considered

| Option | Where it runs | Knows "no route matched" | Middleware (security headers, session) | Built-ins win | Root SPA |
| --- | --- | --- | --- | --- | --- |
| A. `spaFallback` inside a static mount | HTTP server, before dispatch | No: the mount owns the prefix | No | n/a | No (`/` rejected) |
| B. Serve the shell at the route-miss point | `dispatchRequest:` 404 branch | Yes | No | Yes, if run after built-ins | Yes |
| C. Framework-registered `GET /*path` route | Router | Yes | Yes | **No**: shadows the openapi and live.js built-ins | Yes |
| **D. Synthesized fallback route at the route-miss point** | `dispatchRequest:` 404 branch, then the normal controller path | Yes | Yes | Yes | Yes |

**Recommendation: D.** When the router misses and no built-in handled the
request, dispatch treats an eligible request as if it had matched a
framework-owned `ALNSPAFallbackController#shell` route. Dispatch then continues
down the normal matched-route path. The shell therefore gets the app's
middleware (security headers, sessions, including the CSRF token cookie an SPA
needs on first load, rate limits), request logging and metrics under a stable
route name, and the same response finalization as any controller. Real routes
and built-ins always win, because the fallback is only considered after both
have declined.

Option A is still worth doing later, as a mount-local convenience for SPAs
under a non-root prefix that need no middleware. It is not needed for the
cases in the issue.

## 4. Proposed contract

### 4.1 Configuration

```plist
spaFallback = {
  file = "public/app/index.html";              // required
  prefix = "/";                                 // optional; fallback applies only under this path
  excludePrefixes = ("/api", "/auth", "/media"); // optional
  cacheControl = "no-cache";                    // optional; default "no-cache"
  allowDottedPaths = NO;                        // optional; default NO
};
```

- `file` resolves the same way as `staticMounts` directories: relative to the
  app root, or absolute.
- The programmatic equivalent is
  `-[ALNApplication setSPAFallbackFile:options:]`, with the same keys.
- Validation at startup:
  - A non-string or empty `file` is a configuration error.
  - A `prefix` or `excludePrefixes` entry must be a local absolute path. `/` is
    allowed as a `prefix`, but not in `excludePrefixes`.
  - A file that does not exist at startup is only a **warning**. In development
    the frontend is often served by Vite and not yet built. At request time a
    missing file produces the normal 404.

### 4.2 Eligibility

A request is served the shell only when **all** of these hold. Otherwise the
current 404 path runs unchanged: same JSON or plain-text body, same status,
still bypassing middleware.

1. The router found no route, no built-in handled the request, and
   `dispatchRequest:requiringRoute:` was not called with a required route.
2. The method is `GET` or `HEAD`.
3. The request path is within `prefix`, using a segment-boundary match, and not
   within any `excludePrefixes` entry. A segment-boundary match means `/api`
   matches `/api` and `/api/x`, but not `/apiary`.
4. The request is an HTML navigation:
   - The resolved request format is not `json`. This reuses
     `ALNRequestPreferredFormat`, so `apiOnly`, `/api` paths and JSON `Accept`
     all decline.
   - `Accept` explicitly contains `text/html`. A bare `*/*` is not enough, so
     `fetch()` and `curl` calls to a missing endpoint still get a 404. Browser
     navigations always send `text/html`.
5. The last path segment has no `.`, unless `allowDottedPaths = YES`. A missing
   `/assets/app-3f9a.js` must be a 404, not an HTML page served with a 200.

### 4.3 Response

- Served by `-renderFileAtPath:contentType:options:` (PR #70). This provides
  `Content-Type: text/html; charset=utf-8`, ETag/Last-Modified, 304 responses,
  HEAD support and sendfile.
- `Cache-Control` defaults to `no-cache`, so a redeploy is picked up on the
  next navigation.
- Status is `200`. The server cannot know whether the client route exists; the
  SPA renders its own not-found view.
- The request log and metrics record route name `arlen_spa_fallback` and
  controller `ALNSPAFallbackController`.
- `arlen routes` and `printRoutes` list it last, with source `spa_fallback`.

### 4.4 Precedence (complete order)

1. HTTP server static mounts. Each owns its prefix, including 404s for missing
   files, so hashed assets belong on a mount such as `/assets` with the
   immutable `cacheControl` from PR #77.
2. Mounted child applications (`mountApplication:atPrefix:`). A child app uses
   its own `spaFallback`, if configured.
3. Reserved operability endpoints (`/healthz`, `/readyz`, `/livez`, `/metrics`,
   `/clusterz`).
4. Router: static, then parameterized, then wildcard routes. An app's own
   `/*path` route still wins over the fallback. Startup logs a warning when an
   app has both a root wildcard `GET` route and `spaFallback`.
5. Route-miss built-ins: openapi, docs and `/arlen/live.js`.
6. **SPA fallback** (this design).
7. The 404, unchanged.

### 4.5 Recommended app layout (StateMap)

```plist
staticMounts = ({ prefix = "/assets"; directory = "public/app/assets";
                  cacheControl = "public, max-age=31536000, immutable"; });
spaFallback = { file = "public/app/index.html"; excludePrefixes = ("/api", "/auth", "/media"); };
```

With this, StateMap can delete `AppShellController` and its wildcard route.

## 5. Implementation sketch

- `ALNApplication` stores a normalized fallback descriptor and a prebuilt
  `ALNRoute` for `ALNSPAFallbackController#shell`. The route is not registered
  in the router, so matching cost and precedence are unchanged.
- In `dispatchRequest:`, restructure the `matchedRoute == nil` branch:
  1. Run `ALNApplyBuiltInResponse`. It commits the response only on a match;
     confirm this with a test before relying on it.
  2. If the built-ins did not handle the request and it is fallback-eligible,
     set `matchedRoute` to the fallback route with empty params and fall
     through to the normal matched-route path.
  3. Otherwise run today's 404 code, unchanged.
- `ALNSPAFallbackController` lives in `src/Arlen/MVC/Controller/`. It calls
  `renderFileAtPath:` with the resolved file and the configured
  `cacheControl`.
- Config normalization goes in `ALNConfig` (key `spaFallback`); there is no
  environment override in v1.
- Docs: a new "SPA history fallback" section in `STATIC_FILES.md`, plus
  `CONFIGURATION_REFERENCE.md`, the frontend starter docs
  (`FRONTEND_STARTERS.md`) and the release notes.

## 6. Test plan (issue acceptance plus design-specific checks)

Unit tests (in-process `dispatchRequest:`):

- A deep link (`/explorers/3/map`, `Accept: text/html`) returns 200, `text/html`,
  the shell body, and `Cache-Control: no-cache`.
- An excluded prefix (`/api/missing`, `/auth/x`) returns the unchanged 404.
  `/apiary` is not excluded.
- A real route wins; an app wildcard route wins.
- `Accept: application/json`, `*/*`, or no `Accept` header returns 404.
- A dotted last segment returns 404, unless `allowDottedPaths` is set.
- `POST` to a deep link returns 404.
- `/openapi.json` and `/arlen/live.js` still return the built-in responses
  while the fallback is configured.
- Middleware runs: the security headers are present, and a session cookie and
  CSRF token are issued.
- The `prefix` option limits the fallback to `/app/...`.
- A missing shell file returns 404 plus a startup warning. Invalid config fails
  startup.
- If-None-Match returns 304; HEAD returns no body.

Integration test (`HTTPIntegrationTests`): a wire-level deep link through
`boomhauer` with the shell served, plus a `/static` asset from the same
server.

## 7. Out of scope and follow-ups

- **Security headers on static-mount responses** (constraint 3). This is a
  general gap, independent of the SPA work. HTML served from mounts lacks the
  app's CSP. File it as its own issue.
- **Precompressed `.br`/`.gz` siblings** (optional in the issue). This needs
  `Accept-Encoding` negotiation, `Vary`, `Content-Encoding` and per-encoding
  ETags in `ALNFileResponse`. It is a separate change.
- **Mount-local `spaFallback`** (option A), for non-root SPAs that need no
  middleware. Add it only if asked for.

## 8. Decisions needed

1. Should an `Accept` of `*/*` alone decline the fallback? Recommended: yes. It
   keeps API clients on a 404; the cost is that an unusual client navigating
   with only `*/*` gets a 404.
2. Should the default `Cache-Control` for the shell be `no-cache`?
   Recommended: yes.
3. Should a missing shell file at startup be a warning rather than an error?
   Recommended: warning, so it works in development with a Vite dev server.

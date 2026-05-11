# Admin UI Module

The first-party `admin-ui` module ships one admin product with two surfaces:

- HTML-first admin pages under `/admin/...`
- headless JSON endpoints under `/admin/api/...`

Both surfaces are driven from the same resource definitions and now share the
same bulk-action, export, filter, sort, pagination, and autocomplete metadata.

## Resource Registration

Apps register resources through provider classes:

```plist
adminUI = {
  resourceProviders = {
    classes = ("MyOrdersAdminProvider");
  };
};
```

Each provider returns one or more objects conforming to `ALNAdminUIResource`.

Core resource responsibilities:

- resource identifier
- metadata
- list/detail/update handlers
- optional custom actions
- optional bulk actions
- optional exports
- optional autocomplete hooks
- optional policy hook

Useful metadata includes:

- `fields` with typed `kind`, `choices`, and optional `autocomplete`
- `filters` with `type`, placeholder text, and numeric/date bounds when needed
- `sorts` with explicit names, labels, and optional default direction
- `pageSize` and `pageSizes`
- `bulkActions`
- `exports`

The built-in `users` resource is only registered when `database.connectionString`
is configured. Provider-only app resources continue to work without a database.

## HTML Surface

Key endpoints:

- `GET /admin`
- `GET /admin/resources/:resource`
- `GET /admin/resources/:resource/:identifier`
- `POST /admin/resources/:resource/:identifier`
- `POST /admin/resources/:resource/:identifier/actions/:action`
- `POST /admin/resources/:resource/bulk-actions/:action`
- `GET /admin/resources/:resource/export/:format`

## JSON Surface

Key endpoints:

- `GET /admin/api/session`
- `GET /admin/api/resources`
- `GET /admin/api/resources/:resource`
- `GET /admin/api/resources/:resource/items`
- `GET /admin/api/resources/:resource/items/:identifier`
- `POST /admin/api/resources/:resource/items/:identifier`
- `POST /admin/api/resources/:resource/items/:identifier/actions/:action`
- `POST /admin/api/resources/:resource/bulk-actions/:action`
- `GET /admin/api/resources/:resource/export/:format`
- `GET /admin/api/resources/:resource/autocomplete/:field`

The built-in `users` resource also keeps compatibility aliases under the same
HTML and JSON prefixes when it is available:

- `GET /admin/users`
- `GET /admin/users/:identifier`
- `POST /admin/users/:identifier`
- `GET /admin/api/users`
- `GET /admin/api/users/:identifier`
- `POST /admin/api/users/:identifier`
- `POST /admin/api/users/bulk-actions/:action`
- `GET /admin/api/users/export/:format`
- `GET /admin/api/users/autocomplete/:field`

Provider-defined resources may also set `legacyPath` in their metadata. When
present, `admin-ui` now keeps full parity between the generic
`/admin/resources/:resource...` routes and the legacy aliases for list, detail,
update, row action, bulk action, export, and autocomplete flows.

Example:

```plist
{
  identifier = "orders";
  legacyPath = "orders-support";
}
```

This resource remains available at both:

- `/admin/resources/orders`
- `/admin/orders-support`

and its JSON aliases remain available at both:

- `/admin/api/resources/orders/items`
- `/admin/api/orders-support`

## Mounted Runtime

`admin-ui` runs as a mounted child application under `/admin`. The mounted app
inherits the parent application's middleware classes so app-owned auth/session
middleware continues to apply consistently on the admin surface.

## Config

Minimal config:

```plist
adminUI = {
  title = "Arlen Admin";
  resourceProviders = {
    classes = ( "MyOrdersAdminProvider" );
  };
  paths = {
    prefix = "/admin";
    apiPrefix = "api";
  };
};
```

Notes:

- `session.secret` is still required because the module depends on the shared
  authenticated-session contract
- `database.connectionString` is optional unless you want the built-in `users`
  resource
- the mounted HTML surface resolves to `/admin/...` and the JSON surface to
  `/admin/api/...`

## Policy Defaults

The module protects both HTML and JSON surfaces with the same defaults:

- authenticated session required
- admin role required
- AAL2 / step-up required

Apps can add per-resource policy checks through the optional
`adminUIResourceAllowsOperation:identifier:context:error:` hook.

## SPA Notes

Use `/admin/api/...` for React or other SPA clients. The module does not ship a
frontend framework bundle; it exposes machine-readable resource metadata so the
app can build its own client against the same admin contract.

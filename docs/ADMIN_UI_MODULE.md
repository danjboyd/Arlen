# Admin UI Module

The first-party `admin-ui` module ships one admin product with two surfaces:

- HTML-first admin pages under `/admin/...`
- headless JSON endpoints under `/admin/api/...`

Both surfaces are driven from the same resource definitions.

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
- optional policy hook

## JSON Surface

Key endpoints:

- `GET /admin/api/session`
- `GET /admin/api/resources`
- `GET /admin/api/resources/:resource`
- `GET /admin/api/resources/:resource/items`
- `GET /admin/api/resources/:resource/items/:identifier`
- `POST /admin/api/resources/:resource/items/:identifier`
- `POST /admin/api/resources/:resource/items/:identifier/actions/:action`

The built-in `users` resource also keeps compatibility aliases under:

- `GET /admin/api/users`
- `GET /admin/api/users/:identifier`
- `POST /admin/api/users/:identifier`

## Policy Defaults

The module protects both HTML and JSON surfaces with the same defaults:

- authenticated session required
- admin role required
- AAL2 / step-up required for JSON admin operations

Apps can add per-resource policy checks through the optional
`adminUIResourceAllowsOperation:identifier:context:error:` hook.

## SPA Notes

Use `/admin/api/...` for React or other SPA clients. The module does not ship a
frontend framework bundle; it exposes machine-readable resource metadata so the
app can build its own client against the same admin contract.

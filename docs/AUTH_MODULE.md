# Auth Module

The first-party `auth` module ships one auth product with two surfaces:

- HTML-first account flows under `/auth/...`
- headless JSON endpoints under `/auth/api/...`

Both surfaces use the same underlying session, provider, MFA, verification, and
password-reset contracts.

## Default Paths

- `GET /auth/login`
- `POST /auth/login`
- `POST /auth/logout`
- `GET /auth/register`
- `POST /auth/register`
- `GET /auth/session`
- `GET /auth/verify`
- `POST /auth/password/forgot`
- `POST /auth/password/reset`
- `POST /auth/password/change`
- `GET /auth/mfa/totp`
- `POST /auth/mfa/totp/verify`
- `GET /auth/provider/stub/login`

Headless aliases:

- `GET /auth/api/session`
- `POST /auth/api/login`
- `POST /auth/api/logout`
- `POST /auth/api/register`
- `GET /auth/api/verify`
- `POST /auth/api/password/forgot`
- `POST /auth/api/password/reset`
- `POST /auth/api/password/change`
- `GET /auth/api/mfa/totp`
- `POST /auth/api/mfa/totp/verify`
- `GET /auth/api/provider/stub/login`

Provider CTAs and provider API routes are driven by the enabled provider set in
`authModule.providers`. If `authModule.providers.stub.enabled = NO`, the
`/auth/login` page no longer renders the stub-provider CTA and the stub routes
are not registered.

## Customization

Use hook classes in `authModule.hooks` for:

- registration policy
- password policy
- user provisioning
- notification delivery
- session policy
- provider mapping

The default-first path keeps schema, routes, templates, and session wiring in
the module while leaving policy and branding with the app.

## SPA Notes

SPA clients should use `/auth/api/...` rather than scraping the HTML routes.
Those endpoints are intended to back React or other frontend clients without
shipping a bundled frontend inside the module. Session payloads also expose
`login_providers` so SPA clients can discover enabled provider-login affordances
without hard-coding them.

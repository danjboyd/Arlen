# Auth Primitives Example

This sample app demonstrates the Phase 12 core auth primitives without turning
Arlen core into a full account-management product.

It intentionally uses:

- a local TOTP step-up flow built directly on `ALNTOTP` and `ALNAuthSession`
- a stub OIDC provider flow built on `ALNOIDCClient` and
  `ALNAuthProviderSessionBridge`
- one AAL2-protected route to show that provider login establishes primary auth
  but still requires local step-up when policy demands it

## Endpoints

- `GET /healthz`
- `GET /auth/session`
- `GET /auth/local/login`
- `GET /auth/local/totp/provisioning`
- `GET /auth/local/totp/verify?code=<totp>`
- `GET /auth/provider/stub/login`
- `GET /auth/provider/secure`

## Demo Notes

- The OIDC flow is intentionally stubbed and self-contained. It is meant to
  show the Phase 12 core contracts, not real provider production setup.
- The TOTP secret is static in this example for determinism. Real apps or
  Phase 13 modules should persist per-user secrets and recovery state through
  app-owned storage.
- The secure route requires AAL2, so a successful provider login alone still
  returns `step_up_required` until the local TOTP route upgrades the session.

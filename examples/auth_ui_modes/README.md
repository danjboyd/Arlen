# Auth UI Modes

This example pack documents the three supported Phase 15 auth presentation
modes for the first-party `auth` module.

Common contract across all three modes:

- the same backend session, provider-login, MFA, verification, and
  password-reset behavior
- the same stable `/auth/api/...` JSON surface
- the same module-owned auth runtime and migrations
- the same Phase 18 MFA fragment contract for server-rendered EOC apps
- the same optional disabled-by-default SMS/Twilio Verify factor surface when
  app policy enables it

What changes by mode is who owns the HTML under `/auth/...`.

Mode guides:

- `headless`: `examples/auth_ui_modes/headless/README.md`
- `module-ui`: `examples/auth_ui_modes/module_ui/README.md`
- `generated-app-ui`: `examples/auth_ui_modes/generated_app_ui/README.md`

Recommended progression:

1. start with `module-ui` if the stock auth flows are close to what you need
2. choose `headless` if your product already owns all auth screens in a SPA or
   native client
3. choose `generated-app-ui` when the app should own the auth presentation
   fully but still keep the module backend contract

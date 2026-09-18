# Auth Module

The first-party `auth` module ships one auth backend contract with three UI
ownership modes:

- `headless`
- `module-ui`
- `generated-app-ui`

All three modes keep the same session, provider-login, MFA, verification, and
password-reset behavior. The UI mode only changes who owns the HTML surface.

The module ships three explicit reuse paths:

- stock full-page auth UI
- reusable server-rendered auth fragments for EOC apps
- strengthened headless `/auth/api/...` contracts for React/native clients

Optional SMS MFA through Twilio Verify is available as a disabled-by-default
secondary factor without changing the core TOTP-first auth/session contract.

## Route Contract

Interactive HTML routes:

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
- `GET /auth/mfa`
- `GET /auth/mfa/totp`
- `POST /auth/mfa/totp/verify`
- `GET /auth/provider/stub/login`
- `GET /auth/provider/:provider/login`
- `GET /auth/provider/:provider/callback`
- when `authModule.mfa.sms.enabled = YES`:
  - `GET /auth/mfa/sms`
  - `POST /auth/mfa/sms/start`
  - `POST /auth/mfa/sms/verify`
  - `POST /auth/mfa/sms/resend`
  - `POST /auth/mfa/sms/remove`

Stable API-first aliases:

- `GET /auth/api/session`
- `POST /auth/api/login`
- `POST /auth/api/logout`
- `POST /auth/api/register`
- `GET /auth/api/verify`
- `POST /auth/api/password/forgot`
- `POST /auth/api/password/reset`
- `POST /auth/api/password/change`
- `GET /auth/api/mfa`
- `GET /auth/api/mfa/totp`
- `POST /auth/api/mfa/totp/verify`
- `GET /auth/api/provider/stub/login`
- `GET /auth/api/provider/:provider/login`
- `GET /auth/api/provider/:provider/callback`
- when `authModule.mfa.sms.enabled = YES`:
  - `GET /auth/api/mfa/sms`
  - `POST /auth/api/mfa/sms/start`
  - `POST /auth/api/mfa/sms/verify`
  - `POST /auth/api/mfa/sms/resend`
  - `POST /auth/api/mfa/sms/remove`

Mode behavior:

- `headless` keeps `/auth/api/...` and provider completion routes active, but
  suppresses module-owned HTML form/result pages.
- `module-ui` serves stock auth page bodies through a module-owned default UI,
  with app-owned layout and partial hooks available.
- `generated-app-ui` keeps the same backend routes but resolves HTML from
  app-owned templates under `templates/auth/...` by default.

Provider CTAs and provider API routes are driven by the enabled provider set in
`authModule.providers`. If `authModule.providers.stub.enabled = NO`, the
provider CTA disappears and the stub provider routes are not registered.

## Generic OIDC Providers

Every `authModule.providers` entry other than `stub` is a real OIDC provider
driven by the module-owned `/auth/provider/:provider/...` routes. `stub` keeps
its own hand-rolled routes because it is a test double with no upstream to talk
to.

```plist
authModule = {
  providers = {
    entra = {
      preset = "microsoft";
      clientID = "00000000-0000-0000-0000-000000000000";
      clientSecret = "...";
      tenantID = "contoso-tenant-id";
      issuer = "https://login.microsoftonline.com/contoso-tenant-id/v2.0";
    };
  };
};
```

An entry names a `preset` (`google` or `microsoft`) and overrides any field on
it; an entry with no preset must supply the endpoints itself. A provider whose
key matches a preset name picks that preset up implicitly. Set `enabled = NO` to
configure a provider without registering it.

The flow the routes drive:

- `GET /auth/provider/:provider/login` builds the authorization request,
  generates PKCE (S256), state and nonce, stashes them in the session, and
  redirects to the provider.
- `GET /auth/provider/:provider/callback` validates state, exchanges the code
  while replaying the stashed verifier, fetches and caches the JWKS, verifies
  the ID token, normalizes the identity, and hands it to the app's
  `ALNAuthProviderSessionResolver`.

PKCE is always on and is not configurable. The stashed material is single-use:
the callback consumes it before doing any work, so a replayed callback cannot
reuse a state, nonce or verifier.

Mapping a normalized identity onto the app's own user table stays the app's job
through the resolver seam — the module does not assume a user model.

### Tenant issuer overrides

**Both shipped presets default to the multi-tenant issuer**
(`login.microsoftonline.com/common/v2.0`). A single-tenant app must override
`issuer` with its real tenant issuer, or issuer validation accepts tokens from
any tenant.

Configuration fails at registration when a provider sets `tenantID` to a real
tenant but leaves a `/common/` issuer in place, since that combination is
almost always the mistake rather than the intent.

### JWKS fetching

Keys are fetched over a bounded transport that rejects redirects, cookies and
non-200 responses, and are cached per provider. `authModule.jwksMaxAgeSeconds`
controls the cache lifetime and must be between 30 and 3600 seconds (default
300). A provider may set `jwksAllowedHosts` to constrain which hosts its keys
may come from; it defaults to the host of its own `jwksURI`, and a JWKS URI
outside the allowlist is refused.

This mirrors the resource-server side described in
[OAuth Resource Server](OAUTH_RESOURCE_SERVER.md), so both JWKS consumers make
the same trust decisions.

TOTP route behavior:

- `GET /auth/mfa` and `GET /auth/api/mfa` expose factor inventory, preferred
  challenge factor, and policy-gated management affordances
- `GET /auth/mfa/totp` renders either enrollment or challenge based on factor
  state
- first successful HTML enrollment verification renders a recovery-code
  completion page before redirecting back to the app
- `GET /auth/api/mfa/totp` and `POST /auth/api/mfa/totp/verify` expose the same
  backend flow through explicit JSON `flow` and `mfa` payloads

Current MFA factor scope:

- authenticator-app TOTP remains the recommended and preferred factor
- optional SMS/Twilio Verify is implemented as a disabled-by-default fallback
  factor
- when SMS is disabled, no SMS routes are registered and the stock HTML factor
  management UI hides SMS affordances entirely

## UI Configuration

```plist
authModule = {
  ui = {
    mode = "module-ui";
    layout = "layouts/guest";
    generatedPagePrefix = "auth";
    partials = {
      providerRow = "auth/partials/provider_row";
      errorBlock = "auth/partials/error_block";
    };
    contextClass = "APPAuthUIContextHook";
  };
};
```

Config semantics:

- `ui.mode`
  - `module-ui` is the default
  - `headless` disables module-owned HTML routes
  - `generated-app-ui` resolves page and partial templates from the app prefix
- `ui.layout`
  - default `modules/auth/layouts/main`
  - used by `module-ui`
  - can be overridden per page through `ALNAuthModuleUIContextHook`
- `ui.generatedPagePrefix`
  - default `auth`
  - used by `generated-app-ui`
- `ui.partials`
  - optional fine-grained partial override map such as `providerRow`,
    `errorBlock`, or `pageWrapper`
- `ui.contextClass`
  - optional Objective-C hook class for page-level layout and context injection

Session payloads expose both `ui_mode` and `login_providers`, so app-owned or
SPA clients can discover the active presentation mode and provider affordances
without hard-coding them.

## Server-Rendered Fragment Contract

The module promotes a small coarse fragment contract for server-rendered EOC
apps. These are the supported fragment identifiers:

- `provider_login_buttons`
- `mfa_factor_inventory_panel`
- `mfa_enrollment_panel`
- `mfa_challenge_form`
- `mfa_sms_enrollment_panel`
- `mfa_sms_challenge_form`
- `mfa_recovery_codes_panel`

The stock full-page auth UI uses these same fragments internally, so the
default pages and embeddable surfaces stay aligned.

Fragment consumers should treat lower-level form/layout helpers such as
`page_wrapper`, `form_shell`, `field_row`, and `provider_row` as internal. They
may still be overridden in `module-ui` or copied by `generated-app-ui`, but
they are not the stable embeddable contract.

Useful runtime helpers for app-owned server-rendered pages:

```objc
NSDictionary *fragmentContext = [[ALNAuthModuleRuntime sharedRuntime]
    mfaManagementFragmentContextForCurrentUserInContext:ctx
                                      returnTo:@"/account/security"
                                         error:&error];
```

That helper returns the context expected by the factor-management fragments,
including:

- `authMFAFactors`
- `authMFAPolicy`
- `authTOTPProvisioning`
- `authSMSState`
- `authSMSStartFormDescriptor`
- `authSMSVerifyFormDescriptor`

For a dedicated SMS challenge surface, use:

```objc
NSDictionary *smsContext = [[ALNAuthModuleRuntime sharedRuntime]
    smsChallengeFragmentContextForCurrentUserInContext:ctx
                                              returnTo:@"/account/security"
                                                 error:&error];
```

The intended reuse target is app-owned account/security pages and other
server-rendered auth surfaces that want to embed framework-provided MFA/auth UI
without forking the full-page templates.

## Customization Hooks

Use `authModule.hooks` for auth behavior and policy seams:

- registration policy
- password policy
- user provisioning
- notification delivery
- session policy
- provider mapping

Use `ALNAuthModuleUIContextHook` for page-level UI ownership in `module-ui`:

```objc
@protocol ALNAuthModuleUIContextHook <NSObject>
@optional
- (nullable NSString *)authModuleUILayoutForPage:(NSString *)pageIdentifier
                                   defaultLayout:(NSString *)defaultLayout
                                         context:(ALNContext *)context;
- (nullable NSDictionary *)authModuleUIContextForPage:(NSString *)pageIdentifier
                                       defaultContext:(NSDictionary *)defaultContext
                                              context:(ALNContext *)context;
@end
```

## Headless MFA Contract

SPA or native clients should target `/auth/api/...` directly rather than
scraping HTML routes. That API surface is the stable headless contract across
all UI modes.

The module makes the MFA JSON surface explicit:

- `GET /auth/api/mfa`
  - returns `status`, `preferred_factor`, `available_challenge_factors`,
    `factors`, `policy`, `mfa`, `paths`, and `session`
  - `mfa.sms.enabled` plus `paths.sms*` let React/native clients detect whether
    SMS is enabled without probing route existence
- `GET /auth/api/mfa/totp`
  - returns `status`, `flow`, `mfa`, and `session`
  - `flow.state` is `enrollment` or `challenge`
  - `mfa.provisioning` is populated during enrollment and empty during the
    steady-state challenge path
- when SMS is enabled:
  - `GET /auth/api/mfa/sms` returns challenge state for the enrolled SMS factor
  - `POST /auth/api/mfa/sms/start` starts phone verification or replacement
  - `POST /auth/api/mfa/sms/verify` completes enrollment or step-up challenge
  - `POST /auth/api/mfa/sms/resend` issues another Verify challenge
  - `POST /auth/api/mfa/sms/remove` removes the SMS factor after recent MFA
- `POST /auth/api/mfa/totp/verify`
  - returns top-level session fields for compatibility plus structured `flow`
    and `mfa`
  - `flow.state` is `recovery_codes` on first successful enrollment verify and
    `complete` on later step-up verifies
  - `mfa.recovery_codes` is populated only on that first successful enrollment
    verify

React/native apps should build their MFA UI from those JSON fields rather than
inferring flow state from the stock HTML behavior. When both factors are
enrolled, the stock and headless contracts keep TOTP preferred and expose SMS
only as an explicit fallback path.

## Trusted Email Claim Flow

Apps that already proved email ownership outside the stock auth UI can now use
`ALNAuthModuleRuntime` to claim a session directly:

```objc
NSDictionary *result = [[ALNAuthModuleRuntime sharedRuntime]
    claimTrustedEmail:@"invitee@example.com"
          displayName:@"Invitee"
               source:@"invite_claim"
sendPasswordSetupEmail:YES
              baseURL:@"https://example.com"
              context:ctx
                error:&error];
```

This flow is intended for app-owned invite-claim or verified email-link pages.
It will:

- find or create the local user for the claimed email
- mark the email as verified
- start an authenticated session using the `email_link` method
- optionally issue the stock password-setup email so the claimed user can set a
  reusable local password

The result payload includes `user`, `session`, `created_user`,
`email_verified`, `password_setup_issued`, and `source`.

## Example References

- `headless`: `examples/auth_ui_modes/headless/README.md`
- `module-ui`: `examples/auth_ui_modes/module_ui/README.md`
- `generated-app-ui`: `examples/auth_ui_modes/generated_app_ui/README.md`

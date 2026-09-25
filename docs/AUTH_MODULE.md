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

## Configurable OIDC Login (including Microsoft Entra)

Enable real providers under `authModule.providers`. The module owns discovery,
authorization-code login with PKCE S256, the session-bound state and nonce,
token exchange, RS256 ID-token verification against JWKS, and session completion.
This is browser sign-in; `ALNOAuthResourceServer` separately handles bearer-token
access to APIs and MCP.

```plist
authModule = {
  paths = { prefix = "/context/auth"; };
  localPassword = { enabled = NO; };
  providers = {
    stub = { enabled = NO; };
    entra = {
      enabled = YES;
      type = "oidc";
      ctaLabel = "Sign in with Microsoft";
      issuer = "https://login.microsoftonline.com/<TENANT_GUID>/v2.0";
      discoveryURL = "https://login.microsoftonline.com/<TENANT_GUID>/v2.0/.well-known/openid-configuration";
      clientID = "<WEB_CLIENT_GUID>";
      clientSecretEnvironmentKey = "ARLEN_AUTH_ENTRA_CLIENT_SECRET";
      redirectURI = "https://example.com/context/auth/provider/entra/callback";
      scopes = ("openid", "profile", "email");
      subjectClaim = "oid";
      tenantClaim = "tid";
      allowedTenants = ("<TENANT_GUID>");
      jwksAllowedHosts = ("login.microsoftonline.com");
    };
  };
  hooks = { providerSessionResolverClass = "CompanyIdentityResolver"; };
};
```

For local development against `boomhauer`, `redirectURI` may be a loopback
`http` URL (`http://localhost:3000/...`, `http://127.0.0.1:3000/...` or
`http://[::1]:3000/...`) when the app environment is `development` or `test`.
Google and Entra both accept loopback http redirect URIs for development
clients. Any other environment, including `production` and `staging`, refuses
them at startup. Issuer, discovery, token and JWKS URLs are always HTTPS-only.

Register the exact HTTPS redirect URI as a web redirect in the identity provider,
and supply the client secret through the named environment variable in every
worker. Do not put the secret into the plist. The auth module's existing
`session.secret` and `database.connectionString` requirements still apply.
The resolver may use a separate application-owned person store; OIDC does not
create or link an `auth_users` row automatically.

### Google preset

`preset = "google"` fills in Google's issuer, discovery URL, scopes, client
authentication method and button label. It also derives the allowed hosts from
Google's endpoints: `accounts.google.com` and `oauth2.googleapis.com` for
endpoints, and `www.googleapis.com` for JWKS. A hand-written Google config needs
those hosts listed explicitly; the preset makes that unnecessary.

```plist
authModule = {
  providers = {
    google = {
      enabled = YES;
      preset = "google";
      clientID = "<CLIENT_ID>.apps.googleusercontent.com";
      clientSecretEnvironmentKey = "ARLEN_AUTH_GOOGLE_CLIENT_SECRET";
      redirectURI = "https://app.example.com/auth/provider/google/callback";
    };
  };
  hooks = { providerSessionResolverClass = "AppIdentityResolver"; };
};
```

`enabled = YES` is still required. Any key set explicitly overrides the preset.
The auth module currently supports only the `google` preset. The other
`ALNAuthProviderPresets` entries need a tenant-specific issuer (Microsoft,
Okta, Auth0), are not OIDC (GitHub), or need a client authentication method
the module does not implement (Apple), so the module rejects them at startup.
For Entra, use the explicit configuration above.

### Admission policy

Small private apps often only need "these people may sign in". An optional
per-provider `admission` dictionary provides that without a custom resolver.
It is checked after ID-token verification and before the resolver runs:

```plist
google = {
  enabled = YES;
  preset = "google";
  /* ... */
  admission = {
    allowedEmails = ("parent@example.com", "kid@example.com");
    allowedEmailsEnvironmentKey = "APP_ALLOWED_EMAILS";  // optional comma-separated list
    allowedDomains = ("example.com");
    requireHostedDomain = NO;
    rejectionMessage = "This site is for family members only.";
  };
};
```

- `allowedEmails`, and addresses from `allowedEmailsEnvironmentKey`, are matched
  case-insensitively against the verified `email` claim.
- `allowedDomains` matches the email's domain exactly; subdomains do not match.
  When the ID token carries Google's `hd` (hosted domain) claim, `hd` must also
  be listed. `requireHostedDomain = YES` additionally requires `hd` to be
  present, which excludes consumer Google accounts created with a work address.
- If any list is configured, the address must be provider-verified
  (`email_verified` true). `requireVerifiedEmail = YES` imposes that requirement
  on its own, without lists.
- Unknown keys and malformed values fail at startup. Entries must be plain
  `name@domain.tld` addresses and dotted domain names, not patterns. A missing
  or empty `allowedEmailsEnvironmentKey` variable also fails startup.

Rejected logins never reach the resolver or create a session. JSON callbacks
return `403` with `{"status":"error","code":"admission_denied","message":...}`.
Browser callbacks redirect to the module's login page, which shows
`rejectionMessage` (default "This account is not permitted to sign in."). If a
[failure redirect](#failure-redirect) is configured, they go there with
`error=admission_denied` instead.

Admission only decides who may sign in. It does not link identities: accounts
are still keyed on the verified provider subject, the resolver still decides
membership and roles, and email is never a fallback match.

For the example above, the module registers:

- `GET /context/auth/provider/entra/login`
- `GET /context/auth/provider/entra/callback`
- `GET /context/auth/api/provider/entra/login`
- `GET /context/auth/api/provider/entra/callback`

Use the configured redirect URI consistently even when starting from the API
login route. API login returns `authorize_url`; browser login redirects there.
A successful browser callback redirects to a local `return_to` path or the
module's `defaultRedirect`. External `return_to` URLs are ignored. JSON callbacks
return session metadata and `redirect_to`, without provider tokens. Failed
callbacks return 401 with a generic message (403 `admission_denied` for an
admission-policy rejection); provider setup/network failures
at login return 502. Disabled providers have no routes or login buttons.

### Failure redirect

By default a rejected browser callback answers `401` with a small JSON body.
SPA and headless apps can instead send people to their own page. Set
`authModule.failureRedirect`, or `failureRedirect` on a provider (which wins),
to a local absolute path:

```plist
authModule = {
  failureRedirect = "/sign-in";
  providers = { google = { /* ... */ failureRedirect = "/family/sign-in"; }; };
};
```

A failed browser callback then redirects with `302` to
`<failureRedirect>?error=<code>&provider=<identifier>`, or with `&` if the path
already has a query string. The JSON API callback (`<apiPrefix>/provider/...`)
never redirects. It keeps its `401` and adds the same `code` field. The value
must be a local path: a scheme, a leading `//`, a backslash, a fragment or
whitespace fails configuration at startup.

| `error` code | Meaning |
| --- | --- |
| `rejected` | The resolver returned nil, or the verified subject/tenant was not accepted. |
| `admission_denied` | The provider's `admission` policy refused the identity. |
| `expired_state` | The login state was missing, expired, or did not match. |
| `provider_error` | The provider returned an error, such as `access_denied`. |
| `verification_failed` | Token or ID-token checks failed (signature, issuer, audience, nonce). |
| `provider_unavailable` | Discovery, token or JWKS requests failed, or the client secret is missing. |

A resolver can supply a more specific code by setting
`ALNAuthModuleOIDCFailureCodeKey` in the `userInfo` of the NSError it returns.
The code must be lowercase letters, digits or underscores, at most 64
characters; otherwise `rejected` is used.

```objc
if (invite == nil) {
  if (error) *error = [NSError errorWithDomain:@"App" code:1
                                      userInfo:@{ ALNAuthModuleOIDCFailureCodeKey : @"not_invited" }];
  return nil;
}
```

Codes never include provider messages or claim values.

### Application Identity Resolver

Implement `ALNAuthProviderSessionResolver` and configure its class under
`hooks.providerSessionResolverClass`. The class is instantiated without arguments
and must support concurrent calls. It receives only an identity whose ID token
has passed signature, issuer, audience, expiry, nonce, and tenant checks.

```objc
@interface CompanyIdentityResolver : NSObject <ALNAuthProviderSessionResolver>
@end

@implementation CompanyIdentityResolver
- (NSDictionary *)resolveSessionDescriptorForNormalizedIdentity:(NSDictionary *)identity
                                         providerConfiguration:(NSDictionary *)provider
                                                         error:(NSError **)error {
  NSString *principal = identity[@"provider_subject"]; // verified "tid:oid"
  // Implement this lookup against the application's durable person directory.
  NSDictionary *person = [CompanyPeople activePersonForPrincipal:principal error:error];
  if (person == nil) return nil; // deny unknown or suspended principals
  return @{
    @"subject": person[@"identifier"],
    @"roles": person[@"roles"] ?: @[],
    @"assuranceLevel": @1,
  };
}
@end
```

`CompanyPeople` above represents application code, not a framework class. Use
immutable principal identifiers for the lookup; email is display data and is
never a fallback match on this path. With `tenantClaim` configured,
`provider_subject` is `<tenant>:<subject>`; both claims must be nonempty, contain
no colon, and the tenant must be allowed. Without `tenantClaim`, it is the
verified `subjectClaim` (default `sub`). The raw verified claims remain available
under `identity["claims"]`. Normal OIDC `sub` validation still applies when using
`oid` as the application principal. The resolver owns membership, roles, and any
explicit account-linking decision; nil rejects login. Arlen does not infer MFA
assurance from the fact that a provider was used.

OIDC sessions expose the application's subject and roles. The auth session API
does not try to look up an external subject in its own user table. Stock local
account/MFA management remains backed by the auth module's own user records;
applications with external person stores own those account-management surfaces.

### Defaults and Upgrade Behavior

When any real OIDC provider is enabled, local password login and the stub
provider default off. Explicit `localPassword.enabled` or
`providers.stub.enabled` overrides are honored. Without real OIDC providers,
the existing local-password and stub defaults remain enabled for compatibility.
Disabling local passwords removes registration, verification, password-login,
forgot/reset/change-password routes in both HTML and API surfaces. The login
page remains available and shows provider buttons without a password form.
Session payloads include `local_password_enabled` and `login_providers`.

Existing applications may have copied an older auth manifest containing
`stub.enabled = YES`. Set `authModule.providers.stub.enabled = NO` explicitly
when upgrading to enterprise login; update the copied module sources and login
body template together. The example above makes both opt-outs explicit.

### Transport and Callback Contract

- Provider/discovery/redirect URLs require HTTPS. The only exception is a
  loopback http `redirectURI` in `development`/`test`. Endpoint hosts default to the
  issuer host; `endpointAllowedHosts` can explicitly allow other discovery,
  authorization, and token hosts. `jwksAllowedHosts` separately restricts key
  retrieval and defaults to the endpoint hosts. Redirects are rejected.
- Each discovery, token, or JWKS request has a five-second total deadline and a
  256 KiB response limit. TLS verification is required and shared cookies are
  disabled. A callback fetches fresh discovery and keys, so a key rotation does
  not depend on worker-local caches. Calls are synchronous; account for provider
  latency in request capacity planning.
- Confidential web clients use `client_secret_post` by default. Public clients
  must explicitly set `tokenEndpointAuthMethod = "none"`; PKCE remains required.
  Other token authentication methods and ID-token algorithms are not supported
  by this module path.
- One pending provider login is stored per browser session. Starting another
  replaces it. The five-minute callback is bound to the provider, configured
  redirect URI, state, nonce, and PKCE verifier. Callback attempts clear pending
  state. Signed cookie sessions cannot revoke an older copied cookie; the
  provider must enforce one-time authorization-code redemption, including PKCE.
- `hooks.oidcTransportClass` optionally names an application implementation of
  `ALNAuthModuleOIDCTransport` for controlled tests or custom networking. This is
  trusted application code, responsible for the same TLS, redirect, deadline,
  and response-limit contract. Normal deployments should use the default.

Run `make test-unit-filter TEST=AuthModuleOIDCTests` and
`make test-unit-filter TEST=MetadataTransportTests` after sourcing
`tools/source_gnustep_env.sh`. These tests use synthetic signed tokens and local
transport fixtures; no tenant credentials are required. Validate the registered
web client, real tenant policy, reverse-proxy callback URL, and downstream person
mapping separately before enabling an application deployment.

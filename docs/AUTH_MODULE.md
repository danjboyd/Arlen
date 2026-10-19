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
- `POST /auth/logout/all`
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
- `POST /auth/api/logout/all`
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

Login (password, provider, or trusted email claim) and MFA step-up start a
fresh session: other keys stored before, including the CSRF token, are dropped,
and only `return_to` is kept. The JSON login, registration and verify responses
return the new `csrf_token` (also at `GET /auth/api/session`); use it for the
next unsafe request. See [Session and CSRF](CONFIGURATION_REFERENCE.md#5-session-and-csrf).

Local-password login answers `Invalid email or password` for both an unknown
email and a wrong password. For an unknown email it still runs one Argon2id
verification against a throwaway hash, so response time does not reveal whether
the account exists. (Registration still reports an already-registered email.)

Password-reset and email-verification emails link to
`authModule.publicBaseURL` (for example `publicBaseURL =
"https://app.example.com";`). Set it in production: there, without it, the module
sends no link rather than trusting the request's `Host` header, and logs an
error. In `development` and `test` an unset value falls back to the request's
scheme and `Host`. See
[Configuration Reference](CONFIGURATION_REFERENCE.md#auth-module-email-links).

Password-reset links expire after 30 minutes and email-verification links after
one day. Each link works once, even when several requests present it at the same
time. Any successful password change, through a reset link or the authenticated
change-password route, retires all of that user's other outstanding reset links.

Provider CTAs and provider API routes are driven by the enabled provider set in
`authModule.providers`. If `authModule.providers.stub.enabled = NO`, the
provider CTA disappears and the stub provider routes are not registered. The
stub provider is only available in the `development` and `test` environments;
see [Defaults and Upgrade Behavior](#defaults-and-upgrade-behavior).

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

### Database pool and unavailability

The auth module keeps its own PostgreSQL connection pool:

```plist
authModule = {
  database = {
    maxConnections = 8;          /* default */
    acquireTimeoutSeconds = 2;   /* default; how long a request waits for a free connection */
  };
};
```

When no connection becomes free within `acquireTimeoutSeconds`, or the
database cannot be reached, auth routes answer `503` with `Retry-After: 2` and
the message `The sign-in service is temporarily unavailable. Try again
shortly.` They never answer `401` for that reason and never clear the session,
so clients should keep the session and retry. A password sign-in that cannot
reach the database also answers `503`, not `Invalid email or password`.
Connections the server closed while idle (restart, failover, idle timeout) are
replaced and the statement retried once (see
[Arlen Data](ARLEN_DATA.md#connection-pool-liveness-checks)); only if that
fails too does the route answer `503`. Database driver messages never reach
the client: responses carry a generic message and the detail is logged.
Size `maxConnections` for the number of auth requests you expect at once,
within the database's own connection limit.

### TOTP replay protection and attempt limits

These need auth module migration `004_auth_totp_limits` (run
`./bin/arlen module migrate --env <env>` after upgrading to auth 1.6.0):

- each TOTP enrollment remembers the last time step it accepted
  (`auth_mfa_enrollments.last_used_step`). A code for that step or an earlier
  one is refused with `That authenticator code was already used`, even from a
  different session, so one code cannot complete step-up twice.
- a verified enrollment also accepts one of its recovery codes in the `code`
  field of `POST /auth/mfa/totp/verify` and `POST /auth/api/mfa/totp/verify`.
  Each recovery code works once, and two different codes used at the same
  time both succeed. The session records the method as `recovery_code`
  instead of `totp`.
- TOTP and recovery-code checks share one failure counter per account
  (`auth_attempt_limits`, scope `mfa`). When an account reaches
  `mfa.maxFailures` consecutive failures it is locked for `lockoutSeconds`.
  Each further failure after a lock ends doubles the lock, up to
  `maxLockoutSeconds`. A successful check resets the counter, and failures
  older than 24 hours start over.
- local password sign-in (and the current-password check when a signed-in user
  changes their password) is slowed down rather than locked:
  - failures are counted per pair of submitted email and client address. After
    `password.maxFailures` failures from one address, that pair waits
    `delaySeconds` before its next attempt, and each further failure doubles
    the wait, up to `maxDelaySeconds`. Other addresses are not affected, and a
    successful sign-in clears only its own pair.
  - an account-wide ceiling against distributed guessing counts failures for
    the email across all addresses. Beyond `accountMaxFailures` failures within
    `accountWindowSeconds`, every further failure adds a wait for that email
    (`accountDelaySeconds`, doubling, up to `maxDelaySeconds`). The wait ends
    on its own; nothing needs to be unlocked. Only failures arm it: a
    successful sign-in never adds to, extends or re-arms the account-wide
    wait, so after it expires the owner's correct passwords keep working.
  - known devices: an (email, address) pair that signed in successfully within
    the last `trustedPairDays` days (default 30; `0` turns this off) is not
    subject to the account-wide ceiling, and its failures do not count toward
    it. Its own pair delay still applies. The time of the last successful
    sign-in is stored on the pair row only. An email with no account never
    has a successful sign-in, so it never gets the exemption.
  - the client address is the server's proxy-aware address
    (`ALNRequest.effectiveRemoteAddress`), never a raw `X-Forwarded-For` or
    `Forwarded` header.
  - counters are keyed by a SHA-256 of the normalized submitted email
    (`auth_password_attempts`), not by the account, and are checked before the
    account is looked up. Known and unknown emails get the same counters,
    delays, response bodies and one Argon2 verification each, so the limiter
    does not reveal whether an account exists.
  - the tables stay bounded: at most once a minute a sign-in starts a prune
    on a background queue, so the request does not wait for it. Each prune
    deletes at most `pruneBatchSize` rows (default 1000). First it removes
    expired rows with no active wait: account-wide rows untouched for a whole
    `accountWindowSeconds` (their count would restart anyway), pair rows
    untouched for 24 hours unless they signed in within `trustedPairDays`, and
    mail rows past their window. Then, above `maxTrackedEntries` rows, it
    removes pair rows still under `maxFailures` failures with no active wait,
    oldest first, known devices last. Account-wide rows and rows with an
    active wait are never removed to meet the cap: if only those are left,
    the table stays over the cap until they expire and a warning is logged.
    Every statement is limited and walks the `updated_at` index; the only
    count reads at most `maxTrackedEntries + pruneBatchSize` rows.
- forgot-password is not subject to the password delays or the account-wide
  ceiling, so the owner can always ask for a reset. It has its own limit
  against sending lots of mail (`auth_mail_sends`): per hashed submitted email
  (`mail.maxPerEmail`, default 5) and per hashed client address
  (`mail.maxPerAddress`, default 20) within `mail.windowSeconds` (3600).
  Requests are counted alike for known and unknown emails. Beyond a limit the
  route still answers exactly as usual (the same `200` and generic reply), but
  sends nothing and logs a warning. The module has no separate route for
  resending the verification email; registration sends it once.
- while a lock or wait is active, the route answers `429` with a `Retry-After`
  header (seconds) and the error `Too many failed attempts. Try again in N
  seconds.`, without checking the submitted code or password. HTML routes
  render the same error on the form.
- an attempt is counted before the code or password is checked, so parallel
  requests cannot run more checks than the limit allows.

Defaults (`maxFailures = 0` turns a counter off; for `password` it turns off
both the per-address delay and the account-wide ceiling, and
`accountMaxFailures = 0` turns off only the ceiling):

```plist
authModule = {
  attemptLimits = {
    mfa = { maxFailures = 5; lockoutSeconds = 30; maxLockoutSeconds = 900; };
    password = {
      maxFailures = 5;
      delaySeconds = 30;
      maxDelaySeconds = 900;
      accountMaxFailures = 50;
      accountWindowSeconds = 3600;
      accountDelaySeconds = 30;
      maxTrackedEntries = 100000;
      pruneBatchSize = 1000;
      trustedPairDays = 30;
    };
    mail = {
      maxPerEmail = 5;
      maxPerAddress = 20;
      windowSeconds = 3600;
    };
  };
};
```

While the account-wide ceiling is in effect, sign-in for that email waits from
every address that has not signed in successfully within `trustedPairDays`. Provider (OIDC) sign-in is not counted.

If migration 004 has not been applied, TOTP and password verification keep
working without replay protection, counters or delays. The module logs one warning
naming `arlen module migrate` and never fails the request because of the
missing schema.

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

In `module-ui`, the stock stylesheet and TOTP QR script are served under the
module's own prefix at `<paths.prefix>/assets/` (default `/auth/assets/`), and
pages link them there. An app mounted behind a path-scoped reverse proxy that
only forwards `paths.prefix` therefore gets styled pages without extra config.
The files are also still served at `/modules/auth/`.

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

## Sessions and Roles

Sessions are signed cookies. The roles written into the session at sign-in are
not what authorization uses on later requests. On every request that carries a
session identity, the module's middleware resolves that identity again and
replaces the session's roles for the request with the current ones, so
`[ctx authRoles]`, route contracts (`requiredRoles`, minimum assurance level),
and the admin-ui, jobs, ops and other module API guards all see the user's
current roles:

- Module sign-ins (local password, email link, the stub provider) are looked up
  in `auth_users` by subject: one indexed query per request, with no cache
  between requests. Roles come from `roles_json`, passed through the session
  policy hook's `authModuleSessionDescriptorForUser:defaultDescriptor:` when one
  is configured, exactly as at sign-in. A role granted or revoked in the
  database takes effect on the user's next request, with no new sign-in.
- If the user row no longer exists, the session is signed out.
- Each user has a session stamp (`auth_users.session_stamp`, added by migration
  `002_auth_session_stamp.sql`). Sign-in records the current stamp in the
  session; a session whose stamp no longer matches is signed out.
  `-[ALNAuthModuleRuntime bumpSessionStampForSubject:error:]` increments the
  stamp, which ends every existing session for that user. Revoking the admin
  role through the admin-ui users resource does this. Sessions issued before
  the stamp existed count as stamp `0`.
- Sessions from a configured OIDC provider belong to the application resolver.
  When the resolver implements `refreshSessionDescriptorForSubject:provider:error:`
  (see [Application Identity Resolver](#application-identity-resolver)), its
  `roles` apply on every request and a nil result signs the session out.
  Without it, the roles the resolver returned at sign-in stay in force until the
  session ends.
- Sessions that application code establishes itself, for providers the module
  does not own, are left as they are. To have the module manage one for an
  `auth_users` subject, call `recordSessionStampForContext:error:` after
  establishing it.

Ending sessions:

- Signing out (`POST /auth/logout`, `POST /auth/api/logout`) clears the session
  and records it in `auth_revoked_sessions` (migration
  `003_auth_revoked_sessions.sql`). Any other copy of that session cookie is
  then signed out on its next request, including copies taken before an MFA
  step-up. The user's sessions on other devices stay signed in. The check is
  part of the same per-request `auth_users` query. A record is kept only until
  the cookie would have expired anyway (`session.maxAgeSeconds`, or the
  absolute lifetime below if that ends sooner); expired records are deleted
  when someone signs out.
  `-[ALNAuthModuleRuntime revokeCurrentSessionForContext:error:]` does the same
  from application code.
- Sign out everywhere (`POST /auth/logout/all`, `POST /auth/api/logout/all`, or
  `signOutAllSessionsForContext:error:`) bumps the user's session stamp and
  signs out the current session, ending every session the user has. The JSON
  reply is `{"status":"ok","scope":"all_sessions"}`. Until migration
  `002_auth_session_stamp.sql` is applied it can end only the current session
  and replies `{"status":"partial","scope":"current_session",...}`;
  `-[ALNAuthModuleRuntime canEndOtherSessions]` reports which applies.
- Changing the password (`/auth/password/change`) bumps the stamp in the same
  transaction as the new password, so every other session ends; the session
  that made the change records the new stamp and stays signed in. A reset by
  emailed link ends every existing session too, and the resetting browser is
  signed in with a new session as before. Removing the SMS factor ends the
  user's other sessions and keeps the current one.
  `signOutOtherSessionsForContext:error:` does this from application code.
- Deleting the `auth_users` row signs out every session of that user (see
  above).
- `authModule.session.absoluteLifetimeSeconds` (default `1209600`, 14 days,
  the same as the default `session.maxAgeSeconds`) limits how long a module or
  OIDC sign-in lasts. The session cookie renews on use, but once this much time
  has passed since sign-in (`auth_time`, which step-up does not change) the
  session is signed out and the user signs in again. A session with no
  recorded sign-in time is treated as expired.

These apply to module sign-ins (local password, email link, stub). Sessions
from a configured OIDC provider are subject to the absolute lifetime; whether
they stay valid otherwise is decided by the application resolver (see above),
so signing out clears them without a server-side record. Sessions application
code establishes for identities the module does not own are not affected.

Whether `auth_users.session_stamp` and `auth_revoked_sessions` exist is checked
once per process (per database adapter) and cached, so a database without
those migrations does not see a failing query on every request. Restart the
application after running `arlen module migrate` for newly added objects to be
used.

Running `arlen module migrate` after upgrading is recommended: it applies
`002_auth_session_stamp.sql`, which enables ending sessions by stamp, and
`003_auth_revoked_sessions.sql`, which lets a sign-out refuse other copies of
the session cookie. Until 002 runs, roles are still read live and deleted users
are still signed out; only the stamp is skipped. The stamp comparison is not
made, sign-ins do not record a stamp, `bumpSessionStampForSubject:error:` (and
so password changes, sign out everywhere and admin-ui revocation) succeeds
without changing it, and the revoked role is still denied. Until 003 runs,
signing out still clears the session cookie and succeeds, but other copies of
that cookie are not refused. For each missing migration the module logs one
warning per process naming it.

Any other lookup failure (for example the database is unreachable, or the
`auth_users` table is missing) fails the request instead of continuing with the
stored roles.

The auth module always requires `database.connectionString`. Applications that
do not install it and establish sessions with `ALNAuthSession` directly keep the
roles they store in the session.

## Customization Hooks

Use `authModule.hooks` for auth behavior and policy seams:

- registration policy
- password policy
- user provisioning
- notification delivery
- session policy
- provider mapping

Post-login redirects stay on the app's origin. Every route that accepts
`return_to` (login, registration, MFA, recovery codes, SMS, and provider login)
keeps it only when it is a single-slash absolute path such as `/dashboard?tab=2`.
Absolute URLs, protocol-relative `//host` values, backslashes, and control
characters are dropped, and the redirect falls back to `defaultRedirect`. An app
that really needs a cross-origin return implements
`authModulePostLoginRedirectForContext:user:defaultRedirect:` on its session
policy hook, whose result is used as-is.

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

`baseURL` is used for the password setup link only when
`authModule.publicBaseURL` is unset; a configured `publicBaseURL` always wins.
Pass a fixed, configured value here, never one built from the request's `Host`
or forwarding headers, because the link carries a password setup token.

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
  or empty `allowedEmailsEnvironmentKey` variable also fails startup. An
  explicitly empty `allowedEmails` or `allowedDomains` list fails startup;
  omit the key when that list is not used.

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
    // No assuranceLevel: the provider's `assurance` mapping (or 1) applies.
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

To keep roles current for the life of a session, also implement the optional
`refreshSessionDescriptorForSubject:provider:error:`. The module calls it on
every request for a session from that provider, with the local subject the
resolver returned at sign-in. Return a descriptor whose `roles` apply to the
request, nil to sign the session out (for example a suspended person), or nil
with an error to fail the request. Keep it to one indexed lookup; results are
not cached. See [Sessions and Roles](#sessions-and-roles).

```objc
- (NSDictionary *)refreshSessionDescriptorForSubject:(NSString *)subject
                                            provider:(NSString *)provider
                                               error:(NSError **)error {
  NSDictionary *person = [CompanyPeople activePersonForIdentifier:subject error:error];
  return person ? @{ @"subject": subject, @"roles": person[@"roles"] ?: @[] } : nil;
}
```

### Provider assurance from amr and acr

Module surfaces such as the admin UI need assurance level 2. A provider sign-in
gets level 1 unless something says it was multi-factor. Rather than reading
`amr` in every resolver, map the verified ID-token claims on the provider:

```plist
providers = {
  entra = {
    /* ... */
    assurance = {
      amr = { mfa = 2; otp = 2; hwk = 2; };
      acr = { "urn:example:loa:mfa" = 2; };
    };
  };
};
```

- The session gets the highest level any `amr` value or the `acr` value maps
  to, and 1 when none matches or the claims are absent. Matching is exact and
  case-sensitive, and only the signature-checked ID token is read (never
  userinfo).
- Levels are 1 to 3. Unknown keys, empty maps and other level values are a
  startup error.
- The resolver sees the mapped level as `identity[@"assurance_level"]`. If it
  returns its own `assuranceLevel`, that wins, so a resolver that hard-codes
  `assuranceLevel` turns the mapping off. Leave it out to use the mapping.
- Which claims a provider sends, and their values, is provider-specific; some
  send neither by default. Check a real ID token before relying on a mapping.

Without `assurance`, nothing changes: the resolver's level applies, or 1.

OIDC sessions expose the application's subject and roles. The auth session API
does not try to look up an external subject in its own user table. Stock local
account/MFA management remains backed by the auth module's own user records;
applications with external person stores own those account-management surfaces.

### Step-up for provider sign-in

Module surfaces (admin UI, jobs, notifications, ops, search, storage) send a
user who needs assurance level 2 to `authModule.paths.stepUp`, adding
`return_to` (and, from route-level checks, `reason`). It defaults to the TOTP
page (`paths.totp`), which is right for local accounts. A user who signs in only
through a provider has no TOTP factor there, so point step-up at the provider
login and ask it to re-authenticate:

```plist
authModule = {
  paths = { stepUp = "/auth/provider/entra/login?prompt=login"; };
};
```

The value is a local path; a relative value is joined to `paths.prefix`, and a
query is kept (the redirect then appends with `&`). Absolute URLs are a
configuration error. Provider login routes accept `prompt=login` and pass it to
the identity provider; other `prompt` values are ignored.

A fresh provider sign-in satisfies step-up only if it reaches assurance level 2,
through the provider's [`assurance` mapping](#provider-assurance-from-amr-and-acr)
or the level your resolver returns. `prompt=login` asks the provider to
re-authenticate; Arlen does not verify that it did.

### Defaults and Upgrade Behavior

When any real OIDC provider is enabled, local password login and the stub
provider default off. Explicit `localPassword.enabled` overrides are honored.
Without real OIDC providers, local-password login stays enabled for
compatibility.

The stub provider signs a visitor in without any credentials, so it is a
development and test convenience only:

- In the `development` and `test` environments it defaults on when no real
  OIDC provider is enabled, and `providers.stub.enabled` is honored either way.
- In every other environment (`production`, `staging`, or any custom name) it
  defaults off. Setting `providers.stub.enabled = YES` there is refused: the
  auth module's configuration is rejected. There is no override.
- Even if a stub route is reached outside `development`/`test`, it answers 404
  and the stub identity never creates or signs in a user.

Production apps that use local passwords must set `authModule.publicBaseURL`
when upgrading to auth 1.6.0; without it, password-reset and verification
emails are not sent outside `development` and `test`.

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

# Headless Auth UI Mode

Use `headless` when the app owns all auth presentation and only wants the
module backend contract.

## Config

```plist
authModule = {
  ui = {
    mode = "headless";
  };
};
```

## What Changes

- module-owned auth HTML routes such as `/auth/login` and `/auth/register` are
  suppressed
- `/auth/api/...` remains the stable session/auth/provider surface
- provider login bootstrap and callback completion still run through the module

## App-Owned Surface

- your SPA, native client, or custom frontend owns the auth screens
- no app templates are required under `templates/auth/...`
- auth state discovery still comes from `/auth/api/session`

## MFA JSON Contract

Phase 18 makes MFA flow state explicit for headless clients:

- `GET /auth/api/mfa`
  - returns factor inventory, policy, preferred factor, and path discovery
  - `mfa.sms.enabled` stays `false` and `paths.sms*` stay empty unless the app
    explicitly enables SMS MFA
- `GET /auth/api/mfa/totp`
  - returns `status`, `flow`, `mfa`, and `session`
  - `flow.state` is `enrollment` or `challenge`
  - `mfa.provisioning` is populated only during enrollment
- when `authModule.mfa.sms.enabled = YES`:
  - `GET /auth/api/mfa/sms` returns SMS challenge state
  - `POST /auth/api/mfa/sms/start` starts phone verification or replacement
  - `POST /auth/api/mfa/sms/verify` completes enrollment or step-up
  - `POST /auth/api/mfa/sms/resend` and `POST /auth/api/mfa/sms/remove` manage
    the enrolled SMS factor
- `POST /auth/api/mfa/totp/verify`
  - returns `flow.state = recovery_codes` on the first successful enrollment
    verify
  - returns `flow.state = complete` on later step-up verifies
  - returns `mfa.recovery_codes` only on that first successful enrollment

That is the intended React/native integration surface; headless apps should not
infer MFA state from the stock HTML pages. When both factors are enrolled, the
contract keeps TOTP preferred and exposes SMS only as an explicit fallback.

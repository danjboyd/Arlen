# Phase 7B Security Defaults and Policy Contracts

Phase 7B defines security-default presets and fail-fast misconfiguration behavior.

This document captures the initial 7B implementation slice completed on 2026-02-23.

## 1. Security Profile Presets

Top-level config key:

```plist
securityProfile = "balanced";
```

Environment overrides:

- `ARLEN_SECURITY_PROFILE`
- legacy compatibility fallback: `MOJOOBJC_SECURITY_PROFILE`

Supported profiles:

- `balanced` (default):
  - `trustedProxy = NO`
  - `session.enabled = NO`
  - `csrf.enabled = NO`
  - `securityHeaders.enabled = YES`
- `strict`:
  - `trustedProxy = NO`
  - `session.enabled = YES`
  - `csrf.enabled = YES`
  - `securityHeaders.enabled = YES`
- `edge`:
  - `trustedProxy = YES`
  - `session.enabled = NO`
  - `csrf.enabled = NO`
  - `securityHeaders.enabled = YES`

Contract behavior:

- Unknown profile values normalize to `balanced`.
- Profile values provide defaults only; explicit config/env settings still override.
- Final config output always includes normalized `securityProfile`.

## 2. Fail-Fast Security Validation

Startup (`startWithError:`) now rejects misconfigured security-critical settings:

- code `330`: `session.enabled` requires non-empty `session.secret`
- code `331`: `csrf.enabled` requires `session.enabled = YES`
- code `332`: `auth.enabled` requires non-empty `auth.bearerSecret`

Diagnostics contract:

- startup returns `NO`
- error domain is `Arlen.Application.Error`
- localized message is deterministic and includes the violated contract
- `config_key`, `reason`, and `security_profile` are attached in error metadata

## 3. Middleware Wiring Contract

Session middleware activation now gates CSRF middleware wiring:

- CSRF middleware is only registered when session middleware is actually active.
- Misconfigured session/CSRF combinations no longer silently wire partial middleware state.

## 4. Executable Verification

Machine-readable contract fixture:

- `tests/fixtures/phase7b/security_policy_contracts.json`

Runtime/config verification:

- `tests/unit/ConfigTests.m`
  - `testLoadConfigMergesAndAppliesDefaults`
  - `testSecurityProfilePresetsApplyDeterministicDefaults`
  - `testLegacyEnvironmentPrefixFallback`
- `tests/unit/ApplicationTests.m`
  - `testStartFailsFastWhenSessionEnabledWithoutSecret`
  - `testStartFailsFastWhenCSRFEnabledWithoutSession`
  - `testStartFailsFastWhenAuthEnabledWithoutBearerSecret`
  - `testStartSucceedsForStrictProfileWhenRequiredSecretsConfigured`
- `tests/unit/Phase7BTests.m`
  - `testSecurityPolicyContractFixtureSchemaAndTestCoverage`

## 5. Runbook Baseline

Deployment checklist for this 7B slice:

1. Choose `securityProfile` intentionally per deployment shape (`balanced`, `strict`, `edge`).
2. If enabling sessions or auth, set required secrets before startup.
3. Validate merged config with `arlen config --json` in CI/deploy checks.
4. Treat startup validation failures as release blockers, not runtime warnings.

# Arlen Phase 12 Roadmap

Status: Complete (Phase 12A-12F delivered on 2026-03-09)  
Last updated: 2026-03-09

Related docs:
- `docs/PHASE11_ROADMAP.md`
- `docs/PHASE3_ROADMAP.md`
- `docs/PHASE2_PHASE3_ROADMAP.md`
- `docs/PHASE13_ROADMAP.md`
- `docs/FEATURE_PARITY_MATRIX.md`
- `docs/PASSWORD_HASHING.md`
- `docs/GETTING_STARTED.md`

## 1. Objective

Make strong authentication dead simple for Arlen applications without turning Arlen core into a full account-management product.

Phase 12 focuses on:

- session-native auth-assurance and step-up primitives
- first-class MFA helpers for common application flows
- OIDC-first federation helpers for common public identity providers
- deterministic policy, diagnostics, and regression coverage

Phase 12 is additive to existing `ALNAuth` bearer/JWT verification and session middleware. It does not replace Arlen's current API auth baseline.

Phase 12 is the reusable auth substrate for future optional modules, especially Phase 13 `auth` and `admin-ui`. Core Arlen owns the primitives and contracts; the product-layer modules own default schemas, routes, templates, and full end-user/admin workflows.

## 1.1 Entry Context

Phase 11 closed the major hostile-input and trust-boundary gaps in sessions, request framing, websocket handling, filesystem boundaries, and proxy trust. The next missing layer is application-facing authentication ergonomics:

1. Local MFA currently requires each app to hand-roll assurance state, step-up policy, TOTP math, recovery-code handling, and session upgrade behavior.
2. External-login support for common providers should be easier than wiring raw OAuth/OIDC flows by hand, but Arlen should still avoid becoming a full account-management product.
3. MFA and external login need one shared assurance model so route policy stays explicit and deterministic.
4. The upcoming module system should be able to consume these primitives directly, so Phase 12 should stabilize contracts instead of drifting into built-in account-product behavior.

## 2. Scope Summary

1. Phase 12A: auth-assurance model and session step-up foundation.
2. Phase 12B: TOTP and recovery-code MFA baseline.
3. Phase 12C: WebAuthn/passkey MFA and phishing-resistant assurance path.
4. Phase 12D: generic OIDC/OAuth2 client foundation.
5. Phase 12E: provider presets and session/login bridge contracts.
6. Phase 12F: hardening, module-facing DX contracts, docs, and release confidence.

Execution order is intentional: Arlen should establish one request/session assurance contract first, land local MFA before federation-specific ergonomics, then layer provider helpers onto the same route-policy and session-upgrade rules.

## 3. Scope Guardrails

- Keep full account-management product surfaces out of Arlen core:
  - registration UX
  - password-reset UX
  - email verification UX
  - account-linking dashboards
  - admin/backoffice identity management
- Core may ship middleware, helpers, protocols, controller utilities, and scaffolds, but not a mandatory product opinion.
- Treat Phase 12 deliverables as module-facing primitives first:
  - stable session/auth contracts belong in core
  - default account/admin product flows belong in optional modules
- Prefer OIDC over raw OAuth2 for login/federation wherever provider support exists.
- Keep bearer/JWT resource-server verification in `ALNAuth` first-class; federation/login support is additive.
- Do not add SMS MFA to Arlen core.
- Defer trusted-device/"remember this browser" flows until the baseline assurance model and factor primitives are stable.

## 4. Milestones

## 4.1 Phase 12A: Auth Assurance + Session Step-Up Foundation

Status: Complete (2026-03-06)

Deliverables:

- Introduce an explicit auth-assurance model for request/session context:
  - normalized subject/provider identifiers
  - authentication methods reference (`amr`-style)
  - assurance level (`aal`-style)
  - primary authentication time
  - MFA satisfaction time
- Add `ALNContext` helpers for assurance inspection so controllers and guards do not parse raw session state directly.
- Rotate session identifiers on:
  - primary login success
  - MFA/step-up completion
  - logout and forced assurance downgrade
- Add route-level assurance policy metadata:
  - minimum assurance level
  - recent-auth/step-up age window
  - deterministic HTML redirect vs JSON/API rejection behavior
- Add middleware/controller helpers for step-up required flows.

Acceptance (required):

- `tests/unit/ApplicationTests.m`:
  - route metadata stores and enforces minimum assurance deterministically
  - recent-auth window enforcement behaves deterministically at boundaries
- `tests/unit/MiddlewareTests.m`:
  - session rotates on assurance elevation
  - logout clears assurance state
- `tests/integration/HTTPIntegrationTests.m`:
  - browser routes redirect to configured step-up entrypoint
  - API routes return deterministic machine-readable rejection payloads

Implemented in current tree:

- `ALNAuthSession` normalizes session/bearer assurance state (`subject`, `provider`, `amr`, `aal`, auth timestamps, session rotation identifier).
- `ALNContext`, `ALNController`, `ALNRoute`, and `ALNApplication` expose step-up inspection and route-policy helpers.
- `configureAuthAssuranceForRouteNamed:minimumAuthAssuranceLevel:maximumAuthenticationAgeSeconds:stepUpPath:error:` provides route-level policy wiring.
- Protected browser routes redirect to the configured step-up path with `X-Arlen-Step-Up-Required: 1`; JSON/API routes return structured `403 step_up_required`.

## 4.2 Phase 12B: TOTP + Recovery Code MFA Baseline

Status: Complete (2026-03-06)

Deliverables:

- Add TOTP helpers:
  - secret generation
  - `otpauth://` provisioning URI generation
  - verification with injectable clock and bounded skew window
- Add recovery-code helpers:
  - deterministic code generation
  - hash-at-rest storage contract
  - one-time consume semantics
  - regeneration invalidates older sets
- Add a minimal MFA storage abstraction for app-owned persistence:
  - factor enrollment lookup
  - recovery-code verification/consume
  - lockout or attempt-counter persistence hooks
- Add step-up completion helpers that upgrade session assurance after successful local factor verification.

Acceptance (required):

- `tests/unit/MFATests.m`:
  - TOTP verification accepts valid current-window codes and rejects stale/future-window codes outside skew policy
  - recovery codes are single-use and hashed-at-rest
  - regenerated recovery-code sets invalidate prior codes
- `tests/integration/HTTPIntegrationTests.m`:
  - enrolled user completes step-up and reaches an AAL2-protected route
  - repeated bad codes trigger deterministic throttle/lockout response

Implemented in current tree:

- `ALNTOTP` provides secret generation, provisioning URI generation, deterministic code generation, and skew-bounded verification.
- `ALNRecoveryCodes` provides generation, Argon2id hash-at-rest helpers, single-use consume semantics, and regeneration invalidation coverage.
- Controller/session helpers upgrade assurance state after successful local factor verification.

## 4.3 Phase 12C: WebAuthn / Passkey MFA

Status: Complete (2026-03-06)

Deliverables:

- Add WebAuthn challenge helpers for registration and assertion ceremonies.
- Verify WebAuthn ceremony invariants:
  - challenge binding
  - RP ID/origin binding
  - timeout/expiration
  - user-presence and user-verification policy
  - credential replay/sign-count handling where applicable
- Normalize WebAuthn success into the same assurance/session upgrade model as TOTP.
- Keep WebAuthn usable both as a step-up factor and as a stronger local MFA option for sensitive routes.

Acceptance (required):

- `tests/unit/WebAuthnTests.m`:
  - origin and RP ID mismatch are rejected
  - replayed/stale challenges are rejected
  - success path upgrades assurance deterministically
- `tests/fixtures/auth/phase12_webauthn_cases.json`:
  - fixture corpus for valid and invalid registration/assertion payloads

Implemented in current tree:

- `ALNWebAuthn` provides registration/assertion option generation plus verification for challenge, origin, RP ID hash, UP/UV flags, ES256 credential keys, and sign-count replay rejection.
- Successful assertions normalize into the same AAL2 step-up contract used by local MFA helpers.
- Current registration verification intentionally supports the deterministic `fmt=none` attestation baseline first.

## 4.4 Phase 12D: OIDC / OAuth2 Client Foundation

Status: Complete (2026-03-09)

Deliverables:

- Add a generic OIDC-first client for authorization-code + PKCE flows:
  - authorization URL generation
  - `state` and `nonce` management
  - token exchange
  - ID-token verification
  - JWKS fetch/cache/rotation handling
- Keep a generic OAuth2 fallback path for providers that do not support full OIDC login semantics.
- Normalize provider identity into a stable claim shape separate from raw provider payloads.
- Add deterministic timeout/error/redaction behavior for provider HTTP interactions.
- Keep this layer product-neutral so future modules can consume it:
  - no built-in registration/reset/account UX
  - no provider-specific controller pages in core
  - no mandatory persistence model beyond explicit contracts

Acceptance (required):

- `tests/unit/OIDCClientTests.m`:
  - PKCE, `state`, and `nonce` generation/verification are deterministic and fail closed
  - tampered callback parameters are rejected
  - stale or mismatched JWKS/key material is rejected deterministically
- `tests/fixtures/auth/phase12_oidc_cases.json`:
  - callback tamper, nonce mismatch, key rotation, and timeout scenarios

Implemented in current tree:

- `ALNOIDCClient` provides authorization-code + PKCE request generation, callback validation, token-exchange request shaping, token-response parsing, ID-token verification, and normalized provider identity output.
- ID-token verification supports HS256 and RS256 flows with issuer/audience/exp/nbf/nonce enforcement plus JWKS freshness checks.
- `tests/unit/OIDCClientTests.m` covers PKCE/state/nonce generation, tampered callback rejection, client-secret redaction, RS256 key verification, nonce mismatch, JWKS rotation miss, JWKS expiry, and HS256 normalization.
- `tests/fixtures/auth/phase12_oidc_cases.json` captures the hostile-input fixture baseline for callback tamper, nonce mismatch, and JWKS rotation/expiry scenarios.

## 4.5 Phase 12E: Provider Presets + Session/Login Bridge Contracts

Status: Complete (2026-03-09)

Deliverables:

- Add first-party provider presets for common public providers where contracts are stable:
  - Google
  - GitHub
  - Microsoft
  - Apple
  - generic OIDC providers such as Okta/Auth0-style deployments
- Add session bootstrap/login bridge helpers and protocols:
  - app or module callback maps provider identity to local user/account through an explicit hook/protocol
  - successful provider login establishes Arlen session state without apps or future modules reimplementing callback plumbing
- Ensure local assurance policy composes with external login:
  - provider login can satisfy primary authentication
  - AAL2 routes may still require local step-up unless stronger assurance is explicitly established
- Add deterministic account-linking hooks without shipping a full product UI.
- Keep this milestone product-neutral:
  - provider presets and session bootstrap live in core
  - module-owned login/register/callback UX lives in Phase 13 `auth`

Acceptance (required):

- `tests/integration/HTTPIntegrationTests.m`:
  - stub-provider login bridge flow completes and establishes session state
  - AAL2-protected route still triggers local step-up after provider login when required by policy
- `tests/unit/ApplicationTests.m`:
  - provider preset config merges deterministically with explicit overrides

Implemented in current tree:

- `ALNAuthProviderPresets` ships deterministic first-party provider defaults for Google, GitHub, Microsoft, Apple, Okta, and Auth0-style OIDC deployments.
- `ALNAuthProviderSessionBridge` provides explicit provider-identity resolution and local session-bootstrap hooks without embedding product-specific account UX in core.
- `tests/unit/ApplicationTests.m` verifies deterministic provider preset merging with explicit overrides.
- `tests/integration/HTTPIntegrationTests.m` adds the stub provider login/session bootstrap and local step-up-after-provider-login coverage expected for future module consumers.

## 4.6 Phase 12F: Hardening + Module-Facing DX Contracts + Confidence Artifacts

Status: Complete (2026-03-09)

Deliverables:

- Add Phase 12 hostile-input and regression corpus for:
  - malformed TOTP secrets and provisioning URIs
  - recovery-code replay and regeneration races
  - WebAuthn challenge replay and origin mismatch
  - OIDC callback tampering, state reuse, nonce mismatch, and JWKS rotation
- Add sanitizer/fuzz targets for security-sensitive parsing/material handling:
  - base32/TOTP secret parsing
  - JWT/JWK parsing
  - WebAuthn JSON/CBOR fixture ingestion
- Add first-party docs and module-facing integration contracts:
  - getting-started guidance for local MFA and provider login primitives
  - API reference updates for new auth-assurance/MFA/OIDC surfaces
  - a minimal sample app showing TOTP MFA plus one OIDC provider flow on top of core primitives
  - explicit integration guidance for future Phase 13 auth-module hooks/store wiring instead of a built-in account-product scaffold

Acceptance (required):

- `make phase12-confidence` writes artifacts under `build/release_confidence/phase12/`
- new docs/sample app are validated by the Phase 12 confidence gate and referenced from the docs index
- unit and integration coverage for OIDC/provider flows are present in the standard XCTest suites

Implemented in current tree:

- `examples/auth_primitives/` demonstrates local TOTP step-up plus a stub OIDC provider flow on top of the core Phase 12 contracts.
- `tools/ci/run_phase12_confidence.sh` and `tools/ci/generate_phase12_confidence_artifacts.py` generate a dedicated Phase 12 confidence artifact pack under `build/release_confidence/phase12/`.
- `docs/GETTING_STARTED.md`, `docs/CLI_REFERENCE.md`, `docs/README.md`, and `README.md` now reference the new helper surface, sample app, and confidence gate.

## 5. Recommended Execution Sequence

1. Land assurance/session semantics before any factor or provider-specific work.
2. Ship TOTP + recovery codes as the default-first MFA path.
3. Add WebAuthn on top of the same assurance/session contract instead of building a separate passkey stack.
4. Add generic OIDC/OAuth2 client primitives before any provider presets.
5. Layer provider presets and session/login bridge contracts only after the generic client contracts are stable.
6. Make Phase 12 release confidence depend on fixture, hostile-input, and sample-flow coverage, not just happy-path tests.

## 6. Explicit Non-Goals

- Full registration/reset/email-verification product flows in Arlen core.
- SMS/voice MFA in Arlen core.
- Provider-specific SDK sprawl or one-off controller logic embedded in the framework.
- Replacing current bearer/JWT API auth helpers with a login-product abstraction.
- Shipping the full Phase 13 `auth` or `admin-ui` module experience inside core Arlen.

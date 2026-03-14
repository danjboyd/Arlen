# Arlen Phase 18 Roadmap

Status: complete on 2026-03-13 (`18A-18G`); downstream follow-up `18H` queued
Last updated: 2026-03-14

Related docs:
- `docs/AUTH_MODULE.md`
- `docs/AUTH_UI_INTEGRATION_MODES.md`
- `docs/PHASE15_ROADMAP.md`
- `docs/PHASE12_ROADMAP.md`
- `../V1_SPEC.md`

## 1. Objective

Mature the first-party `auth` module beyond Phase 15 UI ownership modes so the
same backend auth contract supports three presentation layers cleanly:

- full-page default auth UI for server-rendered apps
- reusable server-rendered auth fragments for app-owned EOC pages
- strengthened headless JSON contracts for React/native clients

Phase 18 now also tracks an additive MFA follow-on: optional SMS support through
Twilio Verify, while keeping authenticator-app flows first-class and preferred.

Phase 18 does not replace the existing Phase 15 model. It builds on it.

## 1.1 Why Phase 18 Exists

Phase 15 established who owns the HTML surface:

- `headless`
- `module-ui`
- `generated-app-ui`

That solved the coarse ownership problem, but the reusable composition story is
still incomplete:

- the stock auth UI is still mostly page-oriented rather than fragment-first
- MFA enrollment and step-up are still too tightly coupled in the default UI
- server-rendered apps lack a stable supported contract for embedding auth
  components such as MFA/account-security panels inside app-owned pages
- React/native clients have stable `/auth/api/...` routes, but the MFA JSON
  contract is still closer to "API parity with the HTML flow" than "first-class
  headless product surface"

Phase 18 closes that gap.

## 2. Design Principles

- Keep one auth backend contract across all presentation modes.
- Treat full-page defaults and embeddable fragments as two consumers of the
  same reusable building blocks.
- Expose only coarse, useful auth fragments as public/stable contracts.
- Keep low-level layout helpers private so internal markup can evolve safely.
- Preserve `headless` as a first-class product mode for React/native apps.
- Do not require SPA frameworks inside the auth module.
- Prefer small browser-native assets over server-side image pipelines for MFA QR
  rendering.
- Keep SMS MFA disabled by default and policy-gated.
- Prefer stronger factors such as passkeys/WebAuthn and TOTP over SMS.
- Treat SMS as an optional secondary factor or fallback, not the default MFA
  path.
- Use Twilio Verify as the delivery/verification provider seam rather than
  baking raw carrier delivery semantics into core auth logic.

## 3. Scope Summary

1. Phase 18A: reusable auth fragment contract and fragment-first stock pages.
2. Phase 18B: MFA enrollment/challenge/recovery UI maturation.
3. Phase 18C: headless MFA/API contract maturity for React/native clients.
4. Phase 18D: docs, examples, and confidence coverage.
5. Phase 18E: optional SMS MFA factor integration through Twilio Verify.
6. Phase 18F: factor-management GUI and multi-factor enrollment UX.
7. Phase 18G: docs, examples, and confidence coverage for SMS/Twilio Verify.
8. Phase 18H: generated-app-ui include-path normalization and auth-page render
   confidence.

## 4. Scope Guardrails

- Do not move app-owned account/business workflow code into the auth module.
- Do not force server-rendered apps to consume JSON when EOC fragments are the
  better fit.
- Do not force React/native clients to consume HTML or scrape auth pages.
- Do not publish every low-level auth partial as a stable public API.
- Do not split backend auth semantics by presentation mode.
- Do not make SMS the default or only recommended MFA factor in stock UI.
- Do not require Twilio Verify credentials for TOTP-only applications.
- Do not allow phone add/change/remove flows to bypass recent reauthentication
  and existing-factor checks.

## 5. Milestones

Delivered on 2026-03-13:

- stock auth pages now compose through the supported coarse fragments
- TOTP HTML now separates enrollment, challenge, and recovery-code completion
- `/auth/api/mfa/totp` and `/auth/api/mfa/totp/verify` now expose explicit
  `flow` and `mfa` payloads for headless clients
- `generated-app-ui` eject now copies the fragment-first MFA templates plus the
  local QR asset
- confidence coverage now includes stock HTML MFA states, embeddable fragment
  render paths, and the new headless MFA JSON shape
- optional SMS MFA through Twilio Verify as a disabled-by-default factor
- factor-management UX that lets users enroll both authenticator app and SMS
  when app policy allows it
- headless and server-rendered coverage for multi-factor inventory, SMS
  enrollment, SMS challenge, and phone-change safeguards

Delivered on 2026-03-14:

- generated-app-ui auth templates now render through unsuffixed nested include
  targets the same way top-level view renders do
- regression coverage now includes direct runtime normalization checks plus a
  generated-app-ui auth-page scaffold regression that executes when
  `ARLEN_PG_TEST_DSN` is configured

## 5.1 Phase 18A: Reusable Auth Fragment Contract

Deliverables:

- Define a stable set of coarse auth fragments intended for app reuse in EOC:
  - `mfa_enrollment_panel`
  - `mfa_challenge_form`
  - `mfa_recovery_codes_panel`
  - `provider_login_buttons`
  - additional account-security fragments only where they are broadly reusable
- Keep lower-level partials such as field rows and wrapper plumbing internal.
- Build the stock full-page auth UI from those same coarse fragments.
- Document the fragment identifiers, required locals, and expected context
  values.
- Use the Phase 9 EOC composition model (`layout`, `slot`, `include`, `render`,
  required locals) as the supported assembly path for fragment consumers.

Acceptance (required):

- the stock full-page MFA/auth pages render by composing the same public
  fragments that app-owned EOC pages can consume
- coarse fragment contracts are documented and stable
- internal/private auth partials remain free to change

## 5.2 Phase 18B: MFA UI Maturation

Deliverables:

- Split MFA enrollment from MFA challenge in the stock auth UI.
- Keep the existing TOTP step-up route focused on interruption-style challenge
  behavior.
- Add a distinct enrollment-oriented flow for authenticator setup.
- Add a recovery-code completion screen after first successful enrollment
  verification.
- Replace raw provisioning-URI presentation with:
  - client-side QR rendering from `otpauth_uri`
  - manual secret/key entry fallback
- Expose the new enrollment/challenge/recovery building blocks through the
  reusable fragment contract from 18A.

Acceptance (required):

- already-enrolled users see a short challenge-oriented MFA flow
- first-time enrollment users see setup guidance plus a recovery-code completion
  step
- the stock full-page UI and embeddable fragment UI stay behaviorally aligned

## 5.3 Phase 18C: Headless MFA/API Contract Maturity

Deliverables:

- Keep `/auth/api/...` as the stable headless namespace.
- Strengthen MFA-specific JSON contracts so React/native apps can own their UI
  cleanly without reverse-engineering HTML-oriented flows.
- Add explicit JSON payload shapes for:
  - MFA status / factor state
  - enrollment provisioning data
  - challenge vs enrollment flow state
  - first-verification recovery-code completion payloads
  - any required acknowledgement/follow-up action metadata
- Document the JSON fields as the supported React/native surface instead of
  relying on HTML parity by implication.

Acceptance (required):

- React/native clients can implement MFA UX using JSON-only contracts
- HTML mode and headless mode use the same backend/session semantics
- JSON behavior is explicit enough that apps do not need to scrape or infer the
  flow from the stock HTML pages

## 5.4 Phase 18D: Docs, Examples, and Confidence

Deliverables:

- Update:
  - `docs/AUTH_MODULE.md`
  - `docs/AUTH_UI_INTEGRATION_MODES.md`
  - `docs/CLI_REFERENCE.md`
  - `docs/GETTING_STARTED.md`
- Add one server-rendered example consuming auth fragments inside an app-owned
  account/security page.
- Add one headless/SPA-oriented example consuming the MFA JSON contract.
- Extend confidence/integration coverage for:
  - stock full-page MFA enrollment
  - stock full-page MFA challenge
  - reusable fragment render paths
  - headless MFA JSON flows
  - recovery-code completion

Acceptance (required):

- the fragment contract and the headless MFA contract are both documented and
  example-backed
- regressions in MFA flow shape are caught by automated tests

## 5.5 Phase 18E: Optional SMS MFA via Twilio Verify

Deliverables:

- Add an optional SMS MFA factor backed by Twilio Verify.
- Keep SMS support disabled by default unless the app config explicitly enables
  it and provides the required Twilio Verify credentials.
- Add config/runtime seams for:
  - Verify service SID
  - account credentials / auth token material
  - message locale or template options where appropriate
  - app policy toggles for whether SMS can be used for enrollment, challenge,
    or fallback only
- Model SMS as a separately enrolled factor, not as an implicit substitute for
  TOTP.
- Require recent authentication plus an existing verified factor to add,
  replace, or remove a phone-based factor.
- Add attempt limits, resend cooldowns, audit hooks, and generic error shaping
  around SMS challenge issuance and verification.

Acceptance (required):

- TOTP-only apps remain unaffected and require no Twilio configuration.
- When SMS MFA is disabled, no SMS enrollment or challenge routes/CTAs appear.
- When SMS MFA is enabled, apps can bind a phone factor through Twilio Verify
  without changing the core auth session semantics.
- Phone-factor lifecycle operations are guarded strongly enough for MFA use.

## 5.6 Phase 18F: Factor-Management GUI and Multi-Factor UX

Deliverables:

- Add stock full-page and embeddable auth fragments for MFA factor management,
  including factor inventory and SMS enrollment/challenge panels where useful.
- Keep authenticator app enrollment visually primary and recommended in the
  stock UI.
- Present SMS as a weaker optional factor or fallback with clear labeling.
- Let users enroll both an authenticator app and SMS on the same account when
  policy allows it; do not force a single-factor choice.
- Keep factor-management actions explicit:
  - add phone
  - verify phone
  - resend SMS code
  - remove phone
  - rotate or reset only after strong reauthentication
- During step-up, prefer the strongest enrolled factor allowed by policy and
  only offer SMS fallback when explicitly enabled.
- Expose factor inventory and preferred challenge state through headless JSON so
  React/native clients can own the same UX.

Acceptance (required):

- Stock UI hides SMS completely when disabled.
- Enabled apps can present both authenticator-app and SMS enrollment paths on
  the same account-security surface.
- Stock UI clearly communicates that SMS is weaker than authenticator-app MFA.
- Step-up flows do not silently downgrade to SMS when a stronger factor is
  enrolled and allowed.

## 5.7 Phase 18G: Docs, Examples, and Confidence for SMS MFA

Deliverables:

- Update:
  - `docs/AUTH_MODULE.md`
  - `docs/AUTH_UI_INTEGRATION_MODES.md`
  - `docs/CLI_REFERENCE.md`
  - `docs/GETTING_STARTED.md`
- Add one server-rendered example showing app-owned account/security pages with
  both TOTP and optional SMS factor management.
- Add one headless example or fixture set covering the JSON contract for SMS
  enrollment and challenge using Twilio Verify-friendly test seams/mocks.
- Extend confidence/integration coverage for:
  - disabled-by-default behavior
  - SMS enrollment and verification
  - factor inventory showing both TOTP and SMS
  - preferred stronger-factor challenge behavior
  - guarded phone add/change/remove flows

Acceptance (required):

- Apps can discover the SMS factor contract from docs without reverse
  engineering Twilio-specific behavior.
- The server-rendered and headless SMS flows are example-backed.
- Regression coverage catches changes to factor inventory, SMS challenge state,
  and policy gating.

## 5.8 Phase 18H: Generated-App-UI Include-Path Normalization

Delivered on 2026-03-14 in response to a downstream bug report after
`MusicianApp` validated a real generated-app-ui auth regression on current
Arlen head.

Deliverables:

- Normalize unsuffixed logical include targets so `ALNEOCInclude(...)` resolves
  auth-generated partial/body/fragment paths the same way top-level
  `ALNView`/`ALNEOCRenderTemplate(...)` page renders do.
- Preserve the current generated-app-ui contract where auth page/body/partial
  helpers may return logical paths such as `auth/partials/page_wrapper` without
  forcing every caller to append `.html.eoc` manually.
- Add regression coverage that boots generated-app-ui auth pages end-to-end and
  exercises nested `ALNEOCInclude(...)` calls through real stock auth templates
  rather than only direct template lookups. The end-to-end scaffold regression
  remains gated on `ARLEN_PG_TEST_DSN` because the auth module currently
  requires `database.connectionString` at startup.

Acceptance (required):

- generated-app-ui stock auth pages such as `/auth/login` and `/auth/register`
  render successfully without local app patches to append `.html.eoc`.
- include resolution semantics are consistent between top-level page renders and
  nested `ALNEOCInclude(...)` calls.
- MFA/body/fragment auth templates are covered by real generated-app-ui
  integration confidence, not only unit-level path-resolution checks.

## 6. Completion Criteria

Phase 18 is complete when:

1. the stock auth UI is composed from supported coarse auth fragments
2. server-rendered apps can embed stable auth/MFA fragments inside app-owned EOC
   pages without forking module-owned auth templates
3. React/native apps can implement MFA UX using documented `/auth/api/...`
   contracts only
4. MFA enrollment, challenge, and recovery-code completion are all represented
   coherently in both stock UI and headless contracts
5. docs, examples, and confidence coverage reflect the new split
6. optional SMS MFA can be enabled through Twilio Verify without weakening the
   default TOTP-first posture
7. stock UI and headless clients can both manage multiple enrolled MFA factors,
   including authenticator app plus optional SMS

Downstream note:

`18A-18G` shipped on 2026-03-13, and `18H` shipped on 2026-03-14 to restore the
generated-app-ui auth-page render path after a real downstream regression was
reported that same day.

## 7. Expected Outcome

After Phase 18, Arlen should offer one auth backend and three clean product
paths:

1. stock full-page auth UI
2. server-rendered app-owned pages that embed reusable auth fragments
3. React/native app-owned UI built entirely on `/auth/api/...`

That backend should stay TOTP-first while optionally supporting SMS through
Twilio Verify as a policy-controlled secondary factor.

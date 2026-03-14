# Arlen Phase 18 Roadmap

Status: Complete on 2026-03-13
Last updated: 2026-03-13

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

## 3. Scope Summary

1. Phase 18A: reusable auth fragment contract and fragment-first stock pages.
2. Phase 18B: MFA enrollment/challenge/recovery UI maturation.
3. Phase 18C: headless MFA/API contract maturity for React/native clients.
4. Phase 18D: docs, examples, and confidence coverage.

## 4. Scope Guardrails

- Do not move app-owned account/business workflow code into the auth module.
- Do not force server-rendered apps to consume JSON when EOC fragments are the
  better fit.
- Do not force React/native clients to consume HTML or scrape auth pages.
- Do not publish every low-level auth partial as a stable public API.
- Do not split backend auth semantics by presentation mode.

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

## 7. Expected Outcome

After Phase 18, Arlen should offer one auth backend and three clean product
paths:

1. stock full-page auth UI
2. server-rendered app-owned pages that embed reusable auth fragments
3. React/native app-owned UI built entirely on `/auth/api/...`

That is the maturity bar for treating the `auth` module as a reusable framework
component rather than only a default-first starter surface.

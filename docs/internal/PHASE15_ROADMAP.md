# Arlen Phase 15 Roadmap

Status: Complete (`15A-15E` delivered on 2026-03-10)  
Last updated: 2026-03-10

Related docs:
- `docs/AUTH_UI_INTEGRATION_MODES.md`
- `docs/AUTH_MODULE.md`
- `docs/MODULES.md`
- `docs/PHASE13_ROADMAP.md`
- `docs/PHASE14_ROADMAP.md`
- `docs/CLI_REFERENCE.md`
- `docs/GETTING_STARTED.md`

## 1. Objective

Productize auth presentation ownership so apps can adopt the first-party `auth`
module in one of three explicit modes:

- `headless`
- `module-ui`
- `generated-app-ui`

Phase 15 is a focused follow-on to Phase 13 `auth`. It does not change the
core-auth substrate or replace the existing `/auth/api/...` backend contract.
It improves how apps integrate auth HTML and app shell ownership.

## 1.1 Why Phase 15 Exists

The current `auth` module already provides:

- stable auth/session/provider/MFA/password-reset flows
- HTML routes under `/auth/...`
- headless JSON routes under `/auth/api/...`
- template override support through `templates/modules/auth/...`

That is functional, but the main customization seam is still low-level template
replacement. Apps wanting auth pages to share their own shell, guest layout,
navigation, and design system are forced earlier than necessary into template
forking.

Phase 15 closes that product gap.

## 1.2 Sequencing

Phase 15 was planned as the auth UI ownership closeout between the early and
late Phase 14 module slices.

Historical delivery order:

- Phase 14A/14B/14C landed first
- Phase 15 stabilized auth presentation ownership and the app-shell/eject model
- Phase 14D/14E/14F/14G/14H/14I then resumed and shipped

In the current tree, both Phase 14 and Phase 15 are complete.

## 1.3 Current Delivery State

- `15A` complete: explicit `headless`, `module-ui`, and `generated-app-ui`
  contract with stable `/auth/api/...` routes
- `15B` complete: app-owned guest-shell layout and page-context hook support
- `15C` complete: partialized auth page contract and deterministic override model
- `15D` complete: `arlen module eject auth-ui --json` workflow
- `15E` complete: auth UI docs, examples, focused HTTP integration coverage,
  and `phase15-confidence`

## 2. Design Principles

- Keep one auth backend contract across all UI modes.
- Treat UI mode as presentation ownership, not auth-behavior divergence.
- Preserve Objective-C-native explicitness:
  - plist config
  - protocol-based hooks
  - deterministic template lookup
- Make app-shell integration first-class, not an accidental side effect of raw
  template overrides.
- Keep `headless` a supported product mode, not merely "ignore the HTML routes".
- Keep the current override model available as an escape hatch.
- Add a first-class eject/scaffold workflow only after the page/partial contract
  is stable.

## 3. Scope Summary

1. Phase 15A: auth UI mode contract and route split.
2. Phase 15B: `module-ui` app-shell integration.
3. Phase 15C: partialized auth UI contract and override model.
4. Phase 15D: `generated-app-ui` eject/scaffold workflow.
5. Phase 15E: docs, examples, and confidence coverage.

## 4. Scope Guardrails

- Do not move auth product flows back into core Arlen.
- Do not create a second auth backend just for SPA or generated UI modes.
- Do not bundle React/Vue frontend code into the module.
- Do not use hidden runtime magic such as swizzling or global category-driven
  template mutations.
- Do not break the existing `/auth/api/...` contract while adding UI modes.

## 5. Milestones

## 5.1 Phase 15A: Auth UI Mode Contract + Route Split

Deliverables:

- Add `authModule.ui` config parsing to the auth module.
- Support explicit UI modes:
  - `headless`
  - `module-ui`
  - `generated-app-ui`
- In `headless` mode:
  - keep `/auth/api/...` active
  - keep provider callback/completion flows active
  - disable module-owned HTML form/result routes
- Keep backend/session/provider/MFA behavior identical across modes.

Acceptance (required):

- `headless` disables module-owned HTML routes deterministically
- `/auth/api/...` remains stable
- provider callback flows remain coherent
- unit/integration coverage proves the mode split does not change auth semantics

## 5.2 Phase 15B: `module-ui` App-Shell Integration

Deliverables:

- Add first-class auth layout config such as:

```plist
authModule = {
  ui = {
    mode = "module-ui";
    layout = "layouts/guest";
  };
};
```

- Add a small explicit Objective-C hook for page-level layout/context
  customization.
- Support guest-shell auth rendering without replacing each auth page template.
- Keep module-owned auth page bodies as the default-first path.

Acceptance (required):

- an app can render stock auth flows inside an app-owned guest layout
- layout/context hooks are deterministic and documented
- no template wholesale replacement is required for common shell integration

## 5.3 Phase 15C: Partialized Auth UI Contract + Override Model

Deliverables:

- Break auth UI into smaller stable partials/components:
  - page wrapper
  - message block
  - error block
  - form shell
  - field row
  - provider CTA row
  - result actions
- Define deterministic override precedence for:
  - explicit `authModule.ui.partials.*` overrides
  - app template overrides
  - module defaults
- Document stable auth page identifiers and partial identifiers.

Acceptance (required):

- apps can restyle the provider CTA row without replacing the whole login page
- shared shell/error/form pieces can be overridden once across multiple pages
- override precedence is deterministic and test-covered

## 5.4 Phase 15D: `generated-app-ui` Eject/Scaffold Workflow

Deliverables:

- Add a first-class CLI workflow:

```bash
./build/arlen module eject auth-ui --json
```

- Scaffold app-owned auth templates/partials/assets into the app tree.
- Keep module-owned backend routes and auth runtime contracts.
- Emit machine-readable Phase 7G-style payloads:
  - `workflow`
  - `status`
  - `created_files`
  - `updated_files`
  - `next_steps`
- Default generated template prefix to `templates/auth/...`.

Acceptance (required):

- a freshly ejected auth UI boots without controller/route rewiring
- generated HTML remains on the same backend/session/provider/MFA contract
- CLI output is deterministic and agent-friendly

## 5.5 Phase 15E: Docs + Examples + Confidence

Deliverables:

- Update:
  - `docs/AUTH_MODULE.md`
  - `docs/CLI_REFERENCE.md`
  - `docs/GETTING_STARTED.md`
- Add one canonical example for each mode:
  - `headless`
  - `module-ui`
  - `generated-app-ui`
- Add mode-parity confidence coverage for:
  - login
  - registration
  - password reset
  - MFA step-up
  - provider login

Acceptance (required):

- all three modes are documented and example-backed
- example apps prove the same auth contract across all modes
- confidence coverage exercises both HTML and JSON parity where applicable

## 6. Completion Criteria

Phase 15 is complete when:

1. apps can choose `headless`, `module-ui`, or `generated-app-ui` through a
   documented first-class contract
2. stock auth flows can render inside an app-owned guest shell without raw
   template forking
3. app-owned auth presentation can be scaffolded/ejected while preserving the
   same backend auth contract
4. `/auth/api/...` remains the stable headless auth surface for SPA/API clients
5. the mode model is documented, tested, and example-backed

## 7. Non-Goals

- rewriting auth backend behavior as app-owned generated code
- replacing the auth module with a starter-kit-only approach
- a bundled SPA frontend inside the auth module
- cross-module guest-shell abstraction for every first-party module in this
  phase

## 8. Expected Outcome

After Phase 15, an app should be able to reach one of these states quickly:

1. use the stock auth UI
2. use the stock auth flows inside an app-owned guest shell
3. own the auth UI completely without rewriting the auth backend stack

That is the auth integration bar Arlen should set before resuming the remaining
Phase 14 module product work.

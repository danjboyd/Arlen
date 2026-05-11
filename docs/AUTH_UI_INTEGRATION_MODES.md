# Auth UI Integration Modes

Status: Shipped

Related docs:
- `docs/AUTH_MODULE.md`
- `docs/MODULES.md`
- `docs/CLI_REFERENCE.md`
- `docs/GETTING_STARTED.md`

## 1. Objective

Define the first-class auth UI integration model for the first-party `auth`
module so apps can adopt Arlen auth without choosing only between:

1. a framework-owned auth site, or
2. immediate full template forking.

The goal is to keep one stable auth backend contract while supporting three
clear presentation modes:

- `headless`
- `module-ui`
- `generated-app-ui`

## 2. Current State

The `auth` module now provides:

- explicit `headless`, `module-ui`, and `generated-app-ui` modes
- stable `/auth/api/...` routes across all three modes
- module-owned auth page bodies and partials for `module-ui`
- app-owned layout and context injection through
  `ALNAuthModuleUIContextHook`
- deterministic partial override resolution through `authModule.ui.partials`
- generated app-owned auth templates under `templates/auth/...` for
  `generated-app-ui`

The module also ships:

- fragment-first stock auth pages
- supported coarse embeddable auth fragments for server-rendered EOC apps
- stronger MFA-focused headless JSON contracts for React/native clients
- optional SMS MFA through Twilio Verify, disabled by default and preserving
  the same UI ownership model

## 3. Design Goals

- Keep one auth runtime contract for HTML, SPA, and provider-login flows.
- Make `headless`, module-owned UI, and app-owned UI explicit supported modes.
- Let apps place auth pages inside an app-owned guest shell without replacing
  every auth page.
- Break auth UI into smaller partials/components so targeted overrides are
  possible.
- Provide a deterministic scaffold/eject workflow for teams that want full
  presentation ownership.
- Preserve existing template override behavior as an advanced escape hatch.
- Keep GNUstep-friendly, Objective-C-native contracts:
  - plist config
  - protocol-based hooks
  - deterministic template lookup

## 4. Non-Goals

- Rewriting auth backend flows as app-owned code.
- Replacing `/auth/api/...` with a separate SPA-only auth stack.
- Forcing JS frontend code into the module.
- Turning auth UI customization into uncontrolled runtime magic.

## 5. Supported Modes

## 5.1 `headless`

Purpose:
- API-first or SPA-first apps that want the auth backend contract but no
  module-owned HTML forms.

Behavior:
- Keep backend/session/provider/MFA/password-reset contracts active.
- Keep `/auth/api/...` active.
- Keep provider callback/protocol endpoints active when required for auth
  completion.
- Do not register module-owned HTML form/result routes such as:
  - `/auth/login`
  - `/auth/register`
  - `/auth/password/forgot`
  - `/auth/password/reset`
  - `/auth/mfa/totp`
- No module-owned auth layout or page templates are assumed.

Expected app usage:
- React/SPA login screens
- native/mobile clients
- API-driven product shells

## 5.2 `module-ui`

Purpose:
- Default-first server-rendered auth with minimal setup, but with app-shell
  integration.

Behavior:
- Keep module-owned auth page templates as the default page bodies.
- Allow the app to specify an app-owned layout such as `layouts/guest`.
- Allow smaller auth partials to be overridden individually.
- Allow an app-owned context hook to add shell/navigation/brand context without
  replacing the page template wholesale.
- Continue to support raw template override precedence.

Expected app usage:
- server-rendered apps that want stock auth flows inside a house layout
- apps with distinct guest and signed-in shells

## 5.3 `generated-app-ui`

Purpose:
- Apps that want to own auth presentation fully while still using the Arlen auth
  backend contract.

Behavior:
- Keep module-owned controllers, backend flows, session semantics, provider
  bridge, MFA, and JSON routes.
- Render HTML from app-owned templates scaffolded into the app tree.
- Treat those app-owned templates as the primary HTML surface.
- Preserve the same route names, request/response contracts, and backend hooks.

Expected app usage:
- polished product-facing apps
- teams with strong design systems
- apps ready to own auth presentation without owning auth backend logic

## 6. Config Contract

```plist
authModule = {
  ui = {
    mode = "module-ui"; // "module-ui" default; also "headless", "generated-app-ui"
    layout = "layouts/guest";
    generatedPagePrefix = "auth";
    partials = {
      pageWrapper = "auth/partials/page_wrapper";
      errorBlock = "auth/partials/error_block";
      providerRow = "auth/partials/provider_row";
    };
    contextClass = "APPAuthUIContextHook";
  };
};
```

Config semantics:

- `ui.mode`
  - `module-ui` default
  - `headless` disables module-owned HTML page routes
  - `generated-app-ui` resolves HTML templates from the app-owned prefix first
- `ui.layout`
  - only used in `module-ui`
  - default remains `modules/auth/layouts/main`
- `ui.generatedPagePrefix`
  - only used in `generated-app-ui`
  - default `auth`
- `ui.partials`
  - optional fine-grained partial override map for `module-ui`
- `ui.contextClass`
  - optional Objective-C hook for page-specific shell/layout context

## 7. Objective-C Hook Contract

Add a small explicit hook instead of relying on implicit global template state:

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

Use cases:

- choose `layouts/guest`
- inject app branding/navigation/footer links
- provide page-level shell data without replacing the page body template

This should remain explicit:

- no swizzling
- no hidden categories
- no global mutable template state

## 8. Template and Partial Contract

Module page identifiers should be stable and documented:

- `login`
- `register`
- `forgot_password`
- `reset_password`
- `verify_result`
- `totp_enrollment`
- `totp_challenge`
- `totp_recovery_codes`
- `provider_result`

Module partial identifiers should also be stable:

- `page_wrapper`
- `message_block`
- `error_block`
- `form_shell`
- `field_row`
- `provider_row`
- `result_actions`

Resolution precedence in `module-ui` should be deterministic:

1. explicit `authModule.ui.partials.*` logical path override
2. app template override path under `templates/modules/auth/...`
3. module-owned default resource

That gives the app a supported middle path before full ejection.

Fragment-first refinement:

- the current low-level partial contract remains useful for stock page assembly
  and targeted overrides
- the supported embeddable fragment contract is:
  - `provider_login_buttons`
  - `mfa_factor_inventory_panel`
  - `mfa_enrollment_panel`
  - `mfa_challenge_form`
  - `mfa_sms_enrollment_panel`
  - `mfa_sms_challenge_form`
  - `mfa_recovery_codes_panel`
- stock full-page auth UI now renders through those coarse fragments so the
  default pages and embeddable surfaces stay aligned
- app-owned EOC pages can assemble those fragments through the EOC composition
  model plus `ALNAuthModuleRuntime`

## 9. Route and Rendering Contract

Mode matrix:

| Mode | HTML form routes | HTML templates | `/auth/api/...` | Provider callbacks | App-owned shell support |
| --- | --- | --- | --- | --- | --- |
| `headless` | disabled | none | active | active | n/a |
| `module-ui` | active | module-owned | active | active | yes |
| `generated-app-ui` | active | app-owned | active | active | yes |

Important constraint:

- JSON/session/provider backend behavior must not diverge by UI mode.
- HTML mode changes presentation ownership, not auth semantics.

The module also exposes MFA-specific headless contracts explicitly:

- `GET /auth/api/mfa` returns factor inventory, policy, preferred factor, and
  enabled-path discovery for React/native clients
- `GET /auth/api/mfa/totp` returns `flow`, `mfa`, and `session`
- `flow.state` is `enrollment` or `challenge`
- when SMS is enabled, `GET /auth/api/mfa/sms` plus
  `POST /auth/api/mfa/sms/{start,verify,resend,remove}` expose the same SMS
  factor-management contract the stock HTML UI uses
- `POST /auth/api/mfa/totp/verify` returns `flow.state = recovery_codes` on the
  first successful enrollment verify and `complete` on later step-up verifies
- `mfa.provisioning` is populated only during enrollment

## 10. CLI Workflow

Available first-class workflow:

```bash
./build/arlen module eject auth-ui --json
```

Current behavior:

- scaffold app-owned auth templates and partials
- scaffold any module-owned auth CSS/assets that the app should own in this mode
- scaffold fragment-first MFA templates and the local TOTP QR asset
- set or suggest:

```plist
authModule = {
  ui = {
    mode = "generated-app-ui";
    generatedPagePrefix = "auth";
  };
};
```

## 11. Example References

- `examples/auth_ui_modes/headless/README.md`
- `examples/auth_ui_modes/module_ui/README.md`
- `examples/auth_ui_modes/generated_app_ui/README.md`

- emit machine-readable output:
  - `workflow`
  - `status`
  - `created_files`
  - `updated_files`
  - `next_steps`

Recommended initial scaffold targets:

- `templates/auth/layouts/guest.html.eoc`
- `templates/auth/login.html.eoc`
- `templates/auth/register.html.eoc`
- `templates/auth/password/forgot.html.eoc`
- `templates/auth/password/reset.html.eoc`
- `templates/auth/mfa/manage.html.eoc`
- `templates/auth/mfa/sms.html.eoc`
- `templates/auth/mfa/totp.html.eoc`
- `templates/auth/mfa/totp_enrollment.html.eoc`
- `templates/auth/mfa/totp_recovery_codes.html.eoc`
- `templates/auth/fragments/...`
- `templates/auth/partials/...`

`arlen auth scaffold` can exist later as a higher-level alias if it materially
improves ergonomics, but the module-layer workflow should remain the primary
contract.

## 11. Example Deliverables

Official examples should cover:

1. server-rendered app using `module-ui` with `layouts/guest`
2. SPA/headless app using `/auth/api/...` only
3. app-owned `generated-app-ui` auth screens on the same backend contract

These examples should all preserve:

- same session model
- same MFA behavior
- same provider-login semantics
- same admin/auth identity integration

## 12. Proposed Delivery Tranches

## 12.1 Tranche A: UI Mode Contract

Deliver:

- `authModule.ui` config parsing
- route registration split for `headless`
- stable mode resolution at runtime

Acceptance:

- `headless` disables module-owned HTML routes
- `/auth/api/...` remains available
- provider callback flows remain coherent

## 12.2 Tranche B: `module-ui` App-Shell Integration

Deliver:

- configurable auth layout
- guest-shell rendering contract
- `ALNAuthModuleUIContextHook`

Acceptance:

- app can render stock auth page bodies inside `layouts/guest`
- app can inject shell context without replacing the page template

## 12.3 Tranche C: Partialized Auth UI Contract

Deliver:

- smaller stable partial identifiers
- documented override precedence
- targeted override examples

Acceptance:

- provider CTA row can be restyled without replacing the whole login page
- shared error/form shell can be overridden once for multiple pages

## 12.4 Tranche D: `generated-app-ui` Eject Workflow

Deliver:

- `arlen module eject auth-ui --json`
- generated app-owned templates/assets
- config flip guidance or automatic config update

Acceptance:

- freshly ejected auth UI boots without manual route/controller rewiring
- backend auth semantics remain unchanged

## 12.5 Tranche E: Docs, Examples, and Confidence

Deliver:

- updated `docs/AUTH_MODULE.md`
- updated `docs/CLI_REFERENCE.md`
- updated `docs/GETTING_STARTED.md`
- sample apps for `headless`, `module-ui`, and `generated-app-ui`
- unit/integration coverage for mode parity

Acceptance:

- all three modes are documented and example-backed
- login, password reset, MFA, and provider flows pass in all supported modes

## 13. Recommended Sequencing

This should be treated as an auth-module follow-on, not as a new core-auth
phase. The clean boundary remains:

- core Arlen owns auth/session/provider primitives
- the `auth` module owns auth product presentation modes

Recommended order:

1. land `headless` and `module-ui` first
2. partialize the auth UI contract
3. add `generated-app-ui` ejection after the page/partial contract is stable

That order avoids scaffolding a UI structure that would immediately change.

## 14. Expected Outcome

After this work, an app should be able to choose quickly between:

1. stock auth UI
2. stock auth flows inside an app-owned guest shell
3. fully app-owned auth UI on the same Arlen auth backend contract

That is the target integration bar for Arlen’s first-party auth product.

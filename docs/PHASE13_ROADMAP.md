# Arlen Phase 13 Roadmap

Status: Complete (13A-13I delivered on 2026-03-09)  
Last updated: 2026-03-09

Related docs:
- `docs/PHASE12_ROADMAP.md`
- `docs/PHASE3_ROADMAP.md`
- `docs/PHASE7_ROADMAP.md`
- `docs/PHASE2_PHASE3_ROADMAP.md`
- `docs/FEATURE_PARITY_MATRIX.md`
- `docs/ARLEN_CLI_SPEC.md`
- `docs/GETTING_STARTED.md`

## 1. Objective

Add a first-class Objective-C-native module system to Arlen, then prove it with the first two optional first-party modules:

- `auth`
- `admin-ui`

Phase 13 focuses on:

- an explicit module contract layered above the existing plugin system
- source-vendored, bundle-ready module packaging that fits GNUstep build tooling
- deterministic module config, migration, asset, and upgrade behavior
- a real authentication/account product module built on Phase 12 primitives
- a Django-inspired admin module with both EOC-rendered HTML and a headless JSON surface for SPA consumers

Phase 13 keeps Arlen core slim. Modules are the product layer; plugins remain the lower-level runtime extension seam.

## 1.1 Entry Context

Phase 13 starts from the current tree reality:

1. Arlen already has useful extension seams:
   - `ALNPlugin`
   - lifecycle hooks
   - mountable child applications
   - service adapter replacement
2. Those seams are not yet a full module system:
   - no module manifest
   - no dependency graph
   - no module-owned migration lifecycle
   - no resource bundle ownership/override contract
   - no install/upgrade CLI
3. Phase 12 deliberately keeps account-product UX out of core while adding the primitives an auth module should build on:
   - auth assurance / step-up
   - TOTP
   - recovery codes
   - WebAuthn
   - OIDC/provider login helpers
4. The feature-parity and roadmap docs already treat admin/backoffice and full account-management product surfaces as optional modules/products rather than core runtime behavior.
5. Objective-C/GNUstep gives Arlen strong building blocks for this layer:
   - protocols for capability contracts
   - runtime principal-class discovery
   - `NSBundle` for module-owned templates/assets/locales
   - property-list manifests

## 2. Design Principles

- Modules are higher-level than plugins:
  - a module may register plugins, routes, mounted apps, migrations, templates, assets, and service adapters
  - a plugin remains the small runtime extension unit
- Prefer explicit Objective-C contracts over hidden runtime magic:
  - protocol conformance checks
  - manifest-driven loading
  - principal-class entrypoints
  - deterministic dependency order
- Use Objective-C strengths deliberately:
  - `NSBundle` resource ownership and namespacing
  - protocol-based capability discovery
  - selector-based optional lifecycle hooks
  - property-list metadata that fits GNUstep conventions
- Avoid Objective-C footguns:
  - no swizzling
  - no category name collisions as the module extension mechanism
  - no required `+load` side effects
  - no hidden monkey-patching of app behavior
- Start source-vendored, but design for future bundle distribution:
  - Phase 13 installs modules into the application tree
  - manifests and resource resolution should not prevent later external bundle packaging
- Keep modules trusted-code only in v1.
- One domain contract should drive both HTML and JSON surfaces:
  - do not build a separate admin backend and admin HTML product
  - do not build separate auth logic for server-rendered vs SPA flows
- Prefer metadata plus explicit escape hatches over giant code generation:
  - apps should override templates, policies, and resource definitions without forking module internals

## 3. Scope Summary

1. Phase 13A: module contract and loader.
2. Phase 13B: packaging, resources, and override model.
3. Phase 13C: module CLI and install/upgrade lifecycle.
4. Phase 13D: config, migrations, compatibility, and diagnostics.
5. Phase 13E: auth module foundation.
6. Phase 13F: auth product flows and provider bridge.
7. Phase 13G: admin UI module foundation.
8. Phase 13H: Django-inspired admin resource system and headless API.
9. Phase 13I: hardening, docs, sample app, and confidence artifacts.

Execution order is intentional: with Phase 12 complete, Arlen should land the generic module substrate before the first-party modules depend on it.

## 4. Scope Guardrails

- Keep the module system additive:
  - existing plugin contracts remain supported
  - existing app workflows remain valid without modules
- Keep full account-management and admin products out of Arlen core:
  - they ship as optional first-party modules
- Keep Phase 13 single-tenant by default:
  - no org/tenant/invitation matrix as a v1 requirement
- Do not ship a bundled React/Vue/Svelte frontend inside `auth` or `admin-ui`.
- Do ship SPA-friendly backend contracts:
  - stable JSON endpoints
  - machine-readable metadata where appropriate
  - OpenAPI output for integration
- Admin must depend on an auth contract, not hard-code itself to one implementation detail of the first-party `auth` module.
- `auth` should own a sensible default schema and repositories, but advanced apps must have override seams.
- `admin-ui` should be metadata-driven first, but apps must be able to add custom screens/actions without forking the whole module.
- Preserve GNUstep build compatibility and deterministic local workflows.

## 5. Milestones

## 5.1 Phase 13A: Module Contract + Loader

Status: Complete (2026-03-09)

Deliverables:

- Introduce an explicit `ALNModule` contract with a stable lifecycle for:
  - manifest inspection
  - dependency declaration
  - application registration
  - startup/shutdown hooks
  - exported capabilities
- Add plist-backed module manifests with deterministic keys for:
  - module identifier
  - semantic version
  - principal class
  - dependency requirements
  - mounted app prefixes
  - resource bundle metadata
  - migration ownership
  - declared config schema/defaults
- Add a module loader/registry that:
  - validates manifest shape
  - instantiates principal classes
  - verifies protocol conformance
  - resolves dependency order deterministically
  - emits clear diagnostics for duplicate IDs, missing dependencies, version incompatibilities, and cyclic graphs
- Keep the plugin boundary explicit:
  - modules may register one or more `ALNPlugin` implementations internally
  - app/runtime code should not have to know whether a capability came from a module or a direct plugin
- Add base capability protocols for higher-level products, for example:
  - auth provider hooks
  - admin resource registration
  - module migration providers
  - module asset/template providers

Acceptance (required):

- `tests/unit/Phase13ATests.m`:
  - manifest parsing rejects malformed/ambiguous metadata
  - dependency ordering is deterministic
  - duplicate module identifiers fail closed
  - principal-class protocol validation is deterministic
- `tests/integration/DeploymentIntegrationTests.m`:
  - app boots with multiple vendored modules loaded in manifest order
  - cyclic dependency and missing-dependency failures emit clear diagnostics

## 5.2 Phase 13B: Packaging + Resources + Overrides

Status: Complete (2026-03-09)

Deliverables:

- Define a source-vendored module layout suitable for app-local installation, for example:
  - `modules/<ModuleID>/module.plist`
  - `modules/<ModuleID>/Sources/`
  - `modules/<ModuleID>/Resources/Templates/`
  - `modules/<ModuleID>/Resources/Public/`
  - `modules/<ModuleID>/Resources/Locales/`
  - `modules/<ModuleID>/Migrations/`
- Add build/runtime support so vendored modules still resolve resources via module-owned bundle metadata rather than pretending all templates/assets live in the app root.
- Add deterministic template and asset lookup precedence:
  1. app override
  2. installed module resource
  3. framework default where applicable
- Add namespaced module resource resolution for:
  - EOC templates
  - localized strings/catalogs
  - static assets
  - email templates
  - seed fixtures
- Ensure mounted/static paths contributed by modules stay deterministic and collision-checked.

Acceptance (required):

- `tests/unit/Phase13BTests.m`:
  - template/resource resolution prefers app overrides over module defaults
  - duplicate asset or template namespace collisions are diagnosed deterministically
- `tests/integration/DeploymentIntegrationTests.m`:
  - vendored module assets are packaged into releases
  - mounted/static resource paths remain stable across repeated builds

## 5.3 Phase 13C: Module CLI + Lifecycle

Status: Complete (2026-03-09)

Deliverables:

- Add first-class module commands to `arlen`, including:
  - `arlen module add <name>`
  - `arlen module remove <name>`
  - `arlen module list`
  - `arlen module doctor`
  - `arlen module migrate`
  - `arlen module assets`
  - `arlen module upgrade <name>`
- Keep install mode source-vendored first:
  - module files are copied or scaffolded into the application tree
  - install metadata is recorded in an app-owned plist/lock contract
- Add JSON output contracts and fix-it diagnostics matching the existing coding-agent DX direction.
- Make module lifecycle deterministic for automation:
  - install
  - validate
  - migrate
  - package assets
  - upgrade compatibility check

Acceptance (required):

- `tests/unit/Phase13CTests.m`:
  - CLI manifest/lock output is deterministic
  - invalid upgrade/install states emit machine-readable fix-it diagnostics
- `tests/integration/DeploymentIntegrationTests.m`:
  - new app installs `auth` and `admin-ui` without manual file editing
  - repeated installs/upgrades are idempotent where expected

## 5.4 Phase 13D: Config + Migrations + Compatibility

Status: Complete (2026-03-09)

Deliverables:

- Add module-owned config schema/default declarations with deterministic merge rules into app config.
- Add module migration ownership and ordering:
  - module migrations run with stable namespacing
  - install/upgrade checks know which module owns which migration tranche
- Add compatibility checks for:
  - Arlen framework version
  - module version ranges
  - required peer modules
  - missing secrets/config prerequisites
- Add module diagnostics hooks surfaced through `arlen module doctor`.
- Add module-aware docs/OpenAPI hooks where modules expose JSON surfaces.

Acceptance (required):

- `tests/unit/Phase13DTests.m`:
  - config merging is deterministic and conflict-checked
  - migration ordering is stable across installs/upgrades
  - compatibility checks fail closed with module-specific diagnostics
- `tests/integration/PostgresIntegrationTests.m`:
  - module migrations apply cleanly on a new app and on an upgrade path

## 5.5 Phase 13E: Auth Module Foundation

Status: Complete (2026-03-09)

Delivered:

- added first-party vendored `modules/auth/` with module manifest, namespaced migrations, EOC templates, and public assets
- shipped default auth/account schema covering users, local credentials, provider identities, verification/reset tokens, MFA enrollments, and WebAuthn credentials
- added hook-based app override seams for registration policy, password policy, user provisioning, notification customization, provider mapping, and post-login/session policy
- shipped HTML-first auth flows plus JSON session/bootstrap endpoints without bundling a frontend

Deliverables:

- Ship a first-party `auth` module that owns a default authentication/account data model and repository layer suitable for new apps.
- The default module schema should cover the common baseline needed for a real starter account product, including:
  - users
  - local credentials
  - provider identities
  - email verification state
  - password reset state
  - MFA enrollment records
  - WebAuthn credentials
- Build the module on top of existing and planned Phase 12 primitives rather than reimplementing them:
  - session assurance
  - TOTP
  - recovery codes
  - WebAuthn
  - OIDC/provider login helpers
- Add explicit app override seams for:
  - user provisioning/mapping
  - notification/mail customization
  - password policy
  - post-login redirect/session policy
  - route/path overrides
- Ship module-owned EOC templates for the default-first HTML path.
- Ship SPA-friendly auth/session JSON endpoints without bundling a JS frontend.

Acceptance (required):

- `tests/integration/HTTPIntegrationTests.m`:
  - fresh app installs `auth`, migrates, and completes local login/logout flows
  - HTML and JSON login/session flows establish the same session state semantics
- `tests/unit/Phase13ETests.m`:
  - app override hooks are invoked deterministically
  - module defaults remain stable when no overrides are provided

## 5.6 Phase 13F: Auth Product Flows + Provider Bridge

Status: Complete (2026-03-09)

Delivered:

- shipped first-party starter account flows for registration, login/logout, password reset/change, email verification, local TOTP enrollment/step-up, and stub provider login bridge
- normalized provider login onto the same local session and assurance model used by local auth, preserving AAL2 step-up requirements for sensitive routes
- added deterministic hook coverage for registration-policy and provider-mapping overrides in `tests/unit/Phase13FTests.m`
- added end-to-end auth/admin install-and-flow integration coverage in `tests/integration/Phase13AuthAdminIntegrationTests.m` gated by `ARLEN_PG_TEST_DSN`

Deliverables:

- Deliver first-party starter account flows in the module:
  - registration
  - login/logout
  - password change/reset
  - email verification
  - local MFA enrollment and step-up
  - provider login bridge
- Support both HTML-first and SPA-oriented consumption:
  - default EOC-rendered flows
  - JSON endpoints for session/bootstrap/provider callbacks
  - machine-readable validation errors and OpenAPI coverage
- Normalize provider login onto the same local assurance/session model:
  - provider login satisfies primary auth
  - AAL2 routes still require local step-up unless stronger assurance is established
- Add app hooks for controlled customization without full module forks:
  - allow/deny registration
  - map provider identities to users
  - customize verification/reset messaging
  - customize post-auth redirects and onboarding behavior

Acceptance (required):

- `tests/integration/HTTPIntegrationTests.m`:
  - registration, reset, and verification flows complete deterministically
  - provider-login stub flow establishes session state and composes with AAL2 routes
  - JSON and HTML flows share validation/policy behavior
- `tests/unit/Phase13FTests.m`:
  - provider mapping hooks and registration policy hooks are deterministic

## 5.7 Phase 13G: Admin UI Module Foundation

Status: Complete (2026-03-09)

Delivered:

- added first-party vendored `modules/admin-ui/` as a mounted child app with default `/admin` HTML surface and `/admin/api` JSON surface
- made `admin-ui` depend on the auth contract and first-party `auth` module defaults
- enforced shared policy defaults across admin HTML and JSON routes: authenticated session, `admin` role, and AAL2 step-up
- shipped default EOC admin layout, dashboard, user list/detail/edit screens, and public assets
- added deterministic route-contract coverage in `tests/unit/Phase13GTests.m`

Deliverables:

- Ship a first-party `admin-ui` module as a mounted child app under a stable default prefix such as `/admin`.
- Make `admin-ui` depend on the auth contract and default first-party `auth` module integration path.
- Protect the admin surface with explicit policy defaults:
  - authenticated session required
  - admin role/policy required
  - step-up/AAL2 support for sensitive actions
- Ship a complete default EOC-rendered admin experience:
  - layout and navigation
  - dashboard
  - resource list/detail/edit pages
  - login/session handoff
  - audit/event surfaces where applicable
- Ship a headless JSON surface under a stable namespace such as `/admin/api`.
- Do not ship a bundled React frontend; the JSON surface exists so external SPA clients can integrate cleanly.

Acceptance (required):

- `tests/integration/HTTPIntegrationTests.m`:
  - `admin-ui` mounts under the configured prefix and honors auth/policy defaults
  - HTML admin pages and JSON admin endpoints enforce the same access rules
- `tests/unit/Phase13GTests.m`:
  - default mount/config behavior is deterministic
  - role/step-up requirements are reflected in both HTML and JSON contracts

## 5.8 Phase 13H: Django-Inspired Admin Resource System + Headless API

Status: Complete (2026-03-09)

Delivered:

- refactored `admin-ui` around explicit `ALNAdminUIResource` and `ALNAdminUIResourceProvider` Objective-C protocols
- added a metadata-driven resource registry with deterministic registration order and duplicate-identifier rejection
- drove both `/admin/...` HTML screens and `/admin/api/...` JSON endpoints from the same resource metadata
- added machine-readable field/filter/action metadata, generic resource OpenAPI contracts, and per-resource policy hooks
- kept the built-in `users` resource as a first registered resource while allowing app-owned resources to register alongside it
- added `tests/unit/Phase13HTests.m` plus app-level `orders` resource coverage in `tests/integration/Phase13AuthAdminIntegrationTests.m`

Deliverables:

- Add a metadata-driven admin resource registry inspired by Django admin, but expressed through explicit Objective-C protocols/contracts rather than deep runtime magic.
- Resource definitions should support:
  - list/detail/create/update/delete
  - field metadata
  - search/filter/sort/pagination
  - bulk and row actions
  - per-resource policy hooks
  - custom pages/actions where metadata is insufficient
- Prefer repository/query-provider and policy protocols over assuming a full ORM layer.
- Drive both presentations from one resource definition system:
  - EOC HTML admin pages
  - JSON admin endpoints
- Expose machine-readable resource metadata for SPA clients:
  - field types
  - validation rules
  - available actions
  - filter/sort options
  - pagination contract
- Ensure module-generated OpenAPI/docs cover the JSON admin API.

Acceptance (required):

- `tests/integration/HTTPIntegrationTests.m`:
  - one registered resource is operable through both HTML and JSON admin surfaces
  - custom action and per-resource policy hooks are enforced consistently
- `tests/unit/Phase13HTests.m`:
  - metadata-to-HTML and metadata-to-JSON contracts stay in sync
  - resource registration order and field/action resolution are deterministic

## 5.9 Phase 13I: Hardening + Docs + Sample App + Confidence

Status: Complete (2026-03-09)

Delivered:

- added `examples/auth_admin_demo/` to demonstrate `auth` + `admin-ui` installation plus app-owned admin resource registration
- added `docs/MODULES.md`, `docs/AUTH_MODULE.md`, and `docs/ADMIN_UI_MODULE.md`
- added `make phase13-confidence` and artifact generation under `build/release_confidence/phase13/`
- updated docs indexes and quick-start references for the new sample app, module docs, and headless `/auth/api` surface

Deliverables:

- Add a first-party sample app demonstrating:
  - `auth` installation
  - `admin-ui` installation
  - app-level resource registration
  - HTML-first flows
  - SPA-oriented JSON integration against the same auth/admin contracts
- Add docs for:
  - module architecture and authoring
  - module install/upgrade workflow
  - resource/template override mechanics
  - auth module customization
  - admin resource registration
  - SPA integration without shipping a bundled frontend
- Add module-focused regression and confidence coverage:
  - install/upgrade fixtures
  - resource override fixtures
  - hostile-input coverage on auth/admin JSON surfaces
  - packaging and release validation for vendored module resources
- Add a Phase 13 confidence artifact location under `build/release_confidence/phase13/` if the gate surface warrants it.

Acceptance (required):

- `make test` remains green with Phase 13 coverage enabled
- docs/sample app are validated in CI and referenced from the docs index
- a fresh app can install both modules, run migrations, and boot without manual boilerplate edits

## 6. Phase-Level Acceptance

- `arlen module add auth` and `arlen module add admin-ui` work in a freshly scaffolded app.
- Vendored modules own templates/assets/migrations/config cleanly with deterministic app override precedence.
- `auth` ships one product with two access styles:
  - default HTML/EOC flows
  - SPA-friendly JSON/session/provider endpoints
- `admin-ui` ships one product with two access styles:
  - default HTML/EOC admin
  - headless JSON admin API under the same resource/policy model
- Admin HTML and JSON surfaces are generated from the same resource registry and policy hooks.
- The module system remains trusted-code-only and GNUstep-compatible.

## 7. Recommended Execution Sequence

1. Land the module contract/loader before any first-party module logic depends on it.
2. Add source-vendored packaging, resource bundles, and override precedence before shipping product modules.
3. Add module CLI, config, migration ownership, and compatibility checks before installable first-party modules are treated as complete.
4. Ship `auth` foundation first, then the full starter account flows and provider bridge.
6. Ship `admin-ui` only after the auth contract and policy hooks are stable.
7. Make the admin HTML and JSON surfaces share one resource metadata system from the start.
8. Finish with docs, sample app validation, and confidence gates rather than treating module ergonomics as a later polish pass.

## 8. Explicit Non-Goals

- Untrusted third-party module marketplaces, remote code installation, or sandbox claims.
- Swizzling, hidden monkey-patching, or category-collision-driven extension as the module architecture.
- Bundling React/Vue/Svelte apps inside first-party modules.
- Multi-tenant/org/billing/invitation products in Phase 13 v1.
- A full ORM requirement for admin/resource registration.
- Replacing the existing plugin system or forcing apps to adopt modules.

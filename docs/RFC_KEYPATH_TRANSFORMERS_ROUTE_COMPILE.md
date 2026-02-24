# RFC: Keypath Locals, Value Transformers, and Route Compile Validation

Status: Active (Phase 1 implemented; Phase 2 proposed)  
Last updated: 2026-02-24

Related docs:

- `V1_SPEC.md`
- `docs/PHASE1_SPEC.md`
- `docs/EOC_V1_ROADMAP.md`
- `docs/PHASE7E_TEMPLATE_PIPELINE_MATURITY.md`
- `docs/CORE_CONCEPTS.md`

## 1. Purpose

Define a concrete two-phase implementation plan that adds:

1. EOC keypath-aware locals, centralized value transformers, and unified field-error envelopes.
2. Startup route compilation/validation with fail-fast diagnostics.

This RFC is additive. Existing controller, template, and schema behavior remains valid unless strict mode is explicitly enabled.

## 2. Why This Is Worth Doing Now

- Arlen already has deterministic EOC transpilation/runtime and contract coercion; this work tightens those existing paths instead of introducing a new subsystem.
- Current request coercion duplicates conversion logic in `ALNSchemaContract`; a shared transformer pipeline reduces drift.
- Current action/guard signature checks happen per request in `ALNApplication` dispatch; startup compilation moves failures to boot time and lowers runtime overhead.

## 3. Non-Goals for This RFC

- No untrusted template execution model changes.
- No full LiveView-style diff engine.
- No ORM-coupled data model layer.
- No changes to `propane` process-manager scope beyond existing propane accessories.

## 4. Phase 1: Keypath Locals + Transformer Registry + Error Envelope

Status: implemented (2026-02-24)

## 4.1 Scope

1. EOC keypath locals:
   - Extend sigil local grammar from `$identifier` to `$identifier(.identifier)*`.
   - Examples:
     - `<%= $user.name %>`
     - `<%= $order.customer.email %>`
   - Keep current `$identifier` behavior unchanged.
2. Runtime keypath lookup contract:
   - Add keypath-aware runtime helper for generated templates.
   - Preserve strict-locals semantics and template line/column diagnostics.
3. Centralized value transformer registry:
   - Add deterministic transformer registration and lookup.
   - Use transformer names in request schema descriptors.
   - Keep current basic coercion behavior as fallback for compatibility.
4. Unified `NSError`-driven field-error envelope:
   - Standardize API validation/internal template execution error payload shape.
   - Keep keypath field names as first-class identifiers in error details.

## 4.2 Proposed Contracts

Template/runtime contracts:

- New generated helper call form for keypaths:
  - `ALNEOCLocalPath(ctx, @"user.name", @"templates/example.html.eoc", line, column, error)`
- New runtime error metadata keys (additive):
  - `key_path`
  - `segment`

Schema contract additions (additive):

- Per-field descriptor keys:
  - `transformer` (string, optional)
  - `transformers` (array of string, optional; applied in-order)
- Unknown transformer names are deterministic errors (`invalid_transformer`).

Unified envelope contract:

- Error payload shape (JSON responses):
  - `error.code`
  - `error.message`
  - `error.request_id`
  - `error.correlation_id`
  - `details[]` with `field`, `code`, `message`, and optional metadata
- `field` accepts dotted keypaths (for example `user.email`).

## 4.3 Implementation Plan

1. EOC keypath parsing and rewrite:
   - Update sigil rewrite in `src/Arlen/MVC/Template/ALNEOCTranspiler.m`.
   - Keep parser state-machine approach and deterministic diagnostics.
2. Runtime keypath resolver:
   - Add helper(s) in `src/Arlen/MVC/Template/ALNEOCRuntime.h/.m`.
   - Root lookup stays compatible with existing local lookup rules.
3. Transformer registry:
   - Add `src/Arlen/Core/ALNValueTransformers.h/.m` with thread-safe name registry.
   - Provide initial built-ins (string trim/case, integer/number/boolean, ISO-8601 date parse).
4. Schema integration:
   - Apply registered transformer pipeline in `src/Arlen/Core/ALNSchemaContract.m` before type validation.
5. Error envelope unification:
   - Normalize shared JSON error shape in `ALNController`/`ALNApplication` error rendering paths.

## 4.4 Testing Plan

Unit tests:

- `tests/unit/TranspilerTests.m`
  - keypath sigil rewrite success/failure matrix.
- `tests/unit/EOCRuntimeTests.m` (or existing runtime test target)
  - strict/non-strict keypath lookup diagnostics.
- `tests/unit/SchemaContractTests.m`
  - transformer lookup, execution, and deterministic failure codes.

Integration tests:

- `tests/integration/HTTPIntegrationTests.m`
  - template render with keypath locals.
  - validation/template error envelope with keypath field details.

Fixtures:

- Add template fixtures under `tests/fixtures/templates/` for keypath-locals scenarios.

## 4.5 Phase 1 Acceptance Criteria

- `$identifier(.identifier)*` renders correctly in escaped/raw expression tags.
- Strict locals mode reports missing root/segment with template path + line + column.
- Request schema descriptors can apply named transformer(s) deterministically.
- Error responses for validation/template failures use one stable envelope with keypath-ready `field` values.
- Existing `$identifier` templates and existing schema contracts remain backward compatible.

## 5. Phase 2: Startup Route Compilation and Validation

Status: planned

## 5.1 Scope

1. Compile and validate routes at app startup (`startWithError:` path), not first request.
2. Validate controller action and guard signatures once, fail fast on invalid routes.
3. Validate route-attached request/response schemas and transformer references for readiness.
4. Cache compiled invocation metadata to avoid repeated per-request signature checks.

## 5.2 Proposed Contracts

Startup compile pass:

- Add route compile routine in `ALNApplication` startup.
- Diagnostics include:
  - route name/path/method
  - controller class
  - action or guard name
  - deterministic error code and message

Validation rules:

1. Controller class must exist and be instantiable.
2. Action signature must accept exactly one `ALNContext *` argument.
3. Guard signature (when configured) must accept exactly one `ALNContext *` argument.
4. Route schema descriptors must be structurally valid.
5. Referenced transformer names must exist in registry.

Config controls (additive):

- `routing.compileOnStart` (default `YES`)
- `routing.routeCompileWarningsAsErrors` (default `NO`)

## 5.3 Implementation Plan

1. Add compile routine and diagnostics collector in `src/Arlen/Core/ALNApplication.m`.
2. Call compile routine during startup before marking app ready.
3. Persist compiled method-signature metadata on route objects or an internal compiled-route table.
4. Update runtime dispatch path to use compiled metadata and skip repeated signature validation.

## 5.4 Testing Plan

Unit tests:

- `tests/unit/ApplicationTests.m`
  - invalid action signature fails startup deterministically.
  - invalid guard signature fails startup deterministically.
  - missing transformer referenced by route schema fails startup.

Integration tests:

- `tests/integration/DeploymentIntegrationTests.m`
  - startup failure payload is deterministic and actionable in dev/deploy flows.

## 5.5 Phase 2 Acceptance Criteria

- Route/signature/schema readiness errors surface at startup with deterministic diagnostics.
- Successful startup guarantees dispatch-ready route invocation contracts.
- Per-request dispatch path no longer performs first-time signature validation logic.
- Existing valid route registrations continue to work without app-level code changes.

## 6. Execution Sequence

1. Deliver Phase 1 first (template + schema + envelope contract).
2. Land Phase 2 after Phase 1 test and docs baselines are stable.
3. Keep both phases behind additive config defaults where needed to preserve smooth upgrades.

## 7. Documentation and Change Management Requirements

When implementation begins, update in the same change set:

1. `V1_SPEC.md` (sigil grammar and runtime helper contract for keypaths).
2. `docs/CORE_CONCEPTS.md` (request/schema/template behavior updates).
3. `docs/CLI_REFERENCE.md` and `docs/GETTING_STARTED.md` if new config/CLI workflows are introduced.
4. `README.md` and `docs/README.md` links if new user-facing guide pages are added.

## 8. Parked for Future Consideration (Explicitly Out of Scope Here)

These are intentionally deferred and not part of Phase 1 or Phase 2 delivery in this RFC:

1. KVO-driven incremental server rendering and fragment patch streaming as a core default.
2. NSUndoManager-style command/audit/undo architecture in core runtime.
3. NSPredicate/NSSortDescriptor as the primary cross-store query surface.

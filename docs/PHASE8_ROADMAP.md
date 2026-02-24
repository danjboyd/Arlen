# Arlen Phase 8 Roadmap

Status: Active (Phase 8A complete; Phase 8B planned)  
Last updated: 2026-02-24

Related docs:
- `docs/PHASE7_ROADMAP.md`
- `docs/PHASE2_PHASE3_ROADMAP.md`
- `docs/RFC_KEYPATH_TRANSFORMERS_ROUTE_COMPILE.md`
- `docs/CORE_CONCEPTS.md`
- `V1_SPEC.md`

## 1. Objective

Deliver a focused post-Phase-7 roadmap that improves default developer ergonomics and runtime determinism for template/model/controller workflows by:

- adding keypath-aware EOC locals and centralized value transformers
- unifying field-level error envelopes across validation/template/runtime failures
- moving route/action/guard readiness checks to startup-time compile validation

Phase 8 remains additive and compatibility-first:

- existing `$identifier` EOC locals continue to work
- existing route/controller contracts continue to work unless startup validation detects deterministic signature/schema errors
- no change to trusted-template assumptions in v1

## 2. Scope Summary

1. Phase 8A: keypath locals, transformer registry, and unified error envelope.
2. Phase 8B: startup route compilation/validation and cached invocation metadata.

## 3. Milestones

## 3.1 Phase 8A: Keypath Locals + Transformers + Error Envelope

Status: Complete (2026-02-24)

Deliverables:

- Extend EOC sigil local syntax to support keypaths:
  - `$identifier(.identifier)*`
  - examples: `$user.email`, `$order.customer.name`
- Add runtime keypath local resolver with strict-local diagnostics that preserve template path/line/column context.
- Add centralized named value-transformer registry for schema coercion and template/runtime conversion reuse.
- Add schema-descriptor transformer hooks:
  - `transformer` (single)
  - `transformers` (ordered array)
- Unify error envelope shape for field-level failures with keypath-ready `field` semantics.

Acceptance (required):

- Keypath sigil locals compile and render deterministically in escaped/raw expression tags.
- Strict locals mode emits deterministic missing-root/missing-segment diagnostics.
- Unknown transformer names fail deterministically (`invalid_transformer` contract).
- Validation/template/render failure responses use one stable error envelope with field keypaths.

Implementation notes (completed):

- EOC sigil rewrite now supports `$identifier(.identifier)*` and emits `ALNEOCLocalPath(...)` for dotted forms.
- Runtime lookup includes keypath-aware strict diagnostics with additive `key_path` and `segment` metadata.
- Added centralized transformer registry (`ALNValueTransformers`) and schema hooks (`transformer` / `transformers`).
- Structured JSON error payloads normalize detail entries to `details[]` with `field`, `code`, `message`, optional `meta`.
- Coverage added in unit fixtures/tests (`TranspilerTests`, `RuntimeTests`, `SchemaContractTests`).

## 3.2 Phase 8B: Startup Route Compilation + Validation

Status: Planned

Deliverables:

- Add startup route compile pass in `ALNApplication` startup path.
- Validate action/guard signatures once at boot instead of first-request dispatch.
- Validate route schema readiness and transformer references at startup.
- Persist compiled invocation metadata so dispatch path avoids repeated signature inspection.
- Add additive config controls:
  - `routing.compileOnStart` (default `YES`)
  - `routing.routeCompileWarningsAsErrors` (default `NO`)

Acceptance (required):

- Invalid action/guard signatures fail startup with deterministic route/controller diagnostics.
- Missing transformer references in route schemas fail startup deterministically.
- Successful startup implies dispatch-ready route invocation contracts.
- Runtime dispatch no longer depends on first-hit signature validation paths.

## 4. Testing and Rollout Strategy

- Unit coverage:
  - EOC transpiler sigil keypath rewrite matrix
  - runtime keypath lookup strict/non-strict behavior
  - transformer registry and schema coercion failure contracts
  - startup route-compile diagnostics and signature validation
- Integration coverage:
  - keypath template rendering through full HTTP route path
  - deterministic startup failure behavior in deploy/dev workflow tests
- Fixture coverage:
  - new template fixtures under `tests/fixtures/templates/`
  - new contract fixtures for phase 8 roadmap acceptance contracts

Rollout policy:

1. Deliver 8A first and stabilize diagnostics/fixtures.
2. Deliver 8B once 8A contracts are stable and documented.

## 5. Explicitly Deferred (Future Consideration, Not Phase 8 Scope)

The following ideas remain parked for possible future phases and are not part of 8A/8B delivery:

1. KVO-driven incremental server-render patch streaming as a core default.
2. NSUndoManager-style command/audit/undo architecture in core runtime.
3. NSPredicate/NSSortDescriptor as the primary cross-store query surface.

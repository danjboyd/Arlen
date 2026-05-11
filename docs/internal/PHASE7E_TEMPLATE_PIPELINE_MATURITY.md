# Phase 7E Template Pipeline Maturity

Phase 7E defines deterministic compile-time diagnostics and stronger regression coverage for EOC template parsing and render-path behavior.

This document captures the delivered 7E template-pipeline contract set. The
initial slice landed on 2026-02-23, and later lint/watch-path work closed the
remaining acceptance items for the current first-party surface.

## 1. Scope (Initial Slice)

- Deterministic template lint diagnostics for unguarded include calls.
- Expanded fixture matrix for multiline, nested-control-flow, and malformed-tag error shapes.
- Integration coverage for include/render-path behavior and `eocc` lint output contracts.
- Troubleshooting workflow documentation for transpile diagnostics.

## 2. Lint Diagnostics Contract

`ALNEOCTranspiler` now exposes lint diagnostics via:

- `lintDiagnosticsForTemplateString:logicalPath:error:`

Diagnostic payload keys:

- `level`
- `code`
- `message`
- `path`
- `line`
- `column`

Implemented lint rules:

- `unguarded_include`
  - emitted when template code calls `ALNEOCInclude(...)` without guarding the return value.
  - recommended pattern:
    - `if (!ALNEOCInclude(out, ctx, @"partials/_nav.html.eoc", error)) { return nil; }`
- `slot_without_layout`
  - emitted when a template fills a named slot without an active layout/yield contract.
- `unused_slot_fill`
  - emitted when a template fills a slot that no active layout consumes.

`eocc` now emits deterministic lint warnings during transpilation:

- `eocc: warning path=<logical_path> line=<line> column=<column> code=<code> message=<message>`

Lint diagnostics are warnings only in this slice and do not fail transpilation.

## 3. Fixture Matrix Expansion

Added fixture scenarios:

- multiline tags/expressions:
  - `tests/fixtures/templates/multiline_tags.html.eoc`
- multiline malformed expression:
  - `tests/fixtures/templates/malformed_empty_expression_multiline.html.eoc`
- multiline malformed sigil:
  - `tests/fixtures/templates/malformed_invalid_sigil_multiline.html.eoc`
- nested control-flow with sigils:
  - `tests/fixtures/templates/nested_control_flow.html.eoc`
- lint unguarded include:
  - `tests/fixtures/templates/lint_unguarded_include.html.eoc`
- lint guarded include:
  - `tests/fixtures/templates/lint_guarded_include.html.eoc`

## 4. Include/Render Path Hardening

The default app template now uses guarded include handling:

- `templates/index.html.eoc`:
  - `if (!ALNEOCInclude(...)) { return nil; }`

Integration coverage now validates:

- root render includes expected partial output
- `eocc` emits deterministic lint warning for unguarded include and no warning for guarded include
- watch-mode template-failure recovery paths rebuild and return to healthy output

## 5. Troubleshooting Workflow

See `docs/TEMPLATE_TROUBLESHOOTING.md` for command-driven troubleshooting loops and deterministic diagnostic interpretation.

## 6. Executable Verification

Machine-readable contract fixture:

- `tests/fixtures/phase7e/template_pipeline_contracts.json`

Verification coverage:

- `tests/unit/TemplateCodegenTests.m`
  - multiline + nested fixture transpile coverage
- `tests/unit/TemplateParserTests.m`
  - deterministic malformed-tag location diagnostics
- `tests/unit/TemplateSecurityTests.m`
  - deterministic lint diagnostics for guarded/unguarded include patterns
- `tests/integration/HTTPIntegrationTests.m`
  - root endpoint render includes partial output contract
- `tests/integration/DeploymentIntegrationTests.m`
  - `eocc` lint output shape/behavior contract
- `tests/unit/Phase7ETests.m`
  - contract fixture schema/reference integrity checks

## 7. Closeout Notes

The current tree closes the main 7E follow-on bar through additional lint rules,
watch-mode template failure/recovery coverage, and updated troubleshooting docs.
Further lint-rule expansion remains possible, but it is no longer tracked as an
active Phase 7 blocker.

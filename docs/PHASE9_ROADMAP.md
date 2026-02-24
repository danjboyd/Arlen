# Arlen Phase 9 Roadmap

Status: Active (Phase 9A complete; Phase 9B complete; Phase 9C complete; Phase 9D complete; Phase 9E initial slice complete)  
Last updated: 2026-02-24

Related docs:
- `docs/PHASE8_ROADMAP.md`
- `docs/PHASE2_PHASE3_ROADMAP.md`
- `docs/DOCUMENTATION_POLICY.md`
- `docs/API_REFERENCE.md`

## 1. Objective

Deliver a world-class documentation system for Arlen that is:

- API-complete for public umbrella headers (`Arlen.h`, `ArlenData.h`)
- migration-friendly for common framework entrants
- practical for first-time users and experienced teams
- publishable as browser HTML for both website hosting and local checkout use

## 2. Scope Summary

1. Phase 9A: docs platform and HTML publishing pipeline.
2. Phase 9B: API reference generation with per-method purpose/usage guidance.
3. Phase 9C: multi-track getting-started guides for common onboarding paths.
4. Phase 9D: "Arlen for X" migration guides for common incoming ecosystems.
5. Phase 9E: docs quality gates, coverage rules, and maintenance contracts.

## 3. Milestones

## 3.1 Phase 9A: Docs Platform + HTML Publishing

Status: Complete (2026-02-24)

Deliverables:

- Expand docs HTML generation to include nested docs directories.
- Generate API reference docs as part of the docs build pipeline.
- Provide local docs serving entrypoint (`make docs-serve`).
- Keep output deterministic under `build/docs/`.

Acceptance (required):

- `make docs-html` regenerates complete docs portal and API reference HTML.
- `build/docs/index.html` resolves to docs index and cross-links correctly.
- `make docs-serve` serves docs locally from repository checkout.

## 3.2 Phase 9B: API Reference Completeness

Status: Complete (2026-02-24)

Deliverables:

- Generate API reference from public umbrella exports:
  - `src/Arlen/Arlen.h`
  - `src/ArlenData/ArlenData.h`
- Emit symbol pages under `docs/api/`.
- Document every public method with:
  - selector/signature
  - purpose
  - usage guidance
- Include symbol-level summaries and practical usage snippets for high-value APIs.

Acceptance (required):

- API index (`docs/API_REFERENCE.md`) enumerates exported symbols/method totals.
- Each exported symbol has a generated page in `docs/api/`.
- Generated docs are reproducible via `python3 tools/docs/generate_api_reference.py`.

## 3.3 Phase 9C: Getting-Started Track Suite

Status: Complete (2026-02-24)

Deliverables:

- Add track-specific onboarding guides:
  - quickstart path
  - API-first path
  - HTML-first path
  - data-layer-first path
- Cross-link track suite from primary docs index and root README.

Acceptance (required):

- New user can choose a path and reach a running app without ambiguity.
- Track docs include concrete commands and expected outcomes.

## 3.4 Phase 9D: Arlen-for-X Migration Suite

Status: Complete (2026-02-24)

Deliverables:

- Add migration guides for:
  - Rails
  - Django
  - Laravel
  - FastAPI
  - Express/NestJS
  - Mojolicious
- Include concept mapping, request lifecycle translation, and incremental cutover plans.

Acceptance (required):

- Each guide includes at least:
  - mental-model mapping table
  - app structure mapping
  - request/response/auth/data migration notes
  - phased migration checklist

## 3.5 Phase 9E: Documentation Quality Gates

Status: Initial slice complete (2026-02-24)

Deliverables:

- Update documentation policy with API-reference maintenance requirements.
- Define docs quality checks for generated API docs + HTML build validity.
- Wire docs process expectations into roadmap/index documentation.

Acceptance (required):

- `docs/DOCUMENTATION_POLICY.md` includes API docs and HTML quality checks.
- Docs contributors have explicit regeneration commands and review checklist updates.

## 4. Rollout and Maintenance

- Keep API reference generation deterministic and source-of-truth driven from headers.
- Treat public header changes without API doc regeneration as incomplete work.
- Keep migration guides additive and update them as compatibility helpers expand.

## 5. Explicitly Deferred (Future Consideration, Not Phase 9 Scope)

1. Hosted docs search indexing backend beyond static HTML generation.
2. Multi-version docs hosting automation for release branches/tags.
3. Interactive in-browser API playground tied directly to generated reference pages.

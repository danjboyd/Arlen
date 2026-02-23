# Phase 7F Frontend Integration Starters

Phase 7F defines deterministic frontend starter workflows that keep Arlen's core runtime slim while giving users practical static-asset + API wiring paths.

This document captures the initial 7F implementation slice completed on 2026-02-23.

## 1. Scope (Initial Slice)

- CLI starter generation via `arlen generate frontend`.
- Two official starter presets:
  - `vanilla-spa`
  - `progressive-mpa`
- Reference wiring for static assets, API consumption, and release packaging compatibility.
- Reproducibility and deploy-packaging integration validation.

## 2. Starter Generation Contract

Generate starters from an app root:

```bash
arlen generate frontend Dashboard --preset vanilla-spa
arlen generate frontend Portal --preset progressive-mpa
```

Default preset when omitted:

- `vanilla-spa`

Generated path contract:

- `public/frontend/<slug>/index.html`
- `public/frontend/<slug>/app.js`
- `public/frontend/<slug>/styles.css`
- `public/frontend/<slug>/starter_manifest.json`
- `public/frontend/<slug>/README.md`

Slug behavior:

- derived deterministically from `<Name>` using route-safe normalization.

## 3. API Consumption Wiring

Both starters include deterministic API examples against built-in Arlen endpoints:

- `/healthz?format=json`
- `/metrics`

This keeps starter flows dependency-light and runnable without extra controller setup.

## 4. Deployment Packaging Wiring

Frontend starter assets are under `public/` and therefore included automatically by release packaging scripts:

- `tools/deploy/build_release.sh`

Release artifact path includes starter payload under:

- `<release>/app/public/frontend/<slug>/...`

## 5. Versioning and Upgrade Guidance

Each starter ships a manifest:

- `starter_manifest.json`

Current starter version:

- `phase7f-starter-v1`

Recommended upgrade workflow:

1. Compare your generated starter folder with latest framework starter template output.
2. Review manifest version changes before merging updates.
3. Re-run integration validation after upgrade (`make test-integration`).

## 6. Executable Verification

Machine-readable contract fixture:

- `tests/fixtures/phase7f/frontend_starter_contracts.json`

Verification coverage:

- `tests/integration/DeploymentIntegrationTests.m`
  - `testArlenGenerateFrontendStartersAreDeterministicAndDeployPackaged`
- `tests/unit/Phase7FTests.m`
  - `testFrontendStarterContractFixtureSchemaAndTestCoverage`

## 7. Remaining 7F Follow-On

The broader 7F roadmap still includes:

- framework-specific starter variants (e.g., Vite/React/Vue/Svelte integration references)
- richer CI smoke checks that build/bundle starter variants end-to-end
- starter migration utilities for cross-version upgrade automation

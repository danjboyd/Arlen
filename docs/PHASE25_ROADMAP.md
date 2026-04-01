# Arlen Phase 25 Roadmap

Status: Complete (`25A-25G` delivered on 2026-04-01)
Last updated: 2026-04-01

Related docs:

- `docs/STATUS.md`
- `docs/LIVE_UI.md`
- `docs/REALTIME_COMPOSITION.md`
- `docs/FEATURE_PARITY_MATRIX.md`
- `docs/DOCUMENTATION_POLICY.md`

## 0. Progress Checkpoint (2026-04-01)

Phase 25 is complete.

Delivered in-tree:

- `25A`: live response protocol, `ALNLive`, built-in `/arlen/live.js`, and
  explicit replace/update/append/prepend/remove/navigate/dispatch operations
- `25B`: live request metadata (`target`, `swap`, `component`, `event`,
  `source`) carried from authoring markup into controller helpers
- `25C`: live link/form interception, request-driven fragment rerendering,
  live navigation, and focused `phase25-live-tests`
- `25D`: keyed collection helpers through `upsert` / `discard`, keyed
  controller helpers, and feed examples
- `25E`: region fetching via `data-arlen-live-src`, polling/lazy/deferred
  hydration, and upload-progress-aware live forms
- `25F`: payload/meta caps, response hardening, richer reconnect/backpressure
  behavior, and broader negative-path coverage
- `25G`: `/tech-demo/live`, repo-native `phase25-confidence`, and docs/API
  closeout

## 1. Objective

Add a server-driven live UI layer to Arlen that stays aligned with the current
compiled, EOC-first architecture.

This phase does not aim to deliver a full LiveView-style diff engine. The
target remains an explicit fragment-first model:

- controller returns HTML fragments or live operations
- browser runtime applies targeted DOM updates
- websocket-backed pubsub can push the same live operation payloads
- forms, links, and regions remain ordinary HTML authoring surfaces

## 2. Design Principles

- Keep the transport explicit and inspectable.
- Reuse EOC partials/fragments rather than introducing a second view system.
- Preserve graceful fallback to normal HTML navigation.
- Prefer request metadata and explicit targets over hidden runtime magic.
- Keep the client runtime small and framework-owned.
- Do not claim a full-state diff engine before the architecture exists.

## 3. Scope Summary

1. `25A`: live fragment protocol and browser runtime.
2. `25B`: live request metadata and request-driven fragment targeting.
3. `25C`: live forms, live links, and live navigation baseline.
4. `25D`: keyed stream helpers and collection ergonomics.
5. `25E`: defer/poll/lazy/async UX and uploads.
6. `25F`: hardening, backpressure, and failure recovery.
7. `25G`: docs, examples, confidence artifacts, and closeout.

## 4. Delivered Subphases

## 4.1 Phase 25A: Live Fragment Protocol + Browser Runtime (Delivered 2026-04-01)

Delivered:

- `ALNLive` protocol helpers and payload validation
- public content-type/protocol constants and operation builders
- built-in `/arlen/live.js` runtime asset from `ALNApplication`
- browser application of `replace`, `update`, `append`, `prepend`, `remove`,
  `navigate`, and `dispatch`

## 4.2 Phase 25B: Live Actions + Component Identity (Delivered 2026-04-01)

Delivered:

- request metadata extraction for `target`, `swap`, `component`, `event`, and
  `source`
- `data-arlen-live-*` authoring attributes in the runtime
- `ALNContext liveMetadata` and `ALNController liveMetadata`
- request-driven defaults for `renderLiveTemplate:target:action:context:error:`

## 4.3 Phase 25C: Live Forms + Validation + Navigation Baseline (Delivered 2026-04-01)

Delivered:

- delegated interception for live forms and links
- submit-button preservation in live form payload assembly
- busy-state toggling for live forms
- `renderLiveNavigateTo:replace:` controller helper
- graceful fallback to normal navigation/redirect behavior on non-live or
  failed live responses

## 4.4 Phase 25D: Keyed Streams + Collection Helpers (Delivered 2026-04-01)

Delivered:

- keyed `upsert` / `discard` protocol operations
- keyed selector derivation helpers
- `renderLiveKeyedTemplate:` and `publishLiveKeyedTemplate:` controller APIs
- tech-demo keyed feed examples and focused unit coverage

## 4.5 Phase 25E: Lazy/Deferred/Async UX (Delivered 2026-04-01)

Delivered:

- `data-arlen-live-src` region fetching
- `data-arlen-live-poll`, `data-arlen-live-lazy`, and
  `data-arlen-live-defer` runtime behavior
- upload-progress-aware live form handling through XHR

## 4.6 Phase 25F: Hardening and Recovery (Delivered 2026-04-01)

Delivered:

- payload/meta caps for live responses
- `Cache-Control: no-store` and live response variation headers
- richer runtime reconnect, backpressure, and auth-expiry handling
- expanded live protocol/controller regression coverage

## 4.7 Phase 25G: Examples and Closeout (Delivered 2026-04-01)

Delivered:

- `/tech-demo/live` example page
- `phase25-confidence` artifact lane
- roadmap, status, README, and live guide closeout

## 5. Verification

```bash
source tools/source_gnustep_env.sh
make build-tests
make phase25-live-tests
make phase25-confidence
make test-unit
make docs-api
bash tools/ci/run_docs_quality.sh
```

`phase25-live-tests` is the focused XCTest bundle for the live protocol,
controller helpers, and built-in runtime route. `phase25-confidence` boots the
tech demo server and records smoke artifacts for the shipped live page under
`build/release_confidence/phase25/`.

# Arlen Phase 25 Roadmap

Status: In Progress (`25A-25C` delivered on 2026-04-01)
Last updated: 2026-04-01

Related docs:

- `docs/STATUS.md`
- `docs/LIVE_UI.md`
- `docs/REALTIME_COMPOSITION.md`
- `docs/FEATURE_PARITY_MATRIX.md`
- `docs/DOCUMENTATION_POLICY.md`

## 0. Progress Checkpoint (2026-04-01)

Phase 25 is open and the initial fragment-first slice is delivered.

Delivered in-tree:

- `25A`: live response protocol, `ALNLive`, built-in `/arlen/live.js`, and
  explicit replace/update/append/prepend/remove/navigate/dispatch operations
- `25B`: lightweight live request metadata (`target`, `swap`, `component`,
  `event`, `source`) carried from authoring markup into controller helpers
- `25C`: live link/form interception, request-driven fragment rerendering,
  live navigation, and focused `phase25-live-tests`

Still open:

- keyed collection stream helpers
- richer stateful component semantics
- lazy/deferred regions, uploads, reconnect nuance, and broader robustness
- overload/security/backpressure hardening beyond the baseline validation

## 1. Objective

Add a server-driven live UI layer to Arlen that stays aligned with the current
compiled, EOC-first architecture.

This phase does not aim to deliver a full LiveView-style diff engine. The
initial target is a smaller, explicit, fragment-first model:

- controller returns HTML fragments or live operations
- browser runtime applies targeted DOM updates
- websocket-backed pubsub can push the same live operation payloads
- forms and links remain ordinary HTML authoring surfaces

## 2. Design Principles

- Keep the transport explicit and inspectable.
- Reuse EOC partials/fragments rather than introducing a second view system.
- Preserve graceful fallback to normal HTML navigation.
- Prefer request metadata and explicit targets over hidden runtime magic.
- Keep the initial client runtime small and framework-owned.
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

Acceptance achieved:

- controllers can return live JSON payloads without hand-building response
  envelopes
- runtime asset ships from the framework with deterministic route behavior
- invalid live operations fail closed during serialization

## 4.2 Phase 25B: Live Actions + Component Identity (Delivered 2026-04-01, Lightweight Slice)

Delivered:

- request metadata extraction for:
  - `target`
  - `swap`
  - `component`
  - `event`
  - `source`
- `data-arlen-live-*` authoring attributes in the runtime
- `ALNContext liveMetadata` and `ALNController liveMetadata`
- request-driven defaults for `renderLiveTemplate:target:action:context:error:`

Acceptance achieved:

- templates can own the target selector and swap strategy
- controllers can inspect the originating component/event metadata
- one route can serve both full HTML and live fragment updates cleanly

Guardrail:

- this is lightweight identity metadata, not a stateful component runtime

## 4.3 Phase 25C: Live Forms + Validation + Navigation Baseline (Delivered 2026-04-01)

Delivered:

- delegated interception for live forms and links
- submit-button preservation in live form payload assembly
- busy-state toggling for live forms
- `renderLiveNavigateTo:replace:` controller helper
- graceful fallback to normal navigation/redirect behavior on non-live or
  failed live responses

Acceptance achieved:

- apps can build interactive server-rendered filters, pagers, and simple
  validation loops without bespoke frontend code
- ordinary full-page HTML rendering remains the default fallback

## 5. Remaining Subphases

## 5.1 Phase 25D: Keyed Streams + Collection Helpers

Target:

- helpers for keyed list/table/feed updates
- clearer append/prepend/remove ergonomics for realtime collections

## 5.2 Phase 25E: Lazy/Deferred/Async UX

Target:

- deferred regions
- polling helpers
- richer reconnect and loading-state handling
- upload ergonomics

## 5.3 Phase 25F: Hardening and Recovery

Target:

- payload and request caps
- reconnect/backpressure behavior
- auth/session expiry handling
- broader negative-path coverage

## 5.4 Phase 25G: Examples and Closeout

Target:

- checked-in live example app slices
- docs/API/status finalization
- confidence artifacts and broader acceptance lanes

## 6. Verification

Current focused verification:

```bash
source tools/source_gnustep_env.sh
make build-tests
make phase25-live-tests
make test-unit
make docs-api
bash tools/ci/run_docs_quality.sh
```

`phase25-live-tests` is the phase-native XCTest bundle for the live protocol,
controller, and runtime route coverage.

# Arlen Phase 25 Roadmap

Status: Baseline complete (`25A-25G` delivered on 2026-04-01); live testing hardening through `25J` delivered on 2026-04-01; `25K-25L` remain planned
Last updated: 2026-04-01

Related docs:

- `docs/STATUS.md`
- `docs/LIVE_UI.md`
- `docs/REALTIME_COMPOSITION.md`
- `docs/FEATURE_PARITY_MATRIX.md`
- `docs/DOCUMENTATION_POLICY.md`

## 0. Progress Checkpoint (2026-04-01)

Phase 25's shipped live UI baseline is complete, and the first tranche of
follow-on testing hardening is now delivered. The remaining work in this
roadmap is the realtime/recovery/adversarial closeout inspired by the current
LiveView, Livewire, Symfony UX LiveComponent, and Turbo testing surfaces.

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
- `25H`: shared `ALNLiveTestSupport`, the executable Node-backed runtime
  harness, and split runtime-semantic test suites
- `25I`: DOM operation semantics, keyed collection assertions, navigation
  behavior, dispatch-event assertions, and negative-path runtime checks
- `25J`: live form, upload/XHR progress, region defer/poll/lazy interaction
  coverage, plus targeted tech-demo live endpoint integration tests

Planned next:

- `25K`: push stream, reconnect, auth-expiry, and backpressure coverage
- `25L`: adversarial protocol/runtime regressions and artifact closeout

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
8. `25H`: live test support helpers and executable runtime harness.
9. `25I`: DOM patch semantics, navigation, and dispatch assertions.
10. `25J`: forms, regions, poll/lazy/defer, and upload interaction coverage.
11. `25K`: stream lifecycle, reconnect, auth-expiry, and backpressure tests.
12. `25L`: adversarial regressions, issue fixtures, and confidence closeout.

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

## 4.8 Phase 25H: Live Test Support + Runtime Harness (Delivered 2026-04-01)

Goal:

- move Arlen's live testing beyond payload-shape assertions by adding a shared,
  executable runtime harness similar in spirit to `Phoenix.LiveViewTest`,
  `Livewire::test()`, Symfony's `InteractsWithLiveComponents`, and Turbo's
  stream assertion helpers

Delivered:

- `tests/shared/ALNLiveTestSupport.{h,m}` for payload decoding, DOM assertion
  helpers, and live request fixture builders
- a small executable runtime test harness that can load `/arlen/live.js`,
  simulate DOM state, apply payloads, and capture emitted events without
  requiring a full browser for every case
- focused runtime test files split by behavior rather than one large Phase 25
  suite
- helper-level assertions for operation application, attribute mutation, and
  emitted custom events

Why this exists:

- Arlen currently tests live protocol shape, controller helpers, and runtime
  asset serving, but most runtime behavior is still covered by string
  presence/smoke checks rather than executable interaction assertions

## 4.9 Phase 25I: DOM Patch Semantics + Navigation/Event Assertions (Delivered 2026-04-01)

Goal:

- give the runtime the same style of operation-level semantic coverage that
  Phoenix, Symfony, and Turbo use for live redirects, events, and partial-page
  updates

Delivered:

- executable assertions for `replace`, `update`, `append`, `prepend`, and
  `remove`
- executable assertions for keyed `upsert` / `discard`, including empty-state
  toggling and key replacement behavior
- runtime assertions for `navigate` behavior and history replacement/push
  semantics
- runtime assertions for `dispatch` behavior, target scoping, and event-detail
  propagation
- negative-path tests for unknown operations and invalid selectors

## 4.10 Phase 25J: Forms, Regions, Poll/Lazy/Defer, and Upload Interaction Coverage (Delivered 2026-04-01)

Goal:

- close the largest current test gap versus LiveView/Livewire/Symfony by
  exercising actual live interaction flows instead of only payload generation

Delivered:

- GET and POST live form tests covering query/body serialization, submit-button
  preservation, busy-state transitions, and HTML fallback behavior
- live response handling tests for ordinary HTML, live JSON, redirects, and
  validation/error responses
- region tests for `data-arlen-live-src`, including initial hydration, repeat
  hydration protection, poll scheduling, defer timing, lazy hydration, and
  IntersectionObserver fallback
- upload tests covering XHR path selection, progress attribute updates,
  `arlen:live:upload-progress`, and upload failure behavior
- targeted integration tests for the tech demo pulse/upload live endpoints
  that previously sat behind `phase25-confidence` smoke coverage only

## 4.11 Phase 25K: Stream Lifecycle, Reconnect, Auth-Expiry, and Backpressure

Goal:

- bring Arlen's realtime/live tests closer to Turbo stream-source and
  LiveView-connected/disconnected coverage

Planned deliverables:

- runtime tests for websocket stream open, message application, error, close,
  and reconnect backoff behavior
- assertions that stream subscriptions do not double-connect and that repeated
  scans are idempotent
- runtime tests for `arlen:live:stream-open`,
  `arlen:live:stream-closed`, `arlen:live:auth-expired`, and
  `arlen:live:backpressure`
- HTTP/live tests covering `401`, `403`, and `429` responses plus retry-after
  handling
- integration tests that wait for stream readiness before asserting pushed
  content, similar to Turbo's explicit stream-source synchronization helpers

## 4.12 Phase 25L: Adversarial Regressions + Confidence Closeout

Goal:

- preserve the fragment-first live surface with competitor-inspired regression
  discipline, especially around malformed payloads and edge-case runtime input

Planned deliverables:

- protocol tests for invalid `dispatch` details, invalid meta key/value shapes,
  bad navigate locations, selector/key escaping edges, and header normalization
- issue-driven regression fixtures under `tests/fixtures/phase25/`
- a widened `phase25-live-tests` target or sibling focused bundles that fail
  closed on runtime-semantic regressions
- stronger `phase25-confidence` artifacts covering one push-path check and one
  negative-path/live-error check in addition to the current smoke pages
- docs closeout reflecting the new helper/test architecture once the subphases
  ship

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
controller helpers, built-in runtime route, executable runtime DOM semantics,
and live interaction coverage through `tests/shared/ALNLiveTestSupport.{h,m}`
plus `tests/shared/live_runtime_harness.js`. `phase25-confidence` boots the
tech demo server and records smoke artifacts for the shipped live page under
`build/release_confidence/phase25/`.

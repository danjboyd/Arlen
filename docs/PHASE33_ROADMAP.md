# Arlen Phase 33 Roadmap

Status: Complete (`33A-33L` delivered on 2026-04-15)
Last updated: 2026-04-15

Related docs:
- `docs/STATUS.md`
- `docs/README.md`
- `README.md`
- `docs/REALTIME_COMPOSITION.md`
- `docs/LIVE_UI.md`
- `docs/PHASE25_ROADMAP.md`
- `docs/PHASE28_ROADMAP.md`
- `docs/PHASE7H_DISTRIBUTED_RUNTIME_DEPTH.md`
- `docs/ECOSYSTEM_SERVICES.md`
- `docs/DOCUMENTATION_POLICY.md`

Reference inputs reviewed for this roadmap:
- `docs/REALTIME_COMPOSITION.md`
- `docs/LIVE_UI.md`
- `docs/PHASE25_ROADMAP.md`
- `docs/PHASE28_ROADMAP.md`
- `docs/PHASE7H_DISTRIBUTED_RUNTIME_DEPTH.md`
- `docs/ECOSYSTEM_SERVICES.md`
- `docs/NOTIFICATIONS_MODULE.md`
- `docs/JOBS_MODULE.md`
- `src/Arlen/Support/ALNRealtime.h`
- `src/Arlen/Support/ALNRealtime.m`
- `src/Arlen/MVC/Controller/ALNController.h`

## 0. Starting Point

Arlen already ships meaningful realtime and consumer-contract building blocks:

- websocket channel support in the HTTP runtime
- server-sent events through controller helpers
- deterministic in-process fanout via `ALNRealtimeHub`
- fragment-first live UI and browser runtime behavior in Phase 25
- typed transport and optional React-facing helpers in Phase 28
- explicit distributed-runtime honesty that cross-node realtime fanout
  requires an external broker

What Arlen still does not have is a narrow durable event-stream seam between:

- transient transport and in-process fanout
  and
- durable replayable app or module event history

Today any app or module that needs replay/resume semantics still has to define
its own answers for:

- authoritative sequence assignment
- append-versus-live-publish ordering
- replay after a durable cursor
- idempotent append retry behavior
- replay-window and resync boundaries
- explicit authorization for append, replay, and subscribe

Phase 33 exists to define that seam without turning Arlen core into a chat
product or duplicating the existing live UI/runtime or TypeScript work.

## 0.1 Phase 33 North Star

Make Arlen's realtime substrate durable, ordered, and explicit without making
core own product semantics.

That means:

- authoritative event history lives in durable storage rather than in process
  memory
- live delivery is layered on top of durable append instead of pretending to
  be the source of truth
- websocket, SSE, and replay/polling can consume the same core seam
- higher-level semantics such as conversation state, presence, read cursors,
  and operator workflows remain module-owned

## 1. Objective

Add a narrow durable event-stream seam to Arlen core/service architecture.

Phase 33 should deliver:

- a canonical event envelope for durable stream events
- an explicit append, replay, and idempotency contract
- a durable store adapter seam
- a live broker adapter seam
- deny-by-default authorization hooks for append, replay, and subscribe
- transport integration on top of that seam rather than beside it

Phase 33 is an infrastructure phase. It is not a conversation/chat module, a
presence layer, or a React-first consumer phase.

## 1.1 Why Phase 33 Exists

Arlen's current realtime contract is intentionally narrow:

- `ALNRealtimeHub` is process-local fanout over channel messages
- controller realtime helpers are transport helpers
- Phase 25 live UI reuses those transport paths for fragment push behavior

That baseline is useful, but it leaves a correctness gap for durable live
application workflows:

- if the process restarts, in-memory fanout state disappears
- reconnecting clients have no first-class replay contract
- apps must hand-roll sequence assignment and append ordering
- cross-node fanout remains an explicit external-broker concern

Arlen already uses adapter and module seams for durable behavior elsewhere:

- jobs
- notifications
- attachments
- cache

Phase 33 applies the same design discipline to event streams.

## 1.2 Design Principles

- Durability is authoritative:
  - committed durable append is the source of truth
- Live push is downstream of commit:
  - no transport path may present an event as authoritative before append
    succeeds
- Replay is store-backed:
  - broker retention is never the replay contract
- Fail closed on access:
  - append, replay, and subscribe are separately authorizable and denied by
    default
- Keep core narrow:
  - no chat naming, unread state, typing indicators, or presence semantics in
    the core seam
- Preserve transport additivity:
  - websocket, SSE, and replay/polling should compose with existing runtime
    behavior rather than replace it
- Preserve consumer additivity:
  - plain typed contracts come before optional React-facing helpers
- Keep distributed-runtime honesty:
  - cross-node fanout still requires an external broker adapter

## 2. Scope Summary

1. `33A`: durable event-stream contract and canonical envelope.
2. `33B`: store adapter seam and append/replay baseline.
3. `33C`: idempotency, field ownership, and failure semantics.
4. `33D`: authorization hook contract and request-context shape.
5. `33E`: broker adapter seam and in-process baseline implementation.
6. `33F`: replay-window, cursor, and resync-required contract.
7. `33G`: websocket integration on top of the seam.
8. `33H`: SSE and HTTP replay/poll integration.
9. `33I`: plain typed consumer contract and transport fallback shape.
10. `33J`: verification lanes, fixtures, and confidence coverage.
11. `33K`: docs, examples, and app-author guidance.
12. `33L`: module follow-on boundary and post-phase extension map.

## 2.1 Recommended Rollout Order

1. `33A`
2. `33B`
3. `33C`
4. `33D`
5. `33E`
6. `33F`
7. `33G`
8. `33H`
9. `33I`
10. `33J`
11. `33K`
12. `33L`

That order stabilizes correctness, auth, and storage contracts before Arlen
commits to transport behavior, client contracts, or follow-on module work.

## 2.2 Current Phase State

Delivered in this checkpoint:

- `33A`
- `33B`
- `33C`
- `33D`
- `33E`
- `33F`
- `33G`
- `33H`
- `33I`
- `33J`
- `33K`
- `33L`

## 3. Scope Guardrails

- Do not turn Phase 33 into a chat or conversation product.
- Do not put typing indicators, presence heartbeats, read cursors, unread
  state, or participant semantics in core.
- Do not let broker delivery become the source of truth for replay.
- Do not present live delivery as exactly-once transport.
- Do not leave idempotency behavior as adapter-specific hand-waving; the core
  contract must say what retry means.
- Do not accept client-provided channel or stream names as sufficient
  authorization.
- Do not create a parallel live runtime that duplicates Phase 25 behavior.
- Do not require React or Node-specific dependencies in the first shipping
  slice.
- Do not claim cross-node realtime fanout without an explicit external broker
  adapter.

## 4. Detailed Subphases

### 33A. Durable Event-Stream Contract and Canonical Envelope

Status: Delivered on 2026-04-15

Goal:
- define the narrow core contract for named append-only event streams

Deliverables:
- public terminology for:
  - stream identifier
  - cursor
  - durable append
  - replay after cursor
  - resync-required boundary
- canonical event-envelope shape
- clear distinction between framework-required fields and app-provided fields

Required envelope fields:

- `stream_id`
- `sequence`
- `event_id`
- `event_type`
- `occurred_at`
- `payload`

Optional fields:

- `idempotency_key`
- `actor`
- `metadata`

Field ownership contract:

- `stream_id`, `event_type`, `payload`, and optional app metadata are caller
  inputs
- `sequence` is assigned by the durable store
- `event_id` is framework- or store-assigned unless a stricter later contract
  is documented
- `occurred_at` is framework-normalized at append time so replay has one
  authoritative timestamp contract

Acceptance:
- one roadmap/doc page defines the envelope and field ownership clearly
- the contract is generic and domain-neutral rather than conversation-specific

### 33B. Store Adapter Seam and Append/Replay Baseline

Status: Delivered on 2026-04-15

Goal:
- define the durable source-of-truth seam for authoritative append and replay

Deliverables:
- `ALNEventStreamStore`-style protocol for:
  - append committed event to a named stream
  - replay events after a durable sequence cursor
  - fetch latest cursor for a stream
- explicit replay ordering by committed sequence
- replay limit semantics with deterministic defaults

Acceptance:
- append returns the committed envelope with authoritative sequence
- replay returns events strictly ordered by sequence
- latest-cursor lookup is standardized rather than app-defined

### 33C. Idempotency, Field Ownership, and Failure Semantics

Status: Delivered on 2026-04-15

Goal:
- remove ambiguity from retry and post-commit failure behavior

Deliverables:
- explicit idempotency contract:
  - idempotency key scope is `(stream_id, idempotency_key)`
  - retrying the same append on the same stream returns the original committed
    envelope
  - reusing the same key with materially different event contents is rejected
    deterministically
- explicit append failure behavior:
  - if append fails before commit, no authoritative event exists
  - if append commits and live publish fails, replay still returns the
    committed event
- explicit client recovery expectation:
  - clients must tolerate missed live delivery and reconcile through replay

Acceptance:
- Arlen docs/tests state the same retry semantics
- no adapter can silently redefine idempotency meaning

### 33D. Authorization Hook Contract and Request-Context Shape

Status: Delivered on 2026-04-15

Goal:
- make access-control behavior first-class and fail closed

Deliverables:
- separate authorization hooks for:
  - append
  - replay
  - subscribe
- a standardized request/auth context shape derived from Arlen request state
  rather than an unstructured dictionary grab bag
- deny-by-default behavior when no app hook authorizes the operation

Design direction:

- authorization should be able to inspect:
  - route/request context
  - session/auth subject and roles
  - app-owned tenant or claim-token facts
  - requested stream id and cursor

Acceptance:
- append, replay, and subscribe can be authorized independently
- the auth contract is tied to Arlen request/runtime context explicitly

### 33E. Broker Adapter Seam and In-Process Baseline

Status: Delivered on 2026-04-15

Goal:
- formalize live distribution as a separate seam from durability

Deliverables:
- `ALNEventStreamBroker`-style protocol for:
  - publish committed event
  - subscribe to a stream
  - unsubscribe
- first baseline adapter that preserves today's in-process path for simple
  deployments
- lifecycle and diagnostics metadata sufficient for transport integration

Acceptance:
- the in-process baseline remains available for local/simple deployments
- the broker contract is explicitly non-authoritative and non-durable

### 33F. Replay Window, Cursor, and Resync-Required Contract

Status: Delivered on 2026-04-15

Goal:
- standardize what replayable history means and how clients recover when a
  requested cursor can no longer be satisfied

Deliverables:
- first cursor contract based on `afterSequence`
- replay window/limit documentation and server cap behavior
- deterministic `resync_required` result shape for replay failures due to an
  unavailable cursor window
- optional server behavior for "replay first, then switch to live"

First-pass `resync_required` contract should include:

- machine-readable status code/name
- requested cursor
- latest durable cursor
- whether the cursor is too old, malformed, or otherwise unsatisfiable

Acceptance:
- websocket, SSE, and HTTP replay paths share one resync contract
- clients can distinguish auth failure from replay-window failure

### 33G. Websocket Integration on Top of the Seam

Status: Delivered on 2026-04-15

Goal:
- let websocket subscriptions consume the durable seam instead of bypassing it

Deliverables:
- websocket stream subscribe path using:
  - auth hook
  - optional replay-after-sequence
  - transition from replay to live delivery
- authoritative envelope delivery over websocket
- reconnect-path tests that prove replay can recover missed live events

Acceptance:
- websocket delivery no longer relies only on transient channel fanout for
  durable-stream use cases

### 33H. SSE and HTTP Replay/Poll Integration

Status: Delivered on 2026-04-15

Goal:
- make durable stream access transport-independent

Deliverables:
- SSE subscribe path using the same replay/auth/envelope contract
- HTTP replay endpoint or helper path for polling and explicit catch-up
- consistent envelope and cursor semantics across websocket, SSE, and HTTP

Acceptance:
- apps can consume the same stream seam through websocket or SSE
- polling/replay path uses durable storage rather than broker history

### 33I. Plain Typed Consumer Contract and Transport Fallback Shape

Status: Delivered on 2026-04-15

Goal:
- define the consumer-facing contract without making React part of the first
  shipping slice

Deliverables:
- plain typed event/cursor contract compatible with Phase 28 generated/client
  patterns
- reconnect/resume contract built around durable cursor replay
- transport preference/fallback shape for websocket, SSE, and poll consumers
- generated `realtime` TypeScript target in the existing Phase 28 package
- focused unit coverage for transport planning, replay-path shaping, cursor
  advancement, and `resync_required` error behavior

Acceptance:
- no React dependency is required for the first consumer slice
- typed consumer contracts are additive to the existing Phase 28 transport
  story rather than a replacement

### 33J. Verification Lanes, Fixtures, and Confidence Coverage

Status: Delivered on 2026-04-15

Goal:
- give the seam the same seriousness Arlen expects from other core/runtime
  contracts

Deliverables:
- unit coverage for:
  - append ordering
  - idempotent retry
  - auth failure paths
  - replay and resync-required behavior
- integration coverage for:
  - publish-after-commit semantics
  - replay after disconnect
  - websocket and SSE consumption of the same stream seam
- fixture-backed cases for malformed cursor, replay-window failure, and
  unauthorized access
- repo-native `phase33-confidence` lane pairing Objective-C pass markers with
  generated TypeScript snapshot/unit manifests
- updated Phase 28 generated package snapshot fixture to cover the new
  `realtime` target

Acceptance:
- the seam has deterministic regression coverage before Arlen broadens module
  or client semantics on top of it

### 33K. Docs, Examples, and App-Author Guidance

Status: Delivered on 2026-04-15

Goal:
- explain the seam clearly without pretending higher-level semantics already
  ship

Deliverables:
- roadmap and status closeout
- app-author guidance for:
  - when to use raw realtime transport versus durable stream seam
  - how to model store and broker adapters
  - how to reason about replay, auth, and idempotency
- one small example showing append, replay, and transport-agnostic subscribe
- regenerated browser-facing docs and docs index output for the new Phase 33
  materials
- docs quality gate execution as part of closeout:
  - `make docs-api`
  - `make docs-html`
  - `make ci-docs`
- any roadmap/docs consistency issues flagged by the docs quality gate are
  fixed in the same closeout slice rather than deferred

Acceptance:
- docs state current shipped scope honestly
- examples remain domain-neutral and do not imply a chat product in core
- browser docs regenerate cleanly and the docs quality gate passes without
  roadmap/status/index consistency failures

### 33L. Module Follow-On Boundary and Post-Phase Extension Map

Status: Delivered on 2026-04-15

Goal:
- end the phase with explicit boundaries so future work lands in the right
  layer

Follow-on candidates after Phase 33:

- first-party broker/store adapters
- plain generated client helpers on top of the typed seam
- optional React-facing helpers
- a first-party conversation or operator-workflow module
- module-owned read cursor, presence, or participant semantics

Acceptance:
- the roadmap states clearly what Phase 33 does not own
- future module/product semantics are identified as later work rather than
  implied deliverables

## 5. Acceptance Bar

Phase 33 is complete when Arlen can defend all of the following claims:

1. An app can append a durable event to a named stream and receive an
   authoritative committed sequence.
2. Replay after a durable sequence cursor is deterministic and ordered.
3. Retrying an append with the same idempotency key on the same stream returns
   the original committed envelope, while conflicting reuse is rejected.
4. Append, replay, and subscribe can be authorized independently and are
   denied by default when the app does not opt in.
5. Live publish occurs only after durable append succeeds.
6. If live publish fails after commit, replay still returns the committed
   event.
7. Websocket and SSE can consume the same stream seam without redefining
   replay/auth semantics.
8. When a cursor cannot be satisfied, Arlen returns an explicit
   `resync_required` result rather than an ambiguous failure.

## 6. What Phase 33 Is Not

Phase 33 is not:

- a conversation/chat product
- a presence subsystem
- an unread/read-cursor product feature
- a React-first client package
- a guarantee of distributed fanout without an external broker adapter

Those may be valid future module or adapter work, but they are not part of the
core seam acceptance bar.

# HelpDesk feature requests — upstream assessment — 2026-09-18

Status: assessed upstream; accepted in principle; not yet scheduled.
Revised 2026-09-18 after `HelpDesk`'s reply — see "Revision 1" below. The FR-B scope
recorded here was wrong as first written and is corrected in place.

Request: `../HelpDesk/docs/ARLEN_FEATURE_REQUESTS.md` (worker `helpdesk`, raised while
planning M1 against Arlen as vendored at `vendor/Arlen`; approved by Daniel 2026-09-18
for hand-off).

Exchange:

1. `../HelpDesk/docs/ARLEN_FEATURE_REQUESTS.md` — original request.
2. `../HelpDesk/docs/ARLEN_FEATURE_REQUESTS_RESPONSE.md` — our assessment.
3. `../HelpDesk/docs/ARLEN_FEATURE_REQUESTS_REPLY.md` — their reply, which corrected our
   FR-B scope.

Ownership rule:

- Arlen records upstream status only.
- `HelpDesk` keeps app-level closure authority over its own workarounds.
- Nothing in `HelpDesk`'s `vendor/Arlen` is patched locally, so every item below is a
  clean upstream gap rather than a divergence to reconcile.

These are framework gaps, not defects, so they are tracked here as `ARLEN-FR-*` and are
deliberately **not** filed in `docs/internal/OPEN_ISSUES.md`, which is a bug register
(`ARLEN-BUG-*`) by convention.

## Tracking IDs

| ID | Request | Origin | Upstream status |
| --- | --- | --- | --- |
| `ARLEN-FR-008` | Generic config-driven OIDC provider routes | FR-C | accepted; recommended first |
| `ARLEN-FR-009` | Durable PostgreSQL `ALNEventStreamStore` | FR-B (prerequisite) | accepted; prerequisite for `ARLEN-FR-010` |
| `ARLEN-FR-010` | `ALNPostgresEventStreamBroker` over `LISTEN`/`NOTIFY` | FR-B | accepted; must not ship before `ARLEN-FR-009` |
| `ARLEN-FR-014` | Transport seam on `ALNRealtimeHub`, plus its Postgres adapter | FR-B reply | accepted; makes the documented Live UI push path multi-worker-correct |
| `ARLEN-FR-011` | Exported, documented outbound HTTP client | FR-A | accepted; scope carefully |
| `ARLEN-FR-012` | Declarative `amr`/`acr` → assurance mapping | FR-D1 | accepted |
| `ARLEN-FR-013` | Configurable step-up path for module surfaces | FR-D2 | accepted; re-prioritised upward |

## Verification of the report's premises

Every "what ships today" claim in the request was checked against this tree. All of them
hold.

| Claim | Result |
| --- | --- |
| `ALNAuthProviderPresets` + `ALNOIDCClient` + `ALNAuthProviderSessionBridge` all ship | confirmed: `src/Arlen/Support/ALNAuthProviderPresets.{h,m}`, `ALNOIDCClient.{h,m}` |
| `ALNAuthModule.m` hardcodes only the stub provider flow | confirmed: `modules/auth/Sources/ALNAuthModule.m:926-928`, `:934`, `:1053` |
| `authModule.providers` is already a map keyed by provider id | confirmed: `modules/auth/module.plist:44`, containing only `stub` |
| `ALNHTTPCompat.h` is absent from the umbrella and from `API_REFERENCE.md` | confirmed: no match for `HTTPCompat` in `src/Arlen/Arlen.h` or `docs/API_REFERENCE.md`; the header exports three functions |
| Broker seam exists, in-memory implementation only | confirmed: `src/Arlen/Support/ALNEventStream.h:156` (protocol), `:194` (in-memory) |
| Broker-backed multi-node fanout is a documented non-goal | confirmed: `docs/REALTIME_COMPOSITION.md:105` |
| `ALNAuthProviderSessionBridge` takes `assuranceLevel` from the resolver's descriptor | confirmed: `src/Arlen/Support/ALNAuthProviderSessionBridge.m:143` |
| Module surfaces cannot redirect step-up | confirmed: `stepUpPath` hardcoded to the auth runtime `totpPath` in `modules/ops`, `modules/jobs`, `modules/admin-ui`, `modules/storage` |

The report also correctly retracts its own initial reading that the assurance model is
broken with an external IdP. That retraction is right and the model needs no change for
the common case.

## Corrections to the request

Two, both of which change how the work should be sequenced downstream.

### FR-C does not depend on FR-A

The request states that FR-C's JWKS fetch "needs an HTTP fetch — see FR-A." It does not.
`ALNBoundedMetadataGET` already ships and its design constraints — rejects redirects,
rejects cookies, rejects non-200, bounded body — are precisely the JWKS and discovery
threat model. They are a fit for this use, not a limitation to work around.

`ARLEN-FR-008` is therefore fully self-contained against today's tree and is not blocked
by `ARLEN-FR-011`.

### FR-B cannot ship broker-first

The request proposes shipping `ALNPostgresEventStreamBroker` first and treating a durable
Postgres store as a "natural companion." That ordering does not produce a working result.

The notify-a-sequence-number design the request correctly derives from the 8000-byte
`NOTIFY` payload limit requires each subscriber to replay from the store after the cursor
it holds. Sequence numbers are assigned by `appendEvent:toStream:error:`
(`src/Arlen/Support/ALNEventStream.h:122`), which is a store responsibility, and replay is
served by `eventsForStream:afterSequence:limit:error:` from that same store.

With `ALNInMemoryEventStreamStore`, worker B cannot replay an event appended on worker A —
worker B's store does not hold the event, and the two workers do not share a sequence
space, so a notified sequence number is not even meaningful across them. A Postgres broker
over a process-local store does not fix the multi-worker bug; it changes its shape while
leaving it silent.

`ARLEN-FR-009` and `ARLEN-FR-010` therefore ship together, or the store ships first.

## Assessment per item

### ARLEN-FR-008 — generic config-driven OIDC provider routes (FR-C)

Accepted, and the strongest item in the set. The seam is genuinely one adapter short: the
provider map, the per-tenant override path, the full authorization → state validation →
token exchange → ID-token verification → normalization sequence, and the resolver bridge
all ship and work. Only module-owned routes are missing, so the only provider an app can
actually authenticate against today is the test double.

The request's argument for framework ownership is correct: without this, every app writes
the same two routes over the same four classes, each instance an independent chance to get
PKCE, state or issuer validation subtly wrong. That is the category of code a framework
should own exactly once.

Scope as requested, including:

- PKCE S256 on by default, with the routes generating, stashing and replaying the verifier
  that `tokenExchangeRequestForProviderConfiguration:...` already accepts.
- JWKS fetch and cache via `ALNBoundedMetadataGET`, under the key-count and issuer
  constraints `docs/OAUTH_RESOURCE_SERVER.md` already specifies for the resource-server
  side.
- The resolver seam preserved unchanged. Mapping a normalized identity onto an app's user
  table is app work and the bridge already models it correctly.

Take the request's suggested `doctor` check as part of this item, not as a follow-up: a
`microsoft` provider left on the multi-tenant `login.microsoftonline.com/common/v2.0`
issuer while a `tenantID` is configured is issuer validation that silently means nothing.
Both shipped presets default to the `/common/` issuer, so this is the likely
misconfiguration, and it fails open.

### ARLEN-FR-009 / ARLEN-FR-010 — durable Postgres event-stream store and broker (FR-B)

Accepted. The severity argument is the sharpest in the report and it holds: multi-worker
fanout fails with no error, no log and no degraded flag, and only under a configuration
that dev typically does not run. `docs/APP_AUTHORING_GUIDE.md` §5.1 already warns against
process-local state under multiple propane workers, and realtime fanout is precisely that
state.

The implementation notes in the request are sound and reduce the cost:

- No new dependency — libpq is already linked for `ALNPg`.
- `ALNPostgresJobAdapter` is the established pattern for a durable Postgres adapter behind
  a seam.
- One dedicated `LISTEN` connection per process, held outside the pool, matching the
  reservation discipline `docs/DURABLE_JOBS.md` already documents for lease heartbeats.
- Notify a sequence number rather than an event body, and let subscribers replay from the
  store. This fits the existing contract, which already makes the durable store rather
  than broker retention the source of replay, and already specifies `resync_required` for
  a stale cursor.

Subject to the sequencing correction above.

Until this lands, `docs/REALTIME_COMPOSITION.md` §4.1 should say plainly that in-memory
fanout is incorrect — not merely unsupported — under a multi-worker deployment, and point
at polling live regions as the supported alternative. The non-goal line as written reads
as a missing feature rather than a live footgun. That docs change is cheap and should not
wait for the adapters.

### ARLEN-FR-011 — exported outbound HTTP client (FR-A)

Accepted, with the lowest urgency and the largest design surface. Every behaviour on the
request's list is right, particularly redaction-safe logging: a bearer token written to a
log file is exactly the accident a framework should make structurally hard rather than
leave to each app's care.

Two scoping notes:

- Promoting a general outbound client widens our security surface in a way the existing
  primitive deliberately does not. `ALNBoundedMetadataGET` is narrow on purpose; an
  arbitrary-URL client with redirect support is an SSRF vector and needs an explicit
  policy position, not just a timeout story.
- The total-vs-connect timeout trap `docs/OAUTH_RESOURCE_SERVER.md` already documents
  applies unchanged here: `connect_timeout` alone does not bound an established socket.

Nothing blocks on this item, which is the argument for doing it properly rather than
quickly.

### ARLEN-FR-012 — declarative assurance mapping (FR-D1)

Accepted. The observation is correct: every app doing IdP login otherwise hand-rolls the
same "`amr` contains `mfa`/`otp`/`hwk` → assurance 2" rule, and a wrong hand-roll either
under-claims, locking an app's own admin out of module surfaces, or over-claims,
asserting an MFA event that never happened. A declarative mapping on the provider
configuration makes the safe reading the default.

### ARLEN-FR-013 — configurable module step-up path (FR-D2)

Accepted, and re-prioritised above the `low` the request assigned it.

The request files this as a convenience. It is a lockout: an IdP-only user whose module
step-up window ages out is redirected to `/auth/mfa`, which lists no enrolled factor for
them, with no path forward. The correct re-elevation is a fresh OIDC round trip with
`prompt=login`, which module routes today have no way to express.

It is also close to free. The module surfaces already pass a `stepUpPath` — they simply
hardcode it to `[authRuntime totpPath]` at four call sites (`modules/ops/Sources/ALNOpsModule.m:1003`,
`modules/jobs/Sources/ALNJobsModule.m:2086`, `modules/admin-ui/Sources/ALNAdminUIModule.m:3325`,
`modules/storage/Sources/ALNStorageModule.m:2246`). Making that a configurable runtime
property, with the current value as the default, is a small change against an existing
seam. Configuring the assurance requirement alongside it, as the request suggests, is the
natural extension.

## Recommended sequencing

Revised from the request's `C, B, A, D`, and revised again after Revision 1:

0. **Realtime docs warnings** — `LIVE_UI.md` §7, `REALTIME_COMPOSITION.md` §4.1, and the
   `ALNRealtime.h` header. Independent of every item below, near-zero cost, and it retires
   the silent footgun immediately rather than at the end of a multi-item program. Ship
   first.
1. `ARLEN-FR-008` (FR-C) — self-contained, unblocked, highest value per unit of work.
2. `ARLEN-FR-013` (FR-D2) — small, and closes a lockout.
3. `ARLEN-FR-012` (FR-D1).
4. `ARLEN-FR-009` + `ARLEN-FR-010` + `ARLEN-FR-014` (FR-B) — the realtime-correctness
   program. Store before broker within FR-009/010; the FR-014 seam can be designed in
   parallel but lands against the same shared transport.
5. `ARLEN-FR-011` (FR-A) — largest surface, nothing blocks on it.

`ARLEN-FR-008` moves up because it is unblocked once the FR-A dependency is dropped.
`ARLEN-FR-013` moves up because it is a dead-end at trivial cost. `ARLEN-FR-011` stays
last because every consumer of it has a working local workaround.

The FR-B program moves **down** relative to the first revision. It grew by a seam
(`ARLEN-FR-014`) while its urgency fell: no downstream app is waiting on it — `HelpDesk`
stays on a polling live region under every outcome — and the docs warnings at step 0
address the actual live hazard at a fraction of the cost. Scheduling the program honestly
is better than squeezing it ahead of items that are ready.

None of the six should start on `fix/durable-jobs-nonblocking-cleanup`; each wants its own
branch off `main`.

## Downstream workarounds to retire

Recorded so the cleanup is not lost when these land. `HelpDesk` owns the deletions.

| Upstream item | `HelpDesk` workaround to delete |
| --- | --- |
| `ARLEN-FR-008` | app-owned `/auth/oidc/start` and `/auth/oidc/callback` (the resolver is kept) |
| `ARLEN-FR-010` | M3 chat panel polling live region, switched to push |
| `ARLEN-FR-011` | app-owned `HDHTTPClient` (~150 lines over `ALNHTTPCompat.h`) |
| `ARLEN-FR-012` | `amr` read and `assuranceLevel` set in the app's own resolver |

## Revision 1 — FR-B scope was wrong — 2026-09-18

Status: corrected; `ARLEN-FR-014` opened; sequencing above updated to match.

Source: `../HelpDesk/docs/ARLEN_FEATURE_REQUESTS_REPLY.md`.

`HelpDesk` accepted both of our corrections and then found a scoping error in our own
assessment that is more consequential than either of them. Their finding is correct and
was verified against this tree.

### The error

`ARLEN-FR-009` and `ARLEN-FR-010`, as scoped above, fix multi-worker fanout for the
durable event-stream seam and leave the push path `docs/LIVE_UI.md` actually teaches just
as broken, and just as silent.

The documented path does not go through the event-stream seam at all:

- `docs/LIVE_UI.md:198` gives `publishLiveOperations:onChannel:error:` as the push API,
  and `:233`/`:239` give browser subscription as
  `data-arlen-live-stream="/ws/channel/<name>"`.
- `src/Arlen/MVC/Controller/ALNController.m:528` — that method ends in
  `[[ALNRealtimeHub sharedHub] publishMessage:message onChannel:channel ?: @""]`.
- `src/Arlen/Support/ALNRealtime.h:24-42` — `ALNRealtimeHub` is a bare `+sharedHub`
  singleton. There is no settable backend and no transport protocol; nothing corresponds
  to `ALNApplication.h:124 setEventStreamBroker:`. **There is no seam to write an adapter
  against.**

Additionally, and not raised by `HelpDesk`:
`src/Arlen/HTTP/ALNHTTPServer.m:3457` also publishes through `sharedHub`, so introducing
the seam has more than one call site to route.

Our assessment anchored on the seam the request happened to be filed against without
checking whether it was the seam apps are actually pointed at. It is not: an app reaching
for realtime in Arlen lands on `LIVE_UI.md` and `publishLiveOperations:`; the durable seam
in `EVENT_STREAMS.md` is the one that has to be sought out. `HelpDesk`'s framing is right
that this makes the uncovered path the more common one.

### Correction to their proposed remedy

Their preferred option — extend `ARLEN-FR-010` so "one Postgres adapter serves both" —
does not hold, for a reason in the same family as the error we corrected in their original
request.

The event-stream side notifies a sequence number and replays from the store. The hub has
neither: `publishMessage:onChannel:` takes an opaque `NSString` and there is nothing to
replay from. Live operations also carry arbitrary HTML — `ALNLive.m:83`, `:429`, `:610`,
and the `LIVE_UI.md:246` example is `appendOperationForTarget:html:` — so a rendered row
or card will routinely exceed the 8000-byte `NOTIFY` limit that they correctly identified
for the durable path.

The hub therefore needs its own spool to notify against, which on the durable side is
arguably optional and here is not. The workable shape is a **shared low-level Postgres
`LISTEN`/`NOTIFY` transport with two adapters above it**, carrying different payload and
replay semantics — not one adapter serving both seams.

That is materially more work than extending `ARLEN-FR-010`, which is why it is tracked
separately as `ARLEN-FR-014` rather than folded in. Introducing a seam where none exists
is design work, not adapter work, and folding it in would hold `ARLEN-FR-009`/`010`
hostage to it. This also matches their own second preference: file it separately so the
sequencing stays a deliberate choice.

### Docs warnings, widened and promoted

Their amendment to our proposed `REALTIME_COMPOSITION.md` §4.1 change is accepted in full
and promoted to step 0 of the sequencing.

The warning that in-memory fanout is *incorrect* under multi-worker — not merely
unsupported — belongs in `docs/LIVE_UI.md` §7 beside the `publishLiveOperations:` example,
because that is where an app author is standing when the decision is made. §4.1 is only
where `HelpDesk` happened to find it. `ALNRealtime.h` should carry it too.

If the eventual answer for a given app is "rebuild on the durable seam," that instruction
has to state the migration cost `HelpDesk` identified: the durable seam carries
`ALNEventEnvelope` JSON (`streamID`, `sequence`, `eventID`, `eventType`, `occurredAt`,
`payload` — `ALNEventStream.h:30-40`), not the `arlen-live-v1` operations payload that
`/arlen/live.js` knows how to apply (`ALNLive.m:561`, `:1617`). An app taking that route
gives up the runtime's DOM patching for that region and writes its own client glue. Apps
should be told that before they build on `publishLiveOperations:`, not after.

### Design inputs adopted from their reply

Both are better than what we sent and are adopted.

- **`ARLEN-FR-008` JWKS fetch.** Rather than reuse `ALNBoundedMetadataGET` generically,
  reuse the in-tree shape at `src/Arlen/Support/ALNOAuthResourceServer.m:117`, which
  already fetches JWKS via `ALNBoundedMetadataGETWithError(url, 262144, 5, &error)` behind
  a fail-closed `jwksAllowedHosts` allowlist (`:81-83`, `:162`) with a `jwksMaxAgeSeconds`
  cache bounded to 30–3600s (`:87-90`). The host-allowlist and cache-freshness decisions
  are already made; the provider routes should not re-derive them.
- **`ARLEN-FR-011` SSRF policy.** Adopt policy-required-at-construction with a fail-closed
  host allowlist, rather than an opt-in restriction. `jwksAllowedHosts` is the in-tree
  precedent for the shape. `HelpDesk` notes that a required allowlist costs them nothing,
  since their use is three fixed vendor hosts, and that they would not want an
  unrestricted client. That settles the open security question recorded under
  `ARLEN-FR-011` above.

### Downstream effect

None. `HelpDesk`'s M3 chat panel is a polling live region and stays one under every
outcome here — including "FR-B lands as scoped," which they say they would otherwise have
read as the cue to switch to push. Their stated reason for raising this now rather than at
M6 is that they would have retired a working workaround on the strength of a fix that did
not cover their path. That is the failure the step-0 docs warnings prevent generally.

The `ARLEN-FR-010` row in the workaround-retirement table above should therefore be read
as `ARLEN-FR-010` **and** `ARLEN-FR-014`: the chat panel switches to push only when both
have landed.

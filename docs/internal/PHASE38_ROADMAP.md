# Arlen Phase 38 Roadmap

Status: In progress
Last updated: 2026-04-28

Related docs:

- `docs/internal/OPEN_ISSUES.md`
- `docs/STATECOMPULSORYPOOLINGAPI_REPORT_RECONCILIATION_2026-04-24.md`
- `docs/PHASE10_ROADMAP.md`
- `docs/DEPLOYMENT.md`
- `docs/PROPANE.md`

## 1. Objective

Reproduce, isolate, and fix `ARLEN-BUG-024`: long-lived Arlen production
workers accumulating `/dev/null` file descriptors until descriptor exhaustion
breaks dynamic PDF/file responses and surfaces GNUstep Base pipe-creation
exceptions.

Phase 38 is production-runtime reliability work. The goal is to identify the
genuine descriptor opener, close or contain the leak at the right layer, and
leave permanent diagnostics and regression coverage so future Arlen releases
can prove that long-lived file-serving workloads remain stable.

## 2. Current Assessment

The report is accepted as a real Arlen-facing production failure, but current
evidence points to a downstream app descriptor leak rather than an Arlen
file-response leak. Phase 38 staging ruled out a simple per-file-response
`/dev/null` leak in the synthetic `fileBodyPath` path. Follow-up production
inspection identified `StateCompulsoryPoolingAPI` respondent autostart
subprocess launches as the likely descriptor opener.

Known facts:

1. Production workers reached `1023/1024` open descriptors.
2. About `967-970` descriptors per worker pointed at `/dev/null`.
3. Metadata endpoints remained healthy while full PDF `GET` responses failed.
4. `HEAD` on the same PDF endpoint could still return `200`.
5. Arlen logged `Failed to create pipe to handle perform in thread`, a GNUstep
   Base exception string that appears when its internal pipe setup fails.
6. Arlen's visible `fileBodyPath` send path preflights and closes per-request
   file descriptors.
7. The static file descriptor cache is bounded and cannot explain hundreds of
   `/dev/null` descriptors.
8. The short Phase 10M soak tripwire now checks `/dev/null` descriptor drift
   during validated file-body traffic, but it does not reproduce the production
   failure at current scale.

Working hypothesis:

The leak is in downstream app code invoked by respondent workflow endpoints,
not in the visible app file lookup or simple Arlen `fileBodyPath` happy path.
`StateCompulsoryPoolingAPI` creates an `NSTask`, assigns three fresh
`[NSFileHandle fileHandleWithNullDevice]` handles for stdin/stdout/stderr, and
does not release the task object. On GNUstep, an isolated reproduction showed
that this retains three `/dev/null` descriptors in the parent process for each
launch.

Phase 38 staging evidence from 2026-04-28:

- VM: Debian/libvirt via `../OracleTestVMs`, `100G` root disk.
- App: `StateCompulsoryPoolingAPI`, local fixture PostgreSQL DB, synthetic PDFs.
- Runtime shape: `propane`, two workers, `ARLEN_REQUEST_DISPATCH_MODE=serialized`,
  soft open-file limit `1024`.
- Arlen refs tested:
  - API-pinned `9ae509e8542d`
  - incident ref `734ac332693a`
- Incident-ref traffic:
  - `4,000` full PDF `GET` responses, `0` failures
  - `20,000` additional client-discarded PDF `GET` responses, `0` failures
  - final real worker FD state: `25` descriptors per worker, `1` `/dev/null`
    descriptor per worker
  - bounded `strace` windows during PDF traffic: `0` `/dev/null` opens

Production follow-up evidence from 2026-04-28:

- Restarted production workers accumulated `/dev/null` descriptors again while
  still far below the soft limit.
- Worker `1561594` moved from `85` to `100` `/dev/null` descriptors during
  investigation.
- Worker `1561595` moved from `79` to `91` `/dev/null` descriptors during
  investigation.
- Growth occurred in multiples of `3`, matching one app `NSTask` launch with
  three null-device standard streams.
- A disposable GNUstep VM reproducer using the same `NSTask` pattern showed
  `/dev/null` counts `0`, `3`, `6`, `9`, `12`, `15` after five launches.

## 3. Scope Summary

1. Phase 38A: staging infrastructure and environment parity.
2. Phase 38B: downstream app staging deployment and fixture corpus.
3. Phase 38C: synthetic traffic and descriptor sampling harness.
4. Phase 38D: syscall tracing and root-cause isolation.
5. Phase 38E: focused fix in the responsible layer.
6. Phase 38F: regression gates and CI artifact hardening.
7. Phase 38G: operational diagnostics and runbook updates.
8. Phase 38H: downstream validation and closeout.
9. Phase 38I: Arlen FD-pressure hardening and best-practice diagnostics.

## 4. Milestones

## 4.1 Phase 38A: Staging Infrastructure Parity

Status: Complete

Deliverables:

- Use `../OracleTestVMs` to provision a dedicated Debian VM on the libvirt
  infrastructure.
- Size the VM for trace-heavy soak work:
  - minimum `4` vCPUs
  - minimum `8GB` RAM
  - minimum `100GB` disk
- Match production as closely as practical:
  - Debian release and kernel family used by `iep-softwaredev`
  - clang-based GNUstep stack
  - Arlen runtime path and release shape
  - `propane` worker model
  - `ARLEN_REQUEST_DISPATCH_MODE=serialized`
  - worker count `2`
  - `LimitNOFILE=1024`
- Install base diagnostics:
  - `strace`
  - `lsof`
  - `jq`
  - `curl`
  - `gh`
  - `rsync`
- Provision GNUstep using `gnustep-cli-new`.

Acceptance:

- VM can build and run Arlen through the clang GNUstep toolchain.
- `propane` can launch two Arlen workers with the same serialized dispatch and
  open-file limit used in production.
- The VM has enough free disk to retain request logs, FD snapshots, and bounded
  syscall traces for at least one long soak.

## 4.2 Phase 38B: Staging App and Fixture Corpus

Status: Complete

Deliverables:

- Install GitHub CLI on the VM and authenticate interactively with the work
  account. Do not store or handle work tokens in repo docs.
- Clone `StateCompulsoryPoolingAPI` from the work GitHub organization.
- Deploy the same production Arlen commit first:
  `734ac332693a7cae7a656fdc78b376498f783eb6`.
- Prepare a non-production fixture dataset:
  - generated PDFs first
  - copied representative PDFs from `iep-softwaredev` only if needed
  - no production database credentials
  - no unnecessary customer data
- Configure the app so the same PDF endpoint shape exercises
  `response.fileBodyPath`.

Acceptance:

- Staging metadata endpoints return healthy JSON.
- Staging PDF `HEAD` returns expected headers.
- Staging PDF `GET` streams full document bytes before soak begins.
- Fixture data volume is large enough to exercise many file paths without
  depending on production storage.

## 4.3 Phase 38C: Synthetic Traffic and FD Sampling Harness

Status: Complete

Deliverables:

- Add a staging traffic driver that mixes:
  - metadata `GET`
  - PDF `HEAD`
  - PDF `GET`
  - repeated requests for hot documents
  - varied requests over a larger document corpus
- Add periodic FD snapshots per worker:
  - total descriptor count
  - `/dev/null` descriptor count
  - socket descriptor count
  - regular-file descriptor count
  - top descriptor targets grouped by `readlink`
- Capture request counters and failure classes:
  - metadata success/failure
  - PDF `HEAD` success/failure
  - PDF `GET` success/failure
  - first observed descriptor growth point
- Run two profiles:
  - realistic profile: `LimitNOFILE=1024`
  - accelerated profile: `LimitNOFILE=128` or `256`

Acceptance:

- The harness can reproduce or disprove monotonic `/dev/null` growth in a
  production-shaped staging environment.
- The output identifies whether growth is tied to metadata, `HEAD`, `GET`,
  worker startup, restart cycles, or elapsed time independent of traffic.
- Short-scale `boomhauer` Phase 10M soak remains available as a fast Arlen-only
  tripwire, but the staging harness becomes the authoritative reproduction
  route for `ARLEN-BUG-024`.

## 4.4 Phase 38D: Syscall Tracing and Root-Cause Isolation

Status: Complete; production root cause appears downstream

Deliverables:

- Run bounded tracing windows around the reproduction:

  ```bash
  strace -ff -tt -o /tmp/arlen-fd-trace \
    -e trace=open,openat,close,pipe,pipe2,dup,dup2,dup3 \
    <staging propane/app launch command>
  ```

- Correlate:
  - `/dev/null` `open/openat` calls
  - matching or missing `close` calls
  - process IDs and worker IDs
  - request timestamps
  - GNUstep pipe failures
- Compare traces for:
  - exact production Arlen commit
  - current Arlen
  - serialized dispatch
  - concurrent dispatch
  - `propane` launch
  - direct app launch without `propane`, if feasible

Acceptance:

- Identify the descriptor opener and the missing close or ownership transfer.
- Classify root cause as one of:
  - Arlen runtime bug
  - Arlen misuse of GNUstep API
  - GNUstep Base bug
  - `propane` worker setup bug
  - downstream app code bug
  - cross-layer interaction requiring Arlen mitigation
- Capture enough evidence to implement the fix without guessing.

Current 38D disposition:

- Production-safe inspection identified the downstream respondent autostart
  `NSTask` path as the likely descriptor opener.
- The path explains both the `/dev/null` target and the observed production
  growth increments.
- No Arlen file-response or `propane` worker-launch leak has been identified.

## 4.5 Phase 38E: Focused Runtime Fix

Status: Deferred to downstream app fix

Deliverables:

- Implement the smallest fix in the responsible layer once the leaking path is
  captured. Do not patch by guesswork based only on descriptor exhaustion
  symptoms.
- If the leak is in Arlen:
  - close descriptors deterministically at the ownership boundary
  - add failure-path cleanup
  - preserve GNUstep compatibility
- If the leak is in `propane`:
  - repair worker stdio/setup cleanup
  - document any changed propane accessories
  - update deploy/systemd examples if needed
- If the leak is in GNUstep Base:
  - create a minimal upstream reproducer
  - add an Arlen containment path if practical
  - document supported GNUstep version constraints or patch requirements
- If the leak is downstream:
  - document the downstream fix and add an Arlen diagnostic that makes the
    failure mode easier to identify.

Acceptance:

- The staging reproduction no longer shows monotonic `/dev/null` descriptor
  growth.
- PDF `GET` responses continue succeeding through the same or longer soak.
- Existing `fileBodyPath`, serialized-dispatch, and `propane` integration
  coverage remains passing.

Current 38E disposition:

- No focused Arlen runtime fix was applied because the reproduced leak mechanism
  is in downstream `StateCompulsoryPoolingAPI` `NSTask` ownership.
- The downstream fix should release or otherwise close the three null-device
  handles associated with each subprocess launch.

## 4.6 Phase 38F: Regression Gates and CI Artifacts

Status: Complete for Arlen-only tripwire; downstream reproduction gate remains
open

Deliverables:

- Extend or add an opt-in long-run lane that records:
  - FD target drift
  - `/dev/null` descriptor delta
  - file-response success rate
  - worker restart behavior
- Preserve generated artifacts under `build/release_confidence/phase38/`.
- Add focused regression tests if the root cause is reproducible without the
  full downstream app.
- Keep Phase 10M soak as the fast runtime tripwire and link it to Phase 38
  evidence.
- Add an explicit Phase 38 opt-in gate:
  - `make ci-phase38-fd-regression`
  - artifacts under `build/release_confidence/phase38/fd_regression`
  - summary file `phase38_fd_regression_summary.json`

Acceptance:

- A failing implementation reproduces the descriptor-growth signal in the
  regression lane or the staging harness.
- The fixed implementation passes the same lane.
- The artifact pack is reviewable without access to production.

Current 38F disposition:

- Complete for the Arlen-only tripwire. The downstream-app staging harness
  remains the authoritative reproduction route for `ARLEN-BUG-024`.

## 4.7 Phase 38G: Operational Diagnostics and Runbook

Status: Complete

Deliverables:

- Add or document an operator command to sample worker FD targets.
- Consider a health/metrics surface for:
  - open descriptor count
  - `/dev/null` descriptor count on Linux
  - configured open-file soft limit
  - warning threshold when descriptors approach exhaustion
- Update deployment/runbook docs with:
  - triage commands
  - safe restart workaround
  - why raising `LimitNOFILE` is mitigation only
  - staging reproduction instructions

Current 38G disposition:

- Added `tools/ops/sample_fd_targets.py` for Linux `/proc` FD target sampling.
- Updated `docs/PROPANE.md` and `docs/DEPLOYMENT.md` with descriptor exhaustion
  triage and safe restart guidance.

Acceptance:

- Operators can detect descriptor exhaustion before PDF responses fail.
- The documented triage path distinguishes app file lookup failures from
  worker-process descriptor exhaustion.

## 4.8 Phase 38H: Downstream Validation and Closeout

Status: Partial; closeout remains blocked on representative uptime validation

Deliverables:

- Validate the fix in staging with production-shaped traffic.
- Validate the fix in `StateCompulsoryPoolingAPI` outside peak traffic before
  production rollout.
- Update:
  - `docs/internal/OPEN_ISSUES.md`
  - `docs/STATECOMPULSORYPOOLINGAPI_REPORT_RECONCILIATION_2026-04-24.md`
  - `docs/STATUS.md`
  - release notes, if a shipped Arlen behavior changes
- Close `ARLEN-BUG-024` only after downstream confirms the production failure
  no longer recurs over a representative uptime window.

Acceptance:

- Downstream validation confirms stable file responses and stable `/dev/null`
  descriptor counts.
- Arlen docs record the root cause, fix commit, and permanent regression
  evidence.

Current 38H disposition:

- Partial. Downstream staging synthetic traffic passed on the incident Arlen ref,
  but production closeout is intentionally blocked until representative uptime
  validation or production-safe diagnostics confirm the `/dev/null` descriptor
  growth no longer recurs.

## 4.9 Phase 38I: Arlen FD-Pressure Hardening

Status: Complete

Deliverables:

- Add `propane` worker FD pressure warnings on Linux:
  - worker PID
  - current FD count
  - soft open-file limit
  - percent used
  - top FD targets when available
  - warning and critical threshold values
- Add optional FD-pressure worker recycling as propane accessories:
  - retire workers gracefully above a configured FD usage percent
  - retire workers gracefully above a configured absolute FD count
  - log that recycling is mitigation for a process leak, not a root-cause fix
- Improve descriptor-exhaustion diagnostics around pipe/helper creation
  failures:
  - include worker PID, FD count, soft limit, and likely descriptor exhaustion
    guidance when available
  - preserve existing GNUstep exception details
- Add a staging/debug request FD-delta mode:
  - sample FD count before and after each request
  - log request method/path, worker PID, and FD delta above a threshold
  - keep disabled by default
- Document subprocess best practices for Arlen apps:
  - apps that use `NSTask`, `NSPipe`, `NSFileHandle fileHandleWithNullDevice`,
    or raw `open` own descriptor lifetime
  - long-lived workers make small per-request leaks production-significant
  - prefer explicit release/close ownership in subprocess helpers

Acceptance:

- Operators get structured warnings before FD exhaustion breaks file responses.
- FD-pressure recycling can protect availability while the leaking app path is
  being fixed.
- Debug FD-delta logs can identify request paths that leak descriptors without
  requiring production stress traffic.
- Docs clearly distinguish Arlen hardening from downstream descriptor ownership.

Current 38I disposition:

- `propane` samples Linux worker FD pressure and emits structured lifecycle
  warning/critical events.
- `propane` supports optional FD-pressure worker retirement through propane
  accessories.
- Workers support disabled-by-default request FD-delta logs through
  `ARLEN_FD_DELTA_DEBUG` and `ARLEN_FD_DELTA_WARN`.
- `docs/PROPANE.md`, `docs/DEPLOYMENT.md`, and `docs/CLI_REFERENCE.md` document
  the diagnostics and subprocess descriptor ownership guidance.

## 5. Work Queue

The phases/subphases to work on, in order:

1. `38A`: provision the Debian libvirt VM with enough disk for traces.
2. `38B`: install GNUstep via `gnustep-cli-new`, authenticate `gh`, clone and
   stage `StateCompulsoryPoolingAPI`.
3. `38C`: build the synthetic traffic and FD sampling harness against the
   staging deployment.
4. `38D`: run bounded syscall tracing and identify the genuine descriptor
   opener.
5. `38E`: deferred to the downstream app fix for `NSTask` null-device handle
   ownership.
6. `38F`: maintain `make ci-phase38-fd-regression` as the Arlen-only tripwire
   and add a focused reproducer once the real leaking path is known.
7. `38G`: complete; keep operator diagnostics current as production evidence
   improves.
8. `38H`: partial; complete only after downstream confirms stable uptime or a
   root-cause fix ships and validates.
9. `38I`: complete; monitor the new FD-pressure lifecycle events and use
   request FD-delta debugging only for focused diagnostic windows.

## 6. Non-Goals

- Do not trace or stress the live production host as the primary reproduction
  environment.
- Do not handle or commit work GitHub credentials.
- Do not copy unnecessary production data into staging.
- Do not treat increasing `LimitNOFILE` as a fix.
- Do not relax the clang-based GNUstep toolchain requirement.

# Arlen Phase 38 Roadmap

Status: Planned  
Last updated: 2026-04-28

Related docs:

- `docs/OPEN_ISSUES.md`
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

The report is accepted as a real Arlen-facing production bug, but root cause is
not yet proven.

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

The leak is in the worker-process runtime path rather than the application file
lookup path. Possible sources include GNUstep Base internals, Arlen's use of
GNUstep APIs, `propane` worker launch or stdio handling, downstream controller
code invoked under Arlen, or an interaction between those layers.

## 3. Scope Summary

1. Phase 38A: staging infrastructure and environment parity.
2. Phase 38B: downstream app staging deployment and fixture corpus.
3. Phase 38C: synthetic traffic and descriptor sampling harness.
4. Phase 38D: syscall tracing and root-cause isolation.
5. Phase 38E: focused fix in the responsible layer.
6. Phase 38F: regression gates and CI artifact hardening.
7. Phase 38G: operational diagnostics and runbook updates.
8. Phase 38H: downstream validation and closeout.

## 4. Milestones

## 4.1 Phase 38A: Staging Infrastructure Parity

Status: Planned

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

Status: Planned

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

Status: Planned

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

Status: Planned

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

## 4.5 Phase 38E: Focused Runtime Fix

Status: Planned

Deliverables:

- Implement the smallest fix in the responsible layer.
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

## 4.6 Phase 38F: Regression Gates and CI Artifacts

Status: Planned

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

Acceptance:

- A failing implementation reproduces the descriptor-growth signal in the
  regression lane or the staging harness.
- The fixed implementation passes the same lane.
- The artifact pack is reviewable without access to production.

## 4.7 Phase 38G: Operational Diagnostics and Runbook

Status: Planned

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

Acceptance:

- Operators can detect descriptor exhaustion before PDF responses fail.
- The documented triage path distinguishes app file lookup failures from
  worker-process descriptor exhaustion.

## 4.8 Phase 38H: Downstream Validation and Closeout

Status: Planned

Deliverables:

- Validate the fix in staging with production-shaped traffic.
- Validate the fix in `StateCompulsoryPoolingAPI` outside peak traffic before
  production rollout.
- Update:
  - `docs/OPEN_ISSUES.md`
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

## 5. Work Queue

The phases/subphases to work on, in order:

1. `38A`: provision the Debian libvirt VM with enough disk for traces.
2. `38B`: install GNUstep via `gnustep-cli-new`, authenticate `gh`, clone and
   stage `StateCompulsoryPoolingAPI`.
3. `38C`: build the synthetic traffic and FD sampling harness against the
   staging deployment.
4. `38D`: run bounded syscall tracing and identify the genuine descriptor
   opener.
5. `38E`: implement the focused fix in Arlen, `propane`, GNUstep containment,
   or downstream code depending on evidence.
6. `38F`: convert the reproduction into permanent regression coverage and
   artifacts.
7. `38G`: add operator diagnostics and runbook updates.
8. `38H`: complete downstream validation and closeout documentation.

## 6. Non-Goals

- Do not trace or stress the live production host as the primary reproduction
  environment.
- Do not handle or commit work GitHub credentials.
- Do not copy unnecessary production data into staging.
- Do not treat increasing `LimitNOFILE` as a fix.
- Do not relax the clang-based GNUstep toolchain requirement.

# Open Issues

## ISSUE-012: Post-restart health probe could race service startup

- Status: `fixed upstream; awaiting downstream revalidation`
- Priority: `medium-high`
- Tracking ID: `ARLEN-BUG-032`
- Discovered: `2026-05-02`
- Reported by: `TaxCalculator`
- Last updated: `2026-05-02`
- Resolution: `arlen deploy release` now polls `/healthz` for a bounded
  startup window after runtime restart/reload instead of treating the first
  connection failure as final. The default window is 30 seconds with a
  1-second interval, configurable through `healthStartupTimeoutSeconds`,
  `healthStartupIntervalSeconds`, `--health-startup-timeout`, and
  `--health-startup-interval`.
- Verification:
  - `DeploymentIntegrationTests::testArlenDeployReleaseRetriesHealthAfterRuntimeRestart_ARLEN_BUG_032`
- Reconciliation note:
  `docs/internal/TAXCALCULATOR_HEALTH_STARTUP_RECONCILIATION_2026-05-02.md`

### Summary

After the runtime action succeeded, `deploy release` immediately probed
`/healthz` once. During a normal systemd restart, the service can be active and
the new workers can be starting while the socket is not accepting requests yet.
That produced a nonzero deploy result even though follow-up `deploy status`,
`deploy doctor`, and public health probes passed.

### Current Contract

1. Runtime restart/reload success is still required before health validation.
2. Post-runtime health validation polls for a bounded startup window.
3. Transient connection failures during the window are pending, not immediate
   deploy failure.
4. If the window expires, JSON reports `deployment_state =
   activated_health_unverified` with retry attempts, timeout, service state,
   and last health output.

## ISSUE-011: Runtime restart failure could leave `current` advanced

- Status: `fixed upstream; awaiting downstream revalidation`
- Priority: `high`
- Tracking ID: `ARLEN-BUG-031`
- Discovered: `2026-05-02`
- Reported by: `TaxCalculator`
- Last updated: `2026-05-02`
- Resolution: `arlen deploy release` now treats runtime restart/reload failure
  as an activation failure. If a previous active release exists, Arlen restores
  `releases/current` to that release and reports
  `deployment_state = activation_failed`; if rollback cannot be performed, the
  JSON error reports `deployment_state = stale_runtime`. Deploy targets and CLI
  invocations can also supply non-interactive runtime commands with
  `runtimeRestartCommand`, `runtimeReloadCommand`,
  `--runtime-restart-command`, and `--runtime-reload-command`.
- Verification:
  - `DeploymentIntegrationTests::testArlenDeployReleaseRestoresCurrentWhenRuntimeRestartFails_ARLEN_BUG_031`
- Reconciliation note:
  `docs/internal/TAXCALCULATOR_RUNTIME_ACTIVATION_RECONCILIATION_2026-05-02.md`

### Summary

For systemd-backed targets, `arlen deploy release` switched
`releases/current` before running the configured runtime action. If `systemctl
restart` failed because the deploy user lacked non-interactive authorization,
the command exited with an error but left `current` pointing at the new release.
The already-running service could continue serving the previous process image,
while status and health probes still looked healthy.

### Current Contract

1. Runtime action failure after activation must not silently leave the target in
   an apparently successful state.
2. If a previous active release exists, Arlen restores `current` to it and
   reports `deployment_state = activation_failed`.
3. If Arlen cannot restore `current`, it reports `deployment_state =
   stale_runtime` so operators know the symlink and running process may differ.
4. `deploy doctor` compares resolved runtime roots so benign
   `/releases/current` paths are distinguished from a true stale runtime.

## ISSUE-010: Non-RC downstream deploy path was not first-class

- Status: `fixed upstream; awaiting downstream revalidation`
- Priority: `medium`
- Tracking ID: `ARLEN-BUG-030`
- Discovered: `2026-05-02`
- Reported by: `TaxCalculator`
- Last updated: `2026-05-02`
- Resolution: deploy packaging now accepts first-class non-RC aliases
  `--skip-release-certification` and `--dev` in addition to the existing
  `--allow-missing-certification` compatibility spelling. The release artifact
  still records waived Phase 9J / Phase 10E status, and text-mode packaging
  emits an explicit warning when certification checks are waived.
- Verification:
  - `DeploymentIntegrationTests::testBuildReleaseRequiresPhase9JCertificationByDefault`
- Reconciliation note:
  `docs/internal/TAXCALCULATOR_PHASE9J_DEPLOY_RECONCILIATION_2026-05-02.md`

### Summary

`arlen deploy push` intentionally enforced Phase 9J certification by default,
but the documented downstream app-iteration path depended on the older
`--allow-missing-certification` spelling. That made the supported non-RC path
look like an emergency bypass instead of a deliberate app-iteration workflow.

### Current Contract

1. Phase 9J certification remains the default for release-candidate packaging.
2. Non-RC app iteration may explicitly waive certification with
   `--skip-release-certification`, `--dev`, or the compatibility spelling
   `--allow-missing-certification`.
3. Waived releases must record `certification_status = waived` and
   `json_performance_status = waived` in release metadata.
4. Text-mode packaging must warn when certification checks are waived.

## ISSUE-009: HTTP integration reserved-endpoint regression could hang

- Status: `fixed upstream; awaiting downstream revalidation`
- Priority: `high`
- Tracking ID: `ARLEN-BUG-029`
- Discovered: `2026-05-02`
- Reported by: `TaxCalculator`
- Last updated: `2026-05-02`
- Resolution: the HTTP integration request helper no longer waits
  indefinitely for spawned servers. Shell command capture now uses temporary
  files, server shutdown is bounded, stalled children are terminated/killed, and
  timeout diagnostics include the command, port, stdout, and stderr.
- Verification:
  - `make test-integration-filter TEST=HTTPIntegrationTests/testReservedOperabilityEndpointsCannotBeShadowedByCatchAllRoute`
- Reconciliation note:
  `docs/internal/TAXCALCULATOR_PHASE9J_DEPLOY_RECONCILIATION_2026-05-02.md`

### Summary

The reserved operability endpoint regression starts a prepared app and probes
`/healthz`, `/readyz`, `/metrics`, and a catch-all route. The shared helper
launched each server with `--once`, sent one `curl` request, and then waited
unconditionally for the server process to exit. If an operability endpoint did
not drive `--once` shutdown, the request could complete but the test process
would block forever in `waitUntilExit`.

### Current Contract

1. Integration tests that spawn servers must use bounded startup/request/shutdown
   waits.
2. Test failures must include enough process diagnostics to distinguish request
   failures, server startup failures, and shutdown stalls.
3. Spawned server processes must be cleaned up even when the request path fails.

## ISSUE-008: Phase 9J clean certification could run unit tests without `build/arlen`

- Status: `fixed upstream; awaiting downstream revalidation`
- Priority: `high`
- Tracking ID: `ARLEN-BUG-028`
- Discovered: `2026-05-01`
- Reported by: `TaxCalculator`
- Last updated: `2026-05-01`
- Resolution: the unit-test bundle now declares `$(ARLEN_TOOL)` as an explicit
  build prerequisite, so `make test-unit` and `make test-unit-filter` rebuild
  `build/arlen` after `make clean` before any unit regression shells out to the
  CLI. The ARLEN-BUG-027 regression also captures combined shell stdout/stderr
  and reports redirected JSON output size when the CLI exits before emitting a
  payload.
- Verification performed:
  - `make clean`
  - `make test-unit-filter TEST=BuildPolicyTests/testArlenBuildJSONCapturesLargeChildOutputWithoutPipeDeadlock_ARLEN_BUG_027`
  - `make test-unit`
  - `make ci-docs`
- Release-gate note:
  `make ci-release-certification` progressed past the original BuildPolicy unit
  blocker in this workspace, then failed and hung later in
  `HTTPIntegrationTests` endpoint probes under the sandboxed verification
  command. That later integration failure is not attributed to ARLEN-BUG-028.
- Reconciliation note:
  `docs/internal/TAXCALCULATOR_PHASE9J_RECONCILIATION_2026-05-01.md`

### Summary

`make ci-release-certification` starts from a clean build tree before running
the Phase 5E quality gate. That gate begins with `make test-unit`. The unit-test
bundle did not depend on `build/arlen`, even though
`BuildPolicyTests::testArlenBuildJSONCapturesLargeChildOutputWithoutPipeDeadlock_ARLEN_BUG_027`
executes `build/arlen build --json` directly. If no earlier target had rebuilt
the CLI after `make clean`, the test could fail before any JSON payload was
written and report only an empty redirected output file.

### Current Contract

1. Unit-test regressions that execute the Arlen CLI must have `build/arlen`
   available from the `make test-unit` dependency graph.
2. Focused unit-test reruns after `make clean` must not depend on stale or
   previously built CLI artifacts.
3. CLI JSON-output regressions must preserve enough shell diagnostics to
   distinguish missing binaries, early process exits, timeouts, and invalid JSON.

## ISSUE-007: Shell-command capture could deadlock on large child output

- Status: `resolved`
- Priority: `high`
- Tracking ID: `ARLEN-BUG-027`
- Discovered: `2026-04-30`
- Reported by: `TaxCalculator`
- Last updated: `2026-04-30`
- Resolution: `RunShellCaptureCommand()` now captures shell stdout and stderr
  into temporary files instead of `NSPipe`s, so long-running child commands can
  continue writing while Arlen waits for process exit. Captured output is read
  back after the process exits and temporary files are removed.
- Verification:
  - `BuildPolicyTests::testArlenBuildJSONCapturesLargeChildOutputWithoutPipeDeadlock_ARLEN_BUG_027`
- Reconciliation note:
  `docs/internal/TAXCALCULATOR_REPORT_RECONCILIATION_2026-04-30.md`

### Summary

`RunShellCaptureCommand()` launched a shell command with separate stdout and
stderr `NSPipe`s, waited for the child to exit, and only then drained the pipes.
If a child command wrote enough output to fill either pipe buffer, the child
blocked in `pipe_w` while Arlen waited in `waitUntilExit`. This could hang
`arlen deploy push --json` during the local release build before remote upload
started, especially when rebuilding Arlen emitted many compiler warnings.

### Current Contract

1. Shell-command capture must not depend on bounded pipe buffers for captured
   stdout/stderr.
2. Captured build output remains available to JSON callers after command exit.
3. Deploy build failures can reach the existing structured JSON error path
   instead of hanging before any payload is emitted.

## ISSUE-006: Remote deploy push could hang when SSH exited before tar completed

- Status: `resolved`
- Priority: `high`
- Tracking ID: `ARLEN-BUG-026`
- Discovered: `2026-04-30`
- Reported by: `TaxCalculator`
- Last updated: `2026-04-30`
- Resolution: remote upload now closes the parent pipe handles after launching
  the local `tar` and SSH tasks, monitors both child processes, and terminates
  `tar` when SSH exits first so `deploy push --json` can emit a structured
  transport error instead of waiting indefinitely.
- Verification:
  - `DeploymentIntegrationTests::testArlenDeployPushReportsRemoteUploadFailureWhenSSHExitsEarly_ARLEN_BUG_026`
- Reconciliation note:
  `docs/internal/TAXCALCULATOR_REPORT_RECONCILIATION_2026-04-30.md`

### Summary

When the SSH side of a remote upload exited early, for example because host-key
verification failed, `arlen deploy push <target> --json` could hang before
printing a JSON error. The local `tar` child could remain blocked writing the
release archive into the upload pipe while no SSH process was available to read
the stream.

### Current Contract

1. Remote upload must not wait indefinitely after SSH exits.
2. `--json` mode must return a structured `deploy_target_transport_failed`
   payload with captured transport output.
3. SSH stderr must remain visible through the transport diagnostics.

## ISSUE-005: Remote deploy SSH options were reordered before invocation

- Status: `resolved`
- Priority: `high`
- Tracking ID: `ARLEN-BUG-025`
- Discovered: `2026-04-30`
- Reported by: `TaxCalculator`
- Last updated: `2026-04-30`
- Resolution: `transport.sshOptions` now uses order-preserving manifest
  normalization instead of the sorted/deduplicated set helper used for
  order-insensitive fields.
- Verification:
  - `DeploymentIntegrationTests::testArlenDeployReleaseAndStatusOperateAgainstRemoteNamedTargetOverSSH`
- Reconciliation note:
  `docs/internal/TAXCALCULATOR_REPORT_RECONCILIATION_2026-04-30.md`

### Summary

`transport.sshOptions` was parsed through the generic string-array helper used
for set-like configuration values. That helper sorted and deduplicated entries,
which corrupted positional SSH argument pairs such as `("-F", "/dev/null")`.
The resulting invocation could become `ssh -F -oBatchMode=yes /dev/null ...`,
causing SSH to treat `-oBatchMode=yes` as the config-file path.

### Current Contract

1. `transport.sshOptions` preserves manifest order exactly after trimming empty
   string entries.
2. Positional SSH option pairs remain adjacent in the generated argv.
3. Order-insensitive manifest lists may still use sorted/deduplicated
   normalization where that behavior is intentional.

## ISSUE-004: Production workers leak `/dev/null` file descriptors until file responses fail

- Status: `open`
- Priority: `critical`
- Tracking ID: `ARLEN-BUG-024`
- Discovered: `2026-04-27`
- Reported by: `StateCompulsoryPoolingAPI`
- Last updated: `2026-04-28`
- Target follow-up: Phase 38
- Reconciliation note:
  `docs/internal/STATECOMPULSORYPOOLINGAPI_REPORT_RECONCILIATION_2026-04-24.md`
- Roadmap:
  `docs/internal/PHASE38_ROADMAP.md`

### Summary

Long-lived `StateCompulsoryPoolingAPI` workers served by Arlen through
`propane` accumulated hundreds of open `/dev/null` descriptors. At failure time
both workers were near the process soft open-file limit:

- worker `1096874`: `1023` open descriptors, about `970` targeting `/dev/null`
- worker `1096875`: `1023` open descriptors, about `967` targeting `/dev/null`
- process limit: soft `1024`, hard `524288`

Once descriptor exhaustion approached, document metadata endpoints continued to
respond, `HEAD` on PDF endpoints could still return `200`, but full
`GET` file responses failed. Arlen logged controller exceptions with the
GNUstep Base reason `Failed to create pipe to handle perform in thread`.

### Repro context (reported)

- Host: `iep-softwaredev`
- Observed: `2026-04-27` through `2026-04-28`
- App: `StateCompulsoryPoolingAPI`
- Arlen runtime path:
  `/opt/StateCompulsoryPoolingAPI/current/.third_party/Arlen`
- Running release:
  `/opt/StateCompulsoryPoolingAPI/releases/0049b4a5c85a70132ca43f7529650d2b8825c8d5-arlen734ac33`
- Process manager: `propane`
- Service: `scp-api-arlen.service`
- Request dispatch mode: `ARLEN_REQUEST_DISPATCH_MODE=serialized`
- Worker count: `2`
- Worker soft open-file limit: `1024`
- Representative endpoint:
  `/v1/states/OK/dockets/CD_2025-002412/documents/0ee415d6f4ae4ea355d421699aae0990f6070fb14c14e745c22c780d8b02b6c3/pdf`

### Current assessment

This is accepted as a real Arlen-facing production reliability bug. The visible
`ALNResponse.fileBodyPath` send path preflights and closes its per-request
descriptor, and the static file descriptor cache is capped and evicts by
closing entries, so this does not currently look like a simple missing close in
the happy-path file-send code.

The exception text comes from GNUstep Base, which means the observed crash point
is GNUstep failing to allocate an internal pipe after the process is already at
or near descriptor exhaustion. The source of the `/dev/null` leak is not yet
proven. It may be in GNUstep Base internals, Arlen's use of GNUstep APIs,
`propane` worker launch or stdio handling, downstream app code invoked under
Arlen, or an interaction between those components.

### Expected behavior

1. Arlen workers should not leak `/dev/null` descriptors over normal request
   handling.
2. Long-lived workers should continue serving dynamic `fileBodyPath` responses
   under normal uptime.
3. Arlen should surface actionable diagnostics when descriptor exhaustion is
   approaching.
4. If a helper/thread/pipe allocation fails, the failure path should be bounded
   and explicit rather than cascading into unrelated file-response failures.

### Workaround

Restarting the service clears the descriptors and temporarily restores PDF
downloads. Raising `LimitNOFILE` only delays recurrence and is not a fix.

### Current regression coverage

Phase 10M soak coverage now samples `/proc/$pid/fd`, records top FD targets,
tracks `/dev/null` descriptor drift, and sends validated `fileBodyPath`
responses. This is a tripwire, not a full reproduction of the reported
`propane` production shape.

Phase 38 staging on 2026-04-28 built `StateCompulsoryPoolingAPI` against the
reported production Arlen ref `734ac332693a`, launched it through `propane`
with two workers, `ARLEN_REQUEST_DISPATCH_MODE=serialized`, and a soft
open-file limit of `1024`, then ran synthetic PDF traffic:

- `4,000` full PDF `GET` responses: `0` failures
- `20,000` additional PDF `GET` responses discarded client-side: `0` failures
- final worker FD state: `25` FDs per worker, `1` `/dev/null` descriptor per
  worker
- bounded `strace` windows during file traffic observed `0` `/dev/null`
  opens

This disproves a simple per-file-response `/dev/null` leak in the staged
`fileBodyPath` path, but does not close the issue because production still
showed real descriptor exhaustion over uptime. Phase 38 therefore added:

- `tools/ops/sample_fd_targets.py` for production-safe FD target triage
- `make ci-phase38-fd-regression` for an opt-in Arlen-only FD drift evidence
  lane under `build/release_confidence/phase38/fd_regression`

The focused fix remains blocked until a leaking path is reproduced or captured
from production-safe diagnostics.

## ISSUE-003: File streaming responses sent successful headers with no body

- Status: `resolved`
- Priority: `critical`
- Tracking ID: `ARLEN-BUG-023`
- Discovered: `2026-04-24`
- Reported by: `StateCompulsoryPoolingAPI`
- Last updated: `2026-04-24`
- Resolution: `ALNResponse.fileBodyPath` responses now preflight the target
  file descriptor before successful headers are sent. Invalid or stale
  file-body metadata returns Arlen's fallback `500 Internal Server Error`
  instead of advertising a successful response with an undeliverable
  `Content-Length`.
- Verification:
  - `HTTPIntegrationTests::testCommittedFileBodyPathStreamsCompleteBody_ARLEN_BUG_023`
  - `HTTPIntegrationTests::testCommittedFileBodyPathHeadOmitsBody_ARLEN_BUG_023`
  - `HTTPIntegrationTests::testCommittedFileBodyPathPreflightFailureReturns500BeforeHeaders_ARLEN_BUG_023`
- Reconciliation note:
  `docs/internal/STATECOMPULSORYPOOLINGAPI_REPORT_RECONCILIATION_2026-04-24.md`

### Summary

When an application committed a response with `fileBodyPath` and
`fileBodyLength`, Arlen could send `200 OK` headers, including the expected
`Content-Length`, but send zero body bytes if file streaming failed. Browser
PDF viewers and proxy clients then saw a truncated successful transfer instead
of an application-level error.

### Impact

This broke public document download/viewing paths and any downstream client that
trusted Arlen's file streaming response contract.

### Current contract

1. GET file-body responses must stream the advertised byte count.
2. HEAD file-body responses must preserve headers and omit the body.
3. Failed file preflight must fail before successful headers are sent.

## ISSUE-002: Named-target deploy release rebuilds existing release ID instead of reusing it

- Status: `resolved`
- Priority: `high`
- Tracking ID: `ARLEN-BUG-022`
- Discovered: `2026-04-17`
- Target follow-up: Phase 36D
- Last updated: `2026-04-20`
- Resolution: `arlen deploy release <target> --release-id <id>` now reuses an
  existing local staged release for named remote targets before upload and
  packaged remote activation, avoiding the prior `release_exists` rebuild
  failure.
- Verification: Phase 36D added the focused named remote regression, and
  Phase 36K now includes it in `make phase36-confidence`.

### Summary

For named remote targets, `arlen deploy release <target> --release-id <existing-id>`
attempts to run `tools/deploy/build_release.sh` for the selected local release
ID before remote activation. If that release artifact was already built by
`arlen deploy push <target> --release-id <id>` or by a prior push flow, the
local release directory already exists and `build_release.sh` fails with
`release_exists`.

This contradicts the documented `arlen deploy release` contract, where a
selected `--release-id` should reuse an existing release artifact, or build it
only when missing.

### Repro context (reported)

- Downstream app: `OwnerConnect`
- Vendored Arlen path: `vendor/Arlen`
- Report date: `2026-04-17`
- CLI deploy contract version: `phase7g-agent-dx-contracts-v1`
- Deploy manifest version: `phase32-deploy-manifest-v1`
- Likely area: `tools/arlen.m`, named target remote release path

### Reproduction steps

1. Build and upload a named-target release:

   ```bash
   vendor/Arlen/build/arlen deploy push iep-ownerconnect --allow-missing-certification --json
   ```

2. Note the returned release ID, for example `20260417T213058Z`.

3. Attempt to activate the already-built and uploaded release:

   ```bash
   vendor/Arlen/build/arlen deploy release iep-ownerconnect --release-id 20260417T213058Z --allow-missing-certification --json
   ```

### Expected behavior

For a named remote target, `arlen deploy release <target> --release-id <id>`
should reuse the existing local release artifact when present, upload or reuse
the corresponding remote artifact as needed, and activate that release on the
remote host through the packaged remote `arlen deploy release`.

### Actual behavior before Phase 36D

The named-target command attempts to rebuild the same local release ID before
remote activation. Because the local release directory already exists, the build
step fails with:

```json
{
  "code": "release_exists",
  "message": "release already exists: /home/danboyd/git/OwnerConnect/build/deploy/targets/iep-ownerconnect/local-releases/20260417T213058Z"
}
```

### Impact

The intended push-then-release workflow cannot activate a specific already
pushed release ID through the named-target command. During the `2026-04-17`
OwnerConnect deployment, this blocked activation of pushed release
`20260417T213058Z`.

### Workaround used downstream

No Arlen code was changed locally in `OwnerConnect`. The deployment used:

```bash
vendor/Arlen/build/arlen deploy release iep-ownerconnect --allow-missing-certification --json
```

without `--release-id`, allowing Arlen to create, upload, and activate a fresh
release ID: `20260417T213200Z`.

### Suggested upstream fix

In the named-target deploy release path, check whether the selected local
release directory exists before invoking `build_release.sh`, matching the
non-remote release reuse behavior. If the artifact exists, skip the local build
step, upload or reuse the remote artifact as needed, and delegate activation to
the packaged remote `arlen deploy release`.

Regression coverage should include:

1. `arlen deploy push <target> --release-id X`
2. `arlen deploy release <target> --release-id X`
3. Expected result: no `release_exists` failure; release `X` is activated.

## ISSUE-001: Worker crash under normal HTTP traffic (`malloc_consolidate` / intermittent `502`)

- Status: `resolved`
- Priority: `critical`
- GitHub: https://github.com/danjboyd/Arlen/issues/1
- Last updated: `2026-02-25`

### Summary

Under normal API traffic behind nginx + `propane` (with `propane accessories` worker count > 1), workers intermittently abort with:

- `malloc_consolidate(): unaligned fastbin chunk detected`
- worker exit status `134` (and occasional segfaults observed in process lifecycle)

Externally this presents as intermittent or sustained `502 Bad Gateway` from nginx (`upstream prematurely closed connection`).

### Known-good / known-bad

- Known-good: `3876cd8481ba74b5812e52011b3bd9bf3bb80b0b`
- Known-bad: `08ea39abccd0` (still reproducible after timestamp formatter hardening)

### Repro context (reported)

- Host: `iep-softwaredev`
- OS: Debian 13 (trixie)
- Kernel: `6.12.73+deb13-amd64`
- Compiler: clang 19.1.7
- Runtime: nginx -> `propane` -> Arlen workers
- Traffic examples:
  - `/v1/states/OK/dockets/CD_2025-002412/documents/{document_id}/pdf`
  - `/v1/states/OK/dockets/CD_2025-002412/documents`

### Resolution summary

- Fix commit: `0920889` (`fix(http): stabilize serialized dispatch connection lifecycle`)
- Final fix behavior in serialized mode:
  - force one request per HTTP connection (`Connection: close`)
  - disable detached per-connection background thread handling
  - preserve explicit serialized behavior as opt-in (`requestDispatchMode=serialized`)
- Regression coverage:
  - `HTTPIntegrationTests::testProductionSerializedDispatchClosesHTTPConnections`
  - existing production serialization/concurrent-override tests remained passing

### Verification evidence

- Live consumer validation (StateCompulsoryPoolingAPI, production-like traffic on `iep-softwaredev`) confirmed issue resolved after upgrading to `0920889`.
- Arlen CI/local validation remained green after patch:
  - unit suite
  - integration suite
  - postgres integration suite

### Post-resolution watchpoints

1. Keep serialized-mode connection lifecycle deterministic when explicitly configured.
2. Require integration coverage for any future changes to HTTP connection persistence + worker dispatch interaction.
3. Re-run ASAN/UBSAN + endpoint traffic smoke during future runtime concurrency refactors.
4. Keep `tools/ci/run_runtime_concurrency_gate.sh` in pre-merge validation for HTTP/runtime lifecycle changes.
5. Track/update concurrency hardening baselines in `docs/internal/CONCURRENCY_AUDIT_2026-02-25.md`.

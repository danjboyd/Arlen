# Windows production proposal and private lifecycle proof

Status: **draft for architecture review**, based on main
`e26a755e0c250ec972c99eca9fb51a4259d48307`. Authorized scope: Dan's ask #89,
option yes. This document and its private fixture do not enable Windows production.
The `bin/propane` Windows refusal remains required until the acceptance gate below
passes and Dan approves the architecture. All proposed settings are propane accessories.

## Current source and issue #275

[Issue #275](https://github.com/danjboyd/Arlen/issues/275) describes the old MSYS2
`setsid` escape. At this base, `tools/ALNWindowsWatchChild.h` creates a kill-on-close
Job Object, launches suspended, assigns before resume, and monitors the original
watch parent handle. Assignment failure terminates the suspended child. The existing
`tests/fixtures/windows_watch_lifetime.ps1` checks app and build-error server lifetime.
Thus the reported old path is not grounds to add another containment implementation.
This change does not close #275 or claim its interactive Ctrl+C case was tested.
The new fixture below tests independent native primitives, not the watch helper.

## Proposed process ownership

One native propane supervisor owns generation state, the listener and an unnamed
kill-on-close job per generation. Launch each native worker suspended, assign to
its job, then resume. Assignment/resume failure fails closed; never run an uncontained
worker. Keep job handles non-inheritable and owned only by the supervisor. Restrict
inherited handles with an explicit allowlist; no inherited credentials or unrelated
pipe ends. Track processes by open process handles, not a later PID lookup.
Do not request job breakaway; test nested-job restrictions under the actual service
account before enabling support. Jobs are lifetime containment, not a security sandbox.

Keep application and jobs-worker roles separate, with independent health, restart
budgets and logs. Unexpected worker exit uses bounded exponential backoff and a
restart budget; exceeding it marks the service unhealthy rather than spinning.
Never kill by executable name or port discovery. All cleanup is restricted to owned
process handles/jobs. This matters on the VM shared with Performance Dashboard.

## Listener handoff decision

Recommended first implementation: the supervisor binds once with exclusive address
ownership and retains the listener across generations. Transfer a Winsock socket to
the specific suspended worker using `WSADuplicateSocket` plus an authenticated,
private control channel after the target PID exists. The worker imports the socket
and reports protocol version, generation and readiness before accepting work.
This requires a deliberate Windows runtime integration seam; it is not implemented
by this PR and a Winsock SOCKET must not be treated as a POSIX file descriptor.

Readiness must cover configuration validation, listener import and application
startup; process creation alone is insufficient. Old workers continue serving if
the candidate fails before commit. After candidate readiness, commit the generation
under one supervisor state transition, allow new accepts, and tell the old generation
to stop accepting. A brief accept overlap must be explicitly accepted or replaced
by a proven accept-permission handshake. The supervisor retains its own socket
until final shutdown. A supervisor crash can release the listener and kill workers;
zero downtime across supervisor crashes is not promised.

Alternative requiring Dan's decision: a stable front proxy owns the public listener
and generations bind separate private ports. It simplifies generation routing but
adds a deployed component and changes remote-address/trust behavior. Independently
rebinding the same public port is not a zero-downtime reload design.

## Drain, reload and stop protocol

Proposed states: starting -> ready -> serving -> draining -> exited. Each command
contains a protocol version, generation and request identifier; reject stale commands.
Readiness timeout aborts only the candidate. Reload is serialized; reject or coalesce
a second request instead of creating unbounded candidates. A failed post-commit
generation requires a documented rollback policy, never silent resurrection.

Draining disables new accepts and new keep-alive requests while finishing accepted
requests within an absolute deadline. SSE/WebSocket streams need an explicit bounded
policy and application-visible reconnect behavior. At deadline terminate the owned
job, wait for process exit and report forced termination. Shutdown first disables
reload/restart, stops admission, drains, terminates stragglers, then closes the listener.
No worker may keep the job handle alive. Windows SCM controls must be translated
to this protocol; console signals alone are not a service shutdown mechanism.

## Supervised jobs-worker

Stop claiming new jobs before draining active jobs. Allow current handlers to finish
within a separate jobs deadline; on forced exit rely on the queue backend's existing
lease/retry behavior. Do not promise exactly-once execution. Acceptance must include
lease expiry, retries, idempotent handlers, scheduler ownership and duplicate scheduler
prevention. Starting a replacement must not accidentally start two schedulers.
Clarify whether jobs-worker is a separate SCM service (recommended for independent
restart and deployment) or a role under the application supervisor before implementation.

## Windows service deployment proposal

Use a native SCM entrypoint with a dedicated least-privilege account, absolute paths,
explicit working directory, validated propane accessories and private state/log ACLs.
Never assume an interactive console, user PATH or shell profile. Report START_PENDING,
RUNNING, STOP_PENDING and STOPPED truthfully with bounded checkpoints/wait hints.
Keep handlers short; dispatch drain work to the supervisor loop. Define SCM restart
policy separately from child restart policy to avoid recovery storms.

Deployment stages an immutable versioned directory, verifies artifact/pins, validates
configuration privately, then requests a controlled generation switch. Keep previous
binaries/configuration for an explicit rollback. Schema migration compatibility is a
deployment gate, not an automatic side effect. Service installation/account creation,
ACL changes and deployment are out of this prototype's scope and require separate
authorization. No service was installed for these tests.

## Private fixture and evidence limits

Source: `tests/fixtures/windows_production_lifecycle/probe.c`; driver:
`tests/fixtures/windows_production_lifecycle/test_probe.py`. The C executable uses
Win32 Job Objects and named events scoped to its own process ID. These events use
the current token's default ACL and are only a local test mechanism, not a proposed
production authentication protocol. No ports, services, queue backends or Arlen
runtime modules are touched. The Python driver retains process handles for lifetime
assertions and cleans up only processes it created.

From this worktree, in PowerShell:

```powershell
./scripts/run_clang64.ps1 -InnerCommand 'source tools/source_gnustep_env.sh && mkdir -p build/v040-lifecycle && clang -std=c11 -Wall -Wextra -Werror tests/fixtures/windows_production_lifecycle/probe.c -o build/v040-lifecycle/probe.exe'
python tests/fixtures/windows_production_lifecycle/test_probe.py build/v040-lifecycle/probe.exe
```

Six focused cases cover owner force-termination, explicit job closure, cooperative
stop, deadline termination of an uncooperative child, an unready candidate leaving
the previous owner alive, and a ready replacement surviving old-owner shutdown.
The last two exercise process/event ordering only: **no listener handoff, HTTP drain,
real queue recovery, SCM integration or production readiness is proven**.
This private fixture is manually run and does not add or repurpose a CI lane.

## Acceptance gates before changing the production refusal

| Area | Required evidence |
| --- | --- |
| Containment | Assignment/resume failures, inherited-handle audit, descendants, nested jobs, owner crash and forced tree kill leave no owned processes/ports |
| Listener | Exclusive bind, authenticated target-specific import, malformed/stale control rejection, failed candidate rollback, repeated reload under concurrent traffic |
| Drain | Slow request, keep-alive, SSE, WebSocket and deadline cases; no newly admitted work after drain acknowledgement |
| Jobs | Active lease interrupted/retried, backend outage, bounded restart, no duplicate scheduler, forced-stop outcomes recorded |
| SCM | Real noninteractive account start/stop/recovery/reboot and session logout; status/wait-hint accuracy; install/uninstall/rollback separately authorized |
| Security | Private channel/state/log ACLs, no secret command lines/logs, inherited handles allowlisted, artifact integrity and config validation |
| Compatibility | Existing Linux/macOS behavior, GNUstep clang/runtime pins, package/install contracts and Windows development/watch regressions remain green |
| Release | Maintained regression tests, representative Windows CI, CI alignment/branch-protection guidance and operator/CLI/getting-started docs updated together |

## Decisions requested from Dan before implementation

1. Approve supervisor-owned Winsock transfer, or select a stable front proxy.
2. Approve native SCM supervisor and the initial supported Windows/service-account matrix.
3. Choose jobs-worker service ownership and single-scheduler policy.
4. Set drain/readiness/restart budgets and long-lived stream behavior as propane accessories.
5. Decide acceptable accept overlap and rollback semantics after generation commit.

These decisions block shared implementation, not this draft PR. The public guides,
production guards, runtime ABI/pins, shared runner definitions and Core/MVC/modules
remain unchanged. The draft is a concrete review artifact rather than an enablement claim.

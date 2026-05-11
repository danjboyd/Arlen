# Propane Manager

`propane` is Arlen's production process manager.

It runs prefork worker processes, restarts failed workers, and supports rolling reloads.

## Multi-Worker State Contract

`propane` runs multiple worker processes for production workloads. Those
workers do not share Objective-C heap memory. Process-local dictionaries,
arrays, singleton service instances, and in-memory adapter instances can diverge
from worker to worker.

Request-spanning application state that must survive worker changes, worker
restarts, rolling reloads, deploys, or multiple hosts must live in shared
durable storage. Safe production patterns include signed cookie session state
plus a database-backed user lookup, SQLite or file-backed state for a
single-host pilot, PostgreSQL for multi-worker and multi-host production, and
durable first-party adapters where available.

Do not rely on sticky sessions as the default correctness model for normal HTTP
apps. Sticky routing can be useful operationally, but Arlen's production state
contract is that user, role, scenario, workflow, and other mutable domain data
is durable outside a worker process.

The explicit app-level declaration is:

```plist
state = {
  durable = YES;
  mode = "database";
  target = "default";
};
```

Existing deploy database contracts can also satisfy the first warning version.
Without either signal, `arlen doctor --env production`, `arlen deploy doctor`,
and production deploy planning warn when `propaneAccessories.workerCount > 1`.

## Usage

```bash
./bin/propane --env production
```

Run from an app root, or set:
- `ARLEN_APP_ROOT`
- `ARLEN_FRAMEWORK_ROOT`

## Propane Accessories

Define in `config/app.plist`:

```plist
propaneAccessories = {
  workerCount = 4;
  gracefulShutdownSeconds = 10;
  respawnDelayMs = 250;
  reloadOverlapSeconds = 1;
  jobWorkerCount = 0;
  jobWorkerCommand = "";
  jobWorkerRespawnDelayMs = 250;
};
```

Runtime socket controls:

```plist
listenBacklog = 128;
connectionTimeoutSeconds = 30;
enableReusePort = NO;
requestDispatchMode = "concurrent";
runtimeLimits = {
  maxConcurrentHTTPSessions = 256;
  maxConcurrentWebSocketSessions = 256;
};
```

`requestDispatchMode` defaults to `"concurrent"`.
Set `requestDispatchMode = "serialized"` to keep deterministic serialized execution while still
honoring HTTP keep-alive negotiation.

When `workerCount > 1`, `propane` enables `SO_REUSEPORT` automatically for worker binds.
When HTTP session limit is exceeded, workers return deterministic overload diagnostics
(`503 Service Unavailable` with `X-Arlen-Backpressure-Reason: http_session_limit`).
When websocket session limit is exceeded, workers return deterministic overload diagnostics
(`503 Service Unavailable` with `X-Arlen-Backpressure-Reason: websocket_session_limit`).

Cluster controls:

```plist
cluster = {
  enabled = NO;
  name = "default";
  expectedNodes = 1;
  emitHeaders = NO;
};
```

`nodeID` is optional in config; when omitted, Arlen derives a node ID from hostname.

## Signals

- `HUP`: rolling reload (new workers first, then old workers drain)
- `TERM` / `INT`: graceful shutdown

## CLI Overrides

- `--workers <n>`
- `--host <addr>`
- `--port <port>`
- `--env <name>`
- `--pid-file <path>`
- `--graceful-shutdown-seconds <n>`
- `--respawn-delay-ms <n>`
- `--reload-overlap-seconds <n>`
- `--listen-backlog <n>`
- `--connection-timeout-seconds <n>`
- `--cluster-enabled`
- `--cluster-name <name>`
- `--cluster-node-id <id>`
- `--cluster-expected-nodes <n>`
- `--job-worker-cmd <command>`
- `--job-worker-count <n>`
- `--job-worker-respawn-delay-ms <n>`
- `--no-respawn`

Async worker options supervise non-HTTP background processes under the same manager.

For first-party jobs module deployments, point `--job-worker-cmd` or `ARLEN_PROPANE_JOB_WORKER_COMMAND` at `framework/bin/jobs-worker` so the supervised process reuses Arlen's app-root build and worker-mode contracts.

Environment fallbacks:

- `ARLEN_PROPANE_JOB_WORKER_COMMAND`
- `ARLEN_PROPANE_JOB_WORKER_COUNT`
- `ARLEN_PROPANE_JOB_WORKER_RESPAWN_DELAY_MS`
- `ARLEN_PROPANE_LIFECYCLE_LOG` (optional path for structured lifecycle diagnostics copy)
- `ARLEN_CLUSTER_ENABLED`
- `ARLEN_CLUSTER_NAME`
- `ARLEN_CLUSTER_NODE_ID`
- `ARLEN_CLUSTER_EXPECTED_NODES`
- `ARLEN_MAX_HTTP_SESSIONS`
- `ARLEN_MAX_WEBSOCKET_SESSIONS`
- `ARLEN_REQUEST_DISPATCH_MODE` (`concurrent` by default; set `serialized` to force deterministic serialized dispatch)

`propane` exports resolved cluster values to worker processes, so CLI overrides are consistently applied at runtime.

## Deploy Handoff

The deploy-to-`propane` seam is explicit.

Packaged release manifests now carry a `propane_handoff` object describing:

- the packaged `propane` manager binary
- the packaged `jobs-worker` binary
- the `release.env` file that supplies activation/runtime paths
- the config key that owns `propane accessories`
- the default deploy runtime action used for release lifecycle changes

The handoff contract now has two explicit stages:

- the shipped manifest stays release-relative so the payload can move cleanly
  between hosts (`ARLEN-BUG-017`)
- release activation rewrites `release.env` against the target host path, and
  `propane` prefers the packaged app runtime binary whenever it already exists
  in the release app root (`ARLEN-BUG-018`)

That split of ownership is deliberate:

- `arlen deploy` packages releases, activates them, and records the handoff
- `propane` owns process supervision and all `propane accessories`

This keeps deployment orchestration and production process management separate
while still giving operators one deterministic packaged contract.

## Lifecycle Diagnostics Contract

`propane` emits machine-readable lifecycle lines to stdout:

```text
propane:lifecycle event=<event_name> manager_pid=<pid> key=value ...
```

When `ARLEN_PROPANE_LIFECYCLE_LOG` is set, the same lines are also appended to that file.

Stable event coverage includes:

- manager lifecycle: `manager_started`, `manager_reload_requested`, `manager_reload_started`,
  `manager_reload_completed`, `manager_shutdown_requested`, `manager_stopping`, `manager_stopped`
- worker churn: `worker_started`, `worker_exited`, `async_worker_started`, `async_worker_exited`
- stop semantics: `http_worker_stop_requested` / `http_worker_stopped` and
  `async_worker_stop_requested` / `async_worker_stopped`

Stable churn/stop fields include:

- `reason` (for example `respawn_after_exit`, `reload_retire_generation_1`, `signal_term`)
- `status` and `exit_reason` (`exit_0`, `exit_1`, `signal_9`, etc.)
- `restart_action` (`none` or `respawn`)

Stable FD-pressure events include:

- `worker_fd_pressure_warning`
- `worker_fd_pressure_critical`
- `worker_fd_pressure_retire_requested`

Stable FD-pressure fields include:

- `pid`
- `fd_count`
- `fd_soft_limit`
- `fd_usage_percent`
- `fd_remaining`
- `top_fd_targets`

## FD-Pressure Propane Accessories

On Linux, `propane` can sample worker descriptor pressure through `/proc` and
emit lifecycle diagnostics before descriptor exhaustion breaks request handling.
The checks are disabled only by setting thresholds to `0`; warning diagnostics
default on.

Supported propane accessories:

- `workerFDWarnPercent` default `80`
- `workerFDCriticalPercent` default `90`
- `workerFDRetirePercent` default `0`, disabled
- `workerFDRetireCount` default `0`, disabled
- `workerFDCheckSeconds` default `15`

Equivalent CLI/env overrides:

```bash
propane --worker-fd-warn-percent 80 \
  --worker-fd-critical-percent 90 \
  --worker-fd-retire-percent 95 \
  --worker-fd-retire-count 950 \
  --worker-fd-check-seconds 15
```

```bash
ARLEN_PROPANE_WORKER_FD_WARN_PERCENT=80
ARLEN_PROPANE_WORKER_FD_CRITICAL_PERCENT=90
ARLEN_PROPANE_WORKER_FD_RETIRE_PERCENT=95
ARLEN_PROPANE_WORKER_FD_RETIRE_COUNT=950
ARLEN_PROPANE_WORKER_FD_CHECK_SECONDS=15
```

FD-pressure retirement is an availability mitigation. It recycles a worker that
is already under descriptor pressure; it does not fix the application or runtime
path that opened the descriptors.

## Descriptor Exhaustion Triage

For Linux/GNUstep deployments, operators can sample live worker file descriptor
targets without sending traffic:

```bash
python3 /path/to/Arlen/tools/ops/sample_fd_targets.py \
  --pgrep boomhauer-app \
  --json
```

For app-specific release names, use a narrower process pattern, for example:

```bash
python3 /path/to/Arlen/tools/ops/sample_fd_targets.py \
  --pgrep state-compulsory-pooling-api
```

The sampler reports total descriptors, `/dev/null` descriptors, socket
descriptors, regular-file descriptors, the open-file soft limit, and the top
`readlink` targets under `/proc/$pid/fd`. Treat either of these as warning
signals:

- worker descriptors above `85%` of the soft open-file limit
- hundreds of `/dev/null` descriptors in one worker

For file-response incidents, compare the application log with the sampler:

- missing or stale application paths usually show low worker FD pressure
- descriptor exhaustion shows high total descriptors and often transport errors
  such as GNUstep pipe-creation failures

Raising `LimitNOFILE` delays exhaustion but does not fix a descriptor leak.
The safe short-term mitigation is a controlled worker/service restart while
retaining FD snapshots and logs for root-cause analysis.

## Request FD-Delta Debugging

For staging or short production-safe diagnostic windows, workers can log a
request when the process FD count rises during that request:

```bash
ARLEN_FD_DELTA_DEBUG=1
ARLEN_FD_DELTA_WARN=3
```

The log event is `http.request.fd_delta` and includes method, path, worker PID,
status, route/controller/action when known, `fd_before`, `fd_after`, and
`fd_delta`. Keep this disabled by default; it samples `/proc/self/fd` around
each request and is intended to identify leaking request paths.

Apps that launch subprocesses with `NSTask`, `NSPipe`,
`NSFileHandle fileHandleWithNullDevice`, or raw `open` own descriptor lifetime.
Long-lived Arlen workers make small per-request leaks production-significant,
so subprocess helpers should use explicit close/release ownership and should be
validated with FD-count regression checks.

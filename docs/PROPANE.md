# Propane Manager

`propane` is Arlen's production process manager.

It runs prefork worker processes, restarts failed workers, and supports rolling reloads.

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
requestDispatchMode = "serialized";
runtimeLimits = {
  maxConcurrentHTTPSessions = 256;
  maxConcurrentWebSocketSessions = 256;
};
```

`requestDispatchMode = "serialized"` forces one request per HTTP connection (`Connection: close`)
so production workers keep the stable serialized execution path by default.

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
  emitHeaders = YES;
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
- `ARLEN_REQUEST_DISPATCH_MODE` (`serialized` by default in production; set `concurrent` to opt in)

`propane` exports resolved cluster values to worker processes, so CLI overrides are consistently applied at runtime.

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

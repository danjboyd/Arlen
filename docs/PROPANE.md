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
runtimeLimits = {
  maxConcurrentHTTPSessions = 256;
  maxConcurrentWebSocketSessions = 256;
};
```

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
- `ARLEN_CLUSTER_ENABLED`
- `ARLEN_CLUSTER_NAME`
- `ARLEN_CLUSTER_NODE_ID`
- `ARLEN_CLUSTER_EXPECTED_NODES`
- `ARLEN_MAX_HTTP_SESSIONS`
- `ARLEN_MAX_WEBSOCKET_SESSIONS`

`propane` exports resolved cluster values to worker processes, so CLI overrides are consistently applied at runtime.

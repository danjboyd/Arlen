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
```

When `workerCount > 1`, `propane` enables `SO_REUSEPORT` automatically for worker binds.

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
- `--job-worker-cmd <command>`
- `--job-worker-count <n>`
- `--job-worker-respawn-delay-ms <n>`
- `--no-respawn`

Async worker options supervise non-HTTP background processes under the same manager.

Environment fallbacks:

- `ARLEN_PROPANE_JOB_WORKER_COMMAND`
- `ARLEN_PROPANE_JOB_WORKER_COUNT`
- `ARLEN_PROPANE_JOB_WORKER_RESPAWN_DELAY_MS`

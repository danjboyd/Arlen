# Deployment Guide

This guide describes the shared Arlen deployment model plus the supported Linux
and Windows production paths. Native Windows runtime and service-wrapper
details also live in `docs/WINDOWS_RUNTIME_STORY.md`.

Arlen is designed for deployment behind a reverse proxy.

## 1. Runtime Boundary

- Arlen handles HTTP application runtime.
- TLS termination is out of scope for framework runtime.
- Use nginx/apache/Caddy in front of Arlen for public ingress.

## 2. Server Roles

- `boomhauer`: development server
- `propane`: production manager

All production manager settings are referred to as "propane accessories".

## 3. Production Baseline Configuration

Recommended app/runtime defaults for production:

- `logFormat = "json"`
- `serveStatic = NO` (behind reverse proxy/CDN)
- explicit `requestLimits`
- explicit observability policy (`observability.tracePropagationEnabled`, `observability.healthDetailsEnabled`, `observability.readinessRequiresStartup`, `observability.readinessRequiresClusterQuorum`)
- explicit propane accessories (`workerCount`, shutdown/reload timings)
- explicit cluster settings when running multi-node (`cluster.enabled`, `cluster.name`, `cluster.expectedNodes`, `cluster.observedNodes`)

API-only mode (`apiOnly = YES`, or `ARLEN_API_ONLY=1`) defaults to:

- `serveStatic = NO`
- `logFormat = "json"`

## 4. Built-In Health Contract

Arlen provides built-in fallback health endpoints:

- `GET /healthz` -> `200 ok\n`
- `GET /readyz` -> `200 ready\n`
- `GET /livez` -> `200 live\n`
- `GET /clusterz` -> `200` JSON cluster/runtime contract payload

Use these for LB probes and deployment readiness checks.

JSON signal payloads are available for health/readiness when requested:

- `GET /healthz` with `Accept: application/json` (or `?format=json`)
- `GET /readyz` with `Accept: application/json` (or `?format=json`)

Strict readiness mode:

- set `observability.readinessRequiresStartup = YES` (or `ARLEN_READINESS_REQUIRES_STARTUP=1`)
- before startup completes, `GET /readyz` returns deterministic `503 not_ready`

Cluster quorum readiness mode:

- set `observability.readinessRequiresClusterQuorum = YES` (or `ARLEN_READINESS_REQUIRES_CLUSTER_QUORUM=1`)
- in multi-node mode, `GET /readyz` returns deterministic `503 not_ready` when `cluster.observedNodes < cluster.expectedNodes`
- JSON readiness payload includes `checks.cluster_quorum` diagnostics (`ok`, `required_for_readyz`, `status`, `observed_nodes`, `expected_nodes`)

Cluster status payload (`/clusterz`) includes distributed-runtime diagnostics:

- `cluster.quorum` summary (`status`, `met`, observed/expected nodes)
- `coordination` section with capability boundaries for cross-node routing/fanout/jobs/cache semantics

When `cluster.emitHeaders = YES` (default), responses include:

- `X-Arlen-Cluster`
- `X-Arlen-Node`
- `X-Arlen-Worker-Pid`
- `X-Arlen-Cluster-Status`
- `X-Arlen-Cluster-Observed-Nodes`
- `X-Arlen-Cluster-Expected-Nodes`

## 5. Immutable Release Artifact Workflow

Deployment helper scripts are provided under `tools/deploy/`.

### 5.1 Build a release artifact

```bash
tools/deploy/build_release.sh \
  --app-root /path/to/app \
  --framework-root /path/to/Arlen \
  --releases-dir /path/to/app/releases
```

Optional coding-agent planning mode:

```bash
tools/deploy/build_release.sh \
  --app-root /path/to/app \
  --framework-root /path/to/Arlen \
  --releases-dir /path/to/app/releases \
  --release-id rel-001 \
  --dry-run \
  --json
```

`--dry-run --json` emits a deterministic machine payload (`phase7g-agent-dx-contracts-v1`) with:

- `workflow = deploy.build_release`
- `status = planned`
- resolved app/framework/release paths and target release id

Result layout:

```text
releases/<release-id>/
  app/
  framework/
  metadata/
```

Release metadata includes:

- `metadata/release.env`
- `metadata/README.txt` with migrate/run commands

### 5.2 Activate a release

```bash
tools/deploy/activate_release.sh \
  --releases-dir /path/to/app/releases \
  --release-id <release-id>
```

This switches `releases/current` and updates `releases/current.release-id`.

### 5.3 Run migration step (explicit)

From activated release payload on Linux/MSYS:

```bash
cd /path/to/app/releases/current/app
/path/to/app/releases/current/framework/bin/arlen migrate --env production
```

From PowerShell on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File C:\path\to\app\releases\current\framework\tools\deploy\windows\invoke_release_migrate.ps1 -ReleasesDir C:\path\to\app\releases
```

### 5.4 Start runtime from activated release

```bash
ARLEN_APP_ROOT=/path/to/app/releases/current/app \
ARLEN_FRAMEWORK_ROOT=/path/to/app/releases/current/framework \
ARLEN_PROPANE_CONTROL_FILE=/path/to/app/releases/current/app/tmp/propane.control \
/path/to/app/releases/current/framework/bin/propane --env production --pid-file /path/to/app/releases/current/app/tmp/propane.pid
```

From PowerShell on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File C:\path\to\app\releases\current\framework\tools\deploy\windows\start_release.ps1 -ReleasesDir C:\path\to\app\releases
```

Runtime control on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File C:\path\to\app\releases\current\framework\tools\deploy\windows\send_release_control.ps1 -ReleasesDir C:\path\to\app\releases -Action reload
powershell -ExecutionPolicy Bypass -File C:\path\to\app\releases\current\framework\tools\deploy\windows\send_release_control.ps1 -ReleasesDir C:\path\to\app\releases -Action term
```

## 6. Container-First Runbook (Baseline)

Minimum container deployment path:

1. Build release artifact during image build or CI packaging.
2. Set `ARLEN_APP_ROOT` and `ARLEN_FRAMEWORK_ROOT` to active release paths.
3. Run migration command before switching traffic.
4. Start `propane --env production` as container entrypoint.
5. Probe `/readyz` and `/livez` for rollout/health checks.

## 7. VM/systemd Runbook (Linux Baseline)

Use release symlink plus explicit environment wiring in service unit.

Example service command:

```text
ExecStart=/path/to/app/releases/current/framework/bin/propane --env production
Environment=ARLEN_APP_ROOT=/path/to/app/releases/current/app
Environment=ARLEN_FRAMEWORK_ROOT=/path/to/app/releases/current/framework
```

Recommended systemd behavior:

- `Restart=always`
- `TimeoutStopSec` aligned with propane graceful shutdown accessories
- pre-start migrate step via separate unit or deployment orchestration

Reference files now ship under `tools/deploy/systemd/`:

- `arlen@.service`
- `arlen-debug.conf`
- `site.env.example`
- `site.debug.env.example`

Recommended pattern:

- keep one base production unit template
- enable incident-only debug mode with a drop-in plus a second env file
- avoid maintaining separate long-lived "normal" and "debug" service units

Detailed Linux steps:

- `docs/SYSTEMD_RUNBOOK.md`

## 8. Windows Service Wrapper Baseline

Windows uses the same immutable release artifact layout, but the supported
orchestration entrypoints are the packaged PowerShell helpers instead of
`systemd`.

Recommended baseline:

- keep a stable `releases` directory per app
- run `invoke_release_migrate.ps1` before traffic switch
- have your Windows service wrapper execute `start_release.ps1 -ReleasesDir <path>`
- use `send_release_control.ps1 -Action reload` for rolling refreshes
- use `send_release_control.ps1 -Action term` for graceful shutdown
- keep `ARLEN_BASH_PATH` set when MSYS `bash.exe` lives outside the default paths

Arlen now also exposes a Windows service-install CLI on top of that contract:

```powershell
arlen service install --mode runtime
arlen service uninstall --mode runtime
```

Developer-box `boomhauer` services are also supported explicitly:

```powershell
arlen service install --mode dev
arlen service uninstall --mode dev
```

Autodiscovery defaults:

- `runtime`: when invoked from inside a supported immutable release layout,
  `--releases-dir` and `--name` can be omitted
- `dev`: when invoked from inside a supported app root, `--app-root` and
  `--name` can be omitted

Default Windows log locations:

- runtime: `<releases-dir>\service\propane.stdout.log` and
  `<releases-dir>\service\propane.stderr.log`
- dev: `<app-root>\tmp\service\boomhauer.stdout.log` and
  `<app-root>\tmp\service\boomhauer.stderr.log`

Current backend note:

- Windows service installation currently uses `NSSM`
- install it with `winget install NSSM.NSSM` when not already present
- Arlen also probes the Winget package cache when the `nssm` alias link is not
  present
- live install/uninstall relaunch through UAC from a non-elevated PowerShell
  session when the current user can elevate

## 9. Rollback Workflow

Rollback to specific release:

```bash
tools/deploy/rollback_release.sh \
  --releases-dir /path/to/app/releases \
  --release-id <previous-id>
```

Rollback to most recent non-current release:

```bash
tools/deploy/rollback_release.sh --releases-dir /path/to/app/releases
```

After rollback symlink switch, restart/reload `propane` from `releases/current`.

## 10. Automated Runbook Validation

Phase 3C adds automated smoke validation for the documented release runbook:

```bash
tools/deploy/smoke_release.sh \
  --app-root examples/tech_demo \
  --framework-root /path/to/Arlen
```

Or via make target:

```bash
make deploy-smoke
```

Standalone operability validation for a running server:

```bash
tools/deploy/validate_operability.sh --base-url http://127.0.0.1:3000
```

This validates:

- release build
- activation
- text + JSON health/readiness probe contracts from activated payload
- rollback
- text + JSON health/readiness probe contracts after rollback

## 11. Current Capability Snapshot

| Capability | Current state | Verification |
| --- | --- | --- |
| Rolling reload in `propane` | Available | Integration-tested |
| Cluster identity/status contract (`/clusterz` + response headers) | Available (with quorum + coordination depth) | Unit + integration tests |
| Immutable release artifact workflow | Available | Deployment integration test |
| Explicit migration step in runbook | Available | Scripted release metadata + docs |
| Readiness/liveness endpoint contract | Available | Unit + integration tests |
| Rollback workflow | Available | Deployment integration test |
| Container + Linux systemd baseline guidance | Available | Documented runbook baseline |
| Windows release helper / service-wrapper guidance | Available | `docs/WINDOWS_RUNTIME_STORY.md` + packaged PowerShell helpers |
| Deployment runbook smoke validation | Available | `tools/deploy/smoke_release.sh` + integration test |

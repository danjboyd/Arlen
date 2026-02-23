# Deployment Guide

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

This switches `releases/current` symlink.

### 5.3 Run migration step (explicit)

From activated release payload:

```bash
cd /path/to/app/releases/current/app
/path/to/app/releases/current/framework/build/arlen migrate --env production
```

### 5.4 Start runtime from activated release

```bash
ARLEN_APP_ROOT=/path/to/app/releases/current/app \
ARLEN_FRAMEWORK_ROOT=/path/to/app/releases/current/framework \
/path/to/app/releases/current/framework/bin/propane --env production
```

## 6. Container-First Runbook (Baseline)

Minimum container deployment path:

1. Build release artifact during image build or CI packaging.
2. Set `ARLEN_APP_ROOT` and `ARLEN_FRAMEWORK_ROOT` to active release paths.
3. Run migration command before switching traffic.
4. Start `propane --env production` as container entrypoint.
5. Probe `/readyz` and `/livez` for rollout/health checks.

## 7. VM/systemd Runbook (Baseline)

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

## 8. Rollback Workflow

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

## 9. Automated Runbook Validation

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

## 10. Current Capability Snapshot

| Capability | Current state | Verification |
| --- | --- | --- |
| Rolling reload in `propane` | Available | Integration-tested |
| Cluster identity/status contract (`/clusterz` + response headers) | Available (with quorum + coordination depth) | Unit + integration tests |
| Immutable release artifact workflow | Available | Deployment integration test |
| Explicit migration step in runbook | Available | Scripted release metadata + docs |
| Readiness/liveness endpoint contract | Available | Unit + integration tests |
| Rollback workflow | Available | Deployment integration test |
| Container + systemd baseline guidance | Available | Documented runbook baseline |
| Deployment runbook smoke validation | Available | `tools/deploy/smoke_release.sh` + integration test |

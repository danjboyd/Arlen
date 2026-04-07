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

Arlen reserves its built-in operability endpoints ahead of app route dispatch:

- `GET /healthz` -> `200 ok\n`
- `GET /readyz` -> `200 ready\n`
- `GET /livez` -> `200 live\n`
- `GET /metrics` -> `200` Prometheus text exposition payload
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

For app-operator workflows, prefer the first-class `arlen deploy` wrapper:

```bash
./build/arlen deploy plan --app-root /path/to/app --allow-missing-certification --json
./build/arlen deploy push --app-root /path/to/app --allow-missing-certification --json
./build/arlen deploy release --app-root /path/to/app --release-id rel-20260407 --allow-missing-certification --json
```

`arlen deploy push` writes `releases/<id>/metadata/manifest.json` using
`phase29-deploy-manifest-v1`. `arlen deploy release` reuses that manifest,
runs packaged migrations when present, activates `releases/current`, and can
probe `/healthz` when `--base-url` is supplied. Packaged framework payloads now
also include `framework/tools/deploy/validate_operability.sh`, so
`arlen deploy doctor --base-url ...` works from an activated packaged release
without needing a source checkout beside it.

Additional deploy CLI helpers:

- `arlen deploy status --releases-dir /path/to/app/releases --json`
- `arlen deploy rollback --releases-dir /path/to/app/releases --service arlen@myapp --runtime-action reload --json`
- `arlen deploy doctor --releases-dir /path/to/app/releases --base-url http://127.0.0.1:3000 --json`
- `arlen deploy logs --service arlen@myapp --lines 200`

Focused deploy confidence lane:

```bash
make phase29-confidence
```

That lane exercises deploy manifest generation, push/release/status/rollback/
doctor/logs flows, and a reserved-endpoint smoke app where `/:token` must not
shadow `/healthz`, `/readyz`, or `/metrics`.

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

Packaged release payloads now include:

- app config/templates/public/modules/source files needed for runtime inspection
- `app/db/migrations` for the documented `arlen migrate` step
- prebuilt app server binary at `app/.boomhauer/build/boomhauer-app`
- runtime wrapper scripts plus `framework/build/arlen` and `framework/build/boomhauer`

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

The packaged release includes `app/db/migrations`, so this command no longer
depends on copying migration files into the artifact after build time.

### 5.4 Start runtime from activated release

```bash
ARLEN_APP_ROOT=/path/to/app/releases/current/app \
ARLEN_FRAMEWORK_ROOT=/path/to/app/releases/current/framework \
/path/to/app/releases/current/framework/bin/propane --env production
```

`propane` now runs directly from the packaged release payload. It does not
require a full Arlen checkout when `ARLEN_FRAMEWORK_ROOT` points at
`releases/current/framework`.

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

Reference files now ship under `tools/deploy/systemd/`:

- `arlen@.service`
- `arlen-debug.conf`
- `site.env.example`
- `site.debug.env.example`

Recommended pattern:

- keep one base production unit template
- enable incident-only debug mode with a drop-in plus a second env file
- avoid maintaining separate long-lived "normal" and "debug" service units

Detailed steps:

- `docs/SYSTEMD_RUNBOOK.md`

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
- startup through packaged `framework/bin/propane`
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

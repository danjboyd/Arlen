# Deployment Guide

Arlen is designed for deployment behind a reverse proxy.

This guide now has two layers:

- the currently implemented Phase 29 release workflow
- the Phase 32 deployment-target contract that future remote deploy work will
  enforce

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

## 4. Phase 32 Deployment Target Contract

Phase 29 gave Arlen a first-class release workflow. Phase 32 defines the
target-compatibility contract that future remote deploy work must enforce.

### 4.1 Platform Profiles

Deployment support is defined by a platform profile, not by CPU architecture
alone.

A profile should encode:

- OS family
- CPU architecture
- runtime family
- toolchain/runtime variant where relevant

Examples:

- `macos-arm64-apple-foundation`
- `macos-x86_64-apple-foundation`
- `linux-x86_64-gnustep-clang`
- `windows-x86_64-gnustep-clang64`
- `windows-x86_64-gnustep-msvc`

Why this matters:

- Apple Foundation and GNUstep are different runtime families
- the same Objective-C source may still diverge in behavior across those
  families
- deployment safety depends on the full runtime boundary, not only on whether
  the CPU is `arm64` or `x86_64`

### 4.2 Deployment Support Levels

Arlen should classify deployment plans into these levels:

- `supported`
  - local build profile matches the remote target profile exactly
- `experimental`
  - remote rebuild is explicitly enabled and the target falls within a
    narrowly allowed best-effort class
- `unsupported`
  - profile or runtime-family mismatch is outside the supported contract

Current intended v1 policy:

- same-profile deployment: supported
- GNUstep-to-GNUstep remote rebuild across profile differences: experimental
- Apple Foundation to GNUstep deployment: unsupported

### 4.3 Project Deployment Configuration

Future app-owned deployment config should stay declarative.

Recommended target fields:

- target identifier
- host/address metadata
- platform profile
- runtime strategy
- release path
- healthcheck target
- build/deploy hooks
- reserved `propane accessories` fields for future production manager handoff

Illustrative shape:

```yaml
deployment:
  targets:
    production:
      host: app1.example.com
      profile: linux-x86_64-gnustep-clang
      runtime_strategy: managed
      release_path: /opt/arlen/apps/myapp
      healthcheck: /healthz
      hooks:
        pre_activate: []
        post_activate: []
      propane_accessories:
        workerCount: 4
```

This is a contract model, not yet a claim that every field above is already
implemented in the current CLI.

### 4.4 Runtime Strategies

For GNUstep-backed deployment targets, Arlen should treat runtime strategy as
explicit configuration rather than implicit host state.

Recommended strategies:

- `system`
  - the target already carries a compatible runtime/toolchain
- `managed`
  - Arlen deploys and manages the expected runtime on the host
- `bundled`
  - the release artifact carries the runtime beside the app

The default production bias should stay toward deterministic runtime control,
not toward guessing that arbitrary host packages are compatible.

### 4.5 Deploy Doctor Architecture

`arlen deploy doctor` should evolve into a probe-based system.

Probe result classes:

- `error`: deployment cannot proceed
- `warn`: deployment may work, but does not match the preferred contract
- `info`: characterization detail
- `action`: concrete remediation guidance

Probe categories should include:

- local profile resolution
- target profile resolution
- runtime presence and version
- release-root and filesystem readiness
- service-manager readiness
- environment/secrets completeness
- operability endpoint expectations
- remote rebuild capability when enabled

### 4.6 Remote Host Readiness

For target-aware remote deployment, doctor should verify at least:

- target OS family and architecture
- target runtime family and platform profile
- writable release/shared/temp paths
- required service-manager or lifecycle support
- runtime availability or install requirements
- environment/secrets completeness
- network/healthcheck assumptions
- current operability contract (`/healthz`, `/readyz`, `/livez`, `/metrics`)

For Linux and Windows production targets, doctor should also be able to answer:

- whether the host already satisfies the chosen runtime strategy
- whether the deploy user can activate and restart the release
- whether the release layout and health probes are meaningful on that host

### 4.7 Remote Rebuild Contract

Remote rebuild should never be a silent fallback.

If Arlen later supports `--allow-remote-rebuild`, doctor should require:

- explicit operator opt-in
- a functional remote build chain, not just tool presence
- compile and link validation for a minimal Objective-C/Foundation program
- stronger warnings when the local and remote profiles differ

The intended near-term support boundary is:

- GNUstep-to-GNUstep remote rebuild: possible best-effort path
- Apple Foundation to GNUstep remote rebuild: not a supported v1 path

### 4.8 `propane` Handoff Boundary

Activated releases now carry an explicit `propane` handoff contract.

Release manifests expose `propane_handoff` metadata with:

- `manager = propane`
- packaged `propane` binary path
- packaged `jobs-worker` binary path
- `release.env` path
- `accessories_config_key = propaneAccessories`
- default runtime action for deploy-driven lifecycle changes

This is the boundary between responsibilities:

- `arlen deploy`
  - packages the release
  - records deployment and `propane` handoff metadata
  - activates releases and triggers lifecycle actions
- `propane`
  - owns process supervision
  - owns worker lifecycle
  - owns `propane accessories`

The deploy product should not become a second process manager. It hands off to
`propane` through the packaged metadata and environment contract.

## 5. Built-In Health Contract

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

## 6. Immutable Release Artifact Workflow

Deployment helper scripts are provided under `tools/deploy/`.

For app-operator workflows, prefer the first-class `arlen deploy` wrapper:

```bash
./build/arlen deploy plan --app-root /path/to/app --allow-missing-certification --json
./build/arlen deploy push --app-root /path/to/app --allow-missing-certification --json
./build/arlen deploy release --app-root /path/to/app --release-id rel-20260407 --allow-missing-certification --json
```

`arlen deploy push` writes `releases/<id>/metadata/manifest.json` using
`phase32-deploy-manifest-v1`. The manifest now records deployment metadata for
the local profile, target profile, runtime strategy, compatibility status, and
remote rebuild requirements. Manifest runtime/helper paths are now stored
release-relative so the package stays portable after ship/move
(`ARLEN-BUG-017`). `arlen deploy release` reuses that manifest, runs packaged
migrations when present, activates `releases/current`, rewrites
`metadata/release.env` against the activated release root, and can probe
`/healthz` when `--base-url` is supplied. Packaged framework payloads now also
include `framework/tools/deploy/validate_operability.sh`, so
`arlen deploy doctor --base-url ...` works from an activated packaged release
without needing a source checkout beside it.

Target-aware deploy options:

- `--target-profile <profile>` records the intended deployment target profile
- `--runtime-strategy <system|managed|bundled>` records how the runtime should
  be satisfied on the target
- `--allow-remote-rebuild` opts into best-effort GNUstep cross-profile rebuild
  planning
- `--remote-build-check-command <shell>` is required by `deploy release` when
  the manifest represents an experimental remote rebuild target

Additional deploy CLI helpers:

- `arlen deploy status --releases-dir /path/to/app/releases --json`
- `arlen deploy rollback --releases-dir /path/to/app/releases --service arlen@myapp --runtime-action reload --json`
- `arlen deploy doctor --releases-dir /path/to/app/releases --base-url http://127.0.0.1:3000 --json`
- `arlen deploy logs --service arlen@myapp --lines 200`

Focused deploy confidence lane:

```bash
make phase29-confidence
make phase31-confidence
make phase32-confidence
```

That lane exercises deploy manifest generation, push/release/status/rollback/
doctor/logs flows, and a reserved-endpoint smoke app where `/:token` must not
shadow `/healthz`, `/readyz`, or `/metrics`.

`phase31-confidence` adds the packaged-release closeout checks that were still
missing from Phase 29:

- packaged release smoke through `tools/deploy/smoke_release.sh --json`
- packaged `propane` startup plus `deploy doctor --base-url`
- packaged `jobs-worker --once`
- synthetic manifest-base-name to `.exe` fallback validation

`phase32-confidence` adds the target-aware deploy closeout checks:

- supported same-profile release metadata
- experimental GNUstep cross-profile remote rebuild metadata
- fail-closed remote build-check gating in `deploy doctor`
- successful release activation after an explicit remote build-check command
- rollback-candidate deployment metadata in `deploy status`
- rollback-source deployment metadata in `deploy rollback`
- packaged `propane_handoff` manifest and `release.env` contract
- explicit rejection of unsupported cross-runtime deployment targets

Windows support statement for deployment:

- packaged release and deploy workflows are now available on MSYS2 `CLANG64`
  as a preview path
- the preview path is verified by the Windows self-hosted workflow and the
  repo-native `phase31-confidence` lane
- this is still not a general production support claim for Windows hosts

### 6.1 Build a release artifact

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
- prebuilt app server binary at `app/.boomhauer/build/boomhauer-app` (or
  `.exe` on Windows preview builds)
- runtime wrapper scripts plus `framework/build/arlen` and
  `framework/build/boomhauer` (with `.exe` suffixes preserved when present)

Release metadata includes:

- `metadata/release.env`
- `metadata/README.txt` with migrate/run commands
- manifest-backed runtime/helper paths for `arlen`, `boomhauer`, `propane`,
  `jobs-worker`, and the operability helper
- release-relative manifest paths for all packaged runtime/helper entries
  (`ARLEN-BUG-017`)

### 6.2 Activate a release

```bash
tools/deploy/activate_release.sh \
  --releases-dir /path/to/app/releases \
  --release-id <release-id>
```

This switches `releases/current` symlink.

Activation also rewrites `metadata/release.env` so:

- the shipped manifest can stay portable in transit
- the activated environment file points at the target host's actual release
  root
- `deploy status`, `deploy doctor`, and `propane` handoff metadata stay honest
  after the release moves to a different machine/path

### 6.3 Run migration step (explicit)

From activated release payload:

```bash
cd /path/to/app/releases/current/app
/path/to/app/releases/current/framework/build/arlen migrate --env production
```

The packaged release includes `app/db/migrations`, so this command no longer
depends on copying migration files into the artifact after build time.

### 6.4 Start runtime from activated release

```bash
ARLEN_APP_ROOT=/path/to/app/releases/current/app \
ARLEN_FRAMEWORK_ROOT=/path/to/app/releases/current/framework \
/path/to/app/releases/current/framework/bin/propane --env production
```

`propane` now runs directly from the packaged release payload. It does not
require a full Arlen checkout when `ARLEN_FRAMEWORK_ROOT` points at
`releases/current/framework`, and the packaged manifest is authoritative for
runtime/helper path resolution across Unix and Windows preview builds.

When the release app root already carries `app/.boomhauer/build/boomhauer-app`,
both `propane` and `jobs-worker` now prefer that shipped binary even if the
release app root is no longer a mutable source checkout (`ARLEN-BUG-018`).

## 7. Container-First Runbook (Baseline)

Minimum container deployment path:

1. Build release artifact during image build or CI packaging.
2. Set `ARLEN_APP_ROOT` and `ARLEN_FRAMEWORK_ROOT` to active release paths.
3. Run migration command before switching traffic.
4. Start `propane --env production` as container entrypoint.
5. Probe `/readyz` and `/livez` for rollout/health checks.

## 8. VM/systemd Runbook (Baseline)

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

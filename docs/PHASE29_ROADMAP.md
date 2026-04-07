# Arlen Phase 29 Roadmap

Status: In Progress
Last updated: 2026-04-07

Related docs:
- `docs/STATUS.md`
- `docs/README.md`
- `docs/DEPLOYMENT.md`
- `docs/SYSTEMD_RUNBOOK.md`
- `docs/CLI_REFERENCE.md`
- `docs/ARLEN_CLI_SPEC.md`
- `docs/DOCUMENTATION_POLICY.md`

Reference inputs reviewed for this roadmap:
- `docs/DEPLOYMENT.md`
- `docs/SYSTEMD_RUNBOOK.md`
- `docs/CLI_REFERENCE.md`
- `docs/ARLEN_CLI_SPEC.md`
- `tools/deploy/build_release.sh`
- `tools/deploy/activate_release.sh`
- `tools/deploy/rollback_release.sh`
- `tools/deploy/smoke_release.sh`
- `tools/deploy/validate_operability.sh`
- `bin/propane`
- `bin/jobs-worker`
- `tests/integration/DeploymentIntegrationTests.m`
- downstream request:
  - `OwnerConnect/docs/bugs/2026-04-07-arlen-feature-request-deploy-command.md`

## 0. Starting Point

Arlen already ships meaningful deployment primitives:

- immutable release packaging via `tools/deploy/build_release.sh`
- release activation and rollback helpers
- production worker supervision through `propane`
- deployment and systemd runbooks
- release smoke and operability verification scripts

What Arlen does not yet ship is a first-class deployment product.

Today the operator experience still requires knowing which lower-level script
to call, which runtime path to trust, how release metadata hangs together, and
where framework responsibility stops and host glue begins.

Phase 29 exists to turn those pieces into a coherent `arlen deploy` workflow.

## 0.1 Phase 29 North Star

Make Arlen deployment feel like a supported release product rather than a
collection of scripts.

That means:

- an app team can plan, ship, activate, verify, inspect, and roll back a
  release through first-party CLI commands
- release artifacts are self-consistent with the documented production runbook
- deploy output is useful to both humans and coding agents
- the first shipping slice focuses on rollout orchestration, not on becoming a
  general infrastructure-provisioning framework

## 1. Objective

Add a first-party `arlen deploy` command family on top of Arlen's existing
release/runtime scripts and metadata contracts.

Phase 29 should deliver:

- a plan/build/push/release/status/rollback deploy CLI
- stable machine-readable release and rollout metadata
- health verification and rollback contracts integrated into the CLI
- release/runtime diagnostics good enough for ordinary operators
- clear scope boundaries around host bootstrap, secrets, and service-manager
  integration

Phase 29 is a deployment-product phase, not a replacement for SSH, systemd, or
full infrastructure management systems.

## 1.1 Why Phase 29 Exists

Recent downstream deployment work exposed a real gap between Arlen's runtime
capability and its operator UX:

- release artifacts existed, but the path from package to running service was
  still too manual
- rollout knowledge lived partly in shell scripts and partly in docs
- deploy verification and rollback were documented, but not owned by a single
  CLI surface
- host bootstrap and secret completeness checks were not discoverable enough
  for ordinary operators

The framework already has the core mechanisms. The missing piece is a
deliberate operator-facing product around them.

## 1.2 Design Principles

- Release-first:
  - optimize around immutable release build, ship, activate, verify, rollback
- Thin orchestration over honest primitives:
  - reuse `tools/deploy/*` and runtime scripts where they already express the
    right contract
- Deterministic operator output:
  - every deploy command should have stable human-readable output and a
    machine-readable mode where appropriate
- Fail closed:
  - missing secrets, invalid release state, failed health checks, and rollback
    hazards should stop the workflow explicitly
- Keep host bootstrap narrow:
  - support common Linux/systemd patterns without turning Arlen into a generic
    configuration-management tool
- Respect framework/app boundaries:
  - Arlen owns the deployment contract; apps still own environment-specific
    policy and secret values
- Preserve boring recovery:
  - active release, previous release, health check result, and rollback command
    should always be easy to inspect

## 2. Scope Summary

1. `29A`: deploy contract and CLI foundation.
2. `29B`: release manifest and deploy metadata normalization.
3. `29C`: `arlen deploy plan`.
4. `29D`: `arlen deploy push`.
5. `29E`: `arlen deploy release`.
6. `29F`: `arlen deploy status`.
7. `29G`: `arlen deploy rollback`.
8. `29H`: `arlen deploy doctor`.
9. `29I`: `arlen deploy logs`.
10. `29J`: health and operability reservation hardening.
11. `29K`: focused verification lanes and confidence artifacts.
12. `29L`: docs and release closeout.

## 2.1 Recommended Rollout Order

1. `29A`
2. `29B`
3. `29C`
4. `29E`
5. `29F`
6. `29G`
7. `29D`
8. `29H`
9. `29I`
10. `29J`
11. `29K`
12. `29L`

That order gets the local release/orchestration contract stable before Arlen
commits to remote transport convenience, deeper diagnostics, and full docs
closeout.

## 3. Scope Guardrails

- Do not make `arlen deploy init` a hard prerequisite for shipping Phase 29.
- Do not require Arlen to become a full package manager or cloud provisioner.
- Do not hide irreversible schema migration risk behind optimistic messaging.
- Do not make SSH the only possible transport contract, but it is acceptable as
  the first supported remote transport.
- Do not store secrets in release artifacts.
- Do not claim built-in health endpoints are universally safe until route
  precedence is actually enforced in runtime behavior.
- Do not make release/runtime verification depend on a source checkout once a
  packaged release is built.

## 4. Detailed Subphases

### 29A. Deploy Contract and CLI Foundation

Status: Delivered on 2026-04-07

Goal:
- introduce the `arlen deploy` command family and establish naming, output, and
  argument conventions

Deliverables:
- `arlen deploy <subcommand>` command parsing in `tools/arlen.m`
- shared deploy command helpers for environment/site/host resolution
- initial JSON contract shape for deploy subcommands
- explicit CLI spec updates for the new command family

Acceptance:
- `arlen deploy --help` and per-subcommand help are stable and documented
- deploy commands use consistent exit-code behavior with existing Arlen CLI

### 29B. Release Manifest and Deploy Metadata Normalization

Status: Delivered on 2026-04-07

Goal:
- make release metadata a first-class contract instead of loosely coupled text
  files and shell conventions

Deliverables:
- structured release manifest under `metadata/`
- normalized fields for release id, app revision, framework revision, build
  time, migration inventory, and health verification contract
- helper readers for deploy/status/rollback flows

Acceptance:
- deploy commands no longer scrape ad hoc text when structured metadata should
  exist
- release metadata is deterministic and versioned

### 29C. `arlen deploy plan`

Status: Delivered on 2026-04-07

Goal:
- provide a deterministic dry-run of what a rollout will do before any host
  mutation occurs

Deliverables:
- local plan command wrapping release packaging inputs and validation
- resolved release id, artifact paths, migration inventory, required secret
  checks, and health verification targets
- human-readable and machine-readable output modes

Acceptance:
- operator can see what will ship, what is missing, and what rollback target is
  expected before running a release

### 29D. `arlen deploy push`

Status: Delivered on 2026-04-07

Goal:
- ship a built release artifact to a target host without activating it

Deliverables:
- packaging + checksum + upload orchestration
- unpack into release directory on target host
- initial SSH transport support
- noninteractive mode suitable for CI use

Acceptance:
- pushed release is present and verifiable on the target host but not yet
  active

### 29E. `arlen deploy release`

Status: Delivered on 2026-04-07

Goal:
- own the activation path end-to-end

Deliverables:
- explicit migration step
- release activation
- runtime restart/reload orchestration
- health verification and deploy summary output

Acceptance:
- successful release ends with active release id, service status, health result,
  previous release id, and rollback command

### 29F. `arlen deploy status`

Goal:
- give operators a single command for current rollout state

Deliverables:
- active release id
- previous release id
- runtime/service state
- health endpoint contract
- migration/inventory summary
- release metadata visibility

Acceptance:
- status output is enough to answer “what is live right now?” without manual
  symlink and journald inspection

### 29G. `arlen deploy rollback`

Goal:
- make rollback a first-class, verified action instead of a runbook footnote

Deliverables:
- rollback target selection
- activation of previous release
- runtime restart/reload
- post-rollback health verification
- warnings for irreversible migration risk where Arlen can detect it honestly

Acceptance:
- rollback is scriptable, observable, and health-verified

### 29H. `arlen deploy doctor`

Goal:
- expose server-side deployment diagnostics through a first-party CLI

Deliverables:
- release layout checks
- runtime binary integrity checks
- app config completeness checks
- database connectivity validation
- health endpoint availability checks
- runtime-user and filesystem sanity checks where discoverable

Acceptance:
- common deployment misconfiguration paths produce targeted diagnostics instead
  of generic runtime failure

### 29I. `arlen deploy logs`

Goal:
- shorten the path from “deployment failed” to actionable context

Deliverables:
- journald/systemd log access helpers where applicable
- release metadata/log pointer output
- propane lifecycle diagnostic shortcuts

Acceptance:
- operator can reach the active release metadata and runtime logs from one CLI
  entrypoint

### 29J. Health and Operability Reservation Hardening

Goal:
- make deploy verification targets trustworthy in production

Deliverables:
- route-precedence protection or equivalent reservation for built-in health
  endpoints
- explicit health verification contract owned by deploy metadata
- operability guidance updates when reservation is not universal

Acceptance:
- `arlen deploy release` can rely on a documented probe contract without
  downstream route-shadow surprises

### 29K. Focused Verification and Confidence Artifacts

Goal:
- keep the deploy product regression-resistant

Deliverables:
- focused deploy CLI tests
- release metadata/manifest tests
- remote-transport and rollback integration coverage where feasible
- confidence artifacts for deploy runbook verification

Acceptance:
- Phase 29 ships with repo-native verification lanes that fail closed on deploy
  contract regressions

### 29L. Docs and Release Closeout

Goal:
- close the gap between deploy behavior, CLI docs, runbooks, and examples

Deliverables:
- updates to `README.md`, `docs/README.md`, `docs/DEPLOYMENT.md`,
  `docs/SYSTEMD_RUNBOOK.md`, and `docs/CLI_REFERENCE.md`
- API/spec docs for the deploy command family
- completed roadmap and status updates

Acceptance:
- operator-facing docs reflect the shipped deploy behavior with no hidden
  script archaeology required

## 5. Post-Phase Follow-Up (Explicitly Deferred)

- `arlen deploy init` for host bootstrap and service-user creation
- PostgreSQL role/database provisioning helpers
- richer secrets editing/storage UX
- non-SSH transport plugins
- distro-specific package/runtime installers

Those are valuable, but they should follow a stable rollout/status/rollback
product rather than block it.

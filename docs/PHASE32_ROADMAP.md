# Arlen Phase 32 Roadmap

Status: complete on 2026-04-14
Last updated: 2026-04-14

Related docs:
- `docs/STATUS.md`
- `docs/README.md`
- `docs/DEPLOYMENT.md`
- `docs/CLI_REFERENCE.md`
- `docs/ARLEN_CLI_SPEC.md`
- `docs/DOCUMENTATION_POLICY.md`
- `docs/APPLE_PLATFORM.md`
- `docs/WINDOWS_CLANG64.md`
- `docs/TOOLCHAIN_MATRIX.md`

Reference inputs reviewed for this roadmap:
- `docs/PHASE29_ROADMAP.md`
- `docs/PHASE30_ROADMAP.md`
- `docs/PHASE31_ROADMAP.md`
- `docs/DEPLOYMENT.md`
- `docs/CLI_REFERENCE.md`
- `docs/ARLEN_CLI_SPEC.md`
- `docs/APPLE_PLATFORM.md`
- `docs/WINDOWS_CLANG64.md`
- `docs/TOOLCHAIN_MATRIX.md`
- `tools/arlen.m`
- `tools/deploy/build_release.sh`
- `tools/deploy/activate_release.sh`
- `tools/deploy/rollback_release.sh`
- `tools/deploy/validate_operability.sh`

## 0. Starting Point

Phase 29 turned Arlen deployment into a first-class local release product:

- `arlen deploy` owns release planning, packaging, activation, status,
  rollback, doctor, and logs
- immutable release manifests exist
- health and operability probes are reserved and deterministic
- the Linux production baseline is documented

Phase 30 then established macOS as a separate Apple-runtime platform, and
Phase 31 closed the packaged Windows `CLANG64` preview path enough for honest
release/deploy verification.

What Arlen still does not have is an explicit target-compatibility and
production-host contract across those platform families.

Today the docs explain how to package and activate a release, but they do not
yet give app teams one authoritative answer to these questions:

- when is a deployment target actually supported?
- what counts as the "same" deployment environment?
- when is remote rebuild allowed, and under what risk level?
- what should `arlen deploy doctor` prove before activation is allowed?
- how should future project-owned deploy target configuration be modeled?

Phase 32 exists to define that contract before more deploy automation lands.

Follow-up scope added after the initial closeout:

- deploy should keep owning release packaging, migration, activation,
  rollback, and verification, but not secret management
- deploy target config should explicitly declare database dependency mode
  instead of making doctor infer host-local requirements from DSN shape alone
- `arlen deploy doctor` should validate the declared database mode and fail
  clearly when a required host-local database service is unavailable
- release activation should own `ARLEN_APP_ROOT` and
  `ARLEN_FRAMEWORK_ROOT`, while shared host env should stay focused on secrets
  and host-local settings
- developer/operator docs should call out the stale shared-env override
  failure mode that showed up during the `parker-app` migration

## 0.1 Phase 32 North Star

Make Arlen production deployment target-aware and honest.

That means:

- deployment compatibility is evaluated against an explicit platform profile,
  not only against CPU architecture
- app projects declare production targets and runtime expectations in a stable
  config model
- `arlen deploy doctor` grows from release-layout validation into a structured
  target-readiness and capability probe system
- remote rebuild is possible only as an explicit downgraded mode with strong
  validation and warnings
- Apple Foundation and GNUstep remain clearly separated deployment families

## 1. Objective

Define and document the target-aware deployment contract that future Arlen
deploy work will enforce.

Phase 32 should deliver:

- a support matrix based on platform profiles instead of vague
  same-architecture claims
- a deploy-target config model for app projects
- a local-vs-remote compatibility classification contract
- a structured doctor probe architecture for local and remote readiness checks
- explicit host-readiness requirements for Linux and Windows production targets

This phase is intentionally about deploy architecture and operator truth before
deeper execution work such as remote transport, managed runtime installation,
or `propane` integration expansion.

## 1.1 Design Principles

- Fail closed on compatibility:
  - unsupported target profiles should be rejected explicitly
- Distinguish support levels clearly:
  - `supported`, `experimental`, and `unsupported` are different contracts
- Treat runtime family as a first-class boundary:
  - Apple Foundation and GNUstep are not interchangeable
- Keep remote rebuild opt-in:
  - source rebuild across profile boundaries must never be the silent default
- Prefer probeable capability contracts:
  - doctor should report structured evidence, not ad hoc prose
- Preserve the existing Phase 29 release workflow:
  - new target-aware checks should extend the deploy product, not replace it

## 2. Scope Summary

1. `32A`: deployment contract and support matrix.
2. `32B`: project deployment configuration model.
3. `32C`: local planning and platform-profile resolution.
4. `32D`: deploy doctor probe framework.
5. `32E`: remote host readiness checks.
6. `32F`: remote rebuild validation and warnings.
7. `32G`: release artifact and manifest contract expansion.
8. `32H`: deploy execution and activation flow on target hosts.
9. `32I`: rollback and release status depth.
10. `32J`: `propane` integration boundary and production manager handoff.
11. `32K`: confidence lanes and fixture coverage.
12. `32L`: deployment documentation suite closeout.
13. `32M`: explicit database deployment dependency contract.
14. `32N`: doctor validation for declared database mode and secret-safe config checks.
15. `32O`: activation-owned runtime roots and host env conflict detection.
16. `32P`: deploy release runtime action parity and operator workflow closeout.
17. `32Q`: deployment documentation addendum for secrets, database modes, and migrations.

## 2.1 Current Phase State

Delivered in this checkpoint:

- `32A`
- `32B`
- `32C`
- `32D`
- `32E`
- `32F`
- `32G`
- `32H`
- `32I`
- `32J`
- `32K`
- `32L`

Remaining after this checkpoint:

- none

## 3. Scope Guardrails

- Do not claim cross-family deploy parity between Apple Foundation and GNUstep.
- Do not reduce deploy compatibility to CPU architecture alone.
- Do not make remote rebuild the default path for mismatched environments.
- Do not let doctor collapse to "passes/fails"; operators need actionable
  findings and remediation.
- Do not tie the deploy-target contract too tightly to one transport or one
  service manager.
- Do not make source checkout assumptions part of the future activated-release
  contract.
- Do not infer database deployment topology purely from DSN shape when the
  deploy target can declare that contract explicitly.
- Do not let shared host env silently override activation-owned runtime roots.
- Do not expand deploy into secret provisioning; host/platform remains the
  owner of secret values.

## 4. Detailed Subphases

### 32A. Deployment Contract and Support Matrix

Status: Delivered on 2026-04-14

Goal:
- define what Arlen means by a supported production deployment target

Delivered contract:

- deployment compatibility is defined by a platform profile tuple, not only
  CPU architecture
- the profile includes:
  - OS family
  - CPU architecture
  - runtime family (`apple-foundation` or `gnustep`)
  - toolchain/runtime variant where relevant
- same-profile deployment is the supported v1 path
- cross-profile remote rebuild is an explicitly downgraded path
- Apple Foundation to GNUstep cross-family deployment is not a supported v1
  path

Acceptance:

- `docs/DEPLOYMENT.md` documents the platform-profile model
- docs distinguish `supported`, `experimental`, and `unsupported`

### 32B. Project Deployment Configuration Model

Status: Delivered on 2026-04-14

Goal:
- define the app-owned configuration shape for production targets before
  implementation details sprawl across flags and shell scripts

Delivered contract:

- deploy config should declare:
  - target identifier
  - host/address metadata
  - platform profile
  - runtime strategy
  - release path
  - healthcheck target
  - hook surfaces
  - future `propane accessories`
- config remains declarative rather than shell-fragment driven

Acceptance:

- `docs/DEPLOYMENT.md` documents the recommended target schema
- the model reserves room for future `propane` handoff without requiring it
  now

### 32C. Local Planning and Platform-Profile Resolution

Status: Delivered on 2026-04-14

Goal:
- define how Arlen compares the local build environment with the target host

Delivered contract:

- Arlen should resolve a canonical local profile string such as:
  - `macos-arm64-apple-foundation`
  - `linux-x86_64-gnustep-clang`
  - `windows-x86_64-gnustep-clang64`
- deploy planning should classify outcomes as:
  - `supported`
  - `experimental`
  - `unsupported`
- same-profile release deployment is the normal supported path
- GNUstep-to-GNUstep remote rebuild may be allowed as `experimental`
- Apple Foundation to GNUstep remains `unsupported`

Acceptance:

- the planning rules are documented for operators and future CLI work
- docs explain why "same architecture" is insufficient

### 32D. Deploy Doctor Probe Framework

Status: Delivered on 2026-04-14

Goal:
- define the future internal structure of `arlen deploy doctor`

Delivered contract:

- doctor should be probe-based rather than one large script
- probes should report structured findings:
  - `error`
  - `warn`
  - `info`
  - `action`
- probes should be able to run in local-only, remote-only, or combined modes
- probe output should be useful to humans and machine consumers

Acceptance:

- `docs/DEPLOYMENT.md` documents the probe/result model
- probe categories are explicit enough to guide implementation and tests

### 32E. Remote Host Readiness Checks

Status: Delivered on 2026-04-14

Goal:
- define what future remote doctor execution must prove before activation

Delivered contract:

- host-readiness checks should include:
  - target OS and architecture
  - runtime family/profile match
  - required writable paths and permissions
  - service-manager expectations
  - release-root readiness
  - runtime presence or install requirements
  - environment/secrets completeness
  - operability and healthcheck expectations
- remote rebuild mode must additionally prove the remote build chain is
  functional, not merely present

Acceptance:

- host-readiness requirements are documented for Linux and Windows targets
- remote rebuild prerequisites are called out explicitly

### 32F. Remote Rebuild Validation and Warnings

Status: Delivered on 2026-04-14

Goal:
- implement explicit opt-in remote rebuild support with strong doctor gating

Delivered scope:

- added `--allow-remote-rebuild` to deploy planning/build/release flows
- limited the best-effort path to GNUstep-to-GNUstep cross-profile targets
- added `--remote-build-check-command` so `deploy doctor` and
  `deploy release` can require a successful build-chain validation command
- fail-closed release behavior now blocks experimental remote rebuild targets
  unless the build-check command succeeds

### 32G. Release Artifact and Manifest Contract Expansion

Status: Delivered on 2026-04-14

Goal:
- extend release metadata with deployment-target and runtime-strategy truth

Delivered scope:

- release manifests now use `phase32-deploy-manifest-v1`
- release metadata now records:
  - local profile
  - target profile
  - runtime strategy
  - support level
  - compatibility reason
  - remote rebuild requirements
- `release.env` exports the same deployment metadata for activated releases

### 32H. Deploy Execution and Activation Flow on Target Hosts

Status: Delivered on 2026-04-14

Goal:
- expand the deploy product from local release orchestration into target-aware
  activation gating

Delivered scope:

- `arlen deploy release` now evaluates deployment compatibility before migrate
  and activate steps
- unsupported target profiles fail closed before activation
- experimental remote rebuild targets require a successful build-check command
  before activation proceeds
- release JSON payloads now include deployment metadata and the compatibility
  or remote-build-check step outcome

### 32I. Rollback and Release Status Depth

Status: Delivered on 2026-04-14

Goal:
- extend status and rollback around target-aware release history and rollback
  eligibility

Delivered scope:

- `arlen deploy status` now reports deployment metadata for the active release
  plus rollback-candidate deployment metadata
- `arlen deploy rollback` now reports rollback-source and active-target
  deployment metadata in JSON output
- deploy doctor output now includes deployment metadata alongside structured
  checks

### 32J. `propane` Integration Boundary and Production Manager Handoff

Status: Delivered on 2026-04-14

Goal:
- define the seam between deploy orchestration and future `propane`
  accessories ownership

Delivered scope:

- packaged release manifests now carry `propane_handoff` metadata
- release env exports explicit `propane` handoff variables
- deploy JSON output now reports the packaged `propane_handoff` contract in
  `push`, `release`, `status`, `rollback`, and `doctor`
- the deploy/docs contract now states clearly that `arlen deploy` owns release
  packaging/activation while `propane` owns supervision and `propane
  accessories`

### 32K. Confidence Lanes and Fixture Coverage

Status: Delivered on 2026-04-14

Goal:
- add deploy-target fixture matrices and doctor/activation regression lanes

Delivered scope:

- added `tools/ci/run_phase32_confidence.sh`
- added `tools/ci/generate_phase32_confidence_artifacts.py`
- added `make phase32-confidence`
- extended deployment integration tests with `propane_handoff` assertions
- the Phase 32 confidence lane now verifies:
  - supported same-profile release metadata
  - experimental remote rebuild metadata and gating
  - doctor failure without remote build validation
  - doctor degradation to warning with explicit validation
  - rollback/status deployment metadata depth
  - unsupported target rejection
  - packaged `propane_handoff` manifest/release-env contract

### 32L. Deployment Documentation Suite Closeout

Status: Delivered on 2026-04-14

Goal:
- finish the developer and operator documentation package for the target-aware
  deploy product

Delivered scope:

- updated deployment, CLI, `propane`, testing, and toolchain docs
- updated roadmap, status, README surfaces, and docs index
- documented `phase32-confidence` as the deploy closeout artifact lane

### 32M. Explicit Database Deployment Dependency Contract

Status: Delivered on 2026-04-14

Goal:
- stop guessing whether production expects an external database, a host-local
  database service, or an embedded/file-backed database

Required follow-up:

- extend the recommended deploy-target schema with an explicit database block
- document supported database dependency modes:
  - `external`
  - `host_local`
  - `embedded`
- make it explicit that Arlen validates the declared mode but does not install
  or provision the database service

Delivered scope:

- deploy packaging now accepts explicit database contract flags:
  - `--database-mode`
  - `--database-adapter`
  - `--database-target`
- packaged manifests now record a `database` contract block
- deploy docs now state explicitly that Arlen validates this declared mode and
  does not provision the database server itself

### 32N. Doctor Validation for Declared Database Mode and Secret-Safe Config Checks

Status: Delivered on 2026-04-14

Goal:
- make `arlen deploy doctor` validate the declared deployment contract instead
  of relying on implicit heuristics

Required follow-up:

- for `database.mode=external`:
  - validate config presence and optional connectivity
  - do not require a local database package/service on the app host
- for `database.mode=host_local`:
  - validate that the required database service is reachable on the host
  - fail clearly when the declared host-local dependency is unavailable
- for `database.mode=embedded`:
  - validate file/runtime prerequisites instead of service presence
- add secret-safe config inspection guidance:
  - show required keys
  - avoid printing secret values

Delivered scope:

- `arlen deploy doctor` now validates declared database mode from the packaged
  manifest
- `database.mode=external` validates config presence without requiring a local
  database install
- `database.mode=host_local` now uses PostgreSQL-oriented host readiness
  probes when that adapter is declared
- required env keys recorded with `--require-env-key` are now checked without
  printing secret values

### 32O. Activation-Owned Runtime Roots and Host Env Conflict Detection

Status: Delivered on 2026-04-14

Goal:
- prevent legacy host env from silently overriding activated release roots

Required follow-up:

- document that release activation owns:
  - `ARLEN_APP_ROOT`
  - `ARLEN_FRAMEWORK_ROOT`
- document that shared env files should contain true secrets/host settings, not
  release-root runtime overrides
- teach `arlen deploy doctor` to flag conflicting persistent host env/runtime
  root overrides when they disagree with the active release

Delivered scope:

- deploy docs now state explicitly that release activation owns
  `ARLEN_APP_ROOT` and `ARLEN_FRAMEWORK_ROOT`
- `arlen deploy doctor --service <unit>` now inspects the live service
  environment and fails when effective runtime roots disagree with the active
  release
- docs now call out the `parker-app` migration failure mode and remediation

### 32P. Deploy Release Runtime Action Parity and Operator Workflow Closeout

Status: Delivered on 2026-04-14

Goal:
- close the remaining gap between release activation and runtime reload/restart
  orchestration

Required follow-up:

- define whether `arlen deploy release` should support first-class
  `--service` + `--runtime-action`
- keep migration, activation, runtime action, and health verification as
  separately visible workflow steps
- document the boundary:
  - deploy handles packaging, migration, activation, runtime action, and verification
  - `propane` handles worker supervision

Delivered scope:

- `arlen deploy release` now supports `--service` plus
  `--runtime-action <reload|restart|none>`
- release JSON payloads now keep `migrate`, `activate`, `runtime`, and
  `health` as separate visible workflow steps
- CLI/deploy docs now describe that runtime action contract explicitly

### 32Q. Deployment Documentation Addendum for Secrets, Database Modes, and Migrations

Status: Delivered on 2026-04-14

Goal:
- make the deploy contract understandable without requiring developers to infer
  policy from old bugs or implementation details

Required follow-up:

- expand developer/operator docs with explicit guidance for:
  - secret ownership and host injection
  - target-level database mode declaration
  - migration expectations and `--skip-migrate`
  - forward-compatible rollout guidance for schema changes
  - the rule that app workers must not race to migrate at boot
- add concrete examples for:
  - systemd env layout focused on secrets
  - release-based runtime root ownership
  - host-local vs external database targets

Delivered scope:

- updated deploy docs with explicit sections for:
  - deploy ownership boundaries
  - database dependency modes
  - secret-safe required env key recording
  - migration expectations and forward-compatible rollout guidance
  - activation-owned runtime-root behavior
- updated CLI docs to describe the new deploy flags and doctor/runtime-action
  behavior

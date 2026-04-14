# Arlen Phase 32 Roadmap

Status: in progress
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

Remaining after this checkpoint:

- `32J-32L`

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

Goal:
- define the seam between deploy orchestration and future `propane`
  accessories ownership

### 32K. Confidence Lanes and Fixture Coverage

Goal:
- add deploy-target fixture matrices and doctor/activation regression lanes

### 32L. Deployment Documentation Suite Closeout

Goal:
- finish the developer and operator documentation package for the target-aware
  deploy product

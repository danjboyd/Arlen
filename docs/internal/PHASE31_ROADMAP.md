# Arlen Phase 31 Roadmap

Status: complete on 2026-04-08
Last updated: 2026-04-08

Phase 31 intentionally skips Phase 30 and reserves that number unused.

This phase captures the remaining work after the `main`-based reintegration of
the historical Windows `CLANG64` branch. Phase 24 forward-ported the Windows
bootstrap, runtime seams, server entrypoints, transport loaders, runtime parity
tests, and preview CI lane. What remains is making the Windows story honest for
release packaging, deployment, and supported operator workflows.

Guardrails:

- preserve the current Phase 29 deploy contract as the source of truth
- do not regress Linux or packaged-release behavior while extending Windows
  support
- keep Windows support explicit about preview vs supported production status
- prefer additive detection and packaging seams over platform-specific forks

Completed on 2026-04-08:

- `31A` audited the packaged Windows release contract and documented the
  minimum assumptions in `docs/WINDOWS_CLANG64.md`
- `31B` taught packaged-release metadata and deploy flows to resolve compiled
  binaries through `.exe` siblings instead of assuming Unix-only filenames
- `31C` extended `tools/deploy/build_release.sh` so the release manifest and
  `release.env` record the actual packaged runtime/helper paths used by
  `propane`, `jobs-worker`, and deploy commands
- `31D` updated `arlen deploy doctor` and packaged operability checks to use
  manifest-backed helper paths and to keep missing-helper failures
  deterministic
- `31E` added the repo-native `phase31-confidence` packaged release lane plus
  fail-closed artifacts under `build/release_confidence/phase31/`
- `31F` expanded the self-hosted Windows preview workflow to run both runtime
  parity and packaged release confidence validation
- `31G` updated Windows/deploy/testing/toolchain docs to describe the actual
  packaged preview workflow and prerequisites
- `31H` closed Phase 31 with an explicit support statement: Windows `CLANG64`
  remains a supported preview path, while Linux remains the authoritative
  production baseline

## 31A. Windows Release Contract Audit

- characterize the current packaged-release layout on Windows against the
  shipped `build_release.sh`, `propane`, and `jobs-worker` expectations
- document which runtime assumptions still depend on MSYS2 / GNUstep host
  state, DLL search paths, or shell wrappers
- define the minimum supported Windows release contract before code changes

## 31B. Packaged Runtime Binary Resolution

- make packaged release roots resolve Windows binaries and helpers without
  Linux-only path assumptions
- verify `.exe` suffix handling and release-manifest paths across `propane`,
  `jobs-worker`, and deploy subcommands
- keep checkout mode and packaged-release mode behavior aligned

## 31C. Windows Release Artifact Packaging

- extend `tools/deploy/build_release.sh` so Windows-targeted release payloads
  include every helper/runtime file the packaged workflow actually needs
- record Windows-relevant runtime helper paths in the deploy manifest instead
  of relying on inferred shell locations
- keep the packaged layout deterministic and smoke-testable

## 31D. Windows Operability and Doctor Parity

- make `arlen deploy doctor` and related operability helpers succeed against a
  packaged Windows release root
- audit health-probe, lifecycle-log, and runtime-helper checks for
  platform-specific gaps
- ensure missing-helper failures stay deterministic and actionable

## 31E. Windows Release Smoke and Confidence Lanes

- add a focused Phase 31 verification lane for packaged Windows release
  behavior
- exercise release build, activation, `propane`, `jobs-worker`, and
  operability checks in one reproducible workflow
- produce confidence artifacts suitable for CI or manual runner validation

## 31F. Windows Preview CI Expansion

- extend the current preview workflow beyond runtime parity into packaged
  release smoke once the release contract is real
- keep the self-hosted runner contract explicit about required labels and
  installed dependencies
- only publish artifacts that materially help debug packaging/runtime failures

## 31G. Windows Deployment Documentation Closeout

- update `docs/WINDOWS_CLANG64.md`, deployment docs, and runbooks to describe
  the actual supported Windows release workflow
- document prerequisites that remain external, including any required MSYS2,
  GNUstep, or DLL runtime setup
- remove stale “still needs transplant” wording once the release path is
  genuinely closed out

## 31H. Phase 31 Closeout and Support Statement

- decide whether Windows remains a preview or graduates to a narrower supported
  production claim
- update `README.md`, `docs/README.md`, and `docs/STATUS.md` with the final
  authoritative statement
- record the final verification commands and any residual non-goals

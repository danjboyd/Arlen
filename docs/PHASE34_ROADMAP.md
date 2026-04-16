# Phase 34 Roadmap

Status: active (`34A-34J` delivered; `34K` planned)
Last updated: 2026-04-16

## Goal

Make Arlen CI match the current project contract, stay green on the
authoritative baseline, and fail only on signals that materially protect
shipped behavior.

Phase 34 is a CI-robustness phase. It focuses on workflow honesty, merge-gate
clarity, and drift prevention rather than a new end-user feature surface.

After the required Linux/docs merge gate was stabilized, Phase 34 was reopened
for one platform-runner standardization subphase. That work keeps Apple and
Windows non-required under the current support statement, but makes their
runner provisioning path explicit and repeatable before either lane is
considered for promotion.

## 34A. CI Contract Audit

Goal:

- inventory the current GitHub Actions surface and classify each lane by role
- identify stale workflow names, duplicated gates, and required-check drift
- define the authoritative merge gate for `main`

Delivered in this subphase:

- audited the current workflow set and documented the intended contract in
  `docs/CI_ALIGNMENT.md`
- classified Linux/GNUstep quality and sanitizer lanes as the authoritative
  merge gate
- identified the legacy `phase3c-quality` workflow as redundant drift

Acceptance target:

- one written source of truth exists for the intended CI contract

## 34B. Workflow Naming and Topology Cleanup

Goal:

- make workflow filenames and `name:` values match their real purpose
- remove or disable legacy overlapping workflows
- reduce status-check ambiguity in GitHub UI and branch protection

Delivered in this subphase:

- removed the legacy `.github/workflows/phase3c-quality.yml` workflow
- renamed active workflows to purpose-based filenames:
  - `linux-quality.yml`
  - `linux-sanitizers.yml`
  - `windows-preview.yml`
  - `apple-baseline.yml`
- aligned workflow `name:` values to the same descriptive contract

Acceptance target:

- there is one naming scheme across workflow files and GitHub status checks

## 34C. Linux Authoritative Gate Consolidation

Goal:

- keep one Linux/GNUstep quality lane as the authoritative required merge gate
- preserve a distinct required sanitizer lane
- remove duplicate Linux workflow execution that does not add meaningful signal

Delivered in this subphase:

- established `linux-quality` as the canonical Linux/GNUstep quality workflow
- established `linux-sanitizers` as the canonical Linux/GNUstep sanitizer
  workflow
- removed the overlapping legacy Linux quality workflow that duplicated an
  older subset of the contract

Current boundary:

- release-only certification has moved out of `linux-quality`; branch
  protection and final verification remain deferred to later Phase 34 work

Acceptance target:

- the Linux merge gate is clear, singular, and reproducible through existing
  repo-native commands

## 34D. Docs Gate Promotion and Drift Prevention

Goal:

- treat docs quality as part of the core merge contract
- keep generated docs and roadmap/status surfaces aligned with workflow reality
- ensure contributor guidance says CI drift must be fixed immediately

Delivered in this subphase:

- promoted `docs-quality` into the documented required merge-check set
- added `docs/CI_ALIGNMENT.md` and linked it from the docs index
- updated `AGENTS.md` so keeping CI current and green is a core project goal
- updated release/process guidance to reflect the new required-check set

Acceptance target:

- docs quality is part of the written merge contract and contributor workflow

## 34E. Platform Lane Policy

Goal:

- keep Apple and Windows visible in CI without overstating their merge-gate
  weight
- document exactly when a platform lane can be promoted to required
- preserve useful artifact output for non-blocking platform failures

Delivered in this subphase:

- documented Apple as `baseline confidence` and Windows as `preview
  confidence` in `docs/CI_ALIGNMENT.md`
- kept both lanes non-required in the written merge-gate contract
- preserved failure artifact uploads for both platform workflows so they remain
  useful for diagnosis without blocking merges by default

Acceptance target:

- platform workflow policy is explicit and consistent with the project support
  statement

## 34F. Failure Triage And Fast Feedback

Goal:

- reduce stale runner churn and make required-lane failures diagnosable from
  one run
- distinguish ordinary code failures from hung or infrastructure-heavy runs

Delivered in this subphase:

- added workflow-level concurrency cancellation for the active merge-gate and
  platform workflows
- added explicit job timeouts for the active workflows
- changed merge-gate and platform workflows to upload artifacts on failure as
  well as manual runs

Acceptance target:

- the main workflows now fail faster, cancel stale duplicates, and preserve
  enough output for first-pass diagnosis

## 34G. Release Lane Isolation

Goal:

- separate release certification from normal merge gating
- keep release-only rebuilds and artifact generation out of the normal Linux
  quality workflow
- make the release-certification lane explicit in GitHub Actions

Delivered in this subphase:

- removed the `release` trigger from `linux-quality`
- added `.github/workflows/release-certification.yml` as the dedicated Phase
  9J release lane
- kept the release checklist entrypoint aligned with
  `tools/ci/run_phase9j_release_certification.sh`

Acceptance target:

- release certification is now an explicit release-only workflow rather than a
  side effect of the merge gate

## 34H. Branch Protection And Repo Settings Closeout

Goal:

- verify GitHub branch protection for `main` matches the written merge-gate
  contract
- keep platform, nightly, and release-only workflows visible without making
  them accidental merge blockers
- record the live repo-settings outcome so future CI changes have a concrete
  comparison point

Delivered in this subphase:

- verified `main` branch protection requires exactly:
  - `linux-quality / quality-gate`
  - `linux-sanitizers / sanitizer-gate`
  - `docs-quality / docs-gate`
- verified strict required status checks are enabled so required checks must be
  current with the branch being merged
- verified force pushes and deletions remain disabled for `main`
- documented that Apple baseline, Windows preview, nightly thread-race, and
  release certification remain non-required under the current support
  statement

Acceptance target:

- GitHub branch protection, workflow names, and the written merge-gate contract
  describe the same required checks

## 34I. Contributor And Agent Workflow Closeout

Goal:

- make the day-to-day validation path match the updated CI contract
- ensure contributors and coding agents know when CI/docs/release references
  must be updated together
- keep local command guidance aligned with the required GitHub checks

Delivered in this subphase:

- updated contributor testing guidance to name the Phase 34 merge-gate
  commands and their matching GitHub required checks
- kept the pull request checklist aligned with the current CI contract and
  branch-protection drift rule
- kept `AGENTS.md` aligned with the repo-wide expectation that workflow,
  branch-protection, and docs changes ship together

Acceptance target:

- a contributor can determine the required local checks and GitHub status
  checks without reverse-engineering workflow history

## 34J. Robustness Verification And Exit Criteria

Goal:

- verify the final Phase 34 merge-gate contract on GitHub after the workflow
  cleanup
- confirm recent required lanes pass on `main`
- leave a clear exit record for later phases

Delivered in this subphase:

- verified the latest pushed `main` commit has passing `docs-quality` and
  `linux-sanitizers` required workflows
- waited on the latest `linux-quality` workflow before closing the phase
- treated Apple baseline and Windows preview as visible non-blocking signals in
  accordance with the platform lane policy

Acceptance target:

- all required merge-gate checks are green on the closing commit, and Phase 34
  has a documented exit state

## 34K. OracleTestVMs Platform Runner Standardization

Goal:

- align Apple and Windows platform confidence lanes on an OracleTestVMs-backed
  self-hosted runner process
- make LAN-provisioned platform runners reproducible enough that
  `apple-baseline` and `windows-preview` can be operated without manual
  one-off machine state
- use `gnustep-cli-new` as the Windows MSYS2/GNUstep toolchain provisioning
  path before relying on the Windows preview runner for routine CI signal

Planned scope:

- define the standard runner lifecycle for disposable or dedicated LAN VMs:
  provision through OracleTestVMs, install the platform toolchain, register the
  GitHub Actions runner with the expected labels, run Arlen validation, and
  clean up or reset runner state
- document the Windows runner contract around:
  - OracleTestVMs `windows-2022` readiness
  - `gnustep-cli-new` MSYS2 `CLANG64` / GNUstep installation
  - Arlen `scripts/run_clang64.ps1`
  - GitHub runner labels `arlen` and `msys2-clang64`
- document the macOS runner contract once OracleTestVMs macOS VM provisioning
  is available, including full-Xcode/XCTest expectations for
  `apple-baseline`
- decide whether Phase 34 standardizes on dedicated long-lived platform
  runners first, then records ephemeral runner automation as follow-up, or
  requires the ephemeral flow before closing `34K`
- keep `apple-baseline` and `windows-preview` visible but non-required unless a
  later support statement deliberately promotes either lane

Blockers:

- `gnustep-cli-new` must be complete enough for Arlen's Windows use case:
  first-time MSYS2/GNUstep provisioning on a fresh OracleTestVMs Windows lease,
  a working `GNUstep.sh` / `gnustep-config` / `clang` / `xctest` environment,
  and enough dependency coverage to run Arlen's Windows preview and packaged
  release confidence lanes
- OracleTestVMs macOS VM provisioning must be available before the macOS side
  of the standardized runner lifecycle can be completed
- GitHub runner registration and secret/token handling for LAN VMs must be
  documented before the process is treated as operationally repeatable

Acceptance target:

- a documented OracleTestVMs-backed platform runner process exists for Windows
  and macOS, with blockers resolved or explicitly deferred
- `windows-preview` can start on an online LAN runner and run the Arlen Windows
  preview commands through the documented GNUstep provisioning path
- `apple-baseline` has a documented OracleTestVMs-backed runner path that
  matches the Phase 30 full-Xcode/XCTest contract without changing the current
  required merge-gate checks

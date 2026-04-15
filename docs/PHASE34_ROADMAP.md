# Phase 34 Roadmap

Status: in progress
Last updated: 2026-04-15

## Goal

Make Arlen CI match the current project contract, stay green on the
authoritative baseline, and fail only on signals that materially protect
shipped behavior.

Phase 34 is a CI-robustness phase. It focuses on workflow honesty, merge-gate
clarity, and drift prevention rather than a new end-user feature surface.

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

## Remaining Phase 34 Work

- `34H`: branch protection and repo settings closeout
- `34I`: contributor and agent workflow closeout
- `34J`: robustness verification and exit criteria

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

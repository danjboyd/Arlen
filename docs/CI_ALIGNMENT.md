# CI Alignment

Last updated: 2026-04-17

This document defines the intended shape of Arlen CI so workflow names,
required checks, and actual project contracts stay aligned.

CI checkouts must include submodules while Arlen carries the temporary
`vendor/tools-xctest` runner. That submodule pins GNUstep/tools-xctest PR 5 for
Apple-style `-only-testing` / `-skip-testing` support. Periodically check
upstream `tools-xctest`; once that behavior is available upstream, remove the
submodule and switch the default runner back to upstream `xctest`.

## Goal

Arlen CI should always be:

- current with the repo's real support statement
- green on the authoritative baseline
- explicit about which lanes are merge-blocking versus informative
- updated in the same change set as any workflow or contract shift

Keeping CI updated and green is a core project goal.

## Current Recommended Contract

The required merge gate should reflect the current authoritative baseline:

- Linux/GNUstep quality gate
  - build/toolchain bootstrap
  - unit, integration, and data-layer coverage
  - runtime concurrency gate
  - blocking fault-injection/performance checks
- Linux/GNUstep sanitizer gate
  - ASAN/UBSAN matrix and the other blocking hardening lanes
- docs quality gate
  - generated API reference freshness
  - docs navigation/roadmap consistency
  - browser-doc build output

Additional lanes should stay visible but non-blocking unless the support
statement is raised:

- Apple baseline confidence
- Windows preview confidence
- scheduled thread-race / experimental sanitizer follow-up lanes

## Phase 34 Progress

Completed:

- `34A`: CI contract audit
- `34B`: workflow naming and topology cleanup
- `34C`: Linux authoritative gate consolidation
- `34D`: docs gate promotion and drift prevention
- `34E`: platform lane policy
- `34F`: failure triage and fast feedback
- `34G`: release lane isolation
- `34H`: branch protection and repo settings closeout
- `34I`: contributor and agent workflow closeout
- `34J`: robustness verification and exit criteria

Planned/open:

- `34K`: OracleTestVMs-backed platform runner standardization for Apple and
  Windows confidence lanes. This keeps both lanes non-required under the
  current support statement while defining a repeatable LAN/self-hosted runner
  lifecycle. Closing this subphase is blocked on `gnustep-cli-new` being ready
  for Arlen's Windows MSYS2 `CLANG64` GNUstep provisioning path and on
  OracleTestVMs macOS VM provisioning being available for the macOS runner
  side.

## Current Merge-Gate Contract

- `linux-quality`
- `linux-sanitizers`
- `docs-quality`

Additional lanes remain visible but non-blocking while their support level
stays below the authoritative Linux production baseline:

- `apple-baseline`
- `windows-preview`
- nightly thread-race / experimental follow-up lanes

## Platform Lane Policy

Platform lanes below the authoritative Linux production baseline should remain
visible but non-required:

- `apple-baseline`
  - purpose: maintain the verified Apple runtime baseline
  - status: baseline confidence, not the authoritative production merge gate
  - promotion rule: only promote if the platform support statement becomes
    authoritative and the lane stays stably green
- `windows-preview`
  - purpose: validate Windows preview runtime and packaged release parity
  - status: preview confidence, not a required merge gate
  - promotion rule: only promote if Windows leaves preview and the lane is
    operationally stable enough to protect real shipped behavior

Platform lanes should upload artifacts on failure so they remain useful for
diagnosis even while non-blocking.

## Platform Runner Provisioning Direction

Phase 34K standardizes the intended platform-runner path:

- Windows preview should run on an OracleTestVMs-provisioned LAN Windows VM
  with the MSYS2 `CLANG64` GNUstep toolchain installed through
  `gnustep-cli-new`, then registered as a GitHub Actions self-hosted runner
  with labels `arlen` and `msys2-clang64`.
- Apple baseline should move toward an OracleTestVMs-provisioned macOS VM path
  once that provider is available, while preserving the existing full-Xcode and
  XCTest requirements of `apple-baseline`.
- The first operational target can be a dedicated long-lived platform runner;
  ephemeral lease-backed registration/teardown may be documented as a follow-up
  if that is the lower-risk path to a stable signal.

This provisioning work does not change branch protection by itself.

## Failure Triage And Fast Feedback

The current workflow policy is:

- merge-gate workflows cancel older in-progress runs for the same PR/ref
- merge-gate workflows upload artifacts on failure so diagnosis does not depend
  on rerunning the entire lane
- timeouts are explicit so hung jobs fail as infrastructure/tooling signals
  instead of lingering indefinitely

This keeps required lanes focused on actionable failures and reduces stale
runner churn.

## Recommended Workflow Layout

Use clear workflow filenames that match their actual role:

- `.github/workflows/linux-quality.yml`
- `.github/workflows/linux-sanitizers.yml`
- `.github/workflows/docs-quality.yml`
- `.github/workflows/apple-baseline.yml`
- `.github/workflows/windows-preview.yml`
- `.github/workflows/release-certification.yml`

The workflow `name:` field should match the filename-level intent. Avoid
historical phase-number filenames that now launch newer lanes.

## Branch Protection Guidance

For `main`, require:

- `linux-quality / quality-gate`
- `linux-sanitizers / sanitizer-gate`
- `docs-quality / docs-gate`

Do not require by default:

- Apple baseline
- Windows preview
- nightly thread-race / experimental lanes
- release certification

Verified repo state on 2026-04-16:

- `main` branch protection requires exactly the three checks above
- strict required status checks are enabled
- force pushes and branch deletions are disabled
- Apple baseline, Windows preview, nightly thread-race, and release
  certification are not required checks

Raise a lane to required only when:

- the platform/support statement says it is authoritative
- the lane is stable enough to stay green without manual babysitting
- the lane materially protects shipped behavior

## Update Rules

Whenever CI behavior changes, update in the same change:

- workflow files under `.github/workflows/`
- `docs/RELEASE_PROCESS.md`
- `docs/TOOLCHAIN_MATRIX.md` when toolchain assumptions change
- this document
- `AGENTS.md` if the contributor/agent workflow expectation changed

## Practical Rule For Contributors

If a change causes CI drift, fix the drift immediately. Do not leave behind a
state where docs, branch protection, and workflow names describe different
quality gates.

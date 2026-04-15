# CI Alignment

Last updated: 2026-04-15

This document defines the intended shape of Arlen CI so workflow names,
required checks, and actual project contracts stay aligned.

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

Remaining:

- `34H` through `34J`

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

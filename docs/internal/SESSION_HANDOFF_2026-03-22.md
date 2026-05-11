# Session Handoff (2026-03-22 EOD)

This note captures where work stopped at end of day so the next session can
resume from a concrete state instead of chat history.

## Current Revisions

- Arlen:
  - repo: `/home/danboyd/git/Arlen`
  - branch: `main`
  - HEAD: `d40c0b4` (`Pin self-hosted perf gates to iep-apt baselines`)
  - worktree: clean

## Verified State

- Self-hosted GitHub Actions runner `iep-apt-arlen` is working normally again:
  - runner status is `online`
  - current model is outbound-only GitHub connectivity from `iep-apt`
  - no WireGuard/VPN path is required for the current self-hosted design
- The runner-side stability work from this session is in place:
  - GitHub runner upgraded to `2.333.0`
  - runner service uses `KillMode=control-group`
  - the earlier stuck-session / hanging `Complete job` behavior is no longer
    the primary blocker
- The repo-side CI hardening and follow-on fixes from this session are on
  `main`, including:
  - sanitizer/non-sanitizer artifact invalidation
  - GNUstep ARC/CF bridging fix in `ALNApplication`
  - retry/cooldown handling for dispatch perf, blob throughput, and soak gates
  - route rebuild assertion relaxation
  - self-hosted workflow artifact-upload narrowing
  - dedicated self-hosted perf baseline selection via
    `ARLEN_PERF_BASELINE_ROOT`
- A fresh `iep-apt` perf baseline pack was captured and checked in under:
  - `tests/performance/baselines/iep-apt/`
  - these baselines reflect the current runner hardware (`cpu_count = 4`)
  - this resolved the earlier mismatch where checked-in perf baselines had
    been recorded on a 14-core machine

## GitHub CI State At Stand-Down

Commit under test: `d40c0b4`

- `phase5e-quality`
  - run `23410318683`
  - status: `success`
  - completed: `2026-03-22T19:20:14Z`
- `docs-quality`
  - run `23410318682`
  - status: `success`
  - completed: `2026-03-22T19:20:47Z`
- `phase3c-quality`
  - run `23410318681`
  - status: `success`
  - completed: `2026-03-22T19:33:11Z`
- `phase5e-sanitizers`
  - run `23410318685`
  - status at stand-down: `in_progress`
  - active job: `sanitizer-gate`
  - current step: `Run Phase 10M sanitizer matrix gate`
  - job started: `2026-03-22T19:33:12Z`

As of stand-down, three of the four push-triggered GitHub lanes on the new
head are green. The remaining active lane is the sanitizer matrix job.

## Important Host Context

- Host: `iep-apt`
- Current runner hardware observed during this session:
  - `4` CPUs
  - about `3.9 GiB` RAM total
- The runner is healthy but single-threaded at the workflow level:
  - only one self-hosted job executes at a time
  - other workflows remain queued behind the active job
- The host does not appear memory-bound during the current CI lane.
  The likely speed constraint is CPU / wall-clock serialization.
- The current CI scripts use plain `make`, not `make -j`, so adding CPU alone
  will not deliver the full possible speedup unless the build/test phases are
  also parallelized deliberately.

## Where Work Stopped

Primary goal for the session was GitHub CI recovery on the self-hosted
`iep-apt` runner. That goal is almost complete.

The concrete remaining question at stand-down is whether
`phase5e-sanitizers` on `d40c0b4` finishes green. If it does, the main
push-triggered GitHub CI lanes for the current self-hosted path are recovered.

The older cross-repo `apt_portstree` generic runner-image work was not resumed
in this session. The current Arlen path is the host-installed/preinstalled
GNUstep stack on `iep-apt`, not a published runner image.

## Resume Checklist

1. Check the final result of `phase5e-sanitizers` run `23410318685`.
2. If it passed, record that the current push-triggered GitHub CI set on
   `d40c0b4` is green end-to-end.
3. If it failed, inspect the failed log and fix only the concrete
   sanitizer-specific issue shown there.
4. After the sanitizer lane is settled, revisit the dedicated TSAN/nightly
   follow-up:
   - current standing assumption is still that the GNUstep `libobjc`
     lock-order-inversion signature is a runtime/toolchain issue, not an Arlen
     correctness bug
5. If faster CI is a priority, decide whether to:
   - increase `iep-apt` CPU capacity, and/or
   - parallelize compile-heavy CI steps with an explicit `make -j` strategy

## Open Items

- `phase5e-sanitizers` on `d40c0b4` is still running at stand-down.
- Dedicated TSAN promotion remains open after the current GitHub recovery work.
- The generic reusable GitHub Actions runner-image plan in `apt_portstree`
  remains deferred.

## Notes For Tomorrow

- Current best-known stable self-hosted contract for Arlen is:
  - self-hosted runner on `iep-apt`
  - outbound HTTPS from the runner to GitHub
  - `ARLEN_CI_GNUSTEP_STRATEGY=preinstalled`
  - perf workflows pinned to `tests/performance/baselines/iep-apt`
- If CI speed becomes the next target, the highest-signal improvement is
  probably CPU plus deliberate build parallelism, not RAM alone.

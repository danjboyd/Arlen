# Arlen Phase 24 Roadmap

Status: in progress (`24A-24S` delivered on branch `windows/clang64`; `24T` planned for PowerShell-first Windows launcher wrappers)
Last updated: 2026-04-07

Related docs:
- `README.md`
- `docs/README.md`
- `docs/STATUS.md`
- `docs/TOOLCHAIN_MATRIX.md`
- `docs/TESTING_WORKFLOW.md`
- `docs/DEPLOYMENT.md`
- `docs/PROPANE.md`
- `docs/SYSTEMD_RUNBOOK.md`

Audit basis:
- Repository-wide Windows portability audit completed on 2026-03-30 against the
  checked-in build, runtime, test, and deployment surfaces.
- Adjacent MSYS2 `CLANG64` GNUstep precedents reviewed on 2026-03-31 across the
  sibling `libs-OpenSave`, `ScreenshotTool`, `tools-xctest-msys`, and Windows
  MSYS launcher worktrees under the shared `../` workspace.

## 1. Objective

Make Arlen build and run natively on Windows via MSYS2 `CLANG64` while keeping
GNUstep-make as the canonical build system and allowing the main branch to
continue Phase 23 work independently.

Phase 24 is split into three tracks:

- `24A-24F`: first-pass Windows compatibility
- `24G-24M`: Windows preview contract completion
- `24N-24P`: Windows runtime parity closeout
- `24Q-24T`: Windows-to-Linux parity and platform closeout

The implementation branch for this work is `windows/clang64`.

## 1.1 Why Phase 24 Exists

Arlen's current toolchain and runtime contract is Linux-first:

- build/test/bootstrap scripts assume `/usr/GNUstep`, `/bin/bash`, and Debian
  `tools-xctest`
- the HTTP runtime is written directly against POSIX sockets, signals, and file
  descriptor APIs
- database loading assumes Unix shared-library naming and `dlopen`/`dlsym`
- deployment guidance is centered on `systemd` and Unix process management

That is compatible with WSL2, but it is not native Windows support. Phase 24
exists to turn the existing GNUstep-based framework into something that can be
built and validated on Windows itself using the already-adjacent MSYS2
`CLANG64` toolchain.

## 1.2 Success Criteria

First-pass success means:

- one documented Windows host workflow can enter the MSYS2 `CLANG64` GNUstep
  environment from PowerShell
- `eocc`, the core framework library, and `arlen` build successfully on
  `CLANG64`
- a focused Windows-safe XCTest path runs with reliable exit status
- unsupported surfaces are explicitly documented instead of implied

Full-parity success means:

- default app-root `boomhauer` behavior, including watch mode and dev-error
  recovery, matches Linux on Windows
- `jobs worker` and `propane` both run natively on Windows with equivalent
  lifecycle behavior and user-facing contracts
- the HTTP runtime, filesystem security helpers, database transports, and
  production/runtime-manager surfaces all have verified Windows
  implementations
- the supported Windows verification matrix is broad enough to cover the same
  unit, integration, live-backend, perf, sanitizer, and fault-injection
  confidence claims that Linux currently carries
- the release/deployment story for Windows is implementation-backed rather than
  inherited from Linux-only docs or limited to preview caveats

## 2. Design Principles

- Stay GNUmake-first. Do not widen the port into a second build-system effort.
- Use PowerShell as the outer Windows orchestration layer and MSYS bash as the
  inner GNUstep build shell.
- Replace hardcoded Linux paths with `gnustep-config` and `CLANG64`-specific
  discovery where possible.
- Introduce platform seams for sockets, dynamic library loading, paths, time,
  and process control instead of scattering unchecked `_WIN32` branches
  throughout the codebase.
- Allow temporary feature gating while the port is incomplete; do not promise
  parity before it is verified.
- Preserve the clang-based GNUstep requirement; Phase 24 is about Windows
  support, not broadening Arlen toward generic GNUstep stacks.
- Keep the main branch free to continue its own roadmap numbering and release
  work without rebasing the Windows effort into every incremental experiment.

## 3. Scope Summary

## 3.1 First-Pass Compatibility Track

1. Phase 24A: branch + toolchain contract.
2. Phase 24B: build/bootstrap path abstraction.
3. Phase 24C: `eocc` + core library + CLI build bring-up.
4. Phase 24D: Windows-safe CLI/scaffold path normalization.
5. Phase 24E: focused Windows XCTest runner strategy.
6. Phase 24F: first-pass closeout and preview-scope documentation.

## 3.2 Windows Preview Contract Track

7. Phase 24G: HTTP/runtime portability seams.
8. Phase 24H: `boomhauer` and app-root developer-experience parity.
9. Phase 24I: PostgreSQL/MSSQL transport and dynamic-loading parity.
10. Phase 24J: filesystem/security semantics parity.
11. Phase 24K: full verification, CI, and confidence-lane parity.
12. Phase 24L: production/runtime-manager parity and Windows deployment story.
13. Phase 24M: Windows XCTest discovery and native warning closeout.

## 3.3 Windows-To-Linux Parity Track

14. Phase 24N: `boomhauer` watch-mode and dev-error parity.
15. Phase 24O: `jobs worker` and background runtime parity.
16. Phase 24P: `propane` and native process-manager parity.
17. Phase 24Q: full test and live-backend matrix parity.
18. Phase 24R: perf, sanitizer, and fault-injection lane parity.
19. Phase 24S: release, packaging, and first-class platform closeout.
20. Phase 24T: PowerShell-first launcher wrappers for `arlen` and `boomhauer`.

## 3.4 Recommended Rollout Order

1. `24A`
2. `24B`
3. `24C`
4. `24D`
5. `24E`
6. `24F`
7. `24G`
8. `24H`
9. `24I`
10. `24J`
11. `24K`
12. `24L`
13. `24M`
14. `24N`
15. `24O`
16. `24P`
17. `24Q`
18. `24R`
19. `24S`
20. `24T`

That order gets a real Windows development foothold first, then expands
outward into runtime, security, verification, deployment parity, default-platform
closeout, and finally a PowerShell-native launcher surface over the checked-in
CLANG64 contract.

## 4. Scope Guardrails

- Do not switch Arlen to CMake, Meson, or another primary build system as part
  of this phase.
- Do not treat WSL2 success as native Windows parity.
- Do not block the main branch's Phase 23 work by rebasing every Windows
  experiment immediately.
- Do not claim `propane` or deployment parity until a real Windows production
  story is implemented and documented.
- Do not weaken Linux verification or remove existing guardrails just to make
  the Windows port easier.
- Do not rely on ad hoc local path edits as the support model; the toolchain
  contract must be checked in and repeatable.

## 5. Milestones

## 5.1 Phase 24A: Branch + Toolchain Contract

Status: complete

Checkpoint notes:

- The dedicated implementation branch `windows/clang64` was created on
  2026-03-31.
- The adjacent workspace already contains relevant MSYS2/GNUstep precedents,
  including `tools-xctest-msys` and CLANG64 launcher wrappers used by sibling
  repos.

Deliverables:

- Establish the canonical Windows host invocation contract:
  - PowerShell outer launcher
  - MSYS2 `CLANG64` inner shell
  - GNUstep bootstrap via `/clang64/share/GNUstep/Makefiles/GNUstep.sh`
- Document the required `CLANG64` tools and libraries Arlen expects:
  - `clang`
  - `gnustep-config`
  - `make`
  - `xctest`
  - `openapp`
  - `libdispatch`
- Decide the initial supported repo-local helper scripts/wrappers for entering
  that environment.

Acceptance (required):

- One documented command path from Windows host shell to a ready GNUstep
  `CLANG64` build shell succeeds reproducibly.
- The Phase 24 branch and roadmap are the explicit source of truth for Windows
  work-in-progress.

## 5.2 Phase 24B: Build + Bootstrap Path Abstraction

Status: complete

Checkpoint notes:

- Added checked-in Windows/MSYS2 launcher wrappers:
  - `scripts/run_clang64.ps1`
  - `scripts/run_clang64.sh`
- Taught the main GNUmake bootstrap path to resolve `GNUSTEP_SH` through
  `GNUSTEP_MAKEFILES`, `gnustep-config`, and `/clang64` before falling back to
  the Linux `/usr/GNUstep` path.
- Replaced the hardcoded PostgreSQL include path with `pkg-config`/toolchain
  discovery plus `/clang64` and Linux fallbacks.

Deliverables:

- Remove or centralize hardcoded Linux bootstrap assumptions such as:
  - `/usr/GNUstep/...`
  - `/usr/include/postgresql`
  - Debian-only tool discovery text where Windows `CLANG64` alternatives exist
- Teach the repo build/bootstrap scripts to resolve GNUstep paths through
  `gnustep-config` and/or a checked-in Windows wrapper contract.
- Normalize path handling so Windows absolute paths and MSYS paths can coexist
  without brittle string-prefix logic.

Acceptance (required):

- The build/bootstrap entry paths no longer require repo-wide manual rewrites to
  switch from Linux `/usr/GNUstep` to Windows `/clang64`.
- Windows-specific wrapper entrypoints are checked in and documented rather than
  remaining local shell history.

## 5.3 Phase 24C: `eocc` + Core Library + CLI Build Bring-Up

Status: complete

Checkpoint notes:

- Added a Windows preview build mode in `GNUmakefile` that narrows `make all`
  to the first-pass CLANG64 slice instead of pulling in `boomhauer` and other
  Unix-only runtime targets by default.
- Introduced a reduced preview framework library slice for `eocc` and `arlen`
  while the HTTP/runtime, data transport, and filesystem parity phases remain
  pending.
- Added the first Windows-specific source portability change in the preview
  slice by switching `ALNConfig.m` to Winsock-compatible headers on `_WIN32`.

Deliverables:

- Make the following build successfully on MSYS2 `CLANG64`:
  - `build/eocc`
  - core framework library artifacts
  - `build/arlen`
- Resolve immediate compiler and linker issues in Foundation-heavy code before
  widening into runtime-portability work.
- Keep ARC and current clang/GNUstep expectations intact.

Acceptance (required):

- A documented `CLANG64` build command produces `eocc`, the core framework
  library, and `arlen` from a clean checkout.
- Template compiler and non-server CLI build failures are no longer blocked on
  Linux-only toolchain assumptions.

## 5.4 Phase 24D: Windows-Safe CLI + Scaffold Path Normalization

Status: complete

Checkpoint notes:

- Replaced core CLI filesystem-path checks that assumed absolute paths always
  start with `/`.
- Made the CLI shell-launch path resolve `bash` from the active environment or
  common MSYS2 locations instead of hardcoding `/bin/bash`.
- Gated unsupported preview commands with explicit Windows-preview messages so
  first-pass CLI behavior matches the Phase 24 scope instead of failing
  indirectly at link/runtime.
- Updated `bin/arlen-doctor` and `build/arlen doctor` logic toward the CLANG64
  contract by resolving GNUstep/bootstrap paths dynamically and widening `libpq`
  detection beyond Linux-only `ldconfig`.

Deliverables:

- Make `arlen` subcommands that do not require the full HTTP runtime behave
  correctly with Windows path forms and PowerShell/MSYS launch patterns.
- Replace or isolate `/bin/bash` assumptions in CLI-owned helper paths where a
  Windows wrapper can provide the same behavior.
- Revalidate scaffold output and generated path handling under CLANG64.

Acceptance (required):

- Focused CLI smoke paths such as `arlen doctor`, `arlen new`, and core
  generator flows work from the documented Windows workflow.
- Windows path normalization no longer depends on Unix-only “starts with `/`”
  checks in the core CLI flow.

## 5.5 Phase 24E: Focused Windows XCTest Runner Strategy

Status: complete

Checkpoint notes:

- Added a repo-local focused Windows bundle runner source:
  - `tools/arlen_xctest_runner.m`
- Added a checked-in focused Windows test target:
  - `make phase24-windows-tests`
- Added wrapper entrypoints for the focused lane:
  - `scripts/run_phase24_windows_tests.ps1`
  - `scripts/run_phase24_windows_tests.sh`
- Wired `arlen test --unit` to that focused lane on Windows preview while
  keeping `--integration` and `--all` explicitly deferred.

Deliverables:

- Decide the Windows testing contract for the first pass:
  - stock `xctest.exe`
  - repo-local `tools-xctest-msys`
  - temporary focused fallback runner if required
- Define which suites are Windows-first candidates and which remain
  intentionally gated.
- Make the Windows test command return trustworthy pass/fail status even if the
  broader suite is still incomplete.

Acceptance (required):

- One checked-in command runs a focused Windows-safe XCTest subset and returns a
  reliable exit code on CLANG64.
- Unsupported or unstable Windows test lanes are explicitly called out instead
  of silently skipped.

## 5.6 Phase 24F: First-Pass Closeout + Preview Scope

Status: complete

Checkpoint notes:

- Updated the Windows documentation set to describe the widened `24A-24L`
  branch contract in:
  - `README.md`
  - `docs/README.md`
  - `docs/GETTING_STARTED.md`
  - `docs/CLI_REFERENCE.md`
  - `docs/TESTING_WORKFLOW.md`
  - `docs/TOOLCHAIN_MATRIX.md`
  - `docs/WINDOWS_CLANG64.md`
- Recorded the focused Windows test lane, the app-root `boomhauer` preview
  flows, and the remaining deferred surfaces.
- Closeout evidence is still partially pending because this sandbox cannot run
  the MSYS2 `CLANG64` shell end-to-end.

Deliverables:

- Record the first-pass supported Windows preview surface in the docs.
- Explicitly list what remains unsupported after the first-pass milestone.
- Close the first-pass milestone with concrete build/test evidence rather than a
  purely planning-based completion claim.

Acceptance (required):

- A Windows preview user can tell exactly which Arlen surfaces are supported on
  CLANG64 and which still require Phase 24 follow-on work.
- First-pass closeout only happens after `24C-24E` have real build and test
  evidence attached.

## 5.7 Phase 24G: HTTP Runtime Portability Seams

Status: complete

Checkpoint notes:

- Added `src/Arlen/Support/ALNPlatform.{h,m}` for cross-platform time, sleep,
  PID, and absolute-path helpers shared by the preview runtime.
- Replaced the request parser's pthread thread-local path with
  `dispatch_once` plus `NSThread` storage in `src/Arlen/HTTP/ALNRequest.m`.
- Introduced Winsock-aware socket wrappers, console stop handling, and
  portable timeout/send/recv/sendfile-fallback seams in
  `src/Arlen/HTTP/ALNHTTPServer.m`.
- Moved ISO8601 timestamp and worker-PID call sites in
  `src/Arlen/Core/ALNApplication.m` and `src/Arlen/Support/ALNLogger.m` onto
  the shared platform layer.

Deliverables:

- Introduce platform seams for:
  - sockets
  - connection shutdown
  - stop/reload signaling
  - time APIs
  - thread-local helpers
  - `sendfile`-style file response fallbacks
- Preserve the current Linux implementation while adding Windows-capable
  alternatives beneath the same runtime contracts.

Acceptance (required):

- The native HTTP server builds on Windows with explicit Winsock-compatible
  runtime paths.
- Basic request/response service works on CLANG64 without requiring WSL2.

## 5.8 Phase 24H: `boomhauer` + App-Root DX Parity

Status: complete

Checkpoint notes:

- `GNUmakefile` now widens the Windows preview framework slice far enough to
  build the basic app/server runtime needed for app-root `boomhauer` flows.
- `bin/boomhauer` now resolves `GNUstep.sh` dynamically, normalizes
  Windows-owned app-root paths through MSYS, replaces `stat -c` /
  `sha256sum`-based fingerprinting with Python-backed probes, and emits a
  Windows-aware generated app makefile.
- `tools/arlen.m` now enables Windows-preview `boomhauer`, `routes`, and the
  focused `test --unit` path while keeping watch mode, jobs worker, and
  `propane` deferred.
- Repository-root `boomhauer` and watch mode remain intentionally gated on the
  Windows preview until the later parity phases land.

Deliverables:

- Replace Linux shell utility assumptions in `bin/boomhauer` with
  Windows-compatible wrappers or implementation changes.
- Make app-root `prepare-only`, route printing, and basic dev-server workflows
  work under the documented PowerShell + MSYS contract.
- Revisit file-fingerprinting, generated-app makefile emission, and path
  normalization for Windows-owned app roots.

Acceptance (required):

- `boomhauer --prepare-only` works for a scaffolded app on Windows.
- Basic app-root developer flow no longer depends on Linux-only `readlink`,
  `stat`, `sha256sum`, or similar utilities being present natively.

## 5.9 Phase 24I: Database Transport + Dynamic-Loading Parity

Status: complete

Checkpoint notes:

- Added Windows-capable libpq loading in `src/Arlen/Data/ALNPg.m` via
  `LoadLibrary` / `GetProcAddress`, `ARLEN_LIBPQ_LIBRARY`, and CLANG64 DLL
  candidates.
- Added Windows-capable ODBC loading in `src/Arlen/Data/ALNMSSQL.m` via
  `LoadLibrary` / `GetProcAddress`, `ARLEN_ODBC_LIBRARY`, and CLANG64/system
  DLL candidates.
- Widened the Windows preview framework build to include `src/Arlen/Data/*.m`
  and exported the data-layer headers from `src/Arlen/Arlen.h`.
- Restored Windows-preview `arlen migrate`, `arlen schema-codegen`, and
  `arlen module migrate` now that the shared adapter initialization path is
  compiled in again.
- Added `tests/phase24/Phase24WindowsTransportSmokeTests.m` plus
  `make phase24-windows-db-smoke`.

Deliverables:

- Add Windows-capable dynamic-library loading seams for PostgreSQL and ODBC
  transport discovery.
- Replace Unix-only `.so` and Linux path assumptions with CLANG64-compatible
  DLL/import-library discovery.
- Add focused Windows smoke coverage for PostgreSQL and MSSQL adapter bring-up.

Acceptance (required):

- PostgreSQL and MSSQL adapters build and load their transport dependencies on
  Windows through a checked-in discovery contract.
- Focused Windows database smoke tests exist for the supported transport level.

## 5.10 Phase 24J: Filesystem + Security Semantics Parity

Status: complete

Checkpoint notes:

- Added explicit Windows filesystem branches in
  `src/Arlen/Support/ALNServices.m` for:
  - reparse-point detection
  - no-follow regular-file reads
  - atomic write replacement
  - path containment normalization
  - non-POSIX private-storage behavior
- Stopped assuming POSIX mode bits are the only privacy contract on Windows;
  the Windows path now preserves the explicit Arlen safety rules while relying
  on the host ACL model instead of fake `0600`/`0700` parity.
- Updated `tests/unit/Phase3ETests.m` so the Windows service/storage assertions
  validate the Windows contract directly instead of asserting POSIX permission
  bits.

Deliverables:

- Define Windows behavior for Arlen's security-sensitive filesystem helpers:
  - private storage expectations
  - no-follow/symlink containment
  - atomic write behavior
  - temp-file handling
  - path canonicalization and reparse-point safety
- Update storage/service code and regression tests to use explicit
  cross-platform semantics instead of assuming POSIX modes map directly.

Acceptance (required):

- Windows implementations of Arlen's filesystem safety rules are explicit and
  tested.
- Security-sensitive file helpers no longer rely on unexamined POSIX
  substitutions for ACL/reparse-point behavior.

## 5.11 Phase 24K: Full Verification + CI Parity

Status: complete

Checkpoint notes:

- Added the checked-in Windows confidence script:
  `tools/ci/run_phase24_windows_preview.sh`
- Added the wider Windows lane:
  `make phase24-windows-confidence`
- Added the self-hosted Windows workflow:
  `.github/workflows/phase24-windows-preview.yml`
- Updated the testing/toolchain docs so the supported Windows matrix now lists:
  - `make phase24-windows-tests`
  - `make phase24-windows-db-smoke`
  - `make phase24-windows-confidence`
- The focused Windows lanes now run linked test executables so discovery and
  exit status stay reliable on CLANG64 instead of depending on stock
  bundle-based `xctest`.
- Ran the full confidence lane on CLANG64 on 2026-03-31 and confirmed:
  - `make phase24-windows-tests`
  - `make all`
  - `make phase24-windows-db-smoke`
  - `make phase24-windows-confidence`
  - `arlen doctor --json`
  - `arlen new`
  - `arlen boomhauer --no-watch --prepare-only`
  - `arlen routes`
- The PostgreSQL smoke lane is now prerequisite-aware when `libpq` is absent
  on the host while still failing on unexpected transport regressions.

Deliverables:

- Expand from focused Windows-safe suites to the wider supported unit and
  integration matrix.
- Add a Windows verification story for:
  - build
  - focused tests
  - broader tests where supported
  - known unsupported lanes
- Decide what parity means for perf, sanitizers, and other Linux-heavy
  confidence lanes on Windows.

Acceptance (required):

- The supported Windows verification matrix is documented and repeatable.
- Windows support claims are backed by broader automated evidence than the
  first-pass focused subset.

## 5.12 Phase 24L: Production Runtime + Deployment Parity

Status: complete

Checkpoint notes:

- Chose the explicit native Windows runtime boundary instead of pretending to
  support `propane` or the first-party jobs worker loop before the process
  model is real.
- Updated `tools/arlen.m`, `bin/propane`, and `bin/jobs-worker` so native
  Windows fails those paths with a clear message instead of a late shell/runtime
  failure.
- Added `docs/WINDOWS_RUNTIME_STORY.md` and linked the Linux-only deployment
  docs back to that support boundary.

Deliverables:

- Decide the Windows production contract for Arlen:
  - native `propane`
  - limited/partial `propane`
  - explicit alternative manager/service story
  - explicit non-support for some production features
- Replace or partition Linux-only deployment guidance such as `systemd`
  runbooks where necessary.
- Document the supported Windows deployment/runtime-manager story clearly.

Acceptance (required):

- Windows production guidance is explicit, truthful, and tested enough to avoid
  misleading users.
- `propane` support on Windows is either implemented with evidence or clearly
  marked out of scope for the supported Windows surface.

## 5.13 Phase 24M: Windows XCTest Discovery + Native Warning Closeout

Status: complete

Checkpoint notes:

- `make phase24-windows-tests` now discovers and executes a non-empty focused
  XCTest set on CLANG64 through the linked `ArlenPhase21TemplateTestsRunner`.
- `make phase24-windows-db-smoke` now discovers and executes a non-empty
  focused XCTest set on CLANG64 through the linked
  `ArlenPhase24WindowsDBSmokeTestsRunner`.
- `make phase24-windows-confidence` now fails hard if focused discovery
  regresses because the linked runners return non-zero on empty discovery.
- The Phase 24 Windows runner contract is now the repo-local helper plus
  linked test executables on CLANG64 instead of stock bundle-based `xctest`.
- The tracked Arlen source portability warnings in
  `src/Arlen/Core/ALNApplication.m` and `src/Arlen/Support/ALNServices.m`
  are resolved; the only residual warning observed in this workspace is the
  upstream CLANG64/GNUstep `-fobjc-exceptions` unused-command-line warning.

Deliverables:

- Stabilize a Windows-focused XCTest path that:
  - loads the focused bundles successfully
  - discovers real tests
  - returns reliable pass/fail exit status on CLANG64
- Tighten the focused Windows lanes so they fail hard when discovery regresses
  instead of accepting `No tests found`.
- Resolve or deliberately document the remaining high-signal Windows compiler
  warnings that still appear during the confidence lane.
- Decide whether the long-term Windows test-runner contract should use:
  - stock `xctest`
  - a repo-local helper
  - checked-in / adjacent `tools-xctest-msys` source integration

Acceptance (required):

- `make phase24-windows-tests` and `make phase24-windows-db-smoke` execute a
  non-empty discovered test set on CLANG64 with reliable exit status.
- `make phase24-windows-confidence` fails when focused test discovery or bundle
  loading regresses.
- The remaining Windows-native compile warnings are either fixed or explicitly
  called out as intentional/documented exceptions.

## 5.14 Phase 24N: `boomhauer` Watch-Mode + Dev-Error Parity

Status: complete on 2026-04-01

Checkpoint notes:

- Windows now runs the app-root `boomhauer` watch loop natively on CLANG64.
- The checked-in runtime parity lane covers:
  - fallback dev error server readiness
  - automatic rebuild retry after build failure
  - recovery back to the real app after source repair
  - signal-safe teardown and rerun hygiene on Windows

Deliverables:

- Implement reliable Windows file watching for app and framework inputs used by
  `boomhauer`.
- Restore Linux-equivalent watch-mode lifecycle behavior on Windows:
  - rebuild/retry loops
  - config/public restart handling
  - lazy fallback dev error server launch
  - recovery after build failures
- Remove the remaining Windows-specific `boomhauer` watch-mode caveats from the
  CLI and Windows docs.

Acceptance (required):

- `arlen boomhauer` on Windows defaults to watch mode with the same user-facing
  semantics and diagnostics as Linux.
- Build failures and subsequent recoveries in watch mode behave equivalently on
  Windows and Linux for supported app-root flows.

## 5.15 Phase 24O: `jobs worker` + Background Runtime Parity

Status: complete on 2026-04-01

Checkpoint notes:

- Native Windows now supports `arlen jobs worker` and `bin/jobs-worker` through
  the same prepare-then-run contract Linux uses for app-root workflows.
- The checked-in runtime parity lane verifies a queued-on-boot job path end to
  end on CLANG64.

Deliverables:

- Implement the Windows-safe worker lifecycle and shutdown/restart behavior
  needed by the jobs loop.
- Support both CLI and direct script entrypoints:
  - `arlen jobs worker`
  - `bin/jobs-worker`
- Verify that module/system job flows operate correctly on Windows under the
  same contract Linux uses today.

Acceptance (required):

- The first-party jobs worker loop runs natively on Windows with equivalent
  lifecycle behavior, diagnostics, and failure handling.
- Queue-backed jobs workflows pass on Windows without requiring Linux or WSL2.

## 5.16 Phase 24P: `propane` + Native Process-Manager Parity

Status: complete on 2026-04-01

Checkpoint notes:

- Native Windows now supports `arlen propane` and `bin/propane` on CLANG64 for
  the checked-in app-root process-manager path.
- The focused runtime parity lane verifies:
  - build-before-launch readiness
  - `/healthz` availability
  - reload via `HUP`
  - clean shutdown via `TERM`

Deliverables:

- Implement a Windows-native process-manager model for `propane` that preserves
  the existing user-facing contract, including propane accessories.
- Support worker supervision, graceful restart/stop behavior, and the
  build-before-launch path that Linux currently provides.
- Define and test the native Windows production-host story:
  - direct process-manager usage
  - service integration where required
  - logging/lifecycle expectations

Acceptance (required):

- `arlen propane` and `bin/propane` run natively on Windows with Linux-equivalent
  supervision semantics and accessory behavior.
- The Windows production story is implementation-backed rather than
  workaround-only documentation.

## 5.17 Phase 24Q: Full Test + Live-Backend Matrix Parity

Status: complete on 2026-04-06

Checkpoint notes:

- `GNUmakefile` now exposes Linux-matching Windows entrypoints for
  `make test-unit`, `make test-integration`,
  `make phase20-postgres-live-tests`, and
  `make phase20-mssql-live-tests`.
- `tools/ci/_phase24_windows_env.sh` standardizes the checked-in Windows
  PostgreSQL and SQL Server LocalDB defaults for parity hosts.
- Verified on the checked-in CLANG64 path in this workspace on 2026-04-06:
  - `make test-unit`
  - `make test-integration`
  - `make phase20-postgres-live-tests`
  - `make phase20-mssql-live-tests`

Deliverables:

- Make the default Windows developer test entrypoints match Linux:
  - `make test-unit`
  - `make test-integration`
  - filtered reruns where supported
- Run the PostgreSQL and MSSQL live-backend suites natively on Windows.
- Standardize the long-term Windows XCTest contract for the broader suite so
  discovery, filtering, and exit status stay trustworthy.

Acceptance (required):

- The default Linux unit/integration and live-backend test entrypoints produce
  equivalent automated coverage on Windows.
- Windows test failures and prerequisites are explicit, automated, and no
  longer limited to preview-scope smoke coverage.

## 5.18 Phase 24R: Perf, Sanitizer, + Fault-Injection Lane Parity

Status: complete on 2026-04-06

Checkpoint notes:

- `tools/ci/run_phase24_windows_parity.sh` and
  `scripts/run_phase24_windows_parity.ps1` now sequence the broader Windows
  perf, sanitizer, hostile-traffic, fault-injection, soak, chaos, and static
  analysis lanes after the default test/live-backend matrix.
- `.github/workflows/phase24-windows-parity.yml` captures the checked-in
  Windows CI contract for those parity lanes, including PostgreSQL DLL pinning
  and the LocalDB-backed MSSQL DSN.
- Verified on the checked-in CLANG64 path in this workspace on 2026-04-06:
  - `tools/ci/run_phase10e_json_performance.sh`
  - `tools/ci/run_phase10g_dispatch_performance.sh`
  - `tools/ci/run_phase10h_http_parse_performance.sh`
  - `tools/ci/run_phase10m_blob_throughput.sh`
  - `tools/ci/run_phase9i_fault_injection.sh`
  - `tools/ci/run_phase10m_backend_parity_matrix.sh`
  - `tools/ci/run_phase10m_protocol_adversarial.sh`
  - `tools/ci/run_phase10m_syscall_fault_injection.sh`
  - `tools/ci/run_phase10m_allocation_fault_injection.sh`
  - `tools/ci/run_phase10m_soak.sh`
  - `tools/ci/run_phase10m_chaos_restart.sh`
  - `tools/ci/run_phase10m_static_analysis.sh`
  - `tools/ci/run_phase10m_sanitizer_matrix.sh`
  - `tools/ci/run_phase11_confidence.sh`

Deliverables:

- Define and implement the Windows equivalents for the supported Linux
  robustness lanes:
  - perf
  - ASan/UBSan where toolchain-supported
  - fault injection
  - hostile-traffic / protocol stress
  - static analysis
- Add CI/workflow coverage for those Windows parity lanes.
- Document any unavoidable Windows-specific substitutions without weakening the
  confidence claims they are meant to carry.

Acceptance (required):

- Windows CI runs parity-grade performance and robustness lanes instead of only
  the preview confidence pack.
- Any remaining Linux-only lanes are explicitly justified and replaced with
  evidence of equivalent confidence on Windows.

## 5.19 Phase 24S: Release, Packaging, + First-Class Platform Closeout

Status: complete

Checkpoint notes:

- Windows docs, CLI entrypoints, and release helpers now reflect the supported
  CLANG64 parity contract rather than a preview boundary.
- The immutable release workflow now ships Windows PowerShell wrappers for
  migrate, start, reload, and stop operations alongside the Linux shell
  helpers.

Deliverables:

- Remove preview-only framing from top-level Windows docs once parity evidence
  exists.
- Define the release/bootstrap/package story for Windows as a first-class
  platform.
- Update contributor, user, and deployment docs so Windows is documented
  alongside Linux rather than as a separate preview exception path.

Completed implementation:

- `tools/deploy/build_release.sh` now packages the framework runtime binaries,
  static library, source/module headers, deploy tooling, and Windows release
  helpers needed by immutable Windows releases.
- `bin/boomhauer`, `bin/jobs-worker`, and `bin/propane` now accept packaged
  framework roots in addition to source checkouts.
- `tools/deploy/windows/{invoke_release_migrate,start_release,send_release_control}.ps1`
  define the checked-in Windows packaged-release contract.
- `docs/WINDOWS_CLANG64.md`, `docs/WINDOWS_RUNTIME_STORY.md`,
  `docs/DEPLOYMENT.md`, `docs/RELEASE_PROCESS.md`, `docs/PROPANE.md`,
  `docs/TOOLCHAIN_MATRIX.md`, `docs/GETTING_STARTED.md`, `README.md`, and
  `docs/README.md` now document Windows as a first-class supported platform.
- `make deploy-smoke` and the targeted deployment integration tests now pass on
  the checked-in Windows CLANG64 host.

Acceptance (required):

- Windows is documented and shipped as a first-class supported platform rather
  than a preview contract.
- Phase 24 can close with no remaining supported-surface behavior gap between
  Windows and Linux.

## 5.20 Phase 24T: PowerShell-First Launcher Wrappers

Status: planned

Rationale:

- The checked-in Windows CLANG64 support currently requires users to enter the
  MSYS2/GNUstep environment explicitly through `scripts/run_clang64.ps1` before
  invoking `arlen` or `boomhauer`.
- That remains a valid platform contract, but it still feels like an explicit
  toolchain step rather than a first-class Windows command surface.
- A thin wrapper layer can preserve the current CLANG64/GNUstep runtime while
  exposing PowerShell-friendly entrypoints that keep working directory,
  argument pass-through, stdout/stderr, long-running console behavior, and exit
  status intact.

Deliverables:

- Add Windows-facing launcher shims for `arlen` and `boomhauer` that can be
  invoked directly from PowerShell and `cmd.exe`.
- Keep those wrappers thin and deterministic:
  - resolve the checked-in CLANG64 bootstrap path
  - translate the current working directory and relevant path arguments
  - delegate to the existing `bin/arlen` and `bin/boomhauer` launchers
  - propagate stdout/stderr, console lifecycle behavior, and exit status
    without creating a second command implementation
- Document the supported invocation contract in the Windows getting-started and
  CLI docs, including any execution-policy or PATH expectations for `.ps1` and
  `.cmd` entrypoints.

Acceptance (required):

- From plain PowerShell on a supported Windows host, `arlen doctor` works
  without the user manually entering `scripts/run_clang64.ps1`.
- From plain PowerShell on a supported Windows host, a scaffolded app can be
  started with `arlen boomhauer --port 3000` or an equivalent first-class
  launcher path without manually entering the CLANG64 shell first.
- Wrapper-based invocation preserves current working directory, argument
  semantics, visible process output, and non-zero exit propagation.

## 6. Exit Criteria Summary

Phase 24 first-pass closeout requires:

- `24A-24E` complete with real build/test evidence
- documented Windows preview scope
- explicit unsupported-surface list

Phase 24 preview-contract closeout requires:

- `24G-24P` complete
- verified Windows-native runtime and app-root workflows
- verified Windows XCTest discovery for the focused CLANG64 bundles
- explicit deployment/runtime-manager guidance for Windows
- updated top-level docs/toolchain references to reflect the supported Windows
  contract

Phase 24 full-parity closeout requires:

- `24A-24T` complete
- Windows carries the same supported test, live-backend, perf, sanitizer, and
  robustness confidence claims as Linux
- Windows has first-class release/install/package/service guidance instead of a
  preview-scoped runtime boundary
- Windows CLI/dev-server entrypoints can be launched from plain PowerShell
  without a manual CLANG64-shell handoff
- top-level docs no longer describe Windows as preview-only

# TSAN reliability investigation — 2026-09-21

## Outcome

TSAN remains informational. The old green nightly runs did not establish race
freedom: a deliberate application-owned race through a Foundation callback was
hidden by the library-wide suppressions. The replacement rules detect it.
Retiring the base-library suppressions exposes unresolved GNUstep findings; a
red informational lane is expected on the currently installed toolchain. Do not
restore broad suppressions merely to recover the old green result.

GitHub issues [1](https://github.com/danjboyd/Arlen/issues/1) and
[2](https://github.com/danjboyd/Arlen/issues/2) were closed after verifying the
February 25 fix and recorded downstream validation. Their historical HTTP
crash is separate from this sanitizer investigation.

## Reproduction

```bash
source tools/source_gnustep_env.sh
python3 tools/ci/test_tsan_reliability.py
python3 tools/ci/tsan_runtime_diagnostics.py --output /tmp/arlen-tsan-diagnostics
bash tools/ci/run_linux_thread_race_nightly.sh
```

The diagnostic compiles `tests/fixtures/sanitizers/tsan_runtime_probe.m` using
clang and the active GNUstep configuration. It runs startup, synchronized
monitor, NSLock, NSOperationQueue, and deliberately racy Foundation-callback
probes both with and without the current suppressions. It retains every log,
compiler command, compiler version, linked library paths, kernel and effective
suppression text. TSAN logs include library build IDs and offsets even where
private symbols are stripped.

A successful positive control must finish, exit 66, and report a data race on
`ALNTSANCanaryCounter`. A crash, timeout, unrelated warning, or silent exit does
not count. Suppressed non-canary probes must finish without findings. Raw
runtime findings are retained as evidence and never described as clean runs.
On this toolchain the queue probe fails the clean-run requirement.

## Findings and disposition

The installed toolchain was Debian clang 19.1.7 with GNUstep base 1.31 and
libobjc 4.6. Base build ID: `7d8b1a2da0aa65efd2b9453dfe58e5b456e5085a`;
libobjc build ID: `9a78da61cb3af8a76a7274420f415c19c7985055`.
The executable probes use clang's linked TSAN runtime. XCTest loads the
instrumented bundle with the existing `clang -print-file-name=libtsan.so`
preload (GCC 14 libtsan on this installation); both paths remain visible.

| Finding | Evidence | Disposition |
| --- | --- | --- |
| Objective-C module/class initialization lock ordering | Foundation-only startup/threaded probes, including `__objc_load` and `objc_send_initialize` | Replace `deadlock:libobjc.so` with those two function-scoped patterns; underlying runtime behavior remains unclassified. |
| Objective-C monitor allocation versus locking | Foundation-only synchronized counter: `objc_sync_enter`, mutex access versus allocation around libobjc offsets `0x1d6c8` and `0x1d9cc` | Replace `race:libobjc.so` with `race:objc_sync_enter`; preserve raw evidence and the application race control. |
| Template registry lock ordering | Unit-bundle constructor `ALNEOCAutoRegister_ALNEOCRender_index_html_eoc` enters a registry monitor and re-enters initialization guarded by the shared NSThread class monitor | Replace registry lazy initialization with `dispatch_once`; a bounded regression verifies registry operations complete while another thread holds the NSThread class monitor. No syntax or rendering contract changes. |
| GNUstep queue lock ordering and mutex lifetime | Foundation-only NSOperationQueue probe; base offsets `0x27673a` (destroy), `0x276a61` (lock), `0x276bfd` (unlock); also seen in the concurrent libpq-loader test | Retire both base-library suppressions and expose these findings. Private symbols in the installed base are stripped. No claim that these are false positives. |
| GNUstep CLI/configuration lock ordering | Restored large-output CLI test: `RunMakeWorkflowCommand`; HTTP probe startup: `ALNConfig loadConfigAtRoot:environment:includeModules:error:` through base mutex and Objective-C monitor paths | Keep visible; do not exempt the instrumented CLI or disable its TSAN options to make the assertion pass. |
| TSAN preload inherited by uninstrumented Bash | Formerly quarantined shell tests | Remove TSAN entries from the child environment before exec, preserve other preload libraries and TSAN_OPTIONS, and remove all 14 TSAN-only early returns. Instrumented child binaries still load their linked sanitizer runtime. |

The original four library-wide rules caused the deliberate Foundation-callback
race to exit zero with no report. With the replacement rules, the same probe
exits 66 and names the application counter. This demonstrates a real coverage
improvement, not proof that every possible race can be observed.

## Coverage and CI contract

The experimental summary reports `unit_methods_started`,
`tsan_excluded_tests` (currently empty), and `runtime_probe_completed`.
Method starts are not an assertion count: unrelated service-dependent opt-in
tests can still return early. A failure before the HTTP probe explicitly leaves
its completion field false.

The nightly wrapper runs the Foundation diagnostics even after the main TSAN
lane fails, preserving the original failure code. Scheduled successes and
failures both upload artifacts. Missing TSAN returns 77 with `unavailable`;
Helgrind is only an explicit local fallback with `ARLEN_REQUIRE_TSAN=0`, and its
summary identifies that different engine. Absence of both engines also fails.

The required sanitizer job runs the harness self-tests, registry validation,
and existing ASAN/UBSAN matrix. The full TSAN nightly remains non-blocking.
The September 19–21 green runs used the previous suppressions and quarantines;
they cannot be used as promotion evidence for this new configuration.

## Remaining work and promotion criteria

Owner: runtime-core. Target: 2026-12-31; this investigation does not extend it.

1. Reproduce the queue and CLI findings with matching unstripped/debug GNUstep
   libraries, then with instrumented base/libobjc. Identify exact methods,
   source revisions, and synchronization visibility before classifying them.
2. Fix Arlen-owned findings; prepare upstream reproductions for confirmed
   GNUstep issues. Keep upstream library changes and toolchain rollout explicit.
3. Audit the remaining function-scoped suppressions against those results;
   retire them when possible. Suppression removal is not resolution of the
   underlying finding, and expiry renewal is not a fix.
4. Require two consecutive clean runs on the **new** configuration, with the
   canary detected, no TSAN exclusions, the full unit suite and HTTP concurrency
   probe completed, and artifacts retained. Only then promote a dependable
   scoped TSAN gate and update branch protection plus CI alignment together.

No upstream library modification or TSAN gate promotion is part of this change.

## Local validation

- Ordinary XCTest unit suite: 759 method starts across 101 passing classes,
  including the restored subprocess tests and template-registry regression.
- Build-policy suite: 48 passing methods after the final summary changes.
- Focused integration checks: suppression acceptance/expiry rejection,
  confidence-pack generation, and serialized HTTP keep-alive passed.
- Five Python harness checks and `make ci-docs` passed.
- TSAN diagnostic controls detect the deliberate application race; unsuppressed
  and narrowed runs expose the queue/CLI/configuration findings above. The full
  TSAN suite and HTTP concurrency probe are not certified clean.

# Open-issue reconciliation for Dan’s review — 2026-10-28

Pinned source: [`e26a755e`](https://github.com/danjboyd/Arlen/commit/e26a755e0c250ec972c99eca9fb51a4259d48307), main / released v0.3.2, tree `f3b303f828870e51cda529dc36459fcdb365e587`. This is a closure **proposal**, not an issue-state update. All eleven reviewed issues were open in the fetched snapshot; none was closed, relabeled or commented on.

This review compares the requested issue bodies/comments with pinned source, named regressions and retained release evidence. It is not a new security audit or benchmark campaign. No production code, Windows design/fixtures, SSE reader, percent-decoder/ALNRequest or ALNSearchModule was changed. Later v0.4.0 work is outside this snapshot.

## Decisions proposed

`fixed` means the reported behavior has an implemented remedy and relevant retained verification within the stated scope. `partial` means completed work and a concrete residual or evidence gap remain. `residual` would mean no supported remedy was found; no whole issue is assigned that status here, but residual work is explicitly listed. A test name in source alone is not a test execution claim.

| Issue | Disposition | Proposed action |
| --- | --- | --- |
| [#275](https://github.com/danjboyd/Arlen/issues/275) | **fixed** | Close the reported behavior within the limits below. |
| [#282](https://github.com/danjboyd/Arlen/issues/282) | **fixed** | Close the reported behavior within the limits below. |
| [#251](https://github.com/danjboyd/Arlen/issues/251) | **partial** | Keep open or split the stated residual before closure. |
| [#283](https://github.com/danjboyd/Arlen/issues/283) | **fixed** | Close the reported behavior within the limits below. |
| [#252](https://github.com/danjboyd/Arlen/issues/252) | **fixed** | Close the reported behavior within the limits below. |
| [#245](https://github.com/danjboyd/Arlen/issues/245) | **partial** | Keep open or split the stated residual before closure. |
| [#248](https://github.com/danjboyd/Arlen/issues/248) | **partial** | Keep open or split the stated residual before closure. |
| [#196](https://github.com/danjboyd/Arlen/issues/196) | **fixed** | Close the reported behavior within the limits below. |
| [#169](https://github.com/danjboyd/Arlen/issues/169) | **partial** | Keep open or split the stated residual before closure. |
| [#114](https://github.com/danjboyd/Arlen/issues/114) | **partial** | Keep open or split the stated residual before closure. |
| [#228](https://github.com/danjboyd/Arlen/issues/228) | **partial aggregate** | H-1/H-2/H-3/H-4/H-6/H-7 are fixed in the stated scope; H-5 retains a replay-test evidence gap. |

## Evidence and provenance

- Qualified candidate `499214fa009650b9911ba6745a9d93653d6156ad` has exactly the same Git tree as pinned main `e26a755e`. This equivalence was checked locally; older `0a85ddc9` receipts were not substituted for final-source evidence.
- [Native Ubuntu 24 ARM64 full normal qualification](https://github.com/danjboyd/Arlen/actions/runs/40601266486): retained JUnit contains 1,393 unit methods (1,378 passed / 15 skipped) and 266 integration methods (264 passed / 2 skipped), zero failures/errors. The selected method results below were extracted from those raw XML reports, not inferred from a green workflow.
- [Canonical strict pair](https://github.com/danjboyd/Arlen/actions/runs/40601263147): two consecutive retained complete unit XML reports, each 1,393 methods / 1,376 passed / 17 skips / zero failures/errors. This is Debian x64 TSan coverage; no full ARM64 TSan unit pass is claimed.
- [Windows preview](https://github.com/danjboyd/Arlen/actions/runs/40601183776): the log names the force-kill regression and reports four runtime-parity tests passed. Synthetic merge `700e27861cd9328f3fa1fdd0be669e53badd8818` has the same `f3b303f8` tree.
- [Tagged release certification](https://github.com/danjboyd/Arlen/actions/runs/40610731134) and its retained reviewed receipt cover the real `tech_demo` smoke and four certification gates. Its sanitizer-specific skips are not full normal-suite coverage. The separate ARM normal XML provides the issue-specific normal results.
- [Machine-readable companion](V040_ISSUE_RECONCILIATION_2026-10-28.json) records source hashes, immutable links, raw JUnit hashes and selected pass/skip results. Raw issue snapshots and the Windows log archive are retained privately in the coordinator evidence directory; no private credentials or host receipts are copied into this document.
- Historical performance figures below come from shipped release notes and `PERFORMANCE_PROFILES.md`; none was remeasured in this task.

## Per-issue findings and draft closure text

### #275: Windows watch children after force-kill — fixed

Windows watch launches now use a native helper instead of the MSYS2 setsid branch. The helper owns a kill-on-close Windows Job Object, launches the server suspended, assigns it before resuming, and waits for the exact parent process. Both app and build-error servers use this path.

Source: [bin/boomhauer:1283](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/bin/boomhauer#L1283), [tools/ALNWindowsWatchChild.h:25](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tools/ALNWindowsWatchChild.h#L25), [tools/boomhauer.m:2158](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tools/boomhauer.m#L2158).

Regression references:

- [Phase24WindowsRuntimeParityTests/testBoomhauerWatchChildrenExitAfterForceKill](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/phase24/Phase24WindowsRuntimeParityTests.m#L278) — retained Windows preview PASS.

Residual / limits: Windows preview run 40601183776 logs this named regression, followed by all four runtime-parity tests passing. Its synthetic merge 700e27861cd9328f3fa1fdd0be669e53badd8818 has the same tree as main. No Windows fixture/design changes or new native tests were made here.

Draft for Dan’s review:

> Propose closing #275 for the reported force-kill orphan/port leak: both native watch-child modes have a passing Windows lifetime regression on the released tree. Keep interactive console Ctrl+C behavior and broader Windows production supervision with the Windows owner; this proposal does not certify those separate contracts.

### #282: File-backed queue duplication, lost updates and shared default path — fixed

ALNFileJobAdapter takes an exclusive sibling .lock around reload/mutate/persist operations, including initialization and leases. The queue-jobs generator uses `<app-root>/var/jobs/state.plist` instead of a shared temporary directory and fails registration if initialization fails. Generated timers can still run in multiple HTTP workers because queue claims now coordinate.

Source: [src/Arlen/Support/ALNServices.m:1210](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/src/Arlen/Support/ALNServices.m#L1210), [tools/arlen.m:4600](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tools/arlen.m#L4600), [docs/PLUGIN_SERVICE_GUIDE.md:23](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/docs/PLUGIN_SERVICE_GUIDE.md#L23).

Regression references:

- [Phase7DTests/testFileJobsCoordinateConcurrentProcesses](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase7DTests.m#L217) — native normal PASS.
- [Phase7DTests/testFileJobsPreserveJobsDuringInterleavedProcessTransactions](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase7DTests.m#L264) — native normal PASS.
- [DeploymentIntegrationTests/testArlenGeneratePluginPresetsCreateServiceTemplates](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/integration/DeploymentIntegrationTests.m#L735) — native normal PASS.

Residual / limits: The file adapter still has no crashed-worker lease recovery or exactly-once side-effect guarantee. Moving every generated timer to a dedicated worker is an architectural option, not a prerequisite for the specific locking fix. Existing generated apps must regenerate or adopt the new template.

Draft for Dan’s review:

> Propose closing #282 for concurrent file-queue duplicate leasing/lost enqueues and the cross-app default-path collision. The retained regressions cover independent producers/consumers and interleaved transactions. Use PostgreSQL/dedicated jobs workers when crashed-lease recovery is required.

### #251: Shared module state and doctor warning — partial

The reported notification preference/inbox lost updates are addressed by authoritative shared state and SQLite catalog transactions. Jobs operator state, search module state and ops history use cross-process reload/mutate/commit paths. Both doctor entrypoints now require state.durable=YES or one worker; a database URL alone no longer silences the warning. The default pending-job adapter remains ALNInMemoryJobAdapter, so pending jobs are still process-local until an application selects a shared adapter.

Source: [modules/notifications/Sources/ALNNotificationsModule.m:1212](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/notifications/Sources/ALNNotificationsModule.m#L1212), [modules/jobs/Sources/ALNJobsModule.m:635](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/jobs/Sources/ALNJobsModule.m#L635), [modules/search/Sources/ALNSearchModule.m:4557](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/search/Sources/ALNSearchModule.m#L4557), [modules/ops/Sources/ALNOpsModule.m:808](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/ops/Sources/ALNOpsModule.m#L808), [tools/arlen.m:1211](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tools/arlen.m#L1211), [bin/arlen-doctor:236](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/bin/arlen-doctor#L236), [src/Arlen/Core/ALNApplication.m:1151](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/src/Arlen/Core/ALNApplication.m#L1151).

Regression references:

- [Phase16ATests/testJobsOperatorStateTransactionsAcrossProcesses](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase16ATests.m#L230) — native normal PASS.
- [Phase16BTests/testNotificationStateTransactionsAcrossProcesses](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase16BTests.m#L567) — native normal PASS.
- [Phase16DTests/testSearchStateTransactionsAcrossProcesses](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase16DTests.m#L475) — native normal PASS.
- [Phase16ETests/testOpsStateTransactionsAcrossProcesses](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase16ETests.m#L219) — native normal PASS.
- [DeploymentIntegrationTests/testBuiltDoctorReportsProductionMultiWorkerState](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/integration/DeploymentIntegrationTests.m#L6149) — native normal PASS.

Residual / limits: state.durable is an operator declaration, not automatic per-module backend verification. Use one scheduler; enqueue and scheduler bookkeeping are separate. External search engine publication still needs one writer per resource or backend fencing. docs/PROPANE.md still says an existing database contract can satisfy the first warning version: that sentence is historical wording that disagrees with current doctor code/tests and merits a focused docs follow-up. No owner source was changed.

Draft for Dan’s review:

> Keep #251 open for the remaining default-adapter/deployment contract, or close only after moving that residual into an explicitly reviewed follow-up. Record the notification, jobs-operator, search, ops lost-update fixes and database-URL warning fix as completed sub-items; do not describe default in-memory pending jobs as shared.

### #283: Bounded default in-memory cache and mail retention — fixed

The default cache now keeps at most 1,024 entries, updates LRU order on hits/writes, and sweeps expired entries when writing a non-null value. The mail adapter retains only the latest 100 deliveries. These are the two unbounded collection growth paths in the report.

Source: [src/Arlen/Support/ALNServices.m:1873](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/src/Arlen/Support/ALNServices.m#L1873), [src/Arlen/Support/ALNServices.m:1923](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/src/Arlen/Support/ALNServices.m#L1923), [src/Arlen/Support/ALNServices.m:3304](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/src/Arlen/Support/ALNServices.m#L3304).

Regression references:

- [Phase7DTests/testDefaultCacheIsBoundedLRUAndSweepsExpiredKeysOnWrite](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase7DTests.m#L323) — native normal PASS.
- [Phase7DTests/testDefaultMailRetainsOnlyLastHundredDeliveries](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase7DTests.m#L342) — native normal PASS.

Residual / limits: These are entry-count bounds, not byte caps. Up to 100 messages can retain message content, and expired cache entries can remain until another read/write. Optional startup warnings and alternative production adapters are separate improvements; do not claim that the bounded defaults are a production mail delivery service.

Draft for Dan’s review:

> Propose closing #283 for unbounded entry retention: the cache is capped at 1,024 LRU entries and sweeps expired entries on writes; the mail adapter retains the latest 100 deliveries. Both named regressions passed in the retained release suite.

### #252: Prevent multiplied built-in rate budgets under propane — fixed

Startup now rejects enabled built-in rate limiting with more than one configured worker, including exported ARLEN_PROPANE_WORKERS/legacy overrides. Propane also refuses before launching workers. The request limiter itself remains process-local; configuration and deployment docs direct multi-worker deployments to an ingress limiter.

Source: [src/Arlen/Core/ALNApplication.m:2026](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/src/Arlen/Core/ALNApplication.m#L2026), [bin/propane:683](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/bin/propane#L683), [docs/CONFIGURATION_REFERENCE.md:912](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/docs/CONFIGURATION_REFERENCE.md#L912), [docs/PROPANE.md:360](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/docs/PROPANE.md#L360).

Regression references:

- [ApplicationTests/testMultiWorkerRateLimitFailsBeforeStartup](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/ApplicationTests.m#L2982) — native normal PASS.
- [ConfigTests/testRateLimitStartupUsesDefaultWorkersAndEnvironmentOverrides](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/ConfigTests.m#L20) — native normal PASS.
- [HTTPIntegrationTests/testPropaneRejectsMultiWorkerRateLimiterBeforeLaunchingWorkers](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/integration/HTTPIntegrationTests.m#L5496) — native normal PASS.

Residual / limits: This is a fail-closed configuration fix, not a shared-store limiter. Independent app instances/hosts still require an external deployment-wide quota. Authentication account limits are a separate mechanism.

Draft for Dan’s review:

> Propose closing #252 for silently multiplying a configured request budget by the propane worker count. The unsafe configuration now fails before serving or launching workers. Run one worker for the built-in limiter, or disable it and enforce the shared budget at ingress.

### #245: Header serialization and construction cost — partial

The serializer now writes NSData bytes; constant security headers are prepared once per middleware/application instance; validation uses cached character sets, and ordered insertion avoids the redundant linear containsObject scan. The later 3fa59adf construction follow-up resolves some residuals listed in the older handoff. Public setters still validate dynamic inputs. The shared serialization fast path remains restricted to its standard small header layout.

Source: [src/Arlen/HTTP/ALNResponse.m:852](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/src/Arlen/HTTP/ALNResponse.m#L852), [src/Arlen/HTTP/ALNResponse.m:564](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/src/Arlen/HTTP/ALNResponse.m#L564), [src/Arlen/MVC/Middleware/ALNSecurityHeadersMiddleware.m:44](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/src/Arlen/MVC/Middleware/ALNSecurityHeadersMiddleware.m#L44), [docs/internal/PERFORMANCE_PROFILES.md:5](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/docs/internal/PERFORMANCE_PROFILES.md#L5).

Regression references:

- [ResponseTests/testSerializedHeaderBytesAreExact_Issue245](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/ResponseTests.m#L129) — native normal PASS.
- [ResponseTests/testPreparedHeadersPreserveValidationSnapshotsOrderingAndOverrides](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/ResponseTests.m#L12) — native normal PASS.
- [MiddlewareTests/testSecurityHeaderSubclassRetainsValidatedDynamicOverrides](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/MiddlewareTests.m#L1373) — native normal PASS.

Residual / limits: Release notes retain historical 1.6–2x serializer evidence; PERFORMANCE_PROFILES records Windows construction trials (32.1% middleware, 7.2% dynamic32). They are distinct historical microbenchmarks, not new measurements on e26a755e. The standard-header cache is not broadened to the full default 19-header layout. No benchmark campaign was run.

Draft for Dan’s review:

> Keep #245 open as a performance residual, or split it before closing the completed byte-serialization and constant-header construction work. Exact wire bytes/ordering/overrides are covered. Do not present this as elimination of the original 35–40% end-to-end request CPU share.

### #248: JSON logger encoding cost — partial

JSON log output now passes serializer UTF-8 data to emitLogData:, appends one newline, and writes the bytes. The NSData-to-NSString-to-NSData round-trip is gone. JSON serialization and a synchronous per-logger sink lock remain, and production access logging is still enabled at the configured INFO threshold.

Source: [src/Arlen/Support/ALNLogger.m:222](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/src/Arlen/Support/ALNLogger.m#L222), [src/Arlen/Support/ALNLogger.m:229](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/src/Arlen/Support/ALNLogger.m#L229), [src/Arlen/Core/ALNApplication.m:5890](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/src/Arlen/Core/ALNApplication.m#L5890).

Regression references:

- [LoggerTests/testShouldLogLevelRespectsMinimumLevel](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/LoggerTests.m#L53) — native normal PASS.
- [LoggerTests/testLoggerDropsAndDoesNotBlockWhenSinkIsFull_ARLEN_BUG_033](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/LoggerTests.m#L102) — native normal PASS.
- [LoggerTests/testTextLoggerEscapesControlCharactersInFields](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/LoggerTests.m#L182) — native normal PASS.

Residual / limits: The original fix commit 328ce73c explicitly says partial. Existing logger regressions cover levels, bounded POSIX backpressure and text escaping; they are not a dedicated JSON byte-equivalence benchmark. Windows sink behavior remains synchronous. No asynchronous sink, lock-free queue or new performance result is claimed.

Draft for Dan’s review:

> Keep #248 open for the remaining logging-cost question, or split before closing the redundant UTF-8 conversion sub-item. The targeted byte path is shipped; the retained 10–15% access-log-line improvement is not a claim that the original 25–33% request CPU overhead has disappeared.

### #196: Concurrent upload 500s caused by runner temporary space exhaustion — fixed

The issue owner confirmed ENOSPC and explicitly made closure conditional on #203. Current Linux workflows set TMPDIR, TMP and TEMP to a private per-job on-disk runner directory; setting all three matters because GNUstep uses TEMP/TMP. The retained complete native ARM integration report executes the unchanged concurrent 20 MiB multipart/body-limit case successfully.

Source: [.github/workflows/linux-quality.yml:29](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/.github/workflows/linux-quality.yml#L29), [.github/workflows/linux-sanitizers.yml:29](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/.github/workflows/linux-sanitizers.yml#L29), [tests/fixtures/http/body_limits_probe.py:1](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/fixtures/http/body_limits_probe.py#L1).

Regression references:

- [HTTPIntegrationTests/testPerRouteBodyLimitsSpoolAndBoundMemoryOnBothBackends](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/integration/HTTPIntegrationTests.m#L4342) — native normal PASS.

Residual / limits: This does not claim all test temp leaks are fixed or that arbitrary disk-full multipart failures now return 503. The single issue comment identifies per-job temp isolation as the lasting fix; storage-pressure response policy is separate.

Draft for Dan’s review:

> Propose closing #196: the confirmed runner ENOSPC cause is isolated by the merged per-job TMPDIR/TMP/TEMP setup, and the original both-backends concurrent upload regression passes in retained release evidence. Keep developer-machine fixture leaks tracked separately in #210.

### #169: Clean-checkout deploy-smoke packaging — partial

build_release.sh now packages tools/platform.sh and detects app_lite.m or any src/**/*.m, matching propane. Release certification runs smoke_release.sh against examples/tech_demo, and the retained full integration suite passes the release smoke/runbook regression. However, a missing compiled app still falls through to a manifest path: the promised app_binary_missing guard and specifically named non-main-source regression are absent.

Source: [tools/deploy/build_release.sh:126](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tools/deploy/build_release.sh#L126), [tools/deploy/build_release.sh:841](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tools/deploy/build_release.sh#L841), [tools/deploy/build_release.sh:830](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tools/deploy/build_release.sh#L830), [tools/ci/run_release_certification.sh:52](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tools/ci/run_release_certification.sh#L52).

Regression references:

- [DeploymentIntegrationTests/testReleaseBuildActivateAndRollbackScripts](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/integration/DeploymentIntegrationTests.m#L511) — native normal PASS.
- [DeploymentIntegrationTests/testReleaseSmokeScriptValidatesDeployRunbook_ARLEN_BUG_019](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/integration/DeploymentIntegrationTests.m#L597) — native normal PASS.

Residual / limits: The two existing tests do not specifically instantiate the promised no-main.m fixture; inventory/source searches find no testReleasePackagesBinaryForAppWithoutMainSource. The tagged certification is retained evidence, not a new clean-checkout deploy-smoke run in this reconciliation.

Draft for Dan’s review:

> Keep #169 open only for the missing fail-fast app_binary_missing diagnostic and explicit non-main-entry-point regression, or move those to a reviewed follow-up before closing the original packaging failures. The platform helper and broad source detection fixes are shipped, and certification now exercises the real tech_demo release smoke.

### #114: Expectation-based test waits — partial

Shared ALNTestWaitUntil, ALNTestWaitForTaskExit and ALNTestWaitForTCPPort helpers exist and use XCTWaiter when available. The docs gate runs a non-increasing sleep baseline lint. The current baseline still permits eight unannotated waits in Phase24WindowsRuntimeParityTests.m; the original comment counted nine before later edits.

Source: [tests/shared/ALNTestWait.h:26](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/shared/ALNTestWait.h#L26), [tests/shared/ALNTestWait.m:30](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/shared/ALNTestWait.m#L30), [tools/ci/check_test_sleeps.py:26](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tools/ci/check_test_sleeps.py#L26), [tests/fixtures/testing/test_sleep_baseline.json:4](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/fixtures/testing/test_sleep_baseline.json#L4).

Regression references:

- [Phase24WindowsRuntimeParityTests/testBoomhauerWatchRecoversFromBuildFailure](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/phase24/Phase24WindowsRuntimeParityTests.m#L304) — source reference; not a newly executed test.

Residual / limits: The current lint passes with eight baseline entries; that is not proof of zero sleeps. Annotated intentional delays and the toolchain fallback remain legitimate. Windows source/fixtures were read only here.

Draft for Dan’s review:

> Keep #114 open for the remaining eight Windows runtime-parity waits. Shared waiter helpers, the initial conversions and the monotonic lint are complete. Ask the Windows fixture owner to convert or justify the remaining calls individually; no broad lifecycle rewrite is proposed.

## #228 split by sub-item

Keep the aggregate issue open until Dan accepts the individual dispositions and either completes or separately tracks H-5. This proposed split does not create follow-up issues or update checkboxes remotely.

| Sub-item | Disposition | Remaining boundary |
| --- | --- | --- |
| H-1 observability / OpenAPI | fixed | Production controls and explicit opt-ins; custom environment names need their own observability settings. |
| H-2 MCP tools/list | fixed | Tool authors must declare sensitive-tool policy. |
| H-3 bearer-token tables | fixed | Old plaintext links invalid; backups/mail content outside this claim. |
| H-4 enumeration / forgot-password follow-up | fixed | Built-in production-like flow; app hooks and dev compatibility remain app-owned. |
| H-5 SMS cookie replay | partial | Account-scoped DB reservations implemented; direct stale-SMS-cookie regression not evidenced. |
| H-6 inbox href | fixed | External HTTP(S) remains intentional. |
| H-7 LIKE wildcards | fixed | Trigram/fuzzy branch remains intentional. |

### H1: Production observability and route-catalog exposure — fixed

In environment=production, /metrics and /clusterz return 404 unless a token, loopback-only restriction or explicit operabilityAnonymous opt-in is configured. Token comparison is constant-time, and loopback access rejects forwarded-header proxy traffic. OpenAPI routes are unavailable outside development/test until publicInProduction is enabled.

Source: [src/Arlen/Core/ALNApplication.m:3197](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/src/Arlen/Core/ALNApplication.m#L3197), [src/Arlen/Core/ALNApplication.m:2610](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/src/Arlen/Core/ALNApplication.m#L2610), [docs/CONFIGURATION_REFERENCE.md:468](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/docs/CONFIGURATION_REFERENCE.md#L468).

Regression references:

- [ApplicationTests/testOperabilityEndpointsAreDisabledInProductionUntilAccessIsConfigured](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/ApplicationTests.m#L1900) — native normal PASS.
- [ApplicationTests/testOperabilityEndpointsStayAnonymousByDefaultAndCanBeRestricted](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/ApplicationTests.m#L1856) — native normal PASS.
- [ApplicationTests/testOpenAPIRouteCatalogRequiresExplicitProductionOptIn](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/ApplicationTests.m#L1935) — native normal PASS.

Residual / limits: The old 0.3.0 release note says anonymous by default. Current source and 0.3.1 tests supersede that historical statement for environment=production. A custom environment other than production must set its observability controls explicitly.

Draft for Dan’s review:

> Propose marking H-1 complete for production defaults and explicit access controls. Preserve the documented development/non-production behavior and operator opt-ins; do not claim every custom environment name automatically makes /metrics private.

### H2: MCP catalog authorization — fixed

tools/list filters required roles/scopes, assurance age and route-policy visibility without executing handlers. tools/call retains full enforcement. A deliberately roleless/scopeless tool can still be listed/called by an authenticated subject, as its declared policy allows.

Source: [modules/mcp/Sources/ALNMCPModule.m:520](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/mcp/Sources/ALNMCPModule.m#L520).

Regression references:

- [MCPModuleTests/testToolsListOnlyShowsToolsTheCallerMayCall](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/MCPModuleTests.m#L213) — native normal PASS.
- [MCPModuleTests/testToolsListUsesAssuranceAgeAndRoutePoliciesWithoutRunningTools](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/MCPModuleTests.m#L235) — native normal PASS.

Residual / limits: Catalog filtering is not execution of arbitrary application guards or tool handlers. The regression explicitly retains public.ping for an authenticated visitor, while hidden admin/scoped calls remain denied.

Draft for Dan’s review:

> Propose marking H-2 complete for unauthorized catalog disclosure. Tool authors must still declare requiredRoles/scopes for sensitive custom tools; a tool with no requirements is intentionally available within its enclosing authentication contract.

### H3: Reset and verification token storage — fixed

New random reset/verification bearer tokens are transformed by AMStoredBearerToken before insertion; consumption looks up the digest, not the presented plaintext. Existing plaintext links are invalidated by the lookup contract and must be reissued. Single-use consumption and reset invalidation of older tokens are also covered.

Source: [modules/auth/Sources/ALNAuthModule.m:388](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/auth/Sources/ALNAuthModule.m#L388), [modules/auth/Sources/ALNAuthModule.m:2738](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/auth/Sources/ALNAuthModule.m#L2738), [modules/auth/Sources/ALNAuthModule.m:2749](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/auth/Sources/ALNAuthModule.m#L2749), [docs/AUTH_MODULE.md:170](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/docs/AUTH_MODULE.md#L170).

Regression references:

- [Phase13ETests/testBearerLinksStoreOnlyTokenDigests](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase13ETests.m#L1152) — native normal PASS.
- [Phase13ETests/testPasswordResetTokenIsSingleUseAndRetiresOlderTokens](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase13ETests.m#L1203) — native normal PASS.
- [Phase13ETests/testPasswordChangeRetiresOutstandingResetTokens](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase13ETests.m#L1256) — native normal PASS.

Residual / limits: This does not claim that mailboxes, provider delivery records, old backups or historical rows contain no plaintext. A user-facing bearer link necessarily reaches its intended recipient; this issue is the token-table account-takeover path.

Draft for Dan’s review:

> Propose marking H-3 complete for usable plaintext bearer tokens in auth token tables. New rows contain SHA-256 digests and old plaintext links no longer redeem. Request replacement links after upgrading.

### H4: Built-in auth enumeration and forgot-password mail timing — fixed

Unknown-email login spends an Argon2id verification; registration gives generic responses for existing and new addresses without automatic sign-in. Durable registration/forgot-password paths queue work for both address cases, with token creation and mail outside the HTTP request. Production-like local-password/mail setups reject synchronous mail and registration auto-login. Queue failure returns a generic 503; new-account creation and mail enqueue are atomic.

Source: [modules/auth/Sources/ALNAuthModule.m:474](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/auth/Sources/ALNAuthModule.m#L474), [modules/auth/Sources/ALNAuthModule.m:5397](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/auth/Sources/ALNAuthModule.m#L5397), [modules/auth/Sources/ALNAuthModule.m:5612](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/auth/Sources/ALNAuthModule.m#L5612), [docs/AUTH_MODULE.md:131](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/docs/AUTH_MODULE.md#L131).

Regression references:

- [Phase13FTests/testUnknownEmailLoginStillVerifiesADummyPasswordHash](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase13FTests.m#L92) — native normal PASS.
- [Phase13ETests/testRegistrationDoesNotRevealExistingAddressOrStartSessionByDefault](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase13ETests.m#L1569) — native normal PASS.
- [Phase13ETests/testDurableAuthMailQueuesBeforeSendingAndKeepsUnknownAddressesGeneric](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase13ETests.m#L1432) — native normal PASS.
- [Phase13ETests/testDurableAuthMailQueueFailureRollsBackRegistrationAndKeepsResetResponsesGeneric](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase13ETests.m#L1484) — native normal PASS.
- [Phase13ETests/testUnsafeRegistrationAndMailModesFailStartupOutsideDevelopmentAndTest](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase13ETests.m#L1111) — native normal PASS.

Residual / limits: The request still performs a durable enqueue and registration database work; this is not a zero-latency or mathematically constant-time claim. Custom hooks may reveal timing. Historical 0.3.0 synchronous-mode wording was superseded by the 0.3.1 startup rejection.

Draft for Dan’s review:

> Propose marking H-4 complete for built-in production-like registration/login/forgot-password behavior, including Dan’s forgot-password timing follow-up. Apply the auth/jobs migrations, configure durable jobs/publicBaseURL and run its worker. Preserve separate review of app-owned registration hooks and explicitly enabled development compatibility modes.

### H5: Replayed SMS cookie attempt counters — partial

The cookie still carries UI/session counters, but both SMS send and verification reserve an account-scoped attempt in the database before invoking the provider. They fail closed if the attempt-limit schema is unavailable. This addresses the identified trust boundary in source. No dedicated regression that replays a stale SMS cookie through those two flows was found in the pinned test inventory/source or selected retained release evidence.

Source: [modules/auth/Sources/ALNAuthModule.m:4318](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/auth/Sources/ALNAuthModule.m#L4318), [modules/auth/Sources/ALNAuthModule.m:4467](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/auth/Sources/ALNAuthModule.m#L4467), [modules/auth/Migrations/004_auth_totp_limits.sql:1](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/auth/Migrations/004_auth_totp_limits.sql#L1).

Regression references:

- [AuthMFALimitsTests/testTOTPLocksAfterRepeatedFailuresAndResetsOnSuccess](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/AuthMFALimitsTests.m#L237) — native normal PASS; related coverage, not a stale-SMS-cookie replay regression.
- [Phase13AuthAdminIntegrationTests/testAuthModuleSupportsSMSFactorManagementAndKeepsTOTPPreferred](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/integration/Phase13AuthAdminIntegrationTests.m#L1884) — native normal PASS; related coverage, not a stale-SMS-cookie replay regression.

Residual / limits: Generic TOTP/account-limit and SMS management tests are related coverage, not direct proof of stale SMS-cookie resistance. No external SMS calls, new fixtures or full audit were run; source review alone is not labeled end-to-end replay validation.

Draft for Dan’s review:

> Keep H-5 open as a narrow verification follow-up: retain the implemented server-side SMS attempt reservations, then add a stale-cookie replay regression for sends and failed verifies proving provider calls remain bounded across sessions/workers and missing-schema handling fails closed. This reconciliation does not assert the old bypass still reproduces.

### H6: Notification inbox link schemes — fixed

NMSafeInboxHref accepts http/https URLs with a host or relative paths, rejecting controls, backslashes, protocol-relative links and other schemes. The controller places only the sanitized linkHref into display entries; the HTML template emits a link only when that field is nonempty.

Source: [modules/notifications/Sources/ALNNotificationsModule.m:176](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/notifications/Sources/ALNNotificationsModule.m#L176), [modules/notifications/Sources/ALNNotificationsModule.m:3045](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/notifications/Sources/ALNNotificationsModule.m#L3045), [modules/notifications/Resources/Templates/inbox/index.html.eoc:35](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/notifications/Resources/Templates/inbox/index.html.eoc#L35).

Regression references:

- [Phase14NotificationsIntegrationTests/testInboxRendersOnlySafeDeepLinksAndPaginates](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/integration/Phase14NotificationsIntegrationTests.m#L290) — native normal PASS.

Residual / limits: External http/https links remain allowed by design. This is a scheme-safety rule, not a same-origin-only destination allowlist.

Draft for Dan’s review:

> Propose marking H-6 complete for unsafe link schemes in the HTML inbox. Non-http(s) schemes render without a link; the integration regression exercises safe and unsafe destinations.

### H7: PostgreSQL autocomplete LIKE wildcards — fixed

STEscapedLikePattern escapes backslash, percent and underscore before appending the intended prefix wildcard. Both LIKE clauses declare the escape character and continue to use bound parameters/resource scope.

Source: [modules/search/Sources/ALNSearchModule.m:105](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/search/Sources/ALNSearchModule.m#L105), [modules/search/Sources/ALNSearchModule.m:2409](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/modules/search/Sources/ALNSearchModule.m#L2409).

Regression references:

- [Phase27SearchTests/testPostgresAutocompleteTreatsLikeWildcardsLiterally](https://github.com/danjboyd/Arlen/blob/e26a755e0c250ec972c99eca9fb51a4259d48307/tests/unit/Phase27SearchTests.m#L993) — native normal PASS.

Residual / limits: Fuzzy/trigram matching remains intentional in the alternative branch; the fix is not removal of every broad search behavior. ALNSearchModule was read only, and no search benchmarking or owner changes were made.

Draft for Dan’s review:

> Propose marking H-7 complete: user-supplied percent/underscore/backslash are literal in the PostgreSQL prefix LIKE pattern. The retained native normal suite executes the PostgreSQL wildcard regression without skipping it.

## Review boundary and follow-ups

- Proposed closures: #275, #282, #283, #252 and #196. These have scoped implementation and retained relevant execution evidence.
- Keep or split: #251 default pending-job sharing/doctor attestation; #245 and #248 measured performance residuals; #169 missing fail-fast diagnostic/explicit fixture; #114 eight Windows waits; #228 H-5 direct replay validation.
- #210 remains a separate fixture-cleanup issue. A ConfigTests-only change, if prepared, belongs in a separate draft PR and does not justify closing all temp-directory leaks.
- No closure text is posted by this task. Dan decides whether to close, split, relabel or request additional narrow verification. No production changes, merges, tags or broad audit/benchmark work are included.

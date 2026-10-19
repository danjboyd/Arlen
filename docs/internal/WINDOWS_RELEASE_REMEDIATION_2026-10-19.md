# Windows release remediation verification

This private integration checkpoint starts from public main
`1ccbb63654ca432d0a8a53b7ea445115cd113967`. The inherited Windows audit head
`75bfece5c40ed82395b0b3e88e7313210d1de8a1` is already an ancestor of that baseline.
This document is engineering evidence, not a release certification or advisory
publication decision.

## Remediation coverage

| Assigned item | Change | Regression evidence |
| --- | --- | --- |
| DATA-16 | Guard module request/upstream JSON and enforce backend-independent depth limit | JSONSerializationTests: depth boundary, escaped strings, UTF-16/32, scalar/container parity |
| RT-01 | Receive-only channel subscriptions and default same-authority browser Origin checks; route owns authorization | HTTPIntegrationTests/testRealtimeOriginsReceiveOnlyChannelsAndWindowsStaticPaths; updated channel/lifecycle expectations |
| RT-02 | Session-owned WS queue: 128 frames / 1 MiB; event queue: 1024 events / 1 MiB; overflow disconnects; realtime writes have five-second total deadline | RealtimeFanoutTests: stalled transport cannot affect healthy consumer; bounded queue; wire channel checks |
| WIN-01 | Final Windows handle paths resolve junctions and short names before containment and extension checks; reject streams/device syntax | Native wire test creates junction and named stream; tests actual short alias when volume enables it |
| SSE fields | Reject unsafe event/id fields and invalid event-type tokens | ControllerTests and Phase33EHTests |
| HTTP client headers | Reject invalid header names and CR/LF/NUL values before request construction/transport | HTTPClientTests |
| WIN-02 | SO_EXCLUSIVEADDRUSE on Windows listener | Native wire regression attempts duplicate bind |
| llhttp | Unmodified upstream 9.4.3 sources and provenance | Native C framing regression, including empty TE + CL and valid CL control; RequestTests backend matrix |
| #282 | Cross-process lock on initialization and state operations; app-local queue preset; fail storage initialization explicitly | Phase7DTests/testFileJobsCoordinateConcurrentProcesses: four producers/consumers, 200 unique jobs, no duplicates or losses |
| #283 | Cache 1024-entry LRU + expired-key sweep on write; diagnostic mail last 100 deliveries | Phase7DTests retention/eviction regressions |

Standalone Windows executables exposed GNUstep failures when setting POSIX
permission attributes. Private service storage now enforces a protected
current-user DACL through native handles; it rejects a final reparse point.
The ordinary file queue still has no abandoned-lease recovery. Cache values
and individual mail payloads have no byte-size cap; retained entry counts are
bounded. Generic custom realtime subscribers remain responsible for their own
callback behavior; network sessions only enqueue on publisher threads.

## Reproduction

Use `scripts/run_clang64.ps1 -WorkingDirectory <this-worktree> -InnerCommand ...`;
the wrapper initializes the managed clang GNUstep environment. Run:

```sh
make -j4 arlen boomhauer build-tests
make test-unit
make test-integration-filter TEST=HTTPIntegrationTests/testRealtimeOriginsReceiveOnlyChannelsAndWindowsStaticPaths
make test-integration-filter TEST=HTTPIntegrationTests/testWebSocketChannelPubSubFanout
make llhttp-framing-tests
make update-test-inventory
make docs-api docs-html ci-docs
```

Unit tests use the pinned vendored tools-xctest runner. Native Windows defaults
to the legacy HTTP parser; the independent C regression always exercises the
vendored llhttp code. The unit inventory contains 1113 methods and the integration
inventory 223 at this checkpoint. Platform/optional-service skips remain explicit.

Local logs are in the worktree root (`tests-unit-final.log`, `tests-wire-final.log`,
`tests-channel.log`, `tests-llhttp.log`, `tests-buildpolicy2.log`, and documentation
logs). CI records JUnit under `test-results/`. Earlier failed iterations remain
in logs; use the final logs for current results.

Full combined-candidate validation on GNUstep Linux and Apple, plus exact SHA
certification, belongs to the release coordinator after integration. Existing
applications must re-vendor affected module sources and rebuild.

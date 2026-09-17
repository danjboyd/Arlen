# GNUstep #783 upstream verification — 2026-09-17

## Conclusion

The custom-run-loop HTTP(S) scheduling defect reported in
[libs-base #783](https://github.com/gnustep/libs-base/issues/783) is fixed in the
tested master revision, **provided the connection is explicitly started after
scheduling**. The original reproducer deliberately omitted `start` to avoid the
old implementation's duplicate-start behavior. The patched scheduling method no
longer queues `start`, so the reproducer needs `[c start]` after scheduling.

This does not certify master for adoption or justify removing Arlen's libcurl
workaround. The metadata regression class exposes a separate worker subprocess
termination problem with this master build. No production code, installed
toolchain, CI lane, or deployment was changed. No upstream comment was posted.

## Revisions and isolation

- Arlen: `1db6c9dc5165d851b5085fb616793f22d24c5bad`.
- Installed baseline: GNUstep Base 1.31.1 from
  `/usr/GNUstep/System/Library/Libraries/libgnustep-base.so.1.31.1`.
- Tested upstream master: `f014cd06227f790cb8e9ff19da6db5538672527a`.
- Scheduling fix: `a79c99eb8439fcf46d7aabc31c253dd3aa15b534`, plus the missing
  scheduler implementation in `f4fd410b8091b73c07670191e90b4aeb47a792e8`.
- Compiler: Debian clang 19.1.7; existing libobjc2 runtime, GNUstep 2.2 ABI.
- Master was built in `/tmp/arlen-783-base`, using `./configure CC=clang
  CXX=clang++` and `make -j8` after sourcing Arlen's GNUstep bootstrap. No
  `make install` was run. `LD_LIBRARY_PATH` selects the build-tree library.
- `ldd` confirms the probe and vendored XCTest runner load that library and the
  existing `/usr/GNUstep/System/Library/Libraries/libobjc.so.4.6`.
- Baseline library SHA-256:
  `b27956c4a17f509c89c2cf603583bc4097ef409389288dde6ba99587f909aa4c`.
- Built library SHA-256:
  `ef1886fcea81726ed1a8e383585eeb982a845803e934879148556bcf2b5374ef`.

This is an installed-baseline versus pinned-master comparison, not a bisect or
proof that every difference between those libraries originates in #783.

## Results

| Check | Installed baseline | Patched master |
| --- | --- | --- |
| Exact issue reproducer, public Entra URL, custom mode | 2-second deadline; no callbacks | Lifecycle change tested separately below |
| Exact issue reproducer, public Entra URL, default mode | HTTP 200, 1728 bytes | Lifecycle change tested separately below |
| Loopback HTTP, custom mode, main and worker | No completion by 2 seconds | HTTP 200, exact `{}` body, about 1.4 ms |
| Loopback HTTP, default mode, main and worker | Pass | Pass |
| Schedule without explicit start, both modes/threads | Scheduling implicitly starts | No callbacks, as expected from changed lifecycle |
| Live Entra discovery then returned JWKS URL, both modes/threads | Original discovery control above | All 8 requests pass; HTTP 200, valid JSON, no transport errors |
| 50 sequential successful requests per mode/thread | 100 default-mode requests pass | 200 custom/default-mode requests pass |
| Stalled and trickling socket bodies, both modes/threads | Not rerun in standalone baseline probe | All 8 cases meet the caller's 300 ms monotonic deadline and cancel |
| Untrusted TLS with verification explicitly enabled | Both default-mode thread cases reject | All 4 mode/thread cases reject |
| Peer disconnect without response | Default mode incorrectly reports finish, status 0 | Same anomaly in both modes |
| Arlen `MetadataTransportTests`, live tenant enabled | All 4 methods pass | 3 pass; worker socket method hangs in fixture teardown |

The successful HTTP checks require completion, status 200, exact expected body,
and no error; `done=1` alone is not treated as success. Live checks require valid
JSON. The probe cancels and unschedules, then pumps both modes for 50 ms and
checks for additional callbacks; none were observed. No duplicate-start warning
was emitted in these patched runs. Stall/trickle bounds are enforced by the
probe's own deadline, not a claim about Foundation's total-timeout guarantees.

Repeated-request FD counts rise by 2–5 descriptors from a cold process on both
libraries. These measurements include lazy runtime initialization and do not
establish a leak or prove leak freedom; no per-request exhaustion was observed.

Live Foundation TLS checks explicitly set `GS_TLS_VERIFY_S=YES` and
`GS_TLS_CA_FILE=/etc/ssl/certs/ca-certificates.crt`. They do not certify all TLS
defaults, hostname mismatch handling, or a replacement metadata transport.

## Separate subprocess termination finding

The patched worker socket test completes its HTTP assertions but hangs at
`MetadataTransportTests.m:73`, in `[peer waitUntilExit]` after `[peer terminate]`.
A focused rerun times out after 20 seconds; its baseline counterpart passes.
Backtraces show the main thread waiting for the operation and the worker polling
inside `NSTask waitUntilExit`.

A separate [NSTask probe](reproducers/gnustep-783/task-probe.m), independent of
HTTP and XCTest, launches `/bin/sleep 60`, calls `terminate`, waits up to 500 ms,
and uses SIGKILL to clean up if needed:

```text
baseline main:   SigBlk=0000000000000000 exitedAfterTERM=1
baseline worker: SigBlk=0000000000000000 exitedAfterTERM=1
master main:     SigBlk=0000000000000000 exitedAfterTERM=1
master worker:   SigBlk=fffffffe3bfbea27 exitedAfterTERM=0
```

That worker mask includes SIGTERM. The tested source's `posix_spawn` path resets
signal dispositions with `POSIX_SPAWN_SETSIGDEF` but does not set
`POSIX_SPAWN_SETSIGMASK`. This is consistent with inheritance of the dispatch
worker's blocked signals. The introducing commit was not bisected, and this is
not attributed to the #783 patch. Leftover test fixture processes were removed.

The disconnect anomaly also predates the tested fix: a peer that closes without
a response yields finish/no error/status 0 and two bytes on both libraries.
The strict probe marks these cases as failures. Arlen's loader rejects this case.

## Reproduction and evidence

The [probe](reproducers/gnustep-783/probe.m), orchestration scripts, and
[compact results](reproducers/gnustep-783/results.json) are snapshots of this
manual upstream experiment, not new supported build targets or CI gates.
The scripts intentionally use the `/tmp` paths below. Run from the Arlen root
with normal loopback/network access:

```sh
source tools/source_gnustep_env.sh
git clone https://github.com/gnustep/libs-base.git /tmp/arlen-783-base
git -C /tmp/arlen-783-base checkout f014cd06227f790cb8e9ff19da6db5538672527a
(
  cd /tmp/arlen-783-base
  ./configure CC=clang CXX=clang++
  make -j8
)
mkdir -p /tmp/arlen-783-evidence
cp docs/internal/reproducers/gnustep-783/* /tmp/arlen-783-evidence/
clang $(gnustep-config --objc-flags) -Wno-nullability-completeness -fobjc-arc \
  /tmp/arlen-783-evidence/probe.m -o /tmp/arlen-783-evidence/probe \
  $(gnustep-config --base-libs)
python3 /tmp/arlen-783-evidence/matrix.py
python3 /tmp/arlen-783-evidence/live.py
python3 /tmp/arlen-783-evidence/extra.py
clang $(gnustep-config --objc-flags) -Wno-nullability-completeness -fobjc-arc \
  /tmp/arlen-783-evidence/task-probe.m -o /tmp/arlen-783-evidence/task-probe \
  $(gnustep-config --base-libs)
timeout 5s /tmp/arlen-783-evidence/task-probe
LD_LIBRARY_PATH=/tmp/arlen-783-base/Source/obj:$LD_LIBRARY_PATH \
  timeout 5s /tmp/arlen-783-evidence/task-probe
```

`matrix.py` exits nonzero because it preserves the unexpected disconnect
failures. Inspect per-case expectations: a baseline custom-mode timeout and a
patched no-start timeout are expected controls. `extra.py` records failures in
JSON without aggregating them into its exit status.

Arlen regression commands (the first intentionally demonstrates the hang):

```sh
source tools/source_gnustep_env.sh
timeout 20s make test-unit-filter \
  TEST=MetadataTransportTests/testRealSocketOnFreshMaintenanceThread \
  ARLEN_XCTEST_LD_LIBRARY_PATH=/tmp/arlen-783-base/Source/obj:$PWD/vendor/tools-xctest/XCTest/obj
timeout 30s make test-unit-filter TEST=MetadataTransportTests \
  SKIP_TEST=MetadataTransportTests/testRealSocketOnFreshMaintenanceThread \
  ARLEN_XCTEST_LD_LIBRARY_PATH=/tmp/arlen-783-base/Source/obj:$PWD/vendor/tools-xctest/XCTest/obj \
  ARLEN_TEST_ENTRA_TENANT=e163dc2e-cff9-4598-909e-556fa5b36e3a
timeout 30s make test-unit-filter TEST=MetadataTransportTests \
  ARLEN_TEST_ENTRA_TENANT=e163dc2e-cff9-4598-909e-556fa5b36e3a
```

The timed-out worker fixture may require manual SIGKILL cleanup of its specific
Python child because SIGTERM is blocked. The second command reports three
methods passed; the third reports all four passed on the installed baseline.
The live production test confirms signing-key readiness on main and worker
threads, through the existing libcurl loader. It is regression evidence, not
evidence for Foundation scheduling.

Full local logs, loader paths, the exact issue reproducer, and the hang backtrace
are in `/tmp/arlen-783-evidence/`; configuration/build logs are
`/tmp/arlen-783-configure.log` and `/tmp/arlen-783-build.log`. An initial test
invocation used the wrong XCTest library directory and failed before testing;
the corrected runs use `vendor/tools-xctest/XCTest/obj` as shown above.

Recommendation: confirm #783's scoped scheduling fix upstream with the explicit
start caveat. Retain Arlen's libcurl workaround and investigate the separate
NSTask signal-mask problem before adopting this master toolchain.

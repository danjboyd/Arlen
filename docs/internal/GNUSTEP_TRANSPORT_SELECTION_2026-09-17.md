# GNUstep transport selection and NSTask follow-up

## Runtime detection: feasible, but not sufficient for automatic selection

An Arlen process can inspect the library it actually loaded, rather than the
headers it was built against. On the two libraries verified here:

| Runtime observation | Installed Base 1.31.1 | Master with #783 |
| --- | --- | --- |
| `NSClassFromString(@"GSRunLoopScheduler") != Nil` | NO | YES |
| `NSURLConnection` instances respond to `_scheduled` | NO | YES |

The [capability probe](reproducers/gnustep-783/capability.m) demonstrates this.
These are private implementation details, not an upstream capability contract.
They are useful hints for an unreleased build, not proof that socket scheduling,
TLS, or timeout behavior is correct. A local real-socket behavior probe would
provide stronger scheduling evidence. Public provider availability should not
determine startup capability detection.

Recommended eventual selection policy:

1. Assess capabilities once for the loaded runtime, independently of user
   requests; cache the result for that process.
2. Select Foundation only when the complete bounded metadata transport contract
   is supported and verified. Unknown or unsupported runtimes select libcurl.
3. Make both paths exercise the same real socket/TLS regression suite, with an
   override available to tests so automatic selection cannot hide a broken path.
4. Select before starting a request. Do not retry a certificate failure, rejected
   redirect, oversize response, or expired deadline using the other transport.
5. When upstream offers a public capability indicator or a versioned release,
   replace private implementation hints with that supported contract. Retain
   behavior tests for backports and custom builds.

No production selector was added: master still fails an existing requirement
that the #783 scheduling fix does not address.

## Remaining Foundation deadline blocker

`GSHTTPURLProtocol startLoading` resolves its host using `NSHost hostWithName:`
before returning from `[connection start]`. That synchronous work precedes
Arlen's deadline-pumping loop. Moving the request to a worker can bound the
caller's wait, but does not by itself cancel blocked DNS or bound accumulating
workers. It is not a complete replacement for the current transport's
asynchronous-DNS requirement.

A controlled resolver interposer delayed resolution for
`arlen-deadline.invalid` by one second. The existing standalone probe, with a
100 ms monotonic budget and patched custom-mode scheduling, returned:

```text
elapsed=1.001212225004565 status=0 finished=false pass=false
```

This confirms that detecting #783 and enabling the existing Foundation delegate
path would weaken Arlen's total-deadline guarantee. GNUstep supports per-request
TLS properties, so TLS settings also deserve direct validation rather than
assuming either process defaults or scheduling detection are sufficient.

The [interposer source](reproducers/gnustep-783/slow-dns.c) and
[recorded results](reproducers/gnustep-783/followup-results.json) preserve the
experiment. The final probe intercepts both `getaddrinfo` and the
`gethostbyname_r` API actually used by this build. An initial getaddrinfo-only
probe did not inject the intended delay and is not used as evidence.

```sh
source tools/source_gnustep_env.sh
clang -shared -fPIC docs/internal/reproducers/gnustep-783/slow-dns.c \
  -ldl -o /tmp/arlen-783-evidence/slow-dns.so
LD_LIBRARY_PATH=/tmp/arlen-783-base/Source/obj:$LD_LIBRARY_PATH \
LD_PRELOAD=/tmp/arlen-783-evidence/slow-dns.so \
  timeout 8s /tmp/arlen-783-evidence/probe \
  http://arlen-deadline.invalid/ custom 1 0 timeout 0.1
```

The expected nonzero exit records a deadline failure. The probe binary is built
as described in the [initial verification](GNUSTEP_783_VERIFICATION_2026-09-17.md).
This interposer is only for the isolated verification command, never a runtime
workaround or deployment setting.

## NSTask adoption blocker: fixed and verified locally

The [upstream-ready patch](reproducers/gnustep-783/nstask-signal-mask.patch) clears
the child signal mask in both process-creation paths:

- `posix_spawn`: `POSIX_SPAWN_SETSIGMASK` plus an empty mask.
- `fork` fallback: `sigprocmask(SIG_SETMASK, ...)` in the child after restoring
  default signal dispositions.

The launching thread's mask remains unchanged. Fixing only `posix_spawn` did not
resolve the regression in this environment; the fallback needed the same
correction. No swizzling, global signal-mask change, or Arlen test weakening was
used.

The patch includes a deterministic GNUstep-native regression. It explicitly
blocks SIGTERM and SIGUSR1, launches a helper invocation that inspects its own
post-exec mask, and verifies that the parent still has those signals blocked.
It does not depend on libdispatch's choice of worker mask or reading `/proc`
before a child's exec completes. That matters because the older standalone
`task-probe.m` can sample a transient pre-exec mask; its termination outcome,
rather than that early sample, is the useful check.

Validation against master `f014cd06227f790cb8e9ff19da6db5538672527a`:

| Check | Before fix | After fix |
| --- | --- | --- |
| New signal-mask regression | 2 assertions pass, child assertion fails | All 3 pass |
| GNUstep NSTask test group | Not rerun as a whole before fix | All 92 assertions pass |
| Standalone main/worker terminate probe | Worker child ignores SIGTERM | Both terminate within the 500 ms bound |
| Arlen metadata class, including live tenant | Worker fixture teardown hangs | All 4 methods pass |
| Live production discovery/JWKS readiness | Passed separately | Passes on main and worker in complete class |

The isolated GNUstep checkout contains commit
`f34942c` (`NSTask: clear inherited signal masks in child processes`).
The patch is saved in Arlen so it survives deletion of that temporary checkout.
It has **not** been submitted upstream, installed into `/usr/GNUstep`, or wired
into provisioning. The previous conclusion that #783 itself is fixed stands;
the local subprocess adoption blocker is now resolved by this additional patch.

To apply to a fresh checkout of the tested upstream revision:

```sh
git -C /path/to/libs-base am \
  /path/to/Arlen/docs/internal/reproducers/gnustep-783/nstask-signal-mask.patch
source /path/to/Arlen/tools/source_gnustep_env.sh
make -C /path/to/libs-base -j8
make -C /path/to/libs-base/Tests check testobj=NSTask
```

Arlen verification against the fixed build:

```sh
source tools/source_gnustep_env.sh
timeout 30s make test-unit-filter TEST=MetadataTransportTests \
  ARLEN_XCTEST_LD_LIBRARY_PATH=/tmp/arlen-783-base/Source/obj:$PWD/vendor/tools-xctest/XCTest/obj \
  ARLEN_TEST_ENTRA_TENANT=e163dc2e-cff9-4598-909e-556fa5b36e3a
```

Full local logs are in `/tmp/arlen-783-evidence/`, including
`signal-mask-before.log`, `signal-mask-after.log`, `nstask-suite-fixed.log`, and
`arlen-all-fixed.log`. Existing application behavior, CI lanes, and the libcurl
fallback remain unchanged. A Foundation selector should wait until the DNS
deadline problem and full transport parity are addressed.

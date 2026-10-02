# StateCompulsoryPoolingAPI Report Reconciliation — "long-lived hang under default dispatch mode"

Date: `2026-06-03`

This note records the upstream Arlen assessment of the `StateCompulsoryPoolingAPI`
bug report titled *"Arlen bug report — long-lived hang under default dispatch
mode"* (filed 2026-06-03).

Ownership rule:

- Arlen records upstream status only.
- `StateCompulsoryPoolingAPI` keeps app-level closure authority.
- Status below should be read as the upstream status/evidence trail.
  Downstream revalidation still belongs to `StateCompulsoryPoolingAPI`.

Tracking: `ISSUE-013` / `ARLEN-BUG-033` (`docs/internal/OPEN_ISSUES.md`).

## Verdict

- The **hang is genuine and reproducible** — we agree there is a real defect.
- The report's **root-cause attribution is not supported by the code.** This is
  *not* a concurrent-dispatch race, *not* the connection-pool semaphore, and
  *not* a second failure mode of the resolved `malloc_consolidate` crash
  (`ISSUE-001`, fixed in `0920889`). The reporter's own reproduction is purely
  **sequential** (one `curl` at a time), so no concurrent-dispatch path is
  exercised by it.
- The evidence points to a **blocked-stdio backpressure stall**: Arlen logs
  synchronously with `fprintf(stderr, …)` on the request-handling thread, and
  when the consumer of the server's `stderr` stops draining (an undrained pipe
  in the `make test` harness), the per-request log write blocks in the kernel
  and the in-flight request never completes.

## What the reporter's evidence actually shows

| Reported observation | Upstream reading |
| --- | --- |
| `worker thread: futex_wait_queue × 7` | **Normal idle state**, not a deadlock. `maxConcurrentHTTPWorkers` defaults to `8` (`ALNHTTPServer.m:3006`). Idle workers block in `dequeueHTTPClientForWorker` on a timed `NSCondition` wait (`ALNHTTPServer.m:3149-3150`, 0.25 s `waitUntilDate:`), which the kernel reports as `futex_wait_queue`. Seven idle + one busy = eight. |
| `main thread: inet_csk_accept` | Idle at the listen socket — expected, nothing to accept. |
| `log thread: pipe_write (queued output)` | **The actual fault.** A thread is blocked in `write()` to a pipe whose read end is not being drained. This is the busy worker (or the thread that owns `stderr`), stuck emitting log output. |
| in-flight `curl` in `do_sys_poll` | Correct — its worker is blocked in `pipe_write`, so the response is never written. |
| `pg_stat_activity` all idle, no lock | Consistent. Nobody is stuck in the database; the read-only `SELECT`s already returned. The stall is *after* the query, while logging the request. |

The reporter inferred "all worker threads parked on a mutex/condvar" from the
`futex_wait_queue` signature. That inference is the error: the timed
work-queue wait and a real lock contention are indistinguishable from `wchan`
alone, and the one stack that matters — the busy worker blocked in
`pipe_write` — was the single thread they did *not* frame-walk.

## Mechanism

1. `ALNLogger` writes **synchronously and unbuffered** to `stderr` via
   `fprintf(stderr, "%s\n", …)` on the calling thread, with no async queue and
   no drop-on-full path (`src/Arlen/Support/ALNLogger.m:103,119`).
2. Every served request emits at least one Info-level `"request"` /
   `"request complete"` line (`ALNApplication.m:5043,5168,5333,5708`). The
   `test` environment runs at Info level (`ALNApplication.m:1170-1172`), so
   these lines are emitted.
3. The `make test` harness spawns the API as a child
   (`./build/state-compulsory-pooling-api --env test --port <random>`) and, by
   the report's own description, reads the startup banner and then runs ~106
   sequential requests. If the child's `stdout`/`stderr` is connected to a pipe
   the harness stops draining, the per-request log lines accumulate in the
   kernel pipe buffer.
4. A Linux pipe buffer is 64 KiB. Once cumulative log output crosses that
   threshold, the next `fprintf(stderr, …)` blocks in `write()` →
   `pipe_write`. The worker handling the current request never returns to write
   the HTTP response, so `curl` hangs forever.

This explains **every** otherwise-puzzling property of the report:

- **Non-deterministic hang point ("between request ~5 and the end").** The
  trigger is cumulative *log bytes* crossing 64 KiB, which depends on
  per-request field values and response shapes, not on any endpoint.
- **Endpoints fine in isolation.** Run standalone with `stderr` to a terminal
  or file, the pipe is drained (or is not a pipe at all), so it never fills.
- **Different endpoints across runs.** Whichever request happens to push the
  buffer past 64 KiB is the victim; the endpoint is incidental.

## On the production workaround

Production sets `ARLEN_REQUEST_DISPATCH_MODE=serialized` *and* runs under
systemd/journald. We assess the **journald drain**, not the dispatch mode, as
the reason production is stable: journald continuously reads the service's
`stdout`/`stderr`, so the pipe never fills. Serialized mode disables the worker
pool and handles requests on the main thread (`ALNHTTPServer.m:3976,4017`), but
it still logs synchronously to `stderr` — so on an undrained consumer it would
stall identically. The dispatch-mode attribution in the report is therefore a
coincidence of the systemd unit setting both things at once.

## Upstream status

- Status: `accepted as a genuine Arlen reliability gap; root cause identified
  (synchronous blocking stderr logging stalls the request path under an
  undrained output consumer); fix not yet shipped`.
- This root cause is **code-and-evidence supported but not yet empirically
  reproduced upstream.** We do not have the `StateCompulsoryPoolingAPI` test
  harness in-tree to run `make test` directly. The decisive confirmation is
  cheap and is owned downstream (see below).

## Decisive confirmation test (downstream)

Re-run the failing suite with the server's output drained, changing nothing
else:

- Redirect the spawned server's `stdout`/`stderr` to a file or `/dev/null`, **or**
- Have the harness keep reading the child's output for the whole run, **or**
- Capture the busy (8th) worker's stack with `gdb -p <api-pid>` /
  `eu-stack -p <api-pid>` at hang time and confirm it is in `write` →
  `pipe_write` inside `fprintf`/`ALNLogger`.

If draining the output makes the hang disappear, the mechanism above is
confirmed and the concurrent-dispatch / TSAN investigation in the report can be
dropped for this failure mode.

## Recommended fixes

Framework hardening (Arlen-side, the durable fix):

1. A well-behaved server must not let a stalled `stderr` consumer block the
   request path. Make `ALNLogger` resilient to a slow/blocked sink — e.g. mark
   `STDERR` non-blocking and drop (with a dropped-line counter) on `EAGAIN`,
   or move emission to a bounded background queue that drops rather than blocks
   when full. Track under `ARLEN-BUG-033`.
2. Ignore `SIGPIPE` process-wide so a fully closed log reader downgrades to an
   `EPIPE`/`EAGAIN` the logger can handle instead of a signal.

Harness fix (StateCompulsoryPoolingAPI-side, the immediate unblock):

3. Drain the spawned test server's `stdout`/`stderr` for the full run, or
   redirect it to a file. This un-gates `make test` in CI immediately and does
   not depend on the framework change.

## Resolution shipped upstream (2026-06-03)

`ALNLogger` was hardened so a stalled or full output sink can no longer block
the request path (`ARLEN-BUG-033`):

- Emission moved off `fprintf(stderr, …)` onto a bounded, poll-gated writer
  (`src/Arlen/Support/ALNLogger.m`). A line is written only while the sink can
  accept bytes within `writeTimeoutMilliseconds` (default 100 ms); otherwise it
  is dropped and `droppedMessageCount` is incremented. The worker can never park
  indefinitely in `write()`/`pipe_write`.
- The writer chunks each line at `_POSIX_PIPE_BUF` after a successful
  `poll(POLLOUT)`, so it stays non-blocking without mutating the descriptor's
  flags (other writers to fd 2 are unaffected in the healthy case).
- `SIGPIPE` is ignored process-wide (only if still `SIG_DFL`, so an
  app/server-installed handler is preserved) so a fully-closed reader degrades
  to a dropped line instead of killing the process.
- Per-line atomicity under concurrent workers is preserved by serializing
  emission through a write lock. Windows retains the prior synchronous path.

Regression coverage (`tests/unit/LoggerTests.m`):

- `testLoggerDropsAndDoesNotBlockWhenSinkIsFull_ARLEN_BUG_033` — fills a pipe,
  points the logger at it with a 0 ms timeout, and asserts five log calls return
  promptly (well under the wall-clock bound) while incrementing the dropped
  counter, instead of hanging the way `fprintf` did.
- `testLoggerResumesWritingAfterSinkDrains_ARLEN_BUG_033` — confirms a healthy
  (drained) sink drops nothing and the delivered line reaches the reader.

This removes the framework-side trigger. The downstream harness improvement
(drain or redirect the spawned server's output) is still worth doing for fast
local runs and is owned by `StateCompulsoryPoolingAPI`; re-pinning to a ref that
includes this fix is the downstream revalidation step.

## Cross-references

- `ISSUE-001` (`docs/internal/OPEN_ISSUES.md`) — resolved `malloc_consolidate`
  crash; the report's "same root cause" framing does not hold.
- `docs/internal/CONCURRENCY_AUDIT_2026-02-25.md` — concurrency baseline.
- `src/Arlen/Support/ALNLogger.m` — synchronous `fprintf(stderr, …)` emission.
- `src/Arlen/HTTP/ALNHTTPServer.m:3147-3194` — worker dequeue/idle-wait and
  per-request lifecycle (`@finally` release; no monotonic leak found).
- `src/Arlen/Data/ALNPg.m:3234-3323` — pool `acquire`/`release`; exhaustion
  returns an error and does **not** block, ruling out a pool-semaphore hang.

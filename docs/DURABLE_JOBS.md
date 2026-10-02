# Durable Jobs

Use `ALNPostgresJobAdapter` when web processes enqueue work for separate workers.
It implements `ALNDurableJobAdapter`, with atomic claims across processes,
renewable leases, recovery after worker crashes, and persistent status/results.
The memory adapter remains the default for development and tests. The file
adapter persists local state but does not coordinate independent instances or
recover abandoned leases; it is not a production replacement for PostgreSQL.

## Setup and migrations

Use Arlen's supported clang-based GNUstep toolchain and its existing `ALNPg`
libpq dependency. No queue broker, language bridge, PostgreSQL extension, or new
client library is needed. Provision PostgreSQL 14 or newer. All processes must
use the same database, search path, and namespace. Namespaces isolate queue data,
not database privileges.

Run the initial migration once with a deployment credential:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tools/migrations/jobs/001_postgres_jobs.sql
```

The equivalent programmatic migration is `[jobs installSchemaWithError:&error]`.
It takes a transaction advisory lock and applies `+schemaStatements` atomically;
repeated installation is safe. Runtime construction and enqueue/claim never run
DDL. Schema v1 owns `arlen_job_schema`, `arlen_job_queues`, `arlen_jobs`, their
indexes, and the sequence for ordering. Future versions require an explicit
migration; do not edit these tables to emulate a different queue's schema.

The runtime role needs SELECT/INSERT/UPDATE/DELETE on the queue tables and USAGE
on the sequence; schema installation requires DDL privileges. Keep these tables
in a trusted schema on a consistent search path. Preserve PostgreSQL's normal
durable commit settings. Configure connection and statement/lock timeouts for
your deployment; `connect_timeout` alone does not bound an established socket.

Register the same adapter in each process **before configuring the jobs module**:

```objc
#import <Arlen/Arlen.h>

NSError *error = nil;
ALNPg *database = [[ALNPg alloc]
    initWithConnectionString:databaseURL
    maxConnections:4
    error:&error];
ALNPostgresJobAdapter *jobs = database ? [[ALNPostgresJobAdapter alloc]
    initWithDatabase:database
    namespace:@"opportunitytracker"
    leaseDurationSeconds:60
    error:&error] : nil;
if (!jobs) {
  // Abort startup and report error through your application's startup path.
  return NO;
}
[application setJobsAdapter:jobs];
```

Namespaces must be 1–200 characters. Lease duration must be finite and between
0.3 and 86400 seconds. Reserve pool capacity for heartbeats in addition to
connections held by handlers; do not use a one-connection pool if a handler holds
that connection while it works. Construct pools after forking, in each worker.
The existing `arlen jobs worker` / `jobs-worker` runner uses this adapter through
the application's registration path.

## Enqueue and transaction boundaries

`enqueueJobNamed:payload:options:error:` commits before returning an ID. Payloads
are JSON-compatible dictionaries. Options are:

| Option | Default | Meaning |
|---|---|---|
| `queue` | `default` | Shared queue name, at most 200 characters |
| `maxAttempts` | `3` | Positive integer; claims, including crashed claims, consume attempts |
| `notBefore` | Immediate | `NSDate` for absolute due time, or numeric delay in seconds |
| `idempotencyKey` | None | Namespace-wide duplicate request identity |
| `retainDeduplication` | `NO` | Retain the key after completion/failure while its row exists |

Duplicate active keys return the existing ID. By default the key becomes
available again at completion or terminal failure. `retainDeduplication = YES`
keeps that key reserved after terminal state, across process and database
restarts. Use this for requests that may be retried after a lost enqueue response.
A key identifies the original request; reusing it with different inputs returns
the original job, not an update. Unkeyed retries after an ambiguous connection
failure can enqueue duplicate work.

To commit application data and a job together, use the **same connection** in a
READ COMMITTED transaction:

```objc
__block NSString *jobID = nil;
BOOL committed = [database withTransactionUsingBlock:
    ^BOOL(id<ALNDatabaseConnection> connection, NSError **txError) {
      // Perform the application's record update using connection here.
      jobID = [jobs enqueueJobNamed:@"refresh_opportunity"
                           payload:@{@"opportunityID": opportunityID}
                           options:@{@"idempotencyKey": requestID,
                                     @"retainDeduplication": @YES}
                      onConnection:connection
                             error:txError];
      return jobID != nil;
    } error:&error];
// Expose jobID only if committed is YES.
```

The connection overload does not begin or commit the caller's transaction. A
rollback removes the enqueue too. Do not call it on an autocommit connection.
For module handlers, use
`ALNJobsModuleRuntime enqueueJobIdentifier:payload:options:onConnection:error:`
so validation, definition defaults, and managed payload wrapping still apply.
Passing a nil connection uses the regular enqueue path.

For data in another database, write an application-owned outbox record in that
data transaction. Relay committed records with a stable retained idempotency
key, then mark the outbox record delivered. A relay restart can safely repeat
that enqueue. Arlen does not atomically commit across different databases.

## Claims, heartbeats, and results

Claims lock eligible rows with `FOR UPDATE SKIP LOCKED`; jobs order by due time
then persisted sequence. Concurrent execution is not a global completion order.
Each claim increments the attempt count and receives a fresh token. PostgreSQL
clock time controls lease expiration and renewal. The timestamp passed to
`dequeueDueJobAt:error:` controls due-time selection only: advancing it 30 days
cannot expire a live worker's lease.

`ALNJobWorker` renews leases on a heartbeat thread every one-third of the lease
duration while a handler executes. It stops and joins that thread before
completion/retry. A renewal failure prevents completion; the worker returns an
error and the lease can expire for recovery. A handler cannot be forcibly
cancelled by that error, so external side effects must remain idempotent.

Direct adapter consumers must renew their own leases. Use:

- `renewJob:error:` to extend the current unexpired claim;
- `completeJob:result:error:` to atomically persist a JSON-compatible result and
  complete the job;
- `retryJob:delaySeconds:failureMessage:error:` to schedule another attempt or
  record a terminal failure at the attempt limit.

All three reject expired or superseded tokens. `ALNJobLease.leaseExpiresAt` is
the expiration at claim time; poll status for the latest renewed expiration.
ID-only `acknowledgeJobID:error:` deliberately returns error 603. Existing memory
and file adapter callers keep their old API, but a custom PostgreSQL worker must
adopt the lease contract. The baseline adapter conformance suite assumes ID-only
acknowledgement; use the durable jobs suite for this capability.

A later claim recovers expired work; expired final attempts transition to
`failed`. Each dequeue cleans up at most 100 expired final-attempt jobs, ordered
by expiry and sequence. Cleanup skips locked jobs, so a busy terminal job cannot
block unrelated claims; later polls revisit it after its lock is released.
Cleanup also runs when queues are paused. Recovery is driven by polling workers;
there is no separate reaper service. Explicit retry delays come from the
worker/runtime; the jobs module retains its constant, linear, and exponential
backoff policies. Recovered crashed attempts become eligible immediately.

`jobStatusForID:error:` returns `pending`, `leased`, `completed`, or `failed`,
plus ID, payload, attempt count, due time, lease expiration, result, failure
message, and replay origin. Missing IDs return nil without an error; database
failures return nil with an error. Results and terminal rows are retained until
explicit maintenance; they are not deleted at acknowledgement.

Plain worker runtimes may implement `jobWorker:resultForJob:`. Jobs module
definitions may implement the optional
`jobsModulePerformPayload:context:result:error:` method; the runtime uses it in
place of the legacy perform method and persists its result on success. Failed
handlers keep their error description through retry/terminal failure.

Queue fencing protects queue state. It does not provide exactly-once delivery to
an external provider. Use application/provider idempotency keys and, when
needed, transactional application-side ownership checks for side effects.

## Shared operator controls and polling

`setQueue:state:error:` updates shared state:

| State | New enqueue | New claims | Already running work |
|---|---|---|---|
| `active` | Accepted | Allowed | Continues |
| `paused` | Accepted by adapter; module enqueue rejects | Stopped | Continues |
| `draining` | Rejected | Allowed until empty | Continues |

A duplicate existing idempotency key can still resolve its ID during drain.
Queue locks serialize control changes with claim/enqueue transactions. Claims
skip busy queue-control rows and consider only queues locked by that claim
transaction, allowing other queues to keep processing. Skipped queues become
eligible on a later poll after their control lock is released. A claim
that committed before pause may still begin execution after the pause request.
Draining stays enabled until an explicit resume; inspect shared counts for zero
pending and leased jobs. Queue controls apply across independent processes.

`replayJobID:idempotencyKey:delaySeconds:error:` creates a new job with a fresh
attempt budget and a `replayOf` link, preserving the original terminal row.
Only completed/failed jobs can be replayed. The explicit replay request key is
retained after completion, so repeating the same replay request returns the same
new ID. Use a new key for another intentional replay. A key already used for a
different replay source is rejected.

The protected jobs module API adds:

- `GET /jobs/api/jobs/:jobID`: durable status and result; 404 when missing,
  503 on database failure, 501 with a non-durable adapter;
- `POST /jobs/api/queues/:queue/drain`: shared drain control;
- existing pause/resume routes now update shared state;
- existing dead-letter replay accepts a required `idempotencyKey` when using the
  durable adapter;
- enqueue accepts `retainDeduplication` alongside `idempotencyKey`;
- queue and job-list JSON routes report database failures instead of presenting
  an empty successful response.

These routes retain admin and AAL2 protection. For end-user polling, expose an
application route that checks ownership before returning the adapter's status;
do not expose the operator API publicly.

The module's legacy plist run history is diagnostic state, not the authoritative
job/result store. For separate workers, configure
`jobsModule.persistence.enabled = NO` or use a separate diagnostic path per
process. Run a single scheduler process with `--run-scheduler`: schedule trigger
bookkeeping is still process-local/plist-backed, not a distributed scheduler.
Multiple worker processes without that flag can safely consume the shared queue.

## Maintenance and verification

Choose a retention policy before deleting terminal rows. Deleting a retained-key
row also releases its deduplication key. Never delete pending/leased rows as a
retention sweep. `resetWithError:` is a destructive, namespace-scoped test or
maintenance operation and must run with producers/consumers quiesced. The
legacy void `reset` cannot report errors.

Use `jobsWithState:error:` and `queueStatesWithError:` for error-aware inspection.
The legacy array-only snapshot methods preserve their baseline interface and
cannot distinguish an outage from an empty queue.

```bash
source tools/source_gnustep_env.sh
make ci-durable-jobs
```

The gate builds a repo-local XCTest bundle and independent process probe, creates
an isolated Unix-socket PostgreSQL cluster, and removes it afterward. It needs
PostgreSQL server binaries (`ARLEN_TEST_PG_BIN` can override their location), not
application database credentials. It verifies concurrent producers/consumers,
kill/restart, expiry/renewal, stale completion/retry rejection, transaction
rollback, retry exhaustion, duplicate requests, durable results, module
integration, database outages/restart, and private file initialization. Output
is saved to `build/release_confidence/durable_jobs.log`.

The filesystem initialization regression uses POSIX directory creation on
Linux/macOS with `0700` from creation and descriptor-based permission setting;
queue files remain `0600`. It avoids the observed GNUstep combined
create-directory/attributes failure without relaxing permissions. The Windows
Foundation path remains unchanged. Fixing initialization does not change the
file adapter's concurrency or recovery limits.

Server-tool discovery honors `ARLEN_TEST_PG_BIN` first (an invalid explicit path
fails), then a complete `pg_config --bindir`, an `initdb` directory on PATH, and
finally the newest complete Debian/Ubuntu server directory under
`/usr/lib/postgresql`. This allows client development tools and server packages
to have different versions. The Linux quality workflow installs the `postgresql`
server package when tools are missing; clang-based GNUstep provisioning is
unchanged. ORM identifier acceptance uses the same resolver.

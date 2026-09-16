# OpportunityTracker durable jobs upstream implementation — 2026-09-16

Status: implemented upstream; awaiting downstream adoption and revalidation.

Request: `../OpportunityTracker/arlen-sprint6/upstream/durable-jobs.md`, based on
Arlen `0bc963c0f6e711ae0acbaeb3d388840a9c0f62be`.

## Delivered contract

- `ALNPostgresJobAdapter` with explicit schema v1 installation and SQL migration.
- Transactional enqueue, shared queue locks, atomic claims across independent
  processes, finite renewable leases, crashed-worker recovery, and fenced
  completion/retry/renewal.
- Stable IDs, retained results/failure state, bounded attempts, existing module
  backoff integration, explicit replay request identity and provenance.
- Active-key and retained-key deduplication, shared pause/drain/resume controls,
  module result providers and protected status/drain endpoints.
- Worker heartbeat integration, preserving memory/file adapter behavior.
- Dedicated live PostgreSQL XCTest/process acceptance gate in the existing
  linux-quality workflow; no additional branch-protection check name.

Integration instructions and operational boundaries are in
[Durable Jobs](../DURABLE_JOBS.md). Tests use synthetic work and a disposable
local PostgreSQL cluster; no application database, Minion table, external
provider, or downstream export is modified.

## Filesystem issue

The supplied Foundation-only probe was reproduced upstream on the host:
combined directory creation with `NSFilePosixPermissions` returned POSIX EFAULT
(`Bad address`), while separate permission setting succeeded. This supports the
reported failure being below the queue implementation, but does not identify
the precise GNUstep root cause.

Arlen's POSIX path now creates missing directories with mode `0700` and applies
permissions through an opened directory descriptor. It rejects symlink leaf
directories; queue files remain `0600`. Private initialization/reopen and symlink
rejection have regression coverage. No GNUstep installation was modified.
Windows retains its existing Foundation implementation.

The file adapter remains a single-instance persisted queue without cross-process
coordination or expired-lease recovery. OT should qualify the PostgreSQL adapter
for production instead of running its legacy file probe as the production gate.
PostgreSQL lease expiry follows database clock time, so moving the API's due-time
argument 30 days forward does not expire a live lease.

## Upstream verification and downstream ownership

`make ci-durable-jobs` exercises four producers and four consumers with accepted-ID
reconciliation, independent duplicate enqueues, worker SIGKILL/restart,
lease expiry/renewal and stale mutation rejection, retry exhaustion,
transaction commit/rollback, persistent results, module integration, actual
PostgreSQL shutdown/restart, schema artifact alignment, replay-key collisions,
invalid input rejection, lock-wait expiration, protected operator route metadata,
and private filesystem initialization.

Existing `Phase3ETests`, `Phase7DTests`, `Phase14ATests`, and `Phase16ATests`
cover baseline worker, file services, and jobs module compatibility. The gate
records its live log under `build/release_confidence/durable_jobs.log`.

OT still owns porting its 16 handlers, provider idempotency, application-owned
polling authorization, migration/draining of existing Minion work, dependency
adoption, and end-to-end Sprint 6 qualification. Upstream completion does not
close OT's 6H/6I blocker on its behalf. Run a single scheduler; this change does
not implement distributed schedule-trigger coordination.

Verification on the implementation host: the durable jobs gate, 26 existing
regressions across the four classes above, generated API/HTML documentation, and
`make ci-docs`. GitHub execution and OT adoption remain separate downstream/CI
steps; this record does not claim they have run.

## Review correction: claim progress under lock contention

OT reviewed `08029e6` in
`../OpportunityTracker/arlen-sprint6/upstream/durable-jobs-review-08029e6.md`
and supplied `durable-jobs-review-lock-test.m`. The namespace-wide terminal-expiry
UPDATE could wait on one locked expired job before reaching the claim query's
`SKIP LOCKED`. This availability defect was reproduced upstream with a 250ms
lock timeout, including when the available job was in another queue.

The follow-up limits cleanup to 100 candidates per dequeue, selected in expiry
and sequence order with `FOR UPDATE SKIP LOCKED`, and updates only those rows.
The claim-path audit also reproduced blocking on an unrelated queue-control row;
queue selection now uses `FOR SHARE SKIP LOCKED` and continues restricting claims
to the exact queue names it locked. Pause/drain ordering and database-time lease
checks remain intact. Busy jobs/queues are revisited on later polls.

Five added regressions cover same-queue and cross-queue progress while the lock
is held, eventual terminal failure after release, cleanup of a 205-job backlog
in bounded batches, preservation of live/retryable leases, and independent
progress while queue controls are locked. Before the correction, four of the
five new tests failed and the original 20 passed. With the correction, all 25
pass on the implementation host. The correction needs no schema migration or
public API change; the existing linux-quality durable-jobs step runs these tests
before the broader gate, so unrelated later failures cannot skip queue evidence.

Status: fixed in the corrective implementation; awaiting GitHub checks and OT
adoption/revalidation. Do not close OT's qualification or ARM64 gate on the
strength of this host's tests.

The baseline GitHub linux-quality run for `08029e6` (run `35135024797`) failed
in deployment integration coverage before reaching durable jobs: the feature-flag
smoke binary was missing, sanitizer suppression validation failed, and the
release-certification risk register was stale. These failures are separate from
the reproduced queue defect. Required checks must pass before merging the
corrective PR; the queue's local pass does not authorize a check bypass.

# Jobs Module

The first-party `jobs` module productizes queue and scheduler workflows on top of the `ALNJobAdapter` and `ALNJobWorker` contracts, with durable operator metadata, multi-queue controls, and deterministic retry/idempotency semantics.

For independent production web/worker processes, configure
[`ALNPostgresJobAdapter`](DURABLE_JOBS.md) before module registration. It adds
transactional enqueue, renewable fenced leases, crash recovery, shared queue
controls, and retained status/results. The module alone does not turn the
default memory adapter into a durable queue.

## Install

```bash
./build/arlen module add jobs
./build/arlen module doctor --json
./build/arlen module migrate --env development
```

The module is vendored into `modules/jobs/`.

## App Registration

Apps register jobs explicitly through Objective-C provider classes.

- `ALNJobsJobDefinition`: one job contract
- `ALNJobsJobProvider`: supplies job definitions to the runtime
- `ALNJobsScheduleProvider`: supplies cron-like or interval-like schedule definitions

Configure provider classes in app config:

```plist
jobsModule = {
  paths = {
    prefix = "/jobs";
    apiPrefix = "api";
  };
  persistence = {
    enabled = YES;
    path = "var/module_state/jobs-development.plist";
  };
  providers = {
    classes = ( "MyAppJobsProvider" );
  };
  schedules = {
    classes = ( "MyAppScheduleProvider" );
  };
};
```

Relative `persistence.path` values, and the default
`var/module_state/<module>-<environment>.plist`, resolve against the
application root (`-[ALNApplication appRootPath]`: config `appRoot`, then
`ARLEN_APP_ROOT`) rather than the process working directory. The HTTP server,
`arlen jobs worker` and other CLI delegates therefore share one state file.
Production deployments should still use absolute paths under the release's
`shared/` directory.

Path overrides live under `jobsModule.paths.*`. Keep `apiPrefix` relative, such as
`"api"`, when you want the module API under `/jobs/api`. Setting `apiPrefix` to an
absolute path such as `"/api"` bypasses the jobs prefix and can collide with other
module APIs.

Runtime access is available through `ALNJobsModuleRuntime`.

## Worker Runner

Arlen now ships a first-party jobs worker entrypoint for vendored apps:

```bash
./build/arlen jobs worker --env development --once --limit 25
# or the framework script directly
ARLEN_APP_ROOT=/path/to/app ARLEN_FRAMEWORK_ROOT=/path/to/Arlen /path/to/Arlen/bin/jobs-worker --env production
```

Use `--run-scheduler` when you want the same process to advance schedule definitions as well as dequeue jobs. In production, `propane` async worker supervision can point `jobWorkerCommand` or `ARLEN_PROPANE_JOB_WORKER_COMMAND` at `framework/bin/jobs-worker`.

## Definition Metadata

Job definitions may publish operator-facing metadata such as:

- `queue`
- `queuePriority`
- `maxAttempts`
- `retryBackoff`
- `tags`
- `uniqueness`

The runtime surfaces this metadata through the definitions JSON payloads, pending/leased/dead-letter job snapshots, and the module-owned dashboard summary.

## Surfaces

HTML:

- `GET /jobs/`
- `POST /jobs/run-scheduler`
- `POST /jobs/run-worker`

JSON:

- `GET /jobs/api/definitions`
- `GET /jobs/api/schedules`
- `GET /jobs/api/queues`
- `GET /jobs/api/jobs/pending`
- `GET /jobs/api/jobs/leased`
- `GET /jobs/api/jobs/dead-letter`
- `POST /jobs/api/enqueue`
- `POST /jobs/api/run-scheduler`
- `POST /jobs/api/run-worker`
- `POST /jobs/api/jobs/dead-letter/:jobID/replay`
- `POST /jobs/api/queues/:queue/pause`
- `POST /jobs/api/queues/:queue/resume`
- `POST /jobs/api/queues/:queue/drain` (durable adapter)
- `GET /jobs/api/jobs/:jobID` (durable status/results)

The JSON routes are included in module OpenAPI output.

The queue and dashboard surfaces now expose:

- all known queues, not only `default`
- queue depth and queue state (`active`, `paused`, `draining`)
- recent scheduler/worker run history when module persistence is enabled
- job metadata such as queue priority, tags, retry backoff, and uniqueness

## Protection

The operator surfaces are protected by the shared auth/admin contracts:

- authenticated session required
- `admin` role required
- AAL2 step-up required

That keeps the jobs dashboard aligned with the first-party auth and admin model without requiring the `admin-ui` module to render it.

## Defaults

Manifest defaults:

- prefix: `/jobs`
- API prefix: `/jobs/api`
- worker max jobs per run: `50`
- worker retry delay: `5` seconds
- persistence: enabled outside `test`, with an auto-resolved module state path when no explicit path is provided

## Durable adapter integration

The optional definition method
`jobsModulePerformPayload:context:result:error:` supplies a JSON-compatible result
for atomic fenced completion. The runtime's
`enqueueJobIdentifier:payload:options:onConnection:error:` validates and wraps a
job inside an application-owned PostgreSQL transaction.

With the durable adapter, replay requests must include an explicit
`idempotencyKey`; use the adapter's
`replayJobID:idempotencyKey:delaySeconds:error:` for programmatic replay. The
legacy runtime replay method has no request-key argument and rejects durable
replay. Enqueue accepts `retainDeduplication` to retain request identity after
terminal state. Existing memory/file adapter behavior is preserved.

Pause/resume and queue JSON state use the shared database. Drain rejects new
work while allowing pending work to finish. The JSON status/list/queue APIs
report database failures; the older array-only runtime snapshots cannot report
errors. The new status and drain routes retain admin/AAL2 protection.

## Current Limits

- Job execution ordering remains adapter-backed; the module does not impose a supervisor or balancing layer above the configured `ALNJobAdapter`.
- Tags, queue priority, and retry metadata are operator-facing contracts; adapters are not required to implement native queue-priority semantics.
- The dashboard is module-owned HTML, not yet embedded into `admin-ui` navigation.

- Multiple consumers are supported by the PostgreSQL adapter; run only one
  scheduler because trigger bookkeeping remains local/plist-backed.
- Plist operator run history is diagnostic, not a shared job/result store. Use
  `jobsModule.persistence.enabled = NO` or a distinct diagnostic path per process
  for separate workers. PostgreSQL retains authoritative job status and results.
- The file adapter cannot coordinate independent processes or recover crashed
  leases. Its private-directory initialization fix does not change those limits.

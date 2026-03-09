# Jobs Module

The first-party `jobs` module productizes queue and scheduler workflows on top of the Phase 3 `ALNJobAdapter` and `ALNJobWorker` contracts.

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
  providers = {
    classes = ( "MyAppJobsProvider" );
  };
  schedules = {
    classes = ( "MyAppScheduleProvider" );
  };
};
```

Runtime access is available through `ALNJobsModuleRuntime`.

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

The JSON routes are included in module OpenAPI output.

## Protection

The operator surfaces are protected by the shared auth/admin contracts:

- authenticated session required
- `admin` role required
- AAL2 step-up required

That keeps the jobs dashboard aligned with the Phase 13 auth and admin model without requiring the `admin-ui` module to render it.

## Defaults

Manifest defaults:

- prefix: `/jobs`
- API prefix: `/jobs/api`
- worker max jobs per run: `50`
- worker retry delay: `5` seconds

## Current Limits

- Queue pause/resume currently supports the `default` queue only.
- Persistence is adapter-backed; there is no separate jobs-module metadata schema in the 14A/14B slice.
- The dashboard is module-owned HTML, not yet embedded into `admin-ui` navigation.

# Getting Started

This guide gets you from zero to a running Arlen app.

## 1. Prerequisites

- GNUstep development toolchain
- `tools-xctest` package (`xctest` command)

Initialize GNUstep tooling in your shell:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
```

Run bootstrap diagnostics before building:

```bash
/path/to/Arlen/bin/arlen doctor
```

Use JSON output for tooling/CI integrations:

```bash
/path/to/Arlen/bin/arlen doctor --json
```

Reference known-good baselines:

- `docs/TOOLCHAIN_MATRIX.md`

## 2. Build Arlen

From repository root:

```bash
make all
```

This builds:

- EOC transpiler (`build/eocc`)
- CLI (`build/arlen`)
- dev server (`build/boomhauer`)
- framework artifacts and generated templates

## 3. Run Built-In Dev Server

```bash
./bin/boomhauer
```

Check endpoints:

```bash
curl -i http://127.0.0.1:3000/
curl -i http://127.0.0.1:3000/healthz
curl -i http://127.0.0.1:3000/readyz
curl -i http://127.0.0.1:3000/livez
curl -i -H 'Accept: application/json' http://127.0.0.1:3000/healthz
curl -i -H 'Accept: application/json' http://127.0.0.1:3000/readyz
curl -i -H 'traceparent: 00-0123456789abcdef0123456789abcdef-1111111111111111-01' http://127.0.0.1:3000/healthz
curl -i http://127.0.0.1:3000/metrics
curl -i http://127.0.0.1:3000/clusterz
curl -i http://127.0.0.1:3000/openapi.json
curl -i http://127.0.0.1:3000/openapi
curl -i http://127.0.0.1:3000/openapi/viewer
curl -i http://127.0.0.1:3000/openapi/swagger
curl -i http://127.0.0.1:3000/sse/ticker?count=2
curl -i http://127.0.0.1:3000/embedded/status
curl -i http://127.0.0.1:3000/embedded/api/status
curl -i http://127.0.0.1:3000/services/cache?value=ok
curl -i http://127.0.0.1:3000/services/jobs
curl -i http://127.0.0.1:3000/services/i18n?locale=es
curl -i http://127.0.0.1:3000/services/mail
curl -i http://127.0.0.1:3000/services/attachments?content=hello
```

WebSocket echo smoke test:

```bash
python3 - <<'PY'
import base64, os, socket, struct
port = 3000
key = base64.b64encode(os.urandom(16)).decode("ascii")
req = (
    f"GET /ws/echo HTTP/1.1\r\n"
    f"Host: 127.0.0.1:{port}\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n"
    f"Sec-WebSocket-Key: {key}\r\n"
    "Sec-WebSocket-Version: 13\r\n\r\n"
).encode()
s = socket.create_connection(("127.0.0.1", port), timeout=5)
s.sendall(req)
print(s.recv(4096).decode("utf-8", "replace").split("\r\n")[0])
mask = os.urandom(4)
payload = b"hello-ws"
frame = bytearray([0x81, 0x80 | len(payload)]) + mask + bytes(payload[i] ^ mask[i % 4] for i in range(len(payload)))
s.sendall(frame)
b1, b2 = s.recv(1)[0], s.recv(1)[0]
length = b2 & 0x7F
print(s.recv(length).decode())
s.close()
PY
```

Runtime websocket backpressure limit override:

```bash
ARLEN_MAX_WEBSOCKET_SESSIONS=1 ./bin/boomhauer
```

With this limit, a second concurrent websocket upgrade receives `503 Service Unavailable` with
`X-Arlen-Backpressure-Reason: websocket_session_limit`.

Security profile override:

```bash
ARLEN_SECURITY_PROFILE=strict ./bin/boomhauer
```

`strict` profile requires valid security secrets/config; startup fails fast if required values are missing.

Strict readiness startup gating override:

```bash
ARLEN_READINESS_REQUIRES_STARTUP=1 ./bin/boomhauer
```

With this setting, `GET /readyz` returns deterministic `503 not_ready` until startup completes.

## 4. Run Tests and Quality Gates

```bash
./bin/test
```

Direct make targets:

```bash
make test
make test-unit
make test-integration
make test-data-layer
make check
make ci-quality
make phase5e-confidence
```

`make check` runs unit + integration + perf gates.
`make test-data-layer` validates standalone `ArlenData` consumption outside the full runtime stack.
`make ci-quality` runs the Phase 5E quality gate (including soak/fault tests and confidence artifact generation).

Soak iteration override:

```bash
ARLEN_PHASE5E_SOAK_ITERS=240 make ci-quality
```

Phase 3C perf profiles:

```bash
ARLEN_PERF_PROFILE=middleware_heavy make perf
ARLEN_PERF_PROFILE=template_heavy make perf
ARLEN_PERF_PROFILE=api_reference make perf
ARLEN_PERF_PROFILE=migration_sample make perf
```

## 5. Run Tech Demo

```bash
./bin/tech-demo
```

Open `http://127.0.0.1:3110/tech-demo`.

## 6. Run API Reference and Migration Samples

```bash
make api-reference-server
ARLEN_APP_ROOT=examples/api_reference ./build/api-reference-server --port 3125
```

```bash
make migration-sample-server
ARLEN_APP_ROOT=examples/gsweb_migration ./build/migration-sample-server --port 3126
```

## 7. Build Browser-Friendly Documentation

```bash
make docs-html
```

Open `build/docs/index.html`.

## 8. Create Your First App (Recommended CLI Path)

Scaffold a full app:

```bash
mkdir -p ~/arlen-apps
cd ~/arlen-apps
/path/to/Arlen/bin/arlen new MyApp
cd MyApp
```

Run app dev server:

```bash
/path/to/Arlen/bin/arlen boomhauer --port 3000
```

By default, `boomhauer` watches source/template/config/public changes and rebuilds.

If watched reload fails to transpile/compile, `boomhauer` stays up and serves diagnostics:

```bash
curl -sS http://127.0.0.1:3000/
curl -sS -H 'Accept: application/json' http://127.0.0.1:3000/api/dev/build-error
```

Fixing the source and triggering a successful rebuild resumes normal responses automatically.

Lite scaffold remains available:

```bash
/path/to/Arlen/bin/arlen new MyLiteApp --lite
```

For a full walkthrough, see `docs/FIRST_APP_GUIDE.md`.

## 9. Generate Endpoints Quickly

From app root:

```bash
/path/to/Arlen/bin/arlen generate endpoint UserAdmin \
  --route /user/admin/:id \
  --method GET \
  --template
```

This scaffolds controller/action/template and auto-wires route registration.

Run full app quality gate from app root:

```bash
/path/to/Arlen/bin/arlen check
```

## 10. Scaffold Service Plugins

From app root:

```bash
/path/to/Arlen/bin/arlen generate plugin RedisCache --preset redis-cache
/path/to/Arlen/bin/arlen generate plugin QueueJobs --preset queue-jobs
/path/to/Arlen/bin/arlen generate plugin SmtpMail --preset smtp-mail
```

These presets generate compile-safe templates and auto-register classes in `config/app.plist`.

`queue-jobs` preset uses `ALNJobWorker` + `ALNJobWorkerRuntime` as an optional worker contract for periodic job draining.

## 11. Common Environment Variables

Framework/app runtime:

- `ARLEN_APP_ROOT`
- `ARLEN_FRAMEWORK_ROOT`
- `ARLEN_HOST`
- `ARLEN_PORT`
- `ARLEN_LOG_FORMAT`
- `ARLEN_SECURITY_PROFILE` (`balanced`, `strict`, or `edge`)
- `ARLEN_TRUSTED_PROXY`
- `ARLEN_SERVE_STATIC`
- `ARLEN_API_ONLY`
- `ARLEN_PERFORMANCE_LOGGING`
- `ARLEN_TRACE_PROPAGATION_ENABLED`
- `ARLEN_HEALTH_DETAILS_ENABLED`
- `ARLEN_READINESS_REQUIRES_STARTUP`
- `ARLEN_MAX_REQUEST_LINE_BYTES`
- `ARLEN_MAX_HEADER_BYTES`
- `ARLEN_MAX_BODY_BYTES`
- `ARLEN_MAX_WEBSOCKET_SESSIONS`
- `ARLEN_DATABASE_URL`
- `ARLEN_DB_ADAPTER`
- `ARLEN_DB_POOL_SIZE`
- `ARLEN_SESSION_ENABLED`
- `ARLEN_CSRF_ENABLED`
- `ARLEN_RATE_LIMIT_ENABLED`
- `ARLEN_RATE_LIMIT_REQUESTS`
- `ARLEN_RATE_LIMIT_WINDOW_SECONDS`
- `ARLEN_AUTH_ENABLED`
- `ARLEN_AUTH_BEARER_SECRET`
- `ARLEN_AUTH_ISSUER`
- `ARLEN_AUTH_AUDIENCE`
- `ARLEN_OPENAPI_ENABLED`
- `ARLEN_OPENAPI_DOCS_UI_ENABLED`
- `ARLEN_OPENAPI_DOCS_UI_STYLE` (`interactive`, `viewer`, or `swagger`)
- `ARLEN_OPENAPI_TITLE`
- `ARLEN_OPENAPI_VERSION`
- `ARLEN_CLUSTER_ENABLED`
- `ARLEN_CLUSTER_NAME`
- `ARLEN_CLUSTER_NODE_ID`
- `ARLEN_CLUSTER_EXPECTED_NODES`
- `ARLEN_CLUSTER_EMIT_HEADERS`
- `ARLEN_I18N_DEFAULT_LOCALE`
- `ARLEN_I18N_FALLBACK_LOCALE`
- `ARLEN_PAGE_STATE_COMPAT_ENABLED`
- `ARLEN_EOC_STRICT_LOCALS`
- `ARLEN_EOC_STRICT_STRINGIFY`
- `ARLEN_REDIS_URL` (plugin template hook)
- `ARLEN_REDIS_TEST_URL` (optional live Redis conformance test target)
- `ARLEN_SMTP_HOST` (plugin template hook)
- `ARLEN_SMTP_PORT` (plugin template hook)
- `ARLEN_JOB_WORKER_INTERVAL_SECONDS` (plugin template hook)
- `ARLEN_JOB_WORKER_RETRY_DELAY_SECONDS` (plugin template hook)

Legacy compatibility fallback (`MOJOOBJC_*`) is supported but transitional.

## 12. Migrations (PostgreSQL)

From app root with `db/migrations`:

```bash
/path/to/Arlen/bin/arlen migrate --env development
```

Dry-run pending migrations:

```bash
/path/to/Arlen/bin/arlen migrate --dry-run
```

Named database target (uses `db/migrations/<target>`):

```bash
/path/to/Arlen/bin/arlen migrate --env development --database analytics
```

## 13. Generate Typed DB Helpers (Phase 4C)

From app root:

```bash
/path/to/Arlen/bin/arlen schema-codegen --env development
```

Named database target (uses target-aware defaults):

```bash
/path/to/Arlen/bin/arlen schema-codegen --env development --database analytics --force
```

Include typed row/insert/update contract artifacts:

```bash
/path/to/Arlen/bin/arlen schema-codegen --env development --typed-contracts --force
```

Custom output paths/prefix and overwrite mode:

```bash
/path/to/Arlen/bin/arlen schema-codegen \
  --env development \
  --output-dir src/Generated \
  --manifest db/schema/arlen_schema.json \
  --prefix ALNDB \
  --force
```

This generates:

- `src/Generated/ALNDBSchema.h`
- `src/Generated/ALNDBSchema.m`
- `db/schema/arlen_schema.json`

Generate typed SQL parameter/result helpers from SQL files:

```bash
/path/to/Arlen/bin/arlen typed-sql-codegen --force
```

Default SQL input format:

```sql
-- arlen:name list_users_by_status
-- arlen:params status:text limit:int
-- arlen:result id:text name:text
SELECT id, name FROM users WHERE status = $1 LIMIT $2;
```

## 14. Builder Query Caching + Diagnostics (Phase 4D)

`ALNPgConnection` now supports builder-driven execution with cache/diagnostic controls:

- `executeBuilderQuery:error:`
- `executeBuilderCommand:error:`
- `resetExecutionCaches`

Key runtime options:

- `preparedStatementReusePolicy` (`disabled`, `auto`, `always`)
- `preparedStatementCacheLimit`
- `builderCompilationCacheLimit`
- `queryDiagnosticsListener` (events: `compile`, `execute`, `result`, `error`)
- `includeSQLInDiagnosticsEvents` (default `NO`, keeps metadata redaction-safe)
- `emitDiagnosticsEventsToStderr`

## 15. Conformance + Migration Hardening (Phase 4E)

Review matrix + migration references:

- `docs/SQL_BUILDER_CONFORMANCE_MATRIX.md`
- `docs/SQL_BUILDER_PHASE4_MIGRATION.md`

Run regression gate:

```bash
make test-unit
```

CI gate command:

```bash
make ci-quality
```

Sanitizer gate command:

```bash
make ci-sanitizers
```

## 16. Deploy Smoke Validation

```bash
make deploy-smoke
```

# Getting Started

This guide gets you from zero to a running Arlen app.

Choose a focused path if you prefer guided onboarding:

- `docs/GETTING_STARTED_TRACKS.md`
- `docs/GETTING_STARTED_QUICKSTART.md`
- `docs/GETTING_STARTED_API_FIRST.md`
- `docs/GETTING_STARTED_HTML_FIRST.md`
- `docs/GETTING_STARTED_DATA_LAYER.md`

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

Runtime HTTP session backpressure limit override:

```bash
ARLEN_MAX_HTTP_SESSIONS=128 ./bin/boomhauer
```

With this limit, excess concurrent HTTP sessions receive `503 Service Unavailable` with
`X-Arlen-Backpressure-Reason: http_session_limit`.

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

Route compile startup override:

```bash
ARLEN_ROUTING_COMPILE_ON_START=0 ./bin/boomhauer
```

With this setting, route action/guard/schema readiness checks run lazily on first route use instead of during startup.

Route compile warning escalation override:

```bash
ARLEN_ROUTING_ROUTE_COMPILE_WARNINGS_AS_ERRORS=1 ./bin/boomhauer
```

With this setting, startup fails when route schema readiness emits warnings.

Cluster quorum readiness override (multi-node deployments):

```bash
ARLEN_CLUSTER_ENABLED=1 \
ARLEN_CLUSTER_EXPECTED_NODES=3 \
ARLEN_CLUSTER_OBSERVED_NODES=2 \
ARLEN_READINESS_REQUIRES_CLUSTER_QUORUM=1 \
./bin/boomhauer
```

With this setting, `GET /readyz` returns deterministic `503 not_ready` until observed nodes
meet expected quorum.

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
`make test-unit` and `make test-integration` run with a repo-local GNUstep test home (`.gnustep-home`) to keep defaults/lock files isolated.

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
ARLEN_PERF_PROFILE=comparison_http ARLEN_PERF_SKIP_GATE=1 make perf
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
make docs-api
make docs-html
make docs-serve
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

Service durability patterns (Phase 7D):

- keyed job dedupe on enqueue:

```objc
NSString *jobID = [jobs enqueueJobNamed:@"invoice.sync"
                                payload:@{ @"invoiceID" : @"42" }
                                options:@{ @"maxAttempts" : @3,
                                           @"idempotencyKey" : @"tenant-a:invoice:42" }
                                  error:&error];
```

- retry wrapper adapters:

```objc
id<ALNMailAdapter> mail = [[ALNRetryingMailAdapter alloc] initWithBaseAdapter:baseMailAdapter];
id<ALNAttachmentAdapter> attachments =
    [[ALNRetryingAttachmentAdapter alloc] initWithBaseAdapter:baseAttachmentAdapter];
```

## 11. Generate Frontend Starters

From app root:

```bash
/path/to/Arlen/bin/arlen generate frontend Dashboard --preset vanilla-spa
/path/to/Arlen/bin/arlen generate frontend Portal --preset progressive-mpa
```

Generated assets are deterministic and land under:

- `public/frontend/<name_slug>/index.html`
- `public/frontend/<name_slug>/app.js`
- `public/frontend/<name_slug>/styles.css`
- `public/frontend/<name_slug>/starter_manifest.json`
- `public/frontend/<name_slug>/README.md`

These starters demonstrate static asset serving plus API consumption against built-in endpoints:

- `/healthz?format=json`
- `/metrics`

Starter assets are release-packaging compatible because they live under `public/`.

Reference guide:

- `docs/PHASE7F_FRONTEND_STARTERS.md`

## 12. Template Troubleshooting

Run targeted transpile/lint checks when templates fail to compile or behave unexpectedly:

```bash
./build/eocc --template-root templates --output-dir build/gen/templates templates/index.html.eoc
```

`eocc` emits deterministic syntax/lint metadata:

- syntax failure location:
  - `eocc: location path=<path> line=<line> column=<column>`
- lint warning shape:
  - `eocc: warning path=<path> line=<line> column=<column> code=<code> message=<message>`

Current lint rule:

- `unguarded_include`
  - update include calls to guard return values:
    - `if (!ALNEOCInclude(out, ctx, @\"partials/_nav.html.eoc\", error)) { return nil; }`

Sigil locals support both root and dotted keypath forms:

- `$title`
- `$user.profile.email`

Invalid sigil keypath syntax (for example trailing dots) fails transpilation deterministically with location metadata.

Schema request/response descriptors can optionally apply named transformers before type validation:

- `transformer` (single)
- `transformers` (ordered list)

Built-ins include `trim`, `lowercase`, `uppercase`, `to_integer`, `to_number`, `to_boolean`, and `iso8601_date`.

Full troubleshooting workflow:

- `docs/TEMPLATE_TROUBLESHOOTING.md`

## 13. Common Environment Variables

Framework/app runtime:

- `ARLEN_APP_ROOT`
- `ARLEN_FRAMEWORK_ROOT`
- `ARLEN_HOST`
- `ARLEN_PORT`
- `ARLEN_LOG_FORMAT`
- `ARLEN_LOG_LEVEL` (`debug`, `info`, `warn`, or `error`)
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
- `ARLEN_MAX_HTTP_SESSIONS`
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
- `ARLEN_ROUTING_COMPILE_ON_START`
- `ARLEN_ROUTING_ROUTE_COMPILE_WARNINGS_AS_ERRORS`
- `ARLEN_REDIS_URL` (plugin template hook)
- `ARLEN_REDIS_TEST_URL` (optional live Redis conformance test target)
- `ARLEN_SMTP_HOST` (plugin template hook)
- `ARLEN_SMTP_PORT` (plugin template hook)
- `ARLEN_JOB_WORKER_INTERVAL_SECONDS` (plugin template hook)
- `ARLEN_JOB_WORKER_RETRY_DELAY_SECONDS` (plugin template hook)
- `ARLEN_PERF_CONCURRENCY` (perf harness request concurrency override)

Legacy compatibility fallback (`MOJOOBJC_*`) is supported but transitional.

## 14. Migrations (PostgreSQL)

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

## 15. Generate Typed DB Helpers (Phase 4C)

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

## 16. Builder Query Caching + Diagnostics (Phase 4D)

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

## 17. Conformance + Migration Hardening (Phase 4E)

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

## 18. Deploy Smoke Validation

```bash
make deploy-smoke
```

## 19. Coding-Agent JSON Workflow Contracts

Scaffold and generator workflows can emit machine-readable payloads:

```bash
/path/to/Arlen/bin/arlen new AgentApp --full --json
/path/to/Arlen/bin/arlen generate endpoint Health --route /healthz --json
```

Build/check planning workflows:

```bash
/path/to/Arlen/bin/arlen build --dry-run --json
/path/to/Arlen/bin/arlen check --dry-run --json
```

Deploy release planning workflow:

```bash
tools/deploy/build_release.sh \
  --app-root /path/to/app \
  --framework-root /path/to/Arlen \
  --releases-dir /path/to/app/releases \
  --release-id rel-001 \
  --dry-run \
  --json
```

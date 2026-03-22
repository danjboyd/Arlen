# Getting Started

This guide gets you from zero to a running Arlen app.

Choose a focused path if you prefer guided onboarding:

- `docs/GETTING_STARTED_TRACKS.md`
- `docs/GETTING_STARTED_QUICKSTART.md`
- `docs/GETTING_STARTED_API_FIRST.md`
- `docs/GETTING_STARTED_HTML_FIRST.md`
- `docs/GETTING_STARTED_DATA_LAYER.md`

## 1. Prerequisites

- clang-built GNUstep development toolchain
- `tools-xctest` package (`xctest` command)
- optional for contributors: set `ARLEN_XCTEST=/path/to/patched/xctest` if you want Apple-style `-only-testing` / `-skip-testing` filtered reruns
- when using a local uninstalled `tools-xctest` checkout, also set `ARLEN_XCTEST_LD_LIBRARY_PATH=/path/to/tools-xctest/XCTest/obj`

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

CI/runtime parity note:

- Arlen expects a clang-built GNUstep toolchain (`gnustep-config --objc-flags` should include `-fobjc-runtime=gnustep-2.2`).
- The CI bootstrap entry point is `tools/ci/install_ci_dependencies.sh`.
- Current self-hosted CI uses `ARLEN_CI_GNUSTEP_STRATEGY=preinstalled` with the clang-built GNUstep stack installed at `/usr/GNUstep`.
- Use `ARLEN_CI_GNUSTEP_STRATEGY=apt` or `bootstrap` only when provisioning a runner that does not already carry that toolchain.

## 2. Build Arlen

From repository root:

```bash
make all
```

Compile-time feature toggles:

```bash
ARLEN_ENABLE_YYJSON=0 ARLEN_ENABLE_LLHTTP=0 make all
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

`boomhauer` and `make` compile first-party Objective-C sources with `-fobjc-arc` by default.
`EXTRA_OBJC_FLAGS` is allowed for additive flags (for example sanitizers), but cannot disable ARC.
Changing compile toggles or `EXTRA_OBJC_FLAGS` invalidates cached repo build artifacts so sanitizer-instrumented tools are rebuilt before normal lanes run.
For app-root launches, the first run compiles into `.boomhauer/build/boomhauer-app`; later `--no-watch`
or `--prepare-only` runs reuse that cached binary when app/framework build inputs are unchanged.
App-root `--prepare-only` and `--print-routes` runs also print explicit `[1/4]` through `[4/4]`
build phases so you can tell whether Arlen is reusing framework/app artifacts, transpiling templates,
or linking a fresh binary.
If `ARLEN_FRAMEWORK_ROOT` points at an external Arlen checkout whose cached framework archive was last
built under ASan/UBSan, `boomhauer` now forces a clean framework rebuild before linking the app; if the
archive still contains sanitizer symbols afterward, the command fails early with a targeted diagnostic
instead of a late raw linker error.

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

WebSocket origin allowlist:

```bash
ARLEN_WEBSOCKET_ALLOWED_ORIGINS=https://app.example.com,https://admin.example.com ./bin/boomhauer
```

With an allowlist configured, websocket upgrades without a matching `Origin` header receive `403 Forbidden`.

Runtime HTTP session backpressure limit override:

```bash
ARLEN_MAX_HTTP_SESSIONS=128 ./bin/boomhauer
```

With this limit, excess concurrent HTTP sessions receive `503 Service Unavailable` with
`X-Arlen-Backpressure-Reason: http_session_limit`.

Runtime worker queue backpressure override:

```bash
ARLEN_MAX_HTTP_WORKERS=1 ARLEN_MAX_QUEUED_HTTP_CONNECTIONS=1 ./bin/boomhauer
```

With this limit, excess queued requests receive `503 Service Unavailable` with
`X-Arlen-Backpressure-Reason: http_worker_queue_full`.

Runtime realtime subscriber backpressure override:

```bash
ARLEN_MAX_REALTIME_SUBSCRIBERS_PER_CHANNEL=1 ./bin/boomhauer
```

With this limit, excess `/ws/channel/:channel` subscriptions receive `503 Service Unavailable`
with `X-Arlen-Backpressure-Reason: realtime_channel_subscriber_limit`.

Request dispatch mode override:

```bash
ARLEN_REQUEST_DISPATCH_MODE=serialized ./bin/boomhauer --env production
```

`requestDispatchMode` accepts `concurrent` or `serialized`.
Default is `concurrent`.
`serialized` mode preserves deterministic in-process dispatch ordering while still honoring HTTP
keep-alive negotiation.

Runtime metrics hot-path override:

```bash
ARLEN_METRICS_ENABLED=0 ./bin/boomhauer --env production
```

With this setting, request-path metrics counter/gauge/timing updates are bypassed (the `/metrics`
endpoint remains available but reflects only explicitly recorded metrics).

JSON backend behavior:

- `yyjson` is the default runtime backend when compiled in.
- set compile-time toggle `ARLEN_ENABLE_YYJSON=0` before build/prepare steps to
  force Foundation-only builds.
- test and benchmark tooling can still select `foundation` explicitly through
  their own non-runtime flags.

HTTP parser backend override:

```bash
ARLEN_HTTP_PARSER_BACKEND=legacy ./bin/boomhauer --env production
```

`llhttp` is the default parser backend when it is compiled in. Set compile-time toggle
`ARLEN_ENABLE_LLHTTP=0` before build/prepare steps to force legacy-only parser builds.

Security profile override:

```bash
ARLEN_SECURITY_PROFILE=strict ./bin/boomhauer
```

`strict` profile requires valid security secrets/config; startup fails fast if required values are missing.
For session middleware, `session.secret` must be at least 32 characters when `session.enabled=YES`.
Session cookies are encrypted and authenticated by default.

Auth assurance + MFA helpers:

```objc
NSError *error = nil;
[app configureAuthAssuranceForRouteNamed:@"payments_transfer"
               minimumAuthAssuranceLevel:2
         maximumAuthenticationAgeSeconds:900
                              stepUpPath:@"/mfa/challenge"
                                   error:&error];

// Primary login.
[self startAuthenticatedSessionForSubject:userID
                                 provider:@"local"
                                  methods:@[ @"pwd" ]
                                    error:&error];

// Step-up after a verified TOTP or WebAuthn assertion.
[self completeStepUpWithMethod:@"totp" assuranceLevel:2 error:&error];
```

Use `ALNContext`/`ALNController` auth helpers (`authSubject`, `authMethods`, `authAssuranceLevel`,
`isMFAAuthenticated`, `authPrimaryAuthenticatedAt`, `authMFASatisfiedAt`) instead of reading raw
session state. Browser requests that miss a route's assurance requirement redirect to the configured
step-up path with `X-Arlen-Step-Up-Required: 1`; JSON/API requests receive structured
`403 step_up_required`.

Phase 12 public auth helper surface:

- `ALNTOTP` for secrets, provisioning URIs, and bounded-skew code verification
- `ALNRecoveryCodes` for generation, Argon2id hash-at-rest, and single-use consume
- `ALNWebAuthn` for registration/assertion option generation and deterministic verification
- `ALNOIDCClient` for authorization-code + PKCE request generation, callback validation, token parsing, and ID-token verification
- `ALNAuthProviderPresets` for deterministic provider defaults plus explicit config overrides
- `ALNAuthProviderSessionBridge` for provider-identity normalization and local session bootstrap hooks

The sample app in [examples/auth_primitives/README.md](/home/danboyd/git/Arlen/examples/auth_primitives/README.md) demonstrates the local TOTP step-up path plus a stub OIDC provider flow built directly on these core contracts.

Phase 13/14/15/16 first-party module quick path:

```bash
./build/arlen module add auth
./build/arlen module add admin-ui
./build/arlen module add jobs
./build/arlen module add notifications
./build/arlen module add storage
./build/arlen module add ops
./build/arlen module add search
./build/arlen module doctor --json
./build/arlen module assets --output-dir build/module_assets
./build/arlen module migrate --env development
```

Run `./build/arlen module migrate --env <env>` before the first local `auth`
registration or login attempt. If the auth module tables are missing, Arlen now
surfaces that exact fix command instead of a generic database error.

Vendored modules live under `modules/<id>/`. `boomhauer` automatically compiles
module Objective-C sources from `modules/*/Sources` and module templates from
`modules/*/Resources/Templates`. App overrides for module templates live under
`templates/modules/<id>/...`; app overrides for module public assets live under
`public/modules/<id>/...`.

For first-party background work, use the dedicated worker runner instead of inventing an app-local wrapper:

```bash
./build/arlen jobs worker --env development --once --limit 25
```

The underlying framework script is `bin/jobs-worker`. Add `--run-scheduler` if you want that worker process to advance schedule definitions too.

The first-party `auth` module keeps `/auth/api/...` stable and supports three
presentation modes:

- `module-ui`: the default stock auth pages with an app-owned layout/context hook
- `headless`: no module-owned auth HTML, JSON/API-only consumption through `/auth/api/...`
- `generated-app-ui`: app-owned auth templates scaffolded into `templates/auth/...`

Run `./build/arlen module eject auth-ui --json` to scaffold the `generated-app-ui`
mode. See [examples/auth_ui_modes/README.md](/home/danboyd/git/Arlen/examples/auth_ui_modes/README.md)
for the mode-by-mode config and template layout, and
[examples/auth_admin_demo/README.md](/home/danboyd/git/Arlen/examples/auth_admin_demo/README.md)
for a sample app that registers an app-owned admin resource into the shared module system.

Phase 18 makes the auth module reusable below the full-page level too:

- server-rendered EOC apps can embed coarse auth fragments such as
  `mfa_factor_inventory_panel`, `mfa_enrollment_panel`, and
  `mfa_recovery_codes_panel`
- React/native clients can build MFA UX from `/auth/api/mfa`,
  `/auth/api/mfa/totp`, and `/auth/api/mfa/totp/verify` using explicit JSON
  `flow`, `mfa`, and factor-inventory payloads
- optional SMS/Twilio Verify MFA is available as a disabled-by-default factor
  under `authModule.mfa.sms`

Phase 14 adds the first-party `jobs` module with a protected `/jobs` HTML dashboard and
`/jobs/api/...` JSON/OpenAPI surface, expands the first-party `notifications` module with
authenticated inbox/preferences plus admin preview/outbox/test-send flows under
`/notifications/...` and `/notifications/api/...`, and adds the first-party `storage`
module with protected `/storage/...` management views plus `/storage/api/...` direct-upload
and signed-download contracts built on the shared jobs/mail/attachment services.

Phase 16 matures that module stack instead of widening it: `search` now persists
index state and exposes protected drilldowns alongside public query routes,
`ops` adds historical snapshots plus `/ops/modules/:module` drilldowns and
app/module-contributed widgets, and `admin-ui` now ships bulk actions, JSON/CSV
exports, typed list filters, stable sorts, and autocomplete hooks from the same
resource metadata. The reference app for that stack lives at
[examples/phase16_modules_demo/README.md](/home/danboyd/git/Arlen/examples/phase16_modules_demo/README.md).

Trusted proxy allowlist override:

```bash
ARLEN_TRUSTED_PROXY_CIDRS=127.0.0.1/32 ./bin/boomhauer
```

Forwarded headers are honored only when the peer IP matches `ARLEN_TRUSTED_PROXY_CIDRS`.
Setting the CIDR list alone enables forwarded-header handling; `ARLEN_TRUSTED_PROXY=1`
remains as a compatibility toggle that seeds a loopback allowlist when you do not provide an
explicit CIDR list. The `edge` security profile defaults this allowlist to `127.0.0.1/32`.
If you run behind a remote load balancer or ingress proxy, set the CIDR list explicitly to the
proxy network ranges instead of trusting all peers.

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
make browser-error-audit
make parity-phaseb
make perf-phasec
make perf-phased
make ci-perf-smoke
make ci-benchmark-contracts
make check
make ci-quality
make ci-json-abstraction
make ci-json-perf
make ci-dispatch-perf
make ci-http-parse-perf
make phase12-confidence
make phase14-confidence
make phase15-confidence
make phase16-confidence
make phase19-confidence
make ci-fault-injection
make ci-release-certification
make phase5e-confidence
```

`make check` runs unit + integration + perf gates.
`make test-data-layer` validates standalone `ArlenData` consumption outside the full runtime stack.
`make browser-error-audit` runs the dedicated browser error audit bundle and writes a review gallery to `build/browser-error-audit/index.html`.
`make parity-phaseb` runs the Arlen-vs-FastAPI Phase B parity gate and writes `build/perf/parity_fastapi_latest.json`.
`make perf-phasec` runs the Phase C warmup/concurrency-ladder protocol and writes `build/perf/phasec/latest_protocol_report.json`.
`make perf-phased` runs the Phase D baseline campaign (parity + comparison matrix) and writes `build/perf/phased/latest_campaign_report.json`.
`make ci-perf-smoke` runs a lighter local/manual macro perf smoke lane for the checked-in `default` and `template_heavy` profiles using the same baseline/policy gate as `make perf`, and archives artifacts under `build/perf/ci_smoke`. It stays standalone because `make ci-quality` already exercises the broader multi-profile macro perf matrix in CI.
`make ci-benchmark-contracts` validates the imported lightweight comparative benchmark manifests/config under `tests/fixtures/benchmarking/` against the documented source-of-truth split in `docs/COMPARATIVE_BENCHMARKING.md`.
`make ci-quality` runs the Phase 5E quality gate (including unit/integration coverage, the broader multi-profile macro perf gate, soak/fault tests, runtime concurrency checks, JSON abstraction/performance gates, Phase 9I fault injection, and confidence artifact generation).
`make ci-json-abstraction` blocks direct runtime `NSJSONSerialization` usage outside `ALNJSONSerialization`.
`make ci-json-perf` runs the Phase 10E JSON backend microbenchmark gate and writes artifacts under `build/release_confidence/phase10e`.
`make ci-dispatch-perf` runs the Phase 10G dispatch benchmark gate and writes artifacts under `build/release_confidence/phase10g`.
`make ci-http-parse-perf` runs the Phase 10H HTTP parser benchmark gate and writes artifacts under `build/release_confidence/phase10h`.
`make phase12-confidence` runs the Phase 12 auth confidence gate and writes artifacts under `build/release_confidence/phase12`.
`make phase14-confidence` runs the Phase 14 module confidence gate and writes artifacts under `build/release_confidence/phase14`.
`make phase15-confidence` runs the Phase 15 auth UI confidence gate and writes artifacts under `build/release_confidence/phase15`.
`make phase16-confidence` runs the Phase 16 module-maturity confidence gate and writes artifacts under `build/release_confidence/phase16`.
`make phase19-confidence` runs the Phase 19 incremental build-graph confidence gate and writes timing + rebuild-scope artifacts under `build/release_confidence/phase19`.
`make ci-fault-injection` runs the Phase 9I runtime seam fault matrix and writes artifacts under `build/release_confidence/phase9i`.
`make ci-release-certification` runs the Phase 9J release checklist and writes certification artifacts under `build/release_confidence/phase9j`.
`make test-unit` and `make test-integration` run with a repo-local GNUstep test home (`.gnustep-home`) to keep defaults/lock files isolated.
`make test-unit-filter` and `make test-integration-filter` accept `TEST=TestClass[/testMethod]` and optional `SKIP_TEST=TestClass[/testMethod]`; they auto-prefix the bundle target name and honor `ARLEN_XCTEST`.
When the selected runner is a local uninstalled `tools-xctest` build, set `ARLEN_XCTEST_LD_LIBRARY_PATH` to the matching `XCTest/obj` directory so the patched runner loads the patched `libXCTest`.
Filtered reruns require an XCTest runner that understands Apple-style `-only-testing` / `-skip-testing` arguments. Stock Debian `tools-xctest` remains fine for the normal unfiltered `make test-*` path.

Focused rerun examples:

```bash
ARLEN_XCTEST=/path/to/patched/xctest ARLEN_XCTEST_LD_LIBRARY_PATH=/path/to/tools-xctest/XCTest/obj make test-unit-filter TEST=RuntimeTests/testRenderAndIncludeNormalizeUnsuffixedTemplateReferences
ARLEN_XCTEST=/path/to/patched/xctest ARLEN_XCTEST_LD_LIBRARY_PATH=/path/to/tools-xctest/XCTest/obj make test-integration-filter TEST=Phase13AuthAdminIntegrationTests/testGeneratedAppUIAuthPagesRenderAfterEjectScaffold
ARLEN_XCTEST=/path/to/patched/xctest ARLEN_XCTEST_LD_LIBRARY_PATH=/path/to/tools-xctest/XCTest/obj make test-integration-filter TEST=Phase13AuthAdminIntegrationTests SKIP_TEST=Phase13AuthAdminIntegrationTests/testGeneratedAppUIAuthPagesRenderAfterEjectScaffold
```

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
ARLEN_PERF_SMOKE_PROFILES=default,template_heavy ARLEN_PERF_SMOKE_REPEATS=3 make ci-perf-smoke
```

The self-hosted `iep-apt` GitHub perf lanes pin `ARLEN_PERF_BASELINE_ROOT=tests/performance/baselines/iep-apt`
so the runner uses hardware-matched perf baselines instead of the broader local
developer baseline set.

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

Full-mode scaffolds now ship with a composition-first template shell:

- `templates/layouts/main.html.eoc`
- `templates/index.html.eoc` with `<%@ layout "layouts/main" %>`
- `templates/partials/_nav.html.eoc`
- `templates/partials/_feature.html.eoc`

Run app dev server:

```bash
/path/to/Arlen/bin/arlen boomhauer --port 3000
```

By default, `boomhauer` watches source/template/config/public changes and rebuilds when build
inputs change. Config/public changes restart the app without a rebuild.
On the first watch-mode build failure in a session, `boomhauer` builds the fallback error server
on demand before serving diagnostics. While that fallback server is active, `boomhauer` retries
the failed build automatically on a short backoff and the HTML error page refreshes itself unless
you disable that behavior with `ARLEN_BOOMHAUER_BUILD_ERROR_RETRY_SECONDS=0` or
`ARLEN_BOOMHAUER_BUILD_ERROR_AUTO_REFRESH_SECONDS=0`.

If watched reload fails to transpile/compile, `boomhauer` stays up and serves diagnostics:

```bash
curl -sS http://127.0.0.1:3000/
curl -sS -H 'Accept: application/json' http://127.0.0.1:3000/api/dev/build-error
```

Fixing the source and triggering a successful rebuild resumes normal responses automatically.
Fallback diagnostics include the last failure timestamp, the recovery hint, a browser HTML page that
preserves Clang-style colorized compiler output, and a plain-text-safe JSON view at
`/api/dev/build-error`.

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

When `templates/layouts/main.html.eoc` already exists, generated HTML templates opt into it automatically with `<%@ layout "layouts/main" %>`.

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
- static composition validation failures stop transpilation before code generation:
  - unknown static `layout` / `include` / `render` dependencies
  - static composition cycles
- lint warning shape:
  - `eocc: warning path=<path> line=<line> column=<column> code=<code> message=<message>`

Composition directives:

- `<%@ layout "layouts/application" %>`
- `<%@ requires title, rows %>`
- `<%@ yield %>` / `<%@ yield "sidebar" %>`
- `<%@ slot "sidebar" %>` ... `<%@ endslot %>`
- `<%@ include "partials/_summary" with @{ @"title" : $title } %>`
- `<%@ render "partials/_row" collection:$rows as:"row" empty:"partials/_empty" with @{ @"title" : $title } %>`

Current lint rules:

- `unguarded_include`
  - update include calls to guard return values:
    - `if (!ALNEOCInclude(out, ctx, @\"partials/_nav.html.eoc\", error)) { return nil; }`
- `slot_without_layout`
  - add a static `<%@ layout "..." %>` directive or remove the slot fill
- `unused_slot_fill`
  - add a matching `<%@ yield "slot_name" %>` in the selected layout or remove the slot fill

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
- `ARLEN_TRUSTED_PROXY_CIDRS`
- `ARLEN_SERVE_STATIC`
- `ARLEN_API_ONLY`
- `ARLEN_PERFORMANCE_LOGGING`
- `ARLEN_TRACE_PROPAGATION_ENABLED`
- `ARLEN_RESPONSE_IDENTITY_HEADERS_ENABLED`
- `ARLEN_HEALTH_DETAILS_ENABLED`
- `ARLEN_READINESS_REQUIRES_STARTUP`
- `ARLEN_MAX_REQUEST_LINE_BYTES`
- `ARLEN_MAX_HEADER_BYTES`
- `ARLEN_MAX_BODY_BYTES`
- `ARLEN_MAX_HTTP_SESSIONS`
- `ARLEN_MAX_WEBSOCKET_SESSIONS`
- `ARLEN_WEBSOCKET_ALLOWED_ORIGINS`
- `ARLEN_DATABASE_URL`
- `ARLEN_DB_ADAPTER`
- `ARLEN_DB_POOL_SIZE`
- `ARLEN_SESSION_ENABLED`
- `ARLEN_SESSION_SECRET`
- `ARLEN_CSRF_ENABLED`
- `ARLEN_CSRF_ALLOW_QUERY_FALLBACK` (default `0`; unsafe-method query token fallback is opt-in)
- `ARLEN_RATE_LIMIT_ENABLED`
- `ARLEN_RATE_LIMIT_REQUESTS`
- `ARLEN_RATE_LIMIT_WINDOW_SECONDS`
- `ARLEN_AUTH_ENABLED`
- `ARLEN_AUTH_BEARER_SECRET` (minimum 32 characters when `ARLEN_AUTH_ENABLED=1`)
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
- `ARLEN_PERF_BASELINE_ROOT` (optional perf baseline directory override)
- `ARLEN_PERF_POLICY_ROOT` (optional perf policy directory override)

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

Migration file behavior:

- each `.sql` file is executed as one PostgreSQL script inside a transaction
- multi-statement migration files are supported
- empty/comment-only migration files are rejected
- top-level transaction control statements such as `BEGIN`/`COMMIT` are rejected
- commands PostgreSQL disallows inside transactions still fail

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

`make ci-sanitizers` runs the Phase 10M ASan/UBSan sanitizer matrix and writes matrix artifacts
under `build/release_confidence/phase10m/sanitizers`.

Explicit Phase 9H-style blocking lane:

```bash
bash ./tools/ci/run_phase5e_sanitizers.sh
```

That entrypoint runs the narrower ASan/UBSan blocking gate, validates suppression registry
contracts, and generates confidence artifacts under `build/release_confidence/phase9h`.

Optional TSAN experimental lane:

```bash
ARLEN_SANITIZER_INCLUDE_TSAN=1 bash ./tools/ci/run_phase5e_sanitizers.sh
```

TSAN artifacts are retained at `build/sanitizers/tsan` for triage.

Phase 11 hostile-traffic confidence gates:

```bash
make ci-phase11-protocol-adversarial
make ci-phase11-fuzz
make ci-phase11-live-adversarial
make ci-phase11-sanitizers
make ci-phase11
```

Phase 11 artifacts are written under `build/release_confidence/phase11/`:
- `protocol_adversarial/`
- `protocol_fuzz/`
- `live_adversarial/`
- `sanitizers/`

Fault-injection gate seed replay:

```bash
ARLEN_PHASE9I_SEED=9011 make ci-fault-injection
```

Release certification gate:

```bash
make ci-release-certification
```

This command packages release evidence from the inline hardening gates, sanitizer/race-detection reports,
fault/stress matrices, and known-risk register validation into a single Phase 9J certification pack.

JSON backend performance gate (standalone):

```bash
make ci-json-perf
```

Override benchmark controls when needed:

```bash
ARLEN_PHASE10E_ITERATIONS=1200 ARLEN_PHASE10E_WARMUP=150 ARLEN_PHASE10E_ROUNDS=5 make ci-json-perf
```

Dispatch invocation performance gate (standalone):

```bash
make ci-dispatch-perf
```

Tune dispatch benchmark controls:

```bash
ARLEN_PHASE10G_ITERATIONS=60000 ARLEN_PHASE10G_WARMUP=6000 ARLEN_PHASE10G_ROUNDS=5 make ci-dispatch-perf
```

HTTP parser performance gate (standalone):

```bash
make ci-http-parse-perf
```

Tune HTTP parser benchmark controls:

```bash
ARLEN_PHASE10H_ITERATIONS=2000 ARLEN_PHASE10H_WARMUP=250 ARLEN_PHASE10H_ROUNDS=5 make ci-http-parse-perf
```

Tune parser gate policy by editing `tests/fixtures/performance/phase10h_http_parse_perf_thresholds.json`
(`small_*` and `large_*` keys set size-class requirements in addition to global ratios).

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

The scaffold payload now includes the default layout/partial files, and generated HTML endpoints inherit the app shell when `templates/layouts/main.html.eoc` is present.

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
  --certification-manifest /path/to/Arlen/build/release_confidence/phase9j/manifest.json \
  --json-performance-manifest /path/to/Arlen/build/release_confidence/phase10e/manifest.json \
  --dry-run \
  --json
```

`build_release.sh` enforces both a Phase 9J certification manifest and a Phase 10E JSON performance
manifest by default. Use `--allow-missing-certification` only for non-release smoke workflows.

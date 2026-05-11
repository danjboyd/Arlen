# Arlen

Arlen is a GNUstep-native Objective-C web framework with an MVC runtime, EOC templates (`.html.eoc`), and a developer server (`boomhauer`).

Arlen is designed to solve the same class of problems as frameworks like
Mojolicious while staying idiomatic to Objective-C/GNUstep conventions.

The project is still young, but the core shipped surface is already real:
server-rendered HTML and JSON app paths, OpenAPI output, first-party auth/admin
/jobs/storage modules, a PostgreSQL-first data layer, realtime support, and a
managed production runtime (`propane`). Linux with a clang-built GNUstep
toolchain is the primary production target. macOS has a verified Apple-runtime
path, and Windows `CLANG64` is currently a preview target.

## Start Here

If you are new to Arlen, start with:

- `docs/GETTING_STARTED_MACOS.md` if you are targeting macOS with Apple APIs
- `docs/FIRST_APP_GUIDE.md`
- `docs/GETTING_STARTED.md`
- `docs/GETTING_STARTED_TRACKS.md`
- `docs/EOC_GUIDE.md` if you are building server-rendered pages with EOC
- `docs/APP_AUTHORING_GUIDE.md`
- `docs/LITE_MODE_GUIDE.md`
- `docs/README.md`

## Quick Start

If you are evaluating Arlen on Linux/GNUstep, make sure you have:

- a clang-built GNUstep toolchain
- initialized submodules via `git submodule update --init --recursive`
- `tools-xctest` available if you plan to run the full test suite

Linux/GNUstep evaluation path:

```bash
source tools/source_gnustep_env.sh
./bin/arlen doctor
make all
./bin/test --smoke-only
```

macOS Apple-runtime path:

```bash
./bin/arlen doctor
./bin/build-apple
./bin/test --smoke-only
```

Create and run your first app:

```bash
mkdir -p ~/arlen-apps
cd ~/arlen-apps
/path/to/Arlen/bin/arlen new MyApp
cd MyApp
/path/to/Arlen/bin/arlen boomhauer --port 3000
```

Then open `http://127.0.0.1:3000/`.

If you already use a managed GNUstep toolchain on Linux, you can source its
env script first instead. The Arlen helper resolves `GNUSTEP_SH`,
`GNUSTEP_MAKEFILES`, `gnustep-config`, and finally `/usr/GNUstep`. On macOS,
use the Apple builder documented in `docs/GETTING_STARTED_MACOS.md`.
For the current native Windows preview entry path and packaged-release
contract, see `docs/WINDOWS_CLANG64.md`.

If `./bin/arlen doctor` fails, stop there and fix the reported GNUstep
toolchain issue before expecting `make all` or app scaffolds to work.

The default full scaffold gives you:

- `src/main.m`
- `src/Controllers/HomeController.{h,m}`
- `templates/layouts/main.html.eoc`
- `templates/index.html.eoc`
- `config/app.plist`

## Why Arlen

Arlen is for teams that want a batteries-included web framework in
Objective-C/GNUstep instead of a thin HTTP layer plus a long list of unrelated
libraries. The goal is to let you scaffold a real app, serve HTML or JSON, add
auth and operational surfaces, work against a serious data layer, and ship with
one coherent toolchain.

## Good Fit If

- you want to stay native to Objective-C and GNUstep for web work
- you want one framework for server-rendered HTML, JSON APIs, or mixed apps
- you want built-in modules for auth, admin, jobs, notifications, storage, ops, and search
- you want first-party tooling for OpenAPI, migrations, schema/SQL codegen, and production runtime management
- you prefer explicit, deterministic behavior over heavy convention or hidden magic

## Probably Not A Fit If

- you need a large third-party ecosystem today
- you need untrusted template execution or sandboxed template code; EOC templates are trusted code
- you want a non-GNUstep stack or a generic GCC-oriented GNUstep setup
- you want the smallest possible microframework and plan to assemble everything yourself

## What Ships Today

- `HTML-first and JSON-first paths`: EOC templates, layouts, partials, forms, controller rendering helpers, and API endpoints in the same app.
- `API tooling`: OpenAPI generation, interactive docs, and JSON-first scaffolds.
- `Auth and security`: sessions, CSRF, rate limiting, MFA, recovery codes, passkeys/WebAuthn, and OIDC/provider login.
- `First-party modules`: `auth`, `admin-ui`, `jobs`, `notifications`, `storage`, `ops`, and `search`.
- `Realtime and live UI`: WebSocket and SSE support, live fragment responses, built-in `/arlen/live.js`, keyed collection helpers, live regions, controller helpers for live updates/navigation, and a durable event-stream seam with append/replay/auth contracts plus websocket/SSE/poll integration.
- `Data layer`: PostgreSQL-first migrations, schema codegen, typed SQL helpers, an optional SQL ORM foundation, optional MSSQL support, and a runtime-inactive Dataverse Web API client/query/codegen surface.
- `Runtime`: `boomhauer` for development and `propane` for production worker supervision, reloads, and cluster controls.
- `Diagnostics and verification`: `arlen doctor`, build diagnostics, focused regression lanes, and live-backed integration coverage.

## Notable Built-In Capabilities

- interactive OpenAPI explorer and generated API docs
- passkey/WebAuthn MFA and OIDC login flows
- built-in admin, ops, storage, notifications, jobs, and search surfaces
- WebSocket/SSE support plus production runtime management with `propane`
- typed schema and SQL code generation rather than only raw SQL strings
- Dataverse metadata/codegen and OData helpers without forcing Dataverse through the SQL adapter seam

## Quick Evaluation Path

- `5 minutes`: run the quick start, then hit `/`, `/healthz`, and `/openapi`.
- `15 minutes`: add a second endpoint with `arlen generate endpoint Hello --route /hello --method GET --template` and see how the controller/template flow feels.
- `30 minutes`: try a first-party module such as `auth`, or open one of the example apps listed below.

## Example Apps

- [Basic App Smoke Guide](examples/basic_app/README.md): smallest app-owned smoke path.
- [API-First Reference App](examples/api_reference/README.md): JSON/OpenAPI-heavy reference surface.
- [Dataverse Reference](examples/dataverse_reference/README.md): app-level Dataverse config, controller helpers, and codegen flow.
- [Arlen ORM Reference](examples/arlen_orm_reference/README.md): optional SQL and Dataverse ORM reference surface.
- [React/TypeScript Reference](examples/react_typescript_reference/README.md): descriptor-first React/TypeScript workspace showing generated validators, query contracts, module/resource metadata, and optional React helpers.
- [Reference Server (TypeScript Integration)](examples/typescript_reference_server/README.md): live backend used by the generated TypeScript integration and React reference lanes.
- [Auth + Admin Demo](examples/auth_admin_demo/README.md): modules, auth, and admin composition.
- [Multi-Module Demo](examples/multi_module_demo/README.md): broader multi-module app surface (`admin-ui` + `search` + `ops`).
- [Search Module Playbook](examples/search_module_playbook/README.md): scaffold-first path for app-owned search resources and engine swaps.
- [Tech Demo](examples/tech_demo/README.md): larger end-to-end example with Arlen UI/runtime features, including `/tech-demo/live`.

## Status

For readers evaluating maturity: Arlen is young, but it is no longer a minimal
scaffold.

- Core framework and runtime are complete through the current first-party scope: HTML/JSON request handling, EOC templates, data-layer fundamentals, auth/security hardening, realtime/event-stream support, and deployment/runtime management.
- First-party modules (`auth`, `admin-ui`, `jobs`, `notifications`, `storage`, `ops`, `search`) are shipping.
- A public-release test confidence scaffold (acceptance harness, golden-render catalog, regression-intake enforcement) is in place.
- Linux with clang-built GNUstep is the authoritative production baseline.
- macOS has a verified Apple-runtime path.
- Windows `CLANG64` is available as a preview path, not the primary production target.
- A capability-level maturity snapshot lives in [docs/STATUS.md](docs/STATUS.md). Engineering history and milestone detail live under [docs/internal/](docs/internal/).

## Requirements and Setup Details

If you are evaluating Arlen rather than contributing to the framework itself,
the quick start above plus the example apps and docs index are usually enough
for a first pass. The rest of this section covers the more detailed local
toolchain and contributor workflow.

Prerequisites:
- clang-built GNUstep toolchain installed
- `tools-xctest` installed (provides `xctest`)
- initialized submodules (`git submodule update --init --recursive`) so the
  repo-local patched `vendor/tools-xctest` runner and the pinned
  `vendor/gnustep-cli-new` Windows provisioning source are available

Contributor test-runner default:
- Arlen builds and uses `vendor/tools-xctest/obj/xctest` by default while
  GNUstep/tools-xctest PR 5 is pending upstream, so focused reruns such as
  `make test-unit-filter TEST=RuntimeTests/testRenderAndIncludeNormalizeUnsuffixedTemplateReferences`
  honor Apple-style `-only-testing` filters
- set `ARLEN_USE_VENDORED_XCTEST=0` to fall back to the system `xctest`
- set `ARLEN_XCTEST=/path/to/xctest` and, when needed,
  `ARLEN_XCTEST_LD_LIBRARY_PATH=/path/to/tools-xctest/XCTest/obj` to test a
  different runner

Initialize GNUstep in your shell:

```bash
source tools/source_gnustep_env.sh
```

Run bootstrap diagnostics before building:

```bash
./bin/arlen doctor
```

Contributor and CI notes:
- Arlen CI expects a clang-built GNUstep toolchain, not a generic GCC-oriented distro stack.
- The workflow bootstrap entry point is `tools/ci/install_ci_dependencies.sh`.
- The current documented required checks for `main` are `linux-quality / quality-gate`, `linux-sanitizers / sanitizer-gate`, and `docs-quality / docs-gate`.
- Apple and Windows CI lanes are intentionally visible but non-required while
  Linux/GNUstep remains the authoritative production baseline.
- Release certification is intentionally isolated in
  `release-certification / release-certification` instead of the merge gate.
- Current self-hosted runners use `ARLEN_CI_GNUSTEP_STRATEGY=preinstalled` with the clang-built GNUstep toolchain installed at `/usr/GNUstep`.
- Local contributor shells can use `tools/source_gnustep_env.sh`, which also
  supports managed toolchains that export `GNUSTEP_SH` or `GNUSTEP_MAKEFILES`.
- Use `ARLEN_CI_GNUSTEP_STRATEGY=apt` or `bootstrap` only when provisioning a runner that does not already carry that toolchain.

Build framework tools and dev server:

```bash
make all
```

Build policy: Arlen enforces ARC across first-party Objective-C compile paths (`-fobjc-arc` required).
`EXTRA_OBJC_FLAGS` is additive only and cannot disable ARC.
Changing compile toggles or `EXTRA_OBJC_FLAGS` invalidates cached repo build artifacts so sanitizer-built tools are not silently reused in normal lanes.
For app-root non-watch flows, `boomhauer --prepare-only` and `--print-routes`
now preserve the underlying non-zero build exit status and write diagnostics to
`.boomhauer/last_build_error.log` plus `.boomhauer/last_build_error.meta` so
automation does not treat stale binaries as a successful prepare.

Run the built-in development server:

```bash
./bin/boomhauer
```

Create and run your first app with the CLI:

```bash
mkdir -p ~/arlen-apps
cd ~/arlen-apps
/path/to/Arlen/bin/arlen new MyApp
cd MyApp
/path/to/Arlen/bin/arlen boomhauer --port 3000
```

Full-mode scaffolds now default to composition-first EOC:
- `templates/layouts/main.html.eoc` owns the app shell
- `templates/index.html.eoc` opts into that shell with `<%@ layout "layouts/main" %>`
- `templates/partials/_nav.html.eoc` and `templates/partials/_feature.html.eoc` demonstrate partial includes and collection rendering

Module quick path:

```bash
/path/to/Arlen/build/arlen module add auth
/path/to/Arlen/build/arlen module add admin-ui
/path/to/Arlen/build/arlen module add jobs
/path/to/Arlen/build/arlen module add notifications
/path/to/Arlen/build/arlen module add storage
/path/to/Arlen/build/arlen module add ops
/path/to/Arlen/build/arlen module add search
/path/to/Arlen/build/arlen module doctor --json
/path/to/Arlen/build/arlen module assets --output-dir build/module_assets
/path/to/Arlen/build/arlen module migrate --env development
```

Run `module migrate --env <env>` before the first local `auth` registration or
login attempt. Missing auth tables now surface an actionable module-migrate
message instead of a generic database error.

See `examples/multi_module_demo/README.md` for the canonical app-owned
`admin-ui` + `search` + `ops` composition path on top of the first-party
module stack.

First-party module surfaces:
- `auth` keeps `/auth/api/...` stable, now exposes explicit MFA `flow`/`mfa` JSON plus `/auth/api/mfa` factor discovery for headless clients, supports optional disabled-by-default SMS/Twilio Verify MFA, and lets apps choose `headless`, `module-ui`, or `generated-app-ui` ownership for `/auth/...`
- `admin-ui` ships HTML under `/admin/...` and JSON under `/admin/api/...`
- `jobs` ships protected HTML under `/jobs/...` and JSON under `/jobs/api/...`
- `notifications` ships user HTML under `/notifications/...`, admin HTML under `/notifications/...`, and JSON under `/notifications/api/...`
- `storage` ships protected HTML under `/storage/...`, JSON/OpenAPI under `/storage/api/...`, and signed downloads under `/storage/api/download/:token`
- `ops` ships protected HTML under `/ops/...` and JSON/OpenAPI under `/ops/api/...`
- `search` ships public query HTML/JSON under `/search/...` and protected reindex routes under `/search/api/...`

Auth UI ownership quick path:
- `module-ui`: default stock auth pages with optional app layout/context hook
- server-rendered EOC apps can now also embed coarse auth fragments such as the MFA enrollment/challenge/recovery panels inside app-owned pages
- `headless`: set `authModule.ui.mode = "headless"` and use `/auth/api/...` from your SPA or native client
- `generated-app-ui`: run `/path/to/Arlen/build/arlen module eject auth-ui --json` to scaffold `templates/auth/...`, `templates/auth/fragments/...`, factor-management pages, and `public/auth/auth.css` plus the local QR asset

Run tests and quality gate:

```bash
./bin/test
make check
make ci-perf-smoke
make ci-benchmark-contracts
make ci-quality
make ci-fault-injection
make ci-release-certification
make test-data-layer
make browser-error-audit
```

The `GNUmakefile` exposes additional confidence lanes tied to historical
milestone work (search the `Makefile` for `*-confidence` targets). Those lanes
are intended for contributors validating specific subsystems and are not part
of the standard quality gate above.

`make ci-perf-smoke` is the lighter local/manual macro perf subset. The
self-hosted quality workflow already runs the broader multi-profile macro perf
matrix through `make ci-quality`, pinned to
`tests/performance/baselines/iep-apt` on the current `iep-apt` runner.

`make browser-error-audit` generates a browser-reviewable gallery of representative
build/runtime error surfaces under `build/browser-error-audit/index.html`.

Run the technology demo:

```bash
./bin/tech-demo
```

Then open `http://127.0.0.1:3110/tech-demo`.

Run deployment smoke validation:

```bash
make deploy-smoke
```

## Documentation

Start with the [Docs Index](docs/README.md).

Best next reads for evaluation:

- [First App Guide](docs/FIRST_APP_GUIDE.md)
- [Getting Started](docs/GETTING_STARTED.md)
- [App Authoring Guide](docs/APP_AUTHORING_GUIDE.md)
- [Modules](docs/MODULES.md)
- [Auth Module](docs/AUTH_MODULE.md)
- [Deployment Guide](docs/DEPLOYMENT.md)
- [Toolchain Matrix](docs/TOOLCHAIN_MATRIX.md)
- [Arlen for X Migration Guides](docs/ARLEN_FOR_X_INDEX.md)
- [API Reference](docs/API_REFERENCE.md)

Generate browser-friendly HTML docs:

```bash
make docs-api
make docs-html
make docs-serve
```

Open `build/docs/index.html` in a browser.

For the broader guide set, examples, historical roadmap material, and specs,
use [docs/README.md](docs/README.md) and [docs/STATUS.md](docs/STATUS.md).

## Naming

- Development server: `boomhauer`
- Production manager: `propane`
- All `propane` settings are referred to as "propane accessories"

## License

Arlen is licensed under the GNU Lesser General Public License, version 2 or (at your option) any later version (LGPL-2.0-or-later), aligned with GNUstep Base library licensing.

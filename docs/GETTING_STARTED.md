# Getting Started

This guide gets you from a clean checkout to a running Arlen app without
pulling you through contributor-only release or CI material first.

If you are targeting macOS with Apple APIs rather than GNUstep, use
`docs/GETTING_STARTED_MACOS.md` first.

If you prefer a narrower path, see:

- `docs/GETTING_STARTED_QUICKSTART.md`
- `docs/GETTING_STARTED_API_FIRST.md`
- `docs/GETTING_STARTED_HTML_FIRST.md`
- `docs/GETTING_STARTED_DATA_LAYER.md`

## 1. Prerequisites

- a clang-built GNUstep toolchain
- `tools-xctest` (`xctest` command)

Initialize GNUstep in your shell. The repo helper also works with managed
toolchains that expose `GNUSTEP_SH` or `GNUSTEP_MAKEFILES`:

```bash
source /path/to/Arlen/tools/source_gnustep_env.sh
```

Run the bootstrap diagnostic first:

```bash
/path/to/Arlen/bin/arlen doctor
```

If you want structured output for automation:

```bash
/path/to/Arlen/bin/arlen doctor --json
```

For the known-good baseline, see `docs/TOOLCHAIN_MATRIX.md`.

## 2. Build Arlen

From repository root:

```bash
make all
```

This builds the main tools you will use first:

- `build/arlen`
- `build/boomhauer`
- `build/eocc`

## 3. Create Your First App

```bash
mkdir -p ~/arlen-apps
cd ~/arlen-apps
/path/to/Arlen/bin/arlen new MyApp
cd MyApp
```

The full-mode scaffold gives you:

- `src/main.m`
- `src/Controllers/HomeController.{h,m}`
- `templates/layouts/main.html.eoc`
- `templates/index.html.eoc`
- `templates/partials/_nav.html.eoc`
- `templates/partials/_feature.html.eoc`
- `config/app.plist`

If you want the smallest possible app shape instead, see
`docs/LITE_MODE_GUIDE.md`.

## 4. Run the App

From app root:

```bash
/path/to/Arlen/bin/arlen boomhauer --port 3000
```

Then verify:

```bash
curl -i http://127.0.0.1:3000/
curl -i http://127.0.0.1:3000/healthz
curl -i http://127.0.0.1:3000/openapi
```

`boomhauer` watches app files by default and rebuilds when inputs change.
Arlen reserves `/healthz`, `/readyz`, `/livez`, `/metrics`, and `/clusterz`
for built-in operability, so app routes should not reuse those paths.

## 5. Add One More Route

Prefer the generator-driven path for your second route:

```bash
/path/to/Arlen/bin/arlen generate endpoint Hello \
  --route /hello \
  --method GET \
  --template
```

That command:

- creates `src/Controllers/HelloController.{h,m}`
- wires the route into your app bootstrap
- creates `templates/hello/index.html.eoc`

Then verify:

```bash
curl -i http://127.0.0.1:3000/hello
```

For static route tables, you can also declare routes in `config/app.plist`
with the top-level `routes` array. Those entries call the same router APIs as
Objective-C route code, so matching, policies, reverse lookup, and route
inspection stay on one effective route table.

## 6. Common Next Commands

From app root:

```bash
/path/to/Arlen/bin/arlen routes
/path/to/Arlen/bin/arlen config --env development --json
/path/to/Arlen/bin/arlen check
```

Use `arlen routes` when you want to inspect registration order, route names,
and whether each route came from plist configuration or Objective-C code.

## 7. Choose the Next Guide

- building JSON-first endpoints: `docs/GETTING_STARTED_API_FIRST.md`
- building server-rendered pages: `docs/GETTING_STARTED_HTML_FIRST.md`
- writing routes/controllers/middleware directly: `docs/APP_AUTHORING_GUIDE.md`
- configuring the app: `docs/CONFIGURATION_REFERENCE.md`
- adding first-party modules: `docs/MODULES.md`
- adding app-owned search resources after installing `jobs` + `search`:
  `arlen generate search Catalog` and `docs/SEARCH_MODULE.md`
- starting from the smallest app shape: `docs/LITE_MODE_GUIDE.md`
- generating plugins or service adapters: `docs/PLUGIN_SERVICE_GUIDE.md`
- generating frontend starter folders: `docs/FRONTEND_STARTERS.md`
- generating descriptor-first TypeScript models, validators, query/resource
  metadata, clients, and optional React helpers for a frontend app:
  `docs/GETTING_STARTED_API_FIRST.md`, `arlen typescript-codegen`, and
  `examples/phase28_react_reference/README.md`
- using Dataverse through the Web API: `docs/DATAVERSE.md`

## 8. Optional Dataverse Path

If your app needs Dataverse rather than the SQL migration/schema-codegen path,
use `docs/DATAVERSE.md`. The Dataverse surface is compiled in but
runtime-inactive by default, so apps that do not configure it do not pick up
extra startup work.

## 9. Contributor Notes

If you are working on Arlen itself rather than just building an app with it:

- `make test`, `make ci-quality`, and the broader confidence lanes remain the
  deeper project-level verification path
- `docs/DEPLOYMENT.md` covers the immutable release artifact workflow; current
  release payloads package migrations plus a prepared app binary so
  `framework/bin/propane` can run directly from the built artifact, and
  `arlen deploy init|plan|push|release|status|rollback|doctor|logs` is the
  preferred operator-facing wrapper, including checked-in `config/deploy.plist`
  targets and SSH-backed target deploy flows
- `docs/DOCUMENTATION_POLICY.md` covers docs definition-of-done and quality
  expectations
- `docs/TESTING_WORKFLOW.md` covers the focused regression and confidence lanes

# Getting Started

This guide gets you from a clean checkout to a running Arlen app without
pulling you through contributor-only release or CI material first.

If you prefer a narrower path, see:

- `docs/GETTING_STARTED_QUICKSTART.md`
- `docs/GETTING_STARTED_API_FIRST.md`
- `docs/GETTING_STARTED_HTML_FIRST.md`
- `docs/GETTING_STARTED_DATA_LAYER.md`

## 1. Prerequisites

- a clang-built GNUstep toolchain
- `tools-xctest` (`xctest` command)

Initialize GNUstep in your shell:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
```

For native Windows on MSYS2 `CLANG64`, enter the checked-in toolchain shell
instead:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1
```

Or add the checked-in Windows wrappers to your `PATH` for the current
PowerShell session:

```powershell
$env:PATH = "C:\path\to\Arlen\bin;$env:PATH"
```

Run the bootstrap diagnostic first:

```bash
/path/to/Arlen/bin/arlen doctor
```

From plain PowerShell on Windows, the same command can be:

```powershell
arlen doctor
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

On Windows CLANG64, `make all` currently builds:

- `build/arlen`
- `build/eocc`
- `build/lib/libArlenFramework.a`

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

From plain PowerShell on Windows with `bin` on `PATH`:

```powershell
boomhauer --port 3000
```

For a long-running Windows service instead of an interactive console server:

```powershell
arlen service install --mode dev --dry-run --json
```

- run that from the app root to inspect the autodiscovered `boomhauer` service
  plan and default logs under `tmp\service\`
- re-run without `--dry-run` from plain PowerShell and Arlen will request UAC
  elevation when Windows service registration is needed
- use `arlen service uninstall --mode dev` from the same app root to remove the
  registered developer service later

Then verify:

```bash
curl -i http://127.0.0.1:3000/
curl -i http://127.0.0.1:3000/healthz
curl -i http://127.0.0.1:3000/openapi
```

`boomhauer` watches app files by default and rebuilds when inputs change on
both Linux and the checked-in Windows CLANG64 app-root flow.

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

## 6. Common Next Commands

From app root:

```bash
/path/to/Arlen/bin/arlen routes
/path/to/Arlen/bin/arlen config --env development --json
/path/to/Arlen/bin/arlen check
```

Use `arlen routes` when you want to inspect registration order and route names.
On Windows CLANG64:

- use `make phase24-windows-tests`, `make phase24-windows-db-smoke`, and
  `make phase24-windows-runtime-tests` for the fastest focused CLANG64 reruns
- promote broader fixes through `make test-unit`, `make test-integration`,
  `make phase20-postgres-live-tests`, and `make phase20-mssql-live-tests`
- use `make phase24-windows-confidence` for the focused Windows confidence pack
  or `make phase24-windows-parity` for the full parity workflow

## 7. Choose the Next Guide

- building JSON-first endpoints: `docs/GETTING_STARTED_API_FIRST.md`
- building server-rendered pages: `docs/GETTING_STARTED_HTML_FIRST.md`
- writing routes/controllers/middleware directly: `docs/APP_AUTHORING_GUIDE.md`
- configuring the app: `docs/CONFIGURATION_REFERENCE.md`
- adding first-party modules: `docs/MODULES.md`
- starting from the smallest app shape: `docs/LITE_MODE_GUIDE.md`
- generating plugins or service adapters: `docs/PLUGIN_SERVICE_GUIDE.md`
- generating frontend starter folders: `docs/FRONTEND_STARTERS.md`

## 8. Contributor Notes

If you are working on Arlen itself rather than just building an app with it:

- `make test`, `make ci-quality`, and the broader confidence lanes remain the
  deeper project-level verification path
- `docs/DOCUMENTATION_POLICY.md` covers docs definition-of-done and quality
  expectations
- `docs/TESTING_WORKFLOW.md` covers the focused regression and confidence lanes

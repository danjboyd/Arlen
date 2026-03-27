# First App Guide

This is the shortest full-app walkthrough for Arlen.

## 1. Build Arlen CLI (one-time per checkout)

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
cd /path/to/Arlen
make arlen
```

## 2. Create a Workspace and Scaffold an App

```bash
mkdir -p ~/arlen-apps
cd ~/arlen-apps
/path/to/Arlen/bin/arlen new MyApp
cd MyApp
```

Scaffold highlights:

- `src/main.m`: app entrypoint and route registration
- `src/Controllers/HomeController.m`: controller for `/`
- `templates/layouts/main.html.eoc`: default app shell
- `templates/index.html.eoc`: initial page template with `<%@ layout "layouts/main" %>`
- `templates/partials/_nav.html.eoc` and `templates/partials/_feature.html.eoc`: composition-first partial examples
- `config/app.plist`: app config defaults

## 3. Run the App

```bash
/path/to/Arlen/bin/arlen boomhauer --port 3000
```

Check it:

```bash
curl -i http://127.0.0.1:3000/
```

Notes:

- `arlen boomhauer` delegates to `bin/boomhauer`
- watch mode is on by default
- if a reload introduces a compile/transpile error, `boomhauer` stays up and
  serves diagnostics until you fix it

## 4. Add Your First Extra Endpoint

Use the generator-driven path:

```bash
/path/to/Arlen/bin/arlen generate endpoint Hello \
  --route /hello \
  --method GET \
  --template
```

This command creates:

- `src/Controllers/HelloController.h`
- `src/Controllers/HelloController.m`
- `templates/hello/index.html.eoc`

It also wires the route into your app bootstrap automatically.

Verify:

```bash
curl -i http://127.0.0.1:3000/hello
```

## 5. Useful Next Commands

```bash
/path/to/Arlen/bin/arlen routes
/path/to/Arlen/bin/arlen config --json
/path/to/Arlen/bin/arlen generate migration AddUsers
/path/to/Arlen/bin/arlen migrate --dry-run
```

## 6. What To Read Next

- `docs/APP_AUTHORING_GUIDE.md`
- `docs/CONFIGURATION_REFERENCE.md`
- `docs/GETTING_STARTED_API_FIRST.md`
- `docs/GETTING_STARTED_HTML_FIRST.md`
- `docs/MODULES.md`

## 7. Troubleshooting

- `arlen boomhauer` cannot find framework root:
  - run with `ARLEN_FRAMEWORK_ROOT=/path/to/Arlen` in your environment
- GNUstep toolchain errors:
  - re-run `source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh` in the
    same shell
- build error page shown in browser:
  - check your recent code edits; `boomhauer` serves diagnostics and resumes
    normal responses after the next successful rebuild

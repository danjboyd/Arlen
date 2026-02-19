# First App Guide

This is the quickest path to your first working Arlen app.

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
- `templates/index.html.eoc`: initial template
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
- `arlen boomhauer` delegates to `bin/boomhauer`.
- Watch mode is on by default.
- If a reload introduces a compile/transpile error, boomhauer stays up and serves diagnostics until you fix it.

## 4. Add Your First Extra Endpoint

Generate a controller:

```bash
/path/to/Arlen/bin/arlen generate controller Hello
```

Update `src/main.m`:

1. Add import:

```objc
#import "Controllers/HelloController.h"
```

2. Add route registration near the existing home route:

```objc
[app registerRouteMethod:@"GET"
                    path:@"/hello"
                    name:@"hello"
         controllerClass:[HelloController class]
                  action:@"index"];
```

Save file. In watch mode, Arlen rebuilds automatically.

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

## 6. Troubleshooting

- `arlen boomhauer` cannot find framework root:
  - run with `ARLEN_FRAMEWORK_ROOT=/path/to/Arlen` in your environment.
- GNUstep toolchain errors:
  - re-run `source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh` in the same shell.
- Build error page shown in browser:
  - check your recent code edits; boomhauer serves diagnostics and resumes normal responses after the next successful rebuild.

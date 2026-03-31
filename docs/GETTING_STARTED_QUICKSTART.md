# Getting Started: Quickstart Track

This track gets you from a clean checkout to a running app as quickly as
possible.

## 1. Prerequisites

- clang-built GNUstep toolchain
- `tools-xctest` package (`xctest` command)

Initialize GNUstep:

```bash
source /path/to/Arlen/tools/source_gnustep_env.sh
```

## 2. Verify Tooling

```bash
./bin/arlen doctor
```

For automation output:

```bash
./bin/arlen doctor --json
```

## 3. Build Core Tools

```bash
make all
```

## 4. Create an App

```bash
mkdir -p ~/arlen-apps
cd ~/arlen-apps
/path/to/Arlen/bin/arlen new MyApp
cd MyApp
```

## 5. Run Development Server

```bash
/path/to/Arlen/bin/arlen boomhauer --port 3000
```

Smoke checks:

```bash
curl -i http://127.0.0.1:3000/
curl -i http://127.0.0.1:3000/healthz
```

## 6. Add One Route

```bash
/path/to/Arlen/bin/arlen generate endpoint Hello \
  --route /hello \
  --method GET \
  --template
```

```bash
curl -i http://127.0.0.1:3000/hello
```

## 7. Next Guides

- [First App Guide](FIRST_APP_GUIDE.md)
- [App Authoring Guide](APP_AUTHORING_GUIDE.md)
- [API-First](GETTING_STARTED_API_FIRST.md)
- [HTML-First](GETTING_STARTED_HTML_FIRST.md)
- [Lite Mode Guide](LITE_MODE_GUIDE.md)

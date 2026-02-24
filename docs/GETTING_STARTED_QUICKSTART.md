# Getting Started: Quickstart Track

This track takes you from a clean checkout to a running app and passing checks.

## 1. Prerequisites

- GNUstep toolchain
- `tools-xctest` package (`xctest` command)

Initialize GNUstep:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
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

Build outputs:

- `build/arlen`
- `build/boomhauer`
- `build/eocc`

## 4. Run Development Server

```bash
./bin/boomhauer
```

Smoke checks:

```bash
curl -i http://127.0.0.1:3000/
curl -i http://127.0.0.1:3000/healthz
curl -i http://127.0.0.1:3000/readyz
```

## 5. Run Quality Gates

```bash
./bin/test
make check
make ci-quality
```

## 6. Build and Open Docs

```bash
make docs-html
```

Open `build/docs/index.html`.

## 7. Create Your First App

```bash
mkdir -p ~/arlen-apps
cd ~/arlen-apps
/path/to/Arlen/bin/arlen new MyApp
cd MyApp
/path/to/Arlen/bin/arlen boomhauer --port 3000
```

Next: choose [API-First](GETTING_STARTED_API_FIRST.md) or [HTML-First](GETTING_STARTED_HTML_FIRST.md).

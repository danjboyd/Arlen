# Basic App Smoke Guide

This repo now includes a minimal EOC render pipeline and a lightweight dev HTTP server for capability testing.

## Quick Start

1. Build transpiler + generated templates + sample tools:

```bash
make all
make boomhauer
```

2. Run render-only smoke output:

```bash
./build/eoc-smoke-render
```

3. Start dev server:

```bash
./build/boomhauer --port 3000
```

4. Hit endpoints:

```bash
curl -i http://127.0.0.1:3000/
curl -i http://127.0.0.1:3000/healthz
```

## One-Command Smoke Validation

```bash
./bin/smoke
```

This checks:

- template render output from `ALNEOCRenderTemplate("index.html.eoc", ...)`
- include rendering for `partials/_nav.html.eoc`
- HTML escaping behavior
- HTTP server response over localhost

## Convenience Launcher

```bash
./bin/boomhauer --port 3000
```

`bin/boomhauer` builds the dev server target if needed and then launches it.

`bin/dev` remains as a compatibility alias that launches `boomhauer`.

## Technology Demo Site

A richer demo page is available at:

```bash
./bin/tech-demo
```

Then open:

- `http://127.0.0.1:3110/tech-demo`
- `http://127.0.0.1:3110/tech-demo/dashboard`
- `http://127.0.0.1:3110/tech-demo/api/catalog`

## Production Server Naming

- Planned production server manager name: `propane`
- All settings for `propane` will be referred to as **propane accessories**

## Current Limits

- Single-process server, no file watching/reload yet.
- Minimal routing (`/`, `/healthz`, 404 fallback).
- No prefork/worker mode (`propane` not implemented yet).

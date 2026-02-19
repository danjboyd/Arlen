# Getting Started

This guide gets you from zero to a running Arlen app.

## 1. Prerequisites

- GNUstep development toolchain
- `tools-xctest` package (`xctest` command)

Initialize GNUstep tooling in your shell:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
```

## 2. Build Arlen

From the repository root:

```bash
make all
```

This builds:
- EOC transpiler (`build/eocc`)
- CLI (`build/arlen`)
- dev server (`build/boomhauer`)
- framework artifacts and generated templates

## 3. Run the Built-In Dev Server

```bash
./bin/boomhauer
```

Check endpoints:

```bash
curl -i http://127.0.0.1:3000/
curl -i http://127.0.0.1:3000/healthz
```

## 4. Run Tests

```bash
./bin/test
```

Direct make targets are also available:

```bash
make test
make test-unit
make test-integration
```

## 5. Run the Tech Demo

```bash
./bin/tech-demo
```

Then open `http://127.0.0.1:3110/tech-demo`.

## 6. Build Browser-Friendly Documentation

```bash
make docs-html
```

Open `build/docs/index.html`.

## 7. Create Your First App (Recommended CLI Path)

Scaffold a full app (default mode):

```bash
mkdir -p ~/arlen-apps
cd ~/arlen-apps
/path/to/Arlen/bin/arlen new MyApp
cd MyApp
```

Run app dev server from app root:

```bash
/path/to/Arlen/bin/arlen boomhauer --port 3000
```

By default, boomhauer watches source/template/config/public changes and rebuilds.

If a watched reload fails to transpile/compile, `boomhauer` stays up and serves diagnostics instead of crashing:

```bash
curl -sS http://127.0.0.1:3000/
curl -sS -H 'Accept: application/json' http://127.0.0.1:3000/api/dev/build-error
```

After you fix the source error, the next successful rebuild resumes normal app responses automatically.

Lite app scaffold remains available:

```bash
/path/to/Arlen/bin/arlen new MyLiteApp --lite
```

For a copy-paste end-to-end walkthrough, see `docs/FIRST_APP_GUIDE.md`.

## 8. Common Environment Variables

Framework/app runtime:
- `ARLEN_APP_ROOT`
- `ARLEN_FRAMEWORK_ROOT`
- `ARLEN_HOST`
- `ARLEN_PORT`
- `ARLEN_LOG_FORMAT`
- `ARLEN_TRUSTED_PROXY`
- `ARLEN_SERVE_STATIC`
- `ARLEN_PERFORMANCE_LOGGING`
- `ARLEN_MAX_REQUEST_LINE_BYTES`
- `ARLEN_MAX_HEADER_BYTES`
- `ARLEN_MAX_BODY_BYTES`
- `ARLEN_DATABASE_URL`
- `ARLEN_DB_POOL_SIZE`
- `ARLEN_SESSION_ENABLED`
- `ARLEN_CSRF_ENABLED`
- `ARLEN_RATE_LIMIT_ENABLED`
- `ARLEN_RATE_LIMIT_REQUESTS`
- `ARLEN_RATE_LIMIT_WINDOW_SECONDS`

Legacy compatibility fallback (`MOJOOBJC_*`) is supported but should be considered transitional.

## 9. Migrations (PostgreSQL)

From an app root with `db/migrations`:

```bash
/path/to/Arlen/bin/arlen migrate --env development
```

Dry-run pending migrations:

```bash
/path/to/Arlen/bin/arlen migrate --dry-run
```

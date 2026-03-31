# Windows CLANG64 Preview

Last updated: 2026-03-31

This document records the native Windows workflow for Arlen on MSYS2
`CLANG64`.

The branch implementation now covers the full Phase 24 roadmap in code, but
live MSYS2 `CLANG64` build/test confirmation from this sandbox is still pending
because the current terminal cannot start `bash.exe` / `env.exe` successfully.

## 1. Host Entry Path

Use PowerShell as the outer launcher and MSYS2 `CLANG64` as the inner GNUstep
shell:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1
```

Run one command directly:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1 -InnerCommand "make all"
```

The checked-in wrappers are:

- `scripts/run_clang64.ps1`
- `scripts/run_clang64.sh`

## 2. Required Tools

Expected inside the active `CLANG64` environment:

- `clang`
- `make`
- `bash`
- `gnustep-config`
- `xctest`
- `openapp`
- `libdispatch`

Recommended for the wider Windows lanes:

- `python3`
- `curl`
- `pkg-config`
- `pg_config`
- `libpq`
- `libodbc` or `odbc32.dll`

`arlen doctor` checks both `ARLEN_LIBPQ_LIBRARY` / `ARLEN_ODBC_LIBRARY` and
the standard `CLANG64` DLL locations when present.

## 3. Build Contract

From the documented `CLANG64` shell:

```sh
make all
```

On Windows preview, `make all` builds:

- `build/eocc`
- `build/arlen`
- the Windows preview `libArlenFramework.a`, including the data-layer sources

Convenience alias:

```sh
make clang64-preview
```

## 4. Verification Lanes

Focused template lane:

```sh
make phase24-windows-tests
```

Focused DB transport smoke lane:

```sh
make phase24-windows-db-smoke
```

Broader Windows confidence lane:

```sh
make phase24-windows-confidence
```

PowerShell wrappers:

- `scripts/run_phase24_windows_tests.ps1`
- `scripts/run_clang64.ps1 -InnerCommand "make phase24-windows-db-smoke"`
- `scripts/run_clang64.ps1 -InnerCommand "make phase24-windows-confidence"`

Current verification note:

- As of 2026-03-31, `make phase24-windows-confidence` completed on the
  checked-in CLANG64 path in this workspace.
- The remaining Windows test-runner gap is discovery: stock `xctest` currently
  prints `XCTest: No tests found.` for the focused bundles, so the build,
  bundle, and app-root smoke are live, but true XCTest parity is not closed yet.

## 5. Supported Native Windows Surface

Supported on the current branch:

- `arlen doctor`
- `arlen config`
- `arlen new`
- `arlen generate`
- `arlen build`
- `arlen check`
- `arlen boomhauer` for app-root `--no-watch`, `--prepare-only`,
  `--print-routes`, `--once`, and direct non-watch launch
- `arlen routes`
- `arlen test --unit` as the focused Windows XCTest lane
- `arlen migrate`
- `arlen schema-codegen`
- `arlen typed-sql-codegen`
- `arlen module add/remove/list/doctor/migrate/assets/eject/upgrade`
- PostgreSQL/ODBC transport loading through the checked-in Windows DLL
  discovery contract

## 6. Explicit Native Windows Non-Support

Still intentionally unsupported:

- `jobs worker`
- `propane`
- `boomhauer` watch mode
- fallback dev error server watch-loop behavior
- Linux perf/sanitizer confidence lanes
- native Windows production process-manager support

The runtime/deployment boundary is documented in:

- `docs/WINDOWS_RUNTIME_STORY.md`

## 7. Suggested Smoke Sequence

```sh
./bin/arlen doctor
make all
make phase24-windows-tests
make phase24-windows-db-smoke
make phase24-windows-confidence
```

For app-root smoke:

```sh
./bin/arlen new MyApp
cd MyApp
/path/to/Arlen/bin/arlen boomhauer --no-watch --prepare-only
/path/to/Arlen/bin/arlen routes
```

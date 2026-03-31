# Windows CLANG64 Preview

Last updated: 2026-03-31

This document records the native Windows preview workflow for Arlen on MSYS2
`CLANG64`.

Phase 24A-H establishes a basic app/runtime preview. It is still intentionally
narrower than Linux support today.

This checkpoint reflects the branch implementation for `24A-24H`. Live MSYS2
`CLANG64` build/test confirmation from this shell is still pending because the
current sandbox cannot start `bash.exe` / `env.exe` successfully.

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

The checked-in wrappers for this workflow are:

- `scripts/run_clang64.ps1`
- `scripts/run_clang64.sh`

Both bootstrap `/clang64/share/GNUstep/Makefiles/GNUstep.sh` and prefer the
MSYS2 `CLANG64` toolchain.

## 2. Required Tools

The preview expects these commands/libraries inside the active `CLANG64`
environment:

- `clang`
- `make`
- `bash`
- `gnustep-config`
- `xctest`
- `openapp`
- `libdispatch`

Optional but recommended:

- `python3`
- `curl`
- `pkg-config`
- `pg_config`

## 3. Preview Build Contract

From the documented `CLANG64` shell, the first-pass preview build is:

```sh
make all
```

On Windows preview, `make all` currently means:

- `build/eocc`
- the reduced CLANG64 preview `libArlenFramework.a` with the basic app/server
  runtime slice
- `build/arlen`
- `build/arlen-xctest-runner`

It does not imply `build/boomhauer`, `propane`, or the full Linux verification
matrix yet.

You can also build the preview slice explicitly:

```sh
make clang64-preview
```

## 4. Focused CLI Smoke Commands

These are the intended first commands to prove the preview is alive:

```sh
./bin/arlen doctor
./bin/arlen new MyApp
cd MyApp
/path/to/Arlen/bin/arlen generate controller Home --route /
/path/to/Arlen/bin/arlen boomhauer --no-watch --prepare-only
/path/to/Arlen/bin/arlen routes
```

`arlen doctor` is the bootstrap-first preflight path. `build/arlen doctor`
should report the same toolchain contract after the CLI is built.

The focused Windows-safe XCTest lane is:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_phase24_windows_tests.ps1
```

Equivalent inner-shell command:

```sh
make phase24-windows-tests
```

## 5. Supported Preview Surface

Phase 24A-H currently targets:

- `arlen doctor`
- `arlen config`
- `arlen new`
- `arlen generate`
- `arlen build`
- `arlen boomhauer` for app-root `--no-watch`, `--prepare-only`, `--print-routes`,
  `--once`, and direct non-watch server launch
- `arlen routes`
- `arlen test` as the focused `phase24-windows-tests` lane
- `arlen typed-sql-codegen`
- `arlen module add/remove/list/doctor/assets/eject/upgrade`
- `bin/boomhauer` path normalization and generated app makefile emission for
  Windows-owned app roots
- the repo-local `build/arlen-xctest-runner` bundle runner for focused Windows
  XCTest execution

## 6. Deferred To Later Phase 24 Work

These remain intentionally deferred on native Windows at this checkpoint:

- `jobs worker`
- `propane`
- `boomhauer` watch mode and fallback dev error server
- `perf`
- `check`
- `migrate`
- `schema-codegen`
- `module migrate`
- live PostgreSQL/MSSQL validation
- full verification/CI parity
- Windows deployment/runtime-manager parity

Roadmap ownership:

- Phase `24I`: database transport parity
- Phase `24J`: filesystem/security parity
- Phase `24K`: verification/CI parity
- Phase `24L`: deployment/runtime-manager parity

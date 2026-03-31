# Windows CLANG64 Preview

Last updated: 2026-03-31

This document records the native Windows preview workflow for Arlen on MSYS2
`CLANG64`.

Phase 24A-D establishes a CLI-first preview. It is intentionally narrower than
Linux support today.

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
- the reduced CLANG64 preview `libArlenFramework.a`
- `build/arlen`

It does not imply `boomhauer`, `propane`, or the full Linux verification
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
```

`arlen doctor` is the bootstrap-first preflight path. `build/arlen doctor`
should report the same toolchain contract after the CLI is built.

## 5. Supported Preview Surface

Phase 24A-D currently targets:

- `arlen doctor`
- `arlen config`
- `arlen new`
- `arlen generate`
- `arlen build`
- `arlen typed-sql-codegen`
- `arlen module add/remove/list/doctor/assets/eject/upgrade`

## 6. Deferred To Later Phase 24 Work

These remain intentionally deferred on native Windows at this checkpoint:

- `boomhauer`
- `jobs worker`
- `propane`
- `routes`
- `test`
- `perf`
- `check`
- `migrate`
- `schema-codegen`
- `module migrate`
- HTTP runtime portability
- live PostgreSQL/MSSQL validation
- Windows deployment/runtime-manager parity

Roadmap ownership:

- Phase `24E`: Windows XCTest strategy
- Phase `24H`: `boomhauer` and app-root DX parity
- Phase `24I`: database transport parity
- Phase `24K`: verification/CI parity
- Phase `24L`: deployment/runtime-manager parity

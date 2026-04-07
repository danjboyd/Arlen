# Arlen Phase 24 Roadmap

Status: imported from branch work on 2026-04-07; first `main` reintegration pass in progress
Last updated: 2026-04-07

This roadmap tracks the selective reintegration of the Windows `CLANG64` work
developed on branch `origin/windows/clang64`.

Mainline rule:

- Do not merge the historical Windows branch wholesale.
- Forward-port additive Windows portability seams onto current `main`.
- Preserve current post-Phase-24 framework surface while broadening platform
  support incrementally.

Imported branch goals:

- native MSYS2 `CLANG64` bootstrap from PowerShell
- GNUstep path and tool discovery without Linux-only assumptions
- Windows-aware runtime seams for time, path, and process behavior
- focused Windows verification that does not depend on Linux-only CI lanes

Mainline reintegration order:

1. toolchain/bootstrap wrappers and GNUstep resolution
2. platform seam helpers
3. focused Windows-safe XCTest runner and DB loader smoke lane
4. `boomhauer` / `jobs-worker` / `propane` parity forward-ports
5. Windows CI and broader runtime verification
6. release/install/package closeout after runtime parity is real

Current mainline-delivered slice:

- CLANG64 bootstrap wrappers:
  - `scripts/run_clang64.ps1`
  - `scripts/run_clang64.sh`
- GNUstep resolver support for `/clang64/share/GNUstep/Makefiles/GNUstep.sh`
- `ALNPlatform` seam for time/process/path helpers
- `arlen-xctest-runner` helper for focused Windows-safe XCTest bundle loading
- `phase24-windows-db-smoke` focused transport loader lane

Not yet forward-ported from the historical branch:

- full Windows `boomhauer` parity
- full Windows `jobs-worker` parity
- full Windows `propane` parity
- Windows runtime parity suites from the historical branch
- Windows CI workflow and artifact publishing
- Windows release/deployment closeout

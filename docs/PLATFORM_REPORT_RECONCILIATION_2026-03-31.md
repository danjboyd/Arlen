# Platform Report Reconciliation

Date: `2026-03-31`

This note records the upstream Arlen assessment of the GNUstep bootstrap report
logged from `iep-platform` in
`/opt/platform/docs/bugs/2026-03-31-arlen-hardcoded-usr-gnustep-path.md`.

Ownership rule:

- Arlen records upstream status only.
- `platform` keeps downstream closure authority.
- Status below should be read as the upstream status/evidence trail.
  Downstream revalidation still belongs to `platform`.

## Current Upstream Assessment

| Platform report | Upstream status | Evidence |
| --- | --- | --- |
| Arlen hard-codes `/usr/GNUstep/System/Library/Makefiles/GNUstep.sh` and fails under managed GNUstep layouts | fixed in current workspace; awaiting downstream revalidation | `tools/resolve_gnustep.sh`, `tools/source_gnustep_env.sh`, `GNUmakefile`, `bin/arlen-doctor`, `bin/boomhauer`, `tools/arlen.m`, `tests/shared/ALNTestSupport.{h,m}`, `tests/unit/GNUstepResolutionTests.m`, `docs/TOOLCHAIN_MATRIX.md` |

## Notes

- Upstream reproduced the original failure in the managed-toolchain path where
  `GNUSTEP_MAKEFILES` was exported but `GNUstep.sh` did not live under
  `/usr/GNUstep`.
- Root cause:
  - the build and bootstrap path assumed one fixed GNUstep installation root in
    `GNUmakefile`, `bin/arlen-doctor`, `bin/boomhauer`, and the built `arlen`
    CLI doctor path
  - repo-side shellouts in the test harness also embedded the same
    `/usr/GNUstep` assumption
- Current upstream behavior:
  - Arlen now resolves GNUstep shell init in this order:
    `GNUSTEP_SH`, `GNUSTEP_MAKEFILES/GNUstep.sh`,
    `gnustep-config --variable=GNUSTEP_MAKEFILES`, then the historical
    `/usr/GNUstep` fallback
  - repo-local shell init now has an explicit helper:
    `tools/source_gnustep_env.sh`
  - `arlen doctor` now checks `dispatch/dispatch.h` separately so toolchains
    that still lack libdispatch headers fail early with a targeted diagnostic
    instead of surfacing later as a compile error
- Downstream revalidation should confirm the original `arlen doctor --json` and
  `make arlen` flows now succeed on `iep-platform`, or surface any remaining
  non-path issues as separate toolchain defects.

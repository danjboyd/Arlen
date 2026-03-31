# Windows Runtime Story

Last updated: 2026-03-31

This document defines the truthful native Windows runtime/deployment contract
for Arlen on the `windows/clang64` branch.

## Supported Native Windows Scope

Native Windows support is currently aimed at development and CI validation on
MSYS2 `CLANG64`.

Supported entrypoints:

- `make all`
- `make phase24-windows-tests`
- `make phase24-windows-db-smoke`
- `make phase24-windows-confidence`
- `arlen doctor`
- `arlen build`
- `arlen check`
- `arlen boomhauer --no-watch --prepare-only`
- `arlen routes`
- `arlen migrate`
- `arlen schema-codegen`
- `arlen module migrate`

## Explicit Native Windows Non-Support

These remain intentionally unsupported on native Windows:

- `propane`
- `arlen propane`
- `bin/jobs-worker`
- `arlen jobs worker`
- `boomhauer` watch mode
- the Linux/systemd deployment story

Arlen does not currently claim a supported native Windows production-manager
story. The checked-in CLI and shell entrypoints fail explicitly for those
surfaces instead of attempting a partial or misleading launch.

## Recommended Production Path

If you need supported production process management today:

- deploy Arlen on Linux
- use `propane` there
- follow `docs/DEPLOYMENT.md`, `docs/PROPANE.md`, and
  `docs/SYSTEMD_RUNBOOK.md`

Windows hosts can still participate as development machines or CI runners for
the MSYS2 `CLANG64` workflow, but native Windows production deployment is not a
supported Arlen contract yet.

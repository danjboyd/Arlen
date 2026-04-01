# Windows Runtime Story

Last updated: 2026-04-01

This document defines the truthful native Windows runtime/deployment contract
for Arlen on the `windows/clang64` branch.

## Supported Native Windows Scope

Native Windows support is currently aimed at development, CI validation, and
the checked-in runtime parity slice on MSYS2 `CLANG64`.

Supported entrypoints:

- `make all`
- `make phase24-windows-tests`
- `make phase24-windows-db-smoke`
- `make phase24-windows-runtime-tests`
- `make phase24-windows-confidence`
- `arlen doctor`
- `arlen build`
- `arlen check`
- `arlen boomhauer`
- `arlen jobs worker`
- `arlen propane`
- `arlen routes`
- `arlen migrate`
- `arlen schema-codegen`
- `arlen module migrate`

## Explicit Native Windows Non-Support

These remain intentionally incomplete or unsupported as first-class Windows
platform claims:

- the default `make test-unit` / `make test-integration` / live-backend matrix
- Linux perf/sanitizer/fault-injection confidence lanes
- Windows release/install/package closeout
- Windows service-integration guidance beyond direct `propane` usage
- the Linux/systemd deployment story

Arlen now supports the checked-in native Windows runtime entrypoints through
`boomhauer`, `jobs worker`, and `propane`, but it does not yet claim that
Windows is a fully closed-out first-class platform. That broader platform claim
remains gated on Phase `24Q-24S`.

## Recommended Production Path

If you need the most mature packaged production path today:

- Linux remains the default documented deployment target
- follow `docs/DEPLOYMENT.md`, `docs/PROPANE.md`, and
  `docs/SYSTEMD_RUNBOOK.md` there

Windows hosts can now run Arlen natively through the checked-in `CLANG64`
`propane` path, but the surrounding release/install/service story is still part
of the remaining Phase `24Q-24S` closeout work.

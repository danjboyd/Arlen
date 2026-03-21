# Structurizer Report Reconciliation

Date: `2026-03-21`

This note records the upstream Arlen assessment of the open Structurizer report
in `../Structurizer/docs/ARLEN_FEEDBACK.md`.

Ownership rule:

- Arlen records upstream status only.
- `Structurizer` keeps app-level closure authority.
- Statuses below should be read as `fixed upstream` or `awaiting downstream
  revalidation`, not as downstream closure.

## Current Upstream Assessment

| Structurizer report | Upstream status | Evidence |
| --- | --- | --- |
| local `ARLEN_FRAMEWORK_ROOT` override can reuse sanitizer-instrumented `libArlenFramework.a` and fail linking | fixed in current workspace; awaiting downstream revalidation | `bin/boomhauer`, `tests/unit/BuildPolicyTests.m`, `tests/integration/HTTPIntegrationTests.m`, `docs/CLI_REFERENCE.md` |

## Notes

- Scope is intentionally narrow: the normal vendored-submodule path was healthy.
  The reproduced failure only affected app-root `boomhauer` commands that point
  `ARLEN_FRAMEWORK_ROOT` at an external Arlen checkout with cached ASan/UBSan
  framework artifacts.
- Current upstream behavior detects sanitizer-instrumented
  `build/lib/libArlenFramework.a`, forces a clean framework rebuild before the
  app link step, and fails early with a targeted diagnostic if the rebuilt
  archive still contains sanitizer symbols.
- This note does not close the issue for `Structurizer`; downstream should
  close it only after retesting its own local-override workflow.

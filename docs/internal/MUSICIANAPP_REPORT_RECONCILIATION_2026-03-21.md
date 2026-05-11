# MusicianApp Report Reconciliation

Date: `2026-03-21`

This note records the upstream Arlen assessment of `MusicianApp` reports that
were still marked open in `../MusicianApp/docs/ARLEN_BUG_REPORT_LOG.md` during
the 2026-03-21 reconciliation pass.

Ownership rule:

- Arlen records upstream status only.
- `MusicianApp` keeps app-level closure authority.
- Statuses below should be read as historical upstream status snapshots plus the
  later downstream confirmation note; Arlen does not close issues on
  `MusicianApp`'s behalf.

## Current Upstream Assessment

| MusicianApp report | Upstream status | Evidence |
| --- | --- | --- |
| `ARLEN-BUG-001` multi-statement SQL migrations | fixed upstream | `src/Arlen/Data/ALNMigrationRunner.m`, `tests/unit/Phase17ATests.m` |
| `ARLEN-BUG-005` watch-mode build-error recovery UX | fixed in current workspace; awaiting downstream revalidation | `bin/boomhauer`, `tests/integration/HTTPIntegrationTests.m`, `docs/CLI_REFERENCE.md` |
| `ARLEN-BUG-006` disabled stub provider still rendered in UI | fixed upstream | `modules/auth/Sources/ALNAuthModule.m`, `tests/unit/Phase13ETests.m`, `tests/integration/Phase13AuthAdminIntegrationTests.m` |
| `ARLEN-BUG-008` auth action typography mismatch | fixed in current workspace; awaiting downstream revalidation | `modules/auth/Resources/Public/auth.css`, `tests/unit/Phase13ETests.m` |
| `ARLEN-FR-001` first-class auth UI integration modes | implemented upstream | `docs/AUTH_UI_INTEGRATION_MODES.md`, `docs/AUTH_MODULE.md`, `tests/integration/Phase13AuthAdminIntegrationTests.m` |
| `ARLEN-FR-002` durable notification center surface | implemented upstream | `docs/NOTIFICATIONS_MODULE.md`, `modules/notifications/Sources/ALNNotificationsModule.m` |
| `ARLEN-FR-003` first-party jobs worker runner | implemented upstream | `tools/arlen.m`, `docs/CLI_REFERENCE.md`, `docs/JOBS_MODULE.md` |
| `ARLEN-FR-004` safer module path defaults / clearer nested path config | implemented upstream | `modules/jobs/module.plist`, `modules/notifications/module.plist`, `docs/STATUS.md` |
| `ARLEN-BUG-010` `admin-ui` `legacyPath` HTML action/update parity | fixed upstream | `modules/admin-ui/Sources/ALNAdminUIModule.m`, `tests/integration/Phase16ModuleIntegrationTests.m` |
| `ARLEN-FR-005` trusted invite-claim / email-link acquisition primitive | implemented upstream | `modules/auth/Sources/ALNAuthModule.h`, `modules/auth/Sources/ALNAuthModule.m`, `docs/AUTH_MODULE.md`, `tests/unit/Phase13ETests.m` |
| `ARLEN-BUG-011` password-setup email after trusted claim | covered by supported upstream claim flow; folded into `ARLEN-FR-005` unless a current supported repro fails | `modules/auth/Sources/ALNAuthModule.h`, `tests/unit/Phase13ETests.m` |
| `ARLEN-BUG-012` build-error page not reliably served on watch failure | fixed in current workspace; awaiting downstream revalidation | `bin/boomhauer`, `tests/integration/HTTPIntegrationTests.m`, `docs/CLI_REFERENCE.md` |
| `ARLEN-FR-006` first-class MFA enrollment/challenge UX baseline | implemented upstream | `docs/PHASE18_ROADMAP.md`, `docs/AUTH_MODULE.md`, `modules/auth/Resources/Templates/mfa/`, `tests/integration/Phase13AuthAdminIntegrationTests.m` |
| `ARLEN-FR-007` stronger MFA app-integration seams for app-owned security pages | implemented upstream | `modules/auth/Sources/ALNAuthModule.h`, `docs/AUTH_MODULE.md`, `tests/integration/Phase13AuthAdminIntegrationTests.m` |

## Notes

- `ARLEN-BUG-005` and `ARLEN-BUG-012` describe the same broad watch-mode
  diagnostic/recovery area. Current Arlen workspace behavior includes
  auto-retrying the failed build while the diagnostic server remains active,
  richer error-page metadata, and JSON diagnostic output for tool-assisted
  inspection.
- `ARLEN-BUG-011` is not kept as a separate upstream bug because the supported
  public claim flow now issues the reusable password-setup email directly and is
  covered by focused unit regression.
- Downstream confirmation:
  - `MusicianApp` has since confirmed the upstream-fixed items discussed in this
    note are resolved on its own branch/config as of `2026-03-21`.
  - That includes the earlier `awaiting downstream revalidation` items in this
    table plus the later form-parameter/auth-migration fixes shipped in commit
    `16084b8`.
  - This note now serves as the upstream evidence trail for those confirmed
    downstream closures.

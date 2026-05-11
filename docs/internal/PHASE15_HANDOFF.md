# Phase 15 Handoff

Date: 2026-03-09
Status: complete
Updated: 2026-03-10

This note captured the stop point for Phase 15 (`15A-15E`) and now serves as
the closeout record.

## Current State

Implemented in code:

- `15A` auth UI mode contract and route split
- `15B` `module-ui` app-shell integration hooks
- `15C` partialized auth UI contract and override model
- `15D` `generated-app-ui` eject/scaffold workflow
- `15E` docs/examples/confidence closeout

## What Landed

### Auth runtime and route behavior

Files:

- `modules/auth/Sources/ALNAuthModule.h`
- `modules/auth/Sources/ALNAuthModule.m`

Key changes:

- added explicit auth UI modes:
  - `headless`
  - `module-ui`
  - `generated-app-ui`
- added `ALNAuthModuleUIContextHook`
- added runtime properties:
  - `uiMode`
  - `layoutTemplate`
  - `generatedPagePrefix`
- added runtime helpers for page/body/partial resolution and page-level layout
  + UI context composition
- `headless` mode suppresses module-owned interactive HTML routes while keeping
  backend/API/provider behavior active
- session payloads now expose `ui_mode`
- notification links switch to API URLs in `headless` mode

### Auth templates

Files:

- `modules/auth/Resources/Templates/layouts/main.html.eoc`
- `modules/auth/Resources/Templates/login/index.html.eoc`
- `modules/auth/Resources/Templates/register/index.html.eoc`
- `modules/auth/Resources/Templates/password/forgot.html.eoc`
- `modules/auth/Resources/Templates/password/reset.html.eoc`
- `modules/auth/Resources/Templates/mfa/totp.html.eoc`
- `modules/auth/Resources/Templates/result/index.html.eoc`
- `modules/auth/Resources/Templates/partials/...`
- `modules/auth/Resources/Public/auth.css`

Key changes:

- auth pages now render through a shared wrapper/partial contract
- added reusable partials for wrapper/message/error/form/provider/result pieces
- added page-body partials for login/register/reset/TOTP/result screens
- preserved legacy module template logical paths so existing raw app overrides do
  not regress
- `generated-app-ui` resolves app-owned page paths under `templates/auth/...`

### CLI eject workflow

File:

- `tools/arlen.m`

Key changes:

- `arlen module` usage now includes:
  - `eject auth-ui [--force] [--json]`
- added `CommandModuleEject`
- `auth-ui` ejection scaffolds:
  - app-owned auth pages under `templates/auth/...`
  - auth partials/body partials under `templates/auth/partials/...`
  - `templates/layouts/auth_generated.html.eoc`
  - `public/auth/auth.css`
- updates `config/app.plist` to:
  - `authModule.ui.mode = "generated-app-ui"`
  - `authModule.ui.layout = "layouts/auth_generated"`
  - `authModule.ui.generatedPagePrefix = "auth"`
- JSON output includes:
  - `workflow`
  - `status`
  - `target`
  - `created_files`
  - `updated_files`
  - `next_steps`

### Unit coverage

File:

- `tests/unit/Phase13ETests.m`

Key changes:

- added coverage for:
  - default UI config summary
  - generated-app-ui path resolution
  - UI context hook invocation
  - headless route suppression
  - `arlen module eject auth-ui --json`

### HTTP integration coverage

File:

- `tests/integration/Phase13AuthAdminIntegrationTests.m`

Key changes:

- added a headless-mode HTTP proof:
  - `/auth/login` and `/auth/register` are suppressed
  - `/auth/api/session` remains active and reports `ui_mode = headless`
  - `/auth/api/provider/stub/login` remains active
- added a `module-ui` HTTP proof:
  - page-level layout override via `ALNAuthModuleUIContextHook`
  - page-level context injection into the rendered auth shell
  - fine-grained `providerRow` partial override without replacing the full page

## Verification Completed

These passed before the user interrupted the turn, and again after the new
integration/docs follow-up on 2026-03-10:

- `source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && make build-tests`
- `source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && xctest build/tests/ArlenUnitTests.xctest`

Important detail:

- the `Phase13ETests` CLI eject test initially failed because it tried to build
  `arlen` from the temp app directory; that was fixed by rebuilding `build/arlen`
  from repo root first, then running the eject command inside the temp app
- the final unit run completed successfully after that fix

## Remaining Work

None. Phase 15 closeout is complete in the worktree.

## Current Worktree State

Modified:

- `README.md`
- `docs/PHASE14_ROADMAP.md`
- `docs/PHASE2_PHASE3_ROADMAP.md`
- `docs/README.md`
- `docs/STATUS.md`
- `modules/auth/Resources/Public/auth.css`
- `modules/auth/Resources/Templates/layouts/main.html.eoc`
- `modules/auth/Resources/Templates/login/index.html.eoc`
- `modules/auth/Resources/Templates/mfa/totp.html.eoc`
- `modules/auth/Resources/Templates/password/forgot.html.eoc`
- `modules/auth/Resources/Templates/password/reset.html.eoc`
- `modules/auth/Resources/Templates/register/index.html.eoc`
- `modules/auth/Resources/Templates/result/index.html.eoc`
- `modules/auth/Sources/ALNAuthModule.h`
- `modules/auth/Sources/ALNAuthModule.m`
- `tests/unit/Phase13ETests.m`
- `tools/arlen.m`

Untracked:

- `docs/AUTH_UI_INTEGRATION_MODES.md`
- `docs/PHASE15_ROADMAP.md`
- `modules/auth/Resources/Templates/partials/`

Important note:

- several docs files already had local roadmap/status edits before this turn
- do not blindly reset or discard them when finishing Phase 15

## Recommended Resume Commands

Start with:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
git status --short
xctest build/tests/ArlenUnitTests.xctest
```

Then:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
./build/arlen module
```

That should still show:

- `eject auth-ui [--force] [--json]`

After that:

1. add the targeted integration test
2. finish docs/roadmap/status updates
3. add examples
4. add `phase15-confidence`
5. rerun:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make build-tests
xctest build/tests/ArlenUnitTests.xctest
```

If the integration test lands:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
xctest build/tests/ArlenIntegrationTests.xctest
```

## Resume Objective

When work resumes, the goal is to finish `15E` and then update the roadmap/docs
so Phase 15 is recorded as complete and Phase 14D-14I becomes the next active
implementation target.

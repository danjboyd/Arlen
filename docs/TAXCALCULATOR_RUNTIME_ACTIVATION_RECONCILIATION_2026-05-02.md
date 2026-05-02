# TaxCalculator Runtime Activation Reconciliation

Date: `2026-05-02`

This note records the upstream Arlen assessment of the TaxCalculator report that
`arlen deploy release` could advance `releases/current` even when the configured
systemd restart failed non-interactively.

Ownership rule:

- Arlen records upstream status only.
- `TaxCalculator` keeps app-level closure authority.
- Downstream revalidation still belongs to `TaxCalculator` after it updates its
  vendored Arlen checkout.

## Current Upstream Assessment

| TaxCalculator report | Upstream status | Evidence |
| --- | --- | --- |
| `arlen deploy release` can activate a release without successfully restarting the configured runtime service | fixed upstream; awaiting downstream revalidation | `docs/OPEN_ISSUES.md` (`ARLEN-BUG-031`), `tools/arlen.m`, `tests/integration/DeploymentIntegrationTests.m`, `docs/DEPLOYMENT.md`, `docs/CLI_REFERENCE.md` |

## Notes

### `ARLEN-BUG-031`: Runtime Restart Failure After Activation

- Upstream accepted the production-risk class from the downstream report.
- Root cause:
  - `deploy release` switched `releases/current` before running the configured
    runtime restart/reload command
  - if the runtime command failed, the release pointer could name the new
    release while the running service continued serving the old process image
  - ordinary health probes could still pass because they validated liveness, not
    release identity
- Current upstream behavior:
  - runtime restart/reload failure reports `deploy_release_runtime_failed`
  - if a previous active release exists, Arlen restores `releases/current` to it
    and reports `deployment_state = activation_failed`
  - if restoration cannot be performed, Arlen reports
    `deployment_state = stale_runtime`
  - `deploy doctor` resolves symlinked runtime roots before deciding whether a
    `/releases/current` runtime path is benign or stale
  - deploy targets may configure non-interactive commands with
    `runtimeRestartCommand` and `runtimeReloadCommand`; CLI invocations may use
    `--runtime-restart-command` and `--runtime-reload-command`
- Regression coverage:
  - `DeploymentIntegrationTests::testArlenDeployReleaseRestoresCurrentWhenRuntimeRestartFails_ARLEN_BUG_031`

Downstream revalidation should update TaxCalculator's vendored Arlen checkout
and rerun a target release with a non-interactive runtime command, for example:

```bash
ARLEN_FRAMEWORK_ROOT="$PWD/vendor/arlen" \
vendor/arlen/bin/arlen deploy release iep-ownerconnect \
  --release-id 20260502T192507Z \
  --skip-release-certification \
  --runtime-action restart \
  --runtime-restart-command 'sudo -n systemctl restart arlen@iep-ownerconnect.service'
```

The deploy user must have sudoers/systemd authorization for the exact
non-interactive command. If that command fails, Arlen should now either restore
`current` to the previous release or explicitly report `stale_runtime`.

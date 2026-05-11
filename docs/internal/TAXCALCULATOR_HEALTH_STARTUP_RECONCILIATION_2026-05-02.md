# TaxCalculator Health Startup Reconciliation

Date: `2026-05-02`

This note records the upstream Arlen assessment of the TaxCalculator report that
`arlen deploy release` could exit nonzero when the immediate post-restart
health probe raced service startup.

Ownership rule:

- Arlen records upstream status only.
- `TaxCalculator` keeps app-level closure authority.
- Downstream revalidation still belongs to `TaxCalculator` after it updates its
  vendored Arlen checkout.

## Current Upstream Assessment

| TaxCalculator report | Upstream status | Evidence |
| --- | --- | --- |
| `arlen deploy release` exits nonzero when immediate post-restart health probe races service startup | fixed upstream; awaiting downstream revalidation | `docs/internal/OPEN_ISSUES.md` (`ARLEN-BUG-032`), `tools/arlen.m`, `tests/integration/DeploymentIntegrationTests.m`, `docs/DEPLOYMENT.md`, `docs/CLI_REFERENCE.md` |

## Notes

### `ARLEN-BUG-032`: Post-Restart Health Startup Race

- Upstream accepted the deploy UX/state-reporting issue from the downstream
  report.
- Root cause:
  - runtime restart succeeded
  - `deploy release` immediately ran one `/healthz` probe
  - the service was not yet listening, so `curl` returned connection refused
  - follow-up status and doctor passed after normal startup completed
- Current upstream behavior:
  - `deploy release` polls `/healthz` for a bounded startup window after the
    runtime action
  - default timeout is 30 seconds and default interval is 1 second
  - target config can set `healthStartupTimeoutSeconds` and
    `healthStartupIntervalSeconds`
  - CLI invocations can override with `--health-startup-timeout` and
    `--health-startup-interval`
  - if the window expires, JSON reports `deployment_state =
    activated_health_unverified`
- Regression coverage:
  - `DeploymentIntegrationTests::testArlenDeployReleaseRetriesHealthAfterRuntimeRestart_ARLEN_BUG_032`

Downstream revalidation should update TaxCalculator's vendored Arlen checkout
and rerun the target release with the normal systemd restart command. If the app
has a longer expected startup window, set:

```plist
healthStartupTimeoutSeconds = 60;
healthStartupIntervalSeconds = 1;
```

or pass:

```bash
--health-startup-timeout 60 --health-startup-interval 1
```

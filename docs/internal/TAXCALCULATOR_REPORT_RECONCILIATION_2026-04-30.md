# TaxCalculator Report Reconciliation

Date: `2026-04-30`

This note records the upstream Arlen assessment of the TaxCalculator report:

- `transport.sshOptions` ordering is not preserved for remote deploy
- `arlen deploy push` can hang when SSH exits before the upload stream is fully
  written
- `arlen deploy push --json` can hang during local release build when captured
  child output fills an `NSPipe`
- `arlen deploy init <remote-target>` creates target release directories on the
  local filesystem

Ownership rule:

- Arlen records upstream status only.
- `TaxCalculator` keeps app-level closure authority.
- Status below should be read as the upstream status/evidence trail.
  Downstream revalidation still belongs to `TaxCalculator`.

## Current Upstream Assessment

| TaxCalculator report | Upstream status | Evidence |
| --- | --- | --- |
| `sshOptions = ("-F", "/dev/null", "-oBatchMode=yes")` was reordered into an invalid SSH argv | fixed in current workspace; awaiting downstream revalidation | `docs/OPEN_ISSUES.md` (`ARLEN-BUG-025`), `tools/arlen.m`, `tests/integration/DeploymentIntegrationTests.m`, `docs/CLI_REFERENCE.md`, `docs/DEPLOYMENT.md` |
| `deploy push --json` could hang when SSH exited early during tar-stream upload | fixed in current workspace; awaiting downstream revalidation | `docs/OPEN_ISSUES.md` (`ARLEN-BUG-026`), `tools/arlen.m`, `tests/integration/DeploymentIntegrationTests.m`, `docs/CLI_REFERENCE.md`, `docs/DEPLOYMENT.md` |
| `deploy push --json` could hang before upload when a captured build child filled stdout/stderr pipes | fixed in current workspace; awaiting downstream revalidation | `docs/OPEN_ISSUES.md` (`ARLEN-BUG-027`), `tools/arlen.m`, `tests/unit/BuildPolicyTests.m`, `docs/CLI_REFERENCE.md`, `docs/DEPLOYMENT.md` |
| `deploy init <remote-target> --json` created `/srv/arlen/...` directories locally | documented current behavior; not reclassified as a transport bug in this patch | `docs/CLI_REFERENCE.md`, `docs/DEPLOYMENT.md` |

## Notes

### `ARLEN-BUG-025`: SSH Option Ordering

- Upstream accepted the failure class from the downstream report.
- Root cause:
  - Arlen parsed `transport.sshOptions` through the same helper used for
    set-like manifest arrays.
  - That helper sorted and deduplicated values.
  - SSH command arguments are positional, so `("-F", "/dev/null")` must remain
    adjacent and in manifest order.
- Current upstream behavior:
  - `transport.sshOptions` uses order-preserving normalization.
  - Empty and non-string entries are still ignored.
- Regression coverage:
  - `DeploymentIntegrationTests::testArlenDeployReleaseAndStatusOperateAgainstRemoteNamedTargetOverSSH`
  - the mocked SSH command now requires `-F` to be followed by its config path,
    so a reordered argv fails the remote deploy regression.

### `ARLEN-BUG-026`: Early SSH Exit Upload Hang

- Upstream accepted the failure class from the downstream report.
- Root cause:
  - Arlen launched SSH and `tar`, then waited for `tar` before waiting for SSH.
  - If SSH exited early, the local `tar` process could block writing archive
    bytes into the upload pipe and prevent JSON error emission.
- Current upstream behavior:
  - Arlen closes the parent process' unused pipe handles after launch.
  - Arlen monitors both upload children and terminates `tar` if SSH exits first.
  - `deploy push --json` returns `deploy_target_transport_failed` with captured
    transport output.
- Regression coverage:
  - `DeploymentIntegrationTests::testArlenDeployPushReportsRemoteUploadFailureWhenSSHExitsEarly_ARLEN_BUG_026`

### `ARLEN-BUG-027`: Shell Capture Pipe Deadlock

- Upstream accepted the failure class from the downstream report.
- Root cause:
  - `RunShellCaptureCommand()` captured stdout and stderr through `NSPipe`.
  - The parent waited for the child to exit before reading either pipe.
  - A noisy child build process could fill a pipe buffer and block in
    `pipe_w`, while Arlen waited indefinitely for process exit.
- Current upstream behavior:
  - `RunShellCaptureCommand()` writes stdout and stderr to temporary files.
  - The parent waits for process exit without depending on pipe buffer
    capacity, then reads and removes the capture files.
  - `deploy push --json` can now either complete the local build or reach the
    existing structured build-failure JSON path.
- Regression coverage:
  - `BuildPolicyTests::testArlenBuildJSONCapturesLargeChildOutputWithoutPipeDeadlock_ARLEN_BUG_027`

### Remote `deploy init`

`arlen deploy init <target>` is local host scaffolding in the current deploy
contract. It does not SSH to `transport.sshHost`. For a remote target, operators
should run it on the target host or against a filesystem path that intentionally
represents that host layout. Remote `push` and `release` then use SSH/tar only
after the target's expected init artifacts exist.

Downstream revalidation should rebuild the vendored Arlen binary in
TaxCalculator and rerun:

```bash
vendor/arlen/bin/arlen deploy push iep-ownerconnect --json --allow-missing-certification
```

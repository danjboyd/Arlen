# OwnerConnect Report Reconciliation

Date: `2026-04-17`

This note records the upstream Arlen assessment of the OwnerConnect report:

- `Arlen deploy SSH transport invokes bash -lc incorrectly for remote targets`

Ownership rule:

- Arlen records upstream status only.
- `OwnerConnect` keeps app-level closure authority.
- Status below should be read as the upstream status/evidence trail.
  Downstream revalidation still belongs to `OwnerConnect`.

## Current Upstream Assessment

| OwnerConnect report | Upstream status | Evidence |
| --- | --- | --- |
| SSH deploy push fails with `mkdir: missing operand` because remote `bash -lc` arguments are not preserved over SSH | fixed in current workspace; awaiting downstream revalidation | `tools/arlen.m`, `tests/integration/DeploymentIntegrationTests.m`, `docs/DEPLOYMENT.md`, `docs/CLI_REFERENCE.md` |

## Notes

### `ARLEN-BUG-021`: SSH Remote Command Argument Reparse

- Upstream accepted the failure class from the downstream report.
- Root cause:
  - Arlen built SSH transport commands through a local shell pipeline.
  - The remote command was appended as separate post-host words:
    `bash`, `-lc`, and the script.
  - Real SSH serializes post-host words into a remote command string, so the
    remote login shell could reparse the command as `bash -lc mkdir -p ...`.
  - `bash -lc` then executed only `mkdir`, with `-p` and the path shifted into
    positional arguments, producing `mkdir: missing operand`.
- Current upstream behavior:
  - remote SSH command execution now uses `NSTask` argv construction locally
    instead of local shell command construction
  - tar-stream upload now wires a local `tar` task directly into the SSH task
    with `NSPipe`
  - the remote side receives one intentional command string:
    `bash -lc '<remote-script>'`
- Regression coverage:
  - `DeploymentIntegrationTests::testArlenDeployReleaseAndStatusOperateAgainstRemoteNamedTargetOverSSH`
  - the mocked SSH transport now reparses post-host arguments like real SSH, so
    a split `bash -lc` invocation would fail this test
- Downstream revalidation should rebuild the vendored Arlen binary in
  OwnerConnect and rerun:
  - `vendor/Arlen/build/arlen deploy plan iep-ownerconnect --allow-missing-certification --json`
  - `vendor/Arlen/build/arlen deploy push iep-ownerconnect --allow-missing-certification --json`

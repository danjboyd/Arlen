# OwnerConnect Report Reconciliation

Date: `2026-04-17`

This note records the upstream Arlen assessment of the OwnerConnect report:

- `Arlen deploy SSH transport invokes bash -lc incorrectly for remote targets`
- `Named-target deploy release rebuilds existing release ID instead of reusing it`

Ownership rule:

- Arlen records upstream status only.
- `OwnerConnect` keeps app-level closure authority.
- Status below should be read as the upstream status/evidence trail.
  Downstream revalidation still belongs to `OwnerConnect`.

## Current Upstream Assessment

| OwnerConnect report | Upstream status | Evidence |
| --- | --- | --- |
| SSH deploy push fails with `mkdir: missing operand` because remote `bash -lc` arguments are not preserved over SSH | fixed in current workspace; awaiting downstream revalidation | `tools/arlen.m`, `tests/integration/DeploymentIntegrationTests.m`, `docs/DEPLOYMENT.md`, `docs/CLI_REFERENCE.md` |
| `arlen deploy release <target> --release-id <existing-id>` rebuilds an existing local release and fails with `release_exists` | fixed in Phase 36D; awaiting downstream revalidation | `docs/OPEN_ISSUES.md` (`ARLEN-BUG-022`), `tools/arlen.m`, `tests/integration/DeploymentIntegrationTests.m` |

## Notes

### `ARLEN-BUG-022`: Named-Target Release Reuse Regression

- Upstream accepted the failure class from the downstream report.
- Reproduction context:
  - `OwnerConnect` vendored Arlen in `vendor/Arlen` as of the `2026-04-17`
    deployment.
  - CLI reported deploy contract version `phase7g-agent-dx-contracts-v1`.
  - Deploy manifests reported `phase32-deploy-manifest-v1`.
- Reported flow:
  - `vendor/Arlen/build/arlen deploy push iep-ownerconnect --allow-missing-certification --json`
  - returned release ID `20260417T213058Z`
  - `vendor/Arlen/build/arlen deploy release iep-ownerconnect --release-id 20260417T213058Z --allow-missing-certification --json`
- Actual result:
  - named-target release attempted to run `build_release.sh` for the same local
    release ID before remote activation
  - `build_release.sh` failed with `release_exists` because
    `build/deploy/targets/iep-ownerconnect/local-releases/20260417T213058Z`
    already existed
- Expected result:
  - named-target `deploy release --release-id` should reuse the existing
    artifact when present, upload or reuse the remote artifact as needed, and
    activate the selected release on the remote host
- Downstream workaround used:
  - ran `vendor/Arlen/build/arlen deploy release iep-ownerconnect --allow-missing-certification --json`
    without `--release-id`
  - Arlen created, uploaded, and activated fresh release `20260417T213200Z`
- Proposed upstream regression:
  - `deploy push <target> --release-id X`
  - `deploy release <target> --release-id X`
  - assert release `X` is activated without a `release_exists` failure

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

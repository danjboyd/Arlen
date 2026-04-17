# Open Issues

## ISSUE-002: Named-target deploy release rebuilds existing release ID instead of reusing it

- Status: `open`
- Priority: `high`
- Tracking ID: `ARLEN-BUG-022`
- Discovered: `2026-04-17`
- Target follow-up: next deployment bugfix pass
- Last updated: `2026-04-17`

### Summary

For named remote targets, `arlen deploy release <target> --release-id <existing-id>`
attempts to run `tools/deploy/build_release.sh` for the selected local release
ID before remote activation. If that release artifact was already built by
`arlen deploy push <target> --release-id <id>` or by a prior push flow, the
local release directory already exists and `build_release.sh` fails with
`release_exists`.

This contradicts the documented `arlen deploy release` contract, where a
selected `--release-id` should reuse an existing release artifact, or build it
only when missing.

### Repro context (reported)

- Downstream app: `OwnerConnect`
- Vendored Arlen path: `vendor/Arlen`
- Report date: `2026-04-17`
- CLI deploy contract version: `phase7g-agent-dx-contracts-v1`
- Deploy manifest version: `phase32-deploy-manifest-v1`
- Likely area: `tools/arlen.m`, named target remote release path

### Reproduction steps

1. Build and upload a named-target release:

   ```bash
   vendor/Arlen/build/arlen deploy push iep-ownerconnect --allow-missing-certification --json
   ```

2. Note the returned release ID, for example `20260417T213058Z`.

3. Attempt to activate the already-built and uploaded release:

   ```bash
   vendor/Arlen/build/arlen deploy release iep-ownerconnect --release-id 20260417T213058Z --allow-missing-certification --json
   ```

### Expected behavior

For a named remote target, `arlen deploy release <target> --release-id <id>`
should reuse the existing local release artifact when present, upload or reuse
the corresponding remote artifact as needed, and activate that release on the
remote host through the packaged remote `arlen deploy release`.

### Actual behavior

The named-target command attempts to rebuild the same local release ID before
remote activation. Because the local release directory already exists, the build
step fails with:

```json
{
  "code": "release_exists",
  "message": "release already exists: /home/danboyd/git/OwnerConnect/build/deploy/targets/iep-ownerconnect/local-releases/20260417T213058Z"
}
```

### Impact

The intended push-then-release workflow cannot activate a specific already
pushed release ID through the named-target command. During the `2026-04-17`
OwnerConnect deployment, this blocked activation of pushed release
`20260417T213058Z`.

### Workaround used downstream

No Arlen code was changed locally in `OwnerConnect`. The deployment used:

```bash
vendor/Arlen/build/arlen deploy release iep-ownerconnect --allow-missing-certification --json
```

without `--release-id`, allowing Arlen to create, upload, and activate a fresh
release ID: `20260417T213200Z`.

### Suggested upstream fix

In the named-target deploy release path, check whether the selected local
release directory exists before invoking `build_release.sh`, matching the
non-remote release reuse behavior. If the artifact exists, skip the local build
step, upload or reuse the remote artifact as needed, and delegate activation to
the packaged remote `arlen deploy release`.

Regression coverage should include:

1. `arlen deploy push <target> --release-id X`
2. `arlen deploy release <target> --release-id X`
3. Expected result: no `release_exists` failure; release `X` is activated.

## ISSUE-001: Worker crash under normal HTTP traffic (`malloc_consolidate` / intermittent `502`)

- Status: `resolved`
- Priority: `critical`
- GitHub: https://github.com/danjboyd/Arlen/issues/1
- Last updated: `2026-02-25`

### Summary

Under normal API traffic behind nginx + `propane` (with `propane accessories` worker count > 1), workers intermittently abort with:

- `malloc_consolidate(): unaligned fastbin chunk detected`
- worker exit status `134` (and occasional segfaults observed in process lifecycle)

Externally this presents as intermittent or sustained `502 Bad Gateway` from nginx (`upstream prematurely closed connection`).

### Known-good / known-bad

- Known-good: `3876cd8481ba74b5812e52011b3bd9bf3bb80b0b`
- Known-bad: `08ea39abccd0` (still reproducible after timestamp formatter hardening)

### Repro context (reported)

- Host: `iep-softwaredev`
- OS: Debian 13 (trixie)
- Kernel: `6.12.73+deb13-amd64`
- Compiler: clang 19.1.7
- Runtime: nginx -> `propane` -> Arlen workers
- Traffic examples:
  - `/v1/states/OK/dockets/CD_2025-002412/documents/{document_id}/pdf`
  - `/v1/states/OK/dockets/CD_2025-002412/documents`

### Resolution summary

- Fix commit: `0920889` (`fix(http): stabilize serialized dispatch connection lifecycle`)
- Final fix behavior in serialized mode:
  - force one request per HTTP connection (`Connection: close`)
  - disable detached per-connection background thread handling
  - preserve explicit serialized behavior as opt-in (`requestDispatchMode=serialized`)
- Regression coverage:
  - `HTTPIntegrationTests::testProductionSerializedDispatchClosesHTTPConnections`
  - existing production serialization/concurrent-override tests remained passing

### Verification evidence

- Live consumer validation (StateCompulsoryPoolingAPI, production-like traffic on `iep-softwaredev`) confirmed issue resolved after upgrading to `0920889`.
- Arlen CI/local validation remained green after patch:
  - unit suite
  - integration suite
  - postgres integration suite

### Post-resolution watchpoints

1. Keep serialized-mode connection lifecycle deterministic when explicitly configured.
2. Require integration coverage for any future changes to HTTP connection persistence + worker dispatch interaction.
3. Re-run ASAN/UBSAN + endpoint traffic smoke during future runtime concurrency refactors.
4. Keep `tools/ci/run_runtime_concurrency_gate.sh` in pre-merge validation for HTTP/runtime lifecycle changes.
5. Track/update concurrency hardening baselines in `docs/CONCURRENCY_AUDIT_2026-02-25.md`.

# Platform Runner Runbook

Last updated: 2026-04-20

This runbook defines the platform-runner contract for the non-required
Apple and Windows confidence lanes.

The authoritative merge gate remains:

- `linux-quality / quality-gate`
- `linux-sanitizers / sanitizer-gate`
- `docs-quality / docs-gate`

`apple-baseline` and `windows-preview` stay visible and non-required under the
current support statement.

## Windows Preview Runner

Purpose:

- run `.github/workflows/windows-preview.yml`
- validate MSYS2 `CLANG64` runtime parity through
  `tools/ci/run_phase24_windows_preview.sh`
- validate packaged release/deploy parity through `make phase31-confidence`

Required GitHub Actions labels:

- `self-hosted`
- `Windows`
- `X64`
- `arlen`
- `msys2-clang64`

Provisioning source:

- Arlen pins `gnustep-cli-new` as `vendor/gnustep-cli-new`
- the pinned checkout is the source of truth for the MSYS2 `CLANG64` GNUstep
  managed-toolchain manifests, Windows bootstrap helpers, and Windows
  validation contracts used by this runner family
- the pinned vendor revision is
  `5b83862fc81968d3614ebc2d92301a56354d7c15`

Provisioning shape:

1. Provision a Windows `windows-2022` host through OracleTestVMs or an
   equivalent LAN VM lease.
2. Use the pinned `vendor/gnustep-cli-new` contract to install or validate the
   managed MSYS2 `CLANG64` GNUstep toolchain.
3. Confirm the managed Windows activation helpers expose the expected GNUstep
   environment.
4. Register the GitHub Actions runner with the labels listed above.
5. Run `windows-preview` manually before trusting the runner for routine
   non-blocking signal.

Expected tools inside the active `CLANG64` environment:

- `clang`
- `make`
- `bash`
- `gnustep-config`
- `xctest`
- `python3`
- `curl`
- `pkg-config`

Validation commands:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1 -InnerCommand "clang --version"
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1 -InnerCommand "gnustep-config --objc-flags"
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1 -InnerCommand "xctest --help"
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1 -InnerCommand "bash ./tools/ci/run_phase24_windows_preview.sh"
powershell -ExecutionPolicy Bypass -File scripts\run_clang64.ps1 -InnerCommand "make phase31-confidence"
```

Workflow contract:

- `.github/workflows/windows-preview.yml` must keep `submodules: recursive`
- the job must run on `[self-hosted, Windows, X64, arlen, msys2-clang64]`
- failure artifacts must include `build/phase24`, `build/release_confidence/phase31`,
  and `build/tests`
- the workflow remains non-required until the Windows support statement is
  deliberately promoted

The first operational target is a dedicated or long-lived LAN runner. Ephemeral
lease-backed registration and teardown are valid follow-up work, but are not
required for current platform-runner support.

## Apple Baseline Runner

Current implementation:

- `.github/workflows/apple-baseline.yml` runs on GitHub-hosted `macos-15`
- the workflow selects full Xcode explicitly
- the workflow runs `tools/ci/run_apple_baseline_confidence.sh`
- the workflow remains non-required

OracleTestVMs direction:

- Apple should move to an OracleTestVMs-provisioned macOS VM only after that
  provider path is available and stable enough to operate without one-off host
  state
- the future OracleTestVMs macOS runner must preserve the full-Xcode
  and XCTest contract
- until then, GitHub-hosted `macos-15` is the documented Apple baseline runner
  path

Required future self-hosted labels, if Apple moves to OracleTestVMs:

- `self-hosted`
- `macOS`
- `ARM64` or `X64`, matching the provisioned host
- `arlen`
- `apple-baseline`

## GitHub Runner Token Handling

Registration tokens are short-lived credentials and must not be committed,
logged, or stored in Arlen docs. Operators should retrieve runner registration
tokens from GitHub at setup time, register the runner, and then let the token
expire.

For long-lived LAN runners:

- store the runner service under a dedicated OS account when practical
- keep runner working directories outside the Arlen checkout
- update labels deliberately when the runner role changes
- remove stale offline runners from GitHub settings

For future ephemeral runners:

- create the VM lease
- register the runner with a short-lived token
- run the intended workflow
- remove the runner registration before destroying the lease

## Package Manager Boundary

`gnustep-cli-new` is planned to include package-manager support, and a future
distribution path may allow:

```sh
gnustep install arlen
```

That package-manager path is not part of the current runner contract, which only requires a
reproducible platform-runner provisioning contract. Arlen package publication
through `gnustep-cli-new` belongs to a later distribution or release-management
phase.

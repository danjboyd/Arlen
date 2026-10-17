# Release Process

This document defines Arlen release lifecycle operations.

## 1. Versioning Policy

Arlen uses semantic versioning:

- `MAJOR`: breaking API/runtime contract changes
- `MINOR`: additive features, non-breaking behavior additions
- `PATCH`: bug fixes and implementation-only hardening

ArlenData (`src/Arlen/Data` + `src/ArlenData`) follows the same semantic-versioning policy.
Data-layer release details live in `docs/ARLEN_DATA.md`.

While Arlen is on `0.x`, minor releases may still change public API; such
changes are called out in the release notes with migration guidance.

The framework version lives in `ALNModuleSystemFrameworkVersion`
(`src/Arlen/Core/ALNModuleSystem.m`). It always names the latest released
version: bump it only in the release commit, never between releases.

## 2. Deprecation Lifecycle

Deprecations are explicit and time-bounded:

1. Introduce deprecation notice in docs + changelog.
2. Keep compatibility through at least one minor release.
3. Emit development-facing warnings where practical.
4. Remove only in next major release.

### SQL Transitional APIs

For SQL/data-layer transitional SQL APIs:

- Keep compatibility through at least two minor releases.
- Publish replacement migration snippets in `docs/internal/SQL_BUILDER_PHASE4_MIGRATION.md`.
- Track active transitional API status in `docs/STATUS.md`.
- Permit removals only at a major release boundary.

## 3. Release Checklist

Run from repository root:

```bash
make ci-release-certification
```

`make ci-release-certification` executes the release checklist gates and generates the
Certification pack under:

- `build/release_confidence/phase9j/`

Upstream evidence included by this pack:

- `build/release_confidence/phase5e/`
- `build/release_confidence/phase9h/`
- `build/release_confidence/phase9i/`

If you need to run checklist gates individually:

```bash
make ci-quality
bash ./tools/ci/run_phase5e_sanitizers.sh
make ci-fault-injection
make deploy-smoke
make docs-html
```

Then execute artifact flow:

```bash
tools/deploy/build_release.sh \
  --app-root /path/to/app \
  --framework-root /path/to/Arlen \
  --releases-dir /path/to/app/releases \
  --certification-manifest /path/to/Arlen/build/release_confidence/phase9j/manifest.json
```

Validate activation + rollback:

```bash
tools/deploy/activate_release.sh --releases-dir /path/to/app/releases --release-id <id>
tools/deploy/rollback_release.sh --releases-dir /path/to/app/releases --release-id <previous-id>
```

Release notes must include a link to:

- `docs/KNOWN_RISK_REGISTER.md`

### Cutting a Release

1. On a branch, rename `## Unreleased` in `docs/RELEASE_NOTES.md` to
   `## X.Y.Z — YYYY-MM-DD`, add a fresh `## Unreleased` section above it, and
   set `ALNModuleSystemFrameworkVersion` to `X.Y.Z`.
2. Run `python3 tools/ci/check_release_version.py --repo-root .` (also part of
   `make ci-docs`) and `make ci-release-certification`.
3. Merge through the normal required checks.
4. Tag the merge commit and publish the GitHub release, using the release-notes
   section as the body:

   ```bash
   git tag -a vX.Y.Z -m "Arlen X.Y.Z"
   git push origin vX.Y.Z
   gh release create vX.Y.Z --verify-tag --title "Arlen X.Y.Z" --notes-file <notes.md>
   ```

Publishing the release triggers two workflows. Each first rejects a tag that
does not match `ALNModuleSystemFrameworkVersion`:

- `release-certification` runs the certification pack on Linux. Its
  `release-certification / windows` job builds the Windows zip on the Windows
  runner, installs it with `tools/install.ps1`, and runs `arlen new`, the app
  build (`arlen boomhauer --prepare-only`) and a `boomhauer` smoke through the
  installed `arlen.cmd` launcher
  (`tools/ci/run_windows_release_certification.ps1`).
- `release-assets` builds the downloadable archives, smoke-tests an install
  from each one, and attaches them to the release:
  - `arlen-X.Y.Z.tar.gz`: the source tree plus vendored `tools-xctest`. It is
    used on Linux, where `install.sh` builds it once.
  - `arlen-X.Y.Z-macos-arm64.tar.gz`: prebuilt Apple framework tools.
  - `arlen-X.Y.Z-windows-x64.zip`: prebuilt framework tools and library for
    the gnustep-cli managed MSYS2 `CLANG64` toolchain, plus the DLLs that
    toolchain lacks (`build/dll/libpq.dll`, pinned per toolchain in
    `tools/release/windows_bundled_dlls.txt`). `.arlen-dist` records the
    toolchain version and artifact checksum, and `install.ps1` refuses a
    different toolchain version.
  - `install.sh`, `install.ps1` and `SHA256SUMS`.

  The README's install commands,
  `curl -fsSL https://github.com/danjboyd/Arlen/releases/latest/download/install.sh | bash`
  and `irm https://github.com/danjboyd/Arlen/releases/latest/download/install.ps1 | iex`,
  depend on these assets. After publishing, confirm that the release page
  lists all six files. To rebuild them, run `release-assets` with
  `workflow_dispatch`, giving the `tag` and `upload: true`.

To build or test the archives locally:

```bash
tools/release/package_framework.sh --version X.Y.Z --kind source --out build/release-assets
tools/release/smoke_install.sh build/release-assets/arlen-X.Y.Z.tar.gz
```

On Windows, inside the gnustep-cli `CLANG64` shell (`scripts\run_clang64.ps1`):

```bash
tools/release/package_framework.sh --version X.Y.Z --kind windows-x64 --out build/release-assets
tools/release/smoke_windows_archive.sh build/release-assets/arlen-X.Y.Z-windows-x64.zip
```

Then, from PowerShell, certify the installed path:

```powershell
powershell -ExecutionPolicy Bypass -File tools\ci\run_windows_release_certification.ps1 -Archive build\release-assets\arlen-X.Y.Z-windows-x64.zip
```

When gnustep-cli publishes a new Windows toolchain, add a section for it to
`tools/release/windows_bundled_dlls.txt` (packaging fails closed on a toolchain
the list doesn't name).

## 4. Perf Trend Artifacts

Each perf run archives report history per profile under:

- `build/perf/history/<profile>/`

Trend outputs are generated on every run:

- `build/perf/latest_trend.json`
- `build/perf/latest_trend.md`

CI uploads `build/perf/` and profile baselines as release-quality artifacts.

## 5. Branch Protection (Manual Repo Setting)

GitHub branch protection is configured in repository settings, not in-tree.
For `main`, require these status checks before merge:

- `linux-quality / quality-gate`
- `linux-sanitizers / sanitizer-gate`
- `docs-quality / docs-gate`

Keep these visible but non-required unless the support statement changes:

- `apple-baseline / apple-baseline`
- `windows-preview / windows-preview`
- `release-certification / release-certification`
- `release-certification / windows`
- `release-assets / *`

## 6. Release Workflow

Release certification is intentionally isolated from the merge gate.

GitHub Actions release entrypoints (both jobs of one workflow):

- `release-certification / release-certification` (Linux certification pack)
- `release-certification / windows` (Windows zip install, `arlen new`, app
  build and `boomhauer` smoke)

That workflow is triggered on published releases and can also be run manually
with `workflow_dispatch` when release evidence needs to be regenerated without
changing the merge-gate workflow contract. A manual run takes a `lane` input
(`all`, `linux` or `windows`) so one platform's evidence can be regenerated
without occupying the other runner:

```bash
gh workflow run release-certification.yml --ref <branch> -f lane=windows
```

For changes to HTTP/data client contracts, retain the existing required Linux
quality, sanitizer, and docs check names. Verify the Apple confidence job's
`client_data_regressions.log` as well: it exercises received HTTP metadata,
redirect boundaries, retry policies, and microsecond round trips on Apple
Foundation. Its PostgreSQL database is disposable; no provider writes are used.

The required `linux-quality / quality-gate` includes the isolated PostgreSQL
regression step (`tools/ci/run_postgres_regressions.sh`). Release validation must
include its generated-client, migration, search, and repeated server cleanup
coverage. No additional branch-protection check name is needed for this step.

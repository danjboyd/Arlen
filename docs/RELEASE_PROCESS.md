# Release Process

This document defines Arlen release lifecycle operations through Phase 9J.

## 1. Versioning Policy

Arlen uses semantic versioning:

- `MAJOR`: breaking API/runtime contract changes
- `MINOR`: additive features, non-breaking behavior additions
- `PATCH`: bug fixes and implementation-only hardening

ArlenData (`src/Arlen/Data` + `src/ArlenData`) follows the same semantic-versioning policy.
Data-layer release details live in `docs/ARLEN_DATA.md`.

## 2. Deprecation Lifecycle

Deprecations are explicit and time-bounded:

1. Introduce deprecation notice in docs + changelog.
2. Keep compatibility through at least one minor release.
3. Emit development-facing warnings where practical.
4. Remove only in next major release.

### Phase 4 Transitional APIs (4A-4D)

For SQL/data-layer transitional APIs introduced in Phase 4:

- Keep compatibility through at least two 4.x minor releases.
- Publish replacement migration snippets in `docs/SQL_BUILDER_PHASE4_MIGRATION.md`.
- Track active transitional API status in `docs/STATUS.md`.
- Permit removals only at a major release boundary.

## 3. Release Checklist

Run from repository root:

```bash
make ci-release-certification
```

`make ci-release-certification` executes the release checklist gates and generates the
Phase 9J certification pack under:

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

## 6. Release Workflow

Release certification is intentionally isolated from the merge gate.

GitHub Actions release entrypoint:

- `release-certification / release-certification`

That workflow is triggered on published releases and can also be run manually
with `workflow_dispatch` when release evidence needs to be regenerated without
changing the merge-gate workflow contract.

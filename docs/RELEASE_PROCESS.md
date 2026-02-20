# Release Process

This document defines Arlen release lifecycle operations for Phase 3C.

## 1. Versioning Policy

Arlen uses semantic versioning:

- `MAJOR`: breaking API/runtime contract changes
- `MINOR`: additive features, non-breaking behavior additions
- `PATCH`: bug fixes and implementation-only hardening

## 2. Deprecation Lifecycle

Deprecations are explicit and time-bounded:

1. Introduce deprecation notice in docs + changelog.
2. Keep compatibility through at least one minor release.
3. Emit development-facing warnings where practical.
4. Remove only in next major release.

## 3. Release Checklist

Run from repository root:

```bash
make ci-quality
make deploy-smoke
make docs-html
```

Then execute artifact flow:

```bash
tools/deploy/build_release.sh \
  --app-root /path/to/app \
  --framework-root /path/to/Arlen \
  --releases-dir /path/to/app/releases
```

Validate activation + rollback:

```bash
tools/deploy/activate_release.sh --releases-dir /path/to/app/releases --release-id <id>
tools/deploy/rollback_release.sh --releases-dir /path/to/app/releases --release-id <previous-id>
```

## 4. Perf Trend Artifacts

Each perf run archives report history per profile under:

- `build/perf/history/<profile>/`

Trend outputs are generated on every run:

- `build/perf/latest_trend.json`
- `build/perf/latest_trend.md`

CI uploads `build/perf/` and profile baselines as release-quality artifacts.

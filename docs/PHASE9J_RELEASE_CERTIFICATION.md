# Phase 9J Enterprise Release Certification

Phase 9J defines the release-candidate certification contract for Arlen.

## 1. One-Command Certification

Run the full release certification workflow:

```bash
make ci-release-certification
```

Equivalent script entrypoint:

```bash
bash ./tools/ci/run_phase9j_release_certification.sh
```

By default this workflow runs:

- `tools/ci/run_phase5e_quality.sh`
- `tools/ci/run_phase5e_sanitizers.sh`
- `tools/deploy/smoke_release.sh`
- `tools/build_docs_html.sh`
- `tools/ci/generate_phase9j_release_certification_pack.py`

## 2. Artifact Pack

Certification artifacts are generated under:

- `build/release_confidence/phase9j/`

Artifacts:

- `manifest.json`
- `certification_summary.json`
- `release_gate_matrix.json`
- `known_risk_register_snapshot.json`
- `phase9j_release_certification.md`

## 3. Blocking Thresholds and Fail Criteria

Threshold source:

- `tests/fixtures/release/phase9j_certification_thresholds.json`

Release certification is marked incomplete when any blocking criterion fails:

- Phase 5E confidence manifest missing/invalid
- Phase 9H blocking sanitizer lane not allowed
- Phase 9I fault matrix exceeds failure threshold or required seam coverage is missing
- known-risk register is stale, malformed, overdue, or missing active owner/target date fields

Known-risk register source:

- `tests/fixtures/release/phase9j_known_risks.json`
- mirrored as operator-facing doc: `docs/KNOWN_RISK_REGISTER.md`

## 4. Release Script Enforcement

`tools/deploy/build_release.sh` now enforces a valid certification manifest by default.

Default manifest path:

- `build/release_confidence/phase9j/manifest.json`

Non-RC opt-out (for local smoke workflows only):

```bash
tools/deploy/build_release.sh --allow-missing-certification ...
```

Override manifest path:

```bash
tools/deploy/build_release.sh --certification-manifest /path/to/manifest.json ...
```

A release candidate without a certified Phase 9J manifest is considered incomplete.

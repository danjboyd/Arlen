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

The workflow starts from `make clean`. Unit-test regressions that execute Arlen
tools therefore must declare those tools in the build graph; `make test-unit`
builds `build/arlen` before running the unit bundle so CLI JSON regressions do
not depend on stale artifacts from a previous lane.

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

Non-RC opt-out (for explicit app iteration or local smoke workflows only):

```bash
tools/deploy/build_release.sh --skip-release-certification ...
tools/deploy/build_release.sh --dev ...
```

`--allow-missing-certification` remains supported as the compatibility spelling.

Override manifest path:

```bash
tools/deploy/build_release.sh --certification-manifest /path/to/manifest.json ...
```

A release candidate without a certified Phase 9J manifest is considered incomplete.

Non-release-candidate app iteration can explicitly waive certification with
`arlen deploy push --skip-release-certification` or `arlen deploy push --dev`.
That path records waived certification metadata and is not a certified Phase 9J
release candidate.

## 5. Downstream Blocker Triage

When a downstream app reports a Phase 9J blocker, Arlen records upstream status
separately from app closure. The expected upstream response is:

- add or update the bug-ledger entry in `docs/internal/OPEN_ISSUES.md`
- preserve the downstream ownership split in a reconciliation note
- fix the Arlen build/test/release contract rather than bypassing the Phase 9J
  manifest requirement
- verify the clean path with `make clean`, focused regression coverage, and
  `make ci-release-certification`

# Documentation Policy

This policy defines how Arlen documentation stays first-rate and current.

## 1. Principle

Documentation is a product feature, not an afterthought.

A feature is not done until its user-facing behavior is documented.

New-developer success is a primary requirement: documentation should let a developer scaffold and run a first app without guesswork.

## 2. Documentation Definition of Done

Every feature or behavior change should include updates to all affected docs:

1. User-facing guide/reference updates
2. API reference updates when public headers change
3. Spec/roadmap updates when scope or contract changes
4. Example updates when developer workflows change
5. Migration notes when behavior changes incompatibly

## 3. Required Update Targets

When applicable, update:

- `README.md`
- `docs/README.md`
- `docs/GETTING_STARTED.md`
- `docs/CLI_REFERENCE.md`
- `docs/API_REFERENCE.md` and generated pages under `docs/api/` when public API changes
- relevant spec (`docs/PHASE1_SPEC.md`, `V1_SPEC.md`, etc.)
- roadmap docs if milestone/scope changed

## 4. Writing Standards

- Prefer concrete examples over abstract prose.
- Document defaults before advanced customization.
- Include exact command lines and expected behavior.
- Avoid promising features that are not implemented.
- Use Objective-C/GNUstep terminology consistently.

## 5. Accuracy Rules

- Docs must reflect the current shipped behavior in repository code.
- If behavior is planned but not implemented, label clearly as planned.
- Remove or mark stale guidance immediately when behavior changes.

## 6. Upstream vs. Downstream Issue Ownership

Arlen is an upstream framework and may receive bug reports or feature requests
from downstream apps such as `MusicianApp`.

Documentation should preserve that ownership split:

- Arlen docs record upstream truth:
  - report received
  - reproduced or not reproduced upstream
  - fix landed or not landed upstream
  - commit/date/test evidence
  - whether downstream revalidation is still pending
- Downstream app docs record downstream truth:
  - app impact
  - app workaround
  - app rollout decision
  - app-level revalidation
  - final downstream closure
- Upstream should not mark a downstream app issue fully closed on the app's
  behalf unless the downstream repo has explicitly revalidated and adopted that
  closure.
- Preferred upstream statuses for downstream-reported issues are:
  - `fixed upstream`
  - `not reproduced upstream`
  - `awaiting downstream revalidation`
- When cross-linking between repos, link the related report/fix rather than
  duplicating ownership. Each repo should keep its own status language.

## 7. Review Checklist for Documentation Changes

1. Is the first-time developer path still clear?
2. Are commands copy/paste runnable?
3. Are environment variables and defaults accurate?
4. Are cross-links to specs/roadmaps correct?
5. Are examples aligned with current APIs (`ALN*` primary, legacy aliases called out as compatibility only)?
6. Can a new developer reach "first running app" by following `docs/FIRST_APP_GUIDE.md` exactly?
7. If public headers changed, were API docs regenerated with `python3 tools/docs/generate_api_reference.py`?
8. Did the docs quality gate pass (`make ci-docs`)?
9. If comparative benchmark contract fixtures changed, do `tests/fixtures/benchmarking/*` and `docs/COMPARATIVE_BENCHMARKING.md` still describe the same source-of-truth split?
10. If the change references a downstream-reported issue, does the wording keep upstream and downstream closure ownership distinct?

## 8. Browser Docs Build Check

When documentation content changes, run:

```bash
make docs-api
make docs-html
make ci-docs
```

Validate that:
- `build/docs/index.html` loads correctly
- primary navigation links resolve
- newly added pages are rendered
- API reference pages under `build/docs/docs/api/` render and link correctly
- generated API reference markdown (`docs/API_REFERENCE.md` + `docs/api/*.md`) is up to date with no uncommitted generator diff
- imported comparative benchmark contract fixtures remain consistent with `docs/COMPARATIVE_BENCHMARKING.md`

Automated gate entrypoint:

```bash
bash ./tools/ci/run_docs_quality.sh
```

This command is CI-enforced and is the source of truth for docs quality pass/fail.
It also validates roadmap/status summary consistency across `README.md`,
`docs/STATUS.md`, and the historical aggregate/index docs.

## 9. Ongoing Maintenance Cadence

- Update docs in the same change set as feature code whenever possible.
- Run periodic docs audits at phase boundaries.
- Track major doc gaps as roadmap work items, not informal notes.

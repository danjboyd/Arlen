# Documentation Policy

This policy defines how Arlen documentation stays first-rate and current.

## 1. Principle

Documentation is a product feature, not an afterthought.

A feature is not done until its user-facing behavior is documented.

## 2. Documentation Definition of Done

Every feature or behavior change should include updates to all affected docs:

1. User-facing guide/reference updates
2. Spec/roadmap updates when scope or contract changes
3. Example updates when developer workflows change
4. Migration notes when behavior changes incompatibly

## 3. Required Update Targets

When applicable, update:

- `README.md`
- `docs/README.md`
- `docs/GETTING_STARTED.md`
- `docs/CLI_REFERENCE.md`
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

## 6. Review Checklist for Documentation Changes

1. Is the first-time developer path still clear?
2. Are commands copy/paste runnable?
3. Are environment variables and defaults accurate?
4. Are cross-links to specs/roadmaps correct?
5. Are examples aligned with current APIs (`ALN*` primary, legacy aliases called out as compatibility only)?

## 7. Browser Docs Build Check

When documentation content changes, run:

```bash
make docs-html
```

Validate that:
- `build/docs/index.html` loads correctly
- primary navigation links resolve
- newly added pages are rendered

## 8. Ongoing Maintenance Cadence

- Update docs in the same change set as feature code whenever possible.
- Run periodic docs audits at phase boundaries.
- Track major doc gaps as roadmap work items, not informal notes.

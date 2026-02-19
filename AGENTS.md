# AGENTS.md

## Project Mission

Build a GNUstep-native Objective-C web toolkit inspired by Mojolicious, starting with an EOC (`.html.eoc`) template engine that transpiles templates into Objective-C.

## Current Stage

This repository is in early scaffold stage. Priority is delivering a stable v1 template compiler and runtime support.

## Naming Conventions

- Development server codename: `boomhauer`.
- Planned production server manager codename: `propane`.
- All `propane` settings must be referred to as "propane accessories".

## Expected Workflow

- Read `V1_SPEC.md` before changing template syntax or compiler behavior.
- Keep changes incremental and verifiable.
- Prefer deterministic behavior over convenience shortcuts.
- Preserve compatibility with GNUstep build tooling.

## Repository Layout

- `src/Arlen/`: library source code.
- `src/Arlen/MVC/Template/`: template transpiler/runtime components.
- `templates/`: application templates (`.html.eoc`) for examples/tests.
- `tests/unit/`: unit tests for parser/transpiler/runtime helpers.
- `tests/integration/`: end-to-end rendering and framework behavior tests.
- `tests/fixtures/templates/`: fixture inputs/expected outputs for transpiler tests.
- `tools/`: helper scripts and CLI tools (template compiler, build helpers).
- `examples/basic_app/`: minimal end-to-end example application.
- `docs/`: design notes and additional specifications.

## Coding Guidelines

- Use Objective-C with GNUstep/Foundation compatibility.
- Keep a default-first developer experience: common app flows should work with minimal configuration and minimal boilerplate.
- Prefer GNUstep libs-base/Foundation APIs over custom implementations; only re-implement when existing behavior is too heavy or misaligned with project goals.
- Keep parser/transpiler logic explicit and state-machine based.
- Avoid regex-only parsing approaches for template tag handling.
- Emit diagnostics that include template filename and line numbers.
- Keep generated symbol naming deterministic.

## Testing Expectations

- New parser behaviors must include unit tests.
- New template syntax support must include fixtures in `tests/fixtures/templates/`.
- Bug fixes should include regression tests whenever practical.
- Standardize on XCTest via the Debian `tools-xctest` package (runner command: `xctest`).
- Before running tests, initialize GNUstep tooling in the shell with `source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh`.
- Keep test code XCTest-compatible to preserve a future path to Apple XCTest/macOS targets.

## Documentation Expectations

- Documentation is a required deliverable for user-facing behavior changes.
- Keep `README.md` and `docs/README.md` up to date with the current developer entry path.
- For CLI/runtime behavior changes, update `docs/CLI_REFERENCE.md` and `docs/GETTING_STARTED.md` in the same change.
- For architecture/contract changes, update the relevant spec and roadmap docs.
- Follow `docs/DOCUMENTATION_POLICY.md` for the full docs definition-of-done and review checklist.

## Security and Trust Assumptions

- v1 templates are trusted code.
- Do not claim sandboxing for template execution.
- Auto-escape expression output by default unless raw output is explicitly requested.

## Non-Goals For Early Iterations

- Full Mojolicious feature parity.
- Production-grade app server features (hot reload, prefork worker model, etc.).
- Untrusted template execution model.

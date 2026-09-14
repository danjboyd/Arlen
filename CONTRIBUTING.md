# Contributing to Arlen

Thanks for your interest in Arlen. Arlen is a young framework with a small core
team, and outside contributions are welcome — bug reports, reproductions,
documentation fixes, and focused patches are all valuable.

This file covers the practical mechanics: how to set up, what to run before
opening a pull request, and the conventions reviewers will check for.

## Before you start

- File or comment on an issue first if the change is non-trivial. This lets us
  surface design considerations before you invest implementation time.
- For security-sensitive issues, do **not** open a public issue. Follow
  [`SECURITY.md`](SECURITY.md) instead.
- By contributing, you agree your contribution is licensed under the project's
  [LICENSE](LICENSE) and you abide by the
  [Code of Conduct](CODE_OF_CONDUCT.md).

## Development environment

Arlen targets GNUstep on Linux as the primary platform, with verified macOS
(Apple runtime) and Windows `CLANG64` preview paths. The
[Quick Start](README.md#quick-start) in the README is the canonical setup path.
At a minimum you will need:

- a clang-built GNUstep toolchain on Linux, or the Apple toolchain on macOS
- initialized submodules: `git submodule update --init --recursive`
- `tools-xctest` available if you plan to run the full unit suite

Start every session with:

```bash
source tools/source_gnustep_env.sh   # Linux/GNUstep
./bin/arlen doctor
```

If `arlen doctor` reports problems, fix them before building or running tests —
nothing downstream will work reliably until the toolchain is healthy.

## Building and running tests

Common targets used in CI and by reviewers:

| Target                   | What it does                                          |
| ------------------------ | ----------------------------------------------------- |
| `make all`               | Build the framework, tools, and bundled binaries.     |
| `make test-unit`         | Run the XCTest-based unit suite.                      |
| `make test-integration`  | Run integration tests (some require fixtures/DBs).    |
| `make test-data-layer`   | Run PostgreSQL-backed data-layer tests.               |
| `make ci-quality`        | The quality gate run in Linux CI.                     |
| `make ci-sanitizers`     | ASan/UBSan sanitizer lanes.                           |
| `make ci-docs`           | Documentation navigation and consistency checks.      |

For a fast smoke check:

```bash
./bin/test --smoke-only
```

For a single test method (XCTest filter syntax):

```bash
make test-unit-filter TEST=PgTests/testReleaseConnectionDiscardsDeadButOpenConnection
```

## Pull request conventions

- **Branches**: short, descriptive, kebab-case. Prefixes used in this repo:
  `fix/`, `refactor/`, `docs/`, `feat/`. Example: `fix/eoc-partial-cache-key`.
- **Commits**: one logical change per commit. Imperative subject line under
  72 characters; body wrapped at 72 explaining the *why*, not the *what*.
- **Pull requests**: use the [PR template](.github/PULL_REQUEST_TEMPLATE.md).
  Complete the validation checklist honestly — uncheck what you did not run
  and say so in the description.
- **Scope**: keep PRs focused. Refactors, formatting sweeps, and unrelated
  fixes belong in their own PRs.
- **CI**: all required checks must pass. If a check is flaky, say so in the
  PR description rather than re-running silently.

## Code style

Arlen is Objective-C with GNUstep idioms. A few conventions reviewers will
look for:

- Public symbols use the `ALN` prefix; tests and tooling use `ALN`-test
  scaffolding or no prefix when local.
- Header comments document the *intended* contract; implementation comments
  are reserved for non-obvious *why*. Don't restate what the code says.
- Match the surrounding style of the file you are editing. If you think a
  file's style is wrong, fix it in a separate refactor PR.
- New public API should ship with a unit test and, where it spans subsystems,
  an integration test.

## Documentation

User-facing documentation lives in [`docs/`](docs/). Engineering-internal
material (phase roadmaps, dated reconciliations, milestone notes) lives in
[`docs/internal/`](docs/internal/). Keep user-facing prose evergreen — no
phase numbers, no dated milestones in titles or section headings.

If you add a new user-facing document, list it under the appropriate section
of [`docs/README.md`](docs/README.md) and run `make ci-docs` before opening
the PR.

## Reporting bugs

Open a bug report from the GitHub Issues tab. Useful reports include:

- Arlen commit (`git rev-parse HEAD`) and platform.
- GNUstep toolchain version (`gnustep-config --variable=GNUSTEP_MAKEFILES`).
- The smallest reproduction you can produce — ideally a failing test or a
  ten-line app under `examples/`.
- What you expected vs. what happened, including relevant log output.

## Getting help

- For setup or toolchain trouble, start with `./bin/arlen doctor` and the
  guides under [`docs/`](docs/).
- For design questions, open an issue tagged `discussion`.

Thanks for helping make Arlen better.

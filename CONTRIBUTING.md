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
| `make test-inventory`    | Check discovered tests against the committed list.    |
| `make test-data-layer`   | Run PostgreSQL-backed data-layer tests.               |
| `make ci-quality`        | The quality gate run in Linux CI.                     |
| `make ci-sanitizers`     | ASan/UBSan sanitizer lanes.                           |
| `make ci-docs`           | Documentation navigation and consistency checks.      |

On macOS, `./bin/test --smoke-only` runs a fast smoke check. On Linux,
`./bin/test` runs the full `make test`; use the targets above or a filter for
something quicker.

For a single test method (XCTest filter syntax):

```bash
make test-unit-filter TEST=PgTests/testReleaseConnectionDiscardsDeadButOpenConnection
```

To chase a flaky test, repeat it: `ITERATIONS=200` runs it 200 times, and
`UNTIL_FAILURE=1` stops at the first failure. Required CI checks never retry
failed tests.

Other lanes reviewers may ask for: `make check`, `make ci-perf-smoke` (lighter
local macro perf subset), `make ci-benchmark-contracts`,
`make ci-fault-injection`, `make ci-release-certification`, `make deploy-smoke`,
and `make browser-error-audit` (renders a gallery of build/runtime error pages
under `build/browser-error-audit/index.html`). Live PostgreSQL regressions run
with `bash tools/ci/run_postgres_regressions.sh`. The `GNUmakefile` also has
subsystem `*-confidence` targets that aren't part of the standard gate.

### Test runner

The make targets build and use the vendored `vendor/tools-xctest` runner, a
tagged release of the maintained fork
[`danjboyd/tools-xctest`](https://github.com/danjboyd/tools-xctest), and test
bundles link against its `libXCTest`. That gives Apple-style `-only-testing`
filters (a filter that matches no test fails the run), `XCTSkip`, and per-test
time limits (`ARLEN_TEST_TIMEOUT`, default 300 seconds). Every run writes a
JUnit report under `test-results/`.

CI also checks that the unit and integration bundles discover exactly the tests
listed in `tests/fixtures/test_inventory/`, so a test can't disappear
unnoticed. When you add, remove, or rename tests, run
`make update-test-inventory` and commit the updated lists with your change.

Set `ARLEN_USE_VENDORED_XCTEST=0` to use the system `xctest` and `libXCTest`
instead; it must be the fork at the same release or newer. Set
`ARLEN_XCTEST=/path/to/xctest` (plus `ARLEN_XCTEST_LD_LIBRARY_PATH` if needed)
to point at a different runner. See
[`docs/TESTING_WORKFLOW.md`](docs/TESTING_WORKFLOW.md) and
[`docs/TOOLCHAIN_MATRIX.md`](docs/TOOLCHAIN_MATRIX.md).

### Build policy

ARC (`-fobjc-arc`) is required on every first-party Objective-C compile path.
`EXTRA_OBJC_FLAGS` can only add flags and can't disable ARC. Changing compile
toggles or `EXTRA_OBJC_FLAGS` invalidates cached build artifacts, so
sanitizer-built tools are never silently reused in normal lanes.

### CI

- Required checks on `main`: `linux-quality / quality-gate`,
  `linux-sanitizers / sanitizer-gate`, and `docs-quality / docs-gate`.
- Apple and Windows lanes run visibly but aren't required. Release
  certification runs separately in `release-certification`.
- CI expects a clang-built GNUstep toolchain at `/usr/GNUstep`. Runners use
  `ARLEN_CI_GNUSTEP_STRATEGY=preinstalled`. Use `apt` or `bootstrap` only when
  provisioning a fresh runner. The bootstrap entry point is
  `tools/ci/install_ci_dependencies.sh`.
- Lane details and branch-protection guidance are in
  [`docs/CI_ALIGNMENT.md`](docs/CI_ALIGNMENT.md).

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

User-facing changes get an entry in
[`docs/RELEASE_NOTES.md`](docs/RELEASE_NOTES.md), which is the project's
changelog.

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
- For questions, ideas, and show-and-tell, use
  [GitHub Discussions](https://github.com/danjboyd/Arlen/discussions).
- For a design proposal you intend to implement, open an issue describing the
  problem before writing code.

Thanks for helping make Arlen better.

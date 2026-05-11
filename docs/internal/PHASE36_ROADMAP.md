# Phase 36 Roadmap

Status: complete; 36A-36L delivered 2026-04-20
Last updated: 2026-04-20

## Goal

Make Arlen deployment operationally obvious from a new app checkout through a
fresh remote target.

Phase 29 made deploy a first-class command family. Phase 32 made deployment
target-aware and added remote transport, host scaffolding, and target
compatibility checks. Phase 36 is the operator-UX pass that makes those pieces
easy to discover, hard to misuse, and friendly to shell completion and coding
agents.

## North Star

A developer should be able to move from a generated app to a remote release
with a predictable command path:

```sh
cp config/deploy.plist.example config/deploy.plist
$EDITOR config/deploy.plist

arlen deploy list
arlen deploy dryrun production
arlen deploy init production
arlen deploy doctor production
arlen deploy push production
arlen deploy releases production
arlen deploy release production --release-id <id>
```

The CLI should make the next safe action clear when configuration, target
initialization, pushed release artifacts, or shell-completion setup is missing.

## Scope

- deploy target discovery and onboarding
- `plan` to `dryrun` rename with compatibility aliasing
- release inventory listing for local and named remote targets
- generated deploy target sample config for new and existing apps
- initialized-target guards before remote push/release mutation
- bash and PowerShell completion generation
- focused tests, docs, and a Phase 36 confidence lane

## Non-Goals

- Do not make `arlen deploy` a cloud provisioner.
- Do not make `arlen deploy` install GNUstep or Arlen packages implicitly.
- Do not require future `gnustep install arlen` package-manager support to
  complete this phase.
- Do not make shell completion perform SSH, network access, builds, or writes.
- Do not remove the `plan` alias in this phase.
- Do not change required GitHub merge-gate checks.

## 36A. Deploy Command Discovery

Status: delivered 2026-04-20.

Goal:

- make bare `arlen deploy` a useful onboarding entrypoint
- add `arlen deploy list` for configured target discovery

Required behavior:

- `arlen deploy` exits `0` and prints concise help plus next steps
- when no targets are configured, it points to `config/deploy.plist.example`
- when targets exist, it points to `arlen deploy list`
- `arlen deploy --json` emits a structured `deploy.help` payload
- `arlen deploy list` exits `0` when no targets exist and reports an empty
  target list with next actions
- `arlen deploy list --json` emits a stable `deploy.list` payload
- configured target names are sorted deterministically

Acceptance:

- users can discover whether any deploy targets exist without reading plist
  files directly
- missing target configuration is onboarding state, not a crash or generic
  usage error

## 36B. Deploy Dryrun Rename

Status: delivered 2026-04-20.

Goal:

- rename `arlen deploy plan` to `arlen deploy dryrun`
- keep `plan` as a compatibility alias through at least one later phase

Required behavior:

- `arlen deploy dryrun [target]` has the current `plan` semantics
- JSON workflow is `deploy.dryrun`
- `arlen deploy plan` still works
- human `plan` output warns that `plan` is deprecated in favor of `dryrun`
- JSON `plan` output records `deprecated_alias = plan`
- docs and examples prefer `dryrun`

Acceptance:

- existing downstream scripts using `plan` keep working
- new docs and generated next actions use `dryrun`

## 36C. Deploy Release Inventory

Status: delivered 2026-04-20.

Goal:

- add `arlen deploy releases [target]` to list releases available to activate

Required behavior:

- local mode lists release directories under `--releases-dir`
- named local targets list target release directories
- named remote targets list remote release directories over SSH without
  requiring `releases/current`
- output excludes the `current` symlink from the release inventory
- output identifies the active and previous release when available
- JSON workflow is `deploy.releases`
- manifest metadata is included when `metadata/manifest.json` is present

Acceptance:

- after multiple `deploy push <target>` runs, operators can see which release
  IDs are available before choosing one to activate

## 36D. Named-Target Release Reuse

Status: delivered 2026-04-20.

Goal:

- fix `ARLEN-BUG-022` / `ISSUE-002`
- make `arlen deploy release <target> --release-id <id>` reuse existing local
  or remote release artifacts instead of rebuilding blindly

Required behavior:

- if the selected local staged release exists, skip local build
- if the selected remote release exists, skip upload when safe
- if neither exists, build/upload before activation
- preserve packaged remote activation through the packaged `arlen` binary
- return deterministic diagnostics when the selected artifact is incomplete

Acceptance:

- `deploy push <target> --release-id X`
- `deploy release <target> --release-id X`
- no `release_exists` failure; release `X` activates

## 36E. Initialized-Target Guards

Status: delivered 2026-04-20.

Goal:

- prevent remote mutation commands from running before target initialization

Required behavior:

- named remote `deploy push <target>` fails before build/upload when the target
  has not been initialized
- named remote `deploy release <target>` fails before build/upload/activation
  when the target has not been initialized
- error code: `deploy_target_not_initialized`
- fix-it points to `arlen deploy init <target>`
- `deploy list`, `deploy dryrun`, and `deploy doctor` do not require init
- `deploy doctor <target>` reports missing init artifacts as failed probes

Acceptance:

- users get a precise init-first error instead of a late SSH/path/build failure

## 36F. Deploy Config Sample

Status: delivered 2026-04-20.

Goal:

- provide a commented deploy target sample for generated apps and existing apps

Required behavior:

- `arlen new` writes `config/deploy.plist.example`
- the generated app README includes the copy/edit/dryrun/init/doctor/push flow
- the sample uses OpenStep/GNUstep plist syntax
- comments explain each common option
- a regression verifies the commented sample parses through Arlen's deploy
  target loader after being copied to `config/deploy.plist`

Acceptance:

- new apps include an editable deploy target starting point without activating
  fake target configuration by default

## 36G. Deploy Target Sample Command

Status: delivered 2026-04-20.

Goal:

- help existing apps generate the same deploy config sample

Required behavior:

- add `arlen deploy target sample`
- default behavior prints the commented sample to stdout
- `--write` writes `config/deploy.plist.example` by default
- `--force` is required to overwrite an existing file
- `--target <name>` customizes the sample target name
- `--ssh-host <host>` optionally fills the SSH host placeholder
- JSON workflow is `deploy.target.sample`

Acceptance:

- apps created before Phase 36 can get the canonical sample without copying
  from docs

## 36H. CLI Completion Foundation

Status: delivered 2026-04-20.

Goal:

- make shell completion a first-class Arlen CLI feature

Required behavior:

- add `arlen completion bash`
- add `arlen completion powershell`
- scripts are generated to stdout and safe to redirect into shell profile files
- generated completion logic calls back into Arlen for dynamic candidates
- add internal candidate commands for:
  - top-level commands
  - deploy subcommands
  - deploy target names
  - deploy release IDs from local staged release directories
  - command options
- candidate commands are read-only, local-only, fast, and tolerant of missing
  or half-edited config

Acceptance:

- bash and PowerShell users can complete deploy subcommands and target names
  without hand-maintained shell scripts

## 36I. Completion Safety And Tests

Status: delivered 2026-04-20.

Goal:

- keep completion reliable enough to enable by default in operator docs

Required behavior:

- completion candidate commands do not perform SSH
- completion candidate commands do not build releases
- completion candidate commands do not write files
- malformed deploy config returns no target candidates and exit `0`
- generated bash script contains a registered `arlen` completer
- generated PowerShell script contains `Register-ArgumentCompleter`

Acceptance:

- shell completion is useful during normal typing and cannot trigger deploy
  side effects

## 36J. Deploy Docs Refresh

Status: delivered 2026-04-20.

Goal:

- update deploy docs around the new operator flow

Required docs:

- `docs/CLI_REFERENCE.md`
- `docs/DEPLOYMENT.md`
- `docs/GETTING_STARTED.md`
- `docs/GETTING_STARTED_QUICKSTART.md`
- generated app README template
- `docs/internal/OPEN_ISSUES.md` for closing `ARLEN-BUG-022`

Acceptance:

- docs consistently use `dryrun`, `list`, `releases`, and the sample config
  path
- docs clearly separate `gnustep install arlen` future distribution work from
  current deploy commands

## 36K. Confidence Lane

Status: delivered 2026-04-20.

Goal:

- add a focused regression lane for the Phase 36 deploy UX contract

Required behavior:

- add `make phase36-confidence`
- add a CI helper under `tools/ci/`
- generate artifacts under `build/release_confidence/phase36/`
- cover:
  - deploy list with no config and with two targets
  - dryrun and plan alias
  - sample config parsing
  - uninitialized target guard
  - push/release reuse for named remote target
  - releases listing after multiple pushes
  - bash/PowerShell completion generation and candidate commands

Acceptance:

- Phase 36 has one repeatable local verification command

Evidence:

- `make phase36-confidence`
- `build/release_confidence/phase36/manifest.json`
- `build/release_confidence/phase36/phase36_confidence_eval.json`
- `build/release_confidence/phase36/phase36_confidence.md`

## 36L. Closeout

Status: delivered 2026-04-20.

Goal:

- close the deploy operator-UX phase with docs, status, and confidence evidence

Required behavior:

- update README milestone ledger
- update docs index
- update `docs/STATUS.md`
- update roadmap status to complete
- record `phase36-confidence` evidence

Acceptance:

- the new deploy command flow is documented, tested, and visible from the
  project entrypoints

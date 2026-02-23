# Phase 7G Coding-Agent-First DX Contracts

Phase 7G defines machine-readable developer-experience contracts for coding-agent workflows so scaffold/build/check/deploy loops are deterministic and automatable.

This document captures the initial 7G implementation slice completed on 2026-02-23.

## 1. Scope (Initial Slice)

- JSON output contracts for core scaffold workflows.
- JSON dry-run planning contracts for build/check workflows.
- JSON dry-run planning contracts for release build workflow.
- Fix-it diagnostics in JSON error payloads for common scaffold and workflow failures.
- Agent-oriented integration regression coverage for representative iterative task loops.

## 2. Machine-Readable Workflow Contracts

Scaffold workflows:

```bash
arlen new DemoApp --full --json
arlen generate endpoint UsersShow --route /users/:id --json
```

Build/check planning workflows:

```bash
arlen build --dry-run --json
arlen check --dry-run --json
```

Deploy release planning workflow:

```bash
tools/deploy/build_release.sh \
  --app-root /path/to/app \
  --framework-root /path/to/Arlen \
  --releases-dir /path/to/app/releases \
  --release-id rel-001 \
  --dry-run \
  --json
```

Shared contract version in JSON payloads:

- `phase7g-agent-dx-contracts-v1`

## 3. Deterministic Scaffold Conventions

`arlen new --json` payload includes:

- `created_files`: sorted deterministic file list for scaffolded app payload.

`arlen generate --json` payload includes:

- `generated_files`: sorted deterministic created-file list.
- `modified_files`: deterministic modified-file list (for example route wiring into `src/main.m`).

These surfaces are designed for coding-agent postconditions and idempotency checks.

## 4. Fix-It Diagnostics Contract

JSON errors include structured remediation guidance:

- `error.code`
- `error.message`
- `error.fixit.action`
- `error.fixit.example`

Representative error classes in the initial slice:

- missing generator route for endpoint workflows
- unsupported/invalid generator options
- unresolved framework root for build/check workflows
- deploy release path/root validation failures

## 5. Agent Regression Harness Coverage

Representative integration workflow:

- scaffold app via `arlen new --json`
- generate endpoint via `arlen generate ... --json`
- validate missing-route fix-it payload
- validate `arlen build/check --dry-run --json` planning payloads
- validate deploy release build planning payload via `tools/deploy/build_release.sh --dry-run --json`

## 6. Executable Verification

Machine-readable contract fixture:

- `tests/fixtures/phase7g/coding_agent_dx_contracts.json`

Verification coverage:

- `tests/integration/DeploymentIntegrationTests.m`
  - `testAgentJSONWorkflowContractsCoverScaffoldBuildCheckAndDeploy`
- `tests/unit/Phase7GTests.m`
  - `testCodingAgentDXContractFixtureSchemaAndTestCoverage`

## 7. Remaining 7G Follow-On

- Expand machine contracts to additional workflows (`migrate`, `schema-codegen`, typed SQL codegen).
- Add richer agent replay fixtures (multi-step repair loops and idempotent retry scenarios).
- Add versioned schema docs for JSON payload evolution and compatibility policy.

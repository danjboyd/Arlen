# Phase 7H Distributed Runtime Depth

Phase 7H extends Arlen's baseline clustering/runtime primitives with deterministic
multi-node failure-signal contracts for operational triage.

This document captures the initial 7H implementation slice completed on 2026-02-23.

## 1. Scope (Initial Slice)

- Quorum-aware readiness contract for multi-node deployments.
- Expanded `/clusterz` payload with quorum and coordination capability metadata.
- Deterministic distributed-runtime response headers for incident triage.
- Config/env compatibility coverage for new quorum/observed-node controls.
- Unit and integration regressions for degraded and nominal cluster states.

## 2. Configuration Contracts

New/extended config keys:

- `observability.readinessRequiresClusterQuorum` (default: `NO`)
- `cluster.observedNodes` (default: `cluster.expectedNodes`)

Environment overrides (legacy fallback supported):

- `ARLEN_READINESS_REQUIRES_CLUSTER_QUORUM` (`MOJOOBJC_READINESS_REQUIRES_CLUSTER_QUORUM`)
- `ARLEN_CLUSTER_OBSERVED_NODES` (`MOJOOBJC_CLUSTER_OBSERVED_NODES`)

Normalization behavior:

- `cluster.expectedNodes` is clamped to `>= 1`
- `cluster.observedNodes` is clamped to `>= 0`

## 3. Quorum-Gated Readiness Contract

When all are true:

- `cluster.enabled = YES`
- `observability.readinessRequiresClusterQuorum = YES`
- `cluster.observedNodes < cluster.expectedNodes`

`GET /readyz` returns deterministic not-ready behavior:

- text probe: `503` with `ready` signal unavailable
- JSON probe (`Accept: application/json` or `?format=json`):
  - `status = "not_ready"`
  - `ready = false`
  - `checks.cluster_quorum` object with:
    - `ok`
    - `required_for_readyz`
    - `status`
    - `observed_nodes`
    - `expected_nodes`

## 4. `/clusterz` Coordination Contract

`GET /clusterz` now includes distributed-runtime depth fields:

- `cluster.observed_nodes`
- `cluster.quorum`:
  - `status` (`single_node|partitioned|degraded|nominal`)
  - `met`
  - `observed_nodes`
  - `expected_nodes`
- `coordination`:
  - `membership_source` (`static_config`)
  - `state` (same status contract as quorum)
  - `capability_matrix` for cross-node boundaries:
    - `cross_node_request_routing = external_load_balancer_required`
    - `cross_node_realtime_fanout = external_broker_required`
    - `cross_node_jobs_deduplication = external_queue_required`
    - `cross_node_cache_coherence = external_cache_required`

## 5. Response Header Contract

When `cluster.emitHeaders = YES`, responses include:

- `X-Arlen-Cluster`
- `X-Arlen-Node`
- `X-Arlen-Worker-Pid`
- `X-Arlen-Cluster-Status`
- `X-Arlen-Cluster-Observed-Nodes`
- `X-Arlen-Cluster-Expected-Nodes`

These headers are deterministic and can be disabled by setting
`cluster.emitHeaders = NO`.

## 6. Operational Triage Workflow

Recommended triage sequence for degraded rollouts:

1. Query `/readyz` with JSON to confirm whether quorum is required and currently unmet.
2. Query `/clusterz` to inspect quorum/coordination state and capability boundaries.
3. Inspect `X-Arlen-Cluster-*` response headers from live traffic samples to correlate
   degraded node pools quickly.

## 7. Executable Verification

Machine-readable contract fixture:

- `tests/fixtures/phase7h/distributed_runtime_contracts.json`

Verification coverage:

- `tests/unit/ConfigTests.m`
  - `testLoadConfigMergesAndAppliesDefaults`
  - `testEnvironmentOverridesRequestLimitsAndProxyFlags`
  - `testLegacyEnvironmentPrefixFallback`
- `tests/unit/ApplicationTests.m`
  - `testReadyzJSONCanRequireClusterQuorumAndReturnDeterministic503`
  - `testClusterStatusPayloadIncludesQuorumAndCapabilityMatrix`
- `tests/integration/HTTPIntegrationTests.m`
  - `testClusterStatusEndpointAndHeaders`
  - `testClusterHeadersCanBeDisabled`
  - `testReadinessCanRequireClusterQuorumInMultiNodeMode`
- `tests/unit/Phase7HTests.m`
  - `testDistributedRuntimeDepthContractFixtureSchemaAndTestCoverage`

## 8. Remaining 7H Follow-On

The broader 7H roadmap still includes:

- dynamic membership-source contracts (beyond static config)
- deeper failure-injection scenarios for node churn and transient partitions
- expanded deploy runbook automation for distributed failure drills

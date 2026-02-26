# Arlen Phase 10 Roadmap

Status: Active (10A/10B/10C/10D/10E/10F/10G/10H/10I/10J/10K complete)  
Last updated: 2026-02-26

Related docs:
- `docs/PHASE9_ROADMAP.md`
- `docs/STATUS.md`
- `docs/PERFORMANCE_PROFILES.md`
- `docs/RUNTIME_CONCURRENCY_GATE.md`

External source reviewed for this roadmap:
- `/home/danboyd/git/ArlenBenchmarking/runner/tools/json_perf/aln_yyjson_serialization.h`
- `/home/danboyd/git/ArlenBenchmarking/runner/tools/json_perf/aln_yyjson_serialization.m`
- `/home/danboyd/git/ArlenBenchmarking/runner/tools/json_perf/nsjson_vs_yyjson_bench.m`
- `/home/danboyd/git/ArlenBenchmarking/reports/json_perf/latest_summary.md`

## 1. Objective

Replace direct framework/runtime usage of GNUstep `NSJSONSerialization` with a hardened yyjson-backed serialization layer that is:

- API-compatible for Arlen use cases
- deterministic under malformed/untrusted input
- covered by differential/regression testing
- measurable via reproducible performance gates

Phase 10 is reliability and performance hardening, not feature expansion.

## 2. Review Summary (POC Findings)

The benchmarking POC demonstrates meaningful speedups but is not production-ready as-is.

Key findings:

1. ARC compatibility gap:
   - POC implementation uses manual retain/release patterns and must be ported to Arlen's ARC build.
2. Coverage gap:
   - No dedicated parity/regression test suite for behavior equivalence against `NSJSONSerialization`.
3. Scope gap:
   - POC is isolated to benchmark tooling and not integrated into Arlen runtime/CLI build paths.
4. Behavior gap risk:
   - Option/edge behavior (mutable container/leaf semantics, fragments, numeric edge cases, key sorting, error shape) requires explicit contract tests before cutover.
5. Dependency gap:
   - yyjson pinning, provenance, upgrade policy, and build integration are not yet formalized in Arlen.
6. Benchmark bottleneck priority:
   - latest benchmark evidence indicates dispatch/runtime invocation overhead remains the dominant bottleneck (dynamic `NSInvocation` path in `src/Arlen/Core/ALNApplication.m`, around lines 3104 and 3167 in the measured snapshot), and should be addressed with cached IMP invocation paths.

## 3. Scope Summary

1. Phase 10A: yyjson dependency + Arlen JSON abstraction foundation.
2. Phase 10B: serializer parity and fuzz/regression matrix.
3. Phase 10C: runtime path migration (request/response/auth/session/logger/schema).
4. Phase 10D: CLI/tooling migration and compatibility hardening.
5. Phase 10E: performance confidence gate + rollout controls.
6. Phase 10F: full cutover and legacy guardrails.
7. Phase 10G: dispatch/runtime invocation overhead reduction (cached IMP path).
8. Phase 10H: replace HTTP parse pipeline with llhttp-based parser path.
9. Phase 10I: compile-time feature toggles for JSON/parser backends.
10. Phase 10J: HTTP runtime hot-path memory/throughput optimization tranche.
11. Phase 10K: benchmark-driven write/parse/baseline overhead optimization pass.

## 4. Milestones

## 4.1 Phase 10A: yyjson Foundation Layer

Status: Complete (2026-02-26)

Deliverables:

- Vendor pinned yyjson source into Arlen with explicit version metadata.
- Introduce `ALNJSONSerialization` (or equivalent) as Arlen's single JSON API surface.
- Port POC compatibility wrapper to ARC-safe Objective-C.
- Add build integration for yyjson C source and headers in all relevant targets.
- Add runtime/CI backend switch:
  - default backend (phase-dependent)
  - explicit fallback to `NSJSONSerialization` for A/B verification.

Acceptance (required):

- Arlen builds successfully with yyjson-enabled serializer on all existing targets.
- Backend can be switched deterministically without code changes.
- No direct yyjson API use outside serialization module.

## 4.2 Phase 10B: Parity + Regression Contract Matrix

Status: Complete (2026-02-26)

Deliverables:

- New unit suite for serializer contracts:
  - parse/write valid primitives, arrays, objects
  - unicode/escape handling
  - mutable container/leaf options
  - sorted-key behavior
  - invalid JSON error contracts and location diagnostics
  - depth limits and pathological nesting
  - number fidelity (bool/int/uint/real boundaries, NaN/Inf rejection)
- Differential harness comparing yyjson backend vs `NSJSONSerialization` over shared fixture corpus.
- Fuzz-style malformed payload corpus for crash safety and deterministic failures.

Acceptance (required):

- Differential suite shows no unresolved behavior regressions for Arlen-supported JSON contracts.
- Malformed-input corpus produces deterministic errors without crashes/leaks.
- Sanitizer lanes cover JSON parser/writer paths.

## 4.3 Phase 10C: Runtime JSON Path Migration

Status: Complete (2026-02-26)

Deliverables:

- Replace runtime call sites in:
  - `src/Arlen/HTTP/ALNResponse.m`
  - `src/Arlen/Core/ALNSchemaContract.m`
  - `src/Arlen/MVC/Middleware/ALNResponseEnvelopeMiddleware.m`
  - `src/Arlen/MVC/Middleware/ALNSessionMiddleware.m`
  - `src/Arlen/Support/ALNAuth.m`
  - `src/Arlen/Support/ALNLogger.m`
  - `src/Arlen/Core/ALNApplication.m`
  - `src/Arlen/Data/ALNPg.m`
  - `src/Arlen/MVC/Controller/ALNController.m`
- Ensure response contract validation, auth token parsing, session token handling, and envelope middleware retain existing behavior.

Acceptance (required):

- Existing unit/integration suites pass with yyjson backend enabled.
- Runtime concurrency and fault-injection gates remain green.
- No regression in deterministic error payload shapes for JSON failure paths.

## 4.4 Phase 10D: CLI + Tooling Migration

Status: Complete (2026-02-26)

Deliverables:

- Migrate JSON call sites in:
  - `tools/arlen.m`
  - `tools/boomhauer.m`
  - release/deploy/support tooling where JSON parse/write is runtime critical.
- Preserve machine-readable output contracts currently consumed by coding-agent workflows.
- Add compatibility checks for pretty-print/stable output expectations.

Acceptance (required):

- JSON output schemas used by tests/docs remain unchanged.
- Deploy/check/build JSON modes continue to emit deterministic payloads.

## 4.5 Phase 10E: Performance and Rollout Gates

Status: Complete (2026-02-26)

Deliverables:

- Add in-repo JSON microbenchmark (encode/decode only) using shared fixture sets.
- Add CI artifact generation for JSON backend performance deltas:
  - nsjson backend vs yyjson backend
  - parse/write throughput and latency metrics
- Define pass/fail thresholds for release confidence:
  - no severe regressions in latency p95
  - expected throughput improvement bands for representative payload classes.

Acceptance (required):

- Benchmark run is reproducible via one documented command path.
- Release confidence pack includes JSON backend performance snapshot.

## 4.6 Phase 10F: Cutover + Legacy Guardrails

Status: Complete (2026-02-26)

Deliverables:

- Set yyjson-backed serializer as production default.
- Keep temporary fallback backend for one release cycle with explicit deprecation timeline.
- Add lint/check rule preventing new direct `NSJSONSerialization` usage in runtime code.
- Update docs and release process to treat JSON parity/perf artifacts as required evidence.

Acceptance (required):

- Runtime code path uses Arlen JSON abstraction exclusively.
- New direct runtime `NSJSONSerialization` usage fails quality checks.
- Known-risk register and release notes capture migration risk status and closure.

## 4.7 Phase 10G: Dispatch/Runtime Invocation Overhead Hardening

Status: Complete (2026-02-26; runtime invocation mode hardening + multi-round gate calibration complete)

Deliverables:

- Replace high-frequency dynamic `NSInvocation` dispatch path with cached IMP-based invocation in request hot path.
- Preserve existing action/guard signature contracts while reducing per-request reflection overhead.
- Add deterministic regression coverage for invocation-path correctness and error diagnostics.
- Add benchmark deltas showing invocation-path impact separate from JSON backend impact.

Acceptance (required):

- Runtime behavior and diagnostics remain contract-equivalent for controller/action/guard execution.
- JSON migration benchmarks are reported with and without dispatch optimization to avoid attribution drift.
- Performance artifacts are generated reproducibly for selector vs cached-IMP dispatch comparisons with median aggregation across repeated rounds.

## 4.8 Phase 10H: HTTP Parse Pipeline Migration to llhttp

Status: Complete (2026-02-26; llhttp parser migration + multi-round gate calibration complete)

Deliverables:

- Introduce an llhttp-backed request parser path to replace current HTTP parsing hot path.
- Keep existing Arlen request contract behavior (headers/query/body/errors) equivalent for supported inputs.
- Add parser differential tests and malformed-input regressions between legacy parser and llhttp path.
- Add performance artifacts focused on parse throughput/latency and allocator pressure under load.
- Provide a staged fallback toggle for controlled rollout and A/B validation.
- Reduce llhttp adapter overhead for small requests:
  - one-time shared parser settings initialization
  - span-first callback accumulation (avoid per-callback append churn when contiguous)
  - remove unconditional request-line normalization copy from the hot path
  - defer query/cookie materialization until first access

Acceptance (required):

- No unresolved request parsing contract regressions for current supported HTTP/1.1 behavior.
- Existing request-size limits and error response semantics remain deterministic.
- Stress/fault runs show no new crash/leak findings in the llhttp path.
- Parser-gate thresholds enforce llhttp parity-or-better for small fixtures and stronger gains for large fixtures.
- Rollout can be toggled safely between legacy and llhttp parser paths during validation.

## 4.9 Phase 10I: Compile-Time Backend Toggle Hardening

Status: Complete (2026-02-26)

Deliverables:

- Add compile-time switches to build pipelines:
  - `ARLEN_ENABLE_YYJSON` (`1` default, `0` disables yyjson compilation)
  - `ARLEN_ENABLE_LLHTTP` (`1` default, `0` disables llhttp compilation)
- Ensure app-root compile path (`bin/boomhauer`) and framework `GNUmakefile` honor the same switches.
- Preserve runtime behavior deterministically when features are compiled out:
  - JSON serialization falls back to Foundation backend.
  - HTTP parsing falls back to legacy parser backend.
- Add regression coverage for disabled-feature compile path and fallback metadata contracts.

Acceptance (required):

- Arlen compiles with either backend feature disabled independently.
- Runtime/backend metadata and selection APIs report deterministic fallback state (`foundation`/`legacy`, version `disabled`) when compiled out.
- Existing default builds remain unchanged (`yyjson` + `llhttp` enabled by default).

## 4.10 Phase 10J: HTTP Runtime Hot-Path Memory/Throughput Optimization

Status: Complete (2026-02-26)

Deliverables:

- 10J.1 per-request memory lifecycle hardening:
  - add explicit per-request `@autoreleasepool` boundaries in HTTP hot loops (accept-thread and keep-alive request loop paths).
  - add long-run keep-alive/request-churn regression coverage with RSS-growth guardrails.
- 10J.2 production dispatch default policy hardening (gated, not immediate blind flip):
  - keep a reliability-first default while adding benchmark/operability controls to force concurrent dispatch where appropriate.
  - define evidence gates required before changing production default dispatch mode.
- 10J.3 per-request identity/observability overhead reduction:
  - replace UUID-string-heavy request/trace ID generation with lower-overhead hex ID generation.
  - default cluster response headers to disabled when cluster mode is disabled.
- 10J.4 response write-path copy reduction:
  - avoid building full response combined `NSData` for every request.
  - write headers/body with reduced-copy strategy while preserving response contract semantics.
- 10J.5 read+parse pipeline deduplication:
  - remove duplicate header/content-length parsing work between socket read path and request parser path.
  - enforce request limits via a single parse pass where practical.
- 10J.6 suppressed-log overhead elimination:
  - avoid constructing large per-request info log field dictionaries when current logger level will drop them.
- 10J.7 queue/static-mount micro-optimizations:
  - replace O(n) dequeue (`removeObjectAtIndex:0`) in HTTP worker queue.
  - cache normalized static mounts instead of rebuilding per request.

Implemented in this tranche:

- added explicit per-request `@autoreleasepool` boundaries in accept and keep-alive HTTP loops.
- added a keep-alive RSS churn regression guard lane (gated via `ARLEN_ENABLE_PHASE10J_RSS_CHURN=1`).
- replaced UUID-string-heavy request/trace identifier generation with lower-overhead random hex generation.
- defaulted cluster response header emission to `cluster.enabled` when `cluster.emitHeaders` is unset.
- split response serialization into header/body send path to avoid full combined response `NSData` allocations per request.
- eliminated duplicated read-path header/content-length parse work with a single metadata parse pass.
- avoided constructing info-log dictionaries when logger level suppresses info messages.
- replaced O(n) queue dequeue with head-index compaction strategy and cached effective static mount normalization.

Acceptance (required):

- Long-run request churn no longer shows unbounded RSS growth attributable to request-loop autorelease retention.
- Benchmark deltas show net win for small-request latency/throughput and no regression for larger request classes.
- No regressions in request/response behavioral contracts, logging contracts, or deployment operability checks.
- Dispatch-default policy change (if any) is gated by explicit reliability evidence, not by benchmark-only results.

## 4.11 Phase 10K: Benchmark-Driven Throughput/Latency Optimization Pass

Status: Complete (2026-02-26)

Deliverables:

- 10K.1 `H_blob_large` write-path optimization:
  - add reduced-copy/gathered response emission (`writev`-style path with deterministic fallback).
  - add per-worker reusable output buffers to reduce per-chunk allocation churn.
  - add file/static large-payload fast path (`sendfile` where available, portable fallback retained).
  - preserve partial-write/backpressure/error semantics and connection-close correctness.
- 10K.2 parser + metadata path optimization for `F_http_parse_many_headers` and `E_http_parse_large_path`:
  - parse headers/path into spans first and materialize Foundation objects lazily on demand.
  - reduce unconditional lowercase/copy work in header-path hot loops.
  - avoid large-path split/alloc churn with byte-oriented pre-match helpers before full route materialization.
  - preserve existing request contract behavior and parser backend toggles.
- 10K.3 `A_json_status` framework-tax fast path:
  - add an explicitly minimal request execution path for trivial JSON status-style endpoints.
  - avoid avoidable context/log/trace/middleware allocation work when equivalent behavior is configured as disabled.
  - keep auth/session/security semantics unchanged when enabled (no bypass of required middleware).
- 10K.4 cross-cutting allocation/contention cleanup:
  - introduce ARC-safe per-worker scratch storage reuse for request/response hot data structures.
  - reduce shared lock contention via per-worker or sharded state where contract-safe.
  - further reduce dynamic dispatch overhead in hot handlers via cached metadata/IMP paths.
  - avoid unsafe generic object pooling that weakens ARC lifetime/ownership guarantees.

Implemented in this tranche:

- added gathered response emission (`writev`) for header+body writes with deterministic `send` fallback path.
- added static-file fast path using response file metadata + `sendfile` when available, with portable read-loop fallback.
- eliminated eager static-file `NSData` loading in static mount handling and served regular files directly from disk.
- introduced thread-local llhttp parse-state reuse to reduce per-request parser object churn.
- reduced llhttp header parse overhead with byte-level OWS trim + lowercase normalization before string materialization.
- split request URI directly from llhttp span bytes to avoid full request-line URI materialization and split copies.
- reduced large-path route-match allocation churn by splitting request path segments once per match attempt and reusing them across candidates.
- reduced baseline dispatch-path allocations by caching info-level log gating and preferred-format decisions per request, and lazily allocating middleware execution tracking.
- cached serialized response header data with invalidation and added explicit file-body length support for static send paths.
- added regression coverage for new hot paths:
  - `tests/unit/ResponseTests.m`
  - `tests/unit/RequestTests.m`
  - `tests/unit/RouterTests.m`
  - `tests/integration/HTTPIntegrationTests.m`

Acceptance (required):

- New benchmark confidence artifacts capture pre/post deltas for `A_json_status`, `E_http_parse_large_path`, `F_http_parse_many_headers`, and `H_blob_large`.
- `H_blob_large` shows a clear throughput + p95 latency improvement relative to 10J baseline without regressions in correctness tests.
- `E/F` parser suites show improved throughput without request-contract regressions (headers/query/cookies/path params/error behavior).
- `A_json_status` shows measurable reduction in baseline framework overhead while preserving logging/trace/security contracts.
- Long-run stress/fault/sanitizer lanes show no new memory safety or lifecycle regressions.

## 5. Test Strategy

Minimum mandatory test layers:

1. Unit parity tests:
   - serializer API-level behavior and option coverage.
2. Differential corpus tests:
   - same fixtures through both backends with normalized equivalence checks.
3. Integration regressions:
   - endpoint JSON behavior, auth/session token decode paths, response envelope behavior.
4. Reliability tests:
   - sanitizer lanes, runtime concurrency gate, fault injection with JSON-heavy routes.
5. Performance tests:
   - dedicated microbenchmark and representative endpoint macrobenchmark comparison.

## 6. Rollout Order

1. 10A foundation before any runtime call-site migration.
2. 10B parity/fuzz gates before switching core runtime paths.
3. 10C runtime migration with backend toggle still available.
4. 10D tooling migration after runtime behavior is stable.
5. 10E performance gate publication.
6. 10F default cutover + guardrails.
7. 10G dispatch/runtime invocation overhead hardening.
8. 10H llhttp parser migration as final Phase 10 performance hardening stream.
9. 10I compile-time backend toggle hardening for controlled feature-disable builds.
10. 10J HTTP runtime hot-path memory/throughput optimization and reliability-gated dispatch policy.
11. 10K benchmark-driven write/parse/baseline overhead optimization pass with reliability gates.

## 7. Explicit Non-Goals (Phase 10)

1. JSON schema/validation feature expansion unrelated to serializer migration.
2. Wire-format changes to existing API envelopes.
3. Rewriting endpoint/business logic solely for benchmark tuning.

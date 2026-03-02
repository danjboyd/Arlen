# Arlen Phase 11 Roadmap

Status: Planned (Phase 11A-11F defined; implementation pending)  
Last updated: 2026-03-02

Related docs:
- `docs/PHASE10_ROADMAP.md`
- `docs/PHASE7B_SECURITY_DEFAULTS.md`
- `docs/RUNTIME_CONCURRENCY_GATE.md`
- `docs/PHASE9I_FAULT_INJECTION.md`
- `docs/SANITIZER_SUPPRESSION_POLICY.md`
- `docs/KNOWN_RISK_REGISTER.md`

## 1. Objective

Execute a security and correctness hardening phase focused on OpenBSD-style "is this correct under hostile input?" criteria:

- remove unsafe cryptographic/session behavior
- enforce strict HTTP/WebSocket/header correctness
- close filesystem trust-boundary escapes
- expand adversarial and sanitizer confidence gates

Phase 11 is hardening and verification work, not feature expansion.

## 2. Audit-Driven Entry Findings

Phase 11 starts from the 2026-03-02 audit findings in runtime-critical paths:

1. Session token integrity/confidentiality primitives are custom and not cryptographically safe.
2. Response/header serialization allows CRLF injection and case-variant header duplication.
3. WebSocket handshake/frame validation is permissive and frame reads can stall without deadline.
4. Static serving and filesystem attachment ID paths need stronger realpath/symlink confinement.
5. Proxy header trust is all-or-nothing; CSRF unsafe-method query fallback is overly permissive.
6. Text logger allows control-character log-forging patterns.

## 3. Scope Summary

1. Phase 11A: session and CSRF cryptographic/policy hardening.
2. Phase 11B: HTTP response/header correctness and injection resistance.
3. Phase 11C: WebSocket protocol conformance and stall/DoS controls.
4. Phase 11D: filesystem containment for static assets and attachment adapters.
5. Phase 11E: forwarded-header trust boundaries and log safety.
6. Phase 11F: second-pass adversarial verification expansion (fuzzing + sanitizers + live hostile traffic).

## 4. Milestones

## 4.1 Phase 11A: Session + CSRF Hardening

Deliverables:

- Replace custom session token signing/encryption with standard cryptography:
  - signed-cookie baseline: `HMAC-SHA256`
  - optional authenticated encryption path if confidentiality is required
- Remove insecure default session secret fallback; fail fast when secret is missing/weak.
- Use constant-time signature comparison.
- Make CSRF unsafe-method verification header/body-first by default; query fallback opt-in only.

Acceptance (required):

- `tests/unit/MiddlewareTests.m`:
  - tampered session cookie always rejected
  - missing/weak secret fails deterministic startup validation
  - unsafe request with query-only token is rejected by default
- No regression in valid session + CSRF nominal flow tests.

## 4.2 Phase 11B: HTTP Header Correctness + Injection Safety

Deliverables:

- Central header name/value validation:
  - reject `\r`, `\n`, and NUL
  - enforce RFC token charset for header names
- Canonicalize header lookup/storage to case-insensitive behavior.
- Guarantee single semantic `Content-Length` and `Content-Type` emission.
- Harden redirect/header helper paths so user-controlled values cannot split responses.

Acceptance (required):

- `tests/unit/ResponseTests.m`:
  - CRLF header payload is rejected
  - case-variant duplicate content headers cannot produce conflicting output
- Controller/integration tests verify redirects cannot emit injected headers.

## 4.3 Phase 11C: WebSocket Protocol + Stall Resistance

Deliverables:

- Enforce handshake invariants:
  - `Sec-WebSocket-Version: 13`
  - valid base64 nonce decoding to 16 bytes
- Reject unmasked client-to-server frames.
- Add bounded receive deadline/retry budget for frame reads; close stalled sessions.

Acceptance (required):

- `tests/integration/HTTPIntegrationTests.m`:
  - invalid version/key handshake rejected
  - unmasked frame rejected
  - partial-frame stall closes connection within configured timeout and server recovers

## 4.4 Phase 11D: Static + Attachment Filesystem Containment

Deliverables:

- Static mounts:
  - resolve candidate path by `realpath` before serve
  - verify resolved file remains under resolved mount root
  - add symlink-safe open strategy (`O_NOFOLLOW`/`openat` where available)
- Filesystem attachment adapter:
  - strict attachment ID format validation
  - root-constrained path resolution for read/delete/metadata operations

Acceptance (required):

- `tests/integration/HTTPIntegrationTests.m`:
  - symlink escape attempt under static root is denied
- `tests/unit/Phase7DTests.m`:
  - attachment traversal payloads (for example `../`) are rejected

## 4.5 Phase 11E: Proxy Trust + Log Safety

Deliverables:

- Replace boolean trusted-proxy toggle with explicit trusted source list (CIDR/accessory list).
- Apply forwarded headers only for trusted peer addresses.
- Escape control characters in text logger field output.

Acceptance (required):

- Proxy trust tests:
  - untrusted peer cannot spoof `x-forwarded-for`/`x-forwarded-proto`
  - trusted peer forwarding still works
- `tests/unit/LoggerTests.m`:
  - newline/tab/control chars are escaped in text mode.

## 4.6 Phase 11F: Second-Pass Security Verification Expansion

Deliverables:

- Add dedicated hostile-input fixture corpus for Phase 11:
  - header injection probes
  - duplicate-header/canonicalization probes
  - websocket version/key/mask/stall probes
  - traversal/symlink probes
- Add deterministic protocol mutation harness for high-volume request/frame perturbation.
- Add sanitizer-backed hostile-traffic lanes and artifact packaging.
- Add sustained live adversarial mixed-traffic lane (HTTP + websocket + keep-alive + malformed inputs).

Acceptance (required):

- New confidence artifacts under:
  - `build/release_confidence/phase11/`
- Both `concurrent` and `serialized` dispatch modes pass:
  - no crash
  - no hang/deadlock
  - no health/readiness contract regressions
- Blocking sanitizer lanes pass with new hostile corpus coverage.

## 5. Second-Pass Execution Plan (Fuzzing, Sanitizers, Live Adversarial Traffic)

This plan is intentionally incremental and reuses existing CI tooling first.

## 5.1 Baseline Re-Run (Current Tooling)

Run current gates before adding new harnesses:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make boomhauer
make ci-sanitizers
make ci-protocol-adversarial
make ci-fault-injection
```

Optional nightly race lane:

```bash
ARLEN_PHASE10M_INCLUDE_THREAD_NIGHTLY=1 make ci-sanitizers
```

Capture all artifacts under `build/release_confidence/phase10m/` and `build/release_confidence/phase9i/`.

## 5.2 Fuzzing Expansion (Phase 11 Additions)

1. Add `tests/fixtures/protocol/phase11_protocol_adversarial_cases.json` with security-focused cases:
   - CRLF header injection attempts
   - conflicting case-variant content headers
   - websocket invalid key/version/unmasked frames
   - partial-frame stall and timeout behavior
2. Add protocol mutation runner (`tools/ci/phase11_protocol_fuzz.py`) that:
   - mutates seed requests/frames with deterministic seed
   - asserts status-code class and server post-case health
   - records minimal reproducer payload for each failure
3. Add dedicated make/CI entrypoint (`make ci-phase11-fuzz`) and artifact summary markdown/json.

## 5.3 Sanitizer Expansion (Phase 11 Additions)

1. Extend sanitizer matrix fixture:
   - `tests/fixtures/sanitizers/phase11_sanitizer_matrix.json`
2. Add lanes that run new fuzz corpus under ASan+UBSan.
3. Keep TSAN/Helgrind lane non-blocking initially; promote once flake/false-positive budget is stable.
4. Require sanitizer confidence summary for release candidates to include Phase 11 lanes.

## 5.4 Live Adversarial Traffic Expansion (Phase 11 Additions)

1. Add sustained mixed hostile traffic harness (`tools/ci/phase11_live_adversarial_probe.py`) with:
   - concurrent nominal traffic
   - slowloris-style partial headers
   - websocket partial/unmasked/malformed frame traffic
   - static path traversal and symlink probes
   - forwarded-header spoof probes from trusted/untrusted peers
2. Execute against both runtime modes:
   - concurrent
   - serialized
3. Pass criteria:
   - no server crash or stuck worker pool
   - health endpoint remains available within bounded recovery window
   - expected reject statuses are deterministic (`400`/`403`/`431`/`503` as appropriate)

## 6. Explicit Non-Goals (Phase 11)

- No expansion of template feature surface.
- No new app-framework feature tracks unrelated to hardening.
- No relaxation of deterministic diagnostics and GNUstep compatibility constraints.

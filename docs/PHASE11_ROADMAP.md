# Arlen Phase 11 Roadmap

Status: Complete (Phase 11A-11F complete on 2026-03-06)  
Last updated: 2026-03-06

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
- enforce strict HTTP/WebSocket/header correctness with fail-closed request framing
- close filesystem trust-boundary escapes and private-storage gaps
- expand adversarial and sanitizer confidence gates

Phase 11 is hardening and verification work, not feature expansion.

## 1.1 Delivery Snapshot

Delivered on 2026-03-06:

- Phase 11A complete:
  - session startup validation now fails fast for missing/weak secrets
  - bearer-auth startup validation now fails fast for weak `auth.bearerSecret`
  - session cookies use standard cryptographic primitives with encrypted payload round-trip coverage
  - CSRF unsafe-method verification is header/body-first by default, with query fallback opt-in only
- Phase 11B complete:
  - response headers reject invalid names plus CRLF/NUL injection values
  - content header canonicalization is deterministic and case-insensitive
  - legacy request framing rejects duplicate `Content-Length`, unsupported `Transfer-Encoding`, and mixed `Content-Length` + `Transfer-Encoding`
- Phase 11C complete:
  - websocket upgrades require version `13` and a valid 16-byte base64 client key
  - optional websocket `Origin` allowlist enforcement is available
  - unmasked client frames are rejected and partial/stalled frame reads close within the bounded timeout contract
- Phase 11D complete:
  - static file serving now denies symlink-backed leaves, resolves existing assets under the canonical mount root, and opens file bodies with nofollow semantics
  - filesystem attachment IDs are strict framework-generated `att-<32 hex>` values with root-constrained, symlink-rejecting, nofollow-backed reads
  - file-backed job/mail/attachment adapters enforce private `0700` directories and `0600` files at startup and on write
- Phase 11E complete:
  - forwarded proxy metadata is gated by explicit trusted CIDR lists and still preserves the legacy boolean as a compatibility alias
  - text logger output escapes newline/tab/control characters in text mode to prevent log-forging payloads
- Phase 11F complete:
  - added Phase 11 hostile protocol corpus, deterministic mutation harness, mixed live hostile-traffic probe, and sanitizer artifact matrix
  - added make/CI entrypoints with confidence artifacts under `build/release_confidence/phase11/`

## 2. Audit-Driven Entry Findings

Phase 11 starts from the 2026-03-06 audit findings in runtime-critical paths:

1. Session token integrity/confidentiality primitives are custom and not cryptographically safe; bearer-token secret policy is also too weak.
2. Response/header serialization allows CRLF injection and case-variant header duplication.
3. Legacy HTTP request framing is permissive: duplicate `Content-Length`, unsupported `Transfer-Encoding`, and `Content-Length` + `Transfer-Encoding` ambiguity are not rejected fail-closed.
4. WebSocket handshake/frame validation is permissive, frame reads can stall without deadline, and cookie-authenticated upgrades lack origin policy.
5. Static serving and filesystem attachment ID paths need stronger realpath/symlink confinement.
6. File-backed adapters rely on process-default filesystem permissions instead of explicit private directory/file modes.
7. Proxy header trust is all-or-nothing; CSRF unsafe-method query fallback is overly permissive.
8. Text logger allows control-character log-forging patterns.

## 3. Scope Summary

1. Phase 11A: session, bearer-auth secret, and CSRF cryptographic/policy hardening.
2. Phase 11B: HTTP request/response/header correctness and fail-closed parser boundary hardening.
3. Phase 11C: WebSocket protocol, origin-policy, and stall/DoS controls.
4. Phase 11D: filesystem containment and private-storage hardening for static and file-backed adapters.
5. Phase 11E: forwarded-header trust boundaries and log safety.
6. Phase 11F: second-pass adversarial verification expansion (fuzzing + sanitizers + live hostile traffic).

Execution order is intentional: startup secret validation and request-boundary correctness land first so websocket, filesystem, proxy, and hostile-traffic verification work against stable fail-closed contracts instead of ambiguous baseline behavior.

## 4. Milestones

## 4.1 Phase 11A: Session + Bearer + CSRF Hardening

Status: complete (2026-03-06)

Deliverables:

- Replace custom session token signing/encryption with standard cryptography:
  - signed-cookie baseline: `HMAC-SHA256`
  - optional authenticated encryption path if confidentiality is required
- Remove insecure default session secret fallback; fail fast when secret is missing/weak.
- Enforce bearer-auth secret strength at startup:
  - require `auth.bearerSecret` when bearer auth is enabled
  - reject weak secrets with deterministic diagnostics
  - document random-secret generation guidance and minimum length expectations
- Use constant-time signature comparison.
- Make CSRF unsafe-method verification header/body-first by default; query fallback opt-in only.

Acceptance (required):

- `tests/unit/ApplicationTests.m`:
  - missing/weak session secret fails deterministic startup validation
  - weak bearer secret fails deterministic startup validation with targeted diagnostics
- `tests/unit/MiddlewareTests.m`:
  - tampered session cookie always rejected
  - unsafe request with query-only token is rejected by default
- No regression in valid session + CSRF nominal flow tests.

## 4.2 Phase 11B: HTTP Header + Parser Boundary Correctness

Status: complete (2026-03-06)

Deliverables:

- Central header name/value validation:
  - reject `\r`, `\n`, and NUL
  - enforce RFC token charset for header names
- Canonicalize header lookup/storage to case-insensitive behavior.
- Guarantee single semantic `Content-Length` and `Content-Type` emission.
- Harden redirect/header helper paths so user-controlled values cannot split responses.
- Make request framing fail closed on ambiguous transfer semantics:
  - reject duplicate `Content-Length`
  - reject any `Transfer-Encoding` mode the active parser does not fully implement
  - reject mixed `Content-Length` + `Transfer-Encoding`
  - ensure transport framing and app-visible header state derive from the same parse result
- Prefer the strict parser backend in production; if the legacy backend remains supported, keep it behind the same rejection contract or deprecate it.

Acceptance (required):

- `tests/unit/ResponseTests.m`:
  - CRLF header payload is rejected
  - case-variant duplicate content headers cannot produce conflicting output
- `tests/unit/RequestTests.m`:
  - duplicate `Content-Length` is rejected deterministically
  - unsupported `Transfer-Encoding` is rejected deterministically
  - mixed `Content-Length` + `Transfer-Encoding` is rejected deterministically
- Controller/integration tests verify redirects cannot emit injected headers and ambiguous requests cannot desynchronize framing from application-visible headers.

## 4.3 Phase 11C: WebSocket Protocol + Origin + Stall Resistance

Status: complete (2026-03-06)

Deliverables:

- Enforce handshake invariants:
  - `Sec-WebSocket-Version: 13`
  - valid base64 nonce decoding to 16 bytes
- Add optional websocket origin allowlist enforcement before upgrade:
  - missing or mismatched `Origin` is rejected when allowlist is configured
  - document cookie-authenticated deployment guidance
- Reject unmasked client-to-server frames.
- Add bounded receive deadline/retry budget for frame reads; close stalled sessions.

Acceptance (required):

- `tests/integration/HTTPIntegrationTests.m`:
  - invalid version/key handshake rejected
  - missing/mismatched websocket origin rejected when allowlist is active
  - unmasked frame rejected
  - partial-frame stall closes connection within configured timeout and server recovers

## 4.4 Phase 11D: Static + Attachment Filesystem Containment

Status: complete (2026-03-06)

Deliverables:

- Static mounts:
  - resolve candidate path by `realpath` before serve
  - verify resolved file remains under resolved mount root
  - add symlink-safe open strategy (`O_NOFOLLOW`/`openat` where available)
- Filesystem attachment adapter:
  - strict attachment ID format validation
  - root-constrained path resolution for read/delete/metadata operations
  - reject symlink-backed escape paths for attachment operations
- File-backed adapters (jobs/mail/attachments):
  - create directories with explicit private modes (`0700`)
  - create files with explicit private modes (`0600`)
  - verify existing storage paths are not broader than policy at startup and fail closed in production when permissions are too loose

Acceptance (required):

- `tests/integration/HTTPIntegrationTests.m`:
  - symlink escape attempt under static root is denied
- `tests/unit/Phase3ETests.m`:
  - attachment traversal payloads (for example `../`) are rejected
  - absolute-path and symlink escape attachment payloads are rejected
  - file-backed adapter directory/file modes match the private-storage policy

## 4.5 Phase 11E: Proxy Trust + Log Safety

Status: complete (2026-03-06)

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

Status: complete (2026-03-06)

Deliverables:

- Add dedicated hostile-input fixture corpus for Phase 11:
  - header injection probes
  - duplicate-header/canonicalization probes
  - duplicate `Content-Length`, unsupported `Transfer-Encoding`, and `Content-Length` + `Transfer-Encoding` ambiguity probes
  - websocket version/key/origin/mask/stall probes
  - traversal/symlink/path-format probes
  - private-permission policy probes where platform semantics permit deterministic assertions
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
   - duplicate `Content-Length`, unsupported `Transfer-Encoding`, and `Content-Length` + `Transfer-Encoding` ambiguity probes
   - websocket invalid key/version/origin/unmasked frames
   - partial-frame stall and timeout behavior
   - attachment traversal, absolute-path, and symlink escape attempts
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
   - duplicate `Content-Length`, unsupported `Transfer-Encoding`, and `Content-Length` + `Transfer-Encoding` probes
   - websocket origin-spoof/missing-origin plus partial/unmasked/malformed frame traffic
   - static path traversal and symlink probes
   - attachment traversal/symlink probes
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

## Summary
- Describe the change and the user-visible behavior.

## Validation
- [ ] `make test-unit`
- [ ] `make test-integration`
- [ ] `make test-data-layer` (or not applicable)
- [ ] `bash ./tools/ci/run_runtime_concurrency_gate.sh` (for HTTP/runtime/realtime changes)
- [ ] `make ci-sanitizers` (ASAN/UBSAN required for runtime changes)

## Concurrency Impact
- [ ] This change touches request/session lifecycle, shared mutable state, or worker/realtime paths.
- [ ] If checked, list affected files and the new invariants:

## Sanitizer Notes
- [ ] ASAN/UBSAN lane passed for this change.
- [ ] TSAN experimental lane reviewed (if run) and follow-up issues filed for any findings.

## Rollback Notes
- [ ] Rollback plan documented (revert commit(s), config fallback, and expected blast radius).
- [ ] If no rollback complexity, explicitly state why.

# Release Notes

## Upcoming Release Candidate

Certification evidence:

- Phase 9J certification pack: `build/release_confidence/phase9j/manifest.json`
- Phase 10E JSON performance pack: `build/release_confidence/phase10e/manifest.json`
- Release certification workflow: `make ci-release-certification`
- JSON performance workflow: `make ci-json-perf`
- Known risk register: [Known Risk Register](KNOWN_RISK_REGISTER.md)

## Notes

- Release candidates are incomplete unless the Phase 9J certification manifest status is `certified`.
- Release candidates are incomplete unless the Phase 10E JSON performance manifest status is `pass`.
- `tools/deploy/build_release.sh` enforces both requirements by default.

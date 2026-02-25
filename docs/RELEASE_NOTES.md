# Release Notes

## Upcoming Release Candidate

Certification evidence:

- Phase 9J certification pack: `build/release_confidence/phase9j/manifest.json`
- Release certification workflow: `make ci-release-certification`
- Known risk register: [Known Risk Register](KNOWN_RISK_REGISTER.md)

## Notes

- Release candidates are incomplete unless the Phase 9J certification manifest status is `certified`.
- `tools/deploy/build_release.sh` enforces this requirement by default.

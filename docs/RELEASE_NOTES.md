# Release Notes

## Upcoming Release Candidate

- Multipart limits accept bare or quoted decimal plist values without crashing
  the server. Invalid request limits now fail configuration loading with a keyed
  error; direct parser calls return an error instead of raising an exception.
- PostgreSQL job claims skip locked expired jobs and busy queue controls.
  Terminal cleanup is bounded to 100 jobs per poll, so unrelated work can proceed.

Certification evidence:

- Certification pack: `build/release_confidence/phase9j/manifest.json`
- JSON performance pack: `build/release_confidence/phase10e/manifest.json`
- Release certification workflow: `make ci-release-certification`
- JSON performance workflow: `make ci-json-perf`
- Known risk register: [Known Risk Register](KNOWN_RISK_REGISTER.md)

## Notes

- Release candidates are incomplete unless the certification manifest status is `certified`.
- Release candidates are incomplete unless the JSON performance manifest status is `pass`.
- `tools/deploy/build_release.sh` enforces both requirements by default.

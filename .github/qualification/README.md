# Disposable v0.3.2 native qualification harness

This branch is an evidence harness, not a release source change. The workflow checks out the full immutable `source_ref` separately on a fresh Ubuntu 24.04 ARM64 hosted VM. The strict lane preserves the maintained full sanitizer gates; the normal lane runs the unfiltered unit and integration suites against a private PostgreSQL socket and the maintained HTTP concurrency gate. Inventories, skip identities, and runtime lock digests are verified. No production host or OCI resources are used. Never merge this harness branch into the release.

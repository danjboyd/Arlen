# Disposable v0.3.2 native qualification harness

This branch is an evidence harness, not a release source change. The workflow checks out the full immutable `source_ref` separately on a fresh Ubuntu 24.04 ARM64 hosted VM. The strict lane preserves the maintained full sanitizer gates; the normal lane runs the unfiltered unit and integration suites against a private PostgreSQL socket and the maintained HTTP concurrency gate. Inventories, skip identities, and runtime lock digests are verified. No production host or OCI resources are used. Never merge this harness branch into the release.

The public lane refuses an incomplete or wrong latest release, then uses the default public installer without an archive or version override in a fresh pinned Ubuntu Minimal ARM64 container on the native VM. It preserves user-flow logs and the normal runtime controls/provenance. Dispatch this lane only after actual v0.3.2 assets are verified.

The normal harness builds the vendored XCTest runner serially before parallel framework compilation. Its separate XCTest and preload host libraries lack a parallel link dependency; this matches the serial runner preparation used by maintained CI and leaves release source untouched.

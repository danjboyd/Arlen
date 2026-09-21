# Changelog

All notable changes to Arlen are recorded in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
once it cuts a 1.0 release. Prior to 1.0, breaking changes may land on `main`
between any two commits; see [`docs/STATUS.md`](docs/STATUS.md) for the
current capability snapshot.

## [Unreleased]

### Fixed

- `ALNPg` connection pool no longer recirculates connections whose underlying
  socket has died. The pool now consults `PQstatus` (via a new
  `-isConnectionUsable` check) on both acquire and release, tears down
  libpq-marked-bad connections on the query-failure path, and creates a fresh
  connection in their place. The `connectionLivenessChecksEnabled` default is
  now `YES`. Regression tests cover the pool-eviction paths without requiring
  a live PostgreSQL instance.

### Changed

- Renamed `tools/ci/run_phase5e_quality.sh` to
  `tools/ci/run_linux_quality_gate.sh` to reflect its capability rather than
  its origin phase. A compatibility shim is retained for one release.
- Renamed `tools/ci/run_phase30_confidence.sh` to
  `tools/ci/run_apple_baseline_confidence.sh` with a matching compatibility
  shim.

## Releases

No tagged releases have been published yet. Pre-1.0 work happens on `main`;
deployment artifacts are produced from individual commits as needed.

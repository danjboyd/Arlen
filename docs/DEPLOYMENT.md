# Deployment Guide (Current Model)

Arlen is designed for deployment behind a reverse proxy.

## 1. Runtime Boundary

- Arlen handles HTTP application runtime.
- TLS/HTTPS termination is out of scope for framework runtime.
- Use nginx/apache/Caddy in front of Arlen for public ingress.

## 2. Server Roles

- `boomhauer`: development server
- `propane`: production manager (Phase 2A baseline)

All production manager settings are referred to as "propane accessories".

## 3. Recommended Production Topology

1. Run `propane` on loopback/private network.
2. Terminate TLS at reverse proxy.
3. Forward proxy headers.
4. Enable `trustedProxy` in Arlen only for trusted upstreams.

## 4. Propane Quick Start

From app root:

```bash
/path/to/Arlen/bin/propane --env production
```

Signals:
- `kill -HUP <pid>`: rolling reload
- `kill -TERM <pid>`: graceful shutdown

## 5. Example Config with Propane Accessories

```plist
{
  host = "127.0.0.1";
  port = 3000;
  logFormat = "json";
  serveStatic = NO;
  trustedProxy = YES;
  listenBacklog = 128;
  connectionTimeoutSeconds = 30;

  requestLimits = {
    maxRequestLineBytes = 4096;
    maxHeaderBytes = 32768;
    maxBodyBytes = 1048576;
  };

  propaneAccessories = {
    workerCount = 4;
    gracefulShutdownSeconds = 10;
    respawnDelayMs = 250;
    reloadOverlapSeconds = 1;
  };
}
```

## 6. Operational Recommendations

- Keep `serveStatic = NO` in production behind reverse proxy/CDN.
- Enforce request size limits (`requestLimits`) in app config.
- Use `logFormat = "json"` for production ingest.
- Pin explicit propane accessories instead of relying on implicit defaults.

## 7. Roadmap Target Contract (Planned)

The following deployment contract is accepted and tracked in roadmap documents. Some items are not fully implemented yet.

1. Packaging baseline: container-first path with first-class VM/systemd documentation.
2. Artifact model: immutable release artifacts for deterministic deploy and rollback.
3. Configuration model: plist + environment override runtime configuration, with no compile-time secrets.
4. Migration policy: explicit `arlen migrate` deployment step by default.
5. Availability baseline: zero-downtime rolling reload in `propane`.
6. Health model: readiness and liveness endpoints as first-class production contract.
7. Logging model: structured JSON logs to stdout/stderr in production.
8. Rollback model: first-class previous-release switch and restart workflow.

## 8. Current vs Target Snapshot

| Capability | Current state | Target phase |
| --- | --- | --- |
| Rolling reload in `propane` | Available | Phase 2A (complete) |
| Immutable release artifact workflow | Planned | Phase 2D |
| Explicit migration step in deploy runbook | Partial (`arlen migrate` exists) | Phase 2D |
| Readiness/liveness endpoint contract | Planned | Phase 2D |
| Rollback runbook/automation contract | Planned | Phase 2D-3C |
| Container + systemd reference deployment guides | Partial | Phase 2D-3C |

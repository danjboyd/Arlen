# GSWeb-to-Arlen Migration Guide

This guide provides the Phase 3C migration starter path from GNUstepWeb/legacy route patterns to Arlen.

## 1. Migration Strategy

Use side-by-side rollout:

1. Keep legacy endpoint behavior available.
2. Introduce Arlen-native routes with equivalent response contracts.
3. Validate parity with integration tests.
4. Decommission legacy endpoint aliases after compatibility window.

## 2. Side-by-Side Sample

Reference app:

- `examples/gsweb_migration/src/migration_sample_server.m`

Run:

```bash
make migration-sample-server
ARLEN_APP_ROOT=examples/gsweb_migration ./build/migration-sample-server --port 3126
```

Parity routes:

- `GET /legacy/users/:id`
- `GET /arlen/users/:id`

Both return identical payload:

```text
user:<id>
```

## 3. Config Mapping

Common mappings:

- legacy host/port settings -> `config/app.plist`
- process-manager knobs -> `propaneAccessories`
- stateful migration helpers -> `compatibility.pageStateEnabled` (opt-in)
- API docs exposure -> `openapi.*`

## 4. Incremental Cutover Checklist

1. Add Arlen route equivalent for each migrated endpoint.
2. Add integration assertions for legacy/new parity.
3. Keep legacy aliases during migration window.
4. Move clients to Arlen-native route names.
5. Remove legacy aliases in a major release.

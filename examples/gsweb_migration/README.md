# GSWeb Migration Sample

This sample demonstrates side-by-side equivalent behavior between a legacy-style route and an Arlen-native route.

The goal is migration confidence: both endpoints return the same payload contract while the app uses current Arlen runtime wiring.

## Run

```bash
make migration-sample-server
ARLEN_APP_ROOT=examples/gsweb_migration ./build/migration-sample-server --port 3126
```

## Side-by-side routes

- `GET /legacy/users/:id`
- `GET /arlen/users/:id`

Both return:

```text
user:<id>
```

## Additional endpoints

- `GET /healthz`
- `GET /openapi.json`
- `GET /openapi` (viewer style by default)

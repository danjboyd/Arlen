# Phase 28 Reference Server

This example is the live backend used by the Phase 28 TypeScript and React
integration lanes.

It keeps the contract explicit:

- `GET /api/session`
- `GET /api/users`
- `POST /api/users`
- `GET /api/users/:id`
- `PATCH /api/users/:id`
- `GET /ops/api/summary`
- `GET /search/api/capabilities`
- `GET /openapi.json`

Run it with:

```bash
source tools/source_gnustep_env.sh
make phase28-reference-server
ARLEN_APP_ROOT=examples/phase28_reference ./build/phase28-reference-server --port 3140
```

The repo-native Phase 28 CI scripts fetch `/openapi.json`, merge in the
checked-in Phase 28 `x-arlen` metadata, assert that the live exported contract
still matches the checked-in fixture, regenerate the TypeScript package, and
then run the live integration and React reference coverage against that server,
including CSRF-protected mutation flows.

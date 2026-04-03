# Phase 28 React Reference

This example shows the intended app-owned workflow for Phase 28
TypeScript/React consumption:

- generate descriptor-first contracts into a local folder
- import `models.ts`, `validators.ts`, `query.ts`, `client.ts`, `react.ts`,
  and `meta.ts` from that generated package
- keep React optional and downstream of Arlen ORM descriptors plus OpenAPI

This example keeps a deterministic checked-in workflow by default: its normal
`generate:arlen` script points at the repo's fixture ORM/OpenAPI inputs so the
package shape is reproducible from a clean checkout.

Phase `28J` also wires the same workspace into a live Arlen-backed lane. The
repo-native CI scripts now fetch `/openapi.json` from the dedicated
`examples/phase28_reference` server, merge the checked-in Phase 28 `x-arlen`
metadata, regenerate this workspace, and then run `typecheck` plus `build`.

## Layout

- `package.json`: local scripts for codegen, typecheck, and Vite
- `generated/`: app-owned target for `arlen typescript-codegen`
- `src/App.tsx`: example consumption of generated validators, query/resource
  metadata, client helpers, and optional React hooks

## Generate The Contracts

Build `arlen` first, then generate the local package:

```bash
source tools/source_gnustep_env.sh
cd examples/phase28_react_reference
npm install
npm run generate:arlen
```

To regenerate from a live Arlen app instead of the fixture contract, point the
same script at a merged OpenAPI file:

```bash
ARLEN_PHASE28_OPENAPI_INPUT=/tmp/phase28_live_openapi.json npm run generate:arlen
```

That writes:

- `examples/phase28_react_reference/generated/arlen/src/models.ts`
- `examples/phase28_react_reference/generated/arlen/src/validators.ts`
- `examples/phase28_react_reference/generated/arlen/src/query.ts`
- `examples/phase28_react_reference/generated/arlen/src/client.ts`
- `examples/phase28_react_reference/generated/arlen/src/react.ts`
- `examples/phase28_react_reference/generated/arlen/src/meta.ts`

## Run The Workspace

After generation, you can open the reference app locally:

```bash
cd examples/phase28_react_reference
VITE_ARLEN_BASE_URL=http://127.0.0.1:3000 npm run dev
```

The UI demonstrates:

- session bootstrap via generated module metadata and `useGetSessionQuery`
- user-list loading via generated `ArlenClient` plus `useListUsersQuery`
- create-form validation via generated `publicUserCreateFormFields` and
  `validatePublicUserCreateInput`
- admin/query affordances via generated resource metadata and
  `buildUsersQueryParams`

One intentional contract boundary is visible here: `query.ts` is additive UI
metadata. If you want generated select/include/filter/sort params to flow
directly into `client.ts` request types, those params still need to exist in
the OpenAPI operation schema itself.

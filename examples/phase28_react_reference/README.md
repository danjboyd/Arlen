# Phase 28 React Reference

This example shows the intended app-owned workflow for Phase 28
TypeScript/React consumption:

- generate descriptor-first contracts into a local folder
- import `models.ts`, `validators.ts`, `query.ts`, `client.ts`, `react.ts`,
  and `meta.ts` from that generated package
- keep React optional and downstream of Arlen ORM descriptors plus OpenAPI

This example is a checked-in reference workspace, not the Phase 28 live
integration lane yet. It uses the repo's fixture ORM/OpenAPI inputs so the
package shape is deterministic, but it is not wired into a backend app in
repo-wide CI yet. Phase `28J` will cover live integration and React reference
coverage.

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

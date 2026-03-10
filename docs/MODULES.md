# Modules

Phase 13 adds a first-class module layer above plugins.

Modules are:

- source-vendored into the app for deterministic builds
- described by `module.plist`
- loaded through explicit Objective-C protocols and principal classes
- allowed to own routes, templates, assets, migrations, and config defaults

## Runtime Model

- Plugins remain the low-level runtime seam.
- Modules are the higher-level product seam.
- Objective-C protocols define the contract.
- `NSBundle`-style resource ownership and deterministic app overrides define the resource story.

## Install Flow

```bash
./build/arlen module add auth --json
./build/arlen module add admin-ui --json
./build/arlen module add jobs --json
./build/arlen module add notifications --json
./build/arlen module add storage --json
./build/arlen module add ops --json
./build/arlen module add search --json
./build/arlen module migrate --env development --json
```

Useful commands:

- `arlen module list`
- `arlen module doctor`
- `arlen module assets`
- `arlen module upgrade`

Current first-party modules in-tree:

- `auth`
- `admin-ui`
- `jobs`
- `notifications`
- `storage`
- `ops`
- `search`

## Override Model

Apps should customize modules through explicit seams, not by forking internals:

- config defaults and path overrides
- hook classes
- resource provider classes
- module-owned `adminUI.resourceProviderClass` registration for shared admin surfaces
- template and asset override precedence

That keeps module upgrades tractable while still letting the app own its product decisions.

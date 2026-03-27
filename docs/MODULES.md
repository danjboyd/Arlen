# Modules

Modules are Arlen's higher-level product seam. Use them when you want vendored
routes, templates, assets, migrations, and config defaults that ship together
as one installable unit.

Modules are:

- source-vendored into your app for deterministic builds
- described by `module.plist`
- installed under `modules/<id>/`
- tracked in `config/modules.plist`

If you only need one app-local extension point or one service adapter, start
with `docs/PLUGIN_SERVICE_GUIDE.md` instead.

## 1. Typical Module Lifecycle

The normal path for first-party modules is:

```bash
./build/arlen module add auth
./build/arlen module add admin-ui
./build/arlen module doctor --json
./build/arlen module migrate --env development
./build/arlen module assets --output-dir build/module_assets
```

That sequence installs the module, validates it, applies migrations, and stages
its public assets.

## 2. Install a Module

```bash
./build/arlen module add auth --json
```

What `module add` does:

- vendors the module into `modules/<identifier>/`
- updates `config/modules.plist`
- preserves deterministic app-local ownership of the installed files

Current first-party modules in-tree:

- `auth`
- `admin-ui`
- `jobs`
- `notifications`
- `storage`
- `ops`
- `search`

## 3. List and Validate

Use these commands early:

```bash
./build/arlen module list --json
./build/arlen module doctor --json
```

`module doctor` checks:

- manifests
- dependency ordering
- compatibility
- required config keys
- public mount precedence

## 4. Run Module Migrations

```bash
./build/arlen module migrate --env development
```

Important example:

- run `module migrate` before the first local `auth` registration or login
  attempt

Module migrations are applied in dependency order and use the selected target
database in the same general way as normal Arlen migrations.

## 5. Stage Module Assets

```bash
./build/arlen module assets --output-dir build/module_assets
```

This stages module public assets into one deterministic output directory.

Override rule:

- app-owned assets under `public/modules/<id>/...` win over module defaults

## 6. Upgrade a Module

```bash
./build/arlen module upgrade auth --source /path/to/new/auth/module --json
```

Use `module upgrade` when you want to replace the vendored files with a newer
source tree and update the lock metadata in `config/modules.plist`.

## 7. Eject App-Owned Auth UI

Arlen currently supports one explicit UI eject flow:

```bash
./build/arlen module eject auth-ui --json
```

That scaffolds app-owned auth pages, fragments, partials, layout, and assets,
then updates `config/app.plist` for `generated-app-ui` mode.

Use this when you want the first-party auth product flows but want the HTML
templates to live in your app instead of the vendored module.

## 8. Remove a Module

```bash
./build/arlen module remove auth --json
```

Use `--keep-files` if you want to remove the lock/install entry without deleting
the vendored directory immediately.

## 9. Customization Without Forking

Prefer explicit seams over editing vendored internals directly:

- config defaults and path overrides
- hook classes
- resource provider classes
- app-owned template overrides under `templates/modules/<id>/...`
- app-owned asset overrides under `public/modules/<id>/...`
- module-owned resource-provider registration, such as shared admin resource
  hooks

That keeps upgrades tractable while still letting the app own its product
decisions.

## 10. Module vs Plugin

Use a module when you need:

- routes
- templates
- public assets
- migrations
- a reusable product surface

Use a plugin when you need:

- an app-local extension
- a service adapter
- bootstrap/lifecycle wiring without the full module lifecycle

## 11. Module-Specific Docs

- `docs/AUTH_MODULE.md`
- `docs/AUTH_UI_INTEGRATION_MODES.md`
- `docs/ADMIN_UI_MODULE.md`
- `docs/JOBS_MODULE.md`
- `docs/NOTIFICATIONS_MODULE.md`
- `docs/STORAGE_MODULE.md`
- `docs/OPS_MODULE.md`
- `docs/SEARCH_MODULE.md`

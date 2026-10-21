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

For production password-reset and verification mail, also install `jobs`,
configure its PostgreSQL adapter and worker, and set
`authModule.publicBaseURL`; see [Auth Module](AUTH_MODULE.md).

That sequence installs the module, validates it, applies migrations, and stages
its public assets.

## 2. Install a Module

```bash
./build/arlen module add auth --json
```

What `module add` does:

- vendors the module into `modules/<identifier>/`
- updates `config/modules.plist`, including a `contentDigest` of the installed
  files
- preserves deterministic app-local ownership of the installed files

Current first-party modules in-tree:

- `auth`
- `admin-ui`
- `jobs`
- `notifications`
- `storage`
- `ops`
- `search`
- `mcp`

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
- vendored files that were edited locally, lack a recorded `contentDigest`, or
  differ from the framework checkout's copy of the module (warnings)
- a module whose defaults enable sessions while `config/app.plist` sets
  `session.enabled = NO`, as the `arlen new` app.plist does
  (`module_sessions_disabled`, a warning): remove that line before relying on
  the module's sessions

`module doctor` validates configuration statically. The app itself loads and
configures each module when it starts, in dependency order:

- If a module fails to load or configure (a missing required setting, an
  invalid value), loading stops at that module. The error names the module,
  the config key when the module reports one, and the modules that were not
  loaded after it.
- Outside the `development` and `test` environments, the app then refuses to
  start: the server (`boomhauer`, `propane` workers) and `jobs-worker` exit
  non-zero with `startup failed: module <id> failed to load: <reason>`.
- In `development` and `test`, the app keeps serving so you can fix the
  config, and logs `module load failed` at error level with the same fields.

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

**Upgrading Arlen does not upgrade your modules.** `module add` copies a
module's sources into your app (`modules/<id>`), and `boomhauer`, `propane`
and `jobs-worker` compile that copy. After you move to a newer framework, the
app keeps running the old module code until you re-vendor each module:

```bash
./build/arlen module upgrade <id>    # for each installed module
./build/arlen module migrate         # apply any new module migrations
# then rebuild and restart (boomhauer rebuilds on its next start)
```

`arlen doctor` and `arlen module doctor` report `module_outdated` for every
vendored module whose framework copy has a newer version, and the app logs
`vendored module is older than the framework copy` at startup (outside the
`test` environment) when it runs under `boomhauer`, `propane` or
`jobs-worker`, which export `ARLEN_FRAMEWORK_ROOT` to it. The check compares
numeric versions component by component (`1.10.0` is newer than `1.9.0`).
Module versions must be plain `MAJOR.MINOR[.PATCH]` numbers: the module system
refuses a `module.plist` with a pre-release suffix such as `1.2.0-rc1`, and the
doctors skip a copy whose version they can't read rather than guess.

Re-run it for every installed module whenever you move your framework pin.
First-party module sources can change without a `version` bump, so `upgrade`
compares file contents:

- files already match the source: `noop`
- the vendored copy is unedited since install: it is replaced (`updated`)
- the vendored copy was edited locally, or the lock predates `contentDigest`:
  the command exits 1 with `content_differs` and lists the differing files;
  review them, then re-run with `--force`

An upgrade keeps the app's own settings in the lock entry, such as `enabled =
0`, and stamps the copied files with the install time so the next incremental
build recompiles them.

Before Arlen recorded `contentDigest`, `module upgrade` reported `noop` whenever
the version matched, even when the module sources had changed. Apps that
vendored modules and upgraded that way may still carry old module code; run
`module doctor` from the app with `ARLEN_FRAMEWORK_ROOT` pointing at your
framework checkout to find them.

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

## First-party module versions

Each first-party module's `version` changes whenever its files change, so the
version in `config/modules.plist` tells you which module code an app vendors:

- patch (`1.0.1`): internal fixes with no configuration or API change
- minor (`1.1.0`): new features, security fixes, or new required configuration
- major (`2.0.0`): removed or incompatible APIs

CI enforces this with `tools/ci/check_module_versions.py`. Framework
contributors can run it locally before opening a PR:

```bash
python3 tools/ci/check_module_versions.py --base origin/main
```

Module versions first changed on 2026-09-25: `auth` and `storage` moved to
`1.1.0` (OIDC providers; required storage signing secret), and `admin-ui`,
`ops`, and `search` moved to `1.0.1`. `jobs` and `notifications` moved to
`1.0.1` for app-root-relative module state paths (GitHub issue 76).
`auth` moved to `1.2.0` to serve its UI assets under `paths.prefix` (GitHub
issue 51).
`auth` moved to `1.3.0` to keep post-login `return_to` redirects on the app's
origin (a security fix; cross-origin returns now go through the session policy
hook).
`auth` moved to `1.4.0` for the configurable step-up target
(`authModule.paths.stepUp`, GitHub issue 97); `admin-ui`, `jobs`,
`notifications`, `ops` and `search` moved to `1.0.2` and `storage` to `1.1.1` to
send step-up there.
`auth` moved to `1.5.0` for provider `assurance` mapping from `amr`/`acr`
(GitHub issue 98).
`mcp` moved to `1.0.2` so a disabled module stays inert at startup (GitHub issue
105).
`auth` moved to `1.5.1` and `mcp` to `1.0.3` so booleans are detected correctly
on Apple arm64 (GitHub issue 132).
`notifications` moved to `1.1.0` for the Web Push channel, and `jobs` to `1.1.0`
for `ALNJobsModuleRetryAfterSecondsErrorKey`, which `notifications` now requires
(GitHub issue 173).
`search` moved to `1.0.3` to bound query cost (GitHub issue 226).
`notifications` moved to `1.1.2` for outbox/inbox caps, inbox pagination and
preference validation (GitHub issue 227).
`mcp` moved to `1.0.5` to filter `tools/list` by role and scope, and `auth` to
`1.5.2` to equalize unknown-email login timing (GitHub issue 228).
`admin-ui` and `ops` moved to `1.0.3`, `auth` to `1.5.3`, `jobs` to `1.1.1`,
`notifications` to `1.1.3`, `search` to `1.0.4` and `storage` to `1.1.2` so
numbers given as strings (query parameters, old-style plists) are read on Apple
too (GitHub issue 264).
`storage` moved to `1.2.0` to refuse placeholder and published example
`storageModule.signingSecret` values outside development and test.
`storage` moved to `1.3.0` so downloads are attachments with a sandbox policy
unless the type is a passive image, PDF, audio or video type, and so wildcard
accepted types no longer match HTML or SVG (a security fix).
`search` moved to `1.1.0` to encode engine URL path segments with only
unreserved characters and reject empty, `.` and `..` record identifiers and
index names (a security fix).
`auth` moved to `1.5.4`, `jobs` to `1.1.2`, `notifications` to `1.1.4`,
`search` to `1.0.5` and `storage` to `1.1.3` to classify the environment with
the framework's shared helper, so environment names match regardless of case
(GitHub issue 294).
`auth` moved to `1.7.0` to reject production registration auto-login and
request-time auth mail. Its `1.6.0` change refuses reused TOTP codes, limits failed TOTP and
recovery-code attempts per account, slow down repeated failed password
sign-ins, and accept recovery codes at the TOTP challenge. It adds migration `004_auth_totp_limits`; run
`arlen module migrate` after upgrading.
`notifications` moved to `1.3.0` for per-record SQLite persistence and one-time
legacy import; stop old workers and follow the [migration/backup guide](NOTIFICATIONS_MODULE.md#incremental-persistence-and-upgrading).
Its `1.2.0` change ensures `POST /notifications/api/queue` queues
only for the signed-in user unless the caller has the `admin` role at AAL2.
`ops` moved to `1.1.0` for cross-process dashboard history transactions.
`search` moved to `1.2.1` so promotions honor explicit and per-resource query
filters. Its `1.2.0` change added shared-state transactions, replay protection,
and the security fixes below. Upgrade vendored copies with `arlen module upgrade`.
`auth` remains at `1.6.0`, while `admin-ui`
moved to `1.1.0` for the following security fixes and configuration:

- `auth`: the stub provider is development/test only; password-reset and
  verification links are single-use; those links are built from the new
  `authModule.publicBaseURL`; and session roles are resolved from the current
  user record on every request (new migration `002_auth_session_stamp.sql`,
  recommended for ending sessions by stamp; roles are read live without it).
  Signing out ends the session server-side (new migration
  `003_auth_revoked_sessions.sql`, recommended), password changes and resets
  end other sessions, `POST /auth/logout/all` signs out everywhere, and
  `authModule.session.absoluteLifetimeSeconds` limits a sign-in's lifetime.
- `search`: an unscoped query from a caller who may query no registered
  resource returns no results, and auto-indexed `admin-ui` resources are
  searchable only by callers the `admin-ui` policy admits (new
  `queryMinimumAuthAssuranceLevel` resource metadata); its role checks use
  `+[ALNAuth context:hasAnyRole:]` and so the user's current roles.
- `admin-ui`: reports its access policy (`accessRoles`,
  `minimumAuthAssuranceLevel`) and ends a user's sessions when the admin role
  is revoked; it requires `auth` `>= 1.6.0`.

## MCP tools

The optional `mcp` module is disabled by default. It exposes only explicitly
registered route-backed and service-backed tools. See [MCP Module](MCP_MODULE.md)
for installation, schemas, auth, and compatibility.

The `ops` module resolves optional module runtimes at runtime. A partial
installation can build without auth, jobs, notifications, storage, or search.
Absent summary providers are reported as unavailable; authorization remains
required. See [Ops Module](OPS_MODULE.md).

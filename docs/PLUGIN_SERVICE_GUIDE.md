# Plugin + Service Guide

Use `arlen generate plugin` when you want to add a project-local plugin or a
custom service adapter without turning the work into a full module.

Modules are the higher-level product seam. Plugins are the lighter-weight app
extension seam.

## 1. Generate a Plugin

From app root:

```bash
/path/to/Arlen/bin/arlen generate plugin RedisCache --preset redis-cache
/path/to/Arlen/bin/arlen generate plugin QueueJobs --preset queue-jobs
/path/to/Arlen/bin/arlen generate plugin SmtpMail --preset smtp-mail
```

Available presets:

- `generic`
- `redis-cache`
- `queue-jobs`
- `smtp-mail`

## 2. Files the Generator Creates

The plugin generator writes:

- `src/Plugins/<Name>Plugin.h`
- `src/Plugins/<Name>Plugin.m`

It also updates `config/app.plist` so the generated plugin class is listed under
`plugins.classes`.

That means the plugin will be registered as part of normal app startup once the
app is rebuilt.

## 3. What the Generated Plugin Gives You

Every generated plugin implements the normal Arlen plugin contract:

- `pluginName`
- `registerWithApplication:error:`
- optional lifecycle hooks such as `applicationDidStart:` and
  `applicationWillStop:`

The preset-specific files are intentionally compile-safe templates, not
production-ready adapters. They give you the right seam and a working fallback,
then leave the real backend integration for you to finish.

## 4. Preset Expectations

`redis-cache`

- starts with an in-memory cache fallback
- switches to `ALNRedisCacheAdapter` when `ARLEN_REDIS_URL` is set
- good fit when you want a cache adapter quickly and already have Redis

`queue-jobs`

- starts with file-backed jobs when storage is configured successfully
- falls back to in-memory jobs if file-backed setup fails
- creates a simple `ALNJobWorkerRuntime` template hook
- useful env vars in the generated template include:
  - `ARLEN_JOB_STORAGE_PATH`
  - `ARLEN_JOB_WORKER_INTERVAL_SECONDS`
  - `ARLEN_JOB_WORKER_RETRY_DELAY_SECONDS`

`smtp-mail`

- starts with a file-backed mail adapter template
- leaves a clear hook where you can replace that with real SMTP/API delivery
- useful env vars in the generated template include:
  - `ARLEN_SMTP_HOST`
  - `ARLEN_SMTP_PORT`
  - `ARLEN_MAIL_STORAGE_DIR`

`generic`

- gives you the minimum plugin skeleton when none of the presets fit

## 5. Typical Workflow

1. Generate the closest preset.
2. Open `src/Plugins/<Name>Plugin.m`.
3. Replace the template fallback/path hooks with your real backend client.
4. Rebuild and run the app.
5. Verify the plugin shows the behavior you expect in a normal request flow.

Use `arlen check` and your normal app tests after wiring real backend behavior.

## 6. Plugin vs Module

Prefer a plugin when:

- the behavior is app-local
- you are replacing one adapter or adding one bootstrap hook
- you do not need vendored templates, assets, migrations, or routes

Prefer a module when:

- you want installable product behavior with routes, templates, assets, or
  migrations
- you expect reuse across multiple apps
- you need module lifecycle commands (`add`, `migrate`, `assets`, `upgrade`,
  `eject`)

## 7. Related Guides

- `docs/MODULES.md`
- `docs/ECOSYSTEM_SERVICES.md`
- `docs/CONFIGURATION_REFERENCE.md`

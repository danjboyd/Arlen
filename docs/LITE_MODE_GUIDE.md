# Lite Mode Guide

Lite mode is Arlen's smallest app shape. It uses the same runtime as full mode,
but starts from a single-file entrypoint instead of the usual `src/main.m` plus
controller tree.

## 1. When Lite Mode Fits

Choose lite mode when you want:

- a quick prototype
- a docs/demo app
- a small internal tool
- the fastest path to one or two routes

Stay with full mode when you already know you need:

- several controllers
- first-party module adoption
- a larger team-owned app structure
- more obvious long-term separation between bootstrap and feature code

## 2. Create a Lite App

```bash
mkdir -p ~/arlen-apps
cd ~/arlen-apps
/path/to/Arlen/bin/arlen new MyLiteApp --lite
cd MyLiteApp
/path/to/Arlen/bin/arlen boomhauer --port 3000
```

Generated files:

- `app_lite.m`
- `config/app.plist`
- `templates/index.html.eoc`
- `public/health.txt`
- `README.md`

## 3. What `app_lite.m` Looks Like

The generated file contains:

- one small controller class
- one `RegisterRoutes` function
- one `main(...)` that calls `ALNRunAppMain`

That is the whole app shape. There is no separate lite runtime.

## 4. Add Another Route

Lite apps can still use the normal generator path:

```bash
/path/to/Arlen/bin/arlen generate endpoint Hello \
  --route /hello \
  --method GET \
  --template
```

That generator path:

- creates `src/Controllers/HelloController.{h,m}`
- wires the route into `app_lite.m`
- creates `templates/hello/index.html.eoc`

So you can start small without giving up the normal controller/template
workflow.

## 5. Working Style

A good lite-mode progression is:

1. keep the app in `app_lite.m` while you are proving the route shape
2. use generated controllers/templates as the app grows
3. split more logic into `src/Controllers/...` and supporting files
4. move to a full-mode structure once the single-file bootstrap stops helping

There is no automatic lite-to-full conversion command today. The migration path
is structural, not magical: move routes and bootstrap code into the usual
`src/main.m` shape and keep the same controllers, templates, and config.

## 6. Full vs Lite at a Glance

- full mode: better default for long-lived applications
- lite mode: better default for quick experiments and very small apps
- both modes: same `boomhauer`, same controllers, same templates, same config
  format, same runtime behavior

## 7. Related Guides

- `docs/FIRST_APP_GUIDE.md`
- `docs/APP_AUTHORING_GUIDE.md`
- `docs/CONFIGURATION_REFERENCE.md`
- `docs/internal/LITE_MODE_SPEC.md`

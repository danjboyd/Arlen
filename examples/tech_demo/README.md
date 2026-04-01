# Arlen Technology Demo Site

This demo runs on the same runtime and now shows MVC + EOC + implicit JSON +
Phase 25 live UI in one place.
All demo source lives under `examples/tech_demo`:

- `examples/tech_demo/src/tech_demo_server.m`
- `examples/tech_demo/templates/`
- `examples/tech_demo/public/`
- `examples/tech_demo/config/`

## Run

```bash
./bin/tech-demo
```

Then open `http://127.0.0.1:3110/tech-demo`.

For the live UI example page, open `http://127.0.0.1:3110/tech-demo/live`.

## Single Import

For server applications, use one header:

```objc
#import "ArlenServer.h"
```

This imports the POSIX networking headers plus the main Arlen framework headers.

## Demo Endpoints

- `GET /tech-demo`
  - landing page with template-owned layout, named slot, and collection partial rendering
- `GET /tech-demo/dashboard?tab=router`
  - table rendering through collection partials
- `GET /tech-demo/live`
  - Phase 25 live example page with live filters, live regions, upload
    progress, keyed feed updates, and websocket fanout
- `GET /tech-demo/live/orders`
  - live fragment endpoint for the orders region
- `GET /tech-demo/live/pulse`
  - polling live region endpoint
- `GET /tech-demo/live/insights`
  - lazy live region endpoint
- `GET /tech-demo/live/deferred`
  - deferred live region endpoint
- `POST /tech-demo/live/upload`
  - upload-progress-aware live fragment endpoint
- `GET /tech-demo/live/feed/publish`
  - keyed feed upsert + websocket publish path
- `GET /tech-demo/live/feed/remove`
  - keyed feed removal + websocket publish path
- `GET /ws/channel/tech_demo.live`
  - websocket channel used by the live feed example
- `GET /tech-demo/users/peggy?flag=admin`
  - route param + query param rendering with slot-filled request recap
- `GET /tech-demo/api/catalog`
  - implicit JSON from `NSArray`
- `GET /tech-demo/api/summary?view=full`
  - implicit JSON from `NSDictionary`
- `GET /static/tech_demo.css`
  - static asset served by `tech-demo-server` from `examples/tech_demo/public/`

## Why this is useful

It exercises the pieces needed for real apps:

- route dispatch and controller actions
- template rendering with first-class layouts, named slots, and partial collections
- fragment-first live UI with keyed updates, region hydration, and runtime-served JS
- implicit JSON API responses
- static asset serving in dev mode
- request metadata and query handling

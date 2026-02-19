# Arlen Technology Demo Site

This demo runs on the same Phase 1 runtime and shows MVC + EOC + implicit JSON in one place.
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

## Single Import

For server applications, use one header:

```objc
#import "ArlenServer.h"
```

This imports the POSIX networking headers plus the main Arlen framework headers.

## Demo Endpoints

- `GET /tech-demo`
  - landing page with layout + partial + list rendering
- `GET /tech-demo/dashboard?tab=router`
  - table rendering with looped data
- `GET /tech-demo/users/peggy?flag=admin`
  - route param + query param rendering
- `GET /tech-demo/api/catalog`
  - implicit JSON from `NSArray`
- `GET /tech-demo/api/summary?view=full`
  - implicit JSON from `NSDictionary`
- `GET /static/tech_demo.css`
  - static asset served by `tech-demo-server` from `examples/tech_demo/public/`

## Why this is useful

It exercises the pieces needed for real apps:

- route dispatch and controller actions
- template rendering with layouts and partials
- implicit JSON API responses
- static asset serving in dev mode
- request metadata and query handling

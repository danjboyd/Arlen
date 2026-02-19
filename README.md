# Arlen

Arlen is a GNUstep-native Objective-C web framework with an MVC runtime, EOC templates (`.html.eoc`), and a developer server (`boomhauer`).

Arlen is designed to solve the same class of problems as frameworks like Mojolicious while staying idiomatic to Objective-C/GNUstep conventions.

## Status

- Phase 1: complete and working.
- Phase 2A: complete (`propane` + runtime hardening).
- Phase 2B: complete (PostgreSQL adapter, migrations, sessions/CSRF/rate-limit/security headers).
- Phase 2C: complete (developer error UX + validation + timing controls).
- Phase 2D: complete (parity baseline + deployment contract + perf gate hardening).
- Phase 3A: complete (metrics, schema/auth contracts, OpenAPI baseline, plugins/lifecycle).
- Phase 3B: complete (data-layer maturation, interactive OpenAPI explorer, GSWeb compatibility helpers).
- Phase 3C-3E: planned (`docs/PHASE3_ROADMAP.md`).

## Quick Start

Prerequisites:
- GNUstep toolchain installed
- `tools-xctest` installed (provides `xctest`)

Initialize GNUstep in your shell:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
```

Build framework tools and dev server:

```bash
make all
```

Run the built-in development server:

```bash
./bin/boomhauer
```

Create and run your first app with the CLI:

```bash
mkdir -p ~/arlen-apps
cd ~/arlen-apps
/path/to/Arlen/bin/arlen new MyApp
cd MyApp
/path/to/Arlen/bin/arlen boomhauer --port 3000
```

Run tests and quality gate:

```bash
./bin/test
make check
```

Run the technology demo:

```bash
./bin/tech-demo
```

Then open `http://127.0.0.1:3110/tech-demo`.

## Documentation

Start here:
- [Docs Index](docs/README.md)

Generate browser-friendly HTML docs:

```bash
make docs-html
```

Open `build/docs/index.html` in a browser.

High-value guides:
- [First App Guide](docs/FIRST_APP_GUIDE.md)
- [Getting Started](docs/GETTING_STARTED.md)
- [CLI Reference](docs/CLI_REFERENCE.md)
- [Core Concepts](docs/CORE_CONCEPTS.md)
- [Deployment Guide](docs/DEPLOYMENT.md)
- [Propane Manager](docs/PROPANE.md)
- [Documentation Policy](docs/DOCUMENTATION_POLICY.md)

Specifications and roadmaps:
- [Phase 1 Spec](docs/PHASE1_SPEC.md)
- [Phase 2 Roadmap](docs/PHASE2_ROADMAP.md)
- [Phase 3 Roadmap](docs/PHASE3_ROADMAP.md)
- [EOC v1 Spec](V1_SPEC.md)

## Naming

- Development server: `boomhauer`
- Production manager: `propane`
- All `propane` settings are referred to as "propane accessories"

## License

Arlen is licensed under the GNU Lesser General Public License, version 2 or (at your option) any later version (LGPL-2.0-or-later), aligned with GNUstep Base library licensing.

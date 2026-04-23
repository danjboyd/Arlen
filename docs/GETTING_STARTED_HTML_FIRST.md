# Getting Started: HTML-First Track

This track optimizes for server-rendered pages with EOC templates and controller-driven view models.

## 1. Scaffold App

```bash
/path/to/Arlen/bin/arlen new WebApp
cd WebApp
```

## 2. Generate Page Endpoint with Template

```bash
/path/to/Arlen/bin/arlen generate endpoint Dashboard \
  --route /dashboard \
  --method GET \
  --template
```

## 3. Render Template from Controller

Use controller rendering helpers:

- `renderTemplate:context:error:`
- `renderTemplate:context:layout:error:`
- `renderTemplate:context:layout:strictLocals:strictStringify:error:`
- `renderTemplate:context:layout:defaultLayoutEnabled:strictLocals:strictStringify:error:`

Use stash/context patterns for view model data:

- `stashValue:forKey:`
- `stashValues:`

EOC render behavior:

- template and layout names normalize to logical `.html.eoc` paths, so `dashboard` and `layouts/main` are valid inputs
- when `layout:nil` and `defaultLayoutEnabled:YES`, `ALNView` resolves the template's registered static layout automatically
- when a layout is rendered, the page body is exposed as the `content` slot and named slots/yields remain available for composition
- `strictLocals:YES` fails on unresolved sigil locals and missing keypath segments
- `strictStringify:YES` fails when expression output is not clearly string-convertible

## 4. Validate Form Input

Use parameter helpers:

- `stringParamForName:`
- `requireStringParam:value:`
- `requireIntegerParam:value:`

When validation fails:

- add errors with `addValidationErrorForField:code:message:`
- return `renderValidationErrors` (JSON/API paths) or template error state for HTML forms

## 5. Run and Inspect

```bash
/path/to/Arlen/bin/arlen boomhauer --port 3000
curl -i http://127.0.0.1:3000/dashboard
```

## 6. Template Tooling

Use EOC tooling for deterministic compile diagnostics:

```bash
make eocc
make transpile
./build/eocc --template-root templates --output-dir build/gen/templates --manifest build/gen/templates/manifest.json templates/index.html.eoc
```

The direct `eocc` workflow supports manifest-backed incremental reuse/removal accounting and optional custom logical-path prefixes/registry output when you are debugging app or module template trees.

For the full template language reference, composition syntax, escaping rules,
strict modes, and authoring patterns, start with `docs/EOC_GUIDE.md`.

For API-level details see:

- [ALNEOCTranspiler](api/ALNEOCTranspiler.md)
- [ALNView](api/ALNView.md)

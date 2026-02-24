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

Use stash/context patterns for view model data:

- `stashValue:forKey:`
- `stashValues:`

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
```

For API-level details see:

- [ALNEOCTranspiler](api/ALNEOCTranspiler.md)
- [ALNView](api/ALNView.md)

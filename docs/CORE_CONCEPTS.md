# Core Concepts

This guide explains Arlen's runtime model at a high level.

## 1. Request Lifecycle

1. `ALNHTTPServer` accepts an HTTP request.
2. Request is parsed into `ALNRequest`.
3. `ALNRouter` matches method/path to a route.
4. `ALNApplication` dispatches to controller action.
5. Controller writes response directly or returns `NSDictionary`/`NSArray` for implicit JSON.
6. `ALNResponse` is serialized and sent.

## 2. Core Types

- `ALNApplication`: app composition root; owns routes, config, middleware.
- `ALNHTTPServer`: network loop and request handling.
- `ALNRouter` / `ALNRoute`: route registration and matching.
- `ALNController`: base controller with render helpers.
- `ALNContext`: request-scoped object (`request`, `response`, `params`, `stash`, logging/perf references).
- `ALNRequest`: parsed request model.
- `ALNResponse`: mutable response builder.

## 3. EOC Templates

Template extension:
- `.html.eoc`

Supported tags:
- `<% code %>`: Objective-C statements
- `<%= expr %>`: HTML-escaped expression output
- `<%== expr %>`: raw expression output
- `<%# comment %>`: ignored template comment

Transpiler/runtime:
- `tools/eocc` transpiles templates to Objective-C source.
- `ALNEOCRuntime` provides rendering and include support.

## 4. JSON Response Behavior

If controller action returns an `NSDictionary` or `NSArray` and no explicit body has been committed:
- Arlen serializes it to JSON implicitly.
- `Content-Type` is set to `application/json; charset=utf-8`.
- Controller class may override JSON options via `+jsonWritingOptions`.

## 5. Configuration Model

Config is loaded from:
- `config/app.plist`
- `config/environments/<environment>.plist`

Environment variables may override key values (`ARLEN_*`).

## 6. Development vs Production Naming

- Development server: `boomhauer`
- Production process manager: `propane`
- `propane` config is called "propane accessories"

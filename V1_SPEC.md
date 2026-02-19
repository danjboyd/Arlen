# Arlen EOC Template Engine v1 Specification

Status: Draft v1
Target: GNUstep + Objective-C

## 1. Purpose

Define a first working version of an EOC (Encapsulated Objective-C) HTML template system for Objective-C/GNUstep that compiles `.html.eoc` templates into Objective-C source files.

v1 is focused on correctness, diagnostics, and build integration. It is not yet a full app server.

## 2. Scope

### In Scope (v1)

- `.html.eoc` template syntax with Objective-C code blocks.
- A template transpiler that converts template text into Objective-C `.m` files.
- Build-time integration with `gnustep-make`.
- HTML escaping by default for expression output.
- Optional raw output for trusted content.
- Template partial includes.
- Error mapping from generated code back to template file and line.

### Out of Scope (v1)

- Runtime compilation/reload server mode.
- Automatic layout inheritance system.
- Sandbox or untrusted-template execution model.
- Full HTTP routing/controller framework.

## 3. Template Syntax

Template files use `.html.eoc`.

Supported tags:

- `<% code %>`: Insert raw Objective-C statements.
- `<%= expr %>`: Evaluate expression and append HTML-escaped output.
- `<%== expr %>`: Evaluate expression and append raw output.
- `<%# comment %>`: Template comment, ignored.

### Example

```html
<h1><%= [ctx title] %></h1>
<ul>
<% for (NSString *item in [ctx items]) { %>
  <li><%= item %></li>
<% } %>
</ul>
```

## 4. Rendering Contract

Each template compiles into one render function with a deterministic symbol name.

Proposed signature:

```objc
NSString *ALNEOCRender_templates_index_html_eoc(id ctx, NSError **error);
```

Behavior:

- Returns rendered HTML string on success.
- Returns `nil` on failure and fills `error` when available.
- Uses `NSMutableString` as output buffer.

Context model:

- `ctx` is object-based (`id`) to allow idiomatic Objective-C method calls.
- Optional helper protocol(s) may be added later, but v1 does not require strict protocol conformance.

## 5. Escaping Rules

- `<%= expr %>` must HTML-escape `&`, `<`, `>`, `"`, and `'`.
- `<%== expr %>` performs no escaping.
- `nil` expression output appends empty string.
- Non-string objects are converted using `-[NSObject description]`.

Escaping helper (v1) will live in runtime support code, called by generated templates.

## 6. Partials

v1 supports partial include through generated helper calls.

Template usage example:

```html
<% ALNEOCInclude(out, ctx, @"partials/_nav.html.eoc", error); %>
```

Behavior:

- Include resolves using configured template root.
- Include shares the same `ctx`.
- Include failure bubbles up via `error`.

## 7. Transpiler Behavior

Transpiler input:

- Source template path (`.html.eoc`)

Transpiler output:

- Generated `.m` file containing render function.

Implementation requirements:

- Use a deterministic state machine parser (TEXT, TAG).
- Do not rely on regex-only parsing.
- Support multiline code and expressions.
- Emit `#line` directives before generated chunks to preserve template file/line diagnostics.

Parsing errors must include:

- Template path
- Line number
- Column number (if known)
- Human-readable reason (e.g., unclosed tag)

## 8. Build Integration (gnustep-make)

v1 build pipeline:

1. Collect all `templates/**/*.html.eoc`.
2. Run transpiler to emit generated `.m` into a build directory (for example `build/gen/templates`).
3. Add generated `.m` files to normal Objective-C compilation inputs.
4. Link with runtime support module (escape helpers, include dispatch).

Rules:

- Generated code is build output and should not be committed.
- Build should fail fast if transpilation fails.

## 9. File and Naming Conventions

- Source templates: `templates/**/*.html.eoc`
- Generated files: `build/gen/templates/**/*.eoc.m`
- Generated symbol format: `ALNEOCRender_<sanitized_template_path>`
- Runtime support code location (planned): `src/Arlen/MVC/Template/`

Extension rules:

- v1 canonical view extension is `.html.eoc`.
- Future content types may use `.json.eoc`, `.txt.eoc`, etc.

Sanitization rules:

- Replace non-alphanumeric characters with `_`.
- Preserve deterministic mapping across builds.

## 10. Security Model

Templates are trusted code in v1.

Implications:

- Any valid Objective-C in templates executes with process privileges.
- No sandboxing guarantees.
- Raw output tag `<%== ... %>` must be used carefully.

## 11. v1 Acceptance Criteria

- Can render a template with plain text, control flow, and expression output.
- `<%= ... %>` escapes correctly.
- `<%== ... %>` outputs raw string.
- Partial include works.
- Compiler/transpiler errors point to original template lines.
- Example app template compiles and runs through GNUstep build.

## 12. Milestones

1. Parser + transpiler CLI prototype for one template.
2. Runtime helpers (escape + include dispatch).
3. `gnustep-make` prebuild integration.
4. Unit + fixture tests for parser and generated code.
5. Example MVC-style app skeleton using compiled templates.

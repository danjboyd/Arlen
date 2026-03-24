# Template Troubleshooting

Use this workflow when `.html.eoc` transpilation or rendering does not behave as expected.

## 1. Run Targeted Transpile

```bash
./build/eocc \
  --template-root templates \
  --output-dir build/gen/templates \
  --manifest build/gen/templates/manifest.json \
  templates/index.html.eoc
```

If transpilation fails, `eocc` prints deterministic location data:

- `path=<logical_path>`
- `line=<line>`
- `column=<column>`

Useful tooling notes:

- `--manifest` turns on manifest-backed incremental transpilation so unchanged outputs are reused and stale generated files are removed
- manifest-backed runs print `transpiled <n> templates (reused <n>, removed <n>)`
- if you need explicit registry output from a direct `eocc` run, add `--registry-out <path>`
- if you are checking module template trees, add `--logical-prefix modules/<module_id>` so logical paths match runtime lookup

Static composition validation also fails the transpile before code generation when:

- a `layout`, `include`, `render`, or `empty:` partial path does not exist in the current template set
- layouts/includes/renders create a static composition cycle
- template references are normalized to `.html.eoc`, so unsuffixed logical names are the intended form in directives and `ALNView` calls

## 2. Interpret Common Errors

- `Unclosed EOC tag`
  - check `<% ... %>` delimiters around the reported location.
- `Expression tag cannot be empty`
  - ensure `<%= ... %>` and `<%== ... %>` contain a non-empty expression.
- `Invalid sigil local`
  - ensure sigil usage follows `$identifier` with `[A-Za-z_][A-Za-z0-9_]*`.
- `Multiple layout directives are not allowed`
  - keep each template to one static `<%@ layout "..." %>` declaration.
- `Unclosed slot directive`
  - ensure every `<%@ slot "..." %>` has a matching `<%@ endslot %>`.

## 3. Address Lint Warnings

`eocc` warning output format:

- `eocc: warning path=<path> line=<line> column=<column> code=<code> message=<message>`

Current lint rule:

- `unguarded_include`
  - update:
    - `ALNEOCInclude(out, ctx, @"partials/_nav.html.eoc", error);`
  - to:
    - `if (!ALNEOCInclude(out, ctx, @"partials/_nav.html.eoc", error)) { return nil; }`
- `slot_without_layout`
  - add a static `<%@ layout "..." %>` declaration or remove the slot fill.
- `unused_slot_fill`
  - add a matching `<%@ yield "slot_name" %>` in the selected layout or remove the slot fill.

## 4. Re-Run Unit and Integration Gates

```bash
make test-unit
make test-integration
```

Template-specific regressions are covered in:

- `tests/unit/TranspilerTests.m`
- `tests/unit/RuntimeTests.m`
- `tests/integration/HTTPIntegrationTests.m`
- `tests/integration/DeploymentIntegrationTests.m`

## 5. Validate in Watch Mode

```bash
./bin/boomhauer --watch
```

When transpile/compile fails in watch mode, diagnostics are served until a successful rebuild is detected.

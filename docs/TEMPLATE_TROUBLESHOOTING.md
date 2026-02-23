# Template Troubleshooting

Use this workflow when `.html.eoc` transpilation or rendering does not behave as expected.

## 1. Run Targeted Transpile

```bash
./build/eocc --template-root templates --output-dir build/gen/templates templates/index.html.eoc
```

If transpilation fails, `eocc` prints deterministic location data:

- `path=<logical_path>`
- `line=<line>`
- `column=<column>`

## 2. Interpret Common Errors

- `Unclosed EOC tag`
  - check `<% ... %>` delimiters around the reported location.
- `Expression tag cannot be empty`
  - ensure `<%= ... %>` and `<%== ... %>` contain a non-empty expression.
- `Invalid sigil local`
  - ensure sigil usage follows `$identifier` with `[A-Za-z_][A-Za-z0-9_]*`.

## 3. Address Lint Warnings

`eocc` warning output format:

- `eocc: warning path=<path> line=<line> column=<column> code=<code> message=<message>`

Current lint rule:

- `unguarded_include`
  - update:
    - `ALNEOCInclude(out, ctx, @"partials/_nav.html.eoc", error);`
  - to:
    - `if (!ALNEOCInclude(out, ctx, @"partials/_nav.html.eoc", error)) { return nil; }`

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

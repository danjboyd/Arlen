# Phase 28 TypeScript Harness

This workspace complements the Objective-C/XCTest coverage for Phase 28.

It owns four focused families:

- `npm run test:generated`: snapshot and compile-only checks
- `npm run test:unit`: transport, validator, query, meta, and React helper unit tests
- `npm run test:integration`: live generated-client coverage against a running Arlen app
- `npm run generate:arlen`: regenerate the app-owned package under `generated/arlen`

The generated output is intentionally not checked in. Focused make targets and
confidence lanes prepare it before running the tests.

# TaxCalculator Phase 9J Deploy Reconciliation

Date: `2026-05-02`

This note records the upstream Arlen assessment of two TaxCalculator reports
after updating the vendored Arlen checkout to commit `38bb8b0`.

Ownership rule:

- Arlen records upstream status only.
- `TaxCalculator` keeps app-level closure authority.
- Downstream revalidation still belongs to `TaxCalculator` after it updates its
  vendored Arlen checkout.

## Current Upstream Assessment

| TaxCalculator report | Upstream status | Evidence |
| --- | --- | --- |
| Phase 9J certification hangs in `HTTPIntegrationTests/testReservedOperabilityEndpointsCannotBeShadowedByCatchAllRoute` | fixed upstream; awaiting downstream revalidation | `docs/internal/OPEN_ISSUES.md` (`ARLEN-BUG-029`), `tests/integration/HTTPIntegrationTests.m` |
| Downstream app deploys are blocked by heavyweight Arlen release certification by default | fixed upstream; awaiting downstream revalidation | `docs/internal/OPEN_ISSUES.md` (`ARLEN-BUG-030`), `tools/arlen.m`, `tools/deploy/build_release.sh`, `docs/DEPLOYMENT.md`, `docs/CLI_REFERENCE.md` |

## Notes

### `ARLEN-BUG-029`: Reserved Endpoint Integration Hang

- Upstream accepted the failure class from the downstream report.
- Root cause:
  - the HTTP integration helper spawned a server, sent a request, and waited
    indefinitely for server exit
  - reserved operability endpoints can complete the request without forcing
    that helper's `--once` process to exit
- Current upstream behavior:
  - shell capture uses temporary files instead of bounded pipes
  - spawned server shutdown is bounded
  - stalled children are terminated and then killed if needed
  - timeout diagnostics include command, port, stdout, and stderr
- Regression coverage:
  - `HTTPIntegrationTests::testReservedOperabilityEndpointsCannotBeShadowedByCatchAllRoute`

### `ARLEN-BUG-030`: First-Class Non-RC App Deploy Path

- Upstream accepted the UX/contract issue from the downstream report.
- Root cause:
  - the non-certified app-iteration path existed as
    `--allow-missing-certification`, but the name and docs made it look like an
    exceptional bypass rather than a supported non-RC workflow
- Current upstream behavior:
  - `--skip-release-certification` and `--dev` are supported aliases
  - release metadata still records certification and JSON performance status as
    `waived`
  - text-mode packaging prints an explicit warning when the checks are waived
  - strict certification remains the default for release-candidate packaging

Downstream revalidation should update TaxCalculator's vendored Arlen checkout
and rerun:

```bash
cd /home/danboyd/git/TaxCalculator/vendor/arlen
make test-integration-filter TEST=HTTPIntegrationTests/testReservedOperabilityEndpointsCannotBeShadowedByCatchAllRoute
```

For non-RC app iteration, downstream deploys should use one of:

```bash
ARLEN_FRAMEWORK_ROOT="$PWD/vendor/arlen" \
vendor/arlen/bin/arlen deploy push iep-ownerconnect --skip-release-certification

ARLEN_FRAMEWORK_ROOT="$PWD/vendor/arlen" \
vendor/arlen/bin/arlen deploy push iep-ownerconnect --dev
```

The Phase 9J manifest requirement remains the default for certified release
candidate packaging.

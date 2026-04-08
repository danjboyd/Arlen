# OwnerConnect Report Reconciliation

Date: `2026-04-07`

This note records the upstream Arlen assessment of the OwnerConnect deployment
reports filed on `2026-04-07`, including:

- `../OwnerConnect/docs/bugs/2026-04-07-arlen-deploy-doctor-missing-validate-operability-script.md`
- `../OwnerConnect/docs/bugs/2026-04-07-arlen-feature-gaps-after-latest-update.md`

Ownership rule:

- Arlen records upstream status only.
- `OwnerConnect` keeps app-level closure authority.
- Status below should be read as the upstream status/evidence trail.
  Downstream revalidation still belongs to `OwnerConnect`.

## Current Upstream Assessment

| OwnerConnect report | Upstream status | Evidence |
| --- | --- | --- |
| `deploy doctor --base-url` fails against packaged releases because `validate_operability.sh` is missing | fixed in current workspace; awaiting downstream revalidation | `tools/deploy/build_release.sh`, `tools/arlen.m`, `tests/integration/DeploymentIntegrationTests.m`, `docs/DEPLOYMENT.md` |
| broader “feature gaps after latest update” note | partly valid product-gap summary; one concrete packaged-release bug fixed here | `docs/PHASE29_ROADMAP.md`, `docs/DEPLOYMENT.md`, `docs/CLI_REFERENCE.md`, `docs/STATUS.md` |

## Notes

### Packaged `deploy doctor --base-url` Failure

- Upstream reproduced the failure class from the current packaged-release
  contract:
  - `deploy doctor` executed
    `framework/tools/deploy/validate_operability.sh`
  - release packaging only bundled `framework/bin`, `framework/build/arlen`,
    and `framework/build/boomhauer`
- Root cause:
  - the packaged release payload omitted the helper script that the deploy CLI
    still used for live operability verification
- Current upstream behavior:
  - release packaging now includes
    `framework/tools/deploy/validate_operability.sh`
  - the release manifest now records that helper under
    `paths.operability_probe_helper`
  - `deploy doctor` explicitly checks for the helper and emits a deterministic
    error if it is missing or not executable
- Regression coverage:
  - `DeploymentIntegrationTests::testArlenDeployDoctorBaseURLWorksAgainstPackagedRelease`
- Downstream revalidation should rebuild an OwnerConnect release and rerun
  `deploy doctor --base-url ...` against the activated packaged release.

### Broader Deploy Product Gaps

- OwnerConnect’s remaining product-gap summary is mostly fair:
  - no `deploy init`
  - no first-party SSH transport/orchestration
  - no secrets subcommands
  - no PostgreSQL provisioning flow
  - no turnkey service-user/bootstrap product
- Those items remain post-Phase-29 deploy product work, not regressions in the
  shipped local release/status/rollback/doctor/logs contract.

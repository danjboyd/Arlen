# OpportunityTracker ORM reserved-name report

Source: `../OpportunityTracker/arlen-orm/UPSTREAM-REQUEST.md` (2026-09-12).
Reported and reproduced revision: `f0eeb00e020e7f45100e8ee3846c00939448b4f5`.
Status: fixed upstream; awaiting downstream regeneration and app revalidation.

The SQL generator emitted an incompatible `NSString *state` property inherited
from `ALNORMModel`'s lifecycle enum, and a nullable `description` conflicting
with NSObject. Strict compilation reproduced the report. The original GNUstep
probe passed without warnings-as-errors at default optimization and `-O0`;
this report does not establish production data corruption.

The fix reserves generated property names, preserves column/logical field and
relationship names, supports exact-column `property_names` overrides, rejects
ambiguous field/helper names, and fixes camel-case setter capitalization.
See `docs/ARLEN_ORM.md` and `docs/ARLEN_ORM_MIGRATIONS.md` for adoption details.

Upstream evidence:

- `make phase26-orm-generated`: reserved-name/override/determinism/helper tests,
  strict generated compilation, typed getter/setter and runtime-state checks.
- `make phase26-orm-unit`: SQL runtime regressions.
- `make phase26-orm-integration`: Dataverse integration contracts.
- `make docs-api docs-html ci-docs`: documentation generation and quality gate.
- OT's existing schema was regenerated into `/tmp`, without editing OT files.
  The generated `stateValue` and `descriptionValue` properties compile with
  property-type, property-attribute and nullability warnings as errors. Its
  supplied probe, adjusted to call `stateValue`, passes column round-trip,
  lifecycle state and typed getter checks against Arlen's local framework.

OT owns app-level adoption, pilot qualification and downstream issue closure.
Wire-preserving decimal/timestamp projections remain a separate enhancement;
this correction does not alter typed hydration or remove OT's text projections.

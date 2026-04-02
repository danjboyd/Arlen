# OwnerConnect Report Reconciliation

Date: `2026-04-02`

This note records the upstream Arlen assessment of the OwnerConnect report in
`../OwnerConnect/docs/bugs/2026-04-02-arlen-dataverse-codegen-polymorphic-lookup-collision.md`.

Ownership rule:

- Arlen records upstream status only.
- `OwnerConnect` keeps app-level closure authority.
- Status below should be read as the upstream status/evidence trail.
  Downstream revalidation still belongs to `OwnerConnect`.

## Current Upstream Assessment

| OwnerConnect report | Upstream status | Evidence |
| --- | --- | --- |
| Dataverse codegen polymorphic lookup collision | fixed in current workspace; awaiting downstream revalidation | `src/Arlen/Data/ALNDataverseCodegen.m`, `tests/unit/DataverseMetadataTests.m`, `tests/fixtures/phase23/dataverse_polymorphic_entitydefinitions.json`, `docs/DATAVERSE.md` |

## Notes

- Upstream reproduced the failure with a focused fixture that includes multiple
  `ManyToOneRelationships` sharing one referencing attribute, such as
  `lead.customerid` and `contact.parentcustomerid`.
- Root cause:
  - header generation deduplicated helper declarations by referencing
    attribute, but implementation generation still emitted one method body per
    relationship
  - the original singular `lookupNavigationMap` contract could not preserve
    multiple valid navigation targets for one logical lookup attribute
- Current upstream behavior:
  - unambiguous lookups still emit `navigation<Attribute>` helpers and still
    participate in `lookupNavigationMap`
  - every lookup attribute now participates in
    `lookupNavigationTargetsMap`, which preserves all generated navigation
    property targets in deterministic order
  - polymorphic lookups now emit navigation-property-specific helpers such as
    `navigationCustomeridAccount` and `navigationCustomeridContact`
  - ambiguous logical lookup attributes are intentionally omitted from the
    singular `lookupNavigationMap` so Arlen does not claim one arbitrary target
- Regression coverage:
  - `DataverseMetadataTests::testDataverseCodegenHandlesPolymorphicLookupNavigationCollisions`
- Downstream revalidation should regenerate the affected OwnerConnect
  Dataverse artifacts and remove the local workaround once the generated output
  compiles without hand edits.

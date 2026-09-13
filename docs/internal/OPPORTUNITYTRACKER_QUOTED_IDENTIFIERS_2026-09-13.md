# OpportunityTracker quoted SQL identifiers

Source: `../OpportunityTracker/arlen-sprint5/upstream/quoted-identifiers.md`.
Reported revision: `004d7fae492aa556d7fe5d0683fc675ccf866f2f`.
Status: fixed upstream; awaiting downstream regeneration and app revalidation.

The supplied codegen harness reproduced `ALNORMErrorInvalidMetadata` on
`Target ID`. ORM codegen and SQL compilation restricted physical names to
ordinary identifiers. The fix preserves physical names, emits safe aliases,
adds explicit logical-field collision overrides, and parses/escapes identifier
components through query, repository, joins, returning, and upsert paths.
The live upsert regression also exposed and corrected dialect-directed
compilation bypassing the PostgreSQL conflict clause.

The fixture includes the reported legacy columns plus dots, embedded quotes,
placeholder-like names, surrounding whitespace, and injection-shaped names.
The isolated PostgreSQL regression verifies quoted-key CRUD, generated-key
hydration, changesets, reload, composite keys, joined relation hydration,
upsert, neighboring row/field preservation, and rollback. Generated models
compile with strict property/nullability checks. MSSQL compilation checks
cover delimiter escaping without claiming live MSSQL qualification.

Run `bash tools/ci/run_orm_identifier_regressions.sh` for the mandatory CI
regression gate. The user-facing adoption contract is in `../ARLEN_ORM.md`.
OT should rebuild against the fix, regenerate models, and revalidate its native
target/task transaction before adopting persistence. Arlen does not close the
app's issue on OT's behalf.

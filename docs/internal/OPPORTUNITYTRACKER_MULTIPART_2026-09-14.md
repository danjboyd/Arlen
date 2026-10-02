# OpportunityTracker multipart capability request

Source: sister repository `OpportunityTracker/arlen-sprint6/upstream/multipart-uploads.md`
(reproduced against Arlen `79d3fef779fbc7d62d551ce2dfcf22676627234b`).

The report correctly identified missing multipart request APIs, with raw binary
transport preserved. The upstream implementation adds ordered parts and field
values, typed uploads, strict binary-safe parsing, and configurable request,
part-count, field, file, and header limits. The supported buffering and error
contract is documented in [Multipart Uploads](../MULTIPART_UPLOADS.md).

Validation is covered by `MultipartTests` and
`HTTPIntegrationTests/testMultipartFragmentedReadsLimitsAndAborts`, including
both HTTP parser backends, fragmented delivery, failed parses, connection aborts,
and the configured 110 MiB request ceiling. The socket test checks rejection
above that ceiling without sending a 110 MiB payload; it is not a large-upload
memory benchmark. No spool files are created by this implementation.

Status: implemented upstream; awaiting downstream adoption and revalidation.
OT owns its workflow parity checks and downstream closure.

The original OT constructor probe was compiled unchanged against the updated
Arlen framework library. It returned `multipart_description_available: true`,
`multipart_fields: {description: fixture}`, `urlencoded_control: true`, and
`raw_body_preserved: true`. Focused regression results: 7 multipart, 19 request,
72 application, and 10 configuration tests passed, plus the live multipart
integration method on llhttp and legacy backends.

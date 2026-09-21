# GNUstep metadata transport correction

Status: fixed upstream in Arlen; awaiting downstream adoption and revalidation.
Baseline: `19ff5b2f06a952317f809e59856afadf7e090529`.

Follow-up: [2026-09-17 upstream verification](GNUSTEP_783_VERIFICATION_2026-09-17.md)
confirms the custom-mode scheduling fix with explicit `start`, while recording a
separate master-build subprocess termination issue. The libcurl workaround stays.
The [same-day follow-up](GNUSTEP_TRANSPORT_SELECTION_2026-09-17.md) fixes that
subprocess issue locally and verifies that synchronous Foundation DNS still
prevents a scheduling-only automatic transport switch from preserving deadlines.

## Findings

GNUstep Base 1.31.1's NSURLConnection custom-mode transport does not service
HTTP socket streams, which NSURLProtocol schedules in NSDefaultRunLoopMode.
A standalone public Entra discovery probe produced:

```text
mode=Repro.Custom done=0 status=0 bytes=0
mode=NSDefaultRunLoopMode done=1 status=200 bytes=1728
```

The probe used a two-second fractional monotonic deadline and omitted explicit
`start`: GNUstep's scheduling method already queues it. This separates the
transport failure from the duplicate-start warning. Reproduction, source review,
and expected behavior are filed at [GNUstep libs-base #783](https://github.com/gnustep/libs-base/issues/783).

Review also found that GNUstep `systemUptime` returns integral seconds on this
installation, making it unsuitable for subsecond total deadlines. The original
Foundation path accepted a self-signed TLS peer under default settings. Requiring
verification exposed stale GNUstep CA resources; using the OS CA bundle allowed
Entra discovery/JWKS to succeed. A proposed NSURLSession replacement could not
link: headers declare the API, but this installed Foundation library does not
export NSURLSession or NSURLSessionConfiguration.

## Arlen workaround

GNUstep's bounded metadata loader uses libcurl directly, without pumping an
application run loop. It explicitly requires peer-chain and hostname verification,
rejects redirects and non-200 responses, checks declared length and streaming
length, and enforces a fractional monotonic total deadline. TLS and asynchronous
DNS support are mandatory; unsupported transports fail closed. Cookies are not
enabled. No synchronous Foundation completion-handler loader or fixtures replace
the production loader. Apple keeps the Foundation delegate transport.

The existing three-argument API remains available. The error-returning variant
reports sanitized categories and numeric transport codes, excluding request URLs,
credentials and response bodies. OAuth labels discovery/JWKS failures separately
from validation failures and refresh cooldown. Custom loader descriptions are not
forwarded. Startup preflight still fails before a candidate may serve requests.

libcurl is an explicit GNUstep build dependency (Debian/Ubuntu:
`libcurl4-openssl-dev`; MSYS2 CLANG64: `mingw-w64-clang-x86_64-curl`). GNUmakefile,
generated boomhauer app builds, focused build scripts and CI provisioning carry
the dependency. Existing CI lane and branch-protection names stay unchanged.

Reconsider the workaround once the supported GNUstep toolchain supplies a usable
NSURLSession or corrected NSURLConnection implementation. A replacement must pass
the same socket/TLS/deadline tests and live production discovery/JWKS preflight;
merging the scheduling fix alone is not enough evidence to remove it.

## Reproduction and validation

Source `tools/source_gnustep_env.sh` before these commands. Socket tests need normal
loopback network access; the Codex filesystem/network sandbox blocks socket creation.
The initial sandbox run failed for that reason and is not passing evidence.

```sh
make test-unit-filter TEST=MetadataTransportTests
ARLEN_TEST_ENTRA_TENANT=e163dc2e-cff9-4598-909e-556fa5b36e3a \
  make test-unit-filter TEST=MetadataTransportTests
make oauth-check mcp-check
make test-unit test-integration
make docs-api docs-html ci-docs
ARLEN_CI_GNUSTEP_STRATEGY=preinstalled bash tools/ci/install_ci_dependencies.sh
```

The live opt-in test uses `documentLoader:nil`, the real Entra v2 discovery URL,
and its returned JWKS URI. It successfully completes signing-key preflight and
asserts readiness on the main thread and a fresh worker thread. No client secret,
access token, or application consent is needed for these public documents.

Deterministic socket coverage includes successful and exact-limit responses,
oversized declared and chunked bodies, redirects, non-200 responses, disconnects,
stalls and trickling bodies, repeated requests, and rejection of an untrusted TLS
certificate. A real TLS preflight failure proves fail-closed startup, safe transport
reporting, and a distinct subsequent cooldown error. This coverage runs through
`oauth-check` in linux-quality as well as ordinary unit-test discovery.

The initial broad integration run exposed a warning-volume-sensitive watch
fixture: its expected error followed hundreds of imported-header warnings, and
undrained child-output pipes blocked recovery. Separate test-only corrections
move the deliberate error before imports and capture child output in files for
both watch fixtures; the unchanged diagnostic and recovery assertions then pass.
A restart-under-load test failed on one broad run and passed in isolation; the
final integration log records the subsequent complete-suite result.

Final focused results: 717 unit methods across 99 classes passed; all 90 HTTP
integration methods passed; OAuth resource-server tests (18), MCP tests (16),
real socket/TLS/live Entra tests (4), OAuth/MCP example checks, documentation gates,
and the preinstalled-toolchain dependency probe passed.

The broader integration run is **not green**. Its deployment-policy tests reject
four suppressions in `tests/fixtures/sanitizers/phase9h_suppressions.json` expired
on 2026-06-30, and the stale `tests/fixtures/release/phase9j_known_risks.json`
(last updated 2026-05-11; 123 days old against a 14-day policy, with an overdue
active risk). These files are unchanged from the affected revision. This change
does not renew suppressions, recertify release risks, or claim release certification.

Local evidence logs for this run are under `/tmp/arlen-metadata-curl-live.log`,
`/tmp/arlen-oauth-check.log`, `/tmp/arlen-metadata-unit-final.log`,
`/tmp/arlen-metadata-integration-verified.log`,
`/tmp/arlen-metadata-docs.log`, and `/tmp/arlen-metadata-provision.log`.
The downstream production candidate was not rebuilt, adopted or deployed here.
The separate Entra S256 client-discovery interoperability issue is unchanged.

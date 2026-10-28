# Disposable v0.3.2 native qualification harness

This branch is an evidence harness, not a release source change. The workflow checks out the full immutable `source_ref` separately on a fresh Ubuntu 24.04 ARM64 hosted VM. The strict lane preserves the maintained full sanitizer gates; the normal lane runs the unfiltered unit and integration suites against a private PostgreSQL socket and the maintained HTTP concurrency gate. Inventories, skip identities, and runtime lock digests are verified. No production host or OCI resources are used. Never merge this harness branch into the release.

The public lane refuses an incomplete or wrong latest release, then uses the default public installer without an archive or version override in a fresh pinned Ubuntu Minimal ARM64 container on the native VM. It preserves user-flow logs and the normal runtime controls/provenance. Dispatch this lane only after actual v0.3.2 assets are verified.

The `public-debian`, `public-macos`, and `public-windows` lanes exercise the same
actual public latest on a cold native Debian 13 container, a fresh Apple ARM64
host, and the existing supported Windows development runner. They bind the
installed metadata to the tagged merge commit, whose tree must equal the
qualified candidate. Unix homes and install prefixes are isolated. Windows
reuses the tagged maintained six-step installer/first-app contract, changing
only installer selection to the checksum-verified downloaded public script
(without passing its Archive or Version options), source/helper paths, and the
evidence destination. The maintained per-user PATH mutex and restoration stay
intact, with restoration checked before releasing the mutex. These are
post-publication evidence lanes; they do not change release source or broaden
Windows beyond its existing development-platform qualification.

The normal harness builds the vendored XCTest runner serially before parallel framework compilation. Its separate XCTest and preload host libraries lack a parallel link dependency; this matches the serial runner preparation used by maintained CI and leaves release source untouched.

The canonical two-run strict Linux gate can also run on the existing native Debian 13 x64 CI runner. It uses the same immutable source, original Debian lock, pinned thread recipe, 1393-method identity/17-skip contract, four server generations, diagnostics/canaries, and actual DSO hashes. Additional ARM64 strict results are retained separately; they do not stand in for normal ARM64 functional qualification.

Full-suite native runners install unixodbc-dev so the ordinary transport-availability tests exercise their existing paths and preserve the original skip mapping. This is a qualification prerequisite, not a new runtime installer dependency or an added test exclusion.

The `native-race` lane measures two independent instrumented ARM64 HTTP initial/restarted server groups (eight full logs/exits), the unchanged 30 runtime diagnostic controls and two detecting canaries, and exact loaded core DSO hashes. It uses the same instrumented build flags/default suppressions and maintained HTTP probe as the full strict lane. It does not run or report a full unit suite; full normal ARM64 suites and the canonical complete Debian x64 strict pair remain separate required receipts. The failed additional full ARM64 strict run remains retained and explicitly unqualified.

The frozen v0.3.2 source retains the original 1372 methods and three runtime/storage regressions, adds 17 outbound HTTP client methods and one legacy-checksum regression, and totals 1393 unique unit methods. The original 17 strict or 15 normal mapped skips remain unchanged. No original method is removed. The normal integration contract is all 266 methods, 264 pass plus the two unchanged Apple/Windows-only methods. PostgreSQL uses the private socket through a whitespace-free URI so existing CLI integration commands retain the DSN as one shell argument.

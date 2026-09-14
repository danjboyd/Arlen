# Security Policy

Arlen is a young framework and treats security reports seriously. This policy
covers how to report a vulnerability, what to expect from us, and which
versions receive fixes.

## Reporting a vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Use one of the following private channels:

1. **GitHub private vulnerability reporting** (preferred). On the Arlen
   repository, go to the **Security** tab and click **Report a
   vulnerability**. This opens a private advisory visible only to maintainers.
2. **Direct contact to the maintainer** via GitHub. If GitHub's private
   reporting is unavailable, contact the repository owner privately via
   GitHub and we will move the conversation to a private channel.

When reporting, please include:

- A description of the issue and the impact you believe it has.
- The Arlen commit (`git rev-parse HEAD`) or version where you observed it.
- The smallest reproduction you can share — a failing test, curl invocation,
  or short app snippet under `examples/` style is ideal.
- Whether the issue has been disclosed elsewhere.

We will acknowledge receipt within **5 business days** and aim to provide an
initial assessment (severity, affected components, expected fix window) within
**10 business days**. We will keep you updated as we work on the fix and
coordinate disclosure timing with you.

## Scope

In scope:

- The Arlen framework runtime, including request handling, EOC templating,
  the data layer (`ALNPg`, ORM surfaces, migrations), auth/admin/jobs/
  notifications/storage/ops/search modules, realtime/event-stream support,
  and the `propane` production runtime.
- First-party tooling shipped in `bin/` and `tools/` (e.g., `arlen`,
  `boomhauer`, `propane`, codegen).
- Default configurations and templates produced by `arlen new`.

Out of scope:

- Third-party libraries, the GNUstep toolchain itself, or the operating
  system. Report those upstream.
- Vulnerabilities in example apps under `examples/` unless they reflect a
  defect in Arlen itself.
- Issues that require an attacker to already control the host running Arlen
  (e.g., trivial misconfigurations once root is achieved).
- EOC templates executing host-trusted Objective-C: by design, EOC templates
  are trusted code. Untrusted template execution is not a supported use case.

## Supported versions

Arlen has not yet cut a 1.0 release. While in this pre-release phase, security
fixes are made on the `main` branch and will be included in the next published
release artifact. If you need a fix backported to a specific deployment, note
the commit you are running in your report.

## Coordinated disclosure

We follow coordinated disclosure. After we and the reporter agree the fix is
ready, we publish a security advisory with credit to the reporter (unless they
prefer to remain anonymous) and ship the fix in a tagged release.

## Hall of fame

We will list security reporters here once we have published our first
advisory.

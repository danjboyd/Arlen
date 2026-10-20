#!/usr/bin/env bash
# Deterministic installer failure/retry and shell contract regression scenarios.
# Invoked by ReleasePrebuiltTests under the vendored XCTest runner.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/arlen-install-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home" "$work/pkg/arlen-1.2.3/tools" "$work/pkg/arlen-1.2.3/bin" "$work/mocks"
printf 'version=1.2.3\nkind=source\n' > "$work/pkg/arlen-1.2.3/.arlen-dist"
cat > "$work/pkg/arlen-1.2.3/tools/source_gnustep_env.sh" <<'SH'
gnustep-config() { echo '-fobjc-runtime=gnustep-2.2'; }
SH
printf '#!/usr/bin/env bash\nprintf "fixture-ok\\n"\n' > "$work/pkg/arlen-1.2.3/bin/arlen"
chmod +x "$work/pkg/arlen-1.2.3/bin/arlen"
tar -czf "$work/archive.tar.gz" -C "$work/pkg" arlen-1.2.3
# Force the Linux branch on macOS too; no real package installation or build.
printf '#!/bin/sh\ncase "$1" in -s) echo Linux;; -m) echo x86_64;; esac\n' > "$work/mocks/uname"
printf '#!/bin/sh\nexit 71\n' > "$work/mocks/make"
printf '#!/bin/sh\nexit 0\n' > "$work/mocks/clang"
chmod +x "$work/mocks/"*
prefix="$work/home/install with ' quote"
bin_dir="$work/home/bin with ' quote"
run_install() {
  env HOME="$work/home" SHELL=/bin/bash PATH="$work/mocks:$PATH" \
    bash "$root/tools/install.sh" --prefix "$prefix" --bin-dir "$bin_dir" "$@" > "$work/output" 2>&1
}
run_install --archive "$work/archive.tar.gz" --no-build
[[ "$(env PATH="$bin_dir:$PATH" arlen)" == fixture-ok ]]
# Profile must quote spaces/apostrophes correctly; a fresh shell resolves bare arlen.
env HOME="$work/home" PATH=/usr/bin:/bin bash --noprofile --norc -c '. "$HOME/.profile"; cd /; arlen' | grep -qx fixture-ok
run_install --archive "$work/archive.tar.gz" --no-build
[[ "$(grep -c '^# Arlen launcher$' "$work/home/.profile")" == 1 ]]
cp "$bin_dir/arlen" "$work/launcher-before"
printf 'old-install\n' > "$prefix/1.2.3/marker"
# Missing prerequisites with --no-setup or the failing make must both preserve it.
if run_install --archive "$work/archive.tar.gz" --no-setup; then echo 'unexpected build success' >&2; exit 1; fi
grep -q "framework build failed" "$work/output"
[[ -f "$prefix/last-build-failure.log" ]]
[[ -f "$prefix/1.2.3/marker" ]]
cmp "$bin_dir/arlen" "$work/launcher-before"
[[ "$(readlink "$prefix/current")" == 1.2.3 ]]
# Malformed archive and a version mismatch also preserve the active installation.
printf 'broken archive\n' > "$work/broken.tar.gz"
if run_install --archive "$work/broken.tar.gz" --no-build; then exit 1; fi
if run_install --archive "$work/archive.tar.gz" --version 9.9.9 --no-build; then exit 1; fi
[[ -f "$prefix/1.2.3/marker" ]]
# Network failure and checksum mismatch use the actual download branch.
cat > "$work/mocks/curl" <<'SH'
#!/usr/bin/env bash
if [[ "$INSTALL_DOWNLOAD_FAIL" == 1 ]]; then exit 22; fi
out=''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -o ]]; then out="$2"; shift 2; else url="$1"; shift; fi
done
case "$url" in */SHA256SUMS) printf '0000  arlen-1.2.3.tar.gz\n' > "$out";; *) cp "$INSTALL_TEST_ARCHIVE" "$out";; esac
SH
chmod +x "$work/mocks/curl"
export INSTALL_TEST_ARCHIVE="$work/archive.tar.gz" INSTALL_DOWNLOAD_FAIL=1
if run_install --version 1.2.3; then exit 1; fi
export INSTALL_DOWNLOAD_FAIL=0
if run_install --version 1.2.3; then exit 1; fi
grep -q 'checksum mismatch' "$work/output"
[[ -f "$prefix/1.2.3/marker" ]]
cmp "$bin_dir/arlen" "$work/launcher-before"
# Retry works and --no-modify-path leaves profiles untouched.
cp "$work/home/.profile" "$work/profile-before"
run_install --archive "$work/archive.tar.gz" --no-build --no-modify-path
[[ ! -e "$prefix/1.2.3/marker" ]]
cmp "$work/home/.profile" "$work/profile-before"
[[ "$(env PATH="$bin_dir:$PATH" arlen)" == fixture-ok ]]
if run_install --prefix; then exit 1; fi
if run_install --version '../bad'; then exit 1; fi
echo 'installer failure/retry/PATH scenarios passed'

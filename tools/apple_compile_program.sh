#!/usr/bin/env bash
# Compiles and links a small Objective-C program against the Apple framework
# archive (build/apple/lib/libArlenFramework.a). The Apple counterpart of
# `make test-client-program`, used by tests that build client programs.
#
# Usage: apple_compile_program.sh --output <path> [-I <dir>]... <source.m>...
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

# shellcheck source=tools/platform.sh
source "$script_dir/platform.sh"

if ! aln_platform_is_macos; then
  echo "apple-compile-program: this helper only supports macOS" >&2
  exit 1
fi

output=""
extra_flags=()
sources=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    -I)
      extra_flags+=(-I"$2")
      shift 2
      ;;
    -I*)
      extra_flags+=("$1")
      shift
      ;;
    -*)
      echo "apple-compile-program: unknown option $1" >&2
      exit 2
      ;;
    *)
      sources+=("$1")
      shift
      ;;
  esac
done
if [[ -z "$output" || ${#sources[@]} -eq 0 ]]; then
  echo "usage: apple_compile_program.sh --output <path> [-I <dir>]... <source.m>..." >&2
  exit 2
fi

openssl_prefix="${ARLEN_OPENSSL_PREFIX:-}"
if [[ -z "$openssl_prefix" ]]; then
  openssl_prefix="$(aln_platform_first_brew_prefix openssl@3 || true)"
fi
if [[ -z "$openssl_prefix" || ! -d "$openssl_prefix/include/openssl" ]]; then
  echo "apple-compile-program: unable to locate OpenSSL headers" >&2
  exit 1
fi

"$repo_root/bin/build-apple" >/dev/null

include_flags=(-I"$repo_root/src" -I"$openssl_prefix/include")
while IFS= read -r dir; do
  include_flags+=(-I"$dir")
done < <(find "$repo_root/src/Arlen" "$repo_root/src/MojoObjc" -type d ! -path '*/third_party/*' | sort)
include_flags+=(
  -I"$repo_root/src/Arlen/Support/third_party/argon2/include"
)
while IFS= read -r dir; do
  include_flags+=(-I"$dir")
done < <(find "$repo_root/modules" -mindepth 2 -maxdepth 2 -type d -name Sources 2>/dev/null | sort)

"$(xcrun --find clang)" \
  -isysroot "$(xcrun --show-sdk-path)" \
  -arch arm64 \
  -fobjc-arc \
  -fblocks \
  -DARLEN_ENABLE_YYJSON=1 \
  -DARLEN_ENABLE_LLHTTP=1 \
  "${include_flags[@]}" \
  ${extra_flags[@]+"${extra_flags[@]}"} \
  "${sources[@]}" \
  "$repo_root/build/apple/lib/libArlenFramework.a" \
  -o "$output" \
  -L"$openssl_prefix/lib" \
  -lcurl \
  -lcrypto \
  -framework Foundation \
  -framework CoreFoundation

#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

# shellcheck source=tools/platform.sh
source "$script_dir/platform.sh"

if ! aln_platform_is_macos; then
  echo "build-apple-xctest: this helper only supports macOS" >&2
  exit 1
fi

suite="unit"
print_bundle_path=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite)
      suite="$2"
      shift 2
      ;;
    --print-bundle-path)
      print_bundle_path=1
      shift
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: build_apple_xctest.sh [--suite unit] [--print-bundle-path]

Builds Apple XCTest bundles under build/apple/tests/.
USAGE
      exit 0
      ;;
    *)
      echo "build-apple-xctest: unknown option $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$suite" != "unit" ]]; then
  echo "build-apple-xctest: unsupported suite '$suite' (supported: unit)" >&2
  exit 2
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "build-apple-xctest: xcrun is required" >&2
  exit 1
fi

sdk_path="$(xcrun --show-sdk-path)"
platform_path="$(xcrun --show-sdk-platform-path)"
clang_path="$(xcrun --find clang)"
framework_dir="$platform_path/Developer/Library/Frameworks"

openssl_prefix="${ARLEN_OPENSSL_PREFIX:-}"
if [[ -z "$openssl_prefix" ]]; then
  openssl_prefix="$(aln_platform_first_brew_prefix openssl@3 || true)"
fi
if [[ -z "$openssl_prefix" || ! -d "$openssl_prefix/include/openssl" ]]; then
  echo "build-apple-xctest: unable to locate OpenSSL headers" >&2
  echo "build-apple-xctest: install 'openssl@3' with Homebrew or set ARLEN_OPENSSL_PREFIX" >&2
  exit 1
fi

"$repo_root/bin/build-apple" --with-boomhauer >/dev/null

build_root="$repo_root/build/apple"
tests_root="$build_root/tests"
obj_root="$build_root/obj/apple-tests"
bundle_root="$tests_root/ArlenUnitTests.xctest"
bundle_bin="$bundle_root/Contents/MacOS/ArlenUnitTests"
framework_lib="$build_root/lib/libArlenFramework.a"
eocc_bin="$build_root/eocc"
generated_root="$build_root/gen/templates"
module_generated_root="$build_root/gen/apple-test-modules"
mkdir -p "$tests_root" "$obj_root" "$bundle_root/Contents/MacOS"

ensure_wrapper() {
  local target="$1"
  local destination="$2"
  if [[ -e "$destination" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$destination")"
  cat >"$destination" <<EOF
#!/usr/bin/env bash
exec "$target" "\$@"
EOF
  chmod 755 "$destination"
}

# Preserve any real build artifacts, but make Apple-path wrappers available
# when the Objective-C test suite expects repo-root build/ binaries.
ensure_wrapper "$repo_root/build/apple/arlen" "$repo_root/build/arlen"
ensure_wrapper "$repo_root/bin/boomhauer" "$repo_root/build/boomhauer"
ensure_wrapper "$repo_root/build/apple/eocc" "$repo_root/build/eocc"

common_flags=(
  -isysroot "$sdk_path"
  -arch arm64
  -fobjc-arc
  -fblocks
  -fPIC
  -F"$framework_dir"
  -DARLEN_ENABLE_YYJSON=1
  -DARLEN_ENABLE_LLHTTP=1
  -DARGON2_NO_THREADS=1
  -I"$repo_root/src"
  -I"$repo_root/src/Arlen"
  -I"$repo_root/src/Arlen/Core"
  -I"$repo_root/src/Arlen/Data"
  -I"$repo_root/src/Arlen/HTTP"
  -I"$repo_root/src/Arlen/MVC/Controller"
  -I"$repo_root/src/Arlen/MVC/Middleware"
  -I"$repo_root/src/Arlen/MVC/Routing"
  -I"$repo_root/src/Arlen/MVC/Template"
  -I"$repo_root/src/Arlen/MVC/View"
  -I"$repo_root/src/Arlen/ORM"
  -I"$repo_root/src/Arlen/Support"
  -I"$repo_root/src/Arlen/Support/third_party/argon2/include"
  -I"$repo_root/src/Arlen/Support/third_party/argon2/src"
  -I"$repo_root/src/MojoObjc"
  -I"$repo_root/src/MojoObjc/Core"
  -I"$repo_root/src/MojoObjc/Data"
  -I"$repo_root/src/MojoObjc/HTTP"
  -I"$repo_root/src/MojoObjc/MVC/Controller"
  -I"$repo_root/src/MojoObjc/MVC/Middleware"
  -I"$repo_root/src/MojoObjc/MVC/Routing"
  -I"$repo_root/src/MojoObjc/MVC/Template"
  -I"$repo_root/src/MojoObjc/MVC/View"
  -I"$repo_root/src/MojoObjc/Support"
  -I"$repo_root/tests/shared"
  -I"$repo_root/tests/unit"
  -I"$openssl_prefix/include"
)

while IFS= read -r module_sources_dir; do
  common_flags+=(-I"$module_sources_dir")
done < <(find "$repo_root/modules" -mindepth 2 -maxdepth 2 -type d -name Sources 2>/dev/null | sort)

objc_flags=("${common_flags[@]}")
link_flags=(
  -isysroot "$sdk_path"
  -arch arm64
  -F"$framework_dir"
  -L"$openssl_prefix/lib"
  -bundle
  -framework Foundation
  -framework CoreFoundation
  -framework XCTest
  -lobjc
  -lcrypto
)

obj_path_for() {
  local src="$1"
  local rel="${src#$repo_root/}"
  rel="${rel#./}"
  printf '%s/%s.o\n' "$obj_root" "$rel"
}

compile_objc() {
  local src="$1"
  local obj="$2"
  mkdir -p "$(dirname "$obj")"
  "$clang_path" "${objc_flags[@]}" -c "$src" -o "$obj"
}

sources=()
while IFS= read -r src; do
  sources+=("$src")
done < <(find "$repo_root/tests/shared" -type f -name '*.m' | sort)
while IFS= read -r src; do
  sources+=("$src")
done < <(find "$repo_root/tests/unit" -type f -name '*.m' | sort)
while IFS= read -r src; do
  sources+=("$src")
done < <(find "$generated_root" -type f -name '*.m' 2>/dev/null | sort)

rm -rf "$module_generated_root"
mkdir -p "$module_generated_root"
while IFS= read -r module_root; do
  module_id="$(basename "$module_root")"
  template_root="$module_root/Resources/Templates"
  if [[ ! -d "$template_root" ]]; then
    continue
  fi

  module_templates=()
  while IFS= read -r template_path; do
    module_templates+=("$template_path")
  done < <(find "$template_root" -type f -name '*.html.eoc' | sort)
  if [[ ${#module_templates[@]} -eq 0 ]]; then
    continue
  fi

  "$eocc_bin" \
    --template-root "$template_root" \
    --output-dir "$module_generated_root" \
    --manifest "$module_generated_root/$module_id.manifest.json" \
    --logical-prefix "modules/$module_id" \
    "${module_templates[@]}" >/dev/null
done < <(find "$repo_root/modules" -mindepth 1 -maxdepth 1 -type d | sort)

while IFS= read -r src; do
  sources+=("$src")
done < <(find "$module_generated_root" -type f -name '*.m' 2>/dev/null | sort)

if [[ ${#sources[@]} -eq 0 ]]; then
  echo "build-apple-xctest: no Objective-C sources found for Apple XCTest bundle" >&2
  exit 1
fi

objects=()
for src in "${sources[@]}"; do
  obj="$(obj_path_for "$src")"
  compile_objc "$src" "$obj"
  objects+=("$obj")
done

rm -rf "$bundle_root"
mkdir -p "$bundle_root/Contents/MacOS"
"$clang_path" "${objc_flags[@]}" "${objects[@]}" "$framework_lib" -o "$bundle_bin" "${link_flags[@]}"
cp "$repo_root/tests/Info-apple-unit.plist" "$bundle_root/Contents/Info.plist"

if [[ $print_bundle_path -eq 1 ]]; then
  printf '%s\n' "$bundle_root"
fi

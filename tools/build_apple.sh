#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

# shellcheck source=tools/platform.sh
source "$script_dir/platform.sh"

if ! aln_platform_is_macos; then
  echo "build-apple: this builder only supports macOS" >&2
  exit 1
fi

with_boomhauer=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-boomhauer)
      with_boomhauer=1
      shift
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: build-apple.sh [--with-boomhauer]

Builds the Apple-runtime Arlen artifacts under build/apple/.
USAGE
      exit 0
      ;;
    *)
      echo "build-apple: unknown option $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v xcrun >/dev/null 2>&1; then
  echo "build-apple: xcrun is required" >&2
  exit 1
fi

sdk_path="$(xcrun --show-sdk-path)"
clang_path="$(xcrun --find clang)"

openssl_prefix="${ARLEN_OPENSSL_PREFIX:-}"
if [[ -z "$openssl_prefix" ]]; then
  openssl_prefix="$(aln_platform_first_brew_prefix openssl@3 || true)"
fi
if [[ -z "$openssl_prefix" || ! -d "$openssl_prefix/include/openssl" ]]; then
  echo "build-apple: unable to locate OpenSSL headers" >&2
  echo "build-apple: install 'openssl@3' with Homebrew or set ARLEN_OPENSSL_PREFIX" >&2
  exit 1
fi

build_root="$repo_root/build/apple"
obj_root="$build_root/obj"
lib_root="$build_root/lib"
gen_root="$build_root/gen/templates"
mkdir -p "$build_root" "$obj_root" "$lib_root" "$gen_root"

common_flags=(
  -isysroot "$sdk_path"
  -arch arm64
  -fobjc-arc
  -fblocks
  -fPIC
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
  -I"$openssl_prefix/include"
)

while IFS= read -r module_sources_dir; do
  common_flags+=(-I"$module_sources_dir")
done < <(find "$repo_root/modules" -mindepth 2 -maxdepth 2 -type d -name Sources 2>/dev/null | sort)

objc_flags=("${common_flags[@]}")
c_flags=("${common_flags[@]}")
link_flags=(
  -isysroot "$sdk_path"
  -arch arm64
  -L"$openssl_prefix/lib"
  -framework Foundation
  -framework CoreFoundation
  -lcrypto
)

compile_objc() {
  local src="$1"
  local obj="$2"
  mkdir -p "$(dirname "$obj")"
  "$clang_path" "${objc_flags[@]}" -c "$src" -o "$obj"
}

compile_c() {
  local src="$1"
  local obj="$2"
  mkdir -p "$(dirname "$obj")"
  "$clang_path" "${c_flags[@]}" -c "$src" -o "$obj"
}

obj_path_for() {
  local src="$1"
  local rel="${src#$repo_root/}"
  printf '%s/%s.o\n' "$obj_root" "$rel"
}

framework_objs=()
while IFS= read -r src; do
  obj="$(obj_path_for "$src")"
  compile_objc "$src" "$obj"
  framework_objs+=("$obj")
done < <(find "$repo_root/src" -type f -name '*.m' | sort)

while IFS= read -r src; do
  obj="$(obj_path_for "$src")"
  compile_objc "$src" "$obj"
  framework_objs+=("$obj")
done < <(find "$repo_root/modules" -type f -path '*/Sources/*.m' 2>/dev/null | sort)

while IFS= read -r src; do
  obj="$(obj_path_for "$src")"
  compile_c "$src" "$obj"
  framework_objs+=("$obj")
done < <(find "$repo_root/src/Arlen/Support/third_party/yyjson" -type f -name '*.c' | sort)

while IFS= read -r src; do
  obj="$(obj_path_for "$src")"
  compile_c "$src" "$obj"
  framework_objs+=("$obj")
done < <(find "$repo_root/src/Arlen/Support/third_party/llhttp" -type f -name '*.c' | sort)

while IFS= read -r src; do
  obj="$(obj_path_for "$src")"
  compile_c "$src" "$obj"
  framework_objs+=("$obj")
done < <(find "$repo_root/src/Arlen/Support/third_party/argon2/src" -type f -name '*.c' | sort)

framework_lib="$lib_root/libArlenFramework.a"
rm -f "$framework_lib"
libtool -static -o "$framework_lib" "${framework_objs[@]}"

eocc_objs=()
for src in \
  "$repo_root/tools/eocc.m" \
  "$repo_root/src/Arlen/MVC/Template/ALNEOCRuntime.m" \
  "$repo_root/src/Arlen/MVC/Template/ALNEOCTranspiler.m"
do
  obj="$(obj_path_for "$src")"
  compile_objc "$src" "$obj"
  eocc_objs+=("$obj")
done

eocc_bin="$build_root/eocc"
"$clang_path" "${objc_flags[@]}" "${eocc_objs[@]}" -o "$eocc_bin" "${link_flags[@]}"

arlen_entry_obj="$(obj_path_for "$repo_root/tools/arlen.m")"
compile_objc "$repo_root/tools/arlen.m" "$arlen_entry_obj"
arlen_bin="$build_root/arlen"
"$clang_path" "${objc_flags[@]}" "$arlen_entry_obj" "$framework_lib" -o "$arlen_bin" "${link_flags[@]}"

apple_auth_audit_obj="$(obj_path_for "$repo_root/tools/apple_auth_audit.m")"
compile_objc "$repo_root/tools/apple_auth_audit.m" "$apple_auth_audit_obj"
apple_auth_audit_bin="$build_root/apple-auth-audit"
"$clang_path" "${objc_flags[@]}" "$apple_auth_audit_obj" "$framework_lib" -o "$apple_auth_audit_bin" "${link_flags[@]}"

if [[ $with_boomhauer -eq 1 ]]; then
  template_files=()
  while IFS= read -r template; do
    template_files+=("$template")
  done < <(find "$repo_root/templates" -type f -name '*.html.eoc' | sort)

  if [[ ${#template_files[@]} -gt 0 ]]; then
    "$eocc_bin" \
      --template-root "$repo_root/templates" \
      --output-dir "$gen_root" \
      --manifest "$gen_root/manifest.json" \
      "${template_files[@]}"

    generated_objs=()
    while IFS= read -r generated; do
      obj="$(obj_path_for "$generated")"
      compile_objc "$generated" "$obj"
      generated_objs+=("$obj")
    done < <(find "$gen_root" -type f -name '*.m' | sort)

    boomhauer_obj="$(obj_path_for "$repo_root/tools/boomhauer.m")"
    compile_objc "$repo_root/tools/boomhauer.m" "$boomhauer_obj"
    "$clang_path" "${objc_flags[@]}" "$boomhauer_obj" "${generated_objs[@]}" "$framework_lib" \
      -o "$build_root/boomhauer" "${link_flags[@]}"
  fi
fi

cat <<EOF
build-apple: built artifacts:
  $eocc_bin
  $framework_lib
  $arlen_bin
  $apple_auth_audit_bin
EOF

if [[ $with_boomhauer -eq 1 && -x "$build_root/boomhauer" ]]; then
  echo "  $build_root/boomhauer"
fi

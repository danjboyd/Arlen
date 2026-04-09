#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

# shellcheck source=tools/platform.sh
source "$script_dir/platform.sh"

if ! aln_platform_is_macos; then
  echo "build-apple-app: this builder only supports macOS" >&2
  exit 1
fi

app_root="${ARLEN_APP_ROOT:-$PWD}"
framework_root="${ARLEN_FRAMEWORK_ROOT:-$repo_root}"
prepare_only=0
print_path=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-root)
      app_root="$2"
      shift 2
      ;;
    --framework-root)
      framework_root="$2"
      shift 2
      ;;
    --prepare-only)
      prepare_only=1
      shift
      ;;
    --print-path)
      print_path=1
      shift
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: build_apple_app.sh [--app-root <path>] [--framework-root <path>] [--prepare-only] [--print-path]

Builds an app-root Arlen server binary for the Apple runtime.
USAGE
      exit 0
      ;;
    *)
      echo "build-apple-app: unknown option $1" >&2
      exit 2
      ;;
  esac
done

app_root="$(cd "$app_root" && pwd)"
framework_root="$(cd "$framework_root" && pwd)"

if [[ ! -f "$framework_root/GNUmakefile" || ! -d "$framework_root/src/Arlen" ]]; then
  echo "build-apple-app: invalid framework root: $framework_root" >&2
  exit 1
fi

if [[ ! -f "$app_root/config/app.plist" ]]; then
  echo "build-apple-app: app config missing at $app_root/config/app.plist" >&2
  exit 1
fi

if [[ ! -f "$app_root/app_lite.m" ]] &&
   ! find "$app_root/src" -type f -name '*.m' -print -quit 2>/dev/null | grep -q .; then
  echo "build-apple-app: expected Objective-C app sources under $app_root/src or app_lite.m" >&2
  exit 1
fi

"$framework_root/bin/build-apple" >/dev/null

sdk_path="$(xcrun --show-sdk-path)"
clang_path="$(xcrun --find clang)"

openssl_prefix="${ARLEN_OPENSSL_PREFIX:-}"
if [[ -z "$openssl_prefix" ]]; then
  openssl_prefix="$(aln_platform_first_brew_prefix openssl@3 || true)"
fi
if [[ -z "$openssl_prefix" || ! -d "$openssl_prefix/include/openssl" ]]; then
  echo "build-apple-app: unable to locate OpenSSL headers" >&2
  echo "build-apple-app: install 'openssl@3' with Homebrew or set ARLEN_OPENSSL_PREFIX" >&2
  exit 1
fi

app_build_root="$app_root/.boomhauer/apple"
obj_root="$app_build_root/obj"
gen_root="$app_build_root/gen"
app_template_root="$gen_root/templates"
module_template_root="$gen_root/modules"
mkdir -p "$obj_root" "$app_template_root" "$module_template_root"

eocc_bin="$framework_root/build/apple/eocc"
framework_lib="$framework_root/build/apple/lib/libArlenFramework.a"
app_binary="$app_build_root/boomhauer-app"

common_flags=(
  -isysroot "$sdk_path"
  -arch arm64
  -fobjc-arc
  -fblocks
  -fPIC
  -DARLEN_ENABLE_YYJSON=1
  -DARLEN_ENABLE_LLHTTP=1
  -DARGON2_NO_THREADS=1
  -I"$framework_root/src"
  -I"$framework_root/src/Arlen"
  -I"$framework_root/src/Arlen/Core"
  -I"$framework_root/src/Arlen/Data"
  -I"$framework_root/src/Arlen/HTTP"
  -I"$framework_root/src/Arlen/MVC/Controller"
  -I"$framework_root/src/Arlen/MVC/Middleware"
  -I"$framework_root/src/Arlen/MVC/Routing"
  -I"$framework_root/src/Arlen/MVC/Template"
  -I"$framework_root/src/Arlen/MVC/View"
  -I"$framework_root/src/Arlen/ORM"
  -I"$framework_root/src/Arlen/Support"
  -I"$framework_root/src/Arlen/Support/third_party/argon2/include"
  -I"$framework_root/src/Arlen/Support/third_party/argon2/src"
  -I"$framework_root/src/MojoObjc"
  -I"$framework_root/src/MojoObjc/Core"
  -I"$framework_root/src/MojoObjc/Data"
  -I"$framework_root/src/MojoObjc/HTTP"
  -I"$framework_root/src/MojoObjc/MVC/Controller"
  -I"$framework_root/src/MojoObjc/MVC/Middleware"
  -I"$framework_root/src/MojoObjc/MVC/Routing"
  -I"$framework_root/src/MojoObjc/MVC/Template"
  -I"$framework_root/src/MojoObjc/MVC/View"
  -I"$framework_root/src/MojoObjc/Support"
  -I"$app_root/src"
  -I"$openssl_prefix/include"
)

while IFS= read -r module_sources_dir; do
  common_flags+=(-I"$module_sources_dir")
done < <(find "$framework_root/modules" -mindepth 2 -maxdepth 2 -type d -name Sources 2>/dev/null | sort)

while IFS= read -r module_sources_dir; do
  common_flags+=(-I"$module_sources_dir")
done < <(find "$app_root/modules" -mindepth 2 -maxdepth 2 -type d -name Sources 2>/dev/null | sort)

objc_flags=("${common_flags[@]}")
link_flags=(
  -isysroot "$sdk_path"
  -arch arm64
  -L"$openssl_prefix/lib"
  -framework Foundation
  -framework CoreFoundation
  -lcrypto
)

obj_path_for() {
  local src="$1"
  local rel
  rel="${src#$app_root/}"
  if [[ "$rel" == "$src" ]]; then
    rel="${src#$framework_root/}"
  fi
  rel="${rel#./}"
  printf '%s/%s.o\n' "$obj_root" "$rel"
}

compile_objc() {
  local src="$1"
  local obj="$2"
  mkdir -p "$(dirname "$obj")"
  "$clang_path" "${objc_flags[@]}" -c "$src" -o "$obj"
}

transpile_app_templates() {
  rm -rf "$app_template_root" "$module_template_root"
  mkdir -p "$app_template_root" "$module_template_root"

  if [[ -d "$app_root/templates" ]]; then
    template_files=()
    while IFS= read -r template_path; do
      template_files+=("$template_path")
    done < <(find "$app_root/templates" -type f -name '*.html.eoc' | sort)
    if [[ ${#template_files[@]} -gt 0 ]]; then
      "$eocc_bin" \
        --template-root "$app_root/templates" \
        --output-dir "$app_template_root" \
        --manifest "$app_template_root/manifest.json" \
        "${template_files[@]}" 1>&2
    fi
  fi

  if [[ -d "$app_root/modules" ]]; then
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
        --output-dir "$module_template_root" \
        --manifest "$module_template_root/$module_id.manifest.json" \
        --logical-prefix "modules/$module_id" \
        "${module_templates[@]}" 1>&2
    done < <(find "$app_root/modules" -mindepth 1 -maxdepth 1 -type d | sort)
  fi
}

transpile_app_templates

app_sources=()
while IFS= read -r src; do
  app_sources+=("$src")
done < <(find "$app_root/src" -type f -name '*.m' 2>/dev/null | sort)
if [[ -f "$app_root/app_lite.m" ]]; then
  app_sources+=("$app_root/app_lite.m")
fi
while IFS= read -r src; do
  app_sources+=("$src")
done < <(find "$app_root/modules" -type f -path '*/Sources/*.m' 2>/dev/null | sort)

generated_sources=()
while IFS= read -r src; do
  generated_sources+=("$src")
done < <(find "$app_template_root" "$module_template_root" -type f -name '*.m' 2>/dev/null | sort)

if [[ ${#app_sources[@]} -eq 0 ]]; then
  echo "build-apple-app: no app Objective-C sources found" >&2
  exit 1
fi

app_objects=()
for src in "${app_sources[@]}"; do
  obj="$(obj_path_for "$src")"
  compile_objc "$src" "$obj"
  app_objects+=("$obj")
done

if (( ${#generated_sources[@]} > 0 )); then
  for src in "${generated_sources[@]}"; do
    obj="$(obj_path_for "$src")"
    compile_objc "$src" "$obj"
    app_objects+=("$obj")
  done
fi

"$clang_path" "${objc_flags[@]}" "${app_objects[@]}" "$framework_lib" -o "$app_binary" "${link_flags[@]}"

if [[ $print_path -eq 1 ]]; then
  printf '%s\n' "$app_binary"
fi

if [[ $prepare_only -eq 1 ]]; then
  exit 0
fi

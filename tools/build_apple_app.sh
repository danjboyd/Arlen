#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

# shellcheck source=tools/platform.sh
source "$script_dir/platform.sh"
# shellcheck source=tools/apple_build_cache.sh
source "$script_dir/apple_build_cache.sh"

if ! aln_platform_is_macos; then
  echo "build-apple-app: this builder only supports macOS" >&2
  exit 1
fi

app_root="${ARLEN_APP_ROOT:-$PWD}"
framework_root="${ARLEN_FRAMEWORK_ROOT:-$repo_root}"
prepare_only=0
print_path=0
build_tests=0

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
    --build-tests)
      build_tests=1
      shift
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: build_apple_app.sh [--app-root <path>] [--framework-root <path>] [--prepare-only] [--print-path] [--build-tests]

Builds an app-root Arlen server binary for the Apple runtime.
--build-tests also builds tests/**/*.m into .boomhauer/apple/tests/AppTests.xctest
(used by `arlen test --app`); --print-path then prints the bundle path.
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

sdk_path="$(aln_apple_sdk_path)"
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
mkdir -p "$obj_root"

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
  -lcurl
  -isysroot "$sdk_path"
  -arch arm64
  -L"$openssl_prefix/lib"
  -framework Foundation
  -framework CoreFoundation
  -lcrypto
)

aln_apple_reset_on_flag_change "$obj_root" "$("$clang_path" --version)" \
  "${objc_flags[@]}" -- "${link_flags[@]}"

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
  if aln_apple_object_is_current "$src" "$obj"; then
    return 0
  fi
  mkdir -p "$(dirname "$obj")"
  "$clang_path" "${objc_flags[@]}" -MMD -MF "${obj%.o}.d" -c "$src" -o "$obj"
}

# eocc --manifest reuses unchanged outputs, so generated sources keep their
# mtimes and their objects stay current. Each module gets its own output
# directory so a removed module's sources can be dropped. Sets
# generated_sources to the outputs of the current templates only, so a stale
# file left in the gen tree is never compiled.
transpile_app_templates() {
  mkdir -p "$app_template_root" "$module_template_root"
  generated_sources=()

  template_files=()
  if [[ -d "$app_root/templates" ]]; then
    while IFS= read -r template_path; do
      template_files+=("$template_path")
    done < <(find "$app_root/templates" -type f -name '*.html.eoc' | sort)
  fi
  if [[ ${#template_files[@]} -eq 0 ]]; then
    rm -rf "$app_template_root"
  else
    aln_apple_reset_generated_if_stale "$app_template_root" "$eocc_bin" "$app_template_root/manifest.json"
    "$eocc_bin" \
        --template-root "$app_root/templates" \
        --output-dir "$app_template_root" \
        --manifest "$app_template_root/manifest.json" \
      "${template_files[@]}" 1>&2
    for template_path in "${template_files[@]}"; do
      generated_sources+=("$app_template_root/${template_path#"$app_root/templates"/}.m")
    done
  fi

  local active_modules=" "
  if [[ -d "$app_root/modules" ]]; then
    while IFS= read -r module_root; do
      module_id="$(basename "$module_root")"
      template_root="$module_root/Resources/Templates"
      if [[ ! -d "$template_root" ]]; then
        continue
      fi
      # An app template at templates/modules/<id>/<path> overrides the
      # module's own; it is transpiled with the app templates instead.
      module_templates=()
      while IFS= read -r template_path; do
        if [[ -f "$app_root/templates/modules/$module_id/${template_path#"$template_root"/}" ]]; then
          continue
        fi
        module_templates+=("$template_path")
      done < <(find "$template_root" -type f -name '*.html.eoc' | sort)
      if [[ ${#module_templates[@]} -eq 0 ]]; then
        continue
      fi
      active_modules+="$module_id "
      module_out="$module_template_root/$module_id"
      aln_apple_reset_generated_if_stale "$module_out" "$eocc_bin" "$module_out/manifest.json"
      "$eocc_bin" \
        --template-root "$template_root" \
        --output-dir "$module_out" \
        --manifest "$module_out/manifest.json" \
        --logical-prefix "modules/$module_id" \
        "${module_templates[@]}" 1>&2
      for template_path in "${module_templates[@]}"; do
        generated_sources+=("$module_out/modules/$module_id/${template_path#"$template_root"/}.m")
      done
    done < <(find "$app_root/modules" -mindepth 1 -maxdepth 1 -type d | sort)
  fi

  local module_out
  while IFS= read -r module_out; do
    if [[ "$active_modules" != *" $(basename "$module_out") "* ]]; then
      rm -rf "$module_out"
    fi
  done < <(find "$module_template_root" -mindepth 1 -maxdepth 1 2>/dev/null | sort)
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

link_manifest="$obj_root/.link/boomhauer-app.inputs"
if ! aln_apple_link_is_current "$link_manifest" "$app_binary" "${app_objects[@]}" "$framework_lib"; then
  "$clang_path" "${objc_flags[@]}" "${app_objects[@]}" "$framework_lib" -o "$app_binary" "${link_flags[@]}"
  aln_apple_record_link_inputs "$link_manifest" "${app_objects[@]}" "$framework_lib"
fi

# App test bundle (arlen test --app). Mirrors boomhauer --build-tests on
# GNUstep: the app's objects are reused, except files defining main() are
# recompiled with main renamed to ALNAppMain, and a generated entry hands that
# to ALNTestClient so tests see the app's route registration.
build_app_test_bundle() {
  local framework_dir
  framework_dir="$(xcrun --show-sdk-platform-path)/Developer/Library/Frameworks"
  local test_root="$app_build_root/tests"
  local bundle_root="$test_root/AppTests.xctest"
  local bundle_bin="$bundle_root/Contents/MacOS/AppTests"
  local entry="$test_root/aln_app_test_entry.m"
  local test_flags=("${objc_flags[@]}" -F"$framework_dir" -I"$app_root/tests")
  local main_flags=("${objc_flags[@]}" -Dmain=ALNAppMain)
  mkdir -p "$test_root"

  cat >"$entry.tmp" <<'ENTRY'
// Generated by build_apple_app.sh --build-tests. Do not edit.
#import "ALNTestClient.h"
extern int ALNAppMain(int argc, const char *const *argv) __attribute__((weak_import));
__attribute__((constructor)) static void ALNRegisterAppMainForTests(void) {
  if (ALNAppMain != NULL) {
    ALNTestClientSetAppMain(&ALNAppMain);
  }
}
ENTRY
  if cmp -s "$entry.tmp" "$entry"; then
    rm -f "$entry.tmp"
  else
    mv "$entry.tmp" "$entry"
  fi

  local linked_objects=()
  local src obj rel
  for src in "${app_sources[@]}"; do
    obj="$(obj_path_for "$src")"
    if [[ "$src" == "$app_root/"* ]] && grep -Eq '(^|[^A-Za-z0-9_])main[[:space:]]*\(' "$src"; then
      rel="${src#$app_root/}"
      obj="$obj_root/test-main/$rel.o"
      if ! aln_apple_object_is_current "$src" "$obj"; then
        mkdir -p "$(dirname "$obj")"
        "$clang_path" "${main_flags[@]}" -MMD -MF "${obj%.o}.d" -c "$src" -o "$obj"
      fi
    fi
    linked_objects+=("$obj")
  done
  if (( ${#generated_sources[@]} > 0 )); then
    for src in "${generated_sources[@]}"; do
      linked_objects+=("$(obj_path_for "$src")")
    done
  fi

  local test_sources=()
  while IFS= read -r src; do
    test_sources+=("$src")
  done < <(find "$app_root/tests" -type f -name '*.m' 2>/dev/null | sort)
  test_sources+=("$entry")

  for src in "${test_sources[@]}"; do
    rel="${src#$app_root/}"
    rel="${rel#$app_build_root/}"
    obj="$obj_root/test/$rel.o"
    if ! aln_apple_object_is_current "$src" "$obj"; then
      mkdir -p "$(dirname "$obj")"
      "$clang_path" "${test_flags[@]}" -MMD -MF "${obj%.o}.d" -c "$src" -o "$obj"
    fi
    linked_objects+=("$obj")
  done

  local manifest="$obj_root/.link/AppTests.inputs"
  if ! aln_apple_link_is_current "$manifest" "$bundle_bin" "${linked_objects[@]}" "$framework_lib"; then
    rm -rf "$bundle_root"
    mkdir -p "$bundle_root/Contents/MacOS"
    "$clang_path" "${objc_flags[@]}" -F"$framework_dir" "${linked_objects[@]}" "$framework_lib" \
      -bundle -o "$bundle_bin" "${link_flags[@]}" -F"$framework_dir" -framework XCTest \
      -Wl,-U,_ALNAppMain
    aln_apple_record_link_inputs "$manifest" "${linked_objects[@]}" "$framework_lib"
  fi
  cat >"$bundle_root/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>AppTests</string>
  <key>CFBundleIdentifier</key>
  <string>com.arlen.app.tests</string>
  <key>CFBundleName</key>
  <string>AppTests</string>
  <key>CFBundlePackageType</key>
  <string>BNDL</string>
  <key>NSPrincipalClass</key>
  <string>NSObject</string>
</dict>
</plist>
PLIST
  app_test_bundle="$bundle_root"
}

app_test_bundle=""
if [[ $build_tests -eq 1 ]]; then
  build_app_test_bundle
fi

if [[ $print_path -eq 1 ]]; then
  if [[ $build_tests -eq 1 ]]; then
    printf '%s\n' "$app_test_bundle"
  else
    printf '%s\n' "$app_binary"
  fi
fi

if [[ $prepare_only -eq 1 ]]; then
  exit 0
fi

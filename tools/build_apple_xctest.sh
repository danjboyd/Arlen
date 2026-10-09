#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

# shellcheck source=tools/platform.sh
source "$script_dir/platform.sh"
# shellcheck source=tools/apple_build_cache.sh
source "$script_dir/apple_build_cache.sh"

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
Usage: build_apple_xctest.sh [--suite unit|integration|durable-jobs] [--print-bundle-path]

Builds Apple XCTest bundles under build/apple/tests/.

  unit          tests/unit (default)
  integration   tests/integration, plus the example servers it launches
  durable-jobs  tests/durable_jobs, plus build/apple/durable-job-probe
USAGE
      exit 0
      ;;
    *)
      echo "build-apple-xctest: unknown option $1" >&2
      exit 2
      ;;
  esac
done

case "$suite" in
  unit) bundle_name="ArlenUnitTests" ;;
  integration) bundle_name="ArlenIntegrationTests" ;;
  durable-jobs) bundle_name="ArlenDurableJobsTests" ;;
  *)
    echo "build-apple-xctest: unsupported suite '$suite' (supported: unit, integration, durable-jobs)" >&2
    exit 2
    ;;
esac

if ! command -v xcrun >/dev/null 2>&1; then
  echo "build-apple-xctest: xcrun is required" >&2
  exit 1
fi

sdk_path="$(aln_apple_sdk_path)"
platform_path="$(cd "$(xcrun --show-sdk-platform-path)" && pwd -P)"
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
bundle_root="$tests_root/$bundle_name.xctest"
bundle_bin="$bundle_root/Contents/MacOS/$bundle_name"
framework_lib="$build_root/lib/libArlenFramework.a"
eocc_bin="$build_root/eocc"
generated_root="$build_root/gen/templates"
module_generated_root="$build_root/gen/apple-test-modules"
mkdir -p "$tests_root" "$obj_root"

# The Objective-C suites launch repo-root build/ binaries (./build/arlen,
# ./build/boomhauer, ...). On macOS those live under build/apple/, so build/
# gets small exec wrappers. A real binary already at the path is kept; a
# wrapper is rewritten so it follows the current target.
ensure_wrapper() {
  local target="$1"
  local destination="$2"
  if [[ -e "$destination" && "$(head -c 2 "$destination")" != "#!" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$destination")"
  cat >"$destination" <<EOF
#!/usr/bin/env bash
exec "$target" "\$@"
EOF
  chmod 755 "$destination"
}

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
tool_link_flags=(
  -lcurl
  -isysroot "$sdk_path"
  -arch arm64
  -F"$framework_dir"
  -L"$openssl_prefix/lib"
  -framework Foundation
  -framework CoreFoundation
  -lcrypto
)
link_flags=("${tool_link_flags[@]}" -bundle -framework XCTest)

aln_apple_reset_on_flag_change "$obj_root" "$("$clang_path" --version)" \
  "${objc_flags[@]}" -- "${link_flags[@]}"

obj_path_for() {
  local src="$1"
  local rel="${src#$repo_root/}"
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

# compile_sources <src...>: compiles each source and sets compiled_objects
# to their object paths. Runs in the main shell so a compile error stops the
# build under set -e.
compile_sources() {
  compiled_objects=()
  local src
  local obj
  for src in "$@"; do
    obj="$(obj_path_for "$src")"
    compile_objc "$src" "$obj"
    compiled_objects+=("$obj")
  done
}

# link_tool_if_stale <output> <input...>
link_tool_if_stale() {
  local output="$1"
  shift
  local manifest="$obj_root/.link/tools/$(basename "$output").inputs"
  if aln_apple_link_is_current "$manifest" "$output" "$@"; then
    return 0
  fi
  "$clang_path" "${objc_flags[@]}" "$@" -o "$output" "${tool_link_flags[@]}"
  aln_apple_record_link_inputs "$manifest" "$@"
}

# transpile_templates <template_root> <output_dir> [eocc args...]
# Reuses unchanged outputs through the eocc manifest. Fails when the root has
# no templates.
transpile_templates() {
  local template_root="$1"
  local output_dir="$2"
  shift 2
  local templates=()
  local template_path
  while IFS= read -r template_path; do
    templates+=("$template_path")
  done < <(find "$template_root" -type f -name '*.html.eoc' 2>/dev/null | sort)
  if [[ ${#templates[@]} -eq 0 ]]; then
    rm -rf "$output_dir"
    return 1
  fi
  aln_apple_reset_generated_if_stale "$output_dir" "$eocc_bin" "$output_dir/manifest.json"
  "$eocc_bin" \
    --template-root "$template_root" \
    --output-dir "$output_dir" \
    --manifest "$output_dir/manifest.json" \
    ${@+"$@"} \
    "${templates[@]}" >/dev/null
}

# Each module gets its own eocc output directory and manifest so unchanged
# outputs are reused and a removed module's sources can be dropped.
module_generated_sources=()
mkdir -p "$module_generated_root"
active_modules=" "
while IFS= read -r module_root; do
  module_id="$(basename "$module_root")"
  module_out="$module_generated_root/$module_id"
  if transpile_templates "$module_root/Resources/Templates" "$module_out" \
      --logical-prefix "modules/$module_id"; then
    active_modules+="$module_id "
  fi
done < <(find "$repo_root/modules" -mindepth 1 -maxdepth 1 -type d | sort)

while IFS= read -r module_out; do
  if [[ "$active_modules" != *" $(basename "$module_out") "* ]]; then
    rm -rf "$module_out"
  fi
done < <(find "$module_generated_root" -mindepth 1 -maxdepth 1 | sort)

while IFS= read -r src; do
  module_generated_sources+=("$src")
done < <(find "$module_generated_root" -type f -name '*.m' 2>/dev/null | sort)

sources=()
case "$suite" in
  unit|integration)
    while IFS= read -r src; do
      sources+=("$src")
    done < <(find "$repo_root/tests/shared" "$repo_root/tests/$suite" -type f -name '*.m' | sort)
    while IFS= read -r src; do
      sources+=("$src")
    done < <(find "$generated_root" -type f -name '*.m' 2>/dev/null | sort)
    sources+=(${module_generated_sources[@]+"${module_generated_sources[@]}"})
    ;;
  durable-jobs)
    sources+=("$repo_root/tests/durable_jobs/DurableJobsTests.m" "$repo_root/tests/shared/ALNTestWait.m")
    ;;
esac

compile_sources "${sources[@]}"
objects=("${compiled_objects[@]}")

link_manifest="$obj_root/.link/$bundle_name.inputs"
if ! aln_apple_link_is_current "$link_manifest" "$bundle_bin" "${objects[@]}" "$framework_lib"; then
  rm -rf "$bundle_root"
  mkdir -p "$bundle_root/Contents/MacOS"
  "$clang_path" "${objc_flags[@]}" "${objects[@]}" "$framework_lib" -o "$bundle_bin" "${link_flags[@]}"
  aln_apple_record_link_inputs "$link_manifest" "${objects[@]}" "$framework_lib"
fi
sed -e "s/ArlenUnitTests/$bundle_name/g" -e "s/com\.arlen\.tests\.apple\.unit/com.arlen.tests.apple.$suite/" \
  "$repo_root/tests/Info-apple-unit.plist" >"$bundle_root/Contents/Info.plist"

# Binaries the suites launch, matching the GNUstep build's build/ outputs.
case "$suite" in
  integration)
    compile_sources ${module_generated_sources[@]+"${module_generated_sources[@]}"}
    module_generated_objects=(${compiled_objects[@]+"${compiled_objects[@]}"})

    tech_demo_generated_objects=()
    tech_demo_gen_root="$build_root/gen/tech_demo_templates"
    if transpile_templates "$repo_root/examples/tech_demo/templates" "$tech_demo_gen_root"; then
      tech_demo_generated_sources=()
      while IFS= read -r src; do
        tech_demo_generated_sources+=("$src")
      done < <(find "$tech_demo_gen_root" -type f -name '*.m' | sort)
      compile_sources "${tech_demo_generated_sources[@]}"
      tech_demo_generated_objects=("${compiled_objects[@]}")
    fi

    root_generated_sources=()
    while IFS= read -r src; do
      root_generated_sources+=("$src")
    done < <(find "$generated_root" -type f -name '*.m' 2>/dev/null | sort)
    compile_sources "$repo_root/tools/eoc_smoke_render.m" ${root_generated_sources[@]+"${root_generated_sources[@]}"}
    link_tool_if_stale "$build_root/eoc-smoke-render" "${compiled_objects[@]}" "$framework_lib"
    ensure_wrapper "$build_root/eoc-smoke-render" "$repo_root/build/eoc-smoke-render"

    for server in \
      tech_demo/src/tech_demo_server \
      api_reference/src/api_reference_server \
      auth_primitives/src/auth_primitives_server \
      gsweb_migration/src/migration_sample_server
    do
      server_name="$(basename "$server" | tr '_' '-')"
      compile_sources "$repo_root/examples/$server.m"
      server_inputs=("${compiled_objects[@]}")
      server_inputs+=(${module_generated_objects[@]+"${module_generated_objects[@]}"})
      if [[ "$server_name" == "tech-demo-server" ]]; then
        server_inputs+=(${tech_demo_generated_objects[@]+"${tech_demo_generated_objects[@]}"})
      fi
      link_tool_if_stale "$build_root/$server_name" "${server_inputs[@]}" "$framework_lib"
      ensure_wrapper "$build_root/$server_name" "$repo_root/build/$server_name"
    done
    ;;
  durable-jobs)
    compile_sources "$repo_root/tests/durable_jobs/job_probe.m"
    link_tool_if_stale "$build_root/durable-job-probe" "${compiled_objects[@]}" "$framework_lib"
    ensure_wrapper "$build_root/durable-job-probe" "$repo_root/build/durable-job-probe"
    ;;
esac

ensure_wrapper "$build_root/arlen" "$repo_root/build/arlen"
ensure_wrapper "$build_root/boomhauer" "$repo_root/build/boomhauer"
ensure_wrapper "$build_root/eocc" "$repo_root/build/eocc"

if [[ $print_bundle_path -eq 1 ]]; then
  printf '%s\n' "$bundle_root"
fi

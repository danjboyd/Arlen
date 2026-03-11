#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

output_dir="${ARLEN_PHASE16_OUTPUT_DIR:-$repo_root/build/release_confidence/phase16}"
unit_bundle="${ARLEN_PHASE16_UNIT_BUNDLE:-$repo_root/build/tests/ArlenUnitTests.xctest}"
unit_bin="$unit_bundle/ArlenUnitTests"
focused_bundle="${ARLEN_PHASE16_FOCUSED_BUNDLE:-$repo_root/build/tests/Phase16ModulesOnly.xctest}"
focused_bin="$focused_bundle/ArlenIntegrationTests"
unit_log="$output_dir/phase16_unit.log"
integration_log="$output_dir/phase16_modules_integration.log"

mkdir -p "$output_dir" "${HOME}/GNUstep/Defaults/.lck"
rm -rf "$focused_bundle"
mkdir -p "$focused_bundle/Resources"

set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

make "$unit_bin"
xctest "$unit_bundle" >"$unit_log" 2>&1

mapfile -t framework_srcs < <(find "$repo_root/src" -type f -name '*.m' | sort)
mapfile -t module_srcs < <(find "$repo_root/modules" -type f -path '*/Sources/*.m' | sort)
mapfile -t generated_files < <(find "$repo_root/build/gen/templates" -type f -name '*.m' | sort)
mapfile -t module_generated_files < <(find "$repo_root/build/gen/module_templates" -type f -name '*.m' | sort)
third_party_c_srcs=(
  "$repo_root/src/Arlen/Support/third_party/yyjson/yyjson.c"
  "$repo_root/src/Arlen/Support/third_party/llhttp/llhttp.c"
  "$repo_root/src/Arlen/Support/third_party/llhttp/api.c"
  "$repo_root/src/Arlen/Support/third_party/llhttp/http.c"
  "$repo_root/src/Arlen/Support/third_party/argon2/src/argon2.c"
  "$repo_root/src/Arlen/Support/third_party/argon2/src/core.c"
  "$repo_root/src/Arlen/Support/third_party/argon2/src/encoding.c"
  "$repo_root/src/Arlen/Support/third_party/argon2/src/ref.c"
  "$repo_root/src/Arlen/Support/third_party/argon2/src/blake2/blake2b.c"
)
read -r -a objc_flags <<<"$(gnustep-config --objc-flags)"
read -r -a base_libs <<<"$(gnustep-config --base-libs)"

include_flags=(
  -Isrc/Arlen
  -Isrc/Arlen/Core
  -Isrc/Arlen/Data
  -Isrc/Arlen/HTTP
  -Isrc/Arlen/MVC/Controller
  -Isrc/Arlen/MVC/Middleware
  -Isrc/Arlen/MVC/Routing
  -Isrc/Arlen/MVC/Template
  -Isrc/Arlen/MVC/View
  -Isrc/Arlen/Support
  -Isrc/Arlen/Support/third_party/argon2/include
  -Isrc/Arlen/Support/third_party/argon2/src
  -Isrc/MojoObjc
  -Isrc/MojoObjc/Core
  -Isrc/MojoObjc/Data
  -Isrc/MojoObjc/HTTP
  -Isrc/MojoObjc/MVC/Controller
  -Isrc/MojoObjc/MVC/Middleware
  -Isrc/MojoObjc/MVC/Routing
  -Isrc/MojoObjc/MVC/Template
  -Isrc/MojoObjc/MVC/View
  -Isrc/MojoObjc/Support
  -Imodules/auth/Sources
  -Imodules/admin-ui/Sources
  -Imodules/jobs/Sources
  -Imodules/notifications/Sources
  -Imodules/storage/Sources
  -Imodules/ops/Sources
  -Imodules/search/Sources
  -I/usr/include/postgresql
)

clang \
  "${objc_flags[@]}" \
  -fobjc-arc \
  -DARLEN_ENABLE_YYJSON=1 \
  -DARLEN_ENABLE_LLHTTP=1 \
  -DARGON2_NO_THREADS=1 \
  "${include_flags[@]}" \
  "$repo_root/tests/integration/Phase16ModuleIntegrationTests.m" \
  "${framework_srcs[@]}" \
  "${module_srcs[@]}" \
  "${third_party_c_srcs[@]}" \
  "${generated_files[@]}" \
  "${module_generated_files[@]}" \
  -shared \
  -fPIC \
  -o "$focused_bin" \
  "${base_libs[@]}" \
  -ldl \
  -lcrypto \
  -lXCTest

cp "$repo_root/tests/Info-gnustep-integration.plist" "$focused_bundle/Resources/Info-gnustep.plist"
xctest "$focused_bundle" >"$integration_log" 2>&1

python3 ./tools/ci/generate_phase16_confidence_artifacts.py \
  --repo-root "$repo_root" \
  --output-dir "$output_dir" \
  --unit-log "$unit_log" \
  --integration-log "$integration_log"

echo "ci: phase16 confidence gate complete"

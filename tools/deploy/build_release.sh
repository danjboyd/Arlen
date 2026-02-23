#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: build_release.sh [options]

Build an immutable Arlen release artifact layout:
  <releases-dir>/<release-id>/
    app/
    framework/
    metadata/

Options:
  --app-root <path>        App root to package (default: cwd)
  --framework-root <path>  Arlen framework root (default: script ../..)
  --releases-dir <path>    Release output root (default: <app-root>/releases)
  --release-id <id>        Explicit release id (default: UTC timestamp)
  --dry-run                Validate inputs and emit planned release metadata only
  --json                   Emit machine-readable workflow payloads
  --help                   Show this help
USAGE
}

json_escape() {
  local value="${1:-}"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
default_framework_root="$(cd "$script_dir/../.." && pwd)"

app_root="$PWD"
framework_root="$default_framework_root"
releases_dir=""
release_id="$(date -u +%Y%m%dT%H%M%SZ)"
dry_run=0
output_json=0

emit_error() {
  local code="$1"
  local message="$2"
  local fixit_action="$3"
  local fixit_example="$4"
  local exit_code="${5:-1}"

  if [[ "$output_json" == "1" ]]; then
    printf '{'
    printf '"version":"phase7g-agent-dx-contracts-v1",'
    printf '"workflow":"deploy.build_release",'
    printf '"status":"error",'
    printf '"error":{"code":"%s","message":"%s","fixit":{"action":"%s","example":"%s"}},' \
      "$(json_escape "$code")" \
      "$(json_escape "$message")" \
      "$(json_escape "$fixit_action")" \
      "$(json_escape "$fixit_example")"
    printf '"exit_code":%s' "$exit_code"
    printf '}\n'
  else
    echo "build_release.sh: $message" >&2
    if [[ -n "$fixit_action" ]]; then
      echo "build_release.sh: hint: $fixit_action" >&2
    fi
    if [[ -n "$fixit_example" ]]; then
      echo "build_release.sh: example: $fixit_example" >&2
    fi
  fi
  exit "$exit_code"
}

emit_success_json() {
  local status="$1"
  local release_dir="$2"
  local latest_built="$3"
  printf '{'
  printf '"version":"phase7g-agent-dx-contracts-v1",'
  printf '"workflow":"deploy.build_release",'
  printf '"status":"%s",' "$(json_escape "$status")"
  printf '"app_root":"%s",' "$(json_escape "$app_root")"
  printf '"framework_root":"%s",' "$(json_escape "$framework_root")"
  printf '"releases_dir":"%s",' "$(json_escape "$releases_dir")"
  printf '"release_id":"%s",' "$(json_escape "$release_id")"
  printf '"release_dir":"%s"' "$(json_escape "$release_dir")"
  if [[ -n "$latest_built" ]]; then
    printf ',"latest_built_symlink":"%s"' "$(json_escape "$latest_built")"
  fi
  printf '}\n'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-root)
      [[ $# -ge 2 ]] || emit_error \
        "missing_option_value" \
        "--app-root requires a value" \
        "Pass an absolute or relative app root path after --app-root." \
        "tools/deploy/build_release.sh --app-root /path/to/app --framework-root /path/to/Arlen" \
        2
      app_root="$2"
      shift 2
      ;;
    --framework-root)
      [[ $# -ge 2 ]] || emit_error \
        "missing_option_value" \
        "--framework-root requires a value" \
        "Pass the Arlen checkout path after --framework-root." \
        "tools/deploy/build_release.sh --framework-root /path/to/Arlen --app-root /path/to/app" \
        2
      framework_root="$2"
      shift 2
      ;;
    --releases-dir)
      [[ $# -ge 2 ]] || emit_error \
        "missing_option_value" \
        "--releases-dir requires a value" \
        "Provide a releases output directory after --releases-dir." \
        "tools/deploy/build_release.sh --releases-dir /path/to/app/releases --app-root /path/to/app" \
        2
      releases_dir="$2"
      shift 2
      ;;
    --release-id)
      [[ $# -ge 2 ]] || emit_error \
        "missing_option_value" \
        "--release-id requires a value" \
        "Provide an explicit release id after --release-id." \
        "tools/deploy/build_release.sh --release-id rel-20260223 --app-root /path/to/app" \
        2
      release_id="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --json)
      output_json=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      emit_error \
        "unknown_option" \
        "unknown option: $1" \
        "Use --help to review supported options." \
        "tools/deploy/build_release.sh --help" \
        2
      ;;
  esac
done

if [[ ! -d "$app_root" ]]; then
  emit_error \
    "app_root_not_found" \
    "app root path does not exist: $app_root" \
    "Create the app directory first or pass the correct --app-root path." \
    "tools/deploy/build_release.sh --app-root /path/to/app --framework-root /path/to/Arlen" \
    1
fi
if [[ ! -d "$framework_root" ]]; then
  emit_error \
    "framework_root_not_found" \
    "framework root path does not exist: $framework_root" \
    "Pass a valid Arlen checkout path via --framework-root." \
    "tools/deploy/build_release.sh --framework-root /path/to/Arlen --app-root /path/to/app" \
    1
fi

app_root="$(cd "$app_root" && pwd)"
framework_root="$(cd "$framework_root" && pwd)"

if [[ -z "$releases_dir" ]]; then
  releases_dir="$app_root/releases"
fi
mkdir -p "$releases_dir"
releases_dir="$(cd "$releases_dir" && pwd)"

if [[ ! -f "$framework_root/GNUmakefile" || ! -d "$framework_root/src/Arlen" ]]; then
  emit_error \
    "invalid_framework_root" \
    "invalid framework root: $framework_root" \
    "Point --framework-root at an Arlen checkout containing GNUmakefile and src/Arlen." \
    "tools/deploy/build_release.sh --framework-root /path/to/Arlen --app-root /path/to/app" \
    1
fi

if [[ ! -d "$app_root/config" ]]; then
  emit_error \
    "missing_app_config" \
    "app root missing config directory: $app_root" \
    "Run from a valid app root or scaffold one with `arlen new` first." \
    "cd /path/to/work && /path/to/Arlen/build/arlen new DemoApp --full" \
    1
fi

release_dir="$releases_dir/$release_id"
if [[ -e "$release_dir" ]]; then
  emit_error \
    "release_exists" \
    "release already exists: $release_dir" \
    "Choose a unique --release-id or remove the existing release directory." \
    "tools/deploy/build_release.sh --release-id rel2 --app-root /path/to/app" \
    1
fi

if [[ "$dry_run" == "1" ]]; then
  if [[ "$output_json" == "1" ]]; then
    emit_success_json "planned" "$release_dir" "$releases_dir/latest-built"
  else
    echo "build_release.sh dry-run: release_dir=$release_dir"
  fi
  exit 0
fi

make -C "$framework_root" arlen boomhauer >/dev/null

mkdir -p "$release_dir/app" "$release_dir/framework" "$release_dir/metadata"

copy_if_exists() {
  local src="$1"
  local dest="$2"
  if [[ -e "$src" ]]; then
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
  fi
}

# Package app payload.
copy_if_exists "$app_root/config" "$release_dir/app/config"
copy_if_exists "$app_root/public" "$release_dir/app/public"
copy_if_exists "$app_root/templates" "$release_dir/app/templates"
copy_if_exists "$app_root/src" "$release_dir/app/src"
copy_if_exists "$app_root/app_lite.m" "$release_dir/app/app_lite.m"

# Package runtime/tooling payload used by deploy scripts.
copy_if_exists "$framework_root/bin" "$release_dir/framework/bin"
copy_if_exists "$framework_root/build/boomhauer" "$release_dir/framework/build/boomhauer"
copy_if_exists "$framework_root/build/arlen" "$release_dir/framework/build/arlen"

cat >"$release_dir/metadata/release.env" <<EOF
RELEASE_ID=$release_id
RELEASE_CREATED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ARLEN_APP_ROOT=$release_dir/app
ARLEN_FRAMEWORK_ROOT=$release_dir/framework
EOF

cat >"$release_dir/metadata/README.txt" <<EOF
Release: $release_id

Run migrate step before switching traffic:
  cd "$release_dir/app" && "$release_dir/framework/build/arlen" migrate --env production

Run propane from this release:
  ARLEN_APP_ROOT="$release_dir/app" ARLEN_FRAMEWORK_ROOT="$release_dir/framework" \
    "$release_dir/framework/bin/propane" --env production
EOF

ln -sfn "$release_dir" "$releases_dir/latest-built"
if [[ "$output_json" == "1" ]]; then
  emit_success_json "ok" "$release_dir" "$releases_dir/latest-built"
else
  echo "release built: $release_dir"
fi

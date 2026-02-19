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
  --help                   Show this help
USAGE
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
default_framework_root="$(cd "$script_dir/../.." && pwd)"

app_root="$PWD"
framework_root="$default_framework_root"
releases_dir=""
release_id="$(date -u +%Y%m%dT%H%M%SZ)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-root)
      [[ $# -ge 2 ]] || { echo "build_release.sh: --app-root requires a value" >&2; exit 2; }
      app_root="$2"
      shift 2
      ;;
    --framework-root)
      [[ $# -ge 2 ]] || { echo "build_release.sh: --framework-root requires a value" >&2; exit 2; }
      framework_root="$2"
      shift 2
      ;;
    --releases-dir)
      [[ $# -ge 2 ]] || { echo "build_release.sh: --releases-dir requires a value" >&2; exit 2; }
      releases_dir="$2"
      shift 2
      ;;
    --release-id)
      [[ $# -ge 2 ]] || { echo "build_release.sh: --release-id requires a value" >&2; exit 2; }
      release_id="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "build_release.sh: unknown option: $1" >&2
      exit 2
      ;;
  esac
done

app_root="$(cd "$app_root" && pwd)"
framework_root="$(cd "$framework_root" && pwd)"

if [[ -z "$releases_dir" ]]; then
  releases_dir="$app_root/releases"
fi
mkdir -p "$releases_dir"
releases_dir="$(cd "$releases_dir" && pwd)"

if [[ ! -f "$framework_root/GNUmakefile" || ! -d "$framework_root/src/Arlen" ]]; then
  echo "build_release.sh: invalid framework root: $framework_root" >&2
  exit 1
fi

if [[ ! -d "$app_root/config" ]]; then
  echo "build_release.sh: app root missing config directory: $app_root" >&2
  exit 1
fi

make -C "$framework_root" arlen boomhauer >/dev/null

release_dir="$releases_dir/$release_id"
if [[ -e "$release_dir" ]]; then
  echo "build_release.sh: release already exists: $release_dir" >&2
  exit 1
fi

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
echo "release built: $release_dir"

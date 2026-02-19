#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: activate_release.sh --release-id <id> [--releases-dir <path>]

Switch releases/current symlink to the selected immutable release.
USAGE
}

releases_dir="$PWD/releases"
release_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --releases-dir)
      [[ $# -ge 2 ]] || { echo "activate_release.sh: --releases-dir requires a value" >&2; exit 2; }
      releases_dir="$2"
      shift 2
      ;;
    --release-id)
      [[ $# -ge 2 ]] || { echo "activate_release.sh: --release-id requires a value" >&2; exit 2; }
      release_id="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "activate_release.sh: unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$release_id" ]]; then
  echo "activate_release.sh: --release-id is required" >&2
  exit 2
fi

mkdir -p "$releases_dir"
releases_dir="$(cd "$releases_dir" && pwd)"
release_dir="$releases_dir/$release_id"

if [[ ! -d "$release_dir" ]]; then
  echo "activate_release.sh: release not found: $release_dir" >&2
  exit 1
fi

ln -sfn "$release_dir" "$releases_dir/current"
echo "release activated: $release_dir"

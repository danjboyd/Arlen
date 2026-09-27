#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: activate_release.sh --release-id <id> [--releases-dir <path>] [--shared-dir <path>]

Switch releases/current symlink to the selected immutable release.

Paths listed in <release>/metadata/shared_paths are first linked from
<shared-dir>/<path> (default: <releases-dir>/../shared) into <release>/app/<path>.
USAGE
}

releases_dir="$PWD/releases"
release_id=""
shared_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --releases-dir)
      [[ $# -ge 2 ]] || { echo "activate_release.sh: --releases-dir requires a value" >&2; exit 2; }
      releases_dir="$2"
      shift 2
      ;;
    --shared-dir)
      [[ $# -ge 2 ]] || { echo "activate_release.sh: --shared-dir requires a value" >&2; exit 2; }
      shared_dir="$2"
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
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$release_dir" ]]; then
  echo "activate_release.sh: release not found: $release_dir" >&2
  exit 1
fi

# Shared paths (GitHub issue 66): persistent data such as uploads lives in
# shared/<path> and every release links to it, so a new release keeps it. While
# shared/<path> is missing or empty, activation seeds it from whatever the release
# packaged there; after that the shared copy wins and packaged content at that
# path is replaced.
shared_paths_file="$release_dir/metadata/shared_paths"
if [[ -f "$shared_paths_file" ]]; then
  if [[ -z "$shared_dir" ]]; then
    shared_dir="$releases_dir/../shared"
  fi
  mkdir -p "$shared_dir"
  shared_dir="$(cd "$shared_dir" && pwd)"
  while IFS= read -r shared_path || [[ -n "$shared_path" ]]; do
    [[ -n "$shared_path" ]] || continue
    if [[ "$shared_path" == /* || "/$shared_path/" == */../* || "/$shared_path/" == */./* ]]; then
      echo "activate_release.sh: invalid shared path in $shared_paths_file: $shared_path" >&2
      exit 1
    fi
    shared_target="$shared_dir/$shared_path"
    release_link="$release_dir/app/$shared_path"
    mkdir -p "$(dirname "$shared_target")" "$(dirname "$release_link")"
    if [[ -e "$release_link" && ! -L "$release_link" ]]; then
      # Seed when shared/ has nothing yet (deploy init leaves it empty).
      if [[ -d "$shared_target" && ! -L "$shared_target" && -z "$(ls -A "$shared_target")" ]]; then
        rmdir "$shared_target"
      fi
      if [[ ! -e "$shared_target" ]]; then
        mv "$release_link" "$shared_target"
      else
        rm -rf "$release_link"
      fi
    fi
    [[ -e "$shared_target" ]] || mkdir -p "$shared_target"
    ln -sfn "$shared_target" "$release_link"
  done <"$shared_paths_file"
fi

"$script_dir/write_release_env.py" "$release_dir"
ln -sfn "$release_dir" "$releases_dir/current"
echo "release activated: $release_dir"

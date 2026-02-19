#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: rollback_release.sh [--release-id <id>] [--releases-dir <path>]

Rollback releases/current to a previous release.
If --release-id is omitted, selects the most recent release directory
that is not currently active.
USAGE
}

releases_dir="$PWD/releases"
target_release_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --releases-dir)
      [[ $# -ge 2 ]] || { echo "rollback_release.sh: --releases-dir requires a value" >&2; exit 2; }
      releases_dir="$2"
      shift 2
      ;;
    --release-id)
      [[ $# -ge 2 ]] || { echo "rollback_release.sh: --release-id requires a value" >&2; exit 2; }
      target_release_id="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "rollback_release.sh: unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$releases_dir" ]]; then
  echo "rollback_release.sh: releases directory not found: $releases_dir" >&2
  exit 1
fi
releases_dir="$(cd "$releases_dir" && pwd)"

current_target=""
if [[ -L "$releases_dir/current" ]]; then
  current_target="$(readlink -f "$releases_dir/current" || true)"
fi

if [[ -z "$target_release_id" ]]; then
  mapfile -t candidates < <(find "$releases_dir" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort -r)
  for candidate in "${candidates[@]}"; do
    candidate_path="$releases_dir/$candidate"
    if [[ "$candidate_path" == "$current_target" ]]; then
      continue
    fi
    target_release_id="$candidate"
    break
  done
fi

if [[ -z "$target_release_id" ]]; then
  echo "rollback_release.sh: no rollback target found" >&2
  exit 1
fi

target_path="$releases_dir/$target_release_id"
if [[ ! -d "$target_path" ]]; then
  echo "rollback_release.sh: release not found: $target_path" >&2
  exit 1
fi

ln -sfn "$target_path" "$releases_dir/current"
echo "rollback activated: $target_path"

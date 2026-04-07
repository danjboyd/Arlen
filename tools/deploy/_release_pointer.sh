#!/usr/bin/env bash
set -euo pipefail

arlen_deploy_is_windows_host() {
  case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*)
      return 0
      ;;
  esac
  return 1
}

arlen_deploy_pointer_metadata_path() {
  local pointer_path="$1"
  printf '%s.release-id\n' "$pointer_path"
}

arlen_deploy_native_path() {
  local path="$1"
  if arlen_deploy_is_windows_host && command -v cygpath >/dev/null 2>&1; then
    cygpath -aw "$path"
    return 0
  fi
  printf '%s\n' "$path"
}

arlen_deploy_resolved_artifact_path() {
  local base_path="$1"
  if [[ -x "$base_path" || -f "$base_path" ]]; then
    printf '%s\n' "$base_path"
    return 0
  fi
  if [[ "$base_path" != *.exe ]] && [[ -x "${base_path}.exe" || -f "${base_path}.exe" ]]; then
    printf '%s\n' "${base_path}.exe"
    return 0
  fi
  return 1
}

arlen_deploy_copy_artifact_to_dir() {
  local base_path="$1"
  local destination_dir="$2"
  local resolved_path=""

  resolved_path="$(arlen_deploy_resolved_artifact_path "$base_path" 2>/dev/null || true)"
  if [[ -z "$resolved_path" ]]; then
    return 1
  fi

  mkdir -p "$destination_dir"
  cp -a "$resolved_path" "$destination_dir/$(basename "$resolved_path")"
}

arlen_deploy_remove_pointer() {
  local pointer_path="$1"
  local metadata_path=""
  metadata_path="$(arlen_deploy_pointer_metadata_path "$pointer_path")"
  rm -f "$metadata_path"

  if [[ ! -e "$pointer_path" && ! -L "$pointer_path" ]]; then
    return 0
  fi

  if arlen_deploy_is_windows_host; then
    local native_pointer=""
    native_pointer="$(arlen_deploy_native_path "$pointer_path")"
    cmd.exe /d /c "if exist \"$native_pointer\" rmdir \"$native_pointer\"" >/dev/null
    return 0
  fi

  rm -rf "$pointer_path"
}

arlen_deploy_write_pointer_metadata() {
  local pointer_path="$1"
  local release_id="$2"
  local metadata_path=""
  metadata_path="$(arlen_deploy_pointer_metadata_path "$pointer_path")"
  printf '%s\n' "$release_id" >"$metadata_path"
}

arlen_deploy_set_pointer() {
  local pointer_path="$1"
  local target_path="$2"
  local release_id="$3"

  mkdir -p "$(dirname "$pointer_path")"
  arlen_deploy_remove_pointer "$pointer_path"

  if arlen_deploy_is_windows_host; then
    local native_pointer=""
    local native_target=""
    native_pointer="$(arlen_deploy_native_path "$pointer_path")"
    native_target="$(arlen_deploy_native_path "$target_path")"
    cmd.exe /d /c "mklink /J \"$native_pointer\" \"$native_target\"" >/dev/null
  else
    ln -sfn "$target_path" "$pointer_path"
  fi

  arlen_deploy_write_pointer_metadata "$pointer_path" "$release_id"
}

arlen_deploy_resolved_release_id() {
  local pointer_path="$1"
  local metadata_path=""
  metadata_path="$(arlen_deploy_pointer_metadata_path "$pointer_path")"
  if [[ -f "$metadata_path" ]]; then
    tr -d '\r\n' <"$metadata_path"
    return 0
  fi

  if [[ -L "$pointer_path" ]]; then
    basename "$(readlink -f "$pointer_path")"
    return 0
  fi

  return 1
}

arlen_deploy_resolved_release_path() {
  local releases_dir="$1"
  local pointer_path="$2"
  local release_id=""
  release_id="$(arlen_deploy_resolved_release_id "$pointer_path" || true)"
  if [[ -z "$release_id" ]]; then
    return 1
  fi
  printf '%s/%s\n' "$releases_dir" "$release_id"
}

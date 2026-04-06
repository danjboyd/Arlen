#!/usr/bin/env bash

resolve_arlen_ci_gnustep_sh() {
  local gnustep_makefiles_from_config=""
  local candidate=""

  if command -v gnustep-config >/dev/null 2>&1; then
    gnustep_makefiles_from_config="$(gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null || true)"
  fi

  while IFS= read -r candidate; do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done <<EOF
${GNUSTEP_SH:-}
${GNUSTEP_MAKEFILES:+$GNUSTEP_MAKEFILES/GNUstep.sh}
${gnustep_makefiles_from_config:+$gnustep_makefiles_from_config/GNUstep.sh}
/clang64/share/GNUstep/Makefiles/GNUstep.sh
/usr/GNUstep/System/Library/Makefiles/GNUstep.sh
EOF

  return 1
}

arlen_ci_source_gnustep() {
  local resolved_gnustep_sh="${GNUSTEP_SH:-}"
  if [[ -z "$resolved_gnustep_sh" || ! -f "$resolved_gnustep_sh" ]]; then
    resolved_gnustep_sh="$(resolve_arlen_ci_gnustep_sh)" || {
      echo "ci: could not resolve GNUSTEP_SH" >&2
      return 1
    }
    export GNUSTEP_SH="$resolved_gnustep_sh"
  fi

  set +u
  # shellcheck source=/dev/null
  source "$resolved_gnustep_sh"
  set -u
}

arlen_ci_is_windows_preview() {
  local host_os=""
  host_os="${GNUSTEP_HOST_OS:-$(gnustep-config --variable=GNUSTEP_HOST_OS 2>/dev/null || true)}"
  case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*)
      return 0
      ;;
  esac
  [[ "$host_os" == *mingw* ]]
}

arlen_ci_prepend_path() {
  local entry="${1:-}"
  if [[ -z "$entry" ]]; then
    return 0
  fi
  if [[ -z "${PATH:-}" ]]; then
    export PATH="$entry"
  else
    export PATH="$entry:$PATH"
  fi
}

arlen_ci_resolve_binary_path() {
  local base_path="${1:-}"
  if [[ -z "$base_path" ]]; then
    return 1
  fi
  if [[ -x "${base_path}.exe" || -f "${base_path}.exe" ]]; then
    printf '%s\n' "${base_path}.exe"
    return 0
  fi
  if [[ -x "$base_path" || -f "$base_path" ]]; then
    printf '%s\n' "$base_path"
    return 0
  fi
  printf '%s\n' "$base_path"
}

arlen_ci_configure_asan_ubsan() {
  export EXTRA_OBJC_FLAGS="${EXTRA_OBJC_FLAGS:--fsanitize=address,undefined -fno-omit-frame-pointer}"
  export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0:halt_on_error=1:strict_string_checks=1}"
  export UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=1:halt_on_error=1}"

  if arlen_ci_is_windows_preview; then
    local resource_dir=""
    local runtime_dir=""
    local asan_dll=""
    local ubsan_archive=""

    resource_dir="$(clang -print-resource-dir 2>/dev/null || true)"
    runtime_dir="${resource_dir}/lib/windows"
    asan_dll="${runtime_dir}/libclang_rt.asan_dynamic-x86_64.dll"
    if [[ ! -f "$asan_dll" && -f "/clang64/bin/libclang_rt.asan_dynamic-x86_64.dll" ]]; then
      asan_dll="/clang64/bin/libclang_rt.asan_dynamic-x86_64.dll"
    fi
    ubsan_archive="${runtime_dir}/libclang_rt.ubsan_standalone-x86_64.a"
    if [[ ! -f "$asan_dll" ]]; then
      echo "ci: unable to locate Windows ASan runtime at $asan_dll" >&2
      return 1
    fi
    if [[ ! -f "$ubsan_archive" ]]; then
      echo "ci: unable to locate Windows UBSan runtime archive at $ubsan_archive" >&2
      return 1
    fi

    runtime_dir="$(dirname "$asan_dll")"
    arlen_ci_prepend_path "$runtime_dir"
    export XCTEST_LD_PRELOAD=""
    export ARLEN_SANITIZER_RUNTIME_DIR="$runtime_dir"
    return 0
  fi

  local asan_so=""
  local ubsan_so=""
  asan_so="$(clang -print-file-name=libasan.so)"
  ubsan_so="$(clang -print-file-name=libubsan.so)"
  if [[ -z "$asan_so" || ! -f "$asan_so" ]]; then
    echo "ci: unable to locate libasan.so" >&2
    return 1
  fi
  if [[ -z "$ubsan_so" || ! -f "$ubsan_so" ]]; then
    echo "ci: unable to locate libubsan.so" >&2
    return 1
  fi

  export XCTEST_LD_PRELOAD="$asan_so:$ubsan_so"
}

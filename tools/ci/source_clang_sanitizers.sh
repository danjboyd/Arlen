#!/usr/bin/env bash
# Source after source_gnustep_env.sh. Keep dlopened XCTest bundles and exec'd
# instrumented children on the same clang runtime; never preload GCC runtimes.
arlen_sanitizer_compiler="${ARLEN_CC:-clang}"
arlen_sanitizer_arch="$("$arlen_sanitizer_compiler" -dumpmachine)"
arlen_sanitizer_arch="${arlen_sanitizer_arch%%-*}"
arlen_asan_runtime="$("$arlen_sanitizer_compiler" -print-file-name="libclang_rt.asan-${arlen_sanitizer_arch}.so")"
if [[ ! -f "$arlen_asan_runtime" ]]; then
  arlen_asan_runtime="$("$arlen_sanitizer_compiler" -print-runtime-dir)/libclang_rt.asan.so"
fi
if [[ ! -f "$arlen_asan_runtime" ]]; then
  echo "sanitizer gate: clang shared ASan runtime is missing" >&2
  return 1
fi
arlen_sanitizer_dir="$(dirname "$arlen_asan_runtime")"
export EXTRA_OBJC_FLAGS="${EXTRA_OBJC_FLAGS:-} -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer -shared-libsan -Wl,-rpath,$arlen_sanitizer_dir -Wno-unused-command-line-argument"
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0:halt_on_error=1:strict_string_checks=1}"
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=1:halt_on_error=1}"
# ASan's clang runtime also supplies UBSan. Preserve caller preloads, placing
# the sanitizer first for its interceptor initialization requirement.
export XCTEST_LD_PRELOAD="$arlen_asan_runtime${XCTEST_LD_PRELOAD:+:$XCTEST_LD_PRELOAD}${LD_PRELOAD:+:$LD_PRELOAD}"

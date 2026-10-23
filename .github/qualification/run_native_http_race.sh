#!/usr/bin/env bash
set -euo pipefail
root="${1:?exact candidate checkout}" harness="${2:?reviewed harness}" out="${3:?new evidence path}"
mkdir -p "$out"
cd "$root"
[[ "$(git rev-parse HEAD)" == "$SOURCE_REF" && -z "$(git status --porcelain)" ]]
[[ ! -e .arlen-runtime && ! -e .arlen-dist ]]
bootstrap_prefix="${ARLEN_RUNTIME_PREFIX:?qualified native normal prefix}"
bootstrap_config="${ARLEN_GNUSTEP_CONFIG_FILE:?private normal configuration}"
source tools/source_gnustep_env.sh
python3 tools/runtime/qualify_normal.py --output "$out/normal-controls"
cp "$bootstrap_prefix/gnustep-toolchain-provenance.json" "$out/normal-provenance.json"
python3 tools/ci/build_tsan_toolchain.py --mode thread --jobs 4 --cache-dir "$RUNNER_TEMP/native-thread" > "$out/thread-builder.stdout" 2> "$out/thread-builder.stderr"
thread_env="$(tail -n 1 "$out/thread-builder.stdout")"
[[ -f "$thread_env" && "$thread_env" == "$RUNNER_TEMP/native-thread/"*"/environment.sh" ]]
thread="$(dirname "$thread_env")"
cp "$thread/manifest.json" "$out/thread-manifest.json"
# Keep the measured native normal runtime only as the build/header bootstrap.
# Instrumented test processes load the checked thread overlay explicitly.
unset ARLEN_RUNTIME_PREFIX ARLEN_GNUSTEP_CONFIG_FILE
for variable in ${!GNUSTEP_@}; do unset "$variable"; done
export PATH="$bootstrap_prefix/System/Tools:$bootstrap_prefix/Local/Tools:/usr/bin:/bin"
export GNUSTEP_SH="$bootstrap_prefix/System/Library/Makefiles/GNUstep.sh"
export GNUSTEP_CONFIG_FILE="$bootstrap_config"
export GNUSTEP_USER_ROOT="$root/.gnustep"
source tools/source_gnustep_env.sh
source "$thread_env"
export LD_LIBRARY_PATH="$bootstrap_prefix/lib:$bootstrap_prefix/Local/Library/Libraries:$bootstrap_prefix/System/Library/Libraries"
unset LD_PRELOAD XCTEST_LD_PRELOAD ARLEN_XCTEST_LD_LIBRARY_PATH ARLEN_XCTEST
unset TEST SKIP_TEST EXTRA_OBJC_FLAGS ITERATIONS UNTIL_FAILURE MAKEFLAGS MFLAGS GNUMAKEFLAGS
unset ARLEN_TSAN_UNIT_ITERATIONS ARLEN_TSAN_UNIT_UNTIL_FAILURE ARLEN_TSAN_SUPPRESSIONS_FILE
export ARLEN_USE_VENDORED_XCTEST=1 ARLEN_TEST_JUNIT=1 ARLEN_CC=clang ARLEN_REQUIRE_TSAN=1
export TSAN_OPTIONS='halt_on_error=1:history_size=7:second_deadlock_stack=1'
python3 tools/ci/test_clang_sanitizer_runtime.py > "$out/clang-runtime-controls.log" 2>&1
python3 - "$thread" "$out" "$bootstrap_prefix" "$SOURCE_REF" <<'PY'
import hashlib,json,os,subprocess,sys
from pathlib import Path
thread,out,normal,ref=sys.argv[1:];thread=Path(thread);out=Path(out);normal=Path(normal)
m=json.loads((thread/'manifest.json').read_text());p=json.loads((normal/'gnustep-toolchain-provenance.json').read_text());digest=lambda f:hashlib.sha256(Path(f).read_bytes()).hexdigest()
supported={('aarch64','ubuntu-24.04'):'a4d3736287fd93c10fd47603086260c7896f97e96af05d2371de6fe3d0975c9d',
           ('x86_64','debian-13'):'df809d9d55a613726dd7475a3f45ee55a8dbfebe3913f7a442af94f66adfbb34'}
assert p['lock']['sha256']==supported[(p['build_host']['machine'],p['build_host']['os_version'])]
assert all(digest(f)==h for f,h in m['artifacts'].items())
assert json.loads(Path('tools/ci/tsan-toolchain/sources.json').read_text())==m['sources']
assert digest('tools/ci/build_tsan_toolchain.py')==m['builder']
assert all(digest(Path('tools/ci/tsan-toolchain')/f)==h for f,h in m['patches'].items())
for c in p['components']:
 if c['name'] in m['sources']:
  assert c['resolved_commit']==m['sources'][c['name']]['commit']
  assert all(a['sha256']==m['patches'][Path(a['path']).name] for a in c['applied_patches'])
assert all(digest(normal/f)==v['sha256'] for f,v in p['elf_files'].items())
assert subprocess.check_output(['gnustep-config','--objc-flags'],text=True)==m['gnustep_flags']
assert subprocess.check_output(['clang','--version'],text=True)==m['clang']
(out/'source-and-environment.json').write_text(json.dumps({'source':ref,'tree':subprocess.check_output(['git','rev-parse','HEAD^{tree}'],text=True).strip(),'machine':subprocess.check_output(['uname','-a'],text=True),'compiler':m['clang'],'bootstrap_flags':m['gnustep_flags'],'thread_recipe':str(thread),'normal_prefix':str(normal),'cpu_affinity':sorted(os.sched_getaffinity(0))},indent=2)+'\n')
PY
python3 tools/ci/check_sanitizer_suppressions.py > "$out/suppression-classifier.log"
export TSAN_OPTIONS="$TSAN_OPTIONS:suppressions=$root/tests/fixtures/sanitizers/phase9h_tsan.supp"
tsan_so="$(clang -print-file-name=libclang_rt.tsan-aarch64.so)"
[[ -f "$tsan_so" ]]
tsan_objc_flags="-fsanitize=thread -fno-omit-frame-pointer -shared-libsan -Wl,-rpath,$(dirname "$tsan_so") -Wno-unused-command-line-argument"
tsan_cc="clang${ARLEN_TSAN_EXTRA_FLAGS:+ $ARLEN_TSAN_EXTRA_FLAGS}"
mkdir "$out/bootstrap"
bootstrap_eocc="$out/bootstrap/eocc"
make clean > "$out/http-build.log" 2>&1
make EXTRA_OBJC_FLAGS= EOC_TOOL="$bootstrap_eocc" eocc transpile module-transpile >> "$out/http-build.log" 2>&1
make EXTRA_OBJC_FLAGS="$tsan_objc_flags" EOC_TOOL="$bootstrap_eocc" ARLEN_CC="$tsan_cc" -o "$bootstrap_eocc" boomhauer runtime-concurrency-fixture arlen >> "$out/http-build.log" 2>&1
for number in 1 2; do
 export ARLEN_RUNTIME_CONCURRENCY_LOG_DIR="$out/http-$number/runtime_concurrency"
 mkdir -p "$out/http-$number"
 LD_LIBRARY_PATH="$ARLEN_TSAN_LIBRARY_PATH:$LD_LIBRARY_PATH" python3 tools/ci/runtime_concurrency_probe.py --binary ./build/runtime-concurrency-fixture --iterations 1 > "$out/http-$number/probe.log" 2>&1
 LD_LIBRARY_PATH="$ARLEN_TSAN_LIBRARY_PATH:$LD_LIBRARY_PATH" ldd build/runtime-concurrency-fixture > "$out/http-$number/linkage.txt"
done
LD_LIBRARY_PATH="$ARLEN_TSAN_LIBRARY_PATH:$LD_LIBRARY_PATH" python3 tools/ci/tsan_runtime_diagnostics.py --output "$out/diagnostics" > "$out/diagnostics-driver.log" 2>&1
python3 "$harness/verify_native_http_race.py" "$out" "$thread" "$SOURCE_REF"

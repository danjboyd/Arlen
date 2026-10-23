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
assert p['build_host']['machine']=='aarch64' and p['build_host']['os_version']=='ubuntu-24.04'
assert p['lock']['sha256']=='a4d3736287fd93c10fd47603086260c7896f97e96af05d2371de6fe3d0975c9d'
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
pg_bin="$(bash tools/ci/resolve_postgres_test_bin.sh)"
pg_root="$RUNNER_TEMP/v032-private-pg"
mkdir -m 700 "$pg_root"
cleanup() { "$pg_bin/pg_ctl" -D "$pg_root/data" -m immediate -w stop >/dev/null 2>&1 || true; }
trap cleanup EXIT
"$pg_bin/initdb" -D "$pg_root/data" --no-locale --encoding=UTF8 --auth=trust --username=arlen_v032 > "$out/pg-init.log"
mkdir "$pg_root/socket"
"$pg_bin/pg_ctl" -D "$pg_root/data" -l "$out/pg-server.log" -o "-k $pg_root/socket -c listen_addresses=''" -w start
export ARLEN_PG_TEST_DSN="host=$pg_root/socket dbname=postgres user=arlen_v032"
python3 tools/ci/check_sanitizer_suppressions.py > "$out/suppression-classifier.log"
python3 tools/ci/classify_sanitizer_integration_skips.py --check > "$out/integration-classifier.log"
for number in 1 2; do
 [[ "$(git rev-parse HEAD)" == "$SOURCE_REF" && -z "$(git status --porcelain)" ]]
 export ARLEN_PHASE10M_THREAD_ARTIFACT_DIR="$out/run-$number"
 export ARLEN_TEST_RESULTS_DIR="$out/run-$number/xctest-results"
 bash tools/ci/run_linux_thread_race_nightly.sh > "$out/run-$number-driver.log" 2>&1
 python3 - "$ARLEN_PHASE10M_THREAD_ARTIFACT_DIR" <<'PY'
import hashlib,json,os,stat,sys
from pathlib import Path
out=Path(sys.argv[1]);p=Path('var/module_state/jobs-production.plist.lock')
if p.exists() or p.is_symlink():
 assert not Path('var').is_symlink() and not p.parent.is_symlink()
 i=p.lstat();assert stat.S_ISREG(i.st_mode) and i.st_uid==os.getuid() and i.st_size==0 and i.st_nlink==1
 assert hashlib.sha256(p.read_bytes()).hexdigest()=='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
 dest=out/'test-generated-var/module_state/jobs-production.plist.lock';dest.parent.mkdir(parents=True);p.rename(dest);p.parent.rmdir();Path('var').rmdir()
s=json.loads((out/'summary.json').read_text());u=json.loads((out/'tsan/summary.json').read_text());d=json.loads((out/'diagnostics/summary.json').read_text())
assert s['status']=='pass' and s['engine']=='tsan' and s['exit_code']==0
assert u['status']=='pass' and u['runtime_probe_completed'] and u['unit_methods_started']==1372 and u['unit_assertion_failures']==0 and u['sanitizer_warnings']==0 and u['tsan_excluded_tests']==[]
assert d['status']=='pass' and len(d['runs'])==30 and all(x['valid'] for x in d['runs'])
c=[x for x in d['runs'] if x['mode']=='canary'];assert len(c)==2 and all(x['exit_code']==66 and x['canary_detected'] for x in c)
import re
logs=list((out/'tsan/runtime_concurrency').glob('*.log'));assert len(logs)==4
raw=(out/'tsan/tsan.log').read_text(errors='replace');assert raw.count('runtime concurrency server exit=0; log retained:')==4 and 'runtime-concurrency-probe: ok' in raw
pattern=r'(?:WARNING|ERROR|FATAL|SUMMARY):\s*(?:Thread|Address|Leak|Memory|UndefinedBehavior)Sanitizer|(?:^|\s)runtime error:'
assert not any(re.search(pattern,p.read_text(errors='replace')) for p in logs)
(out/'server-receipt.json').write_text(json.dumps({'actual_exit_codes':[0,0,0,0],'distinct_full_logs':4,'logs_sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in logs}},indent=2)+'\n')
PY
 [[ -z "$(git status --porcelain)" ]]
 python3 "$harness/verify_complete_unit_run_1372.py" --contract "$harness/candidate-unit-contract.json" --inventory "$root/tests/fixtures/test_inventory/ArlenUnitTests.tests.txt" --junit "$ARLEN_TEST_RESULTS_DIR/ArlenUnitTests.xml" --log "$ARLEN_PHASE10M_THREAD_ARTIFACT_DIR/tsan/tsan.log" --lane-summary "$ARLEN_PHASE10M_THREAD_ARTIFACT_DIR/tsan/summary.json" --output "$out/run-$number-complete-unit-receipt.json"
 for kind in http unit; do
  binary=build/runtime-concurrency-fixture
  [[ "$kind" == http ]] || binary=build/tests/ArlenUnitTests.xctest/ArlenUnitTests
  LD_LIBRARY_PATH="$ARLEN_TSAN_LIBRARY_PATH:$LD_LIBRARY_PATH" ldd "$binary" > "$out/run-$number-$kind-linkage.txt"
 done
 python3 - "$thread" "$out" "$number" <<'PY'
import hashlib,json,sys
from pathlib import Path
thread,out,n=sys.argv[1:];out=Path(out);m=json.loads((Path(thread)/'manifest.json').read_text());allowed={Path(p).resolve():h for p,h in m['artifacts'].items()};records={}
for kind in ('http','unit'):
 text=(out/f'run-{n}-{kind}-linkage.txt').read_text();record={}
 for name in ('libgnustep-base.so','libobjc.so','libdispatch.so','libBlocksRuntime.so'):
  paths=[Path(x.split('=>',1)[1].split()[0]).resolve() for x in text.splitlines() if x.strip().startswith(name) and '=>' in x]
  assert paths and all(p in allowed and hashlib.sha256(p.read_bytes()).hexdigest()==allowed[p] for p in paths),(kind,name,paths)
  record[name]=[str(p) for p in paths]
 records[kind]=record
(out/f'run-{n}-four-dso-receipt.json').write_text(json.dumps(records,indent=2)+'\n')
PY
done
printf '%s\n' 'Two consecutive native arm64 strict full-unit/HTTP/diagnostic/canary runs passed; exact evidence still requires review.' > "$out/pair-completed.txt"

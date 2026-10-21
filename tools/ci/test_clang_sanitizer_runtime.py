#!/usr/bin/env python3
"""Exercise the actual clang runtime across dlopen/exec, including fault controls."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RuntimeTests(unittest.TestCase):
    def test_tsan_dlopen_and_exec_use_clang_runtime(self):
        compiler = os.environ.get('ARLEN_CC', 'clang')
        arch = subprocess.check_output([compiler, '-dumpmachine'], text=True).strip().split('-')[0]
        runtime = Path(subprocess.check_output(
            [compiler, f'-print-file-name=libclang_rt.tsan-{arch}.so'], text=True).strip())
        if not runtime.is_file():
            runtime = Path(subprocess.check_output(
                [compiler, '-print-runtime-dir'], text=True).strip()) / 'libclang_rt.tsan.so'
        self.assertTrue(runtime.is_file(), f'clang shared TSan runtime missing: {runtime}')
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            flags = ['-fsanitize=thread', '-shared-libsan', '-g', '-O1',
                     '-fno-omit-frame-pointer', '-pthread', f'-Wl,-rpath,{runtime.parent}']
            fault = '''#include <pthread.h>
#include <stdlib.h>
volatile int ArlenTSanRuntimeCanary;
static pthread_barrier_t barrier;
static void *worker(void *unused) {
 pthread_barrier_wait(&barrier);
 for (int i=0;i<10000;i++) ArlenTSanRuntimeCanary++;
 return 0;
}
int check(int mode) {
 if (!mode) return 0;
 pthread_t t;
 pthread_barrier_init(&barrier,0,2);
 pthread_create(&t,0,worker,0); worker(0); pthread_join(t,0);
 pthread_barrier_destroy(&barrier); return 0;
}
'''
            for name, code, extra in [
                ('bundle.so', fault, ['-shared', '-fPIC']),
                ('child', fault + '\nint main(int c,char **v){return check(atoi(v[1]));}', []),
                ('parent', '''#include <dlfcn.h>
#include <stdlib.h>
#include <unistd.h>
int main(int c,char **v) {
 void *lib=dlopen(v[1],RTLD_NOW); if(!lib) return 90;
 int (*check)(int)=dlsym(lib,"check"); if(!check) return 91;
 check(atoi(v[3])); execl(v[2],v[2],v[4],(char *)0); return 92;
}''', ['-ldl'])]:
                source = root / (name + '.c')
                source.write_text(code)
                subprocess.run([compiler, str(source), '-o', str(root / name),
                                *(flags if name != 'parent' else []), *extra], check=True)
            env = dict(os.environ, LD_PRELOAD=str(runtime),
                       TSAN_OPTIONS='halt_on_error=1:exitcode=66')
            for parent_mode, child_mode in [(0, 0), (1, 0), (0, 1)]:
                result = subprocess.run([str(root / 'parent'), str(root / 'bundle.so'),
                                         str(root / 'child'), str(parent_mode), str(child_mode)],
                                        env=env, capture_output=True, text=True, timeout=30)
                if parent_mode or child_mode:
                    self.assertEqual(result.returncode, 66, result.stderr)
                    self.assertIn('ThreadSanitizer: data race', result.stderr)
                    self.assertIn('ArlenTSanRuntimeCanary', result.stderr)
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_runtime_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            compiler = Path(tmp) / 'clang'
            compiler.write_text('#!/bin/sh\necho /nonexistent/arlen-sanitizer-runtime\n')
            compiler.chmod(0o755)
            env = dict(os.environ, ARLEN_CC='clang', PATH=tmp + os.pathsep + os.environ['PATH'])
            result = subprocess.run(['bash', '-c', 'source tools/ci/source_clang_sanitizers.sh'],
                                    cwd=ROOT, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('shared ASan runtime is missing', result.stderr)

    def test_parent_child_instrumentation_and_preloads(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            def compile_source(name, code, flags):
                source = root / (name + '.c')
                source.write_text(code)
                target = root / name
                subprocess.run([os.environ.get('ARLEN_CC', 'clang'), str(source), '-o', str(target), *flags], check=True)
                return target
            marker = compile_source('marker.so', 'int marker(void) { return 1; }', ['-shared', '-fPIC'])
            ambient = os.environ.copy()
            other = compile_source('other.so', 'int other(void) { return 2; }', ['-shared', '-fPIC'])
            ambient['XCTEST_LD_PRELOAD'] = str(other)
            ambient['LD_PRELOAD'] = str(marker)
            configured = subprocess.check_output(
                ['bash', '-c', 'source tools/ci/source_clang_sanitizers.sh && python3 -c '
                 + shlex.quote('import os,json; print(json.dumps(dict(os.environ)))')],
                cwd=ROOT, env=ambient, text=True)
            env = json.loads(configured)
            self.assertIn(str(marker), env['XCTEST_LD_PRELOAD'].split(':'))
            self.assertIn(str(other), env['XCTEST_LD_PRELOAD'].split(':'))
            flags = shlex.split(env['EXTRA_OBJC_FLAGS'])
            fault = '''#include <stdlib.h>
#include <limits.h>
int check(int mode) {
 if (mode == 1) { volatile char *p = malloc(1); p[4] = 1; free((void *)p); }
 if (mode == 2) { volatile int n = INT_MAX; return n + 1; }
 return 0;
}
'''
            bundle = compile_source('bundle.so', fault, flags + ['-shared', '-fPIC'])
            child = compile_source('child', fault + '\nint main(int c,char **v){return check(atoi(v[1]));}', flags)
            parent = compile_source('parent', '''#include <dlfcn.h>
#include <stdlib.h>
#include <unistd.h>
int main(int c,char **v) {
 if(!dlsym(RTLD_DEFAULT,"marker") || !dlsym(RTLD_DEFAULT,"other")) return 93;
 void *lib=dlopen(v[1], RTLD_NOW); if(!lib) return 90;
 int (*check)(int)=dlsym(lib,"check"); if(!check) return 91;
 check(atoi(v[3])); execl(v[2], v[2], v[4], (char *)0); return 92;
}''', ['-ldl'])
            env['LD_PRELOAD'] = env['XCTEST_LD_PRELOAD']
            env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1'
            env['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'
            for parent_mode, child_mode, diagnostic in [
                (0, 0, None), (1, 0, 'AddressSanitizer'), (0, 1, 'AddressSanitizer'),
                (2, 0, 'signed integer overflow'), (0, 2, 'signed integer overflow')]:
                with self.subTest(parent=parent_mode, child=child_mode):
                    result = subprocess.run([str(parent), str(bundle), str(child),
                                             str(parent_mode), str(child_mode)],
                                            env=env, capture_output=True, text=True)
                    if diagnostic:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn(diagnostic, result.stderr)
                    else:
                        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()

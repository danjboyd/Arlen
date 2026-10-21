#!/usr/bin/env python3
"""Build pinned GNUstep dependencies locally; never install into the host toolchain."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
INPUTS = ROOT / 'tools/ci/tsan-toolchain'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache-dir', type=Path, default=ROOT / '.cache/tsan-toolchain')
    parser.add_argument('--mode', choices=('normal', 'thread'), default='thread')
    parser.add_argument('--jobs', type=int, default=4)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    sources = json.loads((INPUTS / 'sources.json').read_text())
    identity = {'mode': args.mode, 'sources': sources,
                'patches': {p.name: digest(p) for p in sorted(INPUTS.glob('*.patch'))},
                'builder': digest(Path(__file__)),
                'clang': subprocess.check_output(['clang', '--version'], text=True),
                'gnustep_flags': subprocess.check_output(['gnustep-config', '--objc-flags'], text=True)}
    key = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()[:20]
    work = args.cache_dir.resolve() / (args.mode + '-' + key)
    work.mkdir(parents=True, exist_ok=True)
    manifest_path = work / 'manifest.json'
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        if all(Path(p).is_file() and digest(Path(p)) == h for p, h in manifest['artifacts'].items()):
            print(work / 'environment.sh')
            return
        raise RuntimeError('cached artifacts changed; preserve this directory and choose a new --cache-dir')
    (work / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
    build_env = os.environ.copy()
    build_env.pop('LD_PRELOAD', None)
    build_env.pop('XCTEST_LD_PRELOAD', None)
    # Build tools use the sourced host bootstrap, never partially built TSAN DSOs.
    with (work / 'build.log').open('a') as log:
        def run(command, cwd=work, env=None):
            log.write('\n$ ' + shlex.join(map(str, command)) + '\n')
            log.flush()
            subprocess.run(list(map(str, command)), cwd=cwd, env=env or build_env,
                           stdout=log, stderr=subprocess.STDOUT, check=True)

        for name in ('libobjc2', 'libdispatch', 'libs-base'):
            spec = sources[name]
            source = work / name
            if not source.exists():
                run(['git', 'init', source])
                run(['git', 'fetch', '--depth=1', spec['url'], spec['commit']], source)
                run(['git', 'checkout', '--detach', 'FETCH_HEAD'], source)
            actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip()
            if actual != spec['commit']:
                raise RuntimeError(f'{name}: unexpected source identity {actual}')
            patch = INPUTS / spec['patch']
            applied = source / '.arlen-patch-sha256'
            if not applied.exists():
                run(['git', 'apply', '--check', patch], source)
                run(['git', 'apply', patch], source)
                applied.write_text(digest(patch))
            elif applied.read_text() != digest(patch):
                raise RuntimeError(f'{name}: patch identity mismatch')

        tsan = args.mode == 'thread'
        flags = '-fsanitize=thread -fno-omit-frame-pointer' if tsan else '-fno-omit-frame-pointer'
        objc = work / 'libobjc2'
        run(['cmake', '-S', objc, '-B', objc / 'build', '-DCMAKE_BUILD_TYPE=RelWithDebInfo',
             '-DCMAKE_C_COMPILER=clang', '-DCMAKE_CXX_COMPILER=clang++', '-DTESTS=OFF',
             *[f'-DCMAKE_{language}_FLAGS={flags}' for language in ('C', 'CXX', 'OBJC', 'OBJCXX')]])
        run(['cmake', '--build', objc / 'build', '-j', args.jobs])
        dispatch = work / 'libdispatch'
        run(['cmake', '-S', dispatch, '-B', dispatch / 'build', '-DCMAKE_BUILD_TYPE=RelWithDebInfo',
             '-DCMAKE_C_COMPILER=clang', '-DCMAKE_CXX_COMPILER=clang++', '-DBUILD_TESTING=OFF',
             '-DDISPATCH_USE_SANITIZER=' + ('Thread' if tsan else '')])
        run(['cmake', '--build', dispatch / 'build', '-j', args.jobs])

        archive = work / 'icu.tgz'
        if not archive.exists():
            temporary = work / 'icu.tgz.download'
            urllib.request.urlretrieve(sources['icu']['url'], temporary)
            temporary.rename(archive)
        if digest(archive) != sources['icu']['sha256']:
            raise RuntimeError('ICU archive checksum mismatch')
        if not (work / 'icu/source/configure').exists():
            with tarfile.open(archive) as tar:
                tar.extractall(work, filter='data')
        icu_build = work / 'icu-build'
        icu_build.mkdir(exist_ok=True)
        icu_env = dict(build_env, CC='clang', CXX='clang++',
                       CFLAGS='-g -O1 ' + flags, CXXFLAGS='-g -O1 ' + flags)
        if tsan:
            arch = subprocess.check_output(['clang', '-dumpmachine'], text=True).strip().split('-')[0]
            runtime_library = Path(subprocess.check_output(
                ['clang', '-print-file-name=libclang_rt.tsan-' + arch + '.so'], text=True).strip())
            if not runtime_library.is_file():
                raise RuntimeError('clang shared TSan runtime is unavailable')
            runtime = str(runtime_library.parent)
            icu_env['LDFLAGS'] = '-fsanitize=thread -shared-libsan -Wl,-rpath,' + runtime
        run([work / 'icu/source/configure', '--disable-tests', '--disable-samples', '--disable-extras',
             '--prefix=' + str(work / 'icu-install')], icu_build, icu_env)
        run(['make', '-j', args.jobs], icu_build, icu_env)

        base = work / 'libs-base'
        icu_headers = ' '.join('-I' + shlex.quote(str(work / 'icu/source' / part))
                               for part in ('common', 'i18n'))
        icu_libraries = '-L' + shlex.quote(str(icu_build / 'lib')) + ' -Wl,-rpath,' + str(icu_build / 'lib')
        base_env = dict(build_env, ICU_I18N_CFLAGS=icu_headers, ICU_UC_CFLAGS=icu_headers,
                        ICU_I18N_LIBS=icu_libraries + ' -licui18n -licuuc -licudata',
                        ICU_UC_LIBS=icu_libraries + ' -licuuc -licudata',
                        CPPFLAGS=icu_headers + ' ' + build_env.get('CPPFLAGS', ''))
        run(['./configure', '--enable-newkvo', '--with-dispatch-include=' + str(dispatch),
             'CC=clang', 'CFLAGS=-g -O1 -fno-omit-frame-pointer'], base, base_env)
        overlay_flags = flags + ' -I' + shlex.quote(str(dispatch)) + ' ' + icu_headers
        run(['make', '-C', 'Source', '-j', args.jobs, 'debug=yes', 'messages=yes',
             'ADDITIONAL_OBJCFLAGS=' + overlay_flags, 'ADDITIONAL_CFLAGS=' + overlay_flags], base, base_env)

    library_dirs = [icu_build / 'lib', dispatch / 'build', objc / 'build', base / 'Source/obj']
    artifacts = {}
    for directory in library_dirs:
        for path in directory.glob('*.so*'):
            if path.is_file():
                artifacts[str(path)] = digest(path)
    if not artifacts:
        raise RuntimeError('no shared libraries produced')
    for path in sorted((dispatch / 'dispatch').glob('*.h')):
        artifacts[str(path)] = digest(path)
    manifest = dict(identity, artifacts=artifacts, library_dirs=list(map(str, library_dirs)),
                    dispatch_headers=str(dispatch / 'dispatch'),
                    install_policy='No host installation. Coordinator owns packaging and production propagation.')
    environment = work / 'environment.sh'
    environment.write_text('export ARLEN_TSAN_LIBRARY_PATH=' + shlex.quote(':'.join(map(str, library_dirs))) + '\n'
                           'export ARLEN_TSAN_EXTRA_FLAGS=' + shlex.quote('-I' + shlex.quote(str(dispatch))) + '\n')
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    print(environment)


if __name__ == '__main__':
    main()

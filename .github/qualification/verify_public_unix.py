#!/usr/bin/env python3
"""Verify actual public latest on an owned Unix test host; no version override."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import signal
import socket
import subprocess
import tarfile
import time
import urllib.error
import urllib.request


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--expected-version', required=True)
    parser.add_argument('--expected-source', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(mode=0o700, parents=True, exist_ok=False)
    downloads = out / 'downloads'
    downloads.mkdir()
    home = out / 'home'
    home.mkdir()
    apps = out / 'apps'
    apps.mkdir()
    prefix, bins = out / 'arlen', out / 'bin'
    steps, server = [], None
    report = {'status': 'running', 'expected_version': args.expected_version,
              'expected_source': args.expected_source, 'platform': platform.platform(),
              'machine': platform.machine(), 'selection': 'actual public latest; installer has no --archive or --version',
              'steps': steps}
    child = {key: value for key, value in os.environ.items()
             if not key.startswith('GNUSTEP_') and key not in {
                 'ARLEN_RUNTIME_PREFIX', 'ARLEN_RUNTIME_ROOT', 'ARLEN_GNUSTEP_CONFIG_FILE',
                 'LD_PRELOAD', 'LD_LIBRARY_PATH', 'XCTEST_LD_PRELOAD',
                 'ARLEN_TSAN_LIBRARY_PATH', 'ARLEN_TSAN_EXTRA_FLAGS', 'TSAN_OPTIONS'}}
    # Isolate only child processes; the caller's home and shell files stay intact.
    child.update(HOME=str(home), SHELL='/bin/zsh' if platform.system() == 'Darwin' else '/bin/bash')
    if platform.system() == 'Darwin':
        child['ZDOTDIR'] = str(home)
    original_path = child['PATH']

    def run(name, command, cwd=None, env=None):
        path = out / (name + '.log')
        with path.open('wb') as log:
            result = subprocess.run(command, cwd=cwd, env=env or child, stdout=log, stderr=subprocess.STDOUT)
        steps.append({'name': name, 'exit_code': result.returncode})
        if result.returncode:
            raise RuntimeError(name + ' failed; see ' + str(path))
        return path

    def fetch(name, url):
        dest = downloads / name
        run('download-' + name, ['curl', '-fsSL', '--retry', '2', '-o', str(dest), url])
        return dest

    base = 'https://github.com/danjboyd/Arlen/releases/latest/download/'
    try:
        installer = fetch('install.sh', base + 'install.sh')
        sums = fetch('SHA256SUMS', base + 'SHA256SUMS')
        expected = {line.split()[1].lstrip('*'): line.split()[0] for line in sums.read_text().splitlines() if len(line.split()) == 2}
        assert hashlib.sha256(installer.read_bytes()).hexdigest() == expected['install.sh']
        report['installer_sha256'] = expected['install.sh']
        run('install', ['bash', str(installer), '--yes', '--prefix', str(prefix), '--bin-dir', str(bins)])
        current = prefix / 'current'
        dist = dict(line.split('=', 1) for line in (current / '.arlen-dist').read_text().splitlines() if '=' in line)
        assert dist['version'] == args.expected_version and dist['commit'] == args.expected_source, dist
        report['installed_dist'] = dist
        child['PATH'] = str(bins) + os.pathsep + original_path
        if platform.system() == 'Linux':
            run('native-normal-controls', ['bash', '-c',
                'cd "$1"; source tools/source_gnustep_env.sh; python3 tools/runtime/qualify_normal.py --output "$2"',
                'public-runtime-controls', str(current), str(out / 'native-normal-controls')])
            runtime = Path((current / '.arlen-runtime').read_text().strip())
            provenance = (runtime / 'gnustep-toolchain-provenance.json').read_bytes()
            (out / 'normal-provenance.json').write_bytes(provenance)
            report['normal_provenance_sha256'] = hashlib.sha256(provenance).hexdigest()
            report['native_normal_controls'] = '14 concurrency modes plus ICU contract, exact prefix linkage, O2/debug flags'
        run('doctor', ['arlen', 'doctor'], cwd='/')
        shell_env = dict(child, PATH=original_path)
        shell = '/bin/zsh' if platform.system() == 'Darwin' else '/bin/bash'
        for name, mode in (('login', '-lc'), ('interactive', '-ic')):
            path = run('fresh-' + name, [shell, mode, 'cd /; command -v arlen; arlen doctor'], cwd='/', env=shell_env)
            assert str(bins / 'arlen') in path.read_text().splitlines(), 'fresh shell selected another launcher'
        run('new', ['arlen', 'new', 'Published032App'], cwd=apps)
        app = apps / 'Published032App'
        run('app-build', ['arlen', 'build'], cwd=app)
        run('app-request-tests', ['arlen', 'test', '--app'], cwd=app)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        with (out / 'http.log').open('wb') as log:
            server = subprocess.Popen(['arlen', 'boomhauer', '--port', str(port)], cwd=app, env=child,
                                      stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        deadline = time.monotonic() + 180
        while True:
            try:
                with opener.open('http://127.0.0.1:%s/healthz' % port, timeout=2) as response:
                    assert response.status == 200
                break
            except (OSError, urllib.error.URLError):
                if server.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError('installed server did not become healthy')
                time.sleep(0.5)
        with opener.open('http://127.0.0.1:%s/' % port, timeout=5) as response:
            assert b'Welcome to Arlen' in response.read()
        steps.append({'name': 'public-installed-http', 'status': 'pass'})
        if platform.system() == 'Darwin':
            assert (current / 'build/apple/.release-prebuilt').is_file()
            assert not (current / 'build/apple/obj').exists(), 'prebuilt framework rebuilt'
            asset = 'arlen-%s-macos-arm64.tar.gz' % args.expected_version
            archive = fetch(asset, base + asset)
            assert hashlib.sha256(archive.read_bytes()).hexdigest() == expected[asset]
            checked = 0
            with tarfile.open(archive) as tar:
                for member in tar.getmembers():
                    if not member.isfile():
                        continue
                    parts = PurePosixPath(member.name).parts
                    assert parts[0] == 'arlen-' + args.expected_version and '..' not in parts
                    target = current.joinpath(*parts[1:])
                    assert target.is_file() and target.read_bytes() == tar.extractfile(member).read(), member.name
                    checked += 1
            report.update(public_archive_sha256=expected[asset], installed_regular_members_byte_equal=checked,
                          prebuilt_framework_reused=True)
        report['status'] = 'pass'
    except BaseException as error:
        report.update(status='fail', error_type=type(error).__name__, error=str(error))
        raise
    finally:
        if server is not None:
            try:
                os.killpg(server.pid, signal.SIGTERM)
                server.wait(timeout=10)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(server.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                server.wait(timeout=10)
            report['server_returncode_after_owned_cleanup'] = server.returncode
        (out / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'status': report['status'], 'summary': str(out / 'summary.json')}))


if __name__ == '__main__':
    main()

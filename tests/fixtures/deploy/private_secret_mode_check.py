#!/usr/bin/env python3
"""Check actual deploy-init write permissions and fail-closed error handling."""
import json
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import sys
import tempfile


def main():
    binary = str(Path(sys.argv[1]).resolve())
    source = Path(__file__).with_name('private_secret_mode_probe.c')
    with tempfile.TemporaryDirectory(prefix='arlen-deploy-secret-mode-') as directory:
        workspace = Path(directory)
        probe = workspace / 'mode-probe.so'
        subprocess.run(['clang', '-shared', '-fPIC', str(source), '-o', str(probe)],
                       check=True, capture_output=True)
        for deny in (False, True):
            root = workspace / ('denied' if deny else 'allowed')
            app = root / 'app'
            config = app / 'config'
            config.mkdir(parents=True)
            (config / 'app.plist').write_bytes(plistlib.dumps({'host': '127.0.0.1', 'port': 3000}))
            (config / 'deploy.plist').write_bytes(plistlib.dumps({'deployment': {'targets': {
                'production': {'host': 'fixture.example.test', 'releasePath': str(root / 'release'),
                               'profile': 'linux-x86_64-gnustep-clang', 'runtimeStrategy': 'system',
                               'environment': 'production', 'service': 'arlen@fixture',
                               'baseURL': 'http://127.0.0.1:3000'},
            }}}))
            audit = root / 'mode-events.log'
            environment = dict(os.environ, ARLEN_PRIVATE_MODE_PROBE_ROOT=str(root),
                               ARLEN_PRIVATE_MODE_PROBE_LOG=str(audit))
            runtime = environment.get('XCTEST_LD_PRELOAD') or environment.get('LD_PRELOAD', '')
            environment['LD_PRELOAD'] = (runtime + ':' if runtime else '') + str(probe)
            if deny:
                environment['ARLEN_PRIVATE_MODE_PROBE_DENY'] = '1'
            else:
                environment.pop('ARLEN_PRIVATE_MODE_PROBE_DENY', None)
            result = subprocess.run([binary, 'deploy', 'init', 'production', '--app-root', str(app),
                                     '--json'], env=environment, capture_output=True, text=True,
                                    preexec_fn=lambda: os.umask(0o022))
            events = audit.read_text().splitlines() if audit.exists() else []
            if any(event.startswith('unsafe-') for event in events):
                raise AssertionError('generated secret payload was exposed before permissions were restricted')
            destination = app / 'build/deploy/targets/production/env/production.env.example'
            if deny:
                if 'permission-denied' not in events:
                    raise AssertionError('permission fault was not exercised')
                if result.returncode == 0 or destination.exists() or 'private-write' in events:
                    raise AssertionError('permission failure did not stop the secret write')
                if list(destination.parent.glob('.arlen-write-*')):
                    raise AssertionError('permission failure left a temporary secret file')
            else:
                if result.returncode != 0 or 'private-write' not in events:
                    raise AssertionError('private secret write did not complete')
                if stat.S_IMODE(destination.stat().st_mode) != 0o600:
                    raise AssertionError('generated secret file is not owner-only')
                if stat.S_IMODE(destination.parent.stat().st_mode) != 0o700:
                    raise AssertionError('generated secret directory is not owner-only')
                if json.loads(result.stdout).get('status') != 'ok':
                    raise AssertionError('deploy init did not report success')
        print('secret payload stayed private; permission failure wrote no payload')


if __name__ == '__main__':
    main()

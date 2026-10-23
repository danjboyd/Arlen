#!/usr/bin/env python3
"""Exercise deploy doctor's actual readiness path without logging DSN contents."""
import json
import os
from pathlib import Path
import plistlib
import shlex
import subprocess
import sys
import tempfile


def main():
    dsn = os.environ['ARLEN_PG_TEST_DSN']
    marker = 'arlen-private-readiness-fixture'
    if dsn.startswith(('postgresql://', 'postgres://')):
        dsn += ('&' if '?' in dsn else '?') + 'password=' + marker
    else:
        dsn += " password='" + marker + "'"
    binary = str(Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix='arlen-private-readiness-') as directory:
        root = Path(directory)
        release = root / 'releases' / 'fixture'
        config = release / 'app' / 'config'
        config.mkdir(parents=True)
        (config / 'app.plist').write_bytes(plistlib.dumps({
            'database': {'adapter': 'postgresql', 'connectionString': dsn},
        }))
        metadata = release / 'metadata'
        metadata.mkdir()
        (metadata / 'manifest.json').write_text(json.dumps({
            'database': {'mode': 'host_local', 'adapter': 'postgresql', 'target': 'default'},
        }))
        (root / 'releases' / 'current').symlink_to('fixture')
        stub = root / 'bin'
        stub.mkdir()
        called = root / 'external-probe-called'
        probe = stub / 'pg_isready'
        probe.write_text('#!/usr/bin/env bash\n'
                         'printf called > ' + shlex.quote(str(called)) + '\n'
                         'exit 99\n')
        probe.chmod(0o700)
        startup = root / 'shell-env.sh'
        startup.write_text('export PATH=' + shlex.quote(str(stub)) + ':"$PATH"\n')
        environment = dict(os.environ, BASH_ENV=str(startup))
        # Exercise the DSN from config, independently of any caller's live DSN.
        environment.pop('ARLEN_DATABASE_URL', None)
        def check_probe(connection_string, expected):
            (config / 'app.plist').write_bytes(plistlib.dumps({
                'database': {'adapter': 'postgresql', 'connectionString': connection_string},
            }))
            result = subprocess.run([binary, 'deploy', 'doctor', '--app-root', str(release / 'app'),
                                     '--releases-dir', str(root / 'releases'), '--env', 'development',
                                     '--json'], env=environment, capture_output=True, text=True)
            if called.exists():
                raise AssertionError('configured readiness probe launched pg_isready')
            payload = json.loads(result.stdout)
            checks = {item['id']: item for item in payload.get('checks', [])}
            check = checks.get('database_host_local', {})
            if check.get('status') != expected:
                raise AssertionError('configured readiness probe returned the wrong status')
            if marker in result.stdout or marker in result.stderr:
                raise AssertionError('readiness output exposed the fixture credential')

        check_probe(dsn, 'pass')
        check_probe('invalid_option=' + marker, 'fail')
        print('host-local readiness passed without external credential arguments')


if __name__ == '__main__':
    main()

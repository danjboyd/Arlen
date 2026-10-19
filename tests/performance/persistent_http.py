#!/usr/bin/env python3
"""Exercise real persistent HTTP connections and server CPU, without curl spawning."""
import argparse
import concurrent.futures
import http.client
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time


def cpu_seconds(pid):
    path = Path(f'/proc/{pid}/stat')
    if not path.exists():
        return None
    fields = path.read_text().rsplit(')', 1)[1].split()
    return (int(fields[11]) + int(fields[12])) / os.sysconf('SC_CLK_TCK')


def exercise(port, path, expected, requests):
    conn = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
    timings = []
    try:
        conn.connect()
        original = conn.sock
        for _ in range(requests):
            start = time.perf_counter()
            conn.request('GET', path)
            response = conn.getresponse()
            body = response.read()
            if response.status != 200 or body != expected:
                raise RuntimeError(f'{path}: status/body mismatch ({response.status}, {len(body)} bytes)')
            if conn.sock is not original:
                raise RuntimeError(f'{path}: server closed or replaced a persistent connection')
            timings.append(time.perf_counter() - start)
    finally:
        conn.close()
    return timings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', default='./build/boomhauer')
    parser.add_argument('--policy', default='tests/performance/policies/persistent_http.json')
    parser.add_argument('--output', default='build/perf/persistent_http.json')
    args = parser.parse_args()
    policy = json.loads(Path(args.policy).read_text())
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0))
        port = reservation.getsockname()[1]
    root = Path('public')
    root.mkdir(exist_ok=True)
    asset = tempfile.NamedTemporaryFile(prefix='persistent-perf-', suffix='.txt', dir=root, delete=False)
    payload = b'Arlen persistent static response\n' * 1024
    asset.write(payload)
    asset.close()
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    log = output.with_suffix('.log').open('wb')
    env = dict(os.environ, ARLEN_LOG_LEVEL='warn', ARLEN_PERFORMANCE_LOGGING='0')
    server = None
    results = []
    try:
        server = subprocess.Popen([args.server, '--port', str(port)], env=env, stdout=log, stderr=log)
        for attempt in range(100):
            if server.poll() is not None:
                raise RuntimeError('server exited before readiness')
            try:
                exercise(port, '/healthz', b'ok\n', 1)
                break
            except (OSError, http.client.HTTPException):
                time.sleep(.05)
        else:
            raise RuntimeError('server did not become ready')
        for name, path, body in [('healthz', '/healthz', b'ok\n'),
                                 ('static', '/static/' + Path(asset.name).name, payload)]:
            # Warm caches, then measure only requests on retained sockets.
            exercise(port, path, body, 10)
            cpu_start = cpu_seconds(server.pid)
            start = time.perf_counter()
            with concurrent.futures.ThreadPoolExecutor(max_workers=policy['connections']) as pool:
                futures = [pool.submit(exercise, port, path, body, policy['requests_per_connection'])
                           for _ in range(policy['connections'])]
                samples = [sample for future in futures for sample in future.result()]
            elapsed = time.perf_counter() - start
            cpu_end = cpu_seconds(server.pid)
            samples.sort()
            entry = dict(scenario=name, requests=len(samples), requests_per_second=len(samples)/elapsed,
                         p95_ms=samples[int(.95*(len(samples)-1))]*1000,
                         server_cpu_us_per_request=None if cpu_start is None else (cpu_end-cpu_start)*1e6/len(samples))
            entry['passed'] = (entry['requests_per_second'] >= policy['min_requests_per_second'] and
                               entry['p95_ms'] <= policy['max_p95_ms'] and
                               (entry['server_cpu_us_per_request'] is None or
                                entry['server_cpu_us_per_request'] <= policy['max_server_cpu_us_per_request']))
            results.append(entry)
        output.write_text(json.dumps(dict(policy=policy, scenarios=results), indent=2)+'\n')
        print(json.dumps(results, indent=2))
        if not all(result['passed'] for result in results):
            raise SystemExit('persistent HTTP performance gate failed')
    finally:
        if server is not None:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
        log.close()
        Path(asset.name).unlink(missing_ok=True)


if __name__ == '__main__':
    main()

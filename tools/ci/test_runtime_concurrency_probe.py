#!/usr/bin/env python3
"""Negative controls for channel and server-process qualification."""
import socket
import contextlib
import io
import os
import subprocess
import tempfile
from pathlib import Path
from unittest import mock
import runtime_concurrency_probe as probe
import unittest
from runtime_concurrency_probe import assert_channel_receive_only


class ReceiveOnlyChannelTests(unittest.TestCase):
    def setUp(self):
        self.client, self.server = socket.socketpair()
        self.client.settimeout(5)
        self.addCleanup(self.client.close)
        self.addCleanup(self.server.close)

    def test_silent_connection_remains_open_and_restores_timeout(self):
        assert_channel_receive_only(self.client)
        self.assertEqual(5, self.client.gettimeout())
        self.server.sendall(b'x')
        self.assertEqual(b'x', self.client.recv(1))

    def test_rebroadcast_is_rejected(self):
        self.server.sendall(b'\x81\x01x')
        with self.assertRaisesRegex(RuntimeError, 'rebroadcast'):
            assert_channel_receive_only(self.client)
        self.assertEqual(5, self.client.gettimeout())

    def test_closed_connection_is_rejected(self):
        self.server.close()
        with self.assertRaisesRegex(RuntimeError, 'closed unexpectedly'):
            assert_channel_receive_only(self.client)


class ServerShutdownTests(unittest.TestCase):
    def run_probe(self, exits, reports=(), request_error=None, timeout=False):
        self.logs = []
        self.processes = []
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        owner = self

        class FakeProcess:
            @classmethod
            def __class_getitem__(cls, item):
                return cls

            def __init__(self, *args, **kwargs):
                self.index = len(owner.processes)
                self.returncode = None
                self.path = owner.logs[-1]
                owner.processes.append(self)

            def poll(self):
                return self.returncode

            def terminate(self):
                with self.path.open("a") as log:
                    log.write(reports[self.index] if self.index < len(reports) else "clean shutdown\n")

            def wait(self, timeout=None):
                if owner.timeout and self.returncode is None:
                    raise subprocess.TimeoutExpired("fake-server", timeout)
                self.returncode = exits[min(self.index, len(exits) - 1)] if self.returncode is None else self.returncode
                return self.returncode

            def kill(self):
                self.returncode = -9

        self.timeout = timeout
        original_mkstemp = tempfile.mkstemp

        def create_log(*args, **kwargs):
            fd, path = original_mkstemp(*args, **kwargs)
            self.logs.append(Path(path))
            return fd, path

        with contextlib.ExitStack() as stack:
            stack.enter_context(mock.patch.object(probe.tempfile, "mkstemp", side_effect=create_log))
            stack.enter_context(mock.patch.dict(os.environ, {"ARLEN_RUNTIME_CONCURRENCY_LOG_DIR": self.directory.name}))
            stack.enter_context(mock.patch.object(probe.subprocess, "Popen", FakeProcess))
            stack.enter_context(mock.patch.object(probe, "reserve_port", return_value=12345))
            for name in ("wait_ready", "run_data_layer_probe", "run_mixed_probe_once"):
                stack.enter_context(mock.patch.object(probe, name))
            stack.enter_context(mock.patch.object(probe, "run_route_surface_probe", side_effect=request_error))
            stack.enter_context(mock.patch.object(probe.threading, "Thread"))
            stack.enter_context(mock.patch.object(probe.time, "sleep"))
            probe.run_mode("fake-server", "concurrent", True, 1)

    def test_shutdown_sanitizer_exit_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "status 66"):
            self.run_probe([66], ["WARNING: ThreadSanitizer: data race\n"])
        self.assertIn("ThreadSanitizer", self.logs[0].read_text())

    def test_zero_exit_with_early_report_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "sanitizer report"):
            self.run_probe([0], ["WARNING: ThreadSanitizer: data race\n" + "normal output\n" * 5000])
        self.assertTrue(self.logs[0].exists())

    def test_nonzero_exit_without_report_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "status 7"):
            self.run_probe([7])

    def test_clean_restart_retains_both_distinct_logs(self):
        self.run_probe([0, 0], ["first generation\n", "second generation\n"])
        self.assertEqual(2, len(set(self.logs)))
        self.assertEqual(["first generation\n", "second generation\n"],
                         [p.read_text() for p in self.logs])

    def test_final_shutdown_failure_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "status 66"):
            self.run_probe([0, 66], ["clean\n", "SUMMARY: ThreadSanitizer: data race\n"])
        self.assertEqual(2, len(self.logs))
        self.assertTrue(all(p.exists() for p in self.logs))

    def test_cleanup_preserves_primary_request_failure(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            with self.assertRaisesRegex(RuntimeError, "primary request failure"):
                self.run_probe([66], request_error=RuntimeError("primary request failure"))
        self.assertIn("cleanup also failed", stderr.getvalue())
        self.assertIn("status 66", stderr.getvalue())

    def test_forced_kill_is_a_failure(self):
        with self.assertRaisesRegex(RuntimeError, "shutdown timed out"):
            self.run_probe([0], timeout=True)
        self.assertEqual(-9, self.processes[0].returncode)


if __name__ == '__main__':
    unittest.main()

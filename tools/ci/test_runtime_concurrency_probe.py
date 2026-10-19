#!/usr/bin/env python3
"""Negative controls for the receive-only channel assertion."""
import socket
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


if __name__ == '__main__':
    unittest.main()

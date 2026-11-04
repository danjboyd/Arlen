"""Focused native primitive tests. Run with Windows Python and probe.exe path."""
import ctypes
from ctypes import wintypes
import subprocess
import sys
import unittest

k32 = ctypes.WinDLL('kernel32', use_last_error=True)
k32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
k32.OpenProcess.restype = wintypes.HANDLE
k32.OpenEventW.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.LPCWSTR]
k32.OpenEventW.restype = wintypes.HANDLE
k32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
k32.CloseHandle.argtypes = [wintypes.HANDLE]
k32.SetEvent.argtypes = [wintypes.HANDLE]
k32.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
EXE = sys.argv.pop(1)


class Lifecycle(unittest.TestCase):
    def start(self, mode):
        proc = subprocess.Popen([EXE, mode], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True)
        self.addCleanup(self.cleanup, proc)
        # Bound output wait as well as process waits: a broken probe cannot hang CI.
        import concurrent.futures
        pool = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        future = pool.submit(proc.stdout.readline)
        try:
            line = future.result(timeout=10)
        finally:
            if not future.done():
                proc.kill()
            pool.shutdown(wait=True)
        leaf, readiness = map(int, line.split())
        handle = k32.OpenProcess(0x101000, False, leaf)
        if handle:
            self.addCleanup(k32.CloseHandle, handle)
        return proc, handle, readiness

    @staticmethod
    def cleanup(proc):
        if proc.poll() is None:
            proc.kill()
        proc.communicate(timeout=10)

    def stop(self, proc):
        event = k32.OpenEventW(2, False, f'Local\\ArlenPrivateStop-{proc.pid}')
        self.assertTrue(event)
        try:
            self.assertTrue(k32.SetEvent(event))
        finally:
            k32.CloseHandle(event)

    def exit_code(self, handle):
        code = wintypes.DWORD()
        self.assertTrue(k32.GetExitCodeProcess(handle, ctypes.byref(code)))
        return code.value

    def test_owner_crash_kills_leaf(self):
        proc, leaf, ready = self.start('hold')
        self.assertEqual(ready, 0)
        self.assertTrue(leaf)
        proc.kill()
        proc.wait(timeout=10)
        self.assertEqual(k32.WaitForSingleObject(leaf, 5000), 0)

    def test_job_close_kills_leaf(self):
        proc, leaf, ready = self.start('close')
        self.assertEqual(ready, 0)
        self.assertEqual(proc.wait(timeout=10), 0)
        if leaf:
            self.assertEqual(k32.WaitForSingleObject(leaf, 5000), 0)

    def test_cooperative_stop(self):
        proc, leaf, ready = self.start('hold')
        self.assertEqual(ready, 0)
        self.stop(proc)
        self.assertEqual(proc.wait(timeout=10), 0)
        self.assertEqual(k32.WaitForSingleObject(leaf, 5000), 0)
        self.assertEqual(self.exit_code(leaf), 0)

    def test_failed_candidate_preserves_old_owner(self):
        old, leaf, ready = self.start('hold')
        self.assertEqual(ready, 0)
        candidate, _, candidate_ready = self.start('unready')
        self.assertEqual(candidate_ready, 258)
        self.assertEqual(candidate.wait(timeout=10), 4)
        self.assertIsNone(old.poll())
        self.assertEqual(k32.WaitForSingleObject(leaf, 0), 258)
        self.stop(old)
        self.assertEqual(old.wait(timeout=10), 0)

    def test_shutdown_deadline_kills_stubborn_leaf(self):
        proc, leaf, ready = self.start('stubborn')
        self.assertEqual(ready, 0)
        self.stop(proc)
        self.assertEqual(proc.wait(timeout=10), 0)
        self.assertEqual(k32.WaitForSingleObject(leaf, 0), 0)
        self.assertEqual(self.exit_code(leaf), 3)

    def test_ready_candidate_before_old_stop(self):
        old, old_leaf, _ = self.start('hold')
        replacement, replacement_leaf, ready = self.start('hold')
        self.assertEqual(ready, 0)
        self.stop(old)
        self.assertEqual(old.wait(timeout=10), 0)
        self.assertEqual(k32.WaitForSingleObject(old_leaf, 5000), 0)
        self.assertEqual(k32.WaitForSingleObject(replacement_leaf, 0), 258)
        self.stop(replacement)
        self.assertEqual(replacement.wait(timeout=10), 0)


if __name__ == '__main__':
    unittest.main(testRunner=unittest.TextTestRunner(stream=sys.stdout, verbosity=2))

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest


RUNNER = Path(__file__).with_name("run-test-process.py")


class TestProcessTests(unittest.TestCase):
    def test_preserves_failure_exit_code(self):
        result = subprocess.run([sys.executable, str(RUNNER), "--timeout", "2", "--",
                                 sys.executable, "-c", "raise SystemExit(7)"], capture_output=True)
        self.assertEqual(result.returncode, 7)

    def test_timeout_kills_descendants_that_ignore_term(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "escaped"
            child = "import signal,time,pathlib; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(1); pathlib.Path(" + repr(str(marker)) + ").touch()"
            parent = "import subprocess,sys,time; subprocess.Popen([sys.executable,'-c'," + repr(child) + "]); time.sleep(10)"
            result = subprocess.run([sys.executable, str(RUNNER), "--timeout", ".3", "--",
                                     sys.executable, "-c", parent], capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 124)
            time.sleep(1)
            self.assertFalse(marker.exists(), "A descendant survived the timeout")

    def test_release_gate_requires_success_at_requested_commit(self):
        gate = RUNNER.parent.parent / "dist" / "require_ci.sh"
        with tempfile.TemporaryDirectory() as directory:
            gh = Path(directory) / "gh"
            receipt = Path(directory) / "arguments"
            gh.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$RECEIPT"\nprintf "%s\\n" "$RESULT"\n')
            gh.chmod(0o755)
            env = dict(os.environ, PATH=directory + ":" + os.environ["PATH"],
                       GH_REPO="example/repo", RECEIPT=str(receipt))
            for outcome in ("success", "failure", "cancelled", "pending", "missing"):
                result = subprocess.run(["bash", str(gate), "abc123"],
                                        env=dict(env, RESULT=outcome), capture_output=True)
                self.assertEqual(result.returncode == 0, outcome == "success", outcome)
                self.assertIn("head_sha=abc123", receipt.read_text())
                if outcome == "success":
                    self.assertIn("repos/example/repo/commits/abc123/check-runs", receipt.read_text())


if __name__ == "__main__":
    unittest.main()

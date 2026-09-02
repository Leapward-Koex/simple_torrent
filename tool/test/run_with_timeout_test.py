#!/usr/bin/env python3
"""Behavioral tests for the Unix process-group timeout supervisor."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import time
import unittest


SUPERVISOR = Path(__file__).resolve().parents[1] / "run_with_timeout.py"


@unittest.skipUnless(os.name == "posix", "the supervisor is used on Unix runners")
class RunWithTimeoutTest(unittest.TestCase):
    def run_supervised(
        self,
        timeout_seconds: int,
        program: str,
    ) -> tuple[subprocess.CompletedProcess[str], float]:
        started = time.monotonic()
        result = subprocess.run(
            [
                sys.executable,
                str(SUPERVISOR),
                str(timeout_seconds),
                sys.executable,
                "-c",
                program,
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=8,
        )
        return result, time.monotonic() - started

    def test_returns_124_and_stops_the_group_at_the_deadline(self) -> None:
        result, elapsed = self.run_supervised(1, "import time; time.sleep(30)")

        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertIn("exceeded its 1-second deadline", result.stderr)
        self.assertLess(elapsed, 5)

    def test_cleans_up_a_descendant_that_keeps_output_open(self) -> None:
        program = (
            "import subprocess, sys; "
            "subprocess.Popen([sys.executable, '-c', "
            "'import time; time.sleep(30)'])"
        )

        result, elapsed = self.run_supervised(5, program)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("descendants still running", result.stderr)
        self.assertLess(elapsed, 5)

    def test_preserves_a_normal_nonzero_exit_code(self) -> None:
        result, _ = self.run_supervised(5, "raise SystemExit(7)")

        self.assertEqual(result.returncode, 7, result.stderr)


if __name__ == "__main__":
    unittest.main()

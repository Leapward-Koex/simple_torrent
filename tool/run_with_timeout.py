#!/usr/bin/env python3
"""Run one command in an isolated process group with a hard deadline."""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import time


_TIMEOUT_EXIT_CODE = 124
_TERMINATION_GRACE_SECONDS = 10


def _signal_process_group(process_group: int, value: int) -> None:
    try:
        os.killpg(process_group, value)
    except ProcessLookupError:
        pass


def _process_group_exists(process_group: int) -> bool:
    try:
        os.killpg(process_group, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _stop_process_group(process: subprocess.Popen[bytes], value: int) -> None:
    process_group = process.pid
    _signal_process_group(process_group, value)
    deadline = time.monotonic() + _TERMINATION_GRACE_SECONDS
    while _process_group_exists(process_group) and time.monotonic() < deadline:
        process.poll()
        time.sleep(0.1)
    if _process_group_exists(process_group):
        _signal_process_group(process_group, signal.SIGKILL)
    try:
        process.wait(timeout=_TERMINATION_GRACE_SECONDS)
    except subprocess.TimeoutExpired:
        _signal_process_group(process_group, signal.SIGKILL)
        process.wait()


def main() -> int:
    if len(sys.argv) < 3:
        print(
            "usage: run_with_timeout.py <timeout-seconds> <command> [argument ...]",
            file=sys.stderr,
        )
        return 64

    try:
        timeout_seconds = int(sys.argv[1])
    except ValueError:
        timeout_seconds = 0
    if timeout_seconds <= 0:
        print("timeout-seconds must be a positive integer", file=sys.stderr)
        return 64

    command = sys.argv[2:]
    process = subprocess.Popen(command, start_new_session=True)
    forwarding_signal = False

    def forward_signal(value: int, _frame: object) -> None:
        nonlocal forwarding_signal
        if forwarding_signal:
            return
        forwarding_signal = True
        _stop_process_group(process, value)
        raise SystemExit(128 + value)

    for forwarded in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(forwarded, forward_signal)

    try:
        return_code = process.wait(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        print(
            f"Command exceeded its {timeout_seconds}-second deadline; "
            "terminating its process group.",
            file=sys.stderr,
            flush=True,
        )
        _stop_process_group(process, signal.SIGTERM)
        return _TIMEOUT_EXIT_CODE

    # Some launchers exit before descendants that inherited their stdout and
    # stderr. Leaving those descendants alive can keep the surrounding `tee`
    # pipeline open forever even though the direct child has finished.
    if _process_group_exists(process.pid):
        print(
            "Command exited with descendants still running; "
            "terminating its process group.",
            file=sys.stderr,
            flush=True,
        )
        _stop_process_group(process, signal.SIGTERM)

    if return_code < 0:
        return 128 - return_code
    return return_code


if __name__ == "__main__":
    raise SystemExit(main())

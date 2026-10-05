#!/usr/bin/env python3
"""Bound a test command and clean up its entire process group."""

import argparse
import os
import signal
import subprocess
import sys
import time


def run(command, timeout):
    process = subprocess.Popen(command, start_new_session=True)

    def stop_group(sig):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            pass

    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)

    previous = {sig: signal.signal(sig, interrupted) for sig in (signal.SIGTERM, signal.SIGINT)}
    try:
        try:
            return process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            print(f"Test command exceeded {timeout}s; terminating its process group.", file=sys.stderr)
            return 124
    finally:
        # SwiftPM can leave XCTest or helper children alive after a timeout.
        # Their build locks must not block the next qualification step.
        stop_group(signal.SIGTERM)
        time.sleep(0.2)
        stop_group(signal.SIGKILL)
        process.wait()
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if args.timeout <= 0 or not command:
        parser.error("a positive timeout and command are required")
    return run(command, args.timeout)


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Run a command in its own process group, wait for a marker file, send the
group SIGINT as a terminal's Ctrl-C does, and exit with the command's status.
Usage: sigint.py <marker file> <command...>"""
import os, signal, subprocess, sys, time

marker, cmd = sys.argv[1], sys.argv[2:]
# A terminal's foreground job has SIGINT at its default; a harness started as a
# background job inherits it ignored, and an ignored signal cannot be trapped.
p = subprocess.Popen(cmd, start_new_session=True, preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
deadline = time.time() + 60
while time.time() < deadline and not os.path.exists(marker) and p.poll() is None:
    time.sleep(0.1)
if p.poll() is None:
    os.killpg(p.pid, signal.SIGINT)
try:
    rc = p.wait(timeout=30)
except subprocess.TimeoutExpired:
    os.killpg(p.pid, signal.SIGKILL)
    rc = 999
sys.exit(rc)

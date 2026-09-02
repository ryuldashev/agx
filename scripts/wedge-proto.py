#!/usr/bin/env python3
"""Regression proof for the pty write deadlock fixed in vendor/abduco (see PATCHES.md).

Upstream abduco pushed client input into the pty with a BLOCKING write from inside its
select loop. Feed it more than one pty queue (BUFSIZ = 1024 on macOS) while the program
is painting, and both sides wedge: the server blocks writing input, so it never drains
the pty, so the program blocks writing output, so it never reads the input. The pane
goes dead — no echo, no repaint — until something flushes the tty by hand.

This drives the real binary through the same shape a pasted block takes: a session
running a program that emits a burst of output for every byte it reads, then one large
write into the client's pty. A patched abduco answers; an unpatched one hangs and the
queue probe below shows both queues pinned full.

    scripts/wedge-proto.py [path/to/abduco]
"""
import fcntl
import os
import pty
import select
import struct
import sys
import time
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ABDUCO = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "vendor/abduco/abduco")
SOCK = "/tmp/agx-wedge-%s" % uuid.uuid4().hex[:8]  # short: sun_path caps near 104 bytes

PAYLOAD = 8000        # bytes pasted in one write; anything over 1024 used to be fatal
BURST = 200           # bytes the program prints per byte read — the output pressure
TIMEOUT = 25.0

TIOCOUTQ = 0x40047473
FIONREAD = 0x4004667F

# Reads one byte at a time, answers every byte with a burst of output, and reports the
# running total when it sees a newline. Raw mode so nothing is echoed or line-buffered.
PROGRAM = (
    "import os,sys,tty,termios\n"
    "fd=sys.stdin.fileno()\n"
    "tty.setraw(fd)\n"
    "n=0\n"
    "while True:\n"
    "    d=os.read(fd,1)\n"
    "    if not d: break\n"
    "    n+=1\n"
    "    os.write(1,b'.'*%d)\n"
    "    if d==b'\\n': os.write(1,b'\\r\\nGOT %%d\\r\\n'%%n)\n"
    "    if d==b'\\x03': break\n" % BURST
)


def queues(tty_path):
    fd = os.open(tty_path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    try:
        out = struct.unpack("i", fcntl.ioctl(fd, TIOCOUTQ, struct.pack("i", 0)))[0]
        inp = struct.unpack("i", fcntl.ioctl(fd, FIONREAD, struct.pack("i", 0)))[0]
        return out, inp
    finally:
        os.close(fd)


def program_tty():
    """The pty of the program abduco forked, found through the detached server."""
    import subprocess
    ps = subprocess.run(["ps", "-eo", "pid,ppid,tty,command"], capture_output=True, text=True)
    server = None
    for line in ps.stdout.splitlines()[1:]:
        f = line.split(None, 3)
        if len(f) == 4 and SOCK in f[3] and f[1] == "1":
            server = f[0]
    if not server:
        return None
    for line in ps.stdout.splitlines()[1:]:
        f = line.split(None, 3)
        if len(f) == 4 and f[1] == server and f[2].startswith("ttys"):
            return "/dev/" + f[2]
    return None


def main():
    print("abduco: %s" % ABDUCO)
    pid, master = pty.fork()
    if pid == 0:
        os.execv(ABDUCO, [ABDUCO, "-A", "-f", SOCK, sys.executable, "-c", PROGRAM])

    ok = False
    try:
        time.sleep(1.5)  # let the session come up and the program reach its first read

        # Paste while draining output, exactly as the terminal does: a client that
        # stops reading would stall the chain on its own and prove nothing.
        os.set_blocking(master, False)
        payload = b"A" * PAYLOAD + b"\n"
        want = b"GOT %d" % (PAYLOAD + 1)
        sent, seen = 0, b""
        deadline = time.time() + TIMEOUT
        while time.time() < deadline:
            want_write = [master] if sent < len(payload) else []
            r, w, _ = select.select([master], want_write, [], 0.5)
            if w:
                try:
                    sent += os.write(master, payload[sent:sent + 4096])
                except (BlockingIOError, OSError):
                    pass
            if r:
                try:
                    chunk = os.read(master, 65536)
                except (BlockingIOError, OSError):
                    continue
                if not chunk:
                    break
                seen = (seen + chunk)[-4096:]
                if want in seen:
                    ok = True
                    break

        if ok:
            print("PASS  program consumed all %d pasted bytes" % (PAYLOAD + 1))
        else:
            print("FAIL  no answer within %.0fs (%d/%d bytes delivered) — the pane is wedged"
                  % (TIMEOUT, sent, len(payload)))
            tty_path = program_tty()
            if tty_path:
                out, inp = queues(tty_path)
                print("      %s queues: out=%d in=%d (1024/1024 == deadlock)" % (tty_path, out, inp))
    finally:
        os.close(master)
        try:
            os.kill(pid, 9)
            os.waitpid(pid, 0)
        except OSError:
            pass
        tty_path = program_tty()
        if tty_path:  # server survives a killed client by design; take it down explicitly
            import subprocess
            subprocess.run(["pkill", "-9", "-f", SOCK], capture_output=True)
        try:
            os.unlink(SOCK)
        except OSError:
            pass
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Standalone proof for docs/decisions/0001-abduco-durable-panes.md.

Drives the exact wrapper line a durable pane will run, under a pty that stands in for
libghostty's: attach, close the pty (what an app quit does to the client), reattach from a new
pty and check the same program answers, then SIGTERM the server through the pid file's parent
and check socket + program are gone. A last phase kills the program while detached and checks
`-A -f` replaces the dead session with a fresh program instead of closing the pane.
"""
import os, pty, re, select, signal, subprocess, sys, time, uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ABDUCO = os.path.join(ROOT, "vendor/abduco/abduco")
BASE = "/tmp/agx-abd"  # short on purpose: sun_path caps near 104 bytes


def sq(s):
    return "'" + s.replace("'", "'\\''") + "'"


def argv_for(sock, line):
    wrapper = f"printf %d $$ >{sq(sock + '.pid')}; exec {line}"
    return [ABDUCO, "-A", "-f", sock, "/bin/zsh", "-lc", wrapper]


def attach(sock, line):
    pid, fd = pty.fork()
    if pid == 0:
        os.execv(ABDUCO, argv_for(sock, line))
    read_until(fd, b"% ")  # the stand-in shell's prompt: input typed before ZLE is up is eaten
    return pid, fd


def read_until(fd, needle, timeout=5):
    buf, end = b"", time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if not r:
            continue
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        if needle in buf:
            return buf
    return buf


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def ppid(pid):
    return int(subprocess.check_output(["ps", "-o", "ppid=", "-p", str(pid)]).strip())


def ask_pid(fd, mark):
    os.write(fd, f"echo PID=$$; echo {mark[:2]}\"\"{mark[2:]}\n".encode())
    out = read_until(fd, mark.encode())
    m = re.search(rb"PID=(\d+)", out)
    assert m, out
    return int(m.group(1)), out


def check(cond, msg):
    print(("ok   " if cond else "FAIL ") + msg)
    if not cond:
        sys.exit(1)


os.makedirs(BASE, exist_ok=True)
sock = f"{BASE}/{uuid.uuid4()}"
line = "/bin/zsh -f"  # stand-in for `claude`: an interactive program that answers on its pty

# phase 1: create + attach
cpid, fd = attach(sock, line)
prog, _ = ask_pid(fd, "MARK1")
time.sleep(0.2)
pidfile = int(open(sock + ".pid").read())
server = ppid(prog)
check(prog == pidfile, f"pid file names the program ({prog})")
check(ppid(server) == 1, f"server {server} reparented to launchd")
check(os.path.exists(sock), "socket exists")

# phase 2: app quit = pty master closes, client gets SIGHUP
os.write(fd, b"(sleep 1; echo LATE-OUTPUT) &\n")
os.close(fd)
os.waitpid(cpid, 0)
time.sleep(1.5)
check(alive(prog) and alive(server), "program + server survive the client's pty closing")
check(os.path.exists(sock), "socket still there while detached")

# phase 3: reattach from a fresh pty (a relaunched app)
cpid2, fd2 = attach(sock, line)
prog2, out2 = ask_pid(fd2, "MARK2")
check(prog2 == prog, f"reattach lands in the SAME program pid ({prog2})")
check(b"LATE-OUTPUT" not in out2, "output emitted while detached is drained, not replayed (redraw is the program's job)")

# phase 4: session close = SIGTERM the server via pid file -> ppid
os.kill(server, signal.SIGTERM)
time.sleep(0.5)
check(not alive(server), "server gone after SIGTERM")
check(not alive(prog), "program gone (SIGHUP from its pty)")
check(not os.path.exists(sock), "socket unlinked by the server's atexit")
try:
    os.close(fd2)
except OSError:
    pass
os.waitpid(cpid2, 0)

# phase 5: program dies while detached -> `-A -f` replaces it instead of closing the pane
sock5 = f"{BASE}/{uuid.uuid4()}"
cpid5, fd5 = attach(sock5, line)
prog5, _ = ask_pid(fd5, "MARK5")
server5 = ppid(prog5)
os.close(fd5)
os.waitpid(cpid5, 0)
os.kill(prog5, signal.SIGKILL)
time.sleep(0.5)
check(alive(server5) and os.path.exists(sock5), "server holds the exit status while nobody is attached")
cpid6, fd6 = attach(sock5, line)
prog6, out6 = ask_pid(fd6, "MARK6")
check(b"terminated" in out6 or prog6 != prog5, "-A -f reported the old exit and created a fresh program")
check(prog6 != prog5 and alive(prog6), f"fresh program pid {prog6} != dead {prog5}")
os.kill(ppid(prog6), signal.SIGTERM)
time.sleep(0.3)
os.close(fd6)
os.waitpid(cpid6, 0)
for p in (sock + ".pid", sock5 + ".pid"):
    try:
        os.remove(p)
    except FileNotFoundError:
        pass
print("ALL OK")

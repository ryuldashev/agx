# 2026-09-03 — a pasted paragraph could freeze a pane (abduco pty deadlock)

## Symptom

A live `claude` pane stopped accepting keys and stopped repainting. The process was healthy —
0% CPU, transcript intact, no crash. It happened twice in an hour on the same pane, both times
right after a paste.

## Cause

`vendor/abduco` 0.6 pushes client input into the pty with a **blocking** `write_all()` called from
inside `server_mainloop()`. macOS caps both pty queues at 1024 bytes (`TTYHOG`, and `BUFSIZ` — the
packet size — is 1024 too). Paste more than that while the program is painting and the two
directions lock each other out:

| side | blocked in |
| --- | --- |
| the program (`claude`) | `__write_nocancel` — output queue full at 1024/1024 |
| abduco server | `server_write_pty` — input queue full at 1022/1024 |
| abduco client | `client_send_packet` → `write_all`, spinning at 100% CPU on `EAGAIN` |

The server can't drain the pty because it is stuck writing to it; the program can't read its input
because it is stuck writing its output. Nothing times out. Measured with `sample(1)` on the live
pane and `TIOCOUTQ`/`FIONREAD` on its tty.

Threshold is 1024 **bytes**, not a screenful — Russian text is 2 bytes per character in UTF-8, so
~500 characters (6–8 lines) is enough.

## Fix — `vendor/abduco`, three parts (see `vendor/abduco/PATCHES.md`)

1. `abduco.c`: server sets `O_NONBLOCK` on `server.pty` after `forkpty()`.
2. `server.c`: `server_write_pty()` parks the packet in one `ptyout` slot and flushes what fits;
   the mainloop selects the pty for writability while the slot is occupied and stops reading
   client sockets until it drains. Back-pressure goes back to the client instead of buffering
   here — and one slot is always enough, because a packet is at most `BUFSIZ` = the queue size.
3. `abduco.c`: `write_all()` waits in `select()` on `EAGAIN` instead of a bare `continue`. That
   loop is what burned a core in the client.

## Verification

- `scripts/wedge-proto.py` — new. Pre-patch binary: `FAIL … queues out=1024 in=1022`. Patched:
  `PASS  program consumed all 8001 pasted bytes`.
- `scripts/durable-proto.py` — still `ALL OK`, no regression to durable panes.
- Real pane: 8 KB pasted into a `zsh` line editor, no freeze, input still live afterwards.

## Rollout note

Nested binaries inside `agx.app` are signature-checked at exec: dropping a rebuilt `abduco` into
`Contents/Resources/abduco/` gets the process **SIGKILLed** (exit 137) until it is signed again —
`codesign --force --sign - <path>` is enough, and it leaves the app's own signature alone. A normal
`scripts/build.sh` handles this on its own.

Live sessions keep the abduco server they were started with, so the fix applies to panes created
after the swap; existing panes carry the old binary until they are recreated.

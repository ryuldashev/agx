# Local patches to vendored abduco

abduco is vendored from upstream v0.6 (see the `vendor abduco 0.6` commit). It is no longer
byte-for-byte upstream: the divergences below are intentional and live here so a future re-vendor
knows what to re-apply. Keep this file in sync with any further change to `vendor/abduco/`.

## Build flags (not a source patch)

macOS needs `-D_DARWIN_C_SOURCE`; the Makefile's strict `-D_POSIX_C_SOURCE`/`-D_XOPEN_SOURCE`
hide `SIGWINCH` and `VLNEXT`. `scripts/setup.sh` builds with
`make CPPFLAGS=-D_DARWIN_C_SOURCE`, so the checked-in Makefile is untouched.

## `abduco.c` — `session_wait_gone()` before re-creating a dead session

Reason: durable panes (ADR `docs/decisions/0001-abduco-durable-panes.md`) rely on `abduco -A -f`
to reattach a live session or, when the program already exited while detached, replace it. In 0.6
that replacement races: the terminated server hands its exit status to the attaching client, then
exits and unlinks its socket a moment LATER, so a `create` that runs in between fails `bind()` with
`EADDRINUSE` (`create-session: Address already in use`) and the pane closes instead of restarting.

Patch: a bounded (2 s) `session_wait_gone()` waits for the old server to disappear before creating,
called on the two `-f`/`-A` fall-through-to-create paths. Once the server is gone, `session_connect()`
removes the stale socket file itself. Verified by `scripts/durable-proto.py` (phase 5).

## `server.c` + `abduco.c` — non-blocking pty writes, so a paste cannot deadlock a pane

Reason: 0.6 pushes client input into the pty with a BLOCKING `write_all()` called from inside
`server_mainloop()`. Paste more than one pty queue (`BUFSIZ` = 1024 on macOS) while the program is
painting and both directions wedge: the server blocks writing input so it never drains the pty, the
program blocks writing output so it never reads the input. The pane goes dead — no echo, no repaint
— and only a manual `tcflush()` on the tty gets it back. Measured on a real pane: `claude` in
`__write_nocancel`, the server in `server_write_pty`, both queues pinned at 1024, and the client
burning 100% of a core. A Russian paste of ~500 characters is enough to trigger it.

Patch, three parts:
- `abduco.c`: the server sets `O_NONBLOCK` on `server.pty` right after `forkpty()`. `server_read_pty()`
  already tolerates `EAGAIN`, so only the write path changes.
- `server.c`: `server_write_pty()` no longer writes through `write_all()`. It parks the packet in a
  single `ptyout` slot and flushes what fits; the mainloop selects the pty for writability while the
  slot is occupied and stops selecting/reading client sockets until it drains. Back-pressure runs
  back to the client instead of growing a buffer here — and one slot always suffices, since a packet
  is at most `BUFSIZ`, which is also the pty queue size.
- `abduco.c`: `write_all()` waits in `select()` for writability on `EAGAIN` instead of retrying in a
  tight loop. That bare `continue` is what burned a core on the client's socket.

Verified by `scripts/wedge-proto.py`: the pre-patch binary fails with both queues at 1024, the
patched one delivers all 8001 pasted bytes. `scripts/durable-proto.py` still passes.

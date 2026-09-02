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

# The reader pane

Agents produce documents — plans, reports, reviews — and a terminal is a bad place to read one. The
reader shows a markdown file in the session's split pane, rendered, next to the shell that is
writing it, and re-renders on every save. The user reads without leaving the session; the agent
keeps editing the file and never pastes it into the chat. This guide is itself read through it.

## Opening and closing

```sh
agx reader plan.md                                  # this session's right pane
agx reader close
agtermctl session reader open ~/report.md --target <id> [--size-percent 60]
agtermctl session reader close --target <id>
```

Paths are resolved against the caller's directory; an unreadable file is refused rather than
watched forever. One document per session — a second `open` replaces the first in place. The
reader is not persisted: after a relaunch the pane is a shell again.

Help ▸ agx Guide… opens this guide the same way, in the active session's pane (or in your markdown
app when no session is selected).

## Living with the split

The reader borrows the split's right pane, so it obeys the split's rules rather than floating over
them. If the session had no split, the reader shows one at 45 % width and remembers that it did:
`close` then takes the split down again (or hides it, if a shell has since run there). If a split
already existed, the reader replaces its shell's view while the shell stays alive unhosted, and
`close` gives it back. `--size-percent` (20–80) moves the divider; otherwise the split's own ratio
holds. ⌘D hides the split and the reader with it; Close Split closes both.

Focus follows a click: click the document and the shell dims and ⌘+ / ⌘− / ⌘0 zoom the text
(10–28 px); click the shell and the document dims. ⌃2 and `session focus --pane right` target the
split *surface*, so with a reader in the pane they are no-ops — click to get in. The page is
tinted to the terminal's background, so it reads as a pane, not a web view.

## Links, zoom and pop-out

- A relative `.md` link opens in the same pane, which is how this guide's chapters chain; the
  `tree` read-back (`reader.path`) follows.
- A web link opens in the browser; any other file opens in whatever handles it.
- **Open in Reader** (the button at the top of the pane) hands the file to the standalone MmeeReader
  when it is installed, else to the system's `.md` handler, and frees the pane. That is where the
  outline, find, and PDF export live; the pane has none.
- The rendering page is a verbatim copy of MmeeReader's (markdown-it, DOMPurify, idiomorph for
  in-place DOM patching, so scroll position survives a re-render).

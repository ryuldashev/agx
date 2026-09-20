# The reader pane

Agents produce documents — plans, reports, reviews — and a terminal is a bad place to read one. The
reader shows a markdown file in the session's split pane, rendered, next to the shell that is
writing it, and re-renders on every save. You are reading this guide through it.

```sh
agx reader plan.md                                  # this session's right pane
agx reader close
agtermctl session reader open ~/report.md --target <id> [--size-percent 60]
agtermctl session reader close --target <id>
```

| rule | detail |
|---|---|
| path | resolved against the caller's directory; an unreadable file is refused, not watched forever |
| one per session | a second `open` replaces the first in place |
| not persisted | after a relaunch the pane is a shell again |
| Help ▸ agx Guide… | opens this guide the same way in the active session's pane (no session: your `.md` app) |

## Living with the split

The reader borrows the split's right pane, so it obeys the split's rules rather than floating over
them:

- No split yet → the reader shows one at 45 % width and remembers that; `close` takes the split
  down again (or hides it, if a shell has since run there).
- Split already there → the reader replaces the shell's *view*; the shell stays alive unhosted and
  `close` gives it back.
- `--size-percent` (20–80) moves the divider; otherwise the split's own ratio holds.
- ⌘D hides the split and the reader with it; Close Split closes both.

Focus follows a click: click the document and the shell dims and ⌘+ / ⌘− / ⌘0 zoom the text
(10–28 px); click the shell and the document dims. ⌃2 and `session focus --pane right` target the
split *surface*, so with a reader in the pane they are no-ops — click to get in. The page is
tinted to the terminal's background, so it reads as a pane, not a web view.

![The guide open beside the shell](../screenshots/guide-reader-pane.png)

## Links and pop-out

- A relative `.md` link opens in the same pane (how this guide's chapters chain); `tree` reports
  the current file as `reader.path`.
- A web link opens in the browser; any other file in whatever handles it.
- **Open in Reader** (top of the pane) hands the file to the standalone MmeeReader when installed,
  else to the system's `.md` handler, and frees the pane. Outline, find, and PDF export live there;
  the pane has none.

# Keyboard, palettes and ⌥ hints

With many sessions the mouse is the slow path. Three palettes reach any session or action by name, a
handful of chords move between sessions and panes, and holding ⌥ names every button on screen — so a
problem can be reported as `split · both : click → …` instead of a screenshot.

The live, rebindable list is **Help ▸ Keyboard Shortcuts…** (⌘/), generated from the keymap that is
actually loaded and shown in the reader pane; `agtermctl keymap list` prints the same from a shell.
This chapter is the shape of it.

## Palettes

| chord | palette | lists |
|---|---|---|
| ⌃P | sessions | every session across workspaces, fuzzy by name; Enter selects |
| ⌃⇧P | actions | every built-in action with its current chord, plus custom commands tagged `custom` |
| ⌃⇧O | custom commands | the `command` lines from your keymap alone |
| ⌃⇥ | recent switcher | sessions by recency; hold ⌃ and tap ⇥ to walk back |
| ⌃⇧I | attention | every session with a glyph, `⛔` first |

The title-bar `recent` popover shows the recency list plus **recently closed** items (⌘⇧T reopens
the last one; `agtermctl restore list | open <n> | last`).

![Action palette](../screenshots/action-palette.png)

## ⌥ names the chrome

Hold ⌥ alone and a panel drops under the title bar listing every visible control as
icon · token · shortcut; release and it is gone. The tokens are the vocabulary for talking about the
UI — `sidebar`, `recent`, `bell`, `zoom`, `split`, `dash`, `quick` in the title bar; `workspace+`,
`session+`, `filter`, `flagged` in the sidebar. Controls hidden in Settings ▸ Interface are not
listed. `AGX_HINTS_ALWAYS=1` in the environment pins the panel open for a whole run (a held ⌥ cannot
be screenshotted). The full vocabulary, including the three states of `split`, is
[ui-lexicon.md](../ui-lexicon.md).

![The ⌥ hint panel](../screenshots/guide-option-hints.png)

## Chords worth knowing

Defaults, every one rebindable:

| chord | does |
|---|---|
| ⌘N / ⌘⇧N / ⌘⌥N | new session / workspace / window |
| ⌘O | new session in a directory you pick |
| ⌘W · ⌘Z · ⌘⇧T | close session · undo that close (3 s) · reopen last closed |
| ⌘⌥↑ / ⌘⌥↓ | previous / next session |
| ⌃⌥↑ / ⌃⌥↓ | previous / next session with a glyph |
| ⌘⇧F | flag / unflag the session |
| ⌘D / ⌘⇧D | split beside / below; again to hide the split |
| ⌃1 / ⌃2 | focus main / split pane (on a hidden split: choose which is shown) |
| ⌘⌥← / ⌘⌥→ | focus left / right pane |
| ⌘⇧⏎ | zoom the focused pane to the window |
| ⌘J | scratch terminal over the session |
| ⌃` | quick terminal over the window |
| ⌘⇧G | dashboard |
| ⌃⌘S | sidebar |
| ⌘F | find in scrollback |
| ⌘+ / ⌘− / ⌘0 | font size (the reader's text when the document is focused) |
| ⌃⌘F | full screen |
| ⌘, | Settings |

⌘C / ⌘V are bound to the physical C and V keys, so they copy and paste on a Cyrillic or any other
layout. ⌃⇥, ⌃⇧⇥, ⌃1 and ⌃2 are reserved and cannot be rebound.

## Custom keymap

`~/.config/agx/keymap.conf` (File ▸ Edit Keymap…; reload with File ▸ Reload Keymap or
`agtermctl keymap reload`):

```
map cmd+shift+j toggle_scratch                                   # rebind a built-in
command "Deploy" cmd+shift+s /bin/zsh -lc '~/bin/deploy.sh'      # a chord that runs a shell line
command "Report" agtermctl session overlay open "zsh -lc ~/bin/report.sh" --socket "$AGT_SOCKET"
```

A `command` without a chord is palette-only (⌃⇧O). Custom commands run in `/bin/sh -c`, not your
login shell, with `{AGT_SELECTION}` and the other `{AGT_*}` tokens expanded; a chord that collides
with a built-in drops to palette-only and is listed in Settings ▸ Key Mapping. Parser diagnostics,
the modifier rule, and the focus rule: [Troubleshooting](../troubleshooting.md#a-custom-action-does-nothing).
On first run AGX copies `~/.config/agterm/*.conf` across when it has no config of its own, so a
keymap written for agterm carries over.

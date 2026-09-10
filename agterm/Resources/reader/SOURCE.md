Source of truth: `~/mmee/reader/web` (the standalone MmeeReader app). Resync with `make sync-reader`;
the vendored `*.min.js` are pinned by that repo's `web/fetch.sh`. `MarkdownReaderView` mirrors its
`WebPane.swift`/`FileWatcher.swift`, so a fix there is a fix here.

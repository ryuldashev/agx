import Foundation

/// Watches one file through a `DispatchSource` and survives atomic saves: an editor or agent that writes a
/// temp file and renames it over the original delivers `.rename`/`.delete`, after which the descriptor
/// points at the orphaned inode, so the source is cancelled and re-armed on the PATH. A missing file is
/// retried on a short cadence and reported after four misses, then reported back the moment it returns.
/// Mirrors `FileWatcher.swift` in `~/mmee/reader`; keep the two in step.
///
/// `@unchecked Sendable` because every mutable field is touched on `queue` alone — `init` and `cancel`
/// hop there — and the callbacks hop to the main actor themselves.
final class ReaderFileWatcher: @unchecked Sendable {
    private let url: URL
    private let onChange: @MainActor @Sendable () -> Void
    private let onMissing: @MainActor @Sendable (Bool) -> Void
    private var misses = 0
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private var cancelled = false
    private let queue = DispatchQueue(label: "\(Bundle.main.bundleIdentifier ?? "agx").reader.watch")

    init(url: URL, onChange: @escaping @MainActor @Sendable () -> Void,
         onMissing: @escaping @MainActor @Sendable (Bool) -> Void) {
        self.url = url
        self.onChange = onChange
        self.onMissing = onMissing
        queue.async { self.arm() }
    }

    deinit { source?.cancel() }

    /// Stops watching for good: the re-arm loop checks the flag, so a watcher torn down while the file is
    /// missing cannot keep polling the path from its own queue after the panel is gone.
    func cancel() {
        queue.async {
            self.cancelled = true
            self.debounce?.cancel()
            self.source?.cancel()
            self.source = nil
        }
    }

    private func arm() {
        guard !cancelled else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            misses += 1
            if misses == 4 { report(missing: true) }
            queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.arm() }
            return
        }
        if misses >= 4 { report(missing: false) }
        misses = 0
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data
            self.fire()
            if event.contains(.delete) || event.contains(.rename) {
                source.cancel()
                self.source = nil
                self.queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.arm() }
            }
        }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }

    /// Coalesces a burst of events (a save is several writes plus an attribute change) into one reread.
    private func fire() {
        debounce?.cancel()
        let onChange = onChange
        let work = DispatchWorkItem { Task { @MainActor in onChange() } }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func report(missing: Bool) {
        let onMissing = onMissing
        Task { @MainActor in onMissing(missing) }
    }
}

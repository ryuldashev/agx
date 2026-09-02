/// Cleans terminal text on its way to the pasteboard: a copy out of a TUI pane otherwise carries the box
/// gutter it was drawn inside (`│ code`), the padding that squared its frame, and a common indent, all of
/// which have to be deleted by hand before the text can be pasted anywhere. Pure and host-free so the
/// rules are testable without a terminal.
///
/// Deliberately NOT re-joining hard-wrapped lines: a TUI wraps its own text, and nothing in the copied
/// characters distinguishes that break from one the author meant. Soft wraps are already rejoined by
/// libghostty before the text reaches here.
public enum CopyCleanup {
    /// Prefix characters a TUI draws its left frame with, plus the two quote markers that behave the same
    /// way. A gutter is one of these followed by at most one space.
    private static let gutterCharacters: Set<Character> = ["│", "┃", "┆", "┇", "┊", "┋", "║", "▏", "▎",
                                                           "▌", "╎", "╏", "|", ">"]

    /// `text` with trailing whitespace, a shared frame gutter, the surrounding blank lines and the common
    /// indent removed. Returns the input unchanged when it carries none of those, so an ordinary shell copy
    /// is byte-identical to what the terminal held.
    public static func clean(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var lines = text.components(separatedBy: "\n").map { line -> String in
            var line = Substring(line)
            while let last = line.last, last == " " || last == "\t" { line = line.dropLast() }
            return String(line)
        }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        guard !lines.isEmpty else { return "" }
        lines = stripGutter(lines)
        lines = deindent(lines)
        return lines.joined(separator: "\n")
    }

    /// Drop the leading frame character (and the single space after it) when EVERY non-empty line carries
    /// the same one — one line without it means the run is content, not a frame.
    private static func stripGutter(_ lines: [String]) -> [String] {
        let filled = lines.filter { !$0.isEmpty }
        guard let gutter = filled.first?.first, gutterCharacters.contains(gutter),
              filled.allSatisfy({ $0.first == gutter }) else { return lines }
        return lines.map { line in
            guard line.first == gutter else { return line }
            let body = line.dropFirst()
            return String(body.first == " " ? body.dropFirst() : body)
        }
    }

    /// Remove the deepest indent every non-empty line shares, so a nested block pastes at column zero.
    private static func deindent(_ lines: [String]) -> [String] {
        let indents = lines.filter { !$0.isEmpty }.map { $0.prefix { $0 == " " || $0 == "\t" } }
        guard let shortest = indents.min(by: { $0.count < $1.count }), !shortest.isEmpty,
              indents.allSatisfy({ $0.hasPrefix(shortest) }) else { return lines }
        return lines.map { $0.isEmpty ? $0 : String($0.dropFirst(shortest.count)) }
    }
}

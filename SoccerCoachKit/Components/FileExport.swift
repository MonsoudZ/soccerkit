import SwiftUI

/// A file prepared for sharing. Identifiable so a prepared URL can drive a
/// `.sheet(item:)`.
struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Presents the system share sheet for an exported file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Writes export data somewhere the share sheet can hand it off from.
enum FileExport {
    /// How much of a coach-typed title survives into a filename, in UTF-8
    /// bytes. Most filesystems cap a path component at 255 bytes, and the
    /// suffix and extension have to fit alongside it.
    private static let maxBaseBytes = 120

    /// Writes `data` to a temporary file and returns where it went.
    ///
    /// Throws rather than returning an optional. The three export paths that
    /// grew out of this each wrote their own copy, and two of them answered a
    /// failed write with `guard let url = … else { return }` — the coach tapped
    /// Export and nothing happened, with nothing said. An optional invites that
    /// answer; a thrown error doesn't.
    static func write(_ data: Data, named fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url)
        return url
    }

    /// Reduces a coach-entered title to a filesystem-safe basename.
    ///
    /// Truncated as well as filtered: the title is free text, and a long one
    /// would push the filename past the filesystem's limit and fail the write.
    /// That failure now reaches the coach instead of vanishing, but it's still
    /// one they can do nothing about, so don't create it. The budget is counted
    /// in UTF-8 bytes because the filter keeps any Unicode letter — a squad
    /// named in Japanese spends three bytes a character, not one.
    /// Separators are collapsed and trimmed before the emptiness check, not
    /// after. Filtering alone leaves a title like "!!! ???" as a bare "-",
    /// which isn't empty — so the fallback never fired and the export was
    /// named "--roster.csv", leading hyphen and all.
    static func slug(_ title: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let words = title
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: allowed.inverted)
            .joined()
            .split(separator: "-", omittingEmptySubsequences: true)
        let cleaned = words.joined(separator: "-")
        // Truncation can land on a separator, so trim once more after cutting.
        let trimmed = truncated(cleaned, toUTF8Bytes: maxBaseBytes)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// Cuts on a character boundary so the result is never invalid UTF-8.
    private static func truncated(_ text: String, toUTF8Bytes limit: Int) -> String {
        guard text.utf8.count > limit else { return text }
        var result = ""
        var used = 0
        for character in text {
            let width = String(character).utf8.count
            guard used + width <= limit else { break }
            result.append(character)
            used += width
        }
        return result
    }
}

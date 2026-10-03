import Foundation

/// Prepared off the main thread. A page bounds text layout by both bytes and line breaks;
/// even a single enormous API line cannot turn into an enormous SwiftUI Text.
nonisolated struct DiagnosticPreview: Sendable {
    static let pageByteLimit = 4096
    static let pageLineLimit = 80
    let pages: [String]

    init(text: String) {
        let scalars = text.unicodeScalars
        var start = scalars.endIndex
        var end = start
        var bytes = 0
        var lines = 0
        var newestFirst: [String] = []
        // Work backwards so the initial, newest page is full even for uneven report sizes.
        while start > scalars.startIndex {
            let previous = scalars.index(before: start)
            let scalar = scalars[previous]
            let size = scalar.utf8.count
            if bytes + size > Self.pageByteLimit || lines >= Self.pageLineLimit {
                newestFirst.append(String(scalars[start..<end]))
                end = start
                bytes = 0
                lines = 0
            }
            start = previous
            bytes += size
            if scalar == "\n" || scalar == "\r" { lines += 1 }
        }
        if start < end { newestFirst.append(String(scalars[start..<end])) }
        pages = newestFirst.isEmpty ? [""] : Array(newestFirst.reversed())
    }
}

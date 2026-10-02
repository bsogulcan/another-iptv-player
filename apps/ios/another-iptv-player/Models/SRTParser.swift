import Foundation

struct SubtitleEntry: Identifiable, Equatable {
    let id = UUID()
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

/// Blok bazlı SRT ayrıştırıcı. Eski Scanner sürümü varsayılan whitespace atlama yüzünden
/// bloklar arası boş satırları yutuyor ve TÜM dosya tek girdiye yapışıyordu.
final class SRTParser {
    func parse(content: String) -> [SubtitleEntry] {
        // BOM at, satır sonlarını normalize etmeden Character.isNewline ile böl.
        var text = Substring(content)
        if text.hasPrefix("\u{FEFF}") { text = text.dropFirst() }
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })

        var entries: [SubtitleEntry] = []
        var i = 0
        let n = lines.count
        while i < n {
            // Boş satırları atla.
            while i < n, lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
            guard i < n else { break }

            // Opsiyonel index satırı.
            if Int(lines[i].trimmingCharacters(in: .whitespaces)) != nil { i += 1 }
            guard i < n else { break }

            // Zaman satırı: 00:00:01,000 --> 00:00:04,000
            let timeLine = lines[i].trimmingCharacters(in: .whitespaces)
            let times = timeLine.components(separatedBy: " --> ")
            guard times.count == 2,
                  let start = parseTime(times[0]),
                  let end = parseTime(times[1]) else {
                // Bozuk blok: sonraki boş satıra kadar atla.
                while i < n, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
                continue
            }
            i += 1

            // Metin satırları: boş satıra veya dosya sonuna kadar.
            var textLines: [String] = []
            while i < n {
                let line = String(lines[i])
                if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
                // A line that was nothing but markup has no text left; keeping it would
                // put an empty row into the cue.
                let stripped = stripBasicTags(line)
                if !stripped.trimmingCharacters(in: .whitespaces).isEmpty { textLines.append(stripped) }
                i += 1
            }

            if !textLines.isEmpty {
                entries.append(SubtitleEntry(startTime: start, endTime: end, text: textLines.joined(separator: "\n")))
            }
        }

        return entries
    }

    /// SRT'de yaygın süsleme tag'leri (<i>, <b>, <u>, <font ...>) kaldırılır.
    /// The cues parsed here become plain WebVTT text on the AirPlay target, which would
    /// show `{\an8}`-style override blocks literally as well, so those go too.
    private func stripBasicTags(_ line: String) -> String {
        Self.strippingOverrideBlocks(Self.strippingMarkupTags(line))
    }

    private func parseTime(_ timeString: String) -> TimeInterval? {
        let components = timeString.replacingOccurrences(of: ",", with: ".").components(separatedBy: ":")
        guard components.count == 3,
              let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]) else { return nil }

        return (hours * 3600) + (minutes * 60) + seconds
    }
}

// MARK: - Markup

extension SRTParser {
    /// `<i>`, `<b>`, `<u>`, `<s>`, `<font ...>`, WebVTT's `<c.class>`, `<v Speaker>`,
    /// `<lang xx>`, `<ruby>`, `<rt>` and inline `<00:01:02.000>` timestamps. Anything else
    /// in angle brackets is left alone: it is more likely dialogue than markup.
    private nonisolated static let markupTagPattern =
        #"(?:</?(?:i|b|u|s|font|c|v|lang|ruby|rt)(?:[ \t.][^<>\n]*)?>|<\d{1,2}:\d{2}(?::\d{2})?\.\d{3}>)"#

    /// Removes the tags no subtitle renderer in the app interprets, which would therefore
    /// be shown as text. Works on a single line or on a whole file.
    nonisolated static func strippingMarkupTags(_ text: String) -> String {
        guard text.contains("<") else { return text }
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]
        return text
            // A line holding nothing but tags goes away together with its line break:
            // left behind as a blank line it would end the cue early.
            .replacingOccurrences(
                of: #"(?m)^[ \t]*(?:\#(markupTagPattern)[ \t]*)+(?:\r?\n|\z)"#,
                with: "",
                options: options
            )
            .replacingOccurrences(of: markupTagPattern, with: "", options: options)
    }

    /// Removes ASS-style override blocks (`{\an8}`, `{\i1}`, `{\pos(10,20)}`) and the
    /// SubRip shorthand `{i}` / `{/i}`. Other text in braces is kept.
    nonisolated static func strippingOverrideBlocks(_ text: String) -> String {
        guard text.contains("{") else { return text }
        return text.replacingOccurrences(
            of: #"\{(?:\\[^{}\n]*|/?[ibus])\}"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}

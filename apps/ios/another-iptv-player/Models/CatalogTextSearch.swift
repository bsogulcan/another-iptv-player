import Foundation

/// GRDB `localized_*` SQL fonksiyonlarıyla aynı mantık (Persistence.swift).
enum CatalogTextSearch {
    private static let locale = Locale(identifier: "tr_TR")
    private static let alphanumericSet = CharacterSet.alphanumerics

    private static func normalize(_ s: String) -> String {
        let lowercase = s.lowercased(with: locale)
        let folded = lowercase.folding(options: .diacriticInsensitive, locale: locale)
        return folded.components(separatedBy: alphanumericSet.inverted).joined()
    }

    static func matches(search: String, text: String) -> Bool {
        let normalizedText = normalize(text)
        let queryWords = search.lowercased(with: locale)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        if queryWords.isEmpty { return true }
        return queryWords.allSatisfy { word in
            normalizedText.contains(normalize(word))
        }
    }

    static func equals(search: String, text: String) -> Bool {
        normalize(text) == normalize(search)
    }

    static func startsWith(search: String, text: String) -> Bool {
        normalize(text).hasPrefix(normalize(search))
    }

    static func sortLiveByRelevance(_ items: [LiveStreamWithCategory], search: String) -> [LiveStreamWithCategory] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return items.sorted { $0.stream.sortIndex < $1.stream.sortIndex }
        }
        return items.sorted { a, b in
            let n1 = a.stream.name, n2 = b.stream.name
            let e1 = equals(search: trimmed, text: n1), e2 = equals(search: trimmed, text: n2)
            if e1 != e2 { return e1 && !e2 }
            let s1 = startsWith(search: trimmed, text: n1), s2 = startsWith(search: trimmed, text: n2)
            if s1 != s2 { return s1 && !s2 }
            return n1.localizedCaseInsensitiveCompare(n2) == .orderedAscending
        }
    }

    static func sortVODByRelevance(_ items: [VODWithCategory], search: String) -> [VODWithCategory] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return items.sorted { $0.stream.sortIndex < $1.stream.sortIndex }
        }
        return items.sorted { a, b in
            let n1 = a.stream.name, n2 = b.stream.name
            let e1 = equals(search: trimmed, text: n1), e2 = equals(search: trimmed, text: n2)
            if e1 != e2 { return e1 && !e2 }
            let s1 = startsWith(search: trimmed, text: n1), s2 = startsWith(search: trimmed, text: n2)
            if s1 != s2 { return s1 && !s2 }
            return n1.localizedCaseInsensitiveCompare(n2) == .orderedAscending
        }
    }

    static func sortSeriesByRelevance(_ items: [SeriesWithCategory], search: String) -> [SeriesWithCategory] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return items.sorted { $0.series.sortIndex < $1.series.sortIndex }
        }
        return items.sorted { a, b in
            let n1 = a.series.name, n2 = b.series.name
            let e1 = equals(search: trimmed, text: n1), e2 = equals(search: trimmed, text: n2)
            if e1 != e2 { return e1 && !e2 }
            let s1 = startsWith(search: trimmed, text: n1), s2 = startsWith(search: trimmed, text: n2)
            if s1 != s2 { return s1 && !s2 }
            return n1.localizedCaseInsensitiveCompare(n2) == .orderedAscending
        }
    }
}

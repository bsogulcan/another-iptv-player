import Foundation

/// The app's one text matcher: the in-memory searches and the GRDB `localized_*` SQL
/// functions (Persistence.swift) fold and match through here, so they cannot drift apart.
/// Pure stateless namespace — used from detached filtering tasks, so it must not be MainActor.
nonisolated enum CatalogTextSearch {
    private static let foldLocale = Locale(identifier: "en_US_POSIX")
    private static let alphanumericSet = CharacterSet.alphanumerics

    // MARK: - Folding

    /// Search key of a name or a query: case, accents, width, punctuation and spaces are
    /// folded away ("Spider-Man" → "spiderman", "ＦＯＸ ４Ｋ" → "fox4k").
    ///
    /// Locale-invariant fold: tr_TR lowercasing maps "I"→"ı" and breaks queries like
    /// "history" against ALL-CAPS catalog names ("HISTORY HD" → "hıstory hd").
    /// The extra "ı"→"i" pass keeps Turkish dotless-ı queries matching ALL-CAPS
    /// Turkish text ("IŞIK" and "ışık" both normalize to "isik").
    static func normalize(_ s: String) -> String {
        withASCIIKey(s) { String(decoding: $0, as: UTF8.self) } ?? foldUnicode(s)
    }

    /// The general path of `normalize`. Internal only so the tests can pin the ASCII
    /// fast path against it; call `normalize`.
    static func foldUnicode(_ s: String) -> String {
        let folded = s.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: foldLocale
        )
        var key = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars {
            switch scalar.value {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
                key.append(scalar)
            case 0..<0x80:
                continue
            case 0x0131:
                key.append("i")
            // Arabic is typed without vowel marks, hamza or tatweel far more often than it
            // is stored with them, and Persian keyboards produce their own yeh and kaf.
            case 0x064B...0x065F, 0x0670, 0x0640:
                continue
            case 0x0622, 0x0623, 0x0625, 0x0671:
                key.append("\u{0627}")
            case 0x0649, 0x06CC:
                key.append("\u{064A}")
            case 0x0629:
                key.append("\u{0647}")
            case 0x06A9:
                key.append("\u{0643}")
            default:
                if alphanumericSet.contains(scalar) { key.append(scalar) }
            }
        }
        return String(key)
    }

    /// Hands `body` the key of a pure-ASCII text without building a String: lower-cased
    /// letters and digits, which is exactly what `foldUnicode` returns for ASCII. Most
    /// catalog names are ASCII, and Foundation folding is the expensive part of a scan.
    /// Returns nil for any other text; the caller then takes the general path.
    fileprivate static func withASCIIKey<R>(_ text: String, _ body: (UnsafeBufferPointer<UInt8>) -> R) -> R? {
        let result: R?? = text.utf8.withContiguousStorageIfAvailable { source -> R? in
            withUnsafeTemporaryAllocation(of: UInt8.self, capacity: max(source.count, 1)) { key -> R? in
                var count = 0
                for byte in source {
                    switch byte {
                    case 0x30...0x39, 0x61...0x7A:
                        key.initializeElement(at: count, to: byte)
                        count += 1
                    case 0x41...0x5A:
                        key.initializeElement(at: count, to: byte | 0x20)
                        count += 1
                    case 0x80...:
                        return nil
                    default:
                        break
                    }
                }
                return body(UnsafeBufferPointer(start: key.baseAddress, count: count))
            }
        }
        return result ?? nil
    }

    // MARK: - Prepared query

    /// A search prepared once, to be tested against many names. Building it per name (as
    /// `matches(search:text:)` does) folds the query again for every row.
    nonisolated struct Query: Sendable {
        /// Folded words. A token of punctuation only ("-", "&") folds to nothing and is
        /// dropped, so "tom & jerry" searches for "tom" and "jerry".
        private let words: [String]
        private let wordBytes: [[UInt8]]
        /// The whole search as one key ("fox tv" → "foxtv"); the ranking tiers compare with it.
        private let whole: String
        private let wholeBytes: [UInt8]
        /// The search had no text at all, as opposed to text without a letter or digit.
        fileprivate let isBlank: Bool

        init(_ search: String) {
            let tokens = search.split(whereSeparator: \.isWhitespace)
            let words = tokens
                .map { CatalogTextSearch.normalize(String($0)) }
                .filter { !$0.isEmpty }
            self.words = words
            self.wordBytes = words.map { Array($0.utf8) }
            self.whole = CatalogTextSearch.normalize(search)
            self.wholeBytes = Array(whole.utf8)
            self.isBlank = tokens.isEmpty
        }

        /// No searchable words: the search is blank or has no letter or digit ("--").
        var isEmpty: Bool { words.isEmpty }

        /// Every word is contained in the folded text. Without words, a blank search
        /// matches everything and a punctuation-only one matches nothing; the latter must
        /// not list the whole catalog as if it were a hit.
        func matches(_ text: String) -> Bool {
            guard !words.isEmpty else { return isBlank }
            if let hit = CatalogTextSearch.withASCIIKey(text, { containsAllWords($0) }) { return hit }
            let key = CatalogTextSearch.foldUnicode(text)
            return words.allSatisfy { key.contains($0) }
        }

        /// Relevance of a name: 0 when it is the query, 1 when it starts with it, 2 otherwise.
        /// With `filtering`, nil when the name does not match at all.
        fileprivate func tier(of text: String, filtering: Bool) -> UInt8? {
            let ascii = CatalogTextSearch.withASCIIKey(text) { key -> UInt8? in
                if filtering, !containsAllWords(key) { return nil }
                guard key.count >= wholeBytes.count,
                      wholeBytes.isEmpty || memcmp(key.baseAddress, wholeBytes, wholeBytes.count) == 0
                else { return 2 }
                return key.count == wholeBytes.count ? 0 : 1
            }
            if let ascii { return ascii }
            let key = CatalogTextSearch.foldUnicode(text)
            if filtering, !words.allSatisfy({ key.contains($0) }) { return nil }
            return key == whole ? 0 : key.hasPrefix(whole) ? 1 : 2
        }

        /// Byte search is enough here: an ASCII key can only contain an ASCII word, and a
        /// word with any other byte fails to match on its own.
        private func containsAllWords(_ key: UnsafeBufferPointer<UInt8>) -> Bool {
            for word in wordBytes {
                guard word.count <= key.count,
                      memmem(key.baseAddress, key.count, word, word.count) != nil
                else { return false }
            }
            return true
        }
    }

    // MARK: - Matching

    static func matches(search: String, text: String) -> Bool {
        Query(search).matches(text)
    }

    static func equals(search: String, text: String) -> Bool {
        normalize(text) == normalize(search)
    }

    static func startsWith(search: String, text: String) -> Bool {
        normalize(text).hasPrefix(normalize(search))
    }

    // MARK: - Ranking

    /// Filters and ranks in one pass over `items`, folding each name once: exact matches
    /// first, then names that start with the query, then the rest, alphabetical inside
    /// each tier and stable for equal names.
    ///
    /// A blank search has nothing to rank by and returns `items` as they are.
    /// Meant to run inside `detached`: it gives up and returns [] once the task is
    /// cancelled, so a query superseded by the next keystroke stops holding a core.
    static func rankedFilter<T>(_ items: [T], search: String, name: (T) -> String) -> [T] {
        var comparisons = 0
        return rankedFilter(items, search: search, sortComparisons: &comparisons, name: name)
    }

    /// `rankedFilter`, also reporting how many pairs its sort compared. Exists only so the
    /// tests can tell a sort that was abandoned from one that ran to the end and had its
    /// result thrown away; both return []. Call the variant above.
    static func rankedFilter<T>(
        _ items: [T],
        search: String,
        sortComparisons: inout Int,
        name: (T) -> String
    ) -> [T] {
        sortComparisons = 0
        if Task.isCancelled { return [] }
        let query = Query(search)
        if query.isEmpty { return query.isBlank ? items : [] }
        return ranked(items, query: query, filtering: true, cancellable: true, comparisons: &sortComparisons, name: name)
    }

    static func sortLiveByRelevance(_ items: [LiveStreamWithCategory], search: String) -> [LiveStreamWithCategory] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return items.sorted { $0.stream.sortIndex < $1.stream.sortIndex }
        }
        var comparisons = 0
        return ranked(items, query: Query(trimmed), filtering: false, cancellable: false, comparisons: &comparisons) { $0.stream.name }
    }

    static func sortVODByRelevance(_ items: [VODWithCategory], search: String) -> [VODWithCategory] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return items.sorted { $0.stream.sortIndex < $1.stream.sortIndex }
        }
        var comparisons = 0
        return ranked(items, query: Query(trimmed), filtering: false, cancellable: false, comparisons: &comparisons) { $0.stream.name }
    }

    static func sortSeriesByRelevance(_ items: [SeriesWithCategory], search: String) -> [SeriesWithCategory] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return items.sorted { $0.series.sortIndex < $1.series.sortIndex }
        }
        var comparisons = 0
        return ranked(items, query: Query(trimmed), filtering: false, cancellable: false, comparisons: &comparisons) { $0.series.name }
    }

    /// How many names are scanned, and how many pairs compared, between two looks at the
    /// task's cancellation flag.
    private static let cancellationStride = 2048

    /// The tier of every name is computed once, before sorting. Folding inside the
    /// comparator costs several folds per comparison, which made a broad query take
    /// seconds on a large catalog.
    private static func ranked<T>(
        _ items: [T],
        query: Query,
        filtering: Bool,
        cancellable: Bool,
        comparisons: inout Int,
        name: (T) -> String
    ) -> [T] {
        var hits: [(tier: UInt8, offset: Int, name: String)] = []
        if !filtering { hits.reserveCapacity(items.count) }
        for (offset, item) in items.enumerated() {
            if cancellable, offset % cancellationStride == 0, Task.isCancelled { return [] }
            let itemName = name(item)
            guard let tier = query.tier(of: itemName, filtering: filtering) else { continue }
            hits.append((tier, offset, itemName))
        }

        do {
            try hits.sort { a, b in
                comparisons += 1
                // A broad query sorts most of the catalog; throwing is the only way out of
                // a sort that nobody is waiting for any more.
                if cancellable, comparisons % cancellationStride == 0, Task.isCancelled {
                    throw CancellationError()
                }
                if a.tier != b.tier { return a.tier < b.tier }
                switch a.name.localizedCaseInsensitiveCompare(b.name) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                // Names the collation cannot tell apart keep the caller's order.
                case .orderedSame: return a.offset < b.offset
                }
            }
        } catch {
            return []
        }
        if cancellable, Task.isCancelled { return [] }
        return hits.map { items[$0.offset] }
    }

    // MARK: - Off the main actor

    /// Runs `work` in a detached task that is cancelled together with the caller.
    /// Awaiting the value of a plain `Task.detached` does not forward cancellation, so
    /// every superseded search would scan and sort the catalog to the end.
    static func detached<T: Sendable>(
        priority: TaskPriority = .userInitiated,
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        let task = Task.detached(priority: priority) { work() }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// The `localized_*` SQL functions answer the database-backed searches; they have to
/// agree with the in-memory matcher, or the same query finds different rows per screen.
@Suite("CatalogTextSearch SQL functions")
struct CatalogTextSearchSQLTests {

    private func evaluate(_ function: String, text: String, query: String, in database: AppDatabase) async throws -> Bool? {
        try await database.read { db in
            try Bool.fetchOne(db, sql: "SELECT \(function)(?, ?)", arguments: [text, query])
        }
    }

    private let pairs: [(text: String, query: String)] = [
        ("FOX TV", "fox"),
        ("FOX TV", "fox tv"),
        ("FOX TV", "tv fox"),
        ("FOX-TV", "fox tv"),
        ("FİLM 4K", "film"),
        ("FILM 4K", "film"),
        ("HISTORY HD", "history"),
        ("IŞIK TV", "isik"),
        ("Amélie", "amelie"),
        ("Spider-Man", "spiderman"),
        ("Tom & Jerry", "tom & jerry"),
        ("\u{0623}\u{062D}\u{0645}\u{062F}", "\u{0627}\u{062D}\u{0645}\u{062F}"),
        ("\u{0645}\u{064F}\u{062D}\u{064E}\u{0645}\u{0651}\u{064E}\u{062F}", "\u{0645}\u{062D}\u{0645}\u{062F}"),
        ("ＦＯＸ ４Ｋ", "fox 4k"),
        ("ＡＢＣ", "abc"),
        ("Sports HD TV", "sports zone"),
        ("News Channel", "sports"),
        ("Sports Tonight", "sports"),
        ("Today Sports", "sports"),
        ("Sports", "sports"),
        ("", "sports"),
    ]

    @Test
    func containsAgreesWithTheInMemoryMatcher() async throws {
        let database = AppDatabase.empty()
        for (text, query) in pairs {
            let expected = CatalogTextSearch.Query(query).matches(text)
            let actual = try await evaluate("localized_contains", text: text, query: query, in: database)
            #expect(actual == expected, "\(query) in \(text)")
        }
    }

    @Test
    func equalsAndStartsWithAgreeWithTheInMemoryMatcher() async throws {
        let database = AppDatabase.empty()
        for (text, query) in pairs {
            let equals = try await evaluate("localized_equals", text: text, query: query, in: database)
            #expect(equals == CatalogTextSearch.equals(search: query, text: text), "\(query) equals \(text)")
            let startsWith = try await evaluate("localized_starts_with", text: text, query: query, in: database)
            #expect(startsWith == CatalogTextSearch.startsWith(search: query, text: text), "\(query) starts \(text)")
        }
    }

    @Test
    func sqlFunctionsUseTheSharedFold() async throws {
        let database = AppDatabase.empty()
        let hamza = "\u{0623}\u{062D}\u{0645}\u{062F}"   // أحمد
        let plain = "\u{0627}\u{062D}\u{0645}\u{062F}"   // احمد
        let cases: [(function: String, text: String, query: String, expected: Bool)] = [
            ("localized_contains", hamza, plain, true),
            ("localized_equals", hamza, plain, true),
            ("localized_starts_with", "\(hamza) TV", plain, true),
            ("localized_contains", "ＦＯＸ ４Ｋ", "fox 4k", true),
            ("localized_equals", "FOX-TV", "fox tv", true),
            ("localized_starts_with", "Sports TV", "tv", false),
        ]
        for (function, text, query, expected) in cases {
            let actual = try await evaluate(function, text: text, query: query, in: database)
            #expect(actual == expected, "\(function)(\(text), \(query))")
        }
    }

    @Test
    func containsSelectsNothingForAQueryWithoutWords() async throws {
        // In SQL the predicate is only added for a typed query, and a query without any
        // letter or digit must not select the whole table.
        let database = AppDatabase.empty()
        for query in ["", "   ", "--", "&"] {
            let selected = try await evaluate("localized_contains", text: "FOX TV", query: query, in: database)
            #expect(selected == false, "query \"\(query)\"")
        }
    }

    @Test
    func changingTheQueryBetweenRowsIsNotServedFromTheCache() async throws {
        // The functions remember the last prepared query; alternating queries must still
        // be answered for the query of the call.
        let database = AppDatabase.empty()
        let flags = try await database.read { db in
            try Row.fetchOne(db, sql: """
                SELECT localized_contains('FOX TV', 'fox') AS a,
                       localized_contains('FOX TV', 'cnn') AS b,
                       localized_equals('FOX TV', 'fox tv') AS c,
                       localized_equals('FOX TV', 'fox') AS d,
                       localized_starts_with('FOX TV', 'fox') AS e,
                       localized_starts_with('FOX TV', 'tv') AS f,
                       localized_contains('FOX TV', 'fox') AS g
                """).map { row in ["a", "b", "c", "d", "e", "f", "g"].map { row[$0] as Bool? } }
        }
        #expect(flags == [true, false, true, false, true, false, true])
    }
}

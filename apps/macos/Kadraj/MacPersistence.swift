import Foundation
import GRDB

/// The `localized_*` functions run once per row (100k+ rows) with the same query argument,
/// so the query is prepared when it changes instead of once per row.
/// `nonisolated`: runs inside GRDB's DatabaseFunction callbacks on DB queues (a
/// DatabasePool serves concurrent readers), so all state is guarded by the lock.
private nonisolated final class PreparedQueryCache: @unchecked Sendable {
  private let lock = NSLock()
  private var lastQuery: String?
  private var lastPrepared = CatalogTextSearch.Query("")
  private var lastKey = ""

  /// The query as words (for `localized_contains`) and as one folded key (for the
  /// equality and prefix checks of the relevance ordering).
  func entry(for query: String) -> (prepared: CatalogTextSearch.Query, key: String) {
    lock.lock()
    defer { lock.unlock() }
    if lastQuery != query {
      lastPrepared = CatalogTextSearch.Query(query)
      lastKey = CatalogTextSearch.normalize(query)
      lastQuery = query
    }
    return (lastPrepared, lastKey)
  }
}

nonisolated extension AppDatabase {
  static let shared = makeShared()

  /// True: disk DB açılamadı, oturum bellek-içi çalışıyor — bu oturumda yazılan hiçbir
  /// veri kalıcı olmaz. Root view kullanıcıyı bir kez uyarır.
  nonisolated(unsafe) private(set) static var isEphemeral = false
  /// True: bozuk DB dosyası kenara alınıp diskte sıfırdan oluşturuldu — veriler
  /// sıfırlandı ama bundan sonrası kalıcı. Root view kullanıcıyı bir kez uyarır.
  nonisolated(unsafe) private(set) static var didResetCorruptStore = false

  private static func databaseFileURL() throws -> URL {
    let fileManager = FileManager.default
    let appSupportURL = try fileManager.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)

    // Use Bundle Identifier for a unique subfolder (crucial on macOS)
    let bundleID = Bundle.main.bundleIdentifier ?? "com.ogosko.another-iptv-player"
    let appDirectoryURL = appSupportURL.appendingPathComponent(bundleID, isDirectory: true)
    #if DEBUG
      let isFixture = ProcessInfo.processInfo.arguments.contains("-UITests")
      let folder = isFixture ? "UITestDatabase" : "Database"
    #else
      let folder = "Database"
    #endif
    let directoryURL = appDirectoryURL.appendingPathComponent(folder, isDirectory: true)

    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL.appendingPathComponent("db.sqlite")
  }

  private static func makeShared() -> AppDatabase {
    #if DEBUG
      if NSClassFromString("XCTestCase") != nil { return empty() }
    #endif
    do {
      // Eski db.sqlite + çoklu migration geçmişi yerine tek şema dosyası (yerel veri sıfırlanır).
      let databaseURL = try databaseFileURL()
      let dbPool = try DatabasePool(path: databaseURL.path, configuration: databaseConfiguration())
      return try AppDatabase(dbPool)
    } catch {
      Log.error(
        "Persistence", "DB pool init failed (disk/sandbox/corrupt?): \(error.localizedDescription)")

      // Keep the existing Mac store intact if it cannot be opened or migrated.
      do {
        let queue = try DatabaseQueue(configuration: databaseConfiguration())
        Log.error(
          "Persistence", "in-memory DB fallback aktif — kullanıcı verisi bu oturumda kaybolacak")
        isEphemeral = true
        return try AppDatabase(queue)
      } catch {
        // Bellekte bile DB açılamıyorsa cihaz kritik durumda; net bir mesajla son çare.
        Log.error("Persistence", "in-memory DB fallback başarısız: \(error.localizedDescription)")
        fatalError("DB tamamen başarısız: \(error.localizedDescription)")
      }
    }
  }

  static func empty() -> AppDatabase {
    let dbQueue = try! DatabaseQueue(configuration: databaseConfiguration())
    return try! AppDatabase(dbQueue)
  }

  private static func databaseConfiguration() -> Configuration {
    var config = Configuration()
    // A detail screen reads its row while it is being pushed. A reader has to be
    // free for that even when the catalog load, the guide index and a search each
    // hold one, so the pool is a little larger than GRDB's default of five.
    config.maximumReaderCount = 8
    config.prepareDatabase { db in
      db.add(collation: DatabaseCollation("mac_title") { $0.localizedCaseInsensitiveCompare($1) })
      db.add(
        function: DatabaseFunction("mac_adult_name", argumentCount: 1, pure: true) { values in
          AdultContentFilter.isAdultCategoryName(String.fromDatabaseValue(values[0]) ?? "")
        })
      db.add(
        function: DatabaseFunction("mac_live_url", argumentCount: 2, pure: true) { values in
          guard let raw = String.fromDatabaseValue(values[0]),
                let url = M3UParser.sanitizedURL(from: raw) else { return false }
          return M3UStreamClassifier.classify(url: url, groupTitle: String.fromDatabaseValue(values[1])).isLive
        })
      db.add(
        function: DatabaseFunction("mac_provider_timestamp", argumentCount: 1, pure: true) { values in
          String.fromDatabaseValue(values[0]).flatMap(Int.init)
        })
      db.add(
        function: DatabaseFunction("mac_rating", argumentCount: 1, pure: true) { values in
          CatalogRatingValue.parse(String.fromDatabaseValue(values[0]))
        })
      db.add(
        function: DatabaseFunction("mac_file_type", argumentCount: 1, pure: true) { values in
          VODFileType.normalized(String.fromDatabaseValue(values[0]))
        })
      db.add(
        function: DatabaseFunction("mac_has_genre", argumentCount: 2, pure: true) { values in
          guard let genre = String.fromDatabaseValue(values[1]) else { return false }
          return SeriesGenre.split(String.fromDatabaseValue(values[0])).contains(genre)
        })
      // Folding and matching live in CatalogTextSearch, shared with the in-memory
      // searches, so a query selects the same rows whichever path answers it.
      let queryCache = PreparedQueryCache()
      let containsFunc = DatabaseFunction("localized_contains", argumentCount: 2, pure: true) {
        (dbValues: [DatabaseValue]) -> DatabaseValueConvertible? in
        guard dbValues.count == 2,
          let text = String.fromDatabaseValue(dbValues[0]),
          let query = String.fromDatabaseValue(dbValues[1])
        else { return nil }

        let prepared = queryCache.entry(for: query).prepared
        // As a SQL predicate an empty query selects no row; `Query` alone would
        // let a blank one match everything.
        if prepared.isEmpty { return false }
        return prepared.matches(text)
      }
      db.add(function: containsFunc)

      let startsWithFunc = DatabaseFunction("localized_starts_with", argumentCount: 2, pure: true) {
        (dbValues: [DatabaseValue]) -> DatabaseValueConvertible? in
        guard dbValues.count == 2,
          let text = String.fromDatabaseValue(dbValues[0]),
          let query = String.fromDatabaseValue(dbValues[1])
        else { return nil }
        return CatalogTextSearch.normalize(text).hasPrefix(queryCache.entry(for: query).key)
      }
      db.add(function: startsWithFunc)

      let equalsFunc = DatabaseFunction("localized_equals", argumentCount: 2, pure: true) {
        (dbValues: [DatabaseValue]) -> DatabaseValueConvertible? in
        guard dbValues.count == 2,
          let text = String.fromDatabaseValue(dbValues[0]),
          let query = String.fromDatabaseValue(dbValues[1])
        else { return nil }
        return CatalogTextSearch.normalize(text) == queryCache.entry(for: query).key
      }
      db.add(function: equalsFunc)
    }
    return config
  }
}

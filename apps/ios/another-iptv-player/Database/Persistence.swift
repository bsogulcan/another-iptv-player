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
        let appSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)

        // Use Bundle Identifier for a unique subfolder (crucial on macOS)
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ogosko.another-iptv-player"
        let appDirectoryURL = appSupportURL.appendingPathComponent(bundleID, isDirectory: true)
        let directoryURL = appDirectoryURL.appendingPathComponent("Database", isDirectory: true)

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("db.sqlite")
    }

    private static func makeShared() -> AppDatabase {
        do {
            // Eski db.sqlite + çoklu migration geçmişi yerine tek şema dosyası (yerel veri sıfırlanır).
            let databaseURL = try databaseFileURL()
            let dbPool = try DatabasePool(path: databaseURL.path, configuration: databaseConfiguration())
            return try AppDatabase(dbPool)
        } catch {
            Log.error("Persistence", "DB pool init failed (disk/sandbox/corrupt?): \(error.localizedDescription)")

            // Bozuk dosya olasılığı: dosyayı kenara alıp diskte SIFIRDAN dene. Bellek-içi
            // fallback'ten iyidir — veri sıfırlanır ama bundan sonrası kalıcı olur; eski
            // (geçici açılamayan) dosya .corrupt olarak saklanır.
            if let databaseURL = try? databaseFileURL() {
                let fm = FileManager.default
                if fm.fileExists(atPath: databaseURL.path) {
                    let backup = databaseURL.deletingPathExtension().appendingPathExtension("corrupt.sqlite")
                    try? fm.removeItem(at: backup)
                    try? fm.moveItem(at: databaseURL, to: backup)
                    try? fm.removeItem(at: URL(fileURLWithPath: databaseURL.path + "-wal"))
                    try? fm.removeItem(at: URL(fileURLWithPath: databaseURL.path + "-shm"))
                    if let pool = try? DatabasePool(path: databaseURL.path, configuration: databaseConfiguration()),
                       let db = try? AppDatabase(pool) {
                        didResetCorruptStore = true
                        Log.error("Persistence", "bozuk DB kenara alındı (db.corrupt.sqlite), yeni disk DB oluşturuldu")
                        return db
                    }
                }
            }

            // Disk dolu, sandbox sorunu → app'i öldürmek yerine in-memory fallback.
            // Veri kaybolur ama uygulama açık kalır; root view kullanıcıyı uyarır.
            do {
                let queue = try DatabaseQueue(configuration: databaseConfiguration())
                Log.error("Persistence", "in-memory DB fallback aktif — kullanıcı verisi bu oturumda kaybolacak")
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
            // Folding and matching live in CatalogTextSearch, shared with the in-memory
            // searches, so a query selects the same rows whichever path answers it.
            let queryCache = PreparedQueryCache()
            let containsFunc = DatabaseFunction("localized_contains", argumentCount: 2, pure: true) { (dbValues: [DatabaseValue]) -> DatabaseValueConvertible? in
                guard dbValues.count == 2,
                      let text = String.fromDatabaseValue(dbValues[0]),
                      let query = String.fromDatabaseValue(dbValues[1]) else { return nil }

                let prepared = queryCache.entry(for: query).prepared
                // As a SQL predicate an empty query selects no row; `Query` alone would
                // let a blank one match everything.
                if prepared.isEmpty { return false }
                return prepared.matches(text)
            }
            db.add(function: containsFunc)
            
            let startsWithFunc = DatabaseFunction("localized_starts_with", argumentCount: 2, pure: true) { (dbValues: [DatabaseValue]) -> DatabaseValueConvertible? in
                guard dbValues.count == 2,
                      let text = String.fromDatabaseValue(dbValues[0]),
                      let query = String.fromDatabaseValue(dbValues[1]) else { return nil }
                return CatalogTextSearch.normalize(text).hasPrefix(queryCache.entry(for: query).key)
            }
            db.add(function: startsWithFunc)
            
            let equalsFunc = DatabaseFunction("localized_equals", argumentCount: 2, pure: true) { (dbValues: [DatabaseValue]) -> DatabaseValueConvertible? in
                guard dbValues.count == 2,
                      let text = String.fromDatabaseValue(dbValues[0]),
                      let query = String.fromDatabaseValue(dbValues[1]) else { return nil }
                return CatalogTextSearch.normalize(text) == queryCache.entry(for: query).key
            }
            db.add(function: equalsFunc)
        }
        return config
    }
}

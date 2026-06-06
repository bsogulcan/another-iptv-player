import Foundation
import GRDB

extension AppDatabase {
    static let shared = makeShared()
    
    private static func makeShared() -> AppDatabase {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)

            // Use Bundle Identifier for a unique subfolder (crucial on macOS)
            let bundleID = Bundle.main.bundleIdentifier ?? "com.ogosko.another-iptv-player"
            let appDirectoryURL = appSupportURL.appendingPathComponent(bundleID, isDirectory: true)
            let directoryURL = appDirectoryURL.appendingPathComponent("Database", isDirectory: true)

            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            // Eski db.sqlite + çoklu migration geçmişi yerine tek şema dosyası (yerel veri sıfırlanır).
            let databaseURL = directoryURL.appendingPathComponent("db.sqlite")
            let dbPool = try DatabasePool(path: databaseURL.path, configuration: databaseConfiguration())

            return try AppDatabase(dbPool)
        } catch {
            Log.error("Persistence", "DB pool init failed (disk/sandbox/corrupt?): \(error.localizedDescription)")
            // Disk dolu, sandbox sorunu veya bozuk DB → app'i öldürmek yerine in-memory fallback.
            // Veri kaybolur ama uygulama açık kalır; kullanıcı en azından oynatıcıya ulaşabilir.
            do {
                let queue = try DatabaseQueue(configuration: databaseConfiguration())
                Log.error("Persistence", "in-memory DB fallback aktif — kullanıcı verisi bu oturumda kaybolacak")
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
        config.prepareDatabase { db in
            let locale = Locale(identifier: "tr_TR")
            let alphanumericSet = CharacterSet.alphanumerics
            
            let normalize: @Sendable (String) -> String = { s in
                let lowercase = s.lowercased(with: locale)
                let folded = lowercase.folding(options: .diacriticInsensitive, locale: locale)
                return folded.components(separatedBy: alphanumericSet.inverted).joined()
            }
            
            let containsFunc = DatabaseFunction("localized_contains", argumentCount: 2, pure: true) { (dbValues: [DatabaseValue]) -> DatabaseValueConvertible? in
                guard dbValues.count == 2,
                      let text = String.fromDatabaseValue(dbValues[0]),
                      let query = String.fromDatabaseValue(dbValues[1]) else { return nil }
                
                let normalizedText = normalize(text)
                let queryWords = query.lowercased(with: locale)
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                
                if queryWords.isEmpty { return false }
                
                // Every word in the query must be found in the normalized text
                return queryWords.allSatisfy { word in
                    normalizedText.contains(normalize(word))
                }
            }
            db.add(function: containsFunc)
            
            let startsWithFunc = DatabaseFunction("localized_starts_with", argumentCount: 2, pure: true) { (dbValues: [DatabaseValue]) -> DatabaseValueConvertible? in
                guard dbValues.count == 2,
                      let text = String.fromDatabaseValue(dbValues[0]),
                      let query = String.fromDatabaseValue(dbValues[1]) else { return nil }
                return normalize(text).hasPrefix(normalize(query))
            }
            db.add(function: startsWithFunc)
            
            let equalsFunc = DatabaseFunction("localized_equals", argumentCount: 2, pure: true) { (dbValues: [DatabaseValue]) -> DatabaseValueConvertible? in
                guard dbValues.count == 2,
                      let text = String.fromDatabaseValue(dbValues[0]),
                      let query = String.fromDatabaseValue(dbValues[1]) else { return nil }
                return normalize(text) == normalize(query)
            }
            db.add(function: equalsFunc)
        }
        return config
    }
}

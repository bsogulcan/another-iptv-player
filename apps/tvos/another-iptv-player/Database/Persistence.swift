import Foundation
import GRDB

extension AppDatabase {
    static let shared = makeShared()
    
    private static func makeShared() -> AppDatabase {
        do {
            let fileManager = FileManager.default
            let cachesURL = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let databaseURL = cachesURL.appendingPathComponent("db.sqlite")
            let dbPool = try DatabasePool(path: databaseURL.path, configuration: databaseConfiguration())
            
            return try AppDatabase(dbPool)
        } catch {
            fatalError("Unresolved error \(error)")
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

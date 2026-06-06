import SwiftUI

private struct AppDatabaseKey: EnvironmentKey {
    static let defaultValue: AppDatabase = .shared
}

extension EnvironmentValues {
    var appDatabase: AppDatabase {
        get { self[AppDatabaseKey.self] }
        set { self[AppDatabaseKey.self] = newValue }
    }
}

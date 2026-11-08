import Foundation
import KSPlayer

/// Feed player-engine messages into the same report as application events.
nonisolated struct PlayerDiagnosticLog: LogHandler {
    func log(level: LogLevel, message: CustomStringConvertible, file: String, function: String, line: UInt) {
        let text = "[\(level)] \((file as NSString).lastPathComponent):\(line) \(message.description)"
        switch level {
        case .panic, .fatal, .error: Log.error("KSPlayer", text)
        default: Log.info("KSPlayer", text)
        }
    }
}

/// The text behind every "Copy AirPlay log" control: the lines of this app session
/// or, when there are none (the app was relaunched since the cast, or the shared log
/// buffer has moved on), the record saved when the last cast ended. Every line was
/// redacted when it was written, so the text holds no stream URL or credentials.
nonisolated enum AirPlayLogExport {
    static let tags = ["AirPlayCast", "AirPlayRemux"]
    /// Where the cast controller saves the record of the last cast.
    static let persistedKey = "airplay.lastSessionLog"

    static func text() -> String {
        text(live: Log.recentLines(tags: tags), persisted: Log.persistedLines(key: persistedKey))
    }

    /// The choice itself, free of the log store. The saved record is labelled, so a
    /// reader does not take it for what just happened.
    static func text(live: [String], persisted: @autoclosure () -> [String]) -> String {
        if !live.isEmpty { return live.joined(separator: "\n") }
        let saved = persisted()
        guard !saved.isEmpty else { return "No AirPlay log lines recorded." }
        return (["Last saved AirPlay session:"] + saved).joined(separator: "\n")
    }
}

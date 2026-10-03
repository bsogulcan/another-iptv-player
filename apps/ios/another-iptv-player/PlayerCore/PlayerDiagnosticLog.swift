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

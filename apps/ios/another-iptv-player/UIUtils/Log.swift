import Foundation

/// Tüm NSLog çağrıları bu helper üzerinden gitmeli.
///
/// **Neden:** `NSLog("foo \(bar)")` çağrısında interpolate edilmiş tüm string format string
/// olarak yorumlanır. `bar` içinde `%` geçerse (URL'lerdeki `%20`, `%2F` vb.) NSLog
/// va_list'ten çöp pointer okuyup `EXC_BAD_ACCESS` ile crash eder.
///
/// `Log.info/error` her zaman mesajı `"%@"` ile geçirir → format string injection imkânsız.
enum Log {
  static func info(_ tag: String, _ message: @autoclosure () -> String) {
    NSLog("%@", "[\(tag)] \(message())")
  }

  static func error(_ tag: String, _ message: @autoclosure () -> String) {
    NSLog("%@", "[\(tag)] ERROR: \(message())")
  }
}

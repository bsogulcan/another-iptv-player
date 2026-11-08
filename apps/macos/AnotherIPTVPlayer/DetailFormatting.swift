import Foundation

enum DetailFormatting {
  static func year(from releaseDate: String?) -> String? {
    guard let raw = releaseDate?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
      return nil
    }
    let prefix = raw.prefix(4)
    return prefix.count == 4 && prefix.allSatisfy({ $0.isNumber }) ? String(prefix) : raw
  }

  /// The language picked in the app with the device's region, so digits follow the
  /// device as everywhere else in the app.
  private static var appLocale: Locale {
    AppLocale.current
  }

  /// Width of the units in a runtime: "45 min", "1 hr, 45 min", "45 dk.". The narrow
  /// width is shorter in English ("45m") but unreadable in Turkish ("45d").
  private nonisolated static let runtimeUnitWidth: Duration.UnitsFormatStyle.UnitWidth =
    .abbreviated

  /// A playback position: "12:34", or "1:02:03" from one hour on.
  static func formatMs(_ ms: Int) -> String {
    formatMs(ms, locale: appLocale)
  }

  nonisolated static func formatMs(_ ms: Int, locale: Locale) -> String {
    // Whole seconds go in: the format style rounds, and a resume point must not
    // read a second ahead of where playback starts.
    let totalSeconds = max(ms, 0) / 1000
    let duration = Duration.seconds(totalSeconds)
    return totalSeconds >= 3600
      ? duration.formatted(.time(pattern: .hourMinuteSecond).locale(locale))
      : duration.formatted(.time(pattern: .minuteSecond).locale(locale))
  }

  /// Panels send the episode runtime as a bare number of minutes, or as text of their
  /// own ("45 min", "1h 20m"), which is passed through.
  static func seriesRuntime(_ raw: String?) -> String? {
    seriesRuntime(raw, locale: appLocale)
  }

  nonisolated static func seriesRuntime(_ raw: String?, locale: Locale) -> String? {
    guard let r = raw?.trimmingCharacters(in: .whitespaces), !r.isEmpty, r != "0" else {
      return nil
    }
    if r.contains("m") || r.contains("h") { return r }
    guard let minutes = Int(r) else { return r }
    guard minutes > 0 else { return nil }
    // Not a runtime any more, and far enough from overflowing the seconds below.
    guard minutes <= 24 * 60 else { return r }
    return Duration.seconds(minutes * 60).formatted(
      .units(allowed: [.hours, .minutes], width: runtimeUnitWidth).locale(locale)
    )
  }

  /// A fraction as a whole percentage, written the way the app language writes it
  /// ("45%", "%45", "45 %"). Truncated, not rounded: a download at 99.6 % must not
  /// read 100 % while it is still running.
  static func percent(_ fraction: Double) -> String {
    percent(fraction, locale: appLocale)
  }

  nonisolated static func percent(_ fraction: Double, locale: Locale) -> String {
    let clamped = fraction.isFinite ? min(max(fraction, 0), 1) : 0
    let whole = Int((clamped * 100).rounded(.down))
    return whole.formatted(.percent.locale(locale))
  }

  static func genreList(_ raw: String?) -> [String] {
    guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return [] }
    return
      raw
      .split(whereSeparator: { $0 == "," || $0 == "/" || $0 == "|" })
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }
}

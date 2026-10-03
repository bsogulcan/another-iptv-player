import SwiftUI

enum ContentRating {
    /// Rebuilt when the app language or the device region changes, so ratings follow
    /// `AppLocale.current` like every other number on screen.
    private static var cachedFormatter: NumberFormatter?

    private static var roundedFormatter: NumberFormatter {
        let locale = AppLocale.current
        if let cached = cachedFormatter, cached.locale == locale { return cached }
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 0
        f.roundingMode = .halfUp
        cachedFormatter = f
        return f
    }

    /// Boş, yalnızca boşluk veya sayısal olarak 0 olan puanları göstermeyiz.
    /// Sayısal değerler tek ondalık basamağa yuvarlanır (ör. 6.665 → 6.7).
    static func displayText(_ rating: String?) -> String? {
        guard let r = rating?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty else { return nil }
        let forParse = r.replacingOccurrences(of: ",", with: ".")
        let numeric = NSDecimalNumber(string: forParse)
        if numeric == .notANumber {
            return r
        }
        if numeric.compare(NSDecimalNumber.zero) == .orderedSame {
            return nil
        }
        return roundedFormatter.string(from: numeric)
    }

    /// The same text for a rating that is already a number (the detail hero), from
    /// the same formatter, so a poster badge and the hero of the same title agree on
    /// the decimal separator and on the rounding. A rating of 0 means "not rated":
    /// it yields an empty string and the caller leaves the label out.
    static func displayText(_ value: Double) -> String {
        guard value.isFinite, value != 0 else { return "" }
        return roundedFormatter.string(from: NSNumber(value: value)) ?? ""
    }
}

struct RatingLabel: View {
    let rating: String?
    var style: Style = .compact

    enum Style {
        case compact
        case standard
    }

    var body: some View {
        if let text = ContentRating.displayText(rating) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(iconFont)
                    .foregroundStyle(.yellow.opacity(0.95))
                Text(text)
                    .font(textFont)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BrowseAccessibility.ratingLabel(text) ?? "")
        }
    }

    private var iconFont: Font {
        switch style {
        case .compact: return .caption2
        case .standard: return .caption
        }
    }

    private var textFont: Font {
        switch style {
        case .compact: return .caption2.weight(.medium)
        case .standard: return .caption
        }
    }
}

/// Poster / kapak görselinin sağ üst köşesi için koyu yarı saydam rozet.
struct PosterRatingBadge: View {
    let rating: String?

    var body: some View {
        if let text = ContentRating.displayText(rating) {
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .font(.caption2.weight(.semibold))
                Text(text)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.55), in: Capsule())
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BrowseAccessibility.ratingLabel(text) ?? "")
        }
    }
}

import SwiftUI

enum ContentRating {
    private static let roundedFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = .current
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 0
        f.roundingMode = .halfUp
        return f
    }()

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
                    .font(.system(size: 9, weight: .semibold))
                Text(text)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.55), in: Capsule())
        }
    }
}

import SwiftUI

/// Spoken card content in reading order, shared by shelves, grids and favourites.
enum BrowseAccessibility {
    static func ratingLabel(_ displayedRating: String?) -> String? {
        guard let displayedRating, !displayedRating.isEmpty else { return nil }
        return "\(L("movie.rating")) \(displayedRating)"
    }

    static func cardLabel(title: String, rating: String?, category: String?) -> String {
        [title, ratingLabel(ContentRating.displayText(rating)), category]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    static func progressValue(_ progress: Double?) -> String {
        guard let progress, progress.isFinite, progress > 0 else { return "" }
        return DetailFormatting.percent(min(progress, 1))
    }
}

extension View {
    func posterAccessibility(title: String, rating: String?, category: String?, progress: Double?) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(BrowseAccessibility.cardLabel(title: title, rating: rating, category: category))
            .accessibilityValue(BrowseAccessibility.progressValue(progress))
    }
}

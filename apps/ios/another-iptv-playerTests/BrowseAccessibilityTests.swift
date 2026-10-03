import Foundation
import Testing
@testable import another_iptv_player

@Suite("Browse accessibility text")
struct BrowseAccessibilityTests {
    @Test
    func titleComesBeforeRatingAndCategory() {
        let rating = ContentRating.displayText("7.4")!
        #expect(BrowseAccessibility.cardLabel(title: "Echoes", rating: "7.4", category: "Science Fiction")
                == "Echoes, \(L("movie.rating")) \(rating), Science Fiction")
    }

    @Test
    func absentRatingAndBlankCategoryDoNotLeaveSpokenSeparators() {
        #expect(BrowseAccessibility.cardLabel(title: "Echoes", rating: "0", category: "  ") == "Echoes")
        #expect(BrowseAccessibility.cardLabel(title: "Echoes", rating: nil, category: nil) == "Echoes")
    }

    @Test
    func progressUsesTheAppLocaleAndClampsToACompleteItem() {
        #expect(BrowseAccessibility.progressValue(0.4) == DetailFormatting.percent(0.4))
        #expect(BrowseAccessibility.progressValue(1.5) == DetailFormatting.percent(1))
        #expect(BrowseAccessibility.progressValue(nil).isEmpty)
        #expect(BrowseAccessibility.progressValue(.nan).isEmpty)
        #expect(BrowseAccessibility.progressValue(-1).isEmpty)
    }
}

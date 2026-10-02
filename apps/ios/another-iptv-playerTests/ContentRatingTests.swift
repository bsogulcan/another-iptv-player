import Foundation
import Testing
@testable import another_iptv_player

/// The poster badges format a rating that arrives as text, the detail hero one that
/// is already a number. Both have to print the same characters for the same value.
@Suite("ContentRating")
struct ContentRatingTests {

    @Test
    func aNumberPrintsLikeTheSameRatingAsText() {
        #expect(ContentRating.displayText(7.5) == ContentRating.displayText("7.5"))
        #expect(ContentRating.displayText(7.46) == ContentRating.displayText("7.46"))
        #expect(ContentRating.displayText(6.2) == ContentRating.displayText("6.2"))
        #expect(ContentRating.displayText(10) == ContentRating.displayText("10"))
    }

    @Test
    func aNumberIsRoundedToOneFractionDigit() {
        #expect(ContentRating.displayText(7.46) == ContentRating.displayText(7.5))
        #expect(ContentRating.displayText(7.44) == ContentRating.displayText(7.4))
        // Half goes up.
        #expect(ContentRating.displayText(6.75) == ContentRating.displayText(6.8))
        #expect(ContentRating.displayText(6.25) == ContentRating.displayText(6.3))
    }

    @Test
    func aWholeNumberHasNoFractionDigit() {
        #expect(ContentRating.displayText(8.0) == ContentRating.displayText("8"))
        #expect(ContentRating.displayText(8.0).count == 1)
    }

    @Test
    func zeroMeansNotRated() {
        #expect(ContentRating.displayText(0.0) == "")
        #expect(ContentRating.displayText(-0.0) == "")
        #expect(ContentRating.displayText(Double.nan) == "")
        #expect(ContentRating.displayText(Double.infinity) == "")
        // The text form hides the same value.
        #expect(ContentRating.displayText("0") == nil)
        #expect(ContentRating.displayText("0.0") == nil)
    }

    @Test
    func theTextFormKeepsItsRules() {
        #expect(ContentRating.displayText(nil as String?) == nil)
        #expect(ContentRating.displayText("   ") == nil)
        // Not a number: shown as it came.
        #expect(ContentRating.displayText("PG-13") == "PG-13")
        // A comma as the decimal separator of the input is understood.
        #expect(ContentRating.displayText("6,665") == ContentRating.displayText("6.665"))
        #expect(ContentRating.displayText("6.665") == ContentRating.displayText(6.7))
    }
}

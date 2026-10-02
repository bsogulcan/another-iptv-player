import CoreGraphics
import Testing
@testable import another_iptv_player

/// Regression locks for the width of the live player's programme strip and for the rule
/// that ends the in-player brightness override.
/// (Source: ios-player-airplay-review.md, chrome-native-design-10 and system-integration-9.)

// MARK: - Programme strip width

struct PlayerProgrammeStripLayoutTests {
    private typealias Layout = PlayerProgrammeStripLayout

    private func maxWidth(
        _ containerWidth: CGFloat, buttons: Int, leading: CGFloat = 0, trailing: CGFloat = 0
    ) -> CGFloat {
        Layout.maxWidth(
            containerWidth: containerWidth,
            leadingInset: leading,
            trailingInset: trailing,
            rowButtonCount: buttons
        )
    }

    @Test func withoutAChannelRowTheStripKeepsItsFullWidth() {
        #expect(maxWidth(375, buttons: 0) == Layout.defaultMaxWidth)
        #expect(maxWidth(1024, buttons: 0) == Layout.defaultMaxWidth)
        #expect(Layout.defaultMaxWidth == 240)
    }

    @Test func onAPortraitPhoneTheStripEndsBeforeTheSkipAndListButtons() {
        // Previous, next and channel list: 3 x 44 + 2 x 8 = 148 pt, 24 pt from the edge.
        #expect(maxWidth(393, buttons: 3) == 189)
        #expect(maxWidth(375, buttons: 3) == 171)
        #expect(maxWidth(430, buttons: 3) == 226)
    }

    @Test func theStripNeverReachesTheFirstButtonOfTheRow() {
        for width in stride(from: CGFloat(360), through: 460, by: 5) {
            for buttons in 1...3 {
                let cap = maxWidth(width, buttons: buttons)
                let stripEnd = Layout.stripLeadingInset + cap
                let count = CGFloat(buttons)
                let rowWidth = count * Layout.rowButtonSide + (count - 1) * Layout.rowButtonSpacing
                let rowStart = width - Layout.rowTrailingInset - rowWidth
                #expect(stripEnd + Layout.gapToRow <= rowStart)
            }
        }
    }

    @Test func aShorterRowLeavesTheStripMoreRoom() {
        // Skip buttons only.
        #expect(maxWidth(375, buttons: 2) == 223)
        // A single button leaves more than the strip ever takes.
        #expect(maxWidth(375, buttons: 1) == Layout.defaultMaxWidth)
    }

    @Test func landscapeAndTabletKeepTheFullWidth() {
        // iPhone landscape: recall, previous, next, list and rotate in one row.
        #expect(maxWidth(852, buttons: 5, leading: 59, trailing: 59) == Layout.defaultMaxWidth)
        #expect(maxWidth(1024, buttons: 4) == Layout.defaultMaxWidth)
    }

    @Test func safeAreaInsetsOnBothSidesNarrowTheStrip() {
        #expect(maxWidth(393, buttons: 3, leading: 10) == 179)
        #expect(maxWidth(393, buttons: 3, trailing: 10) == 179)
    }

    @Test func aVeryNarrowContainerKeepsAMinimumWidth() {
        #expect(maxWidth(320, buttons: 3) == Layout.minimumMaxWidth)
        #expect(maxWidth(0, buttons: 3) == Layout.minimumMaxWidth)
        #expect(maxWidth(.infinity, buttons: 3) == Layout.defaultMaxWidth)
    }

    @Test func theProgressBarNeverOutgrowsTheStrip() {
        #expect(Layout.barWidth(stripMaxWidth: 240) == Layout.defaultBarWidth)
        #expect(Layout.barWidth(stripMaxWidth: 189) == Layout.defaultBarWidth)
        #expect(Layout.barWidth(stripMaxWidth: 171) == 171)
        #expect(Layout.barWidth(stripMaxWidth: -5) == 0)
        #expect(Layout.defaultBarWidth == 188)
    }
}

// MARK: - Brightness override

struct ScreenBrightnessOverridePolicyTests {
    private typealias Policy = ScreenBrightnessOverridePolicy

    @Test func theEchoOfTheAppsOwnWriteKeepsTheOverride() {
        #expect(!Policy.isExternalChange(current: 0.4, lastAppWritten: 0.4))
        // The level the system reports back may be rounded.
        #expect(!Policy.isExternalChange(current: 0.404, lastAppWritten: 0.4))
        #expect(!Policy.isExternalChange(current: 0.396, lastAppWritten: 0.4))
    }

    @Test func aLevelTheAppDidNotWriteEndsTheOverride() {
        #expect(Policy.isExternalChange(current: 0.8, lastAppWritten: 0.4))
        #expect(Policy.isExternalChange(current: 0.1, lastAppWritten: 0.4))
        #expect(Policy.isExternalChange(current: 0.42, lastAppWritten: 0.4))
    }

    @Test func withNothingWrittenThereIsNoOverrideToEnd() {
        #expect(!Policy.isExternalChange(current: 0.8, lastAppWritten: nil))
    }
}

import CoreGraphics
import SwiftUI
import Testing
@testable import another_iptv_player

/// Poster sizes for a window: scaled from its shorter side and snapped to eighths, so
/// a window that is being resized passes through a handful of layouts, not hundreds.
@Suite("Poster metrics for a window")
struct PosterMetricsWindowTests {

    private func scale(_ width: CGFloat, _ height: CGFloat) -> CGFloat {
        PosterMetrics.snapped(toWindow: CGSize(width: width, height: height)).layoutScale
    }

    @Test
    func fullScreenDevicesKeepTheirScale() {
        #expect(scale(834, 1194) == 1.0)    // iPad 11", the reference
        #expect(scale(1024, 1366) == 1.0)   // iPad 13"
        #expect(scale(402, 874) == 0.5)     // iPhone
        #expect(scale(440, 956) == 0.5)     // largest iPhone
    }

    @Test
    func aNarrowIPadWindowGetsPhoneSizes() {
        #expect(scale(375, 1024) == 0.5)    // Slide Over, one-third split
        #expect(scale(507, 1024) == 0.625)  // half split on the 13"
        #expect(scale(744, 1133) == 0.875)  // iPad mini
    }

    /// The shorter side decides, so rotating (or the player forcing landscape) changes
    /// nothing.
    @Test
    func rotationDoesNotChangeTheScale() {
        for (width, height) in [(834.0, 1194.0), (402.0, 874.0), (507.0, 1024.0), (744.0, 1133.0)] {
            #expect(scale(width, height) == scale(height, width))
        }
    }

    @Test
    func theScaleMovesInEighths() {
        var seen = Set<CGFloat>()
        for side in stride(from: 300.0, through: 1400.0, by: 1.0) {
            let value = scale(side, 2000)
            #expect(value >= 0.5 && value <= 1.0)
            #expect((value * 8).rounded() == value * 8, "\(side) pt gives \(value)")
            seen.insert(value)
        }
        #expect(seen == [0.5, 0.625, 0.75, 0.875, 1.0])
    }

    @Test
    func equalStepsCompareEqual() {
        let a = PosterMetrics.snapped(toWindow: CGSize(width: 600, height: 900))
        let b = PosterMetrics.snapped(toWindow: CGSize(width: 640, height: 480).applying(.init(scaleX: 1.3, y: 1.3)))
        #expect(a.layoutScale == 0.75)
        #expect(a == b)
        #expect(a.shelfPosterWidth == 150)
        #expect(a.shelfPosterHeight == 225)
    }
}

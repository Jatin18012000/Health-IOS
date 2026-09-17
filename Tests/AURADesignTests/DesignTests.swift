import Testing
import Foundation
import SwiftUI
@testable import AURADesign

/// Sparkline geometry.
///
/// Small, and worth pinning: a chart that silently maps a value to the wrong
/// height is the kind of bug nobody reports, because the picture still looks
/// like a picture. Every expectation is derived from the formula in the source.
@Suite("Sparkline geometry")
struct SparklineTests {

    private static let size = CGSize(width: 100, height: 50)
    /// Matches the constant in `Sparkline`. Points are inset at top and bottom
    /// so a peak is not clipped by the frame edge.
    private static let inset: CGFloat = 5

    @Test("the highest value sits at the top and the lowest at the bottom")
    func extremesMapToEdges() throws {
        let points = Sparkline.points([10, 20, 30], in: Self.size, baseline: nil)
        #expect(points.count == 3)

        // Screen coordinates grow downward, so the largest value must have the
        // SMALLEST y. Getting this inverted draws every trend upside down.
        let highest = try #require(points.last)
        let lowest = try #require(points.first)
        #expect(highest.y == Self.inset)
        #expect(lowest.y == Self.size.height - Self.inset)
        #expect(highest.y < lowest.y)
    }

    @Test("the line spans the full width")
    func spansWidth() throws {
        let points = Sparkline.points([1, 2, 3, 4, 5], in: Self.size, baseline: nil)
        let first = try #require(points.first)
        let last = try #require(points.last)
        #expect(first.x == 0)
        #expect(last.x == Self.size.width)
    }

    @Test("a single point is not a line")
    func singleValueDrawsNothing() {
        // With one value there is no span to normalise against, and the step
        // would divide by zero.
        #expect(Sparkline.points([42], in: Self.size, baseline: nil).isEmpty)
        #expect(Sparkline.points([], in: Self.size, baseline: nil).isEmpty)
    }

    @Test("a flat series produces a flat line, not a crash")
    func flatSeries() {
        // span would be zero, so the source floors it at 0.0001. Without that
        // this is a divide by zero and every y is NaN.
        let points = Sparkline.points([7, 7, 7], in: Self.size, baseline: nil)
        #expect(points.count == 3)
        #expect(points.allSatisfy { !$0.y.isNaN })
        #expect(Set(points.map(\.y)).count == 1)
    }

    @Test("the baseline is inside the drawn extent even when it is an outlier")
    func baselineIsIncludedInBounds() {
        // The reason `bounds` takes a baseline at all: a reference line outside
        // the value range would be drawn off the top or bottom of the frame and
        // silently vanish, leaving a chart that looks fine and means less.
        let below = Sparkline.bounds([10, 20], baseline: 5)
        #expect(below.0 == 5)
        #expect(below.1 == 20)

        let above = Sparkline.bounds([10, 20], baseline: 30)
        #expect(above.0 == 10)
        #expect(above.1 == 30)

        // A baseline already inside the range changes nothing.
        let inside = Sparkline.bounds([10, 20], baseline: 15)
        #expect(inside.0 == 10)
        #expect(inside.1 == 20)
    }

    @Test("y(for:) agrees with the points it would draw")
    func yMatchesPoints() throws {
        let values: [Double] = [10, 20, 30]
        let points = Sparkline.points(values, in: Self.size, baseline: nil)
        for (index, value) in values.enumerated() {
            let y = try #require(Sparkline.y(for: value, values: values,
                                             size: Self.size, baseline: nil))
            // The marker and the line have to land on the same pixel; two
            // formulas that drift apart put the dot off the curve.
            #expect(abs(y - points[index].y) < 0.0001)
        }
    }

    @Test("y(for:) has nothing to report on a series too short to draw")
    func yNeedsASeries() {
        #expect(Sparkline.y(for: 5, values: [5], size: Self.size, baseline: nil) == nil)
    }
}

/// Theme invariants.
///
/// These are not style opinions — they are the assumptions the rest of the app
/// makes about every theme, and a new theme that breaks one fails at runtime.
@Suite("Themes")
struct ThemeTests {

    @Test("every theme carries enough chart colours for the highest index used")
    func dataSeriesIsLongEnough() {
        // `dataSeries[4]` is indexed directly in the dashboard and in the
        // sidebar's status dot. A theme added later with four colours would
        // compile cleanly and crash on the screen that uses the fifth.
        for theme in Theme.all {
            #expect(theme.dataSeries.count >= 5,
                    "\(theme.name) has \(theme.dataSeries.count) chart colours")
        }
    }

    @Test("theme ids are unique")
    func idsAreUnique() {
        // `Preferences` stores the id and looks the theme back up by it, so a
        // duplicate would silently load the wrong one after a relaunch.
        let ids = Theme.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("exactly one theme is light, and it is the one that says so")
    func lightThemeIsIdentified() {
        let light = Theme.all.filter(\.isLight)
        #expect(light.count == 1)
        #expect(light.first?.id == "daylight")
        #expect(!Theme.cyberNeon.isLight)
    }

    @Test("the light theme has no glow")
    func lightThemeDropsGlow() {
        // Glow on white reads as smudge rather than light, so the light theme
        // sets it to zero. The character's rim lighting checks `isLight` for
        // the same reason.
        let light = Theme.all.first(where: \.isLight)
        #expect(light?.glowRadius == 0)
        #expect(Theme.cyberNeon.glowRadius > 0)
    }

    @Test("every theme has a non-empty name and id")
    func namesAndIdsArePresent() {
        for theme in Theme.all {
            #expect(!theme.id.isEmpty)
            #expect(!theme.name.isEmpty)
        }
    }

    @Test("the default theme is one of the listed themes")
    func defaultIsListed() {
        // `Preferences` falls back to `.cyberNeon` when a stored id no longer
        // resolves; if it were not in `all`, Settings could not show it as
        // selected.
        #expect(Theme.all.contains { $0.id == Theme.cyberNeon.id })
    }
}

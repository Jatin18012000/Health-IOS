import SwiftUI
import AURACore

/// Design tokens for the neon-glass look in the reference mockups.
///
/// No view hardcodes a colour. A theme is a value; adding one is adding a
/// `Theme`, not touching any dashboard code.
public struct Theme: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String

    public let background: Color
    public let surface: Color
    public let surfaceStroke: Color
    public let primary: Color
    public let secondary: Color
    public let accent: Color
    public let textPrimary: Color
    public let textSecondary: Color

    /// Ordered palette for charts. Sequential series read in this order, so it
    /// is chosen to stay distinguishable at small sizes and in both themes.
    public let dataSeries: [Color]

    public let glowRadius: CGFloat
    public let cornerRadius: CGFloat

    public static let cyberNeon = Theme(
        id: "cyber-neon",
        name: "Cyber Neon",
        background:    Color(red: 0.03, green: 0.03, blue: 0.09),
        surface:       Color(red: 0.07, green: 0.08, blue: 0.16).opacity(0.72),
        surfaceStroke: Color(red: 0.45, green: 0.35, blue: 0.95).opacity(0.35),
        primary:       Color(red: 0.55, green: 0.40, blue: 1.00),
        secondary:     Color(red: 0.20, green: 0.85, blue: 1.00),
        accent:        Color(red: 1.00, green: 0.30, blue: 0.75),
        textPrimary:   Color(white: 0.97),
        textSecondary: Color(white: 0.65),
        dataSeries: [
            Color(red: 0.20, green: 0.85, blue: 1.00),
            Color(red: 0.55, green: 0.40, blue: 1.00),
            Color(red: 1.00, green: 0.30, blue: 0.75),
            Color(red: 0.30, green: 0.95, blue: 0.65),
            Color(red: 1.00, green: 0.75, blue: 0.25),
        ],
        glowRadius: 18,
        cornerRadius: 16
    )

    /// Cool and quiet. The same structure with the heat taken out — for when
    /// the neon is tiring to look at every morning.
    public static let deepOcean = Theme(
        id: "deep-ocean",
        name: "Deep Ocean",
        background:    Color(red: 0.02, green: 0.05, blue: 0.09),
        surface:       Color(red: 0.05, green: 0.10, blue: 0.16).opacity(0.74),
        surfaceStroke: Color(red: 0.20, green: 0.55, blue: 0.75).opacity(0.32),
        primary:       Color(red: 0.25, green: 0.70, blue: 0.95),
        secondary:     Color(red: 0.35, green: 0.90, blue: 0.85),
        accent:        Color(red: 0.95, green: 0.55, blue: 0.35),
        textPrimary:   Color(white: 0.95),
        textSecondary: Color(red: 0.55, green: 0.68, blue: 0.76),
        dataSeries: [
            Color(red: 0.35, green: 0.90, blue: 0.85),
            Color(red: 0.25, green: 0.70, blue: 0.95),
            Color(red: 0.95, green: 0.55, blue: 0.35),
            Color(red: 0.45, green: 0.95, blue: 0.60),
            Color(red: 0.98, green: 0.82, blue: 0.40),
        ],
        glowRadius: 14,
        cornerRadius: 16
    )

    /// Warm and low-glow. Reads as lamplight rather than a screen, which suits
    /// the evening far better than the neon does.
    public static let emberDusk = Theme(
        id: "ember-dusk",
        name: "Ember Dusk",
        background:    Color(red: 0.07, green: 0.05, blue: 0.04),
        surface:       Color(red: 0.13, green: 0.10, blue: 0.08).opacity(0.78),
        surfaceStroke: Color(red: 0.70, green: 0.45, blue: 0.25).opacity(0.30),
        primary:       Color(red: 0.95, green: 0.60, blue: 0.30),
        secondary:     Color(red: 0.98, green: 0.80, blue: 0.45),
        accent:        Color(red: 0.90, green: 0.35, blue: 0.40),
        textPrimary:   Color(red: 0.97, green: 0.94, blue: 0.90),
        textSecondary: Color(red: 0.66, green: 0.59, blue: 0.53),
        dataSeries: [
            Color(red: 0.98, green: 0.80, blue: 0.45),
            Color(red: 0.95, green: 0.60, blue: 0.30),
            Color(red: 0.90, green: 0.35, blue: 0.40),
            Color(red: 0.55, green: 0.75, blue: 0.55),
            Color(red: 0.70, green: 0.60, blue: 0.85),
        ],
        glowRadius: 10,
        cornerRadius: 16
    )

    /// Light, and the one that will need an actual look before it ships.
    ///
    /// Every other theme is a dark variant of the same idea, so the views have
    /// only ever been seen dark. Nothing hardcodes a colour — they read tokens —
    /// but glow and opacity behave very differently on white, and a few panels
    /// will want tuning rather than inverting.
    public static let daylight = Theme(
        id: "daylight",
        name: "Daylight",
        background:    Color(red: 0.97, green: 0.97, blue: 0.98),
        surface:       Color.white.opacity(0.88),
        surfaceStroke: Color(red: 0.42, green: 0.36, blue: 0.62).opacity(0.22),
        primary:       Color(red: 0.42, green: 0.30, blue: 0.80),
        secondary:     Color(red: 0.10, green: 0.52, blue: 0.70),
        accent:        Color(red: 0.80, green: 0.20, blue: 0.50),
        textPrimary:   Color(red: 0.10, green: 0.10, blue: 0.14),
        textSecondary: Color(red: 0.42, green: 0.42, blue: 0.48),
        dataSeries: [
            Color(red: 0.10, green: 0.52, blue: 0.70),
            Color(red: 0.42, green: 0.30, blue: 0.80),
            Color(red: 0.80, green: 0.20, blue: 0.50),
            Color(red: 0.10, green: 0.55, blue: 0.40),
            Color(red: 0.72, green: 0.48, blue: 0.05),
        ],
        // Glow on white is smudge, not light.
        glowRadius: 0,
        cornerRadius: 16
    )

    public static let all: [Theme] = [.cyberNeon, .deepOcean, .emberDusk, .daylight]

    /// True when the theme is light, for the few places that need to know —
    /// the character's rim lighting reads as grime on a white ground and is
    /// dropped rather than inverted.
    public var isLight: Bool { id == "daylight" }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .cyberNeon
}

public extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

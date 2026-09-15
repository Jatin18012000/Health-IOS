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

    public static let all: [Theme] = [.cyberNeon]
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

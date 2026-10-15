import SwiftUI

/*
 * Notion-like black and white, the same values as the Android app's Theme.kt: the phone may run in
 * grayscale, so nothing relies on hue. "Ink" is the one strong color; everything else is a gray.
 */
public enum Ink {
    public static let light = Palette(
        ink: Color(hex: 0x37352F), onInk: .white, background: .white, surfaceLow: Color(hex: 0xFBFBFA),
        tile: Color(hex: 0xF1F1EF), tileHigh: Color(hex: 0xE9E9E7), dim: Color(hex: 0x6F6E69),
        outline: Color(hex: 0xD3D3D1), hairline: Color(hex: 0xEDEDEB), error: Color(hex: 0xD44C47)
    )
    public static let dark = Palette(
        ink: Color(hex: 0xE3E2E0), onInk: Color(hex: 0x191919), background: Color(hex: 0x191919), surfaceLow: Color(hex: 0x1E1E1E),
        tile: Color(hex: 0x2C2C2C), tileHigh: Color(hex: 0x373737), dim: Color(hex: 0x9B9A97),
        outline: Color(hex: 0x474747), hairline: Color(hex: 0x2A2A2A), error: Color(hex: 0xE16259)
    )
}

public struct Palette: Sendable {
    public let ink: Color        // onSurface / primary
    public let onInk: Color      // text on a solid ink fill
    public let background: Color
    public let surfaceLow: Color // sheets
    public let tile: Color       // icon tiles, inputs (surfaceContainerHigh)
    public let tileHigh: Color
    public let dim: Color        // secondary text (onSurfaceVariant)
    public let outline: Color
    public let hairline: Color   // outlineVariant: dividers, soft card edges
    public let error: Color

    /// Faint version of the ink, used for empty cells and quiet backgrounds.
    public var tint: Color { ink.opacity(0.12) }
    /// A barely-there edge: enough to separate a card from the page, never a hard line.
    public var softBorder: Color { hairline.opacity(0.7) }
}

/// One set of shapes for the whole app: Small = cells, tiles, menu items; Medium = cards, groups,
/// inputs, dialogs; Sheet = bottom sheets. Chips, buttons and pills are fully round.
public enum Radius {
    public static let small: CGFloat = 10
    public static let medium: CGFloat = 16
    public static let sheet: CGFloat = 24
}

/// Inter at Material 3's sizes, so text measures the same as on Android.
public enum Type {
    public static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold: name = "Inter-Bold"
        case .semibold: name = "Inter-SemiBold"
        case .medium: name = "Inter-Medium"
        default: name = "Inter-Regular"
        }
        return .custom(name, size: size)
    }
    public static let displaySmall = inter(36, .bold)
    public static let headlineMedium = inter(28, .bold)
    public static let headlineSmall = inter(24, .bold)
    public static let titleLarge = inter(22, .bold)
    public static let titleMedium = inter(16, .semibold)
    public static let titleSmall = inter(14, .semibold)
    public static let bodyLarge = inter(16)
    public static let bodyMedium = inter(14)
    public static let bodySmall = inter(12)
    public static let labelLarge = inter(14, .medium)
    public static let labelMedium = inter(12, .medium)
    public static let labelSmall = inter(11, .medium)
}

public extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

/// The palette for the current color scheme.
public struct PaletteKey: EnvironmentKey { public static let defaultValue = Ink.light }
public extension EnvironmentValues {
    var palette: Palette { get { self[PaletteKey.self] } set { self[PaletteKey.self] = newValue } }
}

public extension View {
    /// Picks Paper or Night from the color scheme (or a forced choice) and provides it to the tree.
    func habitTheme(dark: Bool? = nil) -> some View { modifier(HabitThemeModifier(dark: dark)) }
}

private struct HabitThemeModifier: ViewModifier {
    let dark: Bool?
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let palette = (dark ?? (scheme == .dark)) ? Ink.dark : Ink.light
        content
            .environment(\.palette, palette)
            .foregroundStyle(palette.ink)
            .background(palette.background)
            .preferredColorScheme(dark.map { $0 ? .dark : .light })
    }
}

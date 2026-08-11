import Foundation

public struct ThemeRGBColor: Equatable, Hashable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(hex: UInt32) {
        red = UInt8((hex >> 16) & 0xFF)
        green = UInt8((hex >> 8) & 0xFF)
        blue = UInt8(hex & 0xFF)
    }

    public var hex: UInt32 {
        UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
    }
}

/// A compact mapping of LightQuickLook token kinds onto the official VS Code
/// Dark 2026 and Light 2026 editor/token palettes.
public enum VSCode2026Theme: CaseIterable, Sendable {
    case dark
    case light

    public var background: ThemeRGBColor {
        switch self {
        case .dark: ThemeRGBColor(hex: 0x121314)
        case .light: ThemeRGBColor(hex: 0xFFFFFF)
        }
    }

    public var foreground: ThemeRGBColor {
        switch self {
        case .dark: ThemeRGBColor(hex: 0xBBBEBF)
        case .light: ThemeRGBColor(hex: 0x202020)
        }
    }

    public func color(for kind: TokenKind) -> ThemeRGBColor {
        switch (self, kind) {
        case (_, .plain), (_, .operator), (_, .punctuation):
            // VS Code leaves operators at the editor foreground. Keeping braces
            // there too avoids the low-contrast tertiary-label treatment.
            foreground
        case (.dark, .comment): ThemeRGBColor(hex: 0x8B949E)
        case (.light, .comment): ThemeRGBColor(hex: 0x6E7781)
        case (.dark, .string), (.dark, .link): ThemeRGBColor(hex: 0xA5D6FF)
        case (.light, .string), (.light, .link): ThemeRGBColor(hex: 0x0A3069)
        case (.dark, .number), (.dark, .literal), (.dark, .property), (.dark, .support), (.dark, .heading):
            ThemeRGBColor(hex: 0x79C0FF)
        case (.light, .number), (.light, .literal), (.light, .property), (.light, .support), (.light, .heading):
            ThemeRGBColor(hex: 0x0550AE)
        case (.dark, .keyword), (.dark, .directive), (.dark, .type): ThemeRGBColor(hex: 0xFF7B72)
        case (.light, .keyword), (.light, .directive), (.light, .type): ThemeRGBColor(hex: 0xCF222E)
        case (.dark, .controlKeyword): ThemeRGBColor(hex: 0xC586C0)
        case (.light, .controlKeyword): ThemeRGBColor(hex: 0xAF00DB)
        case (.dark, .variable): ThemeRGBColor(hex: 0xC9D1D9)
        case (.light, .variable): ThemeRGBColor(hex: 0x1F2328)
        case (.dark, .supportFunction): ThemeRGBColor(hex: 0xDCDCAA)
        case (.light, .supportFunction): ThemeRGBColor(hex: 0x795E26)
        case (.dark, .code): ThemeRGBColor(hex: 0x7EE787)
        case (.light, .code): ThemeRGBColor(hex: 0x116329)
        }
    }
}

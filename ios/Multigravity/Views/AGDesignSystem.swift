import SwiftUI
import UIKit

// MARK: - Multigravity v4.0 Dual-Theme Design Token System
// Light Mode: Antigravity Alabaster White + shadcn/ui Zinc/Slate Hairlines
// Dark Mode : Strictly engineered via `claude cut` Local Color Library rules:
//   - 60% Matte Obsidian Canvas (#16161A, Happy Hues #4 Official Scoped Role) + OKLab Dual-Corner Subtle Glow
//   - 30% Elevated Graphite Card (#242629) + Recessed Code/Input Well (#1B1C20) + 1pt Hairline (#363840)
//   - Primary Text #FFFFFE (18.03:1 WCAG AAA), Secondary #AFB8C7 (9.03:1 AAA), Muted #8B95A5 (5.96:1 AA+)
//   - Strict separation of `accentFill` (buttons/arcs) vs `accentText` (lifted foreground labels on dark bg):
//     * Google Gemini Blue: fill #4285F4 | text #7AB3FF (8.35:1 AAA)
//     * Anthropic Claude  : fill #D97757 | text #F5A387 (9.00:1 AAA)
//     * Healthy Emerald   : fill #2CB67D | text #5CE0A8 (10.90:1 AAA)
//     * Urgent Amber      : fill #F59E0B | text #FCD34D (12.51:1 AAA)
//     * Danger Rose       : fill #E11D48 | text #FDA4AF (9.54:1 AAA)
//     * Swarm Violet      : fill #7F5AF0 | text #C4B5FD (9.77:1 AAA)

public enum AGSemanticTone: Sendable {
    case blue
    case claude
    case emerald
    case amber
    case rose
    case violet
    case zinc
    case ink

    public static let accent: AGSemanticTone = .blue
    public static let neutral: AGSemanticTone = .zinc
}

public struct AGPalette: Sendable {
    public let isDark: Bool

    public init(_ scheme: ColorScheme) {
        self.isDark = (scheme == .dark)
    }

    public init(isDark: Bool) {
        self.isDark = isDark
    }

    // MARK: 60% Canvas & 30% Surfaces
    public var canvas: Color {
        isDark ? Self.hex(0x16161A) : Self.hex(0xFFFFFF)
    }

    public var pageBg: Color {
        isDark ? Self.hex(0x16161A) : Self.hex(0xFAFAFB)
    }

    public var navBarBg: Color {
        isDark ? Self.hex(0x16161A) : Self.hex(0xFFFFFF)
    }

    public var card: Color {
        isDark ? Self.hex(0x242629) : Self.hex(0xFFFFFF)
    }

    public var recessed: Color {
        isDark ? Self.hex(0x1B1C20) : Self.hex(0xF4F4F5)
    }

    public var well: Color {
        isDark ? Self.hex(0x1D1E22) : Self.hex(0xF8FAFC)
    }

    // MARK: Hairline Borders
    public var borderCard: Color {
        isDark ? Self.hex(0x363840) : Self.hex(0xE4E4E7)
    }

    public var borderSoft: Color {
        isDark ? Self.hex(0x2C2E35) : Self.hex(0xEEF0F4)
    }

    public var borderStrong: Color {
        isDark ? Self.hex(0x494C57) : Self.hex(0xD4D4D8)
    }

    // MARK: Typography
    public var ink1: Color {
        isDark ? Self.hex(0xFFFFFE) : Self.hex(0x09090B)
    }

    public var ink2: Color {
        isDark ? Self.hex(0xAFB8C7) : Self.hex(0x52525B)
    }

    public var ink3: Color {
        isDark ? Self.hex(0x8B95A5) : Self.hex(0x71717A)
    }

    // MARK: Primary Button
    public var primaryBtnBg: Color {
        isDark ? Self.hex(0xFFFFFE) : Self.hex(0x09090B)
    }

    public var primaryBtnFg: Color {
        isDark ? Self.hex(0x16161A) : Self.hex(0xFFFFFF)
    }

    // MARK: 10% Accents (Strict `Fill` vs `Text` Separation)
    public var accentFill: Color {
        isDark ? Self.hex(0x4285F4) : Self.hex(0x2563EB)
    }

    public var accentText: Color {
        isDark ? Self.hex(0x7AB3FF) : Self.hex(0x1D4ED8)
    }

    public var accentSoft: Color {
        isDark ? Self.hex(0x4285F4, alpha: 0.15) : Self.hex(0xEFF6FF)
    }

    public var accentBorder: Color {
        isDark ? Self.hex(0x7AB3FF, alpha: 0.28) : Self.hex(0xBFDBFE)
    }

    public var claudeFill: Color {
        Self.hex(0xD97757)
    }

    public var claudeText: Color {
        isDark ? Self.hex(0xF5A387) : Self.hex(0x9A3412)
    }

    public var claudeSoft: Color {
        isDark ? Self.hex(0xD97757, alpha: 0.15) : Self.hex(0xFFF7ED)
    }

    public var claudeBorder: Color {
        isDark ? Self.hex(0xF5A387, alpha: 0.28) : Self.hex(0xFED7AA)
    }

    public var emeraldFill: Color {
        isDark ? Self.hex(0x2CB67D) : Self.hex(0x10B981)
    }

    public var emeraldText: Color {
        isDark ? Self.hex(0x5CE0A8) : Self.hex(0x047857)
    }

    public var emeraldSoft: Color {
        isDark ? Self.hex(0x2CB67D, alpha: 0.15) : Self.hex(0xECFDF5)
    }

    public var emeraldBorder: Color {
        isDark ? Self.hex(0x5CE0A8, alpha: 0.28) : Self.hex(0xA7F3D0)
    }

    public var amberFill: Color {
        Self.hex(0xF59E0B)
    }

    public var amberText: Color {
        isDark ? Self.hex(0xFCD34D) : Self.hex(0xB45309)
    }

    public var amberSoft: Color {
        isDark ? Self.hex(0xF59E0B, alpha: 0.15) : Self.hex(0xFFFBEB)
    }

    public var amberBorder: Color {
        isDark ? Self.hex(0xFCD34D, alpha: 0.30) : Self.hex(0xFDE68A)
    }

    public var roseFill: Color {
        Self.hex(0xE11D48)
    }

    public var roseText: Color {
        isDark ? Self.hex(0xFDA4AF) : Self.hex(0xBE123C)
    }

    public var roseSoft: Color {
        isDark ? Self.hex(0xE11D48, alpha: 0.16) : Self.hex(0xFFF1F2)
    }

    public var roseBorder: Color {
        isDark ? Self.hex(0xFDA4AF, alpha: 0.28) : Self.hex(0xFECDD3)
    }

    public var violetFill: Color {
        isDark ? Self.hex(0x7F5AF0) : Self.hex(0x7C3AED)
    }

    public var violetText: Color {
        isDark ? Self.hex(0xC4B5FD) : Self.hex(0x6D28D9)
    }

    public var violetSoft: Color {
        isDark ? Self.hex(0x7F5AF0, alpha: 0.16) : Self.hex(0xF5F3FF)
    }

    public var violetBorder: Color {
        isDark ? Self.hex(0xC4B5FD, alpha: 0.28) : Self.hex(0xDDD6FE)
    }

    public var zincSoft: Color {
        isDark ? Self.hex(0x2E3037) : Self.hex(0xF4F4F5)
    }

    public var zincText: Color {
        isDark ? Self.hex(0xD0D6E0) : Self.hex(0x3F3F46)
    }

    public var zincBorder: Color {
        isDark ? Self.hex(0x3E414B) : Self.hex(0xE4E4E7)
    }

    public var gaugeTrackOuter: Color {
        isDark ? Self.hex(0x31343D) : Self.hex(0xEEF2F6)
    }

    public var gaugeTrackInner: Color {
        isDark ? Self.hex(0x2A2D35) : Self.hex(0xF1F5F9)
    }

    public var gaugeNeedle: Color {
        isDark ? Self.hex(0xFFFFFE) : Self.hex(0x09090B)
    }

    public var tabActivePill: Color {
        isDark ? Self.hex(0x4285F4, alpha: 0.18) : Self.hex(0xEFF6FF)
    }

    public func toneColors(_ tone: AGSemanticTone) -> (fg: Color, bg: Color, border: Color) {
        switch tone {
        case .blue: return (accentText, accentSoft, accentBorder)
        case .claude: return (claudeText, claudeSoft, claudeBorder)
        case .emerald: return (emeraldText, emeraldSoft, emeraldBorder)
        case .amber: return (amberText, amberSoft, amberBorder)
        case .rose: return (roseText, roseSoft, roseBorder)
        case .violet: return (violetText, violetSoft, violetBorder)
        case .zinc: return (zincText, zincSoft, zincBorder)
        case .ink: return (primaryBtnFg, primaryBtnBg, primaryBtnBg)
        }
    }

    public static var adaptiveAccentColor: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0x42 / 255.0, green: 0x85 / 255.0, blue: 0xF4 / 255.0, alpha: 1.0)
                : UIColor(red: 0x25 / 255.0, green: 0x63 / 255.0, blue: 0xEB / 255.0, alpha: 1.0)
        })
    }

    public static func hex(_ rgb: UInt32, alpha: Double = 1.0) -> Color {
        Color(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0,
            opacity: alpha
        )
    }

    // MARK: Static Convenience Accessors (ColorScheme -> Color)
    public static func pageBackground(_ scheme: ColorScheme) -> Color { AGPalette(scheme).pageBg }
    public static func cardBackground(_ scheme: ColorScheme) -> Color { AGPalette(scheme).card }
    public static func tabBarBackground(_ scheme: ColorScheme) -> Color { AGPalette(scheme).navBarBg }
    public static func composerBackground(_ scheme: ColorScheme) -> Color { AGPalette(scheme).card }
    public static func recessedWell(_ scheme: ColorScheme) -> Color { AGPalette(scheme).recessed }

    public static func border(_ scheme: ColorScheme) -> Color { AGPalette(scheme).borderCard }
    public static func borderSubtle(_ scheme: ColorScheme) -> Color { AGPalette(scheme).borderSoft }

    public static func textPrimary(_ scheme: ColorScheme) -> Color { AGPalette(scheme).ink1 }
    public static func textSecondary(_ scheme: ColorScheme) -> Color { AGPalette(scheme).ink2 }
    public static func textTertiary(_ scheme: ColorScheme) -> Color { AGPalette(scheme).ink3 }

    public static func accentFill(_ scheme: ColorScheme) -> Color { AGPalette(scheme).accentFill }
    public static func accentText(_ scheme: ColorScheme) -> Color { AGPalette(scheme).accentText }
    public static func accentSoft(_ scheme: ColorScheme) -> Color { AGPalette(scheme).accentSoft }

    public static func emeraldFill(_ scheme: ColorScheme) -> Color { AGPalette(scheme).emeraldFill }
    public static func emeraldText(_ scheme: ColorScheme) -> Color { AGPalette(scheme).emeraldText }
    public static func emeraldSoft(_ scheme: ColorScheme) -> Color { AGPalette(scheme).emeraldSoft }

    public static func amberFill(_ scheme: ColorScheme) -> Color { AGPalette(scheme).amberFill }
    public static func amberText(_ scheme: ColorScheme) -> Color { AGPalette(scheme).amberText }
    public static func amberSoft(_ scheme: ColorScheme) -> Color { AGPalette(scheme).amberSoft }

    public static func roseFill(_ scheme: ColorScheme) -> Color { AGPalette(scheme).roseFill }
    public static func roseText(_ scheme: ColorScheme) -> Color { AGPalette(scheme).roseText }
    public static func roseSoft(_ scheme: ColorScheme) -> Color { AGPalette(scheme).roseSoft }

    public static func violetFill(_ scheme: ColorScheme) -> Color { AGPalette(scheme).violetFill }
    public static func violetText(_ scheme: ColorScheme) -> Color { AGPalette(scheme).violetText }
    public static func violetSoft(_ scheme: ColorScheme) -> Color { AGPalette(scheme).violetSoft }

    public static func geminiBrandFill(_ scheme: ColorScheme) -> Color { AGPalette(scheme).accentFill }
    public static func geminiBrandText(_ scheme: ColorScheme) -> Color { AGPalette(scheme).accentText }
    public static var claudeBrandFill: Color { hex(0xD97757) }
    public static func claudeBrandText(_ scheme: ColorScheme) -> Color { AGPalette(scheme).claudeText }
    public static func gaugeTrack(_ scheme: ColorScheme) -> Color { AGPalette(scheme).gaugeTrackOuter }
    public static func gaugeNeedle(_ scheme: ColorScheme) -> Color { AGPalette(scheme).gaugeNeedle }
}

// MARK: - claude cut OKLab Subtle Dual-Corner Atmosphere Background

public struct AGPageBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        let p = AGPalette(colorScheme)
        ZStack {
            p.pageBg
            if p.isDark {
                GeometryReader { geo in
                    ZStack {
                        RadialGradient(
                            colors: [AGPalette.hex(0x152849, alpha: 0.34), .clear],
                            center: UnitPoint(x: 0.14, y: 0.16),
                            startRadius: 0,
                            endRadius: max(geo.size.width, geo.size.height) * 0.62
                        )
                        RadialGradient(
                            colors: [AGPalette.hex(0x281A37, alpha: 0.28), .clear],
                            center: UnitPoint(x: 0.88, y: 0.84),
                            startRadius: 0,
                            endRadius: max(geo.size.width, geo.size.height) * 0.58
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - shadcn/ui Card & Semantic Badge Modifiers

public struct AGCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 13
    var customBorder: Color? = nil
    var customBg: Color? = nil

    public func body(content: Content) -> some View {
        let p = AGPalette(colorScheme)
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(customBg ?? p.card)
                    .shadow(
                        color: Color.black.opacity(p.isDark ? 0.22 : 0.035),
                        radius: p.isDark ? 4 : 2,
                        x: 0,
                        y: 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(customBorder ?? p.borderCard, lineWidth: 1)
            )
    }
}

public extension View {
    func agCard(cornerRadius: CGFloat = 13, border: Color? = nil, background: Color? = nil) -> some View {
        modifier(AGCardModifier(cornerRadius: cornerRadius, customBorder: border, customBg: background))
    }
}

public struct AGBadge<Leading: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    public let text: String
    public var tone: AGSemanticTone = .zinc
    public var monospaced: Bool = false
    public var capsule: Bool = false
    private let leading: Leading
    private let hasLeading: Bool

    public init(
        _ text: String,
        tone: AGSemanticTone = .zinc,
        monospaced: Bool = false,
        capsule: Bool = false,
        @ViewBuilder leading: () -> Leading
    ) {
        self.text = text
        self.tone = tone
        self.monospaced = monospaced
        self.capsule = capsule
        self.leading = leading()
        self.hasLeading = true
    }

    public var body: some View {
        let p = AGPalette(colorScheme)
        let style = p.toneColors(tone)
        HStack(spacing: 4) {
            if hasLeading {
                leading
            }
            Text(text)
                .font(.system(size: 10.5, weight: .semibold, design: monospaced ? .monospaced : .default))
                .lineLimit(1)
        }
        .foregroundColor(style.fg)
        .padding(.horizontal, capsule ? 8.5 : 6.5)
        .padding(.vertical, 2.5)
        .background(
            Group {
                if capsule {
                    Capsule().fill(style.bg)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(style.bg)
                }
            }
        )
        .overlay(
            Group {
                if capsule {
                    Capsule().stroke(style.border, lineWidth: 0.9)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(style.border, lineWidth: 0.9)
                }
            }
        )
    }
}

public extension AGBadge where Leading == EmptyView {
    init(_ text: String, tone: AGSemanticTone = .zinc, monospaced: Bool = false, capsule: Bool = false) {
        self.text = text
        self.tone = tone
        self.monospaced = monospaced
        self.capsule = capsule
        self.leading = EmptyView()
        self.hasLeading = false
    }
}

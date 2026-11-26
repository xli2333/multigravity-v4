import Foundation
import SwiftUI

// MARK: - Dual Theme System Aligned 1:1 with Antigravity & iPhone App
// Default: Antigravity Pure White (`defaultLight`). Dark: `claude cut` Obsidian (`defaultDark`).

public enum WatchAppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case followAppDefaultLight = "follow_app"
    case light = "light"
    case dark = "dark"

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .followAppDefaultLight: return String(localized: "跟随手机 (默认纯白)")
        case .light: return String(localized: "Antigravity 纯白")
        case .dark: return String(localized: "黑曜深色")
        }
    }

    public func resolvesToDark(phoneThemeMode: String?) -> Bool {
        switch self {
        case .light:
            return false
        case .dark:
            return true
        case .followAppDefaultLight:
            // Follows phone when explicitly set to dark; defaults to Antigravity Pure White otherwise.
            return phoneThemeMode?.lowercased() == "dark"
        }
    }
}

public struct WatchPalette: Sendable, Equatable {
    public let isDark: Bool

    public let canvasBg: Color
    public let cardBg: Color
    public let recessedBg: Color
    public let cardBorder: Color

    public let primaryFg: Color
    public let secondaryFg: Color
    public let mutedFg: Color

    public let geminiFill: Color
    public let geminiText: Color
    public let claudeFill: Color
    public let claudeText: Color

    public let emeraldFill: Color
    public let emeraldText: Color
    public let emeraldSoftBg: Color

    public let amberFill: Color
    public let amberText: Color
    public let amberCardBg: Color
    public let amberCardBorder: Color

    public let roseFill: Color
    public let roseText: Color
    public let roseSoftBg: Color
    public let roseBorder: Color

    /// Antigravity Pure White — Default watchOS appearance matching desktop Antigravity & iOS Light theme.
    public static let antigravityLight = WatchPalette(
        isDark: false,
        canvasBg: Color(red: 0xFA / 255.0, green: 0xFA / 255.0, blue: 0xFB / 255.0),
        cardBg: Color.white,
        recessedBg: Color(red: 0xF4 / 255.0, green: 0xF4 / 255.0, blue: 0xF5 / 255.0),
        cardBorder: Color(red: 0xE4 / 255.0, green: 0xE4 / 255.0, blue: 0xE7 / 255.0),
        primaryFg: Color(red: 0x09 / 255.0, green: 0x09 / 255.0, blue: 0x0B / 255.0),
        secondaryFg: Color(red: 0x52 / 255.0, green: 0x52 / 255.0, blue: 0x5B / 255.0),
        mutedFg: Color(red: 0x71 / 255.0, green: 0x71 / 255.0, blue: 0x7A / 255.0),
        geminiFill: Color(red: 0x25 / 255.0, green: 0x63 / 255.0, blue: 0xEB / 255.0),
        geminiText: Color(red: 0x1D / 255.0, green: 0x4E / 255.0, blue: 0xD8 / 255.0),
        claudeFill: Color(red: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0),
        claudeText: Color(red: 0x9A / 255.0, green: 0x34 / 255.0, blue: 0x12 / 255.0),
        emeraldFill: Color(red: 0x10 / 255.0, green: 0xB9 / 255.0, blue: 0x81 / 255.0),
        emeraldText: Color(red: 0x04 / 255.0, green: 0x78 / 255.0, blue: 0x57 / 255.0),
        emeraldSoftBg: Color(red: 0x10 / 255.0, green: 0xB9 / 255.0, blue: 0x81 / 255.0).opacity(0.12),
        amberFill: Color(red: 0xF5 / 255.0, green: 0x9E / 255.0, blue: 0x0B / 255.0),
        amberText: Color(red: 0xB4 / 255.0, green: 0x53 / 255.0, blue: 0x09 / 255.0),
        amberCardBg: Color(red: 0xFF / 255.0, green: 0xFB / 255.0, blue: 0xEB / 255.0),
        amberCardBorder: Color(red: 0xF5 / 255.0, green: 0x9E / 255.0, blue: 0x0B / 255.0).opacity(0.45),
        roseFill: Color(red: 0xE1 / 255.0, green: 0x1D / 255.0, blue: 0x48 / 255.0),
        roseText: Color(red: 0xBE / 255.0, green: 0x12 / 255.0, blue: 0x3C / 255.0),
        roseSoftBg: Color(red: 0xE1 / 255.0, green: 0x1D / 255.0, blue: 0x48 / 255.0).opacity(0.10),
        roseBorder: Color(red: 0xE1 / 255.0, green: 0x1D / 255.0, blue: 0x48 / 255.0).opacity(0.32)
    )

    /// `claude cut` Obsidian Dark — Exact token match with iOS App's `ThemePresetCatalog.defaultDark`.
    public static let claudeCutDark = WatchPalette(
        isDark: true,
        canvasBg: Color(red: 0x16 / 255.0, green: 0x16 / 255.0, blue: 0x1A / 255.0),
        cardBg: Color(red: 0x24 / 255.0, green: 0x26 / 255.0, blue: 0x29 / 255.0),
        recessedBg: Color(red: 0x1B / 255.0, green: 0x1C / 255.0, blue: 0x20 / 255.0),
        cardBorder: Color(red: 0x36 / 255.0, green: 0x38 / 255.0, blue: 0x40 / 255.0),
        primaryFg: Color(red: 0xFF / 255.0, green: 0xFF / 255.0, blue: 0xFE / 255.0),
        secondaryFg: Color(red: 0xAF / 255.0, green: 0xB8 / 255.0, blue: 0xC7 / 255.0),
        mutedFg: Color(red: 0x8B / 255.0, green: 0x95 / 255.0, blue: 0xA5 / 255.0),
        geminiFill: Color(red: 0x42 / 255.0, green: 0x85 / 255.0, blue: 0xF4 / 255.0),
        geminiText: Color(red: 0x7A / 255.0, green: 0xB3 / 255.0, blue: 0xFF / 255.0),
        claudeFill: Color(red: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0),
        claudeText: Color(red: 0xF5 / 255.0, green: 0xA3 / 255.0, blue: 0x87 / 255.0),
        emeraldFill: Color(red: 0x2C / 255.0, green: 0xB6 / 255.0, blue: 0x7D / 255.0),
        emeraldText: Color(red: 0x5C / 255.0, green: 0xE0 / 255.0, blue: 0xA8 / 255.0),
        emeraldSoftBg: Color(red: 0x2C / 255.0, green: 0xB6 / 255.0, blue: 0x7D / 255.0).opacity(0.20),
        amberFill: Color(red: 0xF5 / 255.0, green: 0x9E / 255.0, blue: 0x0B / 255.0),
        amberText: Color(red: 0xFC / 255.0, green: 0xD3 / 255.0, blue: 0x4D / 255.0),
        amberCardBg: Color(red: 0x24 / 255.0, green: 0x1D / 255.0, blue: 0x14 / 255.0),
        amberCardBorder: Color(red: 0xF5 / 255.0, green: 0x9E / 255.0, blue: 0x0B / 255.0).opacity(0.45),
        roseFill: Color(red: 0xEF / 255.0, green: 0x44 / 255.0, blue: 0x44 / 255.0),
        roseText: Color(red: 0xFD / 255.0, green: 0xA4 / 255.0, blue: 0xAF / 255.0),
        roseSoftBg: Color(red: 0xEF / 255.0, green: 0x44 / 255.0, blue: 0x44 / 255.0).opacity(0.18),
        roseBorder: Color(red: 0xEF / 255.0, green: 0x44 / 255.0, blue: 0x44 / 255.0).opacity(0.36)
    )

    public func quotaColor(for percent: Double) -> (fill: Color, text: Color) {
        if percent >= 50 {
            return (emeraldFill, emeraldText)
        } else if percent >= 20 {
            return (amberFill, amberText)
        } else {
            return (roseFill, roseText)
        }
    }
}

// MARK: - Official Pure-Shape Vector Brand Icons (0% Emoji)

nonisolated enum WatchSVGPathBuilder {
    static func buildPath(from d: String, in rect: CGRect, viewBox: CGFloat = 24.0) -> Path {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
            return Path()
        }
        let scale = min(rect.width, rect.height) / viewBox
        let ox = rect.minX + (rect.width - viewBox * scale) * 0.5
        let oy = rect.minY + (rect.height - viewBox * scale) * 0.5

        var path = Path()
        let chars = Array(d.utf8)
        let n = chars.count
        var i = 0

        func skipSep() {
            while i < n {
                let c = chars[i]
                if c == 32 || c == 44 || c == 10 || c == 13 || c == 9 { i += 1 } else { break }
            }
        }

        func readDouble() -> CGFloat? {
            skipSep()
            guard i < n else { return nil }
            let start = i
            if chars[i] == 45 || chars[i] == 43 { i += 1 }
            var hasDigits = false
            while i < n, chars[i] >= 48 && chars[i] <= 57 { i += 1; hasDigits = true }
            if i < n, chars[i] == 46 {
                i += 1
                while i < n, chars[i] >= 48 && chars[i] <= 57 { i += 1; hasDigits = true }
            }
            guard hasDigits, let s = String(bytes: chars[start..<i], encoding: .utf8), let v = Double(s) else {
                i = start
                return nil
            }
            return CGFloat(v)
        }

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * scale, y: oy + y * scale)
        }

        var currentCmd: UInt8 = 0
        while i < n {
            skipSep()
            guard i < n else { break }
            let c = chars[i]
            if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) {
                currentCmd = c
                i += 1
                if currentCmd == 90 || currentCmd == 122 {
                    path.closeSubpath()
                    continue
                }
            }
            switch currentCmd {
            case 77:
                guard let x = readDouble(), let y = readDouble() else { i += 1; continue }
                path.move(to: pt(x, y))
                currentCmd = 76
            case 76:
                guard let x = readDouble(), let y = readDouble() else { i += 1; continue }
                path.addLine(to: pt(x, y))
            case 67:
                guard let x1 = readDouble(), let y1 = readDouble(),
                      let x2 = readDouble(), let y2 = readDouble(),
                      let x = readDouble(), let y = readDouble() else { i += 1; continue }
                path.addCurve(to: pt(x, y), control1: pt(x1, y1), control2: pt(x2, y2))
            default:
                i += 1
            }
        }
        return path
    }
}

nonisolated public struct WatchGeminiStarShape: Shape {
    private static let pathD = "M11.04 19.32C11.372 20.562 11.703 21.928 11.998 23.999 12 23.999 12 24 12.001 24 12.297 21.928 12.628 20.562 12.96 19.32 13.733 16.503 15.051 14.616 17.28 13.08 18.709 12.063 20.251 12.299 23.991 12.002 23.996 12.002 24 11.998 23.991 11.998 20.251 11.701 18.709 11.937 17.28 10.92 15.051 9.384 13.733 7.497 12.96 4.68 12.628 3.438 12.297 2.072 12.001 0 12 0 12 0.001 11.998 0.001 11.703 2.072 11.372 3.438 11.04 4.68 10.267 7.497 8.949 9.384 6.72 10.92 5.291 11.937 3.749 11.701 0.009 11.998 0 11.998 0.004 12.002 0.009 12.002 3.749 12.299 5.291 12.063 6.72 13.08 8.949 14.616 10.267 16.503 11.04 19.32Z"

    public init() {}
    public func path(in rect: CGRect) -> Path {
        WatchSVGPathBuilder.buildPath(from: Self.pathD, in: rect, viewBox: 24.0)
    }
}

nonisolated public struct WatchClaudeSunburstShape: Shape {
    private static let pathD = "M4.709 15.955L9.429 13.308 9.509 13.078 9.429 12.95 9.199 12.95 8.409 12.902 5.711 12.829 3.372 12.732 1.106 12.61 0.535 12.489 0 11.784 0.055 11.432 0.535 11.111 1.221 11.171 2.741 11.274 5.019 11.432 6.671 11.529 9.12 11.784 9.509 11.784 9.564 11.627 9.43 11.529 9.327 11.432 6.969 9.836 4.419 8.157 3.083 7.185 2.36 6.694 1.996 6.232 1.838 5.224 2.494 4.502 3.375 4.562 3.599 4.623 4.492 5.309 6.399 6.785 8.89 8.618 9.255 8.922 9.4 8.819 9.419 8.746 9.255 8.472 7.9 6.026 6.454 3.536 5.81 2.504 5.64 1.885C5.58 1.63 5.536 1.417 5.536 1.156L6.265 0.143 6.678 0.01 7.674 0.143 8.094 0.507 8.714 1.921 9.716 4.15 11.271 7.18 11.727 8.078 11.97 8.91 12.061 9.165 12.219 9.165 12.219 9.019 12.347 7.313 12.584 5.218 12.814 2.523 12.894 1.763 13.27 0.853 14.017 0.361 14.601 0.641 15.081 1.328 15.014 1.772 14.728 3.623 14.169 6.526 13.805 8.468 14.017 8.468 14.26 8.226 15.245 6.92 16.897 4.856 17.627 4.036 18.477 3.132 19.024 2.701 20.057 2.701 20.817 3.83 20.477 4.996 19.413 6.343 18.532 7.485 17.268 9.185 16.478 10.545 16.551 10.655 16.739 10.635 19.595 10.029 21.138 9.749 22.979 9.434 23.812 9.822 23.903 10.217 23.575 11.024 21.606 11.51 19.297 11.972 15.86 12.785 15.818 12.815 15.867 12.876 17.416 13.022 18.078 13.058 19.7 13.058 22.72 13.283 23.51 13.805 23.983 14.443 23.904 14.928 22.689 15.548 21.049 15.159 17.22 14.249 15.908 13.92 15.726 13.92 15.726 14.03 16.819 15.098 18.825 16.908 21.334 19.238 21.461 19.816 21.139 20.271 20.799 20.222 18.594 18.565 17.743 17.817 15.817 16.197 15.689 16.197 15.689 16.367 16.133 17.016 18.478 20.537 18.6 21.617 18.43 21.97 17.822 22.183 17.154 22.061 15.78 20.136 14.365 17.969 13.223 16.026 13.083 16.106 12.409 23.36 12.093 23.73 11.364 24.01 10.757 23.549 10.435 22.802 10.757 21.326 11.146 19.402 11.461 17.872 11.747 15.972 11.917 15.34 11.905 15.298 11.765 15.316 10.331 17.283 8.151 20.228 6.425 22.073 6.011 22.237 5.294 21.867 5.361 21.205 5.762 20.616 8.149 17.58 9.589 15.698 10.519 14.612 10.513 14.454 10.458 14.454 4.115 18.57 2.985 18.716 2.498 18.26 2.559 17.514 2.79 17.271 4.698 15.959Z"

    public init() {}
    public func path(in rect: CGRect) -> Path {
        WatchSVGPathBuilder.buildPath(from: Self.pathD, in: rect, viewBox: 24.0)
    }
}

public struct WatchBrandIconView: View {
    public let isClaude: Bool
    public let palette: WatchPalette
    public var size: CGFloat = 13

    public init(isClaude: Bool, palette: WatchPalette, size: CGFloat = 13) {
        self.isClaude = isClaude
        self.palette = palette
        self.size = size
    }

    public var body: some View {
        if isClaude {
            WatchClaudeSunburstShape()
                .fill(palette.claudeFill)
                .frame(width: size, height: size)
        } else {
            WatchGeminiStarShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0x3B / 255.0, green: 0x82 / 255.0, blue: 0xF6 / 255.0),
                            Color(red: 0x60 / 255.0, green: 0xA5 / 255.0, blue: 0xFA / 255.0),
                            Color(red: 0x34 / 255.0, green: 0xD3 / 255.0, blue: 0x99 / 255.0)
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
                .frame(width: size, height: size)
        }
    }
}

nonisolated public struct WatchProgressFillShape: Shape {
    public let fraction: CGFloat

    public init(fraction: CGFloat) {
        self.fraction = fraction
    }

    public func path(in rect: CGRect) -> Path {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
            return Path()
        }
        let clamped = max(0, min(1, fraction.isFinite ? fraction : 0))
        let fillW = rect.width * clamped
        guard fillW > 0 else { return Path() }
        let fillRect = CGRect(x: rect.minX, y: rect.minY, width: fillW, height: rect.height)
        let r = min(fillRect.width, fillRect.height) * 0.5
        return Path(roundedRect: fillRect, cornerRadius: r, style: .continuous)
    }
}

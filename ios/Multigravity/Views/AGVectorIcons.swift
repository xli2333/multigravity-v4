import SwiftUI
import CoreGraphics

// MARK: - Multigravity v4.0 Pure Vector Icon & Brand Mark Engine (ZERO EMOJI)

nonisolated public enum AGSVGPathParser {
    public static func buildPath(_ spec: String) -> Path {
        let path = CGMutablePath()
        let tokens = spec.split(separator: " ")
        var idx = 0
        let count = tokens.count

        func nextFloat() -> CGFloat {
            guard idx < count, let val = Double(tokens[idx]) else { return 0 }
            idx += 1
            return CGFloat(val)
        }

        while idx < count {
            let cmd = tokens[idx]
            idx += 1
            switch cmd {
            case "M":
                let x = nextFloat()
                let y = nextFloat()
                path.move(to: CGPoint(x: x, y: y))
            case "L":
                let x = nextFloat()
                let y = nextFloat()
                path.addLine(to: CGPoint(x: x, y: y))
            case "Q":
                let cx = nextFloat()
                let cy = nextFloat()
                let x = nextFloat()
                let y = nextFloat()
                path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
            case "C":
                let c1x = nextFloat()
                let c1y = nextFloat()
                let c2x = nextFloat()
                let c2y = nextFloat()
                let x = nextFloat()
                let y = nextFloat()
                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: c1x, y: c1y),
                    control2: CGPoint(x: c2x, y: c2y)
                )
            case "Z":
                path.closeSubpath()
            default:
                break
            }
        }
        return Path(path)
    }
}

nonisolated public enum AGBrandVectorPaths {
    public static let geminiPath: Path = AGSVGPathParser.buildPath(
        "M 11.0400 19.3200 Q 12.0000 21.5100 12.0000 24.0000 Q 12.0000 21.5100 12.9300 19.3200 Q 13.8900 17.1300 15.5100 15.5100 Q 17.1300 13.8900 19.3200 12.9600 Q 21.5100 12.0000 24.0000 12.0000 Q 21.5100 12.0000 19.3200 11.0700 C 17.8990 10.4573 16.6064 9.5820 15.5100 8.4900 C 14.4180 7.3936 13.5427 6.1010 12.9300 4.6800 Q 12.0000 2.4900 12.0000 0.0000 Q 12.0000 2.4900 11.0400 4.6800 Q 10.1100 6.8700 8.4900 8.4900 C 7.3936 9.5820 6.1010 10.4573 4.6800 11.0700 Q 2.4900 12.0000 0.0000 12.0000 Q 2.4900 12.0000 4.6800 12.9600 Q 6.8700 13.8900 8.4900 15.5100 Q 10.1100 17.1300 11.0400 19.3200 Z"
    )

    public static let claudePath: Path = AGSVGPathParser.buildPath(
        "M 4.7144 15.9555 L 9.4318 13.3084 L 9.5108 13.0777 L 9.4318 12.9502 L 9.2011 12.9502 L 8.4118 12.9016 L 5.7162 12.8287 L 3.3787 12.7316 L 1.1141 12.6102 L 0.5434 12.4887 L 0.0091 11.7845 L 0.0637 11.4323 L 0.5434 11.1105 L 1.2294 11.1713 L 2.7473 11.2745 L 5.0240 11.4323 L 6.6754 11.5295 L 9.1222 11.7845 L 9.5108 11.7845 L 9.5654 11.6266 L 9.4318 11.5295 L 9.3286 11.4323 L 6.9730 9.8356 L 4.4230 8.1477 L 3.0874 7.1763 L 2.3649 6.6845 L 2.0006 6.2231 L 1.8428 5.2153 L 2.4985 4.4928 L 3.3788 4.5535 L 3.6034 4.6142 L 4.4959 5.3002 L 6.4023 6.7756 L 8.8916 8.6092 L 9.2559 8.9127 L 9.4016 8.8095 L 9.4198 8.7367 L 9.2558 8.4634 L 7.9019 6.0167 L 6.4569 3.5274 L 5.8134 2.4954 L 5.6434 1.8760 C 5.5827 1.6210 5.5402 1.4086 5.5402 1.1475 L 6.2870 0.1335 L 6.6997 0.0000 L 7.6954 0.1336 L 8.1144 0.4978 L 8.7336 1.9125 L 9.7354 4.1407 L 11.2897 7.1703 L 11.7450 8.0688 L 11.9879 8.9006 L 12.0789 9.1556 L 12.2368 9.1556 L 12.2368 9.0099 L 12.3643 7.3039 L 12.6011 5.2092 L 12.8318 2.5135 L 12.9107 1.7546 L 13.2871 0.8439 L 14.0339 0.3521 L 14.6167 0.6314 L 15.0964 1.3174 L 15.0296 1.7607 L 14.7443 3.6124 L 14.1857 6.5145 L 13.8214 8.4574 L 14.0339 8.4574 L 14.2768 8.2145 L 15.2603 6.9092 L 16.9117 4.8449 L 17.6403 4.0253 L 18.4903 3.1207 L 19.0367 2.6896 L 20.0688 2.6896 L 20.8278 3.8189 L 20.4878 4.9846 L 19.4253 6.3324 L 18.5449 7.4738 L 17.2821 9.1738 L 16.4928 10.5338 L 16.5657 10.6431 L 16.7539 10.6248 L 19.6074 10.0178 L 21.1495 9.7384 L 22.9891 9.4227 L 23.8209 9.8113 L 23.9119 10.2059 L 23.5841 11.0134 L 21.6171 11.4991 L 19.3099 11.9605 L 15.8735 12.7741 L 15.8310 12.8045 L 15.8796 12.8652 L 17.4278 13.0109 L 18.0896 13.0473 L 19.7106 13.0473 L 22.7281 13.2720 L 23.5173 13.7940 L 23.9909 14.4316 L 23.9119 14.9173 L 22.6977 15.5366 L 21.0584 15.1480 L 17.2334 14.2373 L 15.9221 13.9094 L 15.7399 13.9094 L 15.7399 14.0187 L 16.8328 15.0873 L 18.8363 16.8965 L 21.3438 19.2279 L 21.4713 19.8047 L 21.1495 20.2601 L 20.8095 20.2115 L 18.6056 18.5540 L 17.7556 17.8072 L 15.8310 16.1862 L 15.7035 16.1862 L 15.7035 16.3562 L 16.1467 17.0058 L 18.4903 20.5272 L 18.6117 21.6079 L 18.4417 21.9600 L 17.8346 22.1725 L 17.1667 22.0511 L 15.7946 20.1265 L 14.3800 17.9590 L 13.2386 16.0162 L 13.0989 16.0952 L 12.4249 23.3504 L 12.1093 23.7207 L 11.3807 24.0000 L 10.7736 23.5386 L 10.4518 22.7918 L 10.7736 21.3165 L 11.1622 19.3919 L 11.4779 17.8619 L 11.7632 15.9615 L 11.9332 15.3301 L 11.9211 15.2876 L 11.7814 15.3058 L 10.3486 17.2730 L 8.1690 20.2176 L 6.4447 22.0632 L 6.0319 22.2272 L 5.3155 21.8568 L 5.3822 21.1950 L 5.7830 20.6061 L 8.1690 17.5704 L 9.6079 15.6884 L 10.5369 14.6016 L 10.5307 14.4437 L 10.4761 14.4437 L 4.1376 18.5601 L 3.0083 18.7058 L 2.5226 18.2504 L 2.5834 17.5037 L 2.8141 17.2608 L 4.7205 15.9494 Z"
    )

    public static let multigravityPath: Path = AGSVGPathParser.buildPath(
        "M 416.4700 205.1400 C 415.0900 204.6900 413.6600 204.9400 412.2400 204.2600 C 405.5700 201.0400 401.4400 192.7300 397.9800 186.5600 C 389.5200 171.4900 383.8800 154.7300 378.0200 138.5300 C 364.6100 101.4400 348.7400 52.7800 318.5500 25.9300 C 311.2800 19.4600 302.8100 14.4200 293.9000 10.5600 C 289.8600 8.8100 285.8000 6.9300 281.5100 5.9000 C 272.8900 3.8400 264.3400 3.3500 255.5000 3.6800 C 244.8000 4.0900 234.3300 6.8400 224.4800 10.9800 C 190.2300 25.3700 170.2300 63.7300 156.5300 96.0700 C 150.2900 110.8100 145.3200 125.7500 140.4800 140.9900 C 120.9800 202.3500 109.1700 265.8200 89.6100 327.1500 C 79.0200 360.3300 66.7200 393.9200 47.9400 423.4600 C 41.6700 433.3200 34.7700 442.8000 27.2200 451.7200 C 21.5600 458.3900 15.2900 464.5700 10.2800 471.7800 C 2.1400 483.4700 -0.5100 499.5700 14.8900 506.6500 C 25.5600 511.5600 37.2800 509.2800 47.8600 505.4600 C 68.0800 498.1600 85.3900 483.9700 100.3000 468.7800 C 138.6900 429.7000 160.2700 380.4300 187.0600 333.5400 C 199.9700 310.9500 219.8600 278.2800 245.4300 268.9500 C 278.6200 256.8600 298.3200 292.2100 309.4600 317.0100 C 327.5300 357.2500 337.9100 400.6000 360.8900 438.6000 C 372.7900 458.2800 391.1900 476.5200 415.5000 477.1500 C 438.6500 477.7500 456.1200 460.5000 468.2400 442.7300 C 486.6700 415.7000 496.7800 383.8900 507.8900 353.3900 C 512.0200 342.0500 516.5600 330.8000 521.1600 319.6400 C 529.8200 298.5800 546.8300 265.7700 573.5000 266.2500 C 600.9100 266.7500 621.9200 295.1700 635.1100 316.3900 C 667.1800 367.9500 689.6600 425.6900 732.9700 469.5200 C 748.5600 485.2900 766.7800 499.4400 788.0400 506.4500 C 798.6200 509.9400 811.9600 510.9600 821.2700 503.7600 C 831.9700 495.4800 827.7300 481.7000 821.2800 472.2300 C 813.9300 461.4300 804.2000 452.5700 796.4000 442.1000 C 782.4200 423.3300 771.2000 403.0700 761.9000 381.6100 C 723.3200 292.6400 714.2100 193.8300 678.6700 104.8300 C 662.4400 64.1900 640.5000 18.2900 594.3100 6.1500 C 585.2900 3.7800 576.1700 3.0300 566.8600 3.4600 C 556.7400 3.9300 547.2100 6.3700 537.9300 10.4200 C 532.1000 12.9600 526.2500 15.8200 521.0900 19.5700 C 485.9000 45.1300 467.7100 99.6200 453.6800 139.2300 C 448.1100 154.9400 442.0500 173.6800 433.3100 187.8400 C 429.9200 193.3300 426.3200 200.7000 420.4700 203.9600 C 419.1700 204.6900 417.7500 204.6100 416.4700 205.1400 Z"
    )
}

nonisolated public struct ScaledCGPathShape: Shape {
    public let basePath: Path
    public let viewBoxWidth: CGFloat
    public let viewBoxHeight: CGFloat

    public init(path: Path, viewBoxWidth: CGFloat = 24, viewBoxHeight: CGFloat = 24) {
        self.basePath = path
        self.viewBoxWidth = viewBoxWidth
        self.viewBoxHeight = viewBoxHeight
    }

    public func path(in rect: CGRect) -> Path {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0,
              viewBoxWidth > 0, viewBoxHeight > 0 else {
            return Path()
        }
        let sx = rect.width / viewBoxWidth
        let sy = rect.height / viewBoxHeight
        let scale = min(sx, sy)
        let ox = rect.minX + (rect.width - viewBoxWidth * scale) / 2.0
        let oy = rect.minY + (rect.height - viewBoxHeight * scale) / 2.0
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: ox, y: oy))
        return basePath.applying(transform)
    }
}

// MARK: - Official Google Gemini & Anthropic Claude Vector Views

public struct GeminiBrandIcon: View {
    public var size: CGFloat = 14

    public init(size: CGFloat = 14) {
        self.size = size
    }

    public var body: some View {
        ScaledCGPathShape(path: AGBrandVectorPaths.geminiPath, viewBoxWidth: 24, viewBoxHeight: 24)
            .fill(
                LinearGradient(
                    colors: [
                        AGPalette.hex(0x3B82F6),
                        AGPalette.hex(0x60A5FA),
                        AGPalette.hex(0x34D399)
                    ],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

public struct ClaudeBrandIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    public var size: CGFloat = 14
    public var customColor: Color? = nil

    public init(size: CGFloat = 14, color: Color? = nil) {
        self.size = size
        self.customColor = color
    }

    public var body: some View {
        let fill = customColor ?? (colorScheme == .dark ? AGPalette.hex(0xF5A387) : AGPalette.hex(0xD97757))
        ScaledCGPathShape(path: AGBrandVectorPaths.claudePath, viewBoxWidth: 24, viewBoxHeight: 24)
            .fill(fill)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

public struct MultigravityPrismSquircle: View {
    @Environment(\.colorScheme) private var colorScheme
    public var boxSize: CGFloat = 28

    public init(boxSize: CGFloat = 28) {
        self.boxSize = boxSize
    }

    public init(size: CGFloat) {
        self.boxSize = size
    }

    public var body: some View {
        let p = AGPalette(colorScheme)
        let iconW = boxSize * 0.72
        let iconH = iconW * 0.62
        let radius = boxSize * 0.28
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(p.card)
                .shadow(color: Color.black.opacity(p.isDark ? 0.28 : 0.06), radius: 2, x: 0, y: 1)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(p.borderCard, lineWidth: 1)
            ScaledCGPathShape(path: AGBrandVectorPaths.multigravityPath, viewBoxWidth: 832, viewBoxHeight: 516)
                .fill(
                    LinearGradient(
                        colors: [
                            AGPalette.hex(0x10B981),
                            AGPalette.hex(0x38BDF8),
                            AGPalette.hex(0x4285F4),
                            AGPalette.hex(0xF59E0B),
                            AGPalette.hex(0xEC4899)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: iconW, height: iconH)
        }
        .frame(width: boxSize, height: boxSize)
        .accessibilityHidden(true)
    }
}

public struct ModelProviderBrandIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    public let kind: ModelProviderKind
    public var size: CGFloat = 13

    public init(kind: ModelProviderKind, size: CGFloat = 13) {
        self.kind = kind
        self.size = size
    }

    public init(modelId: String, size: CGFloat = 13) {
        self.kind = ModelDefaultsLogic.providerKind(forID: modelId)
        self.size = size
    }

    public var body: some View {
        switch kind {
        case .gemini:
            GeminiBrandIcon(size: size)
        case .claude:
            ClaudeBrandIcon(size: size)
        case .orchestrator:
            AGLinearIcon(.layers, size: size, color: AGPalette.violetText(colorScheme), lineWidth: 2.0)
        case .other:
            AGLinearIcon(.flask, size: size, color: AGPalette.amberText(colorScheme), lineWidth: 2.0)
        }
    }
}

// MARK: - Uniform 1.9pt Stroke Linear Engineering Vector Icons (24x24 ViewBox)

public enum AGIconKind: Sendable {
    case chat
    case grid
    case gauge
    case settings
    case search
    case folder
    case clock
    case plug
    case cpu
    case terminal
    case branch
    case pullRequest
    case fileText
    case video
    case pin
    case bolt
    case shield
    case lock
    case eye
    case eyeOff
    case share
    case mic
    case plus
    case arrowUp
    case chevronLeft
    case chevronDown
    case chevronRight
    case check
    case play
    case more
    case flask
    case smartphone
    case monitor
    case camera
    case image
    case scan
    case archive
    case phone
    case qr
    case sparkles
    case layers
    case atSign
    case slash
    case alert
    case alertTriangle
    case refresh
    case gitBranch
    case chevronUp
    case download
    case qrCode
    case link
    case globe
    case bell
    case trash
    case code
    case paperclip
    case stop
    case edit
    case close
}

public struct AGLinearIcon: View {
    public typealias Kind = AGIconKind
    public let kind: AGIconKind
    public var size: CGFloat = 15
    public var color: Color? = nil
    public var lineWidth: CGFloat = 1.95

    public init(_ kind: AGIconKind, size: CGFloat = 15, color: Color? = nil, lineWidth: CGFloat = 1.95) {
        self.kind = kind
        self.size = size
        self.color = color
        self.lineWidth = lineWidth
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 24.0
            let ox = (canvasSize.width - 24.0 * scale) / 2.0
            let oy = (canvasSize.height - 24.0 * scale) / 2.0
            var path = Self.vectorPath(for: kind)
            let transform = CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(translationX: ox, y: oy))
            path = path.applying(transform)
            let resolved = color ?? .primary
            let stroke = StrokeStyle(
                lineWidth: max(1.1, lineWidth * scale),
                lineCap: .round,
                lineJoin: .round
            )
            context.stroke(path, with: .color(resolved), style: stroke)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // swiftlint:disable cyclomatic_complexity function_body_length
    private static func vectorPath(for kind: AGIconKind) -> Path {
        var p = Path()
        switch kind {
        case .chat:
            p.move(to: CGPoint(x: 21, y: 15))
            p.addArc(center: CGPoint(x: 19, y: 15), radius: 2, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: 7, y: 17))
            p.addLine(to: CGPoint(x: 3, y: 21))
            p.addLine(to: CGPoint(x: 3, y: 5))
            p.addArc(center: CGPoint(x: 5, y: 5), radius: 2, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            p.addLine(to: CGPoint(x: 19, y: 3))
            p.addArc(center: CGPoint(x: 19, y: 5), radius: 2, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            p.closeSubpath()

        case .grid:
            p.addRoundedRect(in: CGRect(x: 3, y: 3, width: 7, height: 7), cornerSize: CGSize(width: 1.5, height: 1.5))
            p.addRoundedRect(in: CGRect(x: 14, y: 3, width: 7, height: 7), cornerSize: CGSize(width: 1.5, height: 1.5))
            p.addRoundedRect(in: CGRect(x: 3, y: 14, width: 7, height: 7), cornerSize: CGSize(width: 1.5, height: 1.5))
            p.addRoundedRect(in: CGRect(x: 14, y: 14, width: 7, height: 7), cornerSize: CGSize(width: 1.5, height: 1.5))

        case .gauge:
            p.addArc(center: CGPoint(x: 12, y: 14), radius: 9.5, startAngle: .degrees(150), endAngle: .degrees(390), clockwise: false)
            p.move(to: CGPoint(x: 12, y: 14))
            p.addLine(to: CGPoint(x: 16.2, y: 9.8))

        case .settings:
            p.addEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6))
            for i in 0..<8 {
                let a = Double(i) * (.pi / 4.0)
                let c = cos(a), s = sin(a)
                p.move(to: CGPoint(x: 12 + 6.4 * c, y: 12 + 6.4 * s))
                p.addLine(to: CGPoint(x: 12 + 9.4 * c, y: 12 + 9.4 * s))
            }
            p.addEllipse(in: CGRect(x: 5.2, y: 5.2, width: 13.6, height: 13.6))

        case .search:
            p.addEllipse(in: CGRect(x: 3.5, y: 3.5, width: 15, height: 15))
            p.move(to: CGPoint(x: 20.5, y: 20.5))
            p.addLine(to: CGPoint(x: 16.4, y: 16.4))

        case .folder:
            p.move(to: CGPoint(x: 3, y: 6))
            p.addLine(to: CGPoint(x: 9, y: 6))
            p.addLine(to: CGPoint(x: 11, y: 8.5))
            p.addLine(to: CGPoint(x: 21, y: 8.5))
            p.addLine(to: CGPoint(x: 21, y: 19))
            p.addLine(to: CGPoint(x: 3, y: 19))
            p.closeSubpath()

        case .clock:
            p.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            p.move(to: CGPoint(x: 12, y: 7))
            p.addLine(to: CGPoint(x: 12, y: 12))
            p.addLine(to: CGPoint(x: 15.5, y: 14))

        case .plug:
            p.move(to: CGPoint(x: 9, y: 2.5)); p.addLine(to: CGPoint(x: 9, y: 8))
            p.move(to: CGPoint(x: 15, y: 2.5)); p.addLine(to: CGPoint(x: 15, y: 8))
            p.move(to: CGPoint(x: 6, y: 8)); p.addLine(to: CGPoint(x: 18, y: 8))
            p.addLine(to: CGPoint(x: 18, y: 12.5))
            p.addArc(center: CGPoint(x: 12, y: 12.5), radius: 6, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.closeSubpath()
            p.move(to: CGPoint(x: 12, y: 18.5)); p.addLine(to: CGPoint(x: 12, y: 22))

        case .cpu:
            p.addRoundedRect(in: CGRect(x: 5, y: 5, width: 14, height: 14), cornerSize: CGSize(width: 2, height: 2))
            p.addRect(CGRect(x: 9.2, y: 9.2, width: 5.6, height: 5.6))
            p.move(to: CGPoint(x: 9, y: 2)); p.addLine(to: CGPoint(x: 9, y: 5))
            p.move(to: CGPoint(x: 15, y: 2)); p.addLine(to: CGPoint(x: 15, y: 5))
            p.move(to: CGPoint(x: 9, y: 19)); p.addLine(to: CGPoint(x: 9, y: 22))
            p.move(to: CGPoint(x: 15, y: 19)); p.addLine(to: CGPoint(x: 15, y: 22))
            p.move(to: CGPoint(x: 2, y: 9)); p.addLine(to: CGPoint(x: 5, y: 9))
            p.move(to: CGPoint(x: 2, y: 15)); p.addLine(to: CGPoint(x: 5, y: 15))
            p.move(to: CGPoint(x: 19, y: 9)); p.addLine(to: CGPoint(x: 22, y: 9))
            p.move(to: CGPoint(x: 19, y: 15)); p.addLine(to: CGPoint(x: 22, y: 15))

        case .terminal:
            p.move(to: CGPoint(x: 4, y: 17))
            p.addLine(to: CGPoint(x: 10, y: 11))
            p.addLine(to: CGPoint(x: 4, y: 5))
            p.move(to: CGPoint(x: 12, y: 19))
            p.addLine(to: CGPoint(x: 20, y: 19))

        case .branch, .gitBranch:
            p.move(to: CGPoint(x: 6, y: 3)); p.addLine(to: CGPoint(x: 6, y: 15))
            p.addEllipse(in: CGRect(x: 15, y: 3, width: 6, height: 6))
            p.addEllipse(in: CGRect(x: 3, y: 15, width: 6, height: 6))
            p.move(to: CGPoint(x: 18, y: 9))
            p.addQuadCurve(to: CGPoint(x: 9, y: 18), control: CGPoint(x: 18, y: 18))

        case .pullRequest:
            p.addEllipse(in: CGRect(x: 3, y: 3, width: 6, height: 6))
            p.addEllipse(in: CGRect(x: 15, y: 15, width: 6, height: 6))
            p.move(to: CGPoint(x: 6, y: 9)); p.addLine(to: CGPoint(x: 6, y: 21))
            p.move(to: CGPoint(x: 13, y: 6)); p.addLine(to: CGPoint(x: 16, y: 6))
            p.addQuadCurve(to: CGPoint(x: 18, y: 8), control: CGPoint(x: 18, y: 6))
            p.addLine(to: CGPoint(x: 18, y: 15))

        case .fileText:
            p.move(to: CGPoint(x: 14, y: 2.5))
            p.addLine(to: CGPoint(x: 6, y: 2.5))
            p.addLine(to: CGPoint(x: 6, y: 21.5))
            p.addLine(to: CGPoint(x: 18, y: 21.5))
            p.addLine(to: CGPoint(x: 18, y: 7))
            p.closeSubpath()
            p.move(to: CGPoint(x: 13.5, y: 2.5)); p.addLine(to: CGPoint(x: 13.5, y: 7.5)); p.addLine(to: CGPoint(x: 18, y: 7.5))
            p.move(to: CGPoint(x: 9, y: 12.5)); p.addLine(to: CGPoint(x: 15, y: 12.5))
            p.move(to: CGPoint(x: 9, y: 16.5)); p.addLine(to: CGPoint(x: 13.5, y: 16.5))

        case .video:
            p.addRoundedRect(in: CGRect(x: 2.5, y: 5.5, width: 13.5, height: 13), cornerSize: CGSize(width: 2, height: 2))
            p.move(to: CGPoint(x: 16, y: 10.2))
            p.addLine(to: CGPoint(x: 21.5, y: 7))
            p.addLine(to: CGPoint(x: 21.5, y: 17))
            p.addLine(to: CGPoint(x: 16, y: 13.8))

        case .pin:
            p.move(to: CGPoint(x: 12, y: 16.5)); p.addLine(to: CGPoint(x: 12, y: 22))
            p.move(to: CGPoint(x: 5.5, y: 16.5)); p.addLine(to: CGPoint(x: 18.5, y: 16.5))
            p.addLine(to: CGPoint(x: 15.5, y: 12)); p.addLine(to: CGPoint(x: 15.5, y: 5))
            p.addLine(to: CGPoint(x: 8.5, y: 5)); p.addLine(to: CGPoint(x: 8.5, y: 12))
            p.closeSubpath()

        case .bolt:
            p.move(to: CGPoint(x: 13, y: 2.5))
            p.addLine(to: CGPoint(x: 4, y: 13.5))
            p.addLine(to: CGPoint(x: 11.8, y: 13.5))
            p.addLine(to: CGPoint(x: 11, y: 21.5))
            p.addLine(to: CGPoint(x: 20, y: 10.5))
            p.addLine(to: CGPoint(x: 12.2, y: 10.5))
            p.closeSubpath()

        case .shield:
            p.move(to: CGPoint(x: 12, y: 2.5))
            p.addLine(to: CGPoint(x: 4.5, y: 5.5))
            p.addLine(to: CGPoint(x: 4.5, y: 11.5))
            p.addQuadCurve(to: CGPoint(x: 12, y: 21.5), control: CGPoint(x: 4.5, y: 18))
            p.addQuadCurve(to: CGPoint(x: 19.5, y: 11.5), control: CGPoint(x: 19.5, y: 18))
            p.addLine(to: CGPoint(x: 19.5, y: 5.5))
            p.closeSubpath()
            p.move(to: CGPoint(x: 9, y: 12)); p.addLine(to: CGPoint(x: 11.2, y: 14.2)); p.addLine(to: CGPoint(x: 15.2, y: 10))

        case .lock:
            p.addRoundedRect(in: CGRect(x: 4.5, y: 11, width: 15, height: 10), cornerSize: CGSize(width: 2, height: 2))
            p.move(to: CGPoint(x: 8, y: 11))
            p.addLine(to: CGPoint(x: 8, y: 7.2))
            p.addArc(center: CGPoint(x: 12, y: 7.2), radius: 4, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: 16, y: 11))

        case .eye:
            p.move(to: CGPoint(x: 2, y: 12))
            p.addQuadCurve(to: CGPoint(x: 22, y: 12), control: CGPoint(x: 12, y: 3))
            p.addQuadCurve(to: CGPoint(x: 2, y: 12), control: CGPoint(x: 12, y: 21))
            p.addEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6))

        case .eyeOff:
            p.move(to: CGPoint(x: 2, y: 12))
            p.addQuadCurve(to: CGPoint(x: 22, y: 12), control: CGPoint(x: 12, y: 3))
            p.addQuadCurve(to: CGPoint(x: 2, y: 12), control: CGPoint(x: 12, y: 21))
            p.move(to: CGPoint(x: 3.5, y: 3.5)); p.addLine(to: CGPoint(x: 20.5, y: 20.5))

        case .share:
            p.move(to: CGPoint(x: 4.5, y: 12.5)); p.addLine(to: CGPoint(x: 4.5, y: 20)); p.addLine(to: CGPoint(x: 19.5, y: 20)); p.addLine(to: CGPoint(x: 19.5, y: 12.5))
            p.move(to: CGPoint(x: 16, y: 6.5)); p.addLine(to: CGPoint(x: 12, y: 2.5)); p.addLine(to: CGPoint(x: 8, y: 6.5))
            p.move(to: CGPoint(x: 12, y: 2.5)); p.addLine(to: CGPoint(x: 12, y: 15))

        case .mic:
            p.addRoundedRect(in: CGRect(x: 9, y: 2.5, width: 6, height: 10.5), cornerSize: CGSize(width: 3, height: 3))
            p.addArc(center: CGPoint(x: 12, y: 10), radius: 6.5, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.move(to: CGPoint(x: 12, y: 16.5)); p.addLine(to: CGPoint(x: 12, y: 21))

        case .plus:
            p.move(to: CGPoint(x: 12, y: 5)); p.addLine(to: CGPoint(x: 12, y: 19))
            p.move(to: CGPoint(x: 5, y: 12)); p.addLine(to: CGPoint(x: 19, y: 12))

        case .arrowUp:
            p.move(to: CGPoint(x: 12, y: 19)); p.addLine(to: CGPoint(x: 12, y: 5))
            p.move(to: CGPoint(x: 5.5, y: 11.5)); p.addLine(to: CGPoint(x: 12, y: 5)); p.addLine(to: CGPoint(x: 18.5, y: 11.5))

        case .chevronLeft:
            p.move(to: CGPoint(x: 15, y: 18)); p.addLine(to: CGPoint(x: 9, y: 12)); p.addLine(to: CGPoint(x: 15, y: 6))

        case .chevronDown:
            p.move(to: CGPoint(x: 6, y: 9)); p.addLine(to: CGPoint(x: 12, y: 15)); p.addLine(to: CGPoint(x: 18, y: 9))

        case .chevronRight:
            p.move(to: CGPoint(x: 9, y: 18)); p.addLine(to: CGPoint(x: 15, y: 12)); p.addLine(to: CGPoint(x: 9, y: 6))

        case .check:
            p.move(to: CGPoint(x: 20, y: 6)); p.addLine(to: CGPoint(x: 9, y: 17)); p.addLine(to: CGPoint(x: 4, y: 12))

        case .play:
            p.move(to: CGPoint(x: 6.5, y: 4.5)); p.addLine(to: CGPoint(x: 19.5, y: 12)); p.addLine(to: CGPoint(x: 6.5, y: 19.5)); p.closeSubpath()

        case .more:
            p.addEllipse(in: CGRect(x: 4, y: 11, width: 2, height: 2))
            p.addEllipse(in: CGRect(x: 11, y: 11, width: 2, height: 2))
            p.addEllipse(in: CGRect(x: 18, y: 11, width: 2, height: 2))

        case .flask:
            p.move(to: CGPoint(x: 8.5, y: 2.5)); p.addLine(to: CGPoint(x: 15.5, y: 2.5))
            p.move(to: CGPoint(x: 10, y: 2.5)); p.addLine(to: CGPoint(x: 10, y: 9)); p.addLine(to: CGPoint(x: 5, y: 18.5))
            p.addLine(to: CGPoint(x: 19, y: 18.5)); p.addLine(to: CGPoint(x: 14, y: 9)); p.addLine(to: CGPoint(x: 14, y: 2.5))
            p.move(to: CGPoint(x: 7, y: 14.5)); p.addLine(to: CGPoint(x: 17, y: 14.5))

        case .smartphone:
            p.addRoundedRect(in: CGRect(x: 6, y: 2.5, width: 12, height: 19), cornerSize: CGSize(width: 2.4, height: 2.4))
            p.move(to: CGPoint(x: 11.2, y: 18)); p.addLine(to: CGPoint(x: 12.8, y: 18))

        case .monitor:
            p.addRoundedRect(in: CGRect(x: 2.5, y: 3.5, width: 19, height: 13), cornerSize: CGSize(width: 2, height: 2))
            p.move(to: CGPoint(x: 8, y: 20.5)); p.addLine(to: CGPoint(x: 16, y: 20.5))
            p.move(to: CGPoint(x: 12, y: 16.5)); p.addLine(to: CGPoint(x: 12, y: 20.5))

        case .camera:
            p.move(to: CGPoint(x: 3, y: 8)); p.addLine(to: CGPoint(x: 7, y: 8)); p.addLine(to: CGPoint(x: 9, y: 5))
            p.addLine(to: CGPoint(x: 15, y: 5)); p.addLine(to: CGPoint(x: 17, y: 8)); p.addLine(to: CGPoint(x: 21, y: 8))
            p.addLine(to: CGPoint(x: 21, y: 19)); p.addLine(to: CGPoint(x: 3, y: 19)); p.closeSubpath()
            p.addEllipse(in: CGRect(x: 9, y: 10.5, width: 6, height: 6))

        case .image:
            p.addRoundedRect(in: CGRect(x: 3, y: 3, width: 18, height: 18), cornerSize: CGSize(width: 2, height: 2))
            p.addEllipse(in: CGRect(x: 7, y: 7, width: 3, height: 3))
            p.move(to: CGPoint(x: 21, y: 15)); p.addLine(to: CGPoint(x: 16, y: 10)); p.addLine(to: CGPoint(x: 5, y: 21))

        case .scan:
            p.move(to: CGPoint(x: 3, y: 7)); p.addLine(to: CGPoint(x: 3, y: 4)); p.addLine(to: CGPoint(x: 6, y: 4))
            p.move(to: CGPoint(x: 18, y: 4)); p.addLine(to: CGPoint(x: 21, y: 4)); p.addLine(to: CGPoint(x: 21, y: 7))
            p.move(to: CGPoint(x: 21, y: 17)); p.addLine(to: CGPoint(x: 21, y: 20)); p.addLine(to: CGPoint(x: 18, y: 20))
            p.move(to: CGPoint(x: 6, y: 20)); p.addLine(to: CGPoint(x: 3, y: 20)); p.addLine(to: CGPoint(x: 3, y: 17))
            p.move(to: CGPoint(x: 7, y: 12)); p.addLine(to: CGPoint(x: 17, y: 12))

        case .archive:
            p.addRoundedRect(in: CGRect(x: 2.5, y: 3.5, width: 19, height: 4.5), cornerSize: CGSize(width: 1, height: 1))
            p.move(to: CGPoint(x: 4.5, y: 8)); p.addLine(to: CGPoint(x: 4.5, y: 20)); p.addLine(to: CGPoint(x: 19.5, y: 20)); p.addLine(to: CGPoint(x: 19.5, y: 8))
            p.move(to: CGPoint(x: 10, y: 12.5)); p.addLine(to: CGPoint(x: 14, y: 12.5))

        case .phone:
            p.move(to: CGPoint(x: 6.5, y: 3.5)); p.addLine(to: CGPoint(x: 9.5, y: 3.5)); p.addLine(to: CGPoint(x: 11, y: 8))
            p.addLine(to: CGPoint(x: 8.8, y: 10)); p.addQuadCurve(to: CGPoint(x: 14, y: 15.2), control: CGPoint(x: 10.5, y: 13.5))
            p.addLine(to: CGPoint(x: 16, y: 13)); p.addLine(to: CGPoint(x: 20.5, y: 14.5)); p.addLine(to: CGPoint(x: 20.5, y: 18))
            p.addQuadCurve(to: CGPoint(x: 3.5, y: 6.5), control: CGPoint(x: 6, y: 20))
            p.closeSubpath()

        case .qr, .qrCode:
            p.addRect(CGRect(x: 3.5, y: 3.5, width: 6.5, height: 6.5))
            p.addRect(CGRect(x: 14, y: 3.5, width: 6.5, height: 6.5))
            p.addRect(CGRect(x: 3.5, y: 14, width: 6.5, height: 6.5))
            p.addRect(CGRect(x: 14, y: 14, width: 3, height: 3))
            p.addRect(CGRect(x: 17.5, y: 17.5, width: 3, height: 3))

        case .sparkles:
            p.move(to: CGPoint(x: 12, y: 3)); p.addLine(to: CGPoint(x: 13.8, y: 8.2)); p.addLine(to: CGPoint(x: 19, y: 10))
            p.addLine(to: CGPoint(x: 13.8, y: 11.8)); p.addLine(to: CGPoint(x: 12, y: 17)); p.addLine(to: CGPoint(x: 10.2, y: 11.8))
            p.addLine(to: CGPoint(x: 5, y: 10)); p.addLine(to: CGPoint(x: 10.2, y: 8.2)); p.closeSubpath()
            p.move(to: CGPoint(x: 19, y: 15.5)); p.addLine(to: CGPoint(x: 19, y: 20.5))
            p.move(to: CGPoint(x: 16.5, y: 18)); p.addLine(to: CGPoint(x: 21.5, y: 18))

        case .layers:
            p.move(to: CGPoint(x: 12, y: 3)); p.addLine(to: CGPoint(x: 2.5, y: 7.5)); p.addLine(to: CGPoint(x: 12, y: 12)); p.addLine(to: CGPoint(x: 21.5, y: 7.5)); p.closeSubpath()
            p.move(to: CGPoint(x: 2.5, y: 12.5)); p.addLine(to: CGPoint(x: 12, y: 17)); p.addLine(to: CGPoint(x: 21.5, y: 12.5))
            p.move(to: CGPoint(x: 2.5, y: 17)); p.addLine(to: CGPoint(x: 12, y: 21.5)); p.addLine(to: CGPoint(x: 21.5, y: 17))

        case .atSign:
            p.addEllipse(in: CGRect(x: 8, y: 8, width: 8, height: 8))
            p.move(to: CGPoint(x: 16, y: 8)); p.addLine(to: CGPoint(x: 16, y: 13.5))
            p.addArc(center: CGPoint(x: 18.5, y: 13.5), radius: 2.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            p.addLine(to: CGPoint(x: 21, y: 12))
            p.addArc(center: CGPoint(x: 12, y: 12), radius: 9, startAngle: .degrees(0), endAngle: .degrees(315), clockwise: true)

        case .slash:
            p.move(to: CGPoint(x: 16, y: 4)); p.addLine(to: CGPoint(x: 8, y: 20))

        case .alert, .alertTriangle:
            p.move(to: CGPoint(x: 12, y: 3.5)); p.addLine(to: CGPoint(x: 2.5, y: 19.5)); p.addLine(to: CGPoint(x: 21.5, y: 19.5)); p.closeSubpath()
            p.move(to: CGPoint(x: 12, y: 9.5)); p.addLine(to: CGPoint(x: 12, y: 13.8))
            p.move(to: CGPoint(x: 12, y: 16.8)); p.addLine(to: CGPoint(x: 12.02, y: 16.8))

        case .refresh:
            p.addArc(center: CGPoint(x: 12, y: 12), radius: 8.5, startAngle: .degrees(-40), endAngle: .degrees(260), clockwise: false)
            p.move(to: CGPoint(x: 16.5, y: 3.8)); p.addLine(to: CGPoint(x: 20.5, y: 4.5)); p.addLine(to: CGPoint(x: 19.5, y: 8.5))

        case .chevronUp:
            p.move(to: CGPoint(x: 6, y: 15)); p.addLine(to: CGPoint(x: 12, y: 9)); p.addLine(to: CGPoint(x: 18, y: 15))

        case .download:
            p.move(to: CGPoint(x: 4.5, y: 14.5)); p.addLine(to: CGPoint(x: 4.5, y: 20)); p.addLine(to: CGPoint(x: 19.5, y: 20)); p.addLine(to: CGPoint(x: 19.5, y: 14.5))
            p.move(to: CGPoint(x: 12, y: 3)); p.addLine(to: CGPoint(x: 12, y: 15))
            p.move(to: CGPoint(x: 7.5, y: 10.5)); p.addLine(to: CGPoint(x: 12, y: 15)); p.addLine(to: CGPoint(x: 16.5, y: 10.5))

        case .link:
            p.move(to: CGPoint(x: 10, y: 13))
            p.addArc(center: CGPoint(x: 14.5, y: 9.5), radius: 4, startAngle: .degrees(135), endAngle: .degrees(-45), clockwise: false)
            p.move(to: CGPoint(x: 14, y: 11))
            p.addArc(center: CGPoint(x: 9.5, y: 14.5), radius: 4, startAngle: .degrees(-45), endAngle: .degrees(135), clockwise: false)

        case .globe:
            p.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            p.move(to: CGPoint(x: 3, y: 12)); p.addLine(to: CGPoint(x: 21, y: 12))
            p.addEllipse(in: CGRect(x: 8, y: 3, width: 8, height: 18))

        case .bell:
            p.move(to: CGPoint(x: 6, y: 9.5))
            p.addArc(center: CGPoint(x: 12, y: 9.5), radius: 6, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: 18, y: 15))
            p.addLine(to: CGPoint(x: 20, y: 17))
            p.addLine(to: CGPoint(x: 4, y: 17))
            p.addLine(to: CGPoint(x: 6, y: 15))
            p.closeSubpath()
            p.move(to: CGPoint(x: 10, y: 20)); p.addLine(to: CGPoint(x: 14, y: 20))

        case .trash:
            p.move(to: CGPoint(x: 4, y: 6.5)); p.addLine(to: CGPoint(x: 20, y: 6.5))
            p.move(to: CGPoint(x: 9, y: 6.5)); p.addLine(to: CGPoint(x: 9, y: 4)); p.addLine(to: CGPoint(x: 15, y: 4)); p.addLine(to: CGPoint(x: 15, y: 6.5))
            p.move(to: CGPoint(x: 6.5, y: 6.5)); p.addLine(to: CGPoint(x: 7.5, y: 20)); p.addLine(to: CGPoint(x: 16.5, y: 20)); p.addLine(to: CGPoint(x: 17.5, y: 6.5))
            p.move(to: CGPoint(x: 10.2, y: 10.5)); p.addLine(to: CGPoint(x: 10.2, y: 16.5))
            p.move(to: CGPoint(x: 13.8, y: 10.5)); p.addLine(to: CGPoint(x: 13.8, y: 16.5))

        case .code:
            p.move(to: CGPoint(x: 8, y: 6.5)); p.addLine(to: CGPoint(x: 3, y: 12)); p.addLine(to: CGPoint(x: 8, y: 17.5))
            p.move(to: CGPoint(x: 16, y: 6.5)); p.addLine(to: CGPoint(x: 21, y: 12)); p.addLine(to: CGPoint(x: 16, y: 17.5))
            p.move(to: CGPoint(x: 13.5, y: 4.5)); p.addLine(to: CGPoint(x: 10.5, y: 19.5))

        case .paperclip:
            p.move(to: CGPoint(x: 19.5, y: 11.5)); p.addLine(to: CGPoint(x: 11, y: 20))
            p.addArc(center: CGPoint(x: 7.5, y: 16.5), radius: 5, startAngle: .degrees(45), endAngle: .degrees(225), clockwise: false)
            p.addLine(to: CGPoint(x: 14.5, y: 4.5))
            p.addArc(center: CGPoint(x: 17, y: 7), radius: 3.5, startAngle: .degrees(225), endAngle: .degrees(45), clockwise: false)
            p.addLine(to: CGPoint(x: 9.5, y: 17))

        case .stop:
            p.addRoundedRect(in: CGRect(x: 6, y: 6, width: 12, height: 12), cornerSize: CGSize(width: 2.2, height: 2.2))

        case .edit:
            p.move(to: CGPoint(x: 16.5, y: 3.5)); p.addLine(to: CGPoint(x: 20.5, y: 7.5))
            p.addLine(to: CGPoint(x: 8, y: 20)); p.addLine(to: CGPoint(x: 4, y: 20)); p.addLine(to: CGPoint(x: 4, y: 16)); p.closeSubpath()

        case .close:
            p.move(to: CGPoint(x: 6, y: 6)); p.addLine(to: CGPoint(x: 18, y: 18))
            p.move(to: CGPoint(x: 18, y: 6)); p.addLine(to: CGPoint(x: 6, y: 18))
        }
        return p
    }
}

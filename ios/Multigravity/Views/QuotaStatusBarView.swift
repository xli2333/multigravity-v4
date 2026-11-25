import SwiftUI

public struct QuotaStatusBarView: View {
    @Environment(\.colorScheme) private var colorScheme
    public let account: CockpitAccountQuota?
    public let onTap: () -> Void
    /// When set, a small connection-heartbeat dot is drawn at the far right of the bar.
    public let linkMonitor: ConversationEventsClient?
    
    public init(account: CockpitAccountQuota?, linkMonitor: ConversationEventsClient? = nil, onTap: @escaping () -> Void) {
        self.account = account
        self.linkMonitor = linkMonitor
        self.onTap = onTap
    }
    
    private var resolvedDisplay: (kind: QuotaBucketKind, bucket: CockpitQuotaBucket)? {
        account?.resolvedQuotaDisplay(preferred: AppSettings.shared.selectedQuotaBucket)
    }

    private var resolvedKind: QuotaBucketKind {
        resolvedDisplay?.kind ?? .gemini5h
    }

    private var isWeekly: Bool {
        resolvedKind == .geminiWeekly || resolvedKind == .claudeWeekly
    }
    
    private var bucket: CockpitQuotaBucket? {
        resolvedDisplay?.bucket
    }
    
    private var titleText: String {
        switch resolvedKind {
        case .gemini5h: return "Gemini · 5h"
        case .claude5h: return "Claude · 5h"
        case .geminiWeekly: return "Gemini"
        case .claudeWeekly: return "Claude"
        }
    }
    
    private var percent: Double {
        bucket?.remainingPercent ?? 0.0
    }
    
    private var progressColor: Color {
        if percent >= 50 {
            return AGPalette.emeraldFill(colorScheme)
        } else if percent >= 20 {
            return AGPalette.amberFill(colorScheme)
        } else {
            return AGPalette.roseFill(colorScheme)
        }
    }

    private var progressTextColor: Color {
        if percent >= 50 {
            return AGPalette.emeraldText(colorScheme)
        } else if percent >= 20 {
            return AGPalette.amberText(colorScheme)
        } else {
            return AGPalette.roseText(colorScheme)
        }
    }
    
    private var formattedResetClockTime: String? {
        guard let resetTimeStr = bucket?.resetTime, !resetTimeStr.isEmpty else {
            return nil
        }
        
        let date: Date?
        let fmtFraction = ISO8601DateFormatter()
        fmtFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmtFraction.date(from: resetTimeStr) {
            date = d
        } else {
            let fmtStandard = ISO8601DateFormatter()
            fmtStandard.formatOptions = [.withInternetDateTime]
            if let d = fmtStandard.date(from: resetTimeStr) {
                date = d
            } else {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                date = df.date(from: resetTimeStr)
            }
        }
        
        guard let validDate = date else {
            return nil
        }
        
        let outputFormatter = DateFormatter()
        outputFormatter.locale = Locale(identifier: "en_US_POSIX")
        outputFormatter.timeZone = TimeZone.current
        outputFormatter.dateFormat = "MM/dd HH:mm"
        return "(\(outputFormatter.string(from: validDate)))"
    }
    
    private var resetCountdownDisplay: String? {
        if isWeekly {
            if let clock = formattedResetClockTime {
                return clock
            }
            if let friendly = bucket?.resetFriendly, friendly == "已就绪" || friendly == "未知" {
                return friendly
            }
            return nil
        }
        guard let friendly = bucket?.resetFriendly, !friendly.isEmpty else {
            return nil
        }
        if friendly == "已就绪" || friendly == "未知" {
            return friendly
        }
        if let clock = formattedResetClockTime {
            return "\(friendly) \(clock)"
        }
        return friendly
    }
    
    public var body: some View {
        guard let _ = bucket else { return AnyView(EmptyView()) }
        
        return AnyView(
            Button(action: onTap) {
                HStack(spacing: 7) {
                    if resolvedKind == .claude5h || resolvedKind == .claudeWeekly {
                        ClaudeBrandIcon(size: 13.5)
                    } else {
                        GeminiBrandIcon(size: 13.5)
                    }
                    
                    Text(titleText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AGPalette.textPrimary(colorScheme))
                        .lineLimit(1)
                        .layoutPriority(1)
                    
                    // Mini progress bar - stretched to fill available width with pace needle
                    let paceInfo = bucket?.calculatePaceForTitle(resolvedKind.displayTitle, tier: account?.subscriptionTier)
                    let showCursor = AppSettings.shared.weeklyPaceCursorEnabled && paceInfo != nil

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(AGPalette.borderSubtle(colorScheme))
                            Capsule()
                                .fill(progressColor)
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(percent / 100.0))))

                            if showCursor, let info = paceInfo {
                                let expectedFrac = CGFloat(info.expectedRemainingPercent / 100.0)
                                let needleOffset = max(0, min(geo.size.width - 1.5, geo.size.width * expectedFrac - 0.75))
                                let needleColor = info.isOverPacing ? AGPalette.amberFill(colorScheme) : AGPalette.textPrimary(colorScheme)

                                RoundedRectangle(cornerRadius: 0.75, style: .continuous)
                                    .fill(needleColor)
                                    .frame(width: 1.8, height: 9.5)
                                    .offset(x: needleOffset, y: (6.0 - 9.5) / 2.0)
                            }
                        }
                    }
                    .frame(height: 6)
                    .frame(minWidth: 24)
                    
                    Text(String(format: "%.0f%%", percent))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(progressTextColor)
                        .lineLimit(1)
                        .layoutPriority(1)
                    
                    if let countdownText = resetCountdownDisplay {
                        Text(countdownText)
                            .font(.system(size: 10))
                            .foregroundColor(AGPalette.textTertiary(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .layoutPriority(1)
                    }
                    
                    if let monitor = linkMonitor {
                        LinkHealthDot(monitor: monitor)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 8.5)
                .agCard(cornerRadius: 12)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        )
    }
}

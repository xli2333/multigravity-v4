import Foundation
import SwiftUI

/// Vertical Digital-Crown Pager for Model Quotas (Gemini / Claude) + Appearance Settings.
struct WatchQuotaPagerScreen: View {
    @State private var store = WatchSessionStore.shared
    @State private var verticalPage: Int = 0

    var body: some View {
        let palette = store.palette
        let quota = store.effectiveEnvelope?.quota

        NavigationStack {
            TabView(selection: $verticalPage) {
                WatchSingleProviderQuotaPage(
                    providerName: "Gemini",
                    isClaude: false,
                    shortWindow: quota?.geminiShort,
                    weeklyWindow: quota?.geminiWeekly,
                    isFreeTier: quota?.isFreeTier ?? false,
                    palette: palette
                )
                .tag(0)

                WatchSingleProviderQuotaPage(
                    providerName: "Claude",
                    isClaude: true,
                    shortWindow: quota?.claudeShort,
                    weeklyWindow: quota?.claudeWeekly,
                    isFreeTier: quota?.isFreeTier ?? false,
                    palette: palette
                )
                .tag(1)

                WatchAppearanceAndLinkPage(palette: palette)
                    .tag(2)
            }
            .tabViewStyle(.verticalPage)
            .navigationTitle(verticalPage == 2 ? String(localized: "外观与同步") : String(localized: "实时额度"))
            .navigationBarTitleDisplayMode(.inline)
            .containerBackground(for: .navigation) {
                WatchCanvasBackground(
                    palette: palette,
                    statusTint: verticalPage == 1 ? palette.claudeFill : (verticalPage == 0 ? palette.geminiFill : nil)
                )
            }
        }
    }
}

private struct WatchSingleProviderQuotaPage: View {
    let providerName: String
    let isClaude: Bool
    let shortWindow: WatchQuotaWindow?
    let weeklyWindow: WatchQuotaWindow?
    let isFreeTier: Bool
    let palette: WatchPalette

    private var primary: (tag: String, window: WatchQuotaWindow)? {
        if !isFreeTier, let s = shortWindow { return ("5h", s) }
        if let w = weeklyWindow { return ("7d", w) }
        if let s = shortWindow { return ("5h", s) }
        return nil
    }

    var body: some View {
        let brandFill = isClaude ? palette.claudeFill : palette.geminiFill
        let brandText = isClaude ? palette.claudeText : palette.geminiText

        VStack(spacing: 6) {
            HStack(spacing: 5) {
                WatchBrandIconView(isClaude: isClaude, palette: palette, size: 13)
                Text(providerName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.primaryFg)
                if let primary {
                    Text(primary.tag)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(brandText)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(palette.recessedBg)
                        )
                }
            }

            if let primary {
                let pct = primary.window.remainingPercent
                let ringColor = pct < 20 ? palette.roseFill : (pct < 50 ? palette.amberFill : brandFill)

                ZStack {
                    Circle()
                        .stroke(palette.recessedBg, lineWidth: 8.5)

                    Circle()
                        .trim(from: 0, to: CGFloat(primary.window.clampedFraction))
                        .stroke(
                            ringColor,
                            style: StrokeStyle(lineWidth: 8.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 1) {
                        Text("\(primary.window.intPercent)%")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.primaryFg)
                            .minimumScaleFactor(0.75)

                        Text(primary.window.countdownText())
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(palette.secondaryFg)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                }
                .frame(width: 90, height: 90)
                .padding(.vertical, 1)

                if let weekly = weeklyWindow, primary.tag == "5h" {
                    let wColors = palette.quotaColor(for: weekly.remainingPercent)
                    HStack(spacing: 6) {
                        Text(String(localized: "7d 周余量"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.secondaryFg)

                        ZStack {
                            Capsule().fill(palette.recessedBg)
                            WatchProgressFillShape(fraction: CGFloat(weekly.clampedFraction))
                                .fill(wColors.fill)
                        }
                        .frame(height: 5)

                        Text("\(weekly.intPercent)%")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(wColors.text)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5.5)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(palette.cardBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(palette.cardBorder, lineWidth: 1)
                            )
                    )
                }
            } else {
                Spacer(minLength: 0)
                Text(String(localized: "等待 iPhone 同步额度"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.secondaryFg)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
    }
}

private struct WatchAppearanceAndLinkPage: View {
    let palette: WatchPalette
    @State private var store = WatchSessionStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.isReachable || store.isLocalPreviewMode ? palette.emeraldFill : palette.amberFill)
                        .frame(width: 7, height: 7)
                    Text(store.isReachable ? String(localized: "iPhone 已连接") : String(localized: "缓存模式"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.primaryFg)
                    Spacer()
                    if let synced = store.effectiveEnvelope?.syncedAt {
                        Text(synced, style: .relative)
                            .font(.system(size: 9.5))
                            .foregroundStyle(palette.mutedFg)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(palette.cardBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(palette.cardBorder, lineWidth: 1)
                        )
                )

                Text(String(localized: "主题外观"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.mutedFg)
                    .padding(.leading, 2)

                ForEach(WatchAppearancePreference.allCases) { option in
                    let isSelected = store.appearancePreference == option
                    Button {
                        store.appearancePreference = option
                    } label: {
                        HStack(spacing: 6) {
                            Text(option.displayTitle)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(palette.primaryFg)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(palette.geminiFill)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7.5)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(palette.cardBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .stroke(isSelected ? palette.geminiFill : palette.cardBorder, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 10)
        }
    }
}

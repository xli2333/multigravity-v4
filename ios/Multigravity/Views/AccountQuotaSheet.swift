import SwiftUI

public struct AccountQuotaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding public var quotaResponse: CockpitQuotaResponse?
    public let tokenHistory: TokenHistoryResponse?
    public let isLoadingTokenHistory: Bool
    public let onLoadTokenHistory: ((Bool) async -> Void)?
    public let onSwitch: ((String) async throws -> Void)?
    public let onRefresh: (() async throws -> Void)?
    public let onAppearFetch: (() async -> Void)?

    /// 是否显示账号切换按钮。网关会先退出电脑上的 Antigravity 再注入新账号。
    public let enableSwitchButton: Bool
    /// Live gateway link monitor; when set the sheet shows a connection detail card with a reconnect button.
    public let linkMonitor: ConversationEventsClient?

    public init(
        quotaResponse: Binding<CockpitQuotaResponse?>,
        tokenHistory: TokenHistoryResponse? = nil,
        isLoadingTokenHistory: Bool = false,
        onLoadTokenHistory: ((Bool) async -> Void)? = nil,
        onSwitch: ((String) async throws -> Void)? = nil,
        onRefresh: (() async throws -> Void)? = nil,
        onAppearFetch: (() async -> Void)? = nil,
        enableSwitchButton: Bool = true,
        linkMonitor: ConversationEventsClient? = nil
    ) {
        self.linkMonitor = linkMonitor
        self._quotaResponse = quotaResponse
        self.tokenHistory = tokenHistory
        self.isLoadingTokenHistory = isLoadingTokenHistory
        self.onLoadTokenHistory = onLoadTokenHistory
        self.onSwitch = onSwitch
        self.onRefresh = onRefresh
        self.onAppearFetch = onAppearFetch
        self.enableSwitchButton = enableSwitchButton
    }

    public var body: some View {
        NavigationStack {
            CockpitDashboardView(
                quotaResponse: $quotaResponse,
                tokenHistory: tokenHistory,
                isLoadingTokenHistory: isLoadingTokenHistory,
                onLoadTokenHistory: onLoadTokenHistory,
                onSwitch: onSwitch,
                onRefresh: onRefresh,
                onAppearFetch: onAppearFetch,
                enableSwitchButton: enableSwitchButton,
                linkMonitor: linkMonitor
            )
            .background(AGPageBackgroundView())
            .navigationTitle("账户与配额驾驶舱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .presentationDragIndicator(.visible)
        }
    }

    public static func formatTokensCompact(_ tokens: Int64) -> String {
        if tokens >= 1_000_000_000 { return String(format: "%.2fB", Double(tokens) / 1_000_000_000.0) }
        if tokens >= 1_000_000 { return String(format: "%.2fM", Double(tokens) / 1_000_000.0) }
        if tokens >= 1_000 { return String(format: "%.1fK", Double(tokens) / 1_000.0) }
        return "\(tokens)"
    }
}

public struct WeeklyPaceDetailItem: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let info: WeeklyPaceInfo
}

struct WeeklyPaceDetailSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: WeeklyPaceDetailItem

    var body: some View {
        let toneText = item.info.isOverPacing ? AGPalette.amberText(colorScheme) : AGPalette.emeraldText(colorScheme)
        let toneSoft = item.info.isOverPacing ? AGPalette.amberSoft(colorScheme) : AGPalette.emeraldSoft(colorScheme)
        let toneBorder = (item.info.isOverPacing ? AGPalette.amberFill(colorScheme) : AGPalette.emeraldFill(colorScheme)).opacity(0.35)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            AGLinearIcon(
                                item.info.isOverPacing ? .alertTriangle : .check,
                                size: 15,
                                color: toneText,
                                lineWidth: 2.1
                            )
                            Text(item.info.isOverPacing ? String(localized: "消耗偏快 (超速透支)") : String(localized: "节奏健康 (额度充裕)"))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(toneText)
                        }
                        Text(item.info.isOverPacing
                             ? String(localized: "当前额度已消耗 \(String(format: "%.1f%%", item.info.usedPercent))，快于 \(item.info.windowLabel)时间匀速基准线 (\(String(format: "%.1f%%", item.info.expectedUsedPercent)))。若保持此速率可能在周期结束前提前耗尽。")
                             : String(localized: "当前额度已消耗 \(String(format: "%.1f%%", item.info.usedPercent))，低于或符合 \(item.info.windowLabel)时间匀速基准线 (\(String(format: "%.1f%%", item.info.expectedUsedPercent)))。剩余额度充足，无需担心断粮。"))
                            .font(.system(size: 13))
                            .foregroundColor(AGPalette.textSecondary(colorScheme))
                            .lineSpacing(2)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(toneSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(toneBorder, lineWidth: 1)
                    )

                    VStack(spacing: 10) {
                        detailRow(label: String(localized: "当前实际剩余"), value: String(format: "%.1f%%", item.info.actualRemainingPercent), isPrimary: true)
                        detailRow(label: String(localized: "当前实际已用"), value: String(format: "%.1f%%", item.info.usedPercent), isPrimary: true)
                        Rectangle()
                            .fill(AGPalette.borderSubtle(colorScheme))
                            .frame(height: 0.75)
                        detailRow(label: String(localized: "\(item.info.windowLabel)匀速应剩 (游标位)"), value: String(format: "%.1f%%", item.info.expectedRemainingPercent), isPrimary: false)
                        detailRow(label: String(localized: "\(item.info.windowLabel)匀速应耗基准"), value: String(format: "%.1f%%", item.info.expectedUsedPercent), isPrimary: false)
                        Rectangle()
                            .fill(AGPalette.borderSubtle(colorScheme))
                            .frame(height: 0.75)
                        detailRow(
                            label: String(localized: "节奏差值 (实际 - 理论)"),
                            value: (item.info.paceDeltaPercent >= 0 ? "+" : "") + String(format: "%.1f%%", item.info.paceDeltaPercent),
                            color: toneText
                        )
                        detailRow(label: String(localized: "重置倒计时"), value: item.info.resetCountdownDisplay, isPrimary: false)
                    }
                    .padding(14)
                    .agCard(cornerRadius: 13)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(AGPageBackgroundView())
            .navigationTitle(String(localized: "\(item.title) 消耗节奏"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func detailRow(label: String, value: String, isPrimary: Bool = false, color: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(AGPalette.textSecondary(colorScheme))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: isPrimary ? .semibold : .medium, design: .monospaced))
                .foregroundColor(color ?? (isPrimary ? AGPalette.textPrimary(colorScheme) : AGPalette.textSecondary(colorScheme)))
        }
    }
}

struct ModelUsageBreakdownSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let models: [ModelTokenBreakdown]

    private var grandTotal: Int64 {
        max(1, models.reduce(Int64(0)) { $0 + $1.total })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(models) { item in
                        let pct = Double(item.total) * 100.0 / Double(grandTotal)
                        let hasDetail = item.input > 0 || item.output > 0 || item.cacheRead > 0 || item.thinking > 0
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 7) {
                                ModelProviderBrandIcon(modelId: item.model, size: 13.5)
                                Text(item.model)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(AGPalette.textPrimary(colorScheme))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 6)
                                Text(AccountQuotaSheet.formatTokensCompact(item.total))
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(AGPalette.accentText(colorScheme))
                                Text(String(format: "%.1f%%", pct))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(AGPalette.textSecondary(colorScheme))
                            }
                            if hasDetail {
                                Rectangle()
                                    .fill(AGPalette.borderSubtle(colorScheme))
                                    .frame(height: 0.75)
                                HStack {
                                    detailCell("Input", AccountQuotaSheet.formatTokensCompact(item.input))
                                    Spacer()
                                    detailCell("Cache Hit", AccountQuotaSheet.formatTokensCompact(item.cacheRead))
                                    Spacer()
                                    detailCell("Output", AccountQuotaSheet.formatTokensCompact(item.output))
                                    Spacer()
                                    detailCell("Thinking", AccountQuotaSheet.formatTokensCompact(item.thinking))
                                }
                                if item.steps > 0 || item.costUsd > 0 {
                                    HStack {
                                        Text("\(item.steps) 轮采样")
                                            .font(.system(size: 10.5))
                                            .foregroundColor(AGPalette.textTertiary(colorScheme))
                                        Spacer()
                                        Text(String(format: "$%.3f", item.costUsd))
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundColor(AGPalette.textTertiary(colorScheme))
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .agCard(cornerRadius: 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(AGPageBackgroundView())
            .navigationTitle("模型用量明细")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(models.count) 款模型")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(AGPalette.textSecondary(colorScheme))
                }
            }
        }
    }

    private func detailCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(AGPalette.textTertiary(colorScheme))
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(AGPalette.textPrimary(colorScheme))
        }
    }
}

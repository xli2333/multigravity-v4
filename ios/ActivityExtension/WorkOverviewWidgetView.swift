import AppIntents
import Foundation
import SwiftUI
import WidgetKit

// MARK: - Combined Work & Quota Overview Timeline Provider

nonisolated struct WorkOverviewWidgetEntry: TimelineEntry {
    let date: Date
    let quota: QuotaWidgetSnapshot?
    let conversations: AgentConversationsWidgetSnapshot?
    let isPaired: Bool
    let isStale: Bool
}

nonisolated struct WorkOverviewTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkOverviewWidgetEntry {
        let now = Date()
        return WorkOverviewWidgetEntry(
            date: now,
            quota: QuotaWidgetSnapshot.demoPlaceholder(now: now),
            conversations: AgentConversationsWidgetSnapshot.demoPlaceholder(now: now),
            isPaired: true,
            isStale: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkOverviewWidgetEntry) -> Void) {
        let now = Date()
        let config = QuotaWidgetStore.shared.loadConfig()
        let cachedQuota = QuotaWidgetStore.shared.loadSnapshot()?.applying(config: config)
        let cachedConvs = QuotaWidgetStore.shared.loadConversationsSnapshot()
        if context.isPreview {
            completion(WorkOverviewWidgetEntry(
                date: now,
                quota: cachedQuota ?? QuotaWidgetSnapshot.demoPlaceholder(now: now),
                conversations: cachedConvs ?? AgentConversationsWidgetSnapshot.demoPlaceholder(now: now),
                isPaired: true,
                isStale: false
            ))
            return
        }
        let paired = (config?.isPaired ?? false) || (cachedQuota != nil) || (cachedConvs != nil)
        completion(WorkOverviewWidgetEntry(
            date: now,
            quota: cachedQuota ?? (paired ? QuotaWidgetSnapshot.demoPlaceholder(now: now) : nil),
            conversations: cachedConvs ?? (paired ? AgentConversationsWidgetSnapshot.demoPlaceholder(now: now) : nil),
            isPaired: paired,
            isStale: false
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkOverviewWidgetEntry>) -> Void) {
        let now = Date()
        let config = QuotaWidgetStore.shared.loadConfig()
        let cachedQuota = QuotaWidgetStore.shared.loadSnapshot()?.applying(config: config)
        let cachedConvs = QuotaWidgetStore.shared.loadConversationsSnapshot()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: now)
            ?? now.addingTimeInterval(15 * 60)

        let quotaFresh = cachedQuota.map { now.timeIntervalSince($0.syncedAt) < 15 * 60 } ?? false
        let convsFresh = cachedConvs.map { now.timeIntervalSince($0.syncedAt) < 15 * 60 } ?? false

        if quotaFresh && convsFresh {
            let entry = WorkOverviewWidgetEntry(
                date: now,
                quota: cachedQuota,
                conversations: cachedConvs,
                isPaired: true,
                isStale: false
            )
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
            return
        }

        Task {
            async let quotaTask = Self.resolveQuota(cached: cachedQuota, isFresh: quotaFresh, config: config)
            async let convsTask = Self.resolveConversations(cached: cachedConvs, isFresh: convsFresh)

            let (freshQuota, freshConvs) = await (quotaTask, convsTask)
            let resolvedQuota = freshQuota ?? cachedQuota
            let resolvedConvs = freshConvs ?? cachedConvs
            let latestSync = [resolvedQuota?.syncedAt, resolvedConvs?.syncedAt].compactMap { $0 }.max()
            let stale = latestSync.map { now.timeIntervalSince($0) > 25 * 60 } ?? false
            let paired = (config?.isPaired ?? false) || (resolvedQuota != nil) || (resolvedConvs != nil)

            let entry = WorkOverviewWidgetEntry(
                date: now,
                quota: resolvedQuota,
                conversations: resolvedConvs,
                isPaired: paired,
                isStale: stale
            )
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private static func resolveQuota(
        cached: QuotaWidgetSnapshot?,
        isFresh: Bool,
        config: QuotaWidgetEndpointConfig?
    ) async -> QuotaWidgetSnapshot? {
        if isFresh, let cached {
            return cached
        }
        return await QuotaWidgetStore.shared.fetchLatestQuotaFromGateway()?.applying(config: config)
    }

    private static func resolveConversations(
        cached: AgentConversationsWidgetSnapshot?,
        isFresh: Bool
    ) async -> AgentConversationsWidgetSnapshot? {
        if isFresh, let cached {
            return cached
        }
        return await QuotaWidgetStore.shared.fetchLatestConversationsFromGateway()
    }
}

// MARK: - Dedicated Combined Home Screen Widget (Recent Work + Quota)

public struct WorkOverviewWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: QuotaWidgetConstants.overviewWidgetKind,
            provider: WorkOverviewTimelineProvider()
        ) { entry in
            WorkOverviewWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "工作与额度"))
        .description(String(localized: "在主屏幕一屏查看最近工作进展与 Gemini / Claude 实时额度，轻点直达对话或驾驶舱。"))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct WorkOverviewWidgetEntryView: View {
    let entry: WorkOverviewWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemLarge:
                WorkOverviewLargeView(entry: entry)
            default:
                WorkOverviewMediumView(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            WidgetCardBackground()
        }
    }
}

// MARK: - Medium (4x2): Split Bento — Left Quota Bars, Right Recent Work

private struct WorkOverviewMediumView: View {
    let entry: WorkOverviewWidgetEntry
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isDark: Bool { colorScheme == .dark }
    private var isFullColor: Bool { renderingMode == .fullColor }

    private var latestSyncDate: Date? {
        [entry.conversations?.syncedAt, entry.quota?.syncedAt].compactMap { $0 }.max()
    }

    var body: some View {
        if entry.quota != nil || entry.conversations != nil {
            let items = Array((entry.conversations?.items ?? []).prefix(2))
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(alignment: .center, spacing: 6) {
                    Image("AppLogoTransparent")
                        .renderingMode(.original)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 19, height: 12.5)

                    Text(String(localized: "工作与额度"))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let convs = entry.conversations {
                        AgentStatusCompactSummaryPills(snapshot: convs, maxPills: 1)
                    }

                    Spacer(minLength: 4)

                    if let syncDate = latestSyncDate {
                        WidgetSyncFooter(
                            syncedAt: syncDate,
                            isDemo: (entry.quota?.isDemo ?? false) || (entry.conversations?.isDemo ?? false),
                            isStale: entry.isStale,
                            alignment: .trailing
                        )
                    }

                    WidgetRefreshIconButton(intent: RefreshQuotaWidgetIntent(), size: 20)
                }

                // Body Split: Left Quota (~43%), Right Recent Work (~57%)
                HStack(alignment: .top, spacing: 8) {
                    Link(destination: QuotaWidgetConstants.deepLinkURL) {
                        VStack(alignment: .leading, spacing: 6) {
                            if let snap = entry.quota {
                                WorkOverviewQuotaStack(snapshot: snap, now: entry.date, compact: true)
                            } else {
                                WorkOverviewPlaceholderTile(
                                    icon: "gauge.with.dots.needle.33percent",
                                    text: String(localized: "等待额度同步")
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 122)

                    Rectangle()
                        .fill(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                        .frame(width: 1)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 5.5) {
                        if !items.isEmpty {
                            ForEach(items) { item in
                                WorkOverviewCompactRow(item: item, now: entry.date)
                            }
                        } else {
                            Link(destination: QuotaWidgetConstants.conversationsDeepLinkURL) {
                                WorkOverviewPlaceholderTile(
                                    icon: "bubble.left.and.text.bubble.right",
                                    text: String(localized: "暂无最近工作")
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            WorkOverviewEmptyView(isPaired: entry.isPaired)
                .widgetURL(QuotaWidgetConstants.conversationsDeepLinkURL)
        }
    }
}

// MARK: - Large (4x4): Top Compact Dual-Model Quota Strip + Bottom 4 Recent Work Rows

private struct WorkOverviewLargeView: View {
    let entry: WorkOverviewWidgetEntry
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    private var latestSyncDate: Date? {
        [entry.conversations?.syncedAt, entry.quota?.syncedAt].compactMap { $0 }.max()
    }

    var body: some View {
        if entry.quota != nil || entry.conversations != nil {
            let items = Array((entry.conversations?.items ?? []).prefix(4))
            VStack(alignment: .leading, spacing: 9) {
                // Header
                HStack(alignment: .center, spacing: 6) {
                    Image("AppLogoTransparent")
                        .renderingMode(.original)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 13)

                    Text(entry.quota?.displayAccountTitle ?? String(localized: "工作与额度"))
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let tier = entry.quota?.tierBadgeLabel {
                        WidgetTierBadge(label: tier)
                    }

                    Spacer(minLength: 4)

                    if let convs = entry.conversations {
                        AgentStatusCompactSummaryPills(snapshot: convs, maxPills: 1)
                    }

                    WidgetRefreshIconButton(intent: RefreshQuotaWidgetIntent())
                }

                // Compact Quota Strip (1 row: Gemini + Claude side-by-side)
                if let snap = entry.quota {
                    Link(destination: QuotaWidgetConstants.deepLinkURL) {
                        HStack(spacing: 7) {
                            if let g = snap.geminiBundle, let bucket = g.primaryWindow {
                                WorkOverviewQuotaCard(
                                    providerTitle: "Gemini",
                                    isClaude: false,
                                    windowTag: g.primaryWindowTag,
                                    bucket: bucket,
                                    now: entry.date
                                )
                            }
                            if let c = snap.claudeBundle, let bucket = c.primaryWindow {
                                WorkOverviewQuotaCard(
                                    providerTitle: "Claude",
                                    isClaude: true,
                                    windowTag: c.primaryWindowTag,
                                    bucket: bucket,
                                    now: entry.date
                                )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Recent Work Section
                HStack(alignment: .center) {
                    Text(String(localized: "最近工作"))
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let syncDate = latestSyncDate {
                        WidgetSyncFooter(
                            syncedAt: syncDate,
                            isDemo: (entry.quota?.isDemo ?? false) || (entry.conversations?.isDemo ?? false),
                            isStale: entry.isStale,
                            alignment: .trailing
                        )
                    }
                }

                if !items.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(items) { item in
                            WidgetConversationRow(
                                item: item,
                                now: entry.date,
                                showStepCount: true,
                                verticalPadding: 7,
                                maxRowHeight: 48
                            )
                        }
                    }
                } else {
                    Link(destination: QuotaWidgetConstants.conversationsDeepLinkURL) {
                        WorkOverviewPlaceholderTile(
                            icon: "bubble.left.and.text.bubble.right",
                            text: String(localized: "暂无最近工作，轻点打开 Multigravity")
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            WorkOverviewEmptyView(isPaired: entry.isPaired)
                .widgetURL(QuotaWidgetConstants.conversationsDeepLinkURL)
        }
    }
}

// MARK: - Subcomponents

private struct WorkOverviewQuotaStack: View {
    let snapshot: QuotaWidgetSnapshot
    let now: Date
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            if let g = snapshot.geminiBundle, let primary = g.primaryWindow {
                WorkOverviewQuotaCard(
                    providerTitle: "Gemini",
                    isClaude: false,
                    windowTag: g.primaryWindowTag,
                    bucket: primary,
                    now: now,
                    compact: compact
                )
            }
            if let c = snapshot.claudeBundle, let primary = c.primaryWindow {
                WorkOverviewQuotaCard(
                    providerTitle: "Claude",
                    isClaude: true,
                    windowTag: c.primaryWindowTag,
                    bucket: primary,
                    now: now,
                    compact: compact
                )
            }
        }
    }
}

private struct WorkOverviewQuotaCard: View {
    let providerTitle: String
    let isClaude: Bool
    let windowTag: String
    let bucket: QuotaWidgetBucketSnapshot
    let now: Date
    var compact: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isDark: Bool { colorScheme == .dark }
    private var isFullColor: Bool { renderingMode == .fullColor }

    var body: some View {
        let tint = isFullColor ? quotaTintColor(percent: bucket.remainingPercent) : Color.primary
        VStack(alignment: .leading, spacing: compact ? 3.5 : 4.5) {
            HStack(spacing: 4) {
                WidgetProviderBrandIcon(isClaude: isClaude, size: compact ? 10 : 11, isFullColor: isFullColor)

                Text("\(providerTitle) \(windowTag)")
                    .font(.system(size: compact ? 9.5 : 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 2)

                Text("\(bucket.intPercent)%")
                    .font(.system(size: compact ? 10.5 : 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: true, vertical: false)
                    .widgetAccentable()
            }

            ZStack {
                Capsule()
                    .fill(isDark ? Color.white.opacity(0.11) : Color.black.opacity(0.08))
                QuotaBarFillShape(fraction: CGFloat(bucket.clampedFraction))
                    .fill(tint)
                    .widgetAccentable()
            }
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 4.5 : 5.0)

            let resetText = panelShortCountdownText(for: bucket, now: now)
            Text(resetText)
                .font(.system(size: compact ? 8.5 : 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 7.5 : 9)
        .padding(.vertical, compact ? 5.5 : 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .fill(widgetSubCardFill(isDark: isDark))
        )
    }
}

private struct WorkOverviewCompactRow: View {
    let item: AgentWidgetConversationItem
    let now: Date

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isDark: Bool { colorScheme == .dark }
    private var isFullColor: Bool { renderingMode == .fullColor }

    private var statusColor: Color {
        if !isFullColor { return .primary }
        if item.needsAction { return .orange }
        if item.isWorking { return Color(red: 0.20, green: 0.58, blue: 1.0) }
        if item.status == .error { return .red }
        if item.isUnread { return Color(red: 0.20, green: 0.78, blue: 0.42) }
        return .secondary
    }

    private var statusIconName: String {
        if item.needsAction { return "exclamationmark.circle.fill" }
        if item.isWorking { return "bolt.circle.fill" }
        if item.status == .error { return "xmark.circle.fill" }
        if item.isUnread { return "circle.fill" }
        return "checkmark.circle"
    }

    private var trailingTag: String {
        if item.needsAction { return String(localized: "待确认") }
        if item.isWorking { return String(localized: "运行中") }
        if item.status == .error { return String(localized: "异常") }
        if let mod = item.lastModified {
            return compactRelativeTimeText(from: mod, now: now)
        }
        return item.displayWorkspace
    }

    var body: some View {
        Link(destination: QuotaWidgetConstants.cascadeDeepLinkURL(id: item.id)) {
            HStack(alignment: .center, spacing: 6.5) {
                Image(systemName: statusIconName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 13)
                    .widgetAccentable()

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(item.displayWorkspace)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 2)

                        Text(trailingTag)
                            .font(.system(size: 9.5, weight: item.needsAction || item.isWorking ? .bold : .medium, design: .rounded))
                            .foregroundStyle(item.needsAction || item.isWorking ? statusColor : .secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .padding(.horizontal, 7.5)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                    .fill(widgetSubCardFill(isDark: isDark))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct WorkOverviewPlaceholderTile: View {
    let icon: String
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .fill(widgetSubCardFill(isDark: colorScheme == .dark))
        )
    }
}

private struct WorkOverviewEmptyView: View {
    let isPaired: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image("AppLogoTransparent")
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 13)
                Text(String(localized: "工作与额度"))
                    .font(.system(size: 13, weight: .bold))
            }

            Spacer(minLength: 0)

            Text(isPaired ? String(localized: "等待同步工作与额度") : String(localized: "尚未配对网关"))
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(.primary)

            Text(isPaired ? String(localized: "轻点打开 App 同步最近任务与实时额度") : String(localized: "轻点打开 App 扫码配对本机网关"))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

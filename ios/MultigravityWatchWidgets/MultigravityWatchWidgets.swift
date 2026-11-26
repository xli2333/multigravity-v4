import Foundation
import SwiftUI
import WidgetKit

// MARK: - Lightweight Shared Envelope Reader for Watch Complications

nonisolated private struct ComplicationQuotaWindow: Decodable, Sendable {
    let remainingPercent: Double
    let resetAt: Date?
    let resetFriendly: String?

    var intPercent: Int { Int(max(0, min(100, remainingPercent)).rounded()) }
    var clampedFraction: Double { max(0, min(1, remainingPercent / 100.0)) }
}

nonisolated private struct ComplicationQuotaSnapshot: Decodable, Sendable {
    let isFreeTier: Bool
    let preferClaude: Bool
    let geminiShort: ComplicationQuotaWindow?
    let geminiWeekly: ComplicationQuotaWindow?
    let claudeShort: ComplicationQuotaWindow?
    let claudeWeekly: ComplicationQuotaWindow?

    var primary: (provider: String, tag: String, window: ComplicationQuotaWindow)? {
        let g: (String, ComplicationQuotaWindow)? = (!isFreeTier && geminiShort != nil)
            ? ("5h", geminiShort!)
            : (geminiWeekly.map { ("7d", $0) } ?? geminiShort.map { ("5h", $0) })
        let c: (String, ComplicationQuotaWindow)? = (!isFreeTier && claudeShort != nil)
            ? ("5h", claudeShort!)
            : (claudeWeekly.map { ("7d", $0) } ?? claudeShort.map { ("5h", $0) })
        if preferClaude {
            if let c { return ("Claude", c.0, c.1) }
            if let g { return ("Gemini", g.0, g.1) }
        } else {
            if let g { return ("Gemini", g.0, g.1) }
            if let c { return ("Claude", c.0, c.1) }
        }
        return nil
    }
}

nonisolated private struct ComplicationTaskSummary: Decodable, Sendable {
    let id: String
    let title: String
    let workspaceName: String
    let status: String
    let stepCount: Int
}

nonisolated private struct ComplicationEnvelope: Decodable, Sendable {
    let syncedAt: Date
    let isPaired: Bool
    let runningCount: Int
    let pendingActionCount: Int
    let conversations: [ComplicationTaskSummary]
    let quota: ComplicationQuotaSnapshot?

    static func previewPlaceholder(now: Date = Date()) -> ComplicationEnvelope {
        ComplicationEnvelope(
            syncedAt: now,
            isPaired: true,
            runningCount: 1,
            pendingActionCount: 1,
            conversations: [
                ComplicationTaskSummary(
                    id: "demo-1",
                    title: "生产集群灰度发布与缓存清理",
                    workspaceName: "deploy",
                    status: "ACTION",
                    stepCount: 12
                )
            ],
            quota: ComplicationQuotaSnapshot(
                isFreeTier: false,
                preferClaude: false,
                geminiShort: ComplicationQuotaWindow(remainingPercent: 76, resetAt: now.addingTimeInterval(3 * 3600), resetFriendly: "3h"),
                geminiWeekly: ComplicationQuotaWindow(remainingPercent: 89, resetAt: nil, resetFriendly: "5d"),
                claudeShort: ComplicationQuotaWindow(remainingPercent: 85, resetAt: nil, resetFriendly: "4h"),
                claudeWeekly: nil
            )
        )
    }
}

nonisolated private enum WatchComplicationReader {
    private static let defaultGroup = "group.com.ghsaimo.antigravity"
    private static let fileName = "watch_context_envelope_v1.json"

    private static func extractProvisionedGroups(from bundleURL: URL) -> [String] {
        let profileURL = bundleURL.appendingPathComponent("embedded.mobileprovision")
        guard let rawData = try? Data(contentsOf: profileURL),
              let plistStart = rawData.range(of: Data("<plist".utf8)),
              let plistEnd = rawData.range(of: Data("</plist>".utf8), in: plistStart.lowerBound..<rawData.endIndex) else {
            return []
        }
        let xmlData = rawData.subdata(in: plistStart.lowerBound..<plistEnd.upperBound)
        guard let obj = try? PropertyListSerialization.propertyList(from: xmlData, format: nil) as? [String: Any],
              let entitlements = obj["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else {
            return []
        }
        return groups.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func loadEnvelope() -> ComplicationEnvelope? {
        var candidates: [String] = []
        var seen = Set<String>()
        func add(_ s: String?) {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, seen.insert(t).inserted else { return }
            candidates.append(t)
        }

        for g in extractProvisionedGroups(from: Bundle.main.bundleURL) { add(g) }
        let parentApp = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        for g in extractProvisionedGroups(from: parentApp) { add(g) }
        add(defaultGroup)
        if var bid = Bundle.main.bundleIdentifier {
            for suffix in [".watchkitapp.widgets", ".watchkitapp", ".widgets"] where bid.hasSuffix(suffix) {
                bid = String(bid.dropLast(suffix.count))
                break
            }
            add("group.\(bid)")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for group in candidates {
            if let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
                let url = dir.appendingPathComponent(fileName)
                if let data = try? Data(contentsOf: url),
                   let decoded = try? decoder.decode(ComplicationEnvelope.self, from: data) {
                    return decoded
                }
            }
        }
        return nil
    }
}

// MARK: - Timeline Provider

nonisolated struct WatchComplicationEntry: TimelineEntry {
    let date: Date
    fileprivate let envelope: ComplicationEnvelope?
}

nonisolated struct WatchComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchComplicationEntry {
        WatchComplicationEntry(date: Date(), envelope: .previewPlaceholder())
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchComplicationEntry) -> Void) {
        let now = Date()
        if context.isPreview {
            completion(WatchComplicationEntry(date: now, envelope: WatchComplicationReader.loadEnvelope() ?? .previewPlaceholder(now: now)))
            return
        }
        completion(WatchComplicationEntry(date: now, envelope: WatchComplicationReader.loadEnvelope()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchComplicationEntry>) -> Void) {
        let now = Date()
        let env = WatchComplicationReader.loadEnvelope()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 20, to: now) ?? now.addingTimeInterval(1200)
        completion(Timeline(entries: [WatchComplicationEntry(date: now, envelope: env)], policy: .after(nextRefresh)))
    }
}

// MARK: - Watch Complication Bundle & Views (Circular / Rectangular / Corner / Inline)

@main
struct MultigravityWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MultigravityWatchComplication()
    }
}

struct MultigravityWatchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "MultigravityWatchComplication",
            provider: WatchComplicationProvider()
        ) { entry in
            WatchComplicationEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Multigravity 状态与额度"))
        .description(String(localized: "在表盘查看待确认提醒、运行中任务与模型实时额度。"))
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

private struct WatchComplicationEntryView: View {
    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    private var deepLinkURL: URL {
        if let top = entry.envelope?.conversations.first,
           (top.status == "ACTION" || top.status == "RUNNING") {
            return URL(string: "antigravity://cascade/\(top.id)") ?? URL(string: "antigravity://quota")!
        }
        return URL(string: "antigravity://quota")!
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                inlineView
            case .accessoryCircular:
                circularView
            case .accessoryCorner:
                cornerView
            case .accessoryRectangular:
                rectangularView
            default:
                circularView
            }
        }
        .widgetURL(deepLinkURL)
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    @ViewBuilder
    private var inlineView: some View {
        if let env = entry.envelope {
            let quotaPart = env.quota?.primary.map { "\($0.provider) \($0.window.intPercent)%" } ?? ""
            if env.pendingActionCount > 0 {
                Label(
                    quotaPart.isEmpty ? "\(env.pendingActionCount) 待确认" : "\(env.pendingActionCount) 待确认 · \(quotaPart)",
                    systemImage: "exclamationmark.circle.fill"
                )
            } else if env.runningCount > 0 {
                Label(
                    quotaPart.isEmpty ? "\(env.runningCount) 运行中" : "\(env.runningCount) 运行中 · \(quotaPart)",
                    systemImage: "bolt.fill"
                )
            } else if !quotaPart.isEmpty {
                Label(quotaPart, systemImage: "checkmark.circle")
            } else {
                Label("Multigravity", systemImage: "sparkles")
            }
        } else {
            Label("Multigravity", systemImage: "sparkles")
        }
    }

    @ViewBuilder
    private var circularView: some View {
        if let env = entry.envelope, env.pendingActionCount > 0 {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.orange)
                        .widgetAccentable()
                    Text("\(env.pendingActionCount)待批")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
            }
        } else if let primary = entry.envelope?.quota?.primary {
            Gauge(value: Double(primary.window.intPercent), in: 0...100) {
                Text(primary.provider.hasPrefix("C") ? "C" : "G")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            } currentValueLabel: {
                Text("\(primary.window.intPercent)%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.75)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(primary.provider.hasPrefix("C") ? .orange : .blue)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "terminal.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .widgetAccentable()
            }
        }
    }

    @ViewBuilder
    private var cornerView: some View {
        if let env = entry.envelope, env.pendingActionCount > 0 {
            Text("\(env.pendingActionCount)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
                .widgetAccentable()
                .widgetLabel {
                    Text(String(localized: "待确认"))
                }
        } else if let primary = entry.envelope?.quota?.primary {
            Text("\(primary.window.intPercent)%")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .widgetAccentable()
                .widgetLabel {
                    ProgressView(value: primary.window.clampedFraction) {
                        Text(primary.provider)
                    }
                }
        } else {
            Image(systemName: "terminal.fill")
                .font(.system(size: 14, weight: .semibold))
                .widgetLabel {
                    Text("Multigravity")
                }
        }
    }

    @ViewBuilder
    private var rectangularView: some View {
        if let env = entry.envelope {
            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 4) {
                    if env.pendingActionCount > 0 {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                            .widgetAccentable()
                        Text(String(localized: "\(env.pendingActionCount) 待确认"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)
                            .widgetAccentable()
                    } else if env.runningCount > 0 {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.cyan)
                            .widgetAccentable()
                        Text(String(localized: "\(env.runningCount) 运行中"))
                            .font(.system(size: 11, weight: .bold))
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                        Text(String(localized: "已就绪"))
                            .font(.system(size: 11, weight: .bold))
                    }
                    Spacer(minLength: 2)
                    if let primary = env.quota?.primary {
                        Text("\(primary.provider.prefix(1)) \(primary.window.intPercent)%")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                if let top = env.conversations.first {
                    Text(top.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                } else {
                    Text(String(localized: "轻点查看任务与实时配额"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let primary = env.quota?.primary {
                    ProgressView(value: primary.window.clampedFraction)
                        .progressViewStyle(.linear)
                        .tint(env.pendingActionCount > 0 ? .orange : .blue)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("Multigravity")
                    .font(.system(size: 12, weight: .bold))
                Text(String(localized: "打开手机同步任务与配额"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

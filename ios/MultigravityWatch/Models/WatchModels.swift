import Foundation
import os

// MARK: - Shared Watch Wire Models & Local App Group Persistence

nonisolated public enum WatchBridgeConstants {
    public static let contextPayloadKey = "mgy_watch_ctx_v1"
    public static let defaultAppGroupID = "group.com.ghsaimo.antigravity"
    public static let sharedEnvelopeFileName = "watch_context_envelope_v1.json"
    public static let watchComplicationKind = "MultigravityWatchComplication"
    public static let protocolVersion = 1
}

nonisolated public enum WatchTaskStatus: String, Codable, Hashable, Sendable {
    case action = "ACTION"
    case running = "RUNNING"
    case error = "ERROR"
    case completed = "COMPLETED"
    case idle = "IDLE"

    public var priorityRank: Int {
        switch self {
        case .action: return 0
        case .running: return 1
        case .error: return 2
        case .completed: return 3
        case .idle: return 4
        }
    }
}

nonisolated public struct WatchPendingApprovalSummary: Codable, Hashable, Sendable {
    public let stepIndex: Int?
    public let kind: String
    public let kindLabel: String
    public let redactedTarget: String
    public let descriptionText: String?
    public let requiresPhoneReview: Bool
}

nonisolated public struct WatchRunningTaskSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let stepIndex: Int
    public let title: String
    public let redactedCommand: String?
}

nonisolated public struct WatchTimelineEvent: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let role: String
    public let summary: String
    public let badge: String?
    public let stepIndex: Int?
}

nonisolated public struct WatchQuotaWindow: Codable, Hashable, Sendable {
    public let remainingPercent: Double
    public let resetAt: Date?
    public let resetFriendly: String?

    public var clampedFraction: Double {
        max(0, min(1, remainingPercent / 100.0))
    }

    public var intPercent: Int {
        Int(remainingPercent.rounded())
    }

    public func countdownText(now: Date = Date()) -> String {
        if let resetAt {
            let diff = resetAt.timeIntervalSince(now)
            if diff <= 0 { return String(localized: "已就绪") }
            let totalMinutes = Int(diff / 60.0)
            let days = totalMinutes / (24 * 60)
            let hours = (totalMinutes % (24 * 60)) / 60
            let minutes = totalMinutes % 60
            var parts: [String] = []
            if days > 0 { parts.append("\(days)d") }
            if hours > 0 { parts.append("\(hours)h") }
            if minutes > 0 && days == 0 { parts.append("\(minutes)m") }
            return parts.isEmpty ? "<1m" : parts.joined(separator: " ")
        }
        if let f = resetFriendly?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
            return f
        }
        return String(localized: "配额充足")
    }
}

nonisolated public struct WatchQuotaSnapshot: Codable, Hashable, Sendable {
    public let accountTitle: String
    public let tierBadge: String?
    public let isFreeTier: Bool
    public let preferClaude: Bool
    public let geminiShort: WatchQuotaWindow?
    public let geminiWeekly: WatchQuotaWindow?
    public let claudeShort: WatchQuotaWindow?
    public let claudeWeekly: WatchQuotaWindow?
    public let syncedAt: Date

    public var geminiPrimary: (tag: String, window: WatchQuotaWindow)? {
        if !isFreeTier, let s = geminiShort { return ("5h", s) }
        if let w = geminiWeekly { return ("7d", w) }
        if let s = geminiShort { return ("5h", s) }
        return nil
    }

    public var claudePrimary: (tag: String, window: WatchQuotaWindow)? {
        if !isFreeTier, let s = claudeShort { return ("5h", s) }
        if let w = claudeWeekly { return ("7d", w) }
        if let s = claudeShort { return ("5h", s) }
        return nil
    }

    public var primaryComplicationMetric: (provider: String, isClaude: Bool, tag: String, window: WatchQuotaWindow)? {
        if preferClaude {
            if let c = claudePrimary { return ("Claude", true, c.tag, c.window) }
            if let g = geminiPrimary { return ("Gemini", false, g.tag, g.window) }
        } else {
            if let g = geminiPrimary { return ("Gemini", false, g.tag, g.window) }
            if let c = claudePrimary { return ("Claude", true, c.tag, c.window) }
        }
        return nil
    }
}

nonisolated public struct WatchConversationSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let workspaceName: String
    public let status: WatchTaskStatus
    public let stepCount: Int
    public let lastModified: Date?
    public let isUnread: Bool
    public let hasRunningTasks: Bool
    public let latestAction: String?
    public let pendingApproval: WatchPendingApprovalSummary?

    public var displayWorkspace: String {
        let trimmed = workspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Chat" : trimmed
    }
}

nonisolated public struct WatchContextEnvelope: Codable, Hashable, Sendable {
    public let version: Int
    public let syncedAt: Date
    public let isPaired: Bool
    public let isDemo: Bool
    public let phoneThemeMode: String
    public let runningCount: Int
    public let pendingActionCount: Int
    public let conversations: [WatchConversationSummary]
    public let quota: WatchQuotaSnapshot?

    public static func demoSample(now: Date = Date()) -> WatchContextEnvelope {
        let approval = WatchPendingApprovalSummary(
            stepIndex: 12,
            kind: "run_command",
            kindLabel: "执行终端命令",
            redactedTarget: "kubectl rollout restart deploy/mgy-api -n prod --token=***",
            descriptionText: "重启生产网关无状态副本",
            requiresPhoneReview: false
        )
        let items: [WatchConversationSummary] = [
            WatchConversationSummary(
                id: "demo-0017-cmd-approval",
                title: "生产集群灰度发布与缓存清理",
                workspaceName: "deploy-scripts",
                status: .action,
                stepCount: 12,
                lastModified: now.addingTimeInterval(-45),
                isUnread: false,
                hasRunningTasks: false,
                latestAction: "kubectl rollout restart deploy/mgy-api...",
                pendingApproval: approval
            ),
            WatchConversationSummary(
                id: "demo-0012-swarm",
                title: "重构小组件与手表同步链路",
                workspaceName: "Multigravity",
                status: .running,
                stepCount: 18,
                lastModified: now.addingTimeInterval(-20),
                isUnread: false,
                hasRunningTasks: true,
                latestAction: "正在编译校验 WatchConnectivity 数据模型",
                pendingApproval: nil
            ),
            WatchConversationSummary(
                id: "demo-0005-redesign",
                title: "Antigravity 纯白与黑曜深色对齐",
                workspaceName: "Multigravity",
                status: .completed,
                stepCount: 9,
                lastModified: now.addingTimeInterval(-300),
                isUnread: false,
                hasRunningTasks: false,
                latestAction: "已完成双主题令牌校准并通过对比度测试",
                pendingApproval: nil
            )
        ]
        let quota = WatchQuotaSnapshot(
            accountTitle: "alex@antigravity.dev",
            tierBadge: "ULTRA",
            isFreeTier: false,
            preferClaude: false,
            geminiShort: WatchQuotaWindow(remainingPercent: 76.4, resetAt: now.addingTimeInterval(3 * 3600 + 48 * 60), resetFriendly: "3h 48m"),
            geminiWeekly: WatchQuotaWindow(remainingPercent: 89.2, resetAt: now.addingTimeInterval(5 * 86400 + 14 * 3600), resetFriendly: "5d 14h"),
            claudeShort: WatchQuotaWindow(remainingPercent: 84.6, resetAt: now.addingTimeInterval(4 * 3600 + 12 * 60), resetFriendly: "4h 12m"),
            claudeWeekly: WatchQuotaWindow(remainingPercent: 91.5, resetAt: now.addingTimeInterval(6 * 86400 + 3 * 3600), resetFriendly: "6d 3h"),
            syncedAt: now
        )
        return WatchContextEnvelope(
            version: WatchBridgeConstants.protocolVersion,
            syncedAt: now,
            isPaired: true,
            isDemo: true,
            phoneThemeMode: "light",
            runningCount: 1,
            pendingActionCount: 1,
            conversations: items,
            quota: quota
        )
    }
}

nonisolated public struct WatchConversationDetail: Codable, Hashable, Sendable {
    public let cascadeId: String
    public let title: String
    public let workspaceName: String
    public let status: WatchTaskStatus
    public let stepCount: Int
    public let activeFocus: String?
    public let errorMessage: String?
    public let runningTasks: [WatchRunningTaskSummary]
    public let pendingApproval: WatchPendingApprovalSummary?
    public let recentEvents: [WatchTimelineEvent]
    public let syncedAt: Date
}

nonisolated public struct WatchRPCRequest: Codable, Sendable {
    public let command: String
    public let cascadeId: String?
    public let expectedStepIndex: Int?

    public init(command: String, cascadeId: String? = nil, expectedStepIndex: Int? = nil) {
        self.command = command
        self.cascadeId = cascadeId
        self.expectedStepIndex = expectedStepIndex
    }
}

nonisolated public struct WatchRPCResponse: Codable, Sendable {
    public let ok: Bool
    public let expired: Bool
    public let message: String?
    public let envelope: WatchContextEnvelope?
    public let detail: WatchConversationDetail?
}

// MARK: - Dynamic Watch App Group Store (Shared with MultigravityWatchWidgets)

nonisolated public final class WatchSharedStore: Sendable {
    public static let shared = WatchSharedStore()

    private let resolvedContainerLock = OSAllocatedUnfairLock<(resolved: Bool, url: URL?)>(initialState: (false, nil))
    private static let fallbackDefaultsKey = "mgy.watch.cached_envelope_v1"

    private init() {}

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

    private func resolveContainerURL() -> URL? {
        resolvedContainerLock.withLock { state in
            if state.resolved { return state.url }
            var candidates: [String] = []
            var seen = Set<String>()
            func add(_ raw: String?) {
                guard let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !t.isEmpty,
                      seen.insert(t).inserted else { return }
                candidates.append(t)
            }

            for g in Self.extractProvisionedGroups(from: Bundle.main.bundleURL) { add(g) }
            if Bundle.main.bundleURL.pathExtension.lowercased() == "appex" {
                let parentURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                for g in Self.extractProvisionedGroups(from: parentURL) { add(g) }
            }
            add(WatchBridgeConstants.defaultAppGroupID)
            if var bid = Bundle.main.bundleIdentifier {
                for suffix in [".watchkitapp.widgets", ".watchkitapp", ".widgets"] where bid.hasSuffix(suffix) {
                    bid = String(bid.dropLast(suffix.count))
                    break
                }
                add("group.\(bid)")
            }

            for c in candidates {
                if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: c) {
                    state = (true, url)
                    return url
                }
            }
            state = (true, nil)
            return nil
        }
    }

    public func saveEnvelope(_ envelope: WatchContextEnvelope) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(envelope) else { return }
        if let dir = resolveContainerURL() {
            let fileURL = dir.appendingPathComponent(WatchBridgeConstants.sharedEnvelopeFileName)
            try? data.write(to: fileURL, options: [.atomic])
        }
        UserDefaults.standard.set(data, forKey: Self.fallbackDefaultsKey)
    }

    public func loadEnvelope() -> WatchContextEnvelope? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let dir = resolveContainerURL() {
            let fileURL = dir.appendingPathComponent(WatchBridgeConstants.sharedEnvelopeFileName)
            if let data = try? Data(contentsOf: fileURL),
               let env = try? decoder.decode(WatchContextEnvelope.self, from: data) {
                return env
            }
        }
        if let data = UserDefaults.standard.data(forKey: Self.fallbackDefaultsKey),
           let env = try? decoder.decode(WatchContextEnvelope.self, from: data) {
            return env
        }
        return nil
    }
}

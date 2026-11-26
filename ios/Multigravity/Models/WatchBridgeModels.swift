import Foundation

// MARK: - Shared iPhone <-> Apple Watch Wire Protocol (JSON over WatchConnectivity)

nonisolated public enum WatchBridgeConstants {
    public static let contextPayloadKey = "mgy_watch_ctx_v1"
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

    public init(
        stepIndex: Int?,
        kind: String,
        kindLabel: String,
        redactedTarget: String,
        descriptionText: String? = nil,
        requiresPhoneReview: Bool = false
    ) {
        self.stepIndex = stepIndex
        self.kind = kind
        self.kindLabel = kindLabel
        self.redactedTarget = redactedTarget
        self.descriptionText = descriptionText
        self.requiresPhoneReview = requiresPhoneReview
    }
}

nonisolated public struct WatchRunningTaskSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let stepIndex: Int
    public let title: String
    public let redactedCommand: String?

    public init(id: String, stepIndex: Int, title: String, redactedCommand: String? = nil) {
        self.id = id
        self.stepIndex = stepIndex
        self.title = title
        self.redactedCommand = redactedCommand
    }
}

nonisolated public struct WatchTimelineEvent: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let role: String // "user" | "agent" | "plan" | "tools" | "error"
    public let summary: String
    public let badge: String?
    public let stepIndex: Int?

    public init(
        id: String,
        role: String,
        summary: String,
        badge: String? = nil,
        stepIndex: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.summary = summary
        self.badge = badge
        self.stepIndex = stepIndex
    }
}

nonisolated public struct WatchQuotaWindow: Codable, Hashable, Sendable {
    public let remainingPercent: Double
    public let resetAt: Date?
    public let resetFriendly: String?

    public init(remainingPercent: Double, resetAt: Date?, resetFriendly: String?) {
        self.remainingPercent = max(0, min(100, remainingPercent))
        self.resetAt = resetAt
        self.resetFriendly = resetFriendly
    }

    public var intPercent: Int {
        Int(remainingPercent.rounded())
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

    public init(
        accountTitle: String,
        tierBadge: String?,
        isFreeTier: Bool,
        preferClaude: Bool,
        geminiShort: WatchQuotaWindow?,
        geminiWeekly: WatchQuotaWindow?,
        claudeShort: WatchQuotaWindow?,
        claudeWeekly: WatchQuotaWindow?,
        syncedAt: Date
    ) {
        self.accountTitle = accountTitle
        self.tierBadge = tierBadge
        self.isFreeTier = isFreeTier
        self.preferClaude = preferClaude
        self.geminiShort = geminiShort
        self.geminiWeekly = geminiWeekly
        self.claudeShort = claudeShort
        self.claudeWeekly = claudeWeekly
        self.syncedAt = syncedAt
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

    public init(
        id: String,
        title: String,
        workspaceName: String,
        status: WatchTaskStatus,
        stepCount: Int,
        lastModified: Date?,
        isUnread: Bool,
        hasRunningTasks: Bool,
        latestAction: String? = nil,
        pendingApproval: WatchPendingApprovalSummary? = nil
    ) {
        self.id = id
        self.title = title
        self.workspaceName = workspaceName
        self.status = status
        self.stepCount = stepCount
        self.lastModified = lastModified
        self.isUnread = isUnread
        self.hasRunningTasks = hasRunningTasks
        self.latestAction = latestAction
        self.pendingApproval = pendingApproval
    }
}

nonisolated public struct WatchContextEnvelope: Codable, Hashable, Sendable {
    public let version: Int
    public let syncedAt: Date
    public let isPaired: Bool
    public let isDemo: Bool
    /// Mirrors iPhone AppSettings.themeMode ("light", "dark", "system").
    public let phoneThemeMode: String
    public let runningCount: Int
    public let pendingActionCount: Int
    public let conversations: [WatchConversationSummary]
    public let quota: WatchQuotaSnapshot?

    public init(
        version: Int = WatchBridgeConstants.protocolVersion,
        syncedAt: Date = Date(),
        isPaired: Bool,
        isDemo: Bool,
        phoneThemeMode: String,
        runningCount: Int,
        pendingActionCount: Int,
        conversations: [WatchConversationSummary],
        quota: WatchQuotaSnapshot?
    ) {
        self.version = version
        self.syncedAt = syncedAt
        self.isPaired = isPaired
        self.isDemo = isDemo
        self.phoneThemeMode = phoneThemeMode
        self.runningCount = runningCount
        self.pendingActionCount = pendingActionCount
        self.conversations = conversations
        self.quota = quota
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

    public init(
        cascadeId: String,
        title: String,
        workspaceName: String,
        status: WatchTaskStatus,
        stepCount: Int,
        activeFocus: String? = nil,
        errorMessage: String? = nil,
        runningTasks: [WatchRunningTaskSummary] = [],
        pendingApproval: WatchPendingApprovalSummary? = nil,
        recentEvents: [WatchTimelineEvent] = [],
        syncedAt: Date = Date()
    ) {
        self.cascadeId = cascadeId
        self.title = title
        self.workspaceName = workspaceName
        self.status = status
        self.stepCount = stepCount
        self.activeFocus = activeFocus
        self.errorMessage = errorMessage
        self.runningTasks = runningTasks
        self.pendingApproval = pendingApproval
        self.recentEvents = recentEvents
        self.syncedAt = syncedAt
    }
}

nonisolated public struct WatchRPCRequest: Codable, Sendable {
    public let command: String // "fetch_snapshot" | "fetch_detail" | "approve_action" | "reject_action" | "stop_task"
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

    public init(
        ok: Bool,
        expired: Bool = false,
        message: String? = nil,
        envelope: WatchContextEnvelope? = nil,
        detail: WatchConversationDetail? = nil
    ) {
        self.ok = ok
        self.expired = expired
        self.message = message
        self.envelope = envelope
        self.detail = detail
    }
}

// MARK: - Watch-Safe Text Sanitization & Code-Block Compaction

nonisolated public enum WatchTextSanitizer {
    public static func redactSensitiveText(_ raw: String) -> String {
        var out = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { return "" }
        let patterns: [(String, String)] = [
            (#"(?i)(Bearer\s+)[A-Za-z0-9._\-~+/=]+"#, "$1***"),
            (#"(?i)((?:token|api[_-]?key|password|passwd|secret|auth_token|access_key)\s*[=:]\s*)[^\s&"']+"#, "$1***"),
            (#"(-w\s+)[^\s"']+"#, "$1***")
        ]
        for (pat, repl) in patterns {
            if let regex = try? NSRegularExpression(pattern: pat) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = regex.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: repl)
            }
        }
        if out.count > 220 {
            return String(out.prefix(220)) + "…"
        }
        return out
    }

    /// Compacts Markdown prose for small Apple Watch screens: collapses fenced code blocks into a concise badge
    /// and strips noisy HTML / heading markers while keeping readable conclusions.
    public static func compactMessage(_ raw: String, maxChars: Int = 140) -> (summary: String, codeBadge: String?) {
        var text = raw
        var codeBlockLines = 0
        var codeBlockCount = 0

        if let fenceRegex = try? NSRegularExpression(pattern: #"```[\s\S]*?```"#, options: []) {
            let ns = text as NSString
            let matches = fenceRegex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            codeBlockCount = matches.count
            for m in matches {
                let snippet = ns.substring(with: m.range)
                let lines = max(1, snippet.components(separatedBy: .newlines).count - 2)
                codeBlockLines += lines
            }
            if codeBlockCount > 0 {
                text = fenceRegex.stringByReplacingMatches(
                    in: text,
                    options: [],
                    range: NSRange(location: 0, length: ns.length),
                    withTemplate: " "
                )
            }
        }

        text = text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let badge: String? = codeBlockCount > 0
            ? (codeBlockCount == 1 ? "代码片段 · \(codeBlockLines)行" : "\(codeBlockCount)段代码 · \(codeBlockLines)行")
            : nil

        if text.isEmpty {
            return (badge != nil ? "包含代码或配置输出" : "", badge)
        }
        if text.count > maxChars {
            return (String(text.prefix(maxChars)) + "…", badge)
        }
        return (text, badge)
    }
}

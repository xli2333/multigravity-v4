import Foundation

public struct CockpitQuotaResponse: Codable, Sendable {
    public let currentAccount: CockpitAccountQuota?
    public let accounts: [CockpitAccountQuota]
    public let updatedAt: Int64
    /// "cockpit" or "live"; nil from older gateways.
    public let source: String?
    /// nil from older gateways (treated as installed).
    public let cockpitInstalled: Bool?
    public let cockpitHint: String?
    
    /// 网关未配置 Cockpit 时为 true,此时只有当前账号的实时额度。
    public var needsCockpitInstall: Bool { cockpitInstalled == false }
    
    enum CodingKeys: String, CodingKey {
        case currentAccount = "current_account"
        case accounts
        case updatedAt = "updated_at"
        case source
        case cockpitInstalled = "cockpit_installed"
        case cockpitHint = "cockpit_hint"
    }
}

public enum QuotaBucketKind: String, CaseIterable, Codable, Sendable {
    case gemini5h = "gemini_5h"
    case geminiWeekly = "gemini_weekly"
    case claude5h = "claude_5h"
    case claudeWeekly = "claude_weekly"

    public var displayTitle: String {
        switch self {
        case .gemini5h: return "Gemini · 5h"
        case .geminiWeekly: return "Gemini · Weekly"
        case .claude5h: return "Claude · 5h"
        case .claudeWeekly: return "Claude · Weekly"
        }
    }
}

public struct CockpitAccountQuota: Codable, Identifiable, Sendable {
    public let id: String
    public let email: String
    public let name: String
    public let subscriptionTier: String?
    public let isCurrent: Bool
    public let claude5h: CockpitQuotaBucket?
    public let claudeWeekly: CockpitQuotaBucket?
    public let gemini5h: CockpitQuotaBucket?
    public let geminiWeekly: CockpitQuotaBucket?
    public let gemini4Argon: CockpitQuotaBucket?
    public let updatedAt: Int64
    
    enum CodingKeys: String, CodingKey {
        case id, email, name
        case subscriptionTier = "subscription_tier"
        case isCurrent = "is_current"
        case claude5h = "claude_5h"
        case claudeWeekly = "claude_weekly"
        case gemini5h = "gemini_5h"
        case geminiWeekly = "gemini_weekly"
        case gemini4Argon = "gemini_4_argon"
        case updatedAt = "updated_at"
    }
    
    public var displayName: String {
        if !name.isEmpty {
            return "\(name) (\(email))"
        }
        return email
    }

    public var isFreeTier: Bool {
        subscriptionTier?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "FREE" ||
            (gemini5h == nil && claude5h == nil)
    }

    public func bucket(for kind: QuotaBucketKind) -> CockpitQuotaBucket? {
        switch kind {
        case .gemini5h: return gemini5h
        case .geminiWeekly: return geminiWeekly
        case .claude5h: return claude5h
        case .claudeWeekly: return claudeWeekly
        }
    }

    /// Resolves the effective quota kind and bucket to display on the home quota bar,
    /// falling back gracefully when the preferred bucket is unavailable (e.g. FREE accounts).
    public func resolvedQuotaDisplay(preferred: QuotaBucketKind) -> (kind: QuotaBucketKind, bucket: CockpitQuotaBucket)? {
        if let selected = bucket(for: preferred) {
            return (preferred, selected)
        }
        let fallbackOrder: [QuotaBucketKind] = isFreeTier
            ? [.geminiWeekly, .claudeWeekly]
            : [.gemini5h, .geminiWeekly, .claude5h, .claudeWeekly]
        for kind in fallbackOrder {
            if let fallback = bucket(for: kind) {
                return (kind, fallback)
            }
        }
        return nil
    }
}

public struct CockpitQuotaBucket: Codable, Sendable {
    public let remainingFraction: Double
    public let remainingPercent: Double
    public let resetTime: String?
    public let resetFriendly: String?
    
    enum CodingKeys: String, CodingKey {
        case remainingFraction = "remaining_fraction"
        case remainingPercent = "remaining_percent"
        case resetTime = "reset_time"
        case resetFriendly = "reset_friendly"
    }

    /// Parses `resetTime` ISO-8601 string into a `Date`.
    public var parsedResetDate: Date? {
        guard let rt = resetTime?.trimmingCharacters(in: .whitespacesAndNewlines), !rt.isEmpty else { return nil }
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFull.date(from: rt) { return d }
        let isoStd = ISO8601DateFormatter()
        isoStd.formatOptions = [.withInternetDateTime]
        if let d = isoStd.date(from: rt) { return d }
        let cleanRt = rt.components(separatedBy: ".").first ?? rt
        let isoBare = ISO8601DateFormatter()
        isoBare.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        if let d = isoBare.date(from: cleanRt) ?? isoBare.date(from: cleanRt + "Z") { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: cleanRt)
    }

    /// Formats the remaining time until quota recovery in natural Chinese:
    /// - >= 24h: e.g. "3天5小时后恢复" / "3天后恢复"
    /// - >= 1h:  e.g. "4小时57分后恢复" / "4小时后恢复"
    /// - < 1h:   e.g. "42分钟后恢复" / "即将恢复"
    public func recoveryCountdownText(now: Date = Date()) -> String? {
        if let target = parsedResetDate {
            let remaining = target.timeIntervalSince(now)
            if remaining <= 60 {
                return "即将恢复"
            }
            let totalMinutes = Int(remaining / 60)
            let days = totalMinutes / (24 * 60)
            let hours = (totalMinutes % (24 * 60)) / 60
            let mins = totalMinutes % 60
            if days > 0 {
                return hours > 0 ? "\(days)天\(hours)小时后恢复" : "\(days)天后恢复"
            }
            if hours > 0 {
                return mins > 0 ? "\(hours)小时\(mins)分后恢复" : "\(hours)小时后恢复"
            }
            return "\(max(1, mins))分钟后恢复"
        }

        if let raw = resetFriendly?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let lower = raw.lowercased()
            if lower.contains("恢复") || lower.contains("满") {
                return raw
            }
            var translated = raw
            translated = translated.replacingOccurrences(of: "d ", with: "天")
            translated = translated.replacingOccurrences(of: "d", with: "天")
            translated = translated.replacingOccurrences(of: "h ", with: "小时")
            translated = translated.replacingOccurrences(of: "h", with: "小时")
            translated = translated.replacingOccurrences(of: "m", with: "分")
            translated = translated.replacingOccurrences(of: " ", with: "")
            return "\(translated)后恢复"
        }
        return nil
    }

    public func calculateWeeklyPace(totalWindowHours: Double = 168.0) -> WeeklyPaceInfo? {
        guard let rt = resetTime?.trimmingCharacters(in: .whitespacesAndNewlines), !rt.isEmpty else { return nil }
        let cleanRt = rt.components(separatedBy: ".").first ?? rt
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        if let date = isoFmt.date(from: cleanRt) ?? isoFmt.date(from: cleanRt + "Z") {
            return evaluatePace(date: date, totalWindowHours: totalWindowHours)
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let fallbackDate = df.date(from: cleanRt) {
            return evaluatePace(date: fallbackDate, totalWindowHours: totalWindowHours)
        }
        return nil
    }

    public func calculatePaceForTitle(_ title: String, tier: String? = nil) -> WeeklyPaceInfo? {
        let lower = title.lowercased()
        let hours: Double
        if lower.contains("carbon") {
            hours = 168.0
        } else if lower.contains("argon") {
            let isUltra = tier?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().contains("ULTRA") == true
            hours = isUltra ? 5.0 : 168.0
        } else if lower.contains("5h") {
            hours = 5.0
        } else if lower.contains("weekly") {
            hours = 168.0
        } else {
            hours = 168.0
        }
        return calculateWeeklyPace(totalWindowHours: hours)
    }

    private func evaluatePace(date: Date, totalWindowHours: Double) -> WeeklyPaceInfo? {
        let remainingSeconds = date.timeIntervalSinceNow
        guard remainingSeconds > 0 else { return nil }
        let totalSeconds = totalWindowHours * 3600.0
        let expectedRemaining = min(100.0, max(0.0, (remainingSeconds / totalSeconds) * 100.0))
        let actualRemaining = min(100.0, max(0.0, remainingPercent))
        let used = min(100.0, max(0.0, 100.0 - actualRemaining))
        let expectedUsed = min(100.0, max(0.0, 100.0 - expectedRemaining))
        let delta = actualRemaining - expectedRemaining
        let isOver = delta < -1.0

        let deltaAbsStr = String(format: "%.1f%%", abs(delta))
        let status: String
        if isOver {
            status = String(localized: "消耗偏快 (-\(deltaAbsStr))")
        } else if abs(delta) <= 1.0 {
            status = String(localized: "匀速正常 (±\(deltaAbsStr))")
        } else {
            status = String(localized: "节奏充裕 (+\(deltaAbsStr))")
        }

        return WeeklyPaceInfo(
            actualRemainingPercent: actualRemaining,
            expectedRemainingPercent: expectedRemaining,
            usedPercent: used,
            expectedUsedPercent: expectedUsed,
            paceDeltaPercent: delta,
            isOverPacing: isOver,
            statusText: status,
            windowHours: totalWindowHours,
            resetCountdownDisplay: resetFriendly ?? String(localized: "计算中")
        )
    }
}

public struct WeeklyPaceInfo: Sendable {
    public let actualRemainingPercent: Double
    public let expectedRemainingPercent: Double
    public let usedPercent: Double
    public let expectedUsedPercent: Double
    public let paceDeltaPercent: Double
    public let isOverPacing: Bool
    public let statusText: String
    public let windowHours: Double
    public let resetCountdownDisplay: String
    
    public var windowLabel: String {
        windowHours <= 5.0 ? String(localized: "5小时") : String(localized: "7天")
    }
}

public struct ModelTokenBreakdown: Codable, Identifiable, Sendable, Equatable {
    public var id: String { model }
    public let model: String
    public let total: Int64
    public let input: Int64
    public let output: Int64
    public let cacheRead: Int64
    public let thinking: Int64
    public let steps: Int
    public let costUsd: Double

    public init(
        model: String,
        total: Int64,
        input: Int64 = 0,
        output: Int64 = 0,
        cacheRead: Int64 = 0,
        thinking: Int64 = 0,
        steps: Int = 0,
        costUsd: Double = 0
    ) {
        self.model = model
        self.total = total
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.thinking = thinking
        self.steps = steps
        self.costUsd = costUsd
    }

    enum CodingKeys: String, CodingKey {
        case model, total, input, output, thinking, steps
        case cacheRead = "cache_read"
        case costUsd = "cost_usd"
    }
}

public struct DailyTokenRecord: Codable, Identifiable, Sendable, Equatable {
    public var id: String { date }
    public let date: String
    public let total: Int64
    public let input: Int64
    public let output: Int64
    public let cacheRead: Int64
    public let thinking: Int64
    public let steps: Int
    public let costUsd: Double
    public let models: [String: Int64]
    public let modelDetails: [String: ModelTokenBreakdown]?

    public init(
        date: String,
        total: Int64,
        input: Int64,
        output: Int64,
        cacheRead: Int64,
        thinking: Int64,
        steps: Int,
        costUsd: Double,
        models: [String: Int64],
        modelDetails: [String: ModelTokenBreakdown]? = nil
    ) {
        self.date = date
        self.total = total
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.thinking = thinking
        self.steps = steps
        self.costUsd = costUsd
        self.models = models
        self.modelDetails = modelDetails
    }

    enum CodingKeys: String, CodingKey {
        case date, total, input, output, thinking, steps, models
        case cacheRead = "cache_read"
        case costUsd = "cost_usd"
        case modelDetails = "model_details"
    }
}

public struct TokenHistorySummary: Codable, Sendable, Equatable {
    public let totalTokens: Int64
    public let todayTokens: Int64
    public let last7dTokens: Int64
    public let desktopTokens: Int64
    public let cliTokens: Int64
    public let estimatedCostUsd: Double
    public let estimatedCostCny: Double
    public let activeDays: Int
    public let totalSteps: Int

    enum CodingKeys: String, CodingKey {
        case totalTokens = "total_tokens"
        case todayTokens = "today_tokens"
        case last7dTokens = "last_7d_tokens"
        case desktopTokens = "desktop_tokens"
        case cliTokens = "cli_tokens"
        case estimatedCostUsd = "estimated_cost_usd"
        case estimatedCostCny = "estimated_cost_cny"
        case activeDays = "active_days"
        case totalSteps = "total_steps"
    }
}

public struct TokenHistoryResponse: Codable, Sendable, Equatable {
    public let updatedAt: Int64
    public let summary: TokenHistorySummary
    public let dailyMatrix: [DailyTokenRecord]
    public let modelSummary: [ModelTokenBreakdown]?

    public init(
        updatedAt: Int64,
        summary: TokenHistorySummary,
        dailyMatrix: [DailyTokenRecord],
        modelSummary: [ModelTokenBreakdown]? = nil
    ) {
        self.updatedAt = updatedAt
        self.summary = summary
        self.dailyMatrix = dailyMatrix
        self.modelSummary = modelSummary
    }

    /// 后端下发毫秒级 Unix 时间戳；兼容秒级历史结构并转为本地可格式化 Date
    public var updatedAtDate: Date {
        let seconds = updatedAt >= 10_000_000_000 ? Double(updatedAt) / 1000.0 : Double(updatedAt)
        return Date(timeIntervalSince1970: seconds)
    }

    /// 返回按总 Token 降序的全量模型明细（兼容旧网关未下发 model_summary 的情况）
    public var resolvedModelSummary: [ModelTokenBreakdown] {
        if let list = modelSummary, !list.isEmpty {
            return list.sorted { lhs, rhs in
                if lhs.total != rhs.total { return lhs.total > rhs.total }
                return lhs.model < rhs.model
            }
        }
        var totals: [String: Int64] = [:]
        for rec in dailyMatrix {
            for (m, cnt) in rec.models where cnt > 0 {
                totals[m, default: 0] += cnt
            }
        }
        return totals.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.map { ModelTokenBreakdown(model: $0.key, total: $0.value) }
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case updatedAt = "updated_at"
        case dailyMatrix = "daily_matrix"
        case modelSummary = "model_summary"
    }
}

public struct ContextMeterItem: Codable, Sendable, Equatable {
    public let usedTokens: Int64
    public let maxTokens: Int64
    public let percentage: Double
    public let inputTokens: Int64?
    public let outputTokens: Int64?
    public let cacheReadTokens: Int64?
    public let thinkingTokens: Int64?
    public let timeToFirstTokenSec: Double?
    public let streamingDurationSec: Double?
    public let tokensPerSecond: Double?
    public let isOverflow: Bool?
    public let errorKind: String?
}

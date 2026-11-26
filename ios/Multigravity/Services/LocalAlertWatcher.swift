import Foundation
import UIKit
import UserNotifications

/// Client-side 1:1 notification and Live Activity state machine mirroring Go `Watcher` (`watcher.go`),
/// `Notifier` (`notifier.go` + `messages.go`), `LiveActivityDispatcher` (`live_activity.go`),
/// and `QuotaAlerter` (`cockpit/quota_alert.go`).
///
/// Works over the persistent `/gateway/events` WebSocket + ETag-cached `/gateway/cascade/messages` HTTP endpoint
/// so self-hosted gateways deliver identical alerts, custom sounds, auto-dismissal of resolved approvals,
/// quota warnings, and real-time Dynamic Island updates without any third-party APNs server.
@MainActor
public final class LocalAlertWatcher {
    public static let shared = LocalAlertWatcher()

    private struct SessionTrack {
        var wasRunning: Bool
        var lastRawStatus: ConversationItem.ConversationStatus
        var lastSteps: Int
        var title: String
        var waitingForBackground: Bool = false
        var pendingApprovalKey: String = ""
        var pendingApprovalSince: Date? = nil
        var fetchRetryCount: Int = 0
        var lastUpdated: Date
    }

    private struct PersistedQuotaAlertEntry: Codable {
        var level: String
        var resetTime: String?
        var firedAt: TimeInterval
    }

    private struct QuotaSample {
        let at: Date
        let fraction: Double
    }

    private struct QuotaBucketTracker {
        var samples: [QuotaSample] = []
        var sampleKey: String = ""
        var hasPrev: Bool = false
        var prevFrac: Double = 0
        var prevReset: Date? = nil
        var prevRaw: String = ""
        var prevAt: Date = .distantPast
    }

    private static let dedupStorageKey = "antigravity.local_alert_dedup_v1"
    private static let quotaStateStorageKey = "antigravity.local_quota_alert_state_v1"
    private static let dedupTTLSeconds: TimeInterval = 2 * 3600
    private static let pendingApprovalPollTTL: TimeInterval = 2 * 3600
    private static let maxDetailConcurrency = 4
    private static let warnQuotaFraction = 0.20
    private static let criticalQuotaFraction = 0.05

    private var knownSessions: [String: SessionTrack] = [:]
    private var hasInitialSync: Bool = false
    private var syncedHostKey: String? = nil
    private var dedupMap: [String: TimeInterval] = [:]

    private var isScanning: Bool = false
    private var queuedScan: (conversations: [ConversationItem], baseURL: URL)? = nil

    private var quotaState: [String: PersistedQuotaAlertEntry] = [:]
    private var quotaTrackers: [String: QuotaBucketTracker] = [:]
    private var lastQuotaAccount: String = ""
    private var lastQuotaSeenUpdatedAt: Int64 = 0

    private init() {
        loadDedup()
        loadQuotaState()
    }

    /// True when any tracked session is running, waiting for background tasks/subagents, or awaiting approval.
    public var hasActiveTrackedWork: Bool {
        knownSessions.values.contains {
            $0.wasRunning || $0.waitingForBackground || !$0.pendingApprovalKey.isEmpty
        }
    }

    public func resetForUnpair() {
        knownSessions.removeAll()
        hasInitialSync = false
        syncedHostKey = nil
        queuedScan = nil
        quotaTrackers.removeAll()
        lastQuotaAccount = ""
        lastQuotaSeenUpdatedAt = 0
    }

    // MARK: - Conversation Scan Loop

    public func scan(conversations: [ConversationItem], baseURL: URL) async {
        let settings = AppSettings.shared
        guard settings.isPaired, !settings.isDemoMode else { return }

        let scoped = conversations.filter { !$0.isDraft && !$0.isSubagent }
        if isScanning {
            queuedScan = (scoped, baseURL)
            return
        }

        isScanning = true
        defer { isScanning = false }

        await performScan(conversations: scoped, baseURL: baseURL)

        while let next = queuedScan {
            queuedScan = nil
            await performScan(conversations: next.conversations, baseURL: next.baseURL)
        }
        WatchSyncManager.shared.updateConversations(scoped)
    }

    private func performScan(conversations: [ConversationItem], baseURL: URL) async {
        let settings = AppSettings.shared
        guard settings.isPaired, !settings.isDemoMode else { return }
        guard !conversations.isEmpty else { return }

        let hostKey = (baseURL.host ?? baseURL.absoluteString).lowercased()
        if let prevHost = syncedHostKey, prevHost != hostKey {
            // Do not reset if switching between LAN and Cloudflare tunnel of the same paired gateway!
            syncedHostKey = hostKey
        } else if syncedHostKey == nil {
            syncedHostKey = hostKey
        }

        let now = Date()
        pruneDedup(now: now)
        cleanupStaleKnownSessions(now: now)

        let alertsEnabled = settings.enablePushNotifications
        let liveEnabled = settings.enableLiveActivities && ActivityManager.shared.isLiveActivityEnabled
        guard alertsEnabled || liveEnabled else { return }

        // 1. Initial baseline sync: record already-completed historical sessions so startup never spams old alerts.
        if !hasInitialSync {
            var initialActiveItems: [ConversationItem] = []
            for item in conversations {
                let activeNow = item.status.isRunning || item.status.needsAction || item.hasRunningTasks || item.hasRunningSubagents
                knownSessions[item.id] = SessionTrack(
                    wasRunning: activeNow,
                    lastRawStatus: item.status,
                    lastSteps: item.stepCount,
                    title: item.title,
                    waitingForBackground: item.hasRunningTasks || item.hasRunningSubagents,
                    lastUpdated: now
                )
                if !activeNow {
                    recordDedup("done:\(item.id):\(item.stepCount)", now: now)
                    if item.status.isError {
                        recordDedup("fail:\(item.id):\(item.stepCount)", now: now)
                    }
                } else {
                    initialActiveItems.append(item)
                }
            }
            hasInitialSync = true
            saveDedup()

            if !initialActiveItems.isEmpty {
                let detailMap = await fetchDetailsConcurrently(items: initialActiveItems, baseURL: baseURL)
                for item in initialActiveItems {
                    guard let details = detailMap[item.id] else { continue }
                    let pKey = Self.approvalKey(for: details)
                    let inProg = Self.isCascadeInProgress(details: details, hasRunningSubagents: item.hasRunningSubagents)
                    if var st = knownSessions[item.id] {
                        st.pendingApprovalKey = pKey
                        st.pendingApprovalSince = pKey.isEmpty ? nil : now
                        st.wasRunning = details.status == "CASCADE_RUN_STATUS_RUNNING"
                        st.waitingForBackground = !st.wasRunning && inProg
                        knownSessions[item.id] = st
                    }
                    if liveEnabled {
                        syncLiveActivityFromDetails(cascadeId: item.id, fallbackTitle: item.title, details: details, hasRunningSubagents: item.hasRunningSubagents)
                    }
                    if alertsEnabled {
                        if let pi = details.pendingInteraction {
                            await notifyAction(cascadeId: item.id, title: details.title ?? item.title, interaction: pi)
                        } else if details.canProceed {
                            await notifyProceed(cascadeId: item.id, title: details.title ?? item.title, totalSteps: details.totalSteps)
                        }
                    }
                }
            }
            return
        }

        // 2. Pass 1: identify sessions that are active, transitioning, waiting on background tasks, or resolving an approval.
        var detailCandidates: [ConversationItem] = []
        for item in conversations {
            let prev = knownSessions[item.id]
            let isCurrentlyActive = item.status.isRunning || item.status.needsAction || item.hasRunningTasks || item.hasRunningSubagents
            let transitionedFromRunning = (prev?.wasRunning == true) && !item.status.isRunning
            let wasWaitingBg = prev?.waitingForBackground == true
            let watchPendingApproval: Bool = {
                guard let prev, !prev.pendingApprovalKey.isEmpty else { return false }
                if let since = prev.pendingApprovalSince, now.timeIntervalSince(since) <= Self.pendingApprovalPollTTL {
                    return true
                }
                return prev.lastRawStatus != item.status || prev.lastSteps != item.stepCount
            }()
            let hasLiveCard = liveEnabled && ActivityManager.shared.hasActiveActivity(for: item.id)

            // Detect brand-new session that started and finished within a single poll window (e.g. fast 1-step reply while backgrounded)
            let brandNewCompleted = (prev == nil)
                && !isCurrentlyActive
                && item.stepCount > 0
                && (item.lastModified.map { now.timeIntervalSince($0) < 45 } ?? false)

            if isCurrentlyActive || transitionedFromRunning || wasWaitingBg || watchPendingApproval || hasLiveCard || brandNewCompleted {
                detailCandidates.append(item)
            } else {
                var updated = prev ?? SessionTrack(
                    wasRunning: false,
                    lastRawStatus: item.status,
                    lastSteps: item.stepCount,
                    title: item.title,
                    lastUpdated: now
                )
                if prev == nil || updated.lastRawStatus != item.status || updated.lastSteps != item.stepCount {
                    updated.lastUpdated = now
                }
                updated.wasRunning = false
                updated.lastRawStatus = item.status
                updated.lastSteps = item.stepCount
                if !item.title.isEmpty && item.title != "未命名会话" {
                    updated.title = item.title
                }
                knownSessions[item.id] = updated
            }
        }

        guard !detailCandidates.isEmpty else { return }

        // 3. Pass 2: bounded concurrent detail fetches (uses APIClient's ETag 304 cache!)
        let detailMap = await fetchDetailsConcurrently(items: detailCandidates, baseURL: baseURL)

        // 4. Pass 3: evaluate transitions & fire notifications + Live Activity updates
        for item in detailCandidates {
            let id = item.id
            let prev = knownSessions[id]
            let prevWasRunning = prev?.wasRunning ?? false
            let prevWaitingBg = prev?.waitingForBackground ?? false
            let prevPendingKey = prev?.pendingApprovalKey ?? ""
            let prevPendingSince = prev?.pendingApprovalSince
            let prevRetries = prev?.fetchRetryCount ?? 0

            let details = detailMap[id]
            let resolvedTitle: String = {
                if let dt = details?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !dt.isEmpty, dt != "未命名会话" {
                    return ConversationItem.sanitizeTitle(dt)
                }
                if !item.title.isEmpty, item.title != "未命名会话" {
                    return item.title
                }
                if let pt = prev?.title, !pt.isEmpty, pt != "未命名会话" {
                    return pt
                }
                return item.title
            }()

            var nextWasRunning = item.status.isRunning
            var nextWaitingBg = prevWaitingBg
            var nextPendingKey = prevPendingKey
            var nextPendingSince = prevPendingSince
            var nextRetries = 0

            func setPending(_ key: String) {
                nextPendingKey = key
                if key.isEmpty {
                    nextPendingSince = nil
                } else if key != prevPendingKey || nextPendingSince == nil {
                    nextPendingSince = now
                }
            }

            if item.status.isRunning {
                nextWasRunning = true
                nextWaitingBg = false
                if let details {
                    let curKey = Self.approvalKey(for: details)
                    if curKey.isEmpty && !prevPendingKey.isEmpty {
                        dismissApproval(cascadeId: id)
                    }
                    setPending(curKey)
                    if liveEnabled {
                        syncLiveActivityFromDetails(cascadeId: id, fallbackTitle: resolvedTitle, details: details, hasRunningSubagents: item.hasRunningSubagents)
                    }
                    if alertsEnabled {
                        if let pi = details.pendingInteraction {
                            await notifyAction(cascadeId: id, title: resolvedTitle, interaction: pi)
                        } else if details.canProceed {
                            await notifyProceed(cascadeId: id, title: resolvedTitle, totalSteps: details.totalSteps)
                        }
                    }
                }
            } else if prevWasRunning || prev == nil {
                // Transition: RUNNING -> non-RUNNING (or brand-new fast session)
                guard let details else {
                    if prevWasRunning && prevRetries < 3 {
                        var retryState = prev!
                        retryState.fetchRetryCount = prevRetries + 1
                        retryState.lastUpdated = now
                        knownSessions[id] = retryState
                        continue
                    }
                    // Fallback to summary status after 3 retries
                    if item.stepCount > 0 && prevWasRunning {
                        if item.status.isError {
                            if alertsEnabled { await notifyFailed(cascadeId: id, title: resolvedTitle, totalSteps: item.stepCount) }
                            if liveEnabled { ActivityManager.shared.endActivity(for: id, finalStatus: "FAILED") }
                        } else if item.status.needsAction {
                            // Keep waiting if action needed
                        } else {
                            if alertsEnabled { await notifyCompleted(cascadeId: id, title: resolvedTitle, totalSteps: item.stepCount) }
                            if liveEnabled { ActivityManager.shared.endActivity(for: id, finalStatus: "COMPLETED") }
                        }
                    }
                    setPending("")
                    nextWasRunning = false
                    nextWaitingBg = false
                    knownSessions[id] = SessionTrack(
                        wasRunning: false,
                        lastRawStatus: item.status,
                        lastSteps: item.stepCount,
                        title: resolvedTitle,
                        waitingForBackground: false,
                        pendingApprovalKey: "",
                        pendingApprovalSince: nil,
                        fetchRetryCount: 0,
                        lastUpdated: now
                    )
                    continue
                }

                let curKey = Self.approvalKey(for: details)
                let inProg = Self.isCascadeInProgress(details: details, hasRunningSubagents: item.hasRunningSubagents || item.hasRunningTasks)

                if let pi = details.pendingInteraction {
                    setPending(curKey)
                    nextWaitingBg = false
                    if alertsEnabled { await notifyAction(cascadeId: id, title: resolvedTitle, interaction: pi) }
                    if liveEnabled { syncLiveActivityFromDetails(cascadeId: id, fallbackTitle: resolvedTitle, details: details, hasRunningSubagents: item.hasRunningSubagents) }
                } else if details.canProceed {
                    setPending(curKey)
                    nextWaitingBg = false
                    if alertsEnabled { await notifyProceed(cascadeId: id, title: resolvedTitle, totalSteps: details.totalSteps) }
                    if liveEnabled { syncLiveActivityFromDetails(cascadeId: id, fallbackTitle: resolvedTitle, details: details, hasRunningSubagents: item.hasRunningSubagents) }
                } else if (details.hasError || details.status == "CASCADE_RUN_STATUS_ERROR" || details.status == "CASCADE_RUN_STATUS_FAILED" || item.status.isError) && max(details.totalSteps, item.stepCount) > 0 {
                    if !prevPendingKey.isEmpty { dismissApproval(cascadeId: id) }
                    setPending("")
                    nextWaitingBg = false
                    let total = max(details.totalSteps, item.stepCount)
                    if alertsEnabled { await notifyFailed(cascadeId: id, title: resolvedTitle, totalSteps: total) }
                    if liveEnabled { ActivityManager.shared.endActivity(for: id, finalStatus: "FAILED") }
                } else if inProg {
                    if !prevPendingKey.isEmpty { dismissApproval(cascadeId: id) }
                    setPending("")
                    nextWaitingBg = true
                    if liveEnabled { syncLiveActivityFromDetails(cascadeId: id, fallbackTitle: resolvedTitle, details: details, hasRunningSubagents: item.hasRunningSubagents) }
                } else if max(details.totalSteps, item.stepCount) > 0 {
                    if !prevPendingKey.isEmpty { dismissApproval(cascadeId: id) }
                    setPending("")
                    nextWaitingBg = false
                    let total = max(details.totalSteps, item.stepCount)
                    if alertsEnabled { await notifyCompleted(cascadeId: id, title: resolvedTitle, totalSteps: total) }
                    if liveEnabled { ActivityManager.shared.endActivity(for: id, finalStatus: "COMPLETED") }
                }
                nextWasRunning = (details.status == "CASCADE_RUN_STATUS_RUNNING")
            } else if prevWaitingBg {
                if let details {
                    let inProg = Self.isCascadeInProgress(details: details, hasRunningSubagents: item.hasRunningSubagents || item.hasRunningTasks)
                    let curKey = Self.approvalKey(for: details)
                    if !inProg {
                        nextWaitingBg = false
                        if let pi = details.pendingInteraction {
                            setPending(curKey)
                            if alertsEnabled { await notifyAction(cascadeId: id, title: resolvedTitle, interaction: pi) }
                            if liveEnabled { syncLiveActivityFromDetails(cascadeId: id, fallbackTitle: resolvedTitle, details: details, hasRunningSubagents: item.hasRunningSubagents) }
                        } else if details.canProceed {
                            setPending(curKey)
                            if alertsEnabled { await notifyProceed(cascadeId: id, title: resolvedTitle, totalSteps: details.totalSteps) }
                            if liveEnabled { syncLiveActivityFromDetails(cascadeId: id, fallbackTitle: resolvedTitle, details: details, hasRunningSubagents: item.hasRunningSubagents) }
                        } else if (details.hasError || details.status == "CASCADE_RUN_STATUS_ERROR" || details.status == "CASCADE_RUN_STATUS_FAILED") && details.totalSteps > 0 {
                            setPending("")
                            if alertsEnabled { await notifyFailed(cascadeId: id, title: resolvedTitle, totalSteps: details.totalSteps) }
                            if liveEnabled { ActivityManager.shared.endActivity(for: id, finalStatus: "FAILED") }
                        } else if details.totalSteps > 0 {
                            setPending("")
                            if alertsEnabled { await notifyCompleted(cascadeId: id, title: resolvedTitle, totalSteps: details.totalSteps) }
                            if liveEnabled { ActivityManager.shared.endActivity(for: id, finalStatus: "COMPLETED") }
                        }
                    } else {
                        if !prevPendingKey.isEmpty && curKey.isEmpty {
                            dismissApproval(cascadeId: id)
                            setPending("")
                        }
                        if liveEnabled {
                            syncLiveActivityFromDetails(cascadeId: id, fallbackTitle: resolvedTitle, details: details, hasRunningSubagents: item.hasRunningSubagents)
                        }
                    }
                }
            } else {
                // Idle/Action session with active approval tracking, needsAction status, or an alive Live Activity card
                if let details {
                    let curKey = Self.approvalKey(for: details)
                    let inProg = Self.isCascadeInProgress(details: details, hasRunningSubagents: item.hasRunningSubagents || item.hasRunningTasks)
                    if curKey.isEmpty && !prevPendingKey.isEmpty {
                        dismissApproval(cascadeId: id)
                        setPending("")
                        if liveEnabled {
                            if inProg {
                                syncLiveActivityFromDetails(cascadeId: id, fallbackTitle: resolvedTitle, details: details, hasRunningSubagents: item.hasRunningSubagents)
                            } else if ActivityManager.shared.hasActiveActivity(for: id) {
                                let finalStatus = (details.hasError || details.status == "CASCADE_RUN_STATUS_ERROR") ? "FAILED" : "COMPLETED"
                                ActivityManager.shared.endActivity(for: id, finalStatus: finalStatus)
                            }
                        }
                    } else if !curKey.isEmpty && curKey != prevPendingKey {
                        setPending(curKey)
                        if liveEnabled {
                            syncLiveActivityFromDetails(cascadeId: id, fallbackTitle: resolvedTitle, details: details, hasRunningSubagents: item.hasRunningSubagents)
                        }
                        if alertsEnabled {
                            if let pi = details.pendingInteraction {
                                await notifyAction(cascadeId: id, title: resolvedTitle, interaction: pi)
                            } else if details.canProceed {
                                await notifyProceed(cascadeId: id, title: resolvedTitle, totalSteps: details.totalSteps)
                            }
                        }
                    } else if liveEnabled && ActivityManager.shared.hasActiveActivity(for: id) {
                        if inProg || !curKey.isEmpty {
                            syncLiveActivityFromDetails(cascadeId: id, fallbackTitle: resolvedTitle, details: details, hasRunningSubagents: item.hasRunningSubagents)
                        } else {
                            let finalStatus = (details.hasError || details.status == "CASCADE_RUN_STATUS_ERROR") ? "FAILED" : "COMPLETED"
                            ActivityManager.shared.endActivity(for: id, finalStatus: finalStatus)
                        }
                    }
                    nextWaitingBg = !nextWasRunning && inProg
                }
            }

            knownSessions[id] = SessionTrack(
                wasRunning: nextWasRunning,
                lastRawStatus: item.status,
                lastSteps: max(item.stepCount, details?.totalSteps ?? 0),
                title: resolvedTitle,
                waitingForBackground: nextWaitingBg,
                pendingApprovalKey: nextPendingKey,
                pendingApprovalSince: nextPendingSince,
                fetchRetryCount: nextRetries,
                lastUpdated: now
            )
        }
    }

    private func fetchDetailsConcurrently(items: [ConversationItem], baseURL: URL) async -> [String: FetchMessagesResult] {
        guard !items.isEmpty else { return [:] }
        if items.count == 1, let only = items.first {
            if let res = try? await APIClient.shared.fetchMessages(cascadeId: only.id, limit: 5, baseURL: baseURL) {
                return [only.id: res]
            }
            return [:]
        }

        var out: [String: FetchMessagesResult] = [:]
        await withTaskGroup(of: (String, FetchMessagesResult?).self) { group in
            var iter = items.makeIterator()
            for _ in 0..<min(Self.maxDetailConcurrency, items.count) {
                if let next = iter.next() {
                    let cid = next.id
                    group.addTask {
                        let res = try? await APIClient.shared.fetchMessages(cascadeId: cid, limit: 5, baseURL: baseURL)
                        return (cid, res)
                    }
                }
            }
            while let (cid, res) = await group.next() {
                if let res {
                    out[cid] = res
                }
                if let next = iter.next() {
                    let nextId = next.id
                    group.addTask {
                        let nextRes = try? await APIClient.shared.fetchMessages(cascadeId: nextId, limit: 5, baseURL: baseURL)
                        return (nextId, nextRes)
                    }
                }
            }
        }
        return out
    }

    // MARK: - Live Activity Background Sync

    private func syncLiveActivityFromDetails(
        cascadeId: String,
        fallbackTitle: String,
        details: FetchMessagesResult,
        hasRunningSubagents: Bool
    ) {
        guard AppSettings.shared.enableLiveActivities, ActivityManager.shared.isLiveActivityEnabled else { return }
        guard details.parentConversationId == nil || details.parentConversationId?.isEmpty == true else { return }

        let blockingTasks = details.runningTasks.blockingTasks
        let hasPending = details.canProceed || details.pendingInteraction != nil
        let isRunning = details.status == "CASCADE_RUN_STATUS_RUNNING" || hasRunningSubagents || (details.subagents?.contains(where: \.isRunning) == true)

        let status: String
        if hasPending {
            status = "WAITING_APPROVAL"
        } else if !blockingTasks.isEmpty && !isRunning {
            status = "TASK_RUNNING"
        } else if details.hasError || details.status == "CASCADE_RUN_STATUS_ERROR" || details.status == "CASCADE_RUN_STATUS_FAILED" {
            status = "FAILED"
        } else if isRunning || !blockingTasks.isEmpty {
            status = "RUNNING"
        } else {
            status = "COMPLETED"
        }

        let primaryTask = blockingTasks.first
        let activeTaskTitle: String? = primaryTask.map { task in
            let s = (task.toolSummary ?? task.toolAction ?? task.toolName ?? "后台任务").trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.truncate(Self.sanitizePushText(s.isEmpty ? "后台任务" : s), maxChars: 40)
        }
        let activeTaskCmd: String? = primaryTask.flatMap { task in
            let c = task.commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
            return c.isEmpty ? nil : Self.truncate(Self.sanitizePushText(c), maxChars: 60)
        }

        let snapshots: [AgentTaskSnapshot] = blockingTasks.prefix(2).map { task in
            let tTitle = Self.truncate(
                Self.sanitizePushText((task.toolSummary ?? task.toolAction ?? task.toolName ?? "后台任务").trimmingCharacters(in: .whitespacesAndNewlines)),
                maxChars: 40
            )
            let cmd = task.commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
            return AgentTaskSnapshot(
                id: Self.truncate(task.id, maxChars: 32),
                title: tTitle.isEmpty ? "后台任务" : tTitle,
                command: cmd.isEmpty ? nil : Self.truncate(Self.sanitizePushText(cmd), maxChars: 60),
                isWaiting: false
            )
        }

        let latestAction = Self.truncate(
            Self.sanitizePushText(Self.buildLatestActionSummary(details: details, activeTaskTitle: activeTaskTitle)),
            maxChars: 100
        )

        let pendingStepIndex: Int? = details.pendingInteraction?.stepIndex ?? (details.canProceed ? details.totalSteps : nil)
        let pendingActionKind: String? = details.pendingInteraction?.type ?? (details.canProceed ? "proceed" : nil)
        let cleanTitle: String = {
            let raw = (details.title ?? fallbackTitle).trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? "Antigravity Agent" : Self.truncate(Self.sanitizePushText(raw), maxChars: 40)
        }()

        if ActivityManager.shared.hasActiveActivity(for: cascadeId) {
            ActivityManager.shared.updateActivity(
                cascadeId: cascadeId,
                title: cleanTitle,
                status: status,
                stepCount: max(1, details.totalSteps),
                latestAction: latestAction,
                runningTaskCount: blockingTasks.count,
                runningTasks: snapshots,
                activeTaskTitle: activeTaskTitle,
                activeTaskCommand: activeTaskCmd,
                hasPendingAction: hasPending,
                pendingStepIndex: pendingStepIndex,
                pendingActionKind: pendingActionKind
            )
        } else if status == "RUNNING" || status == "TASK_RUNNING" || status == "WAITING_APPROVAL" {
            ActivityManager.shared.startActivity(
                title: cleanTitle,
                cascadeId: cascadeId,
                status: status,
                stepCount: max(1, details.totalSteps),
                latestAction: latestAction,
                runningTaskCount: blockingTasks.count,
                runningTasks: snapshots,
                activeTaskTitle: activeTaskTitle,
                activeTaskCommand: activeTaskCmd,
                hasPendingAction: hasPending,
                pendingStepIndex: pendingStepIndex,
                pendingActionKind: pendingActionKind
            )
        }
    }

    private static func buildLatestActionSummary(details: FetchMessagesResult, activeTaskTitle: String?) -> String {
        if let pi = details.pendingInteraction {
            let target = sanitizePushText(pi.target ?? "")
            let summary = !target.isEmpty ? target : sanitizePushText(pi.title)
            return summary.isEmpty ? "等待用户审批操作" : "待审批: \(truncate(summary, maxChars: 80))"
        }
        if details.canProceed {
            return "方案待确认，可点击 Proceed"
        }
        if let activeTaskTitle, !activeTaskTitle.isEmpty {
            return activeTaskTitle
        }
        let focus = (details.activeFocus ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let plan = details.activePlan, !plan.items.isEmpty {
            let prefix = plan.totalCount > 0 ? "\(plan.doneCount)/\(plan.totalCount)" : ""
            if !focus.isEmpty {
                return prefix.isEmpty ? focus : "\(prefix) · \(focus)"
            }
            if let inProgItem = plan.items.first(where: { $0.status == "in_progress" && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                let itemTitle = inProgItem.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return prefix.isEmpty ? itemTitle : "\(prefix) · \(itemTitle)"
            }
        }
        if !focus.isEmpty {
            return focus
        }
        if let lastAgent = details.messages.last(where: { $0.isAgent }), !lastAgent.content.isEmpty {
            for line in lastAgent.content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: "#*- >`\t "))
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        if details.totalSteps > 0 {
            return "正在执行第 \(details.totalSteps) 步..."
        }
        return "Agent 正在执行..."
    }

    // MARK: - 1:1 Notification Builders (`notifier.go` + `messages.go`)

    private func notifyAction(cascadeId: String, title: String, interaction pi: PendingInteraction) async {
        let dedupKey = "action:\(cascadeId):\(pi.stepIndex):\(pi.type)"
        guard tryRecordDedup(dedupKey) else { return }

        var notifTitle = "⚠️ Antigravity 需要审批"
        let notifBodyRaw: String

        switch pi.type {
        case "workflow_approval":
            notifTitle = "⚠️ 动态工作流需审批"
            if let wfDesc = pi.workflowApproval?.description, !wfDesc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                notifBodyRaw = "编排工作流申请执行：\(Self.truncate(Self.sanitizePushText(wfDesc), maxChars: 90))"
            } else {
                notifBodyRaw = "动态工作流申请执行：\(Self.truncate(Self.sanitizePushText(pi.title), maxChars: 90))"
            }
        case "permission":
            let actionLower = (pi.action ?? "").lowercased()
            let cleanTarget = Self.truncate(Self.sanitizePushText(pi.target ?? ""), maxChars: 90)
            if actionLower.contains("command") || actionLower.contains("run") {
                notifBodyRaw = "Agent 申请执行命令: \(cleanTarget)"
            } else if actionLower.contains("write") || actionLower.contains("edit") {
                notifBodyRaw = "Agent 申请修改文件: \(cleanTarget)"
            } else if actionLower.contains("read") {
                notifBodyRaw = "Agent 申请读取外部文件: \(cleanTarget)"
            } else if let desc = pi.description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                notifBodyRaw = "Agent 请求审批: \(Self.truncate(Self.sanitizePushText(desc), maxChars: 90))"
            } else {
                notifBodyRaw = "Agent 申请 \(Self.sanitizePushText(pi.action ?? "权限")) 操作: \(cleanTarget)"
            }
        case "ask_question":
            notifTitle = "❓ Antigravity 提问"
            notifBodyRaw = "Agent 提出了新问题: \(Self.truncate(Self.sanitizePushText(pi.title), maxChars: 90))"
        case "run_command":
            notifTitle = "⚠️ 确认执行终端命令"
            notifBodyRaw = "Agent 申请执行命令: \(Self.truncate(Self.sanitizePushText(pi.target ?? ""), maxChars: 90))"
        case "file_permission":
            notifTitle = "⚠️ 跨目录文件访问审批"
            notifBodyRaw = "Agent 申请访问外部文件: \(Self.truncate(Self.sanitizePushText(pi.target ?? ""), maxChars: 90))"
        default:
            notifBodyRaw = "Agent 正在等待您的操作: \(Self.truncate(Self.sanitizePushText(pi.title), maxChars: 90))"
        }

        let cleanSessionTitle = Self.sanitizePushText(title)
        let finalBody: String
        if !cleanSessionTitle.isEmpty && cleanSessionTitle != "未命名会话" {
            finalBody = "【\(Self.truncate(cleanSessionTitle, maxChars: 60))】\(notifBodyRaw)"
        } else {
            finalBody = notifBodyRaw
        }

        let ok = await scheduleLocalNotification(
            identifier: "ag-action-\(cascadeId)",
            title: notifTitle,
            body: finalBody,
            category: "antigravity_action",
            soundId: AppSettings.shared.notificationActionSound,
            interruptionLevel: .timeSensitive,
            userInfo: [
                "cascadeId": cascadeId,
                "cascade_id": cascadeId,
                "url": "antigravity://cascade/\(cascadeId)?action=review",
                "category": "antigravity_action"
            ]
        )
        if !ok {
            removeDedup(dedupKey)
        }
    }

    private func notifyProceed(cascadeId: String, title: String, totalSteps: Int) async {
        let dedupKey = "proceed:\(cascadeId):\(totalSteps)"
        guard tryRecordDedup(dedupKey) else { return }

        let cleanTitle = Self.sanitizePushText(title)
        let displayTitle = (cleanTitle.isEmpty || cleanTitle == "未命名会话") ? "实施方案" : cleanTitle

        let ok = await scheduleLocalNotification(
            identifier: "ag-proceed-\(cascadeId)",
            title: "📋 方案已就绪，等待确认",
            body: "「\(displayTitle)」已完成编写，等待您点击 Proceed 确认以继续执行。",
            category: "antigravity_proceed",
            soundId: AppSettings.shared.notificationActionSound,
            interruptionLevel: .timeSensitive,
            userInfo: [
                "cascadeId": cascadeId,
                "cascade_id": cascadeId,
                "url": "antigravity://cascade/\(cascadeId)",
                "category": "antigravity_proceed"
            ]
        )
        if !ok {
            removeDedup(dedupKey)
        }
    }

    private func dismissApproval(cascadeId: String) {
        let cid = cascadeId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["ag-action-\(cid)", "ag-proceed-\(cid)"]
        )
        PushNotificationManager.shared.clearDeliveredNotifications(for: cid, approvalOnly: true)
    }

    private func notifyCompleted(cascadeId: String, title: String, totalSteps: Int) async {
        let dedupKey = "done:\(cascadeId):\(totalSteps)"
        guard tryRecordDedup(dedupKey) else { return }

        dismissApproval(cascadeId: cascadeId)
        let cleanTitle = Self.sanitizePushText(title)
        let displayTitle = (cleanTitle.isEmpty || cleanTitle == "未命名会话") ? "后台任务" : cleanTitle

        let ok = await scheduleLocalNotification(
            identifier: "ag-done-\(cascadeId)-\(totalSteps)",
            title: "🎉 Antigravity 任务已完成",
            body: "「\(displayTitle)」已顺利执行完毕，共执行 \(totalSteps) 个步骤。",
            category: "antigravity_complete",
            soundId: AppSettings.shared.notificationCompleteSound,
            interruptionLevel: .timeSensitive,
            userInfo: [
                "cascadeId": cascadeId,
                "cascade_id": cascadeId,
                "url": "antigravity://cascade/\(cascadeId)",
                "category": "antigravity_complete"
            ]
        )
        if !ok {
            removeDedup(dedupKey)
        }
    }

    private func notifyFailed(cascadeId: String, title: String, totalSteps: Int) async {
        let dedupKey = "fail:\(cascadeId):\(totalSteps)"
        guard tryRecordDedup(dedupKey) else { return }

        dismissApproval(cascadeId: cascadeId)
        let cleanTitle = Self.sanitizePushText(title)
        let displayTitle = (cleanTitle.isEmpty || cleanTitle == "未命名会话") ? "后台任务" : cleanTitle

        let ok = await scheduleLocalNotification(
            identifier: "ag-fail-\(cascadeId)-\(totalSteps)",
            title: "❌ Antigravity 任务执行失败",
            body: "「\(displayTitle)」执行出现异常或已被终止。",
            category: "antigravity_error",
            soundId: AppSettings.shared.notificationActionSound,
            interruptionLevel: .timeSensitive,
            userInfo: [
                "cascadeId": cascadeId,
                "cascade_id": cascadeId,
                "url": "antigravity://cascade/\(cascadeId)",
                "category": "antigravity_error"
            ]
        )
        if !ok {
            removeDedup(dedupKey)
        }
    }

    // MARK: - Quota Alerts (`cockpit/quota_alert.go` parity)

    public func observeQuota(_ response: CockpitQuotaResponse?) {
        let settings = AppSettings.shared
        guard settings.isPaired, !settings.isDemoMode, settings.enablePushNotifications else { return }
        guard let acc = response?.currentAccount ?? response?.accounts.first(where: \.isCurrent) else { return }

        let accIdent = (acc.email.isEmpty ? acc.id : acc.email).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !accIdent.isEmpty else { return }

        if accIdent == lastQuotaAccount && acc.updatedAt > 0 && acc.updatedAt == lastQuotaSeenUpdatedAt {
            return
        }
        if !lastQuotaAccount.isEmpty && accIdent != lastQuotaAccount {
            quotaTrackers.removeAll()
        }
        lastQuotaAccount = accIdent
        lastQuotaSeenUpdatedAt = acc.updatedAt

        let now = Date()
        let capturedAt = acc.updatedAt > 0
            ? Date(timeIntervalSince1970: Double(acc.updatedAt) / (acc.updatedAt >= 10_000_000_000 ? 1000.0 : 1.0))
            : now

        let specs: [(id: String, label: String, subject: String, isWeekly: Bool, bucket: CockpitQuotaBucket?)] = [
            ("gemini_5h", "Gemini 5h", "Gemini 5h 额度", false, acc.gemini5h),
            ("gemini_weekly", "Gemini 周额度", "Gemini 周额度", true, acc.geminiWeekly),
            ("claude_5h", "Claude 5h", "Claude 5h 额度", false, acc.claude5h),
            ("claude_weekly", "Claude 周额度", "Claude 周额度", true, acc.claudeWeekly),
            ("gemini_4_argon", "Gemini 4 Argon", "Gemini 4 Argon 额度", false, acc.gemini4Argon)
        ]

        var lowHits: [(label: String, subject: String, level: String, frac: Double, resetText: String?, cycleKey: String, resetRaw: String)] = []
        var bonusHits: [(label: String, subject: String, prevFrac: Double, curFrac: Double, bonusKey: String, prevRaw: String)] = []
        var stateDirty = false

        for spec in specs {
            guard let b = spec.bucket else { continue }
            let frac = min(1.0, max(0.0, b.remainingFraction))
            let resetRaw = b.resetTime ?? ""
            let cycleKey = spec.id == "gemini_5h" ? "\(acc.id)|\(resetRaw)" : "\(acc.id)|\(spec.id)|\(resetRaw)"

            var tr = quotaTrackers[spec.id] ?? QuotaBucketTracker()

            // 1. Early Bonus Reset check
            var bonusTriggered = false
            if tr.hasPrev {
                let jump = frac - tr.prevFrac
                let jumpMin = spec.isWeekly ? 0.25 : 0.30
                let earlyMargin: TimeInterval = spec.isWeekly ? 2 * 3600 : 20 * 60
                let maxPrevAge: TimeInterval = spec.isWeekly ? 7 * 86400 : 86400
                let prevAge = capturedAt.timeIntervalSince(tr.prevAt)
                if jump >= jumpMin,
                   frac >= 0.95,
                   let prevReset = tr.prevReset,
                   now < prevReset.addingTimeInterval(-earlyMargin),
                   prevAge >= 0, prevAge <= maxPrevAge {
                    let bonusKey = "\(acc.id)|bonus|\(spec.id)|\(tr.prevRaw)"
                    if quotaState[bonusKey] == nil {
                        bonusHits.append((spec.label, spec.subject, tr.prevFrac, frac, bonusKey, tr.prevRaw))
                        bonusTriggered = true
                    }
                }
            }

            if bonusTriggered {
                tr.samples.removeAll()
                quotaState.removeValue(forKey: cycleKey)
            }
            if tr.sampleKey != cycleKey {
                tr.samples.removeAll()
                tr.sampleKey = cycleKey
            }
            tr.samples.append(QuotaSample(at: capturedAt, fraction: frac))
            let cutoff = now.addingTimeInterval(-3 * 3600)
            tr.samples.removeAll { $0.at <= cutoff }

            // 2. Low quota threshold check (20% warn, 5% critical)
            var level = ""
            if frac <= Self.criticalQuotaFraction {
                level = "critical"
            } else if frac <= Self.warnQuotaFraction {
                level = "warn"
            }
            if !level.isEmpty {
                let fired = quotaState[cycleKey]?.level ?? ""
                if fired != "critical" && fired != level {
                    lowHits.append((spec.label, spec.subject, level, frac, b.recoveryCountdownText(now: now), cycleKey, resetRaw))
                }
            }

            tr.hasPrev = true
            tr.prevFrac = frac
            tr.prevReset = b.parsedResetDate
            tr.prevRaw = resetRaw
            tr.prevAt = capturedAt
            quotaTrackers[spec.id] = tr
        }

        let accPrefix = acc.email.isEmpty ? acc.name : acc.email

        if !lowHits.isEmpty {
            var anyCritical = false
            for h in lowHits {
                if h.level == "critical" { anyCritical = true }
                quotaState[h.cycleKey] = PersistedQuotaAlertEntry(level: h.level, resetTime: h.resetRaw, firedAt: now.timeIntervalSince1970)
            }
            stateDirty = true

            let title: String
            let body: String
            if lowHits.count == 1, let h = lowHits.first {
                let pct = Self.pctInt(h.frac)
                if h.frac <= 0 {
                    title = "🚨 \(h.subject)已用完"
                } else if h.level == "critical" {
                    title = "🚨 \(h.subject)仅剩 \(pct)%"
                } else {
                    title = "⚠️ \(h.subject)仅剩 \(pct)%"
                }
                var parts: [String] = []
                if !accPrefix.isEmpty { parts.append(accPrefix) }
                if let rt = h.resetText, !rt.isEmpty { parts.append(rt) }
                body = parts.isEmpty ? "点击查看当前账号配额详情" : parts.joined(separator: " · ")
            } else {
                title = anyCritical ? "🚨 多项额度告急（\(lowHits.count) 项）" : "⚠️ 多项额度偏低（\(lowHits.count) 项）"
                let items = lowHits.map { "\($0.label) \(Self.pctInt($0.frac))%" }.joined(separator: "、")
                body = accPrefix.isEmpty ? items : "\(accPrefix) · \(items)"
            }

            Task {
                _ = await scheduleLocalNotification(
                    identifier: "ag-quota-\(Int(now.timeIntervalSince1970))",
                    title: title,
                    body: body,
                    category: "quota_alert",
                    soundId: anyCritical ? settings.notificationActionSound : settings.notificationCompleteSound,
                    interruptionLevel: .timeSensitive,
                    userInfo: [
                        "url": "antigravity://quota",
                        "category": "quota_alert"
                    ]
                )
            }
        }

        if !bonusHits.isEmpty {
            for h in bonusHits {
                quotaState[h.bonusKey] = PersistedQuotaAlertEntry(level: "bonus_reset", resetTime: h.prevRaw, firedAt: now.timeIntervalSince1970)
            }
            stateDirty = true

            let title: String
            let body: String
            if bonusHits.count == 1, let h = bonusHits.first {
                title = "🎁 \(h.subject)已提前回满"
                let detail = "\(Self.pctInt(h.prevFrac))% → \(Self.pctInt(h.curFrac))%"
                body = accPrefix.isEmpty ? detail : "\(accPrefix) · \(detail)"
            } else {
                title = "🎁 Antigravity 额度已提前回满"
                let items = bonusHits.map { "\($0.label) (\(Self.pctInt($0.prevFrac))%→\(Self.pctInt($0.curFrac))%)" }.joined(separator: "、")
                body = accPrefix.isEmpty ? "\(items) 已早于原定时间重置" : "\(accPrefix) · \(items) 已早于原定时间重置"
            }

            Task {
                _ = await scheduleLocalNotification(
                    identifier: "ag-quota-bonus-\(Int(now.timeIntervalSince1970))",
                    title: title,
                    body: body,
                    category: "quota_alert",
                    soundId: settings.notificationCompleteSound,
                    interruptionLevel: .timeSensitive,
                    userInfo: [
                        "url": "antigravity://quota",
                        "category": "quota_alert"
                    ]
                )
            }
        }

        if stateDirty {
            saveQuotaState(now: now)
        }
    }

    // MARK: - Notification Scheduling & Sound Resolution

    private func scheduleLocalNotification(
        identifier: String,
        title: String,
        body: String,
        category: String,
        soundId: String,
        interruptionLevel: UNNotificationInterruptionLevel,
        userInfo: [AnyHashable: Any]
    ) async -> Bool {
        guard AppSettings.shared.enablePushNotifications, !AppSettings.shared.isDemoMode else { return false }

        // Suppress scheduling if user is actively looking at this exact conversation in the foreground with no modal covering it
        if UIApplication.shared.applicationState == .active,
           let cid = userInfo["cascadeId"] as? String,
           !cid.isEmpty,
           PushNotificationManager.shared.activeViewingCascadeId == cid,
           !PushNotificationManager.shared.hasBlockingModalPresented {
            return true
        }

        let center = UNUserNotificationCenter.current()
        let notifSettings = await center.notificationSettings()
        if notifSettings.authorizationStatus == .notDetermined {
            let granted = await PushNotificationManager.shared.requestAuthorizationAndRegister()
            guard granted else { return false }
        } else if notifSettings.authorizationStatus == .denied {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = Self.sanitizePushText(title)
        content.body = Self.sanitizePushText(body)
        content.categoryIdentifier = category
        content.threadIdentifier = "multigravity"
        content.interruptionLevel = interruptionLevel
        content.sound = Self.resolveNotificationSound(soundId)
        content.userInfo = userInfo

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await center.add(request)
            return true
        } catch {
            print("[LocalAlert] Failed to schedule \(identifier): \(error.localizedDescription)")
            return false
        }
    }

    private static func resolveNotificationSound(_ soundId: String) -> UNNotificationSound? {
        let clean = soundId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean == "silence" || clean == "none" || clean.isEmpty {
            return nil
        }
        if clean == "default" {
            return .default
        }
        if Bundle.main.url(forResource: clean, withExtension: "caf") != nil {
            return UNNotificationSound(named: UNNotificationSoundName("\(clean).caf"))
        }
        if Bundle.main.url(forResource: clean, withExtension: "caf", subdirectory: "Sounds") != nil {
            return UNNotificationSound(named: UNNotificationSoundName("Sounds/\(clean).caf"))
        }
        return .default
    }

    // MARK: - Helpers & Persistence

    private static func approvalKey(for details: FetchMessagesResult) -> String {
        if let pi = details.pendingInteraction {
            return "pi:\(pi.stepIndex):\(pi.type)"
        }
        if details.canProceed {
            return "proceed:\(details.totalSteps)"
        }
        return ""
    }

    private static func isCascadeInProgress(details: FetchMessagesResult, hasRunningSubagents: Bool) -> Bool {
        if details.status == "CASCADE_RUN_STATUS_RUNNING" { return true }
        if details.runningTasks.hasBlockingTasks { return true }
        if hasRunningSubagents { return true }
        if details.subagents?.contains(where: \.isRunning) == true { return true }
        return false
    }

    private static func sanitizePushText(_ raw: String) -> String {
        let stripped = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let compact = stripped
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return compact.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncate(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        return String(text.prefix(maxChars)) + "..."
    }

    private static func pctInt(_ fraction: Double) -> Int {
        max(0, min(100, Int((fraction * 100.0).rounded())))
    }

    private func tryRecordDedup(_ key: String) -> Bool {
        let now = Date().timeIntervalSince1970
        if let prev = dedupMap[key], now - prev < Self.dedupTTLSeconds {
            return false
        }
        dedupMap[key] = now
        saveDedup()
        return true
    }

    private func recordDedup(_ key: String, now: Date) {
        dedupMap[key] = now.timeIntervalSince1970
    }

    private func removeDedup(_ key: String) {
        dedupMap.removeValue(forKey: key)
        saveDedup()
    }

    private func pruneDedup(now: Date) {
        let cutoff = now.timeIntervalSince1970 - (Self.dedupTTLSeconds * 2)
        let before = dedupMap.count
        dedupMap = dedupMap.filter { $0.value > cutoff }
        if dedupMap.count != before {
            saveDedup()
        }
    }

    private func loadDedup() {
        if let raw = UserDefaults.standard.dictionary(forKey: Self.dedupStorageKey) as? [String: TimeInterval] {
            dedupMap = raw
        }
    }

    private func saveDedup() {
        UserDefaults.standard.set(dedupMap, forKey: Self.dedupStorageKey)
    }

    private func loadQuotaState() {
        guard let data = UserDefaults.standard.data(forKey: Self.quotaStateStorageKey),
              let decoded = try? JSONDecoder().decode([String: PersistedQuotaAlertEntry].self, from: data) else {
            return
        }
        quotaState = decoded
    }

    private func saveQuotaState(now: Date) {
        let cutoff = now.timeIntervalSince1970 - (48 * 3600)
        quotaState = quotaState.filter { $0.value.firedAt > cutoff }
        if let data = try? JSONEncoder().encode(quotaState) {
            UserDefaults.standard.set(data, forKey: Self.quotaStateStorageKey)
        }
    }

    private func cleanupStaleKnownSessions(now: Date) {
        guard knownSessions.count > 300 else { return }
        for (id, st) in knownSessions where !st.wasRunning && !st.waitingForBackground && now.timeIntervalSince(st.lastUpdated) > 86400 {
            knownSessions.removeValue(forKey: id)
            if knownSessions.count <= 300 { break }
        }
    }
}

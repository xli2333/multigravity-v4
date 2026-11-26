import ActivityKit
import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Bridges the paired iPhone app with the Apple Watch companion app (`MultigravityWatch`) over `WatchConnectivity`.
/// - Pushes silent coalesced `applicationContext` snapshots (never triggers intermediate-step haptics).
/// - Handles foreground/background RPC requests from the Watch (`fetch_snapshot`, `fetch_detail`,
///   `approve_action`, `reject_action`, `stop_task`) using the iPhone's gateway connection & E2EE session.
@MainActor
public final class WatchSyncManager: NSObject {
    public static let shared = WatchSyncManager()

    private var isActivated = false
    private var latestConversations: [ConversationItem] = []
    private var coalesceTask: Task<Void, Never>?
    private var lastContextData: Data?

    private override init() {
        super.init()
    }

    public func activateIfSupported() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported(), !isActivated else { return }
        isActivated = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #endif
    }

    public func updateConversations(_ items: [ConversationItem]) {
        self.latestConversations = items
        scheduleContextSync()
    }

    public func scheduleContextSync(immediate: Bool = false) {
        #if canImport(WatchConnectivity)
        activateIfSupported()
        coalesceTask?.cancel()
        if immediate {
            pushApplicationContextNow()
            return
        }
        coalesceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.pushApplicationContextNow()
        }
        #endif
    }

    private func pushApplicationContextNow() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired else { return }

        let envelope = buildCurrentEnvelope()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(envelope) else { return }
        if data == lastContextData { return }
        lastContextData = data

        try? session.updateApplicationContext([
            WatchBridgeConstants.contextPayloadKey: data
        ])
        #endif
    }

    // MARK: - Envelope & Detail Construction

    public func buildCurrentEnvelope() -> WatchContextEnvelope {
        let settings = AppSettings.shared
        let now = Date()
        let quotaSnap = QuotaWidgetStore.shared.loadSnapshot()?.applying(config: QuotaWidgetStore.shared.loadConfig())

        let watchQuota: WatchQuotaSnapshot? = quotaSnap.map { snap in
            WatchQuotaSnapshot(
                accountTitle: snap.displayAccountTitle,
                tierBadge: snap.tierBadgeLabel,
                isFreeTier: snap.isFreeTier,
                preferClaude: snap.isClaude,
                geminiShort: snap.geminiShort.map { WatchQuotaWindow(remainingPercent: $0.remainingPercent, resetAt: $0.resetAt, resetFriendly: $0.resetFriendly) },
                geminiWeekly: snap.geminiWeekly.map { WatchQuotaWindow(remainingPercent: $0.remainingPercent, resetAt: $0.resetAt, resetFriendly: $0.resetFriendly) },
                claudeShort: snap.claudeShort.map { WatchQuotaWindow(remainingPercent: $0.remainingPercent, resetAt: $0.resetAt, resetFriendly: $0.resetFriendly) },
                claudeWeekly: snap.claudeWeekly.map { WatchQuotaWindow(remainingPercent: $0.remainingPercent, resetAt: $0.resetAt, resetFriendly: $0.resetFriendly) },
                syncedAt: snap.syncedAt
            )
        }

        var summaries: [WatchConversationSummary] = []

        if !latestConversations.isEmpty {
            for item in latestConversations where !item.isSubagent && !item.isDraft {
                summaries.append(makeSummary(from: item))
            }
        } else if let widgetConvs = QuotaWidgetStore.shared.loadConversationsSnapshot() {
            for item in widgetConvs.items {
                summaries.append(makeSummary(fromWidgetItem: item))
            }
        }

        summaries.sort { lhs, rhs in
            if lhs.status.priorityRank != rhs.status.priorityRank {
                return lhs.status.priorityRank < rhs.status.priorityRank
            }
            let dA = lhs.lastModified ?? .distantPast
            let dB = rhs.lastModified ?? .distantPast
            if dA != dB { return dA > dB }
            return lhs.id < rhs.id
        }

        let runningCount = summaries.filter { $0.status == .running }.count
        let pendingCount = summaries.filter { $0.status == .action }.count

        return WatchContextEnvelope(
            syncedAt: now,
            isPaired: settings.isPaired,
            isDemo: settings.isDemoMode,
            phoneThemeMode: settings.themeMode,
            runningCount: runningCount,
            pendingActionCount: pendingCount,
            conversations: Array(summaries.prefix(12)),
            quota: watchQuota
        )
    }

    private func makeSummary(from item: ConversationItem) -> WatchConversationSummary {
        let activityState = ActivityManager.shared.findActiveActivity(for: item.id)?.content.state
        let cached = CacheManager.shared.loadSession(for: item.id)

        let mappedStatus: WatchTaskStatus = {
            if item.status.needsAction || activityState?.hasPendingAction == true {
                return .action
            }
            if item.isWorking || activityState?.status == "RUNNING" || activityState?.status == "TASK_RUNNING" {
                return .running
            }
            if item.status.isError {
                return .error
            }
            if activityState?.status == "COMPLETED" {
                return .completed
            }
            return .idle
        }()

        var approval: WatchPendingApprovalSummary?
        if mappedStatus == .action {
            if let pi = cached?.pendingInteraction {
                approval = Self.makeApprovalSummary(from: pi)
            } else if cached?.canProceed == true {
                approval = WatchPendingApprovalSummary(
                    stepIndex: nil,
                    kind: "proceed",
                    kindLabel: String(localized: "确认实施方案"),
                    redactedTarget: item.title,
                    descriptionText: String(localized: "Agent 已整理好方案，等待确认继续执行"),
                    requiresPhoneReview: false
                )
            } else if let act = activityState, act.hasPendingAction {
                let kind = act.pendingActionKind ?? "permission"
                approval = WatchPendingApprovalSummary(
                    stepIndex: act.pendingStepIndex,
                    kind: kind,
                    kindLabel: Self.kindDisplayLabel(for: kind),
                    redactedTarget: WatchTextSanitizer.redactSensitiveText(act.activeTaskCommand ?? act.latestAction),
                    descriptionText: nil,
                    requiresPhoneReview: act.requiresInAppReview
                )
            }
        }

        let latestSnippet: String? = {
            if let app = approval {
                return app.redactedTarget
            }
            if let act = activityState {
                if let cmd = act.activeTaskCommand, !cmd.isEmpty {
                    return WatchTextSanitizer.redactSensitiveText(cmd)
                }
                if !act.latestAction.isEmpty {
                    return WatchTextSanitizer.compactMessage(act.latestAction, maxChars: 72).summary
                }
            }
            if let lastMsg = cached?.messages.last(where: { $0.isAgent || $0.isError }) {
                let compacted = WatchTextSanitizer.compactMessage(lastMsg.content, maxChars: 72).summary
                if !compacted.isEmpty { return compacted }
            }
            return nil
        }()

        return WatchConversationSummary(
            id: item.id,
            title: item.title,
            workspaceName: item.workspaceName.isEmpty ? "Chat" : item.workspaceName,
            status: mappedStatus,
            stepCount: max(item.stepCount, activityState?.stepCount ?? 0),
            lastModified: item.lastModified,
            isUnread: item.isUnread,
            hasRunningTasks: item.hasRunningTasks,
            latestAction: latestSnippet,
            pendingApproval: approval
        )
    }

    private func makeSummary(fromWidgetItem item: AgentWidgetConversationItem) -> WatchConversationSummary {
        let activityState = ActivityManager.shared.findActiveActivity(for: item.id)?.content.state
        let mappedStatus: WatchTaskStatus = {
            switch item.status {
            case .action: return .action
            case .running: return .running
            case .error: return .error
            case .idle, .unknown:
                return item.hasRunningTasks ? .running : .idle
            }
        }()
        return WatchConversationSummary(
            id: item.id,
            title: item.title,
            workspaceName: item.displayWorkspace,
            status: mappedStatus,
            stepCount: item.stepCount,
            lastModified: item.lastModified,
            isUnread: item.isUnread,
            hasRunningTasks: item.hasRunningTasks,
            latestAction: activityState.map { WatchTextSanitizer.compactMessage($0.latestAction, maxChars: 72).summary },
            pendingApproval: nil
        )
    }

    private static func kindDisplayLabel(for kind: String) -> String {
        switch kind.lowercased() {
        case "run_command":
            return String(localized: "执行终端命令")
        case "file_permission":
            return String(localized: "访问或修改文件")
        case "permission":
            return String(localized: "敏感操作授权")
        case "proceed":
            return String(localized: "确认实施方案")
        case "workflow_approval":
            return String(localized: "工作流编排审批")
        case "ask_question", "elicitation":
            return String(localized: "等待回答问题")
        default:
            return String(localized: "需要确认")
        }
    }

    private static func makeApprovalSummary(from pi: PendingInteraction) -> WatchPendingApprovalSummary {
        let kind = pi.type.lowercased()
        let requiresPhone = kind == "ask_question"
            || kind == "workflow_approval"
            || kind == "elicitation"
            || (pi.questions?.isEmpty == false)
            || pi.isMultiSelect == true

        let rawTarget: String = {
            if let t = pi.target?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                return t
            }
            if let wfDesc = pi.workflowApproval?.description?.trimmingCharacters(in: .whitespacesAndNewlines), !wfDesc.isEmpty {
                return wfDesc
            }
            if let desc = pi.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                return desc
            }
            if let q = pi.questions?.first?.question.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
                return q
            }
            return pi.title
        }()

        let desc: String? = {
            guard let d = pi.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !d.isEmpty,
                  d != rawTarget else {
                return nil
            }
            return WatchTextSanitizer.compactMessage(d, maxChars: 96).summary
        }()

        return WatchPendingApprovalSummary(
            stepIndex: pi.stepIndex,
            kind: pi.type,
            kindLabel: kindDisplayLabel(for: pi.type),
            redactedTarget: WatchTextSanitizer.redactSensitiveText(rawTarget),
            descriptionText: desc,
            requiresPhoneReview: requiresPhone
        )
    }

    private func buildDetail(cascadeId: String, snap: FetchMessagesResult) -> WatchConversationDetail {
        let upper = snap.status.uppercased()
        let blockingTasks = snap.runningTasks.blockingTasks
        let hasPending = (snap.pendingInteraction != nil) || snap.canProceed

        let status: WatchTaskStatus = {
            if hasPending { return .action }
            if snap.hasError || upper.contains("ERROR") || upper.contains("FAIL") { return .error }
            if upper.contains("RUNNING") || !blockingTasks.isEmpty { return .running }
            return .completed
        }()

        let approval: WatchPendingApprovalSummary? = {
            if let pi = snap.pendingInteraction {
                return Self.makeApprovalSummary(from: pi)
            }
            if snap.canProceed, let uri = snap.proceedArtifactUri, !uri.isEmpty {
                let fileName = uri.split(separator: "/").last.map(String.init) ?? snap.title
                return WatchPendingApprovalSummary(
                    stepIndex: nil,
                    kind: "proceed",
                    kindLabel: String(localized: "确认实施方案"),
                    redactedTarget: WatchTextSanitizer.redactSensitiveText(fileName),
                    descriptionText: String(localized: "方案已就绪，点击允许即可开始执行"),
                    requiresPhoneReview: false
                )
            }
            return nil
        }()

        let runningSummaries: [WatchRunningTaskSummary] = blockingTasks.prefix(3).map { task in
            let title = (task.toolSummary ?? task.toolAction ?? task.toolName ?? String(localized: "后台任务"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cmd = WatchTextSanitizer.redactSensitiveText(task.commandLine)
            return WatchRunningTaskSummary(
                id: task.id,
                stepIndex: task.stepIndex,
                title: title.isEmpty ? String(localized: "后台任务") : title,
                redactedCommand: cmd.isEmpty ? nil : cmd
            )
        }

        let events = Self.extractRecentEvents(from: snap.messages, activePlan: snap.activePlan)
        let wsName = latestConversations.first(where: { $0.id == cascadeId })?.workspaceName
            ?? CacheManager.shared.loadSession(for: cascadeId)?.workspaceName
            ?? "Chat"
        let resolvedTitle = snap.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (latestConversations.first(where: { $0.id == cascadeId })?.title ?? String(localized: "未命名会话"))
            : snap.title

        return WatchConversationDetail(
            cascadeId: cascadeId,
            title: resolvedTitle,
            workspaceName: wsName.isEmpty ? "Chat" : wsName,
            status: status,
            stepCount: max(1, snap.totalSteps),
            activeFocus: snap.activeFocus?.trimmingCharacters(in: .whitespacesAndNewlines),
            errorMessage: snap.errorMessage.map { WatchTextSanitizer.compactMessage($0, maxChars: 130).summary },
            runningTasks: runningSummaries,
            pendingApproval: approval,
            recentEvents: events,
            syncedAt: Date()
        )
    }

    private func buildOfflineCachedDetail(cascadeId: String) -> WatchConversationDetail? {
        guard let cached = CacheManager.shared.loadSession(for: cascadeId) else { return nil }
        let blocking = (cached.runningTasks ?? []).blockingTasks
        let hasPending = (cached.pendingInteraction != nil) || (cached.canProceed == true)
        let status: WatchTaskStatus = hasPending
            ? .action
            : (!blocking.isEmpty || cached.status.uppercased().contains("RUNNING") ? .running : .idle)

        let approval: WatchPendingApprovalSummary? = {
            if let pi = cached.pendingInteraction {
                return Self.makeApprovalSummary(from: pi)
            }
            if cached.canProceed == true {
                return WatchPendingApprovalSummary(
                    stepIndex: nil,
                    kind: "proceed",
                    kindLabel: String(localized: "确认实施方案"),
                    redactedTarget: cached.title ?? cascadeId,
                    descriptionText: String(localized: "方案已就绪，点击允许即可开始执行"),
                    requiresPhoneReview: false
                )
            }
            return nil
        }()

        let tasks = blocking.prefix(3).map { task in
            WatchRunningTaskSummary(
                id: task.id,
                stepIndex: task.stepIndex,
                title: task.toolSummary ?? task.toolName ?? String(localized: "后台任务"),
                redactedCommand: WatchTextSanitizer.redactSensitiveText(task.commandLine)
            )
        }

        return WatchConversationDetail(
            cascadeId: cascadeId,
            title: cached.title ?? String(localized: "未命名会话"),
            workspaceName: cached.workspaceName ?? "Chat",
            status: status,
            stepCount: max(1, cached.stepCount),
            runningTasks: tasks,
            pendingApproval: approval,
            recentEvents: Self.extractRecentEvents(from: cached.messages, activePlan: nil),
            syncedAt: cached.savedAt
        )
    }

    private static func extractRecentEvents(from messages: [ChatMessage], activePlan: StepPlanItem?) -> [WatchTimelineEvent] {
        var events: [WatchTimelineEvent] = []

        if let plan = activePlan, plan.totalCount > 0 {
            let activeItem = plan.items.first(where: { $0.status == "in_progress" })?.title
            let summary = activeItem.map { "正在执行：\($0)" } ?? "步骤计划进度"
            events.append(
                WatchTimelineEvent(
                    id: "active-plan-\(plan.anchorStepIndex)",
                    role: "plan",
                    summary: summary,
                    badge: "计划 \(plan.doneCount)/\(plan.totalCount)",
                    stepIndex: plan.anchorStepIndex
                )
            )
        }

        for msg in messages.suffix(8).reversed() {
            if events.count >= 5 { break }
            switch msg.sender {
            case .agent:
                let (summary, codeBadge) = WatchTextSanitizer.compactMessage(msg.content, maxChars: 130)
                let artifactBadge = msg.artifacts.first.map { "文档 · \($0.title)" }
                guard !summary.isEmpty || codeBadge != nil || artifactBadge != nil else { continue }
                events.append(
                    WatchTimelineEvent(
                        id: msg.id,
                        role: "agent",
                        summary: summary.isEmpty ? String(localized: "已生成产物或代码变更") : summary,
                        badge: artifactBadge ?? codeBadge,
                        stepIndex: msg.effectiveStepIndex
                    )
                )
            case .user:
                let (summary, _) = WatchTextSanitizer.compactMessage(msg.content, maxChars: 90)
                guard !summary.isEmpty else { continue }
                events.append(
                    WatchTimelineEvent(
                        id: msg.id,
                        role: "user",
                        summary: summary,
                        badge: nil,
                        stepIndex: msg.effectiveStepIndex
                    )
                )
            case .error:
                let (summary, _) = WatchTextSanitizer.compactMessage(msg.content, maxChars: 120)
                guard !summary.isEmpty else { continue }
                events.append(
                    WatchTimelineEvent(
                        id: msg.id,
                        role: "error",
                        summary: summary,
                        badge: String(localized: "异常"),
                        stepIndex: msg.effectiveStepIndex
                    )
                )
            case .toolBatch(let count, let tools):
                let focus = msg.focusText?.trimmingCharacters(in: .whitespacesAndNewlines)
                let summary = (focus?.isEmpty == false)
                    ? focus!
                    : (tools.first.map { "调用 \($0)" } ?? String(localized: "执行工具链"))
                events.append(
                    WatchTimelineEvent(
                        id: msg.id,
                        role: "tools",
                        summary: WatchTextSanitizer.compactMessage(summary, maxChars: 80).summary,
                        badge: "\(max(1, count)) 项操作",
                        stepIndex: msg.effectiveStepIndex
                    )
                )
            case .stepPlan:
                if activePlan == nil, let plan = msg.stepPlan, plan.totalCount > 0 {
                    let currentTitle = plan.items.first(where: { $0.status == "in_progress" })?.title ?? String(localized: "执行计划")
                    events.append(
                        WatchTimelineEvent(
                            id: msg.id,
                            role: "plan",
                            summary: currentTitle,
                            badge: "计划 \(plan.doneCount)/\(plan.totalCount)",
                            stepIndex: msg.effectiveStepIndex
                        )
                    )
                }
            case .subagent, .workflow:
                let label = msg.subagent?.role ?? msg.workflow?.description ?? String(localized: "协同子任务")
                events.append(
                    WatchTimelineEvent(
                        id: msg.id,
                        role: "tools",
                        summary: WatchTextSanitizer.compactMessage(label, maxChars: 80).summary,
                        badge: String(localized: "子代理"),
                        stepIndex: msg.effectiveStepIndex
                    )
                )
            }
        }

        return events
    }

    // MARK: - RPC Execution (Watch -> iPhone -> Gateway)

    private func handleRPC(_ request: WatchRPCRequest) async -> WatchRPCResponse {
        let settings = AppSettings.shared
        guard settings.isPaired else {
            return WatchRPCResponse(
                ok: false,
                message: String(localized: "请先在 iPhone 打开 Multigravity 完成网关配对"),
                envelope: buildCurrentEnvelope()
            )
        }

        switch request.command {
        case "fetch_snapshot":
            if let baseURL = await resolveReachableGatewayURL() {
                async let convsTask = try? APIClient.shared.fetchConversations(baseURL: baseURL)
                async let quotaTask = try? APIClient.shared.fetchCockpitQuotas(baseURL: baseURL)
                let (freshConvs, freshQuota) = await (convsTask, quotaTask)
                if let freshConvs {
                    let cleaned = freshConvs.filter { !$0.isSubagent && !$0.isDraft }
                    self.latestConversations = cleaned
                    QuotaWidgetStore.shared.publishConversationsFromApp(items: cleaned, isDemo: settings.isDemoMode)
                }
                if let freshQuota {
                    let emailMasked = UserDefaults.standard.bool(forKey: "cockpit_email_masked")
                    QuotaWidgetStore.shared.publishFromApp(
                        response: freshQuota,
                        preferredBucket: settings.selectedQuotaBucket,
                        paceCursorEnabled: settings.weeklyPaceCursorEnabled,
                        isEmailMasked: emailMasked,
                        isDemo: settings.isDemoMode
                    )
                }
            }
            let env = buildCurrentEnvelope()
            scheduleContextSync(immediate: true)
            return WatchRPCResponse(ok: true, envelope: env)

        case "fetch_detail":
            guard let cid = request.cascadeId, !cid.isEmpty else {
                return WatchRPCResponse(ok: false, message: String(localized: "无效的会话标识"))
            }
            if let baseURL = await resolveReachableGatewayURL(),
               let snap = try? await APIClient.shared.fetchMessages(cascadeId: cid, limit: 8, baseURL: baseURL) {
                let detail = buildDetail(cascadeId: cid, snap: snap)
                return WatchRPCResponse(ok: true, envelope: buildCurrentEnvelope(), detail: detail)
            }
            if let cachedDetail = buildOfflineCachedDetail(cascadeId: cid) {
                return WatchRPCResponse(
                    ok: true,
                    message: String(localized: "当前显示本地缓存"),
                    envelope: buildCurrentEnvelope(),
                    detail: cachedDetail
                )
            }
            return WatchRPCResponse(ok: false, message: String(localized: "暂时无法连接网关获取详情"), envelope: buildCurrentEnvelope())

        case "approve_action":
            return await executeDecision(cascadeId: request.cascadeId, expectedStepIndex: request.expectedStepIndex, allow: true)

        case "reject_action":
            return await executeDecision(cascadeId: request.cascadeId, expectedStepIndex: request.expectedStepIndex, allow: false)

        case "stop_task":
            guard let cid = request.cascadeId, !cid.isEmpty else {
                return WatchRPCResponse(ok: false, message: String(localized: "无效的会话标识"))
            }
            guard let baseURL = await resolveReachableGatewayURL() else {
                return WatchRPCResponse(ok: false, message: String(localized: "iPhone 暂时无法连接网关"))
            }
            do {
                try await APIClient.shared.cancelTask(cascadeId: cid, killBackgroundTasks: true, baseURL: baseURL)
                if ActivityManager.shared.findActiveActivity(for: cid) != nil {
                    ActivityManager.shared.endActivity(for: cid, finalStatus: "CANCELLED")
                }
                let updatedDetail = (try? await APIClient.shared.fetchMessages(cascadeId: cid, limit: 6, baseURL: baseURL))
                    .map { buildDetail(cascadeId: cid, snap: $0) }
                scheduleContextSync(immediate: true)
                return WatchRPCResponse(
                    ok: true,
                    message: String(localized: "已停止当前任务"),
                    envelope: buildCurrentEnvelope(),
                    detail: updatedDetail
                )
            } catch {
                return WatchRPCResponse(ok: false, message: String(localized: "停止失败，请稍后重试"))
            }

        default:
            return WatchRPCResponse(ok: false, message: "Unsupported command")
        }
    }

    private func executeDecision(cascadeId: String?, expectedStepIndex: Int?, allow: Bool) async -> WatchRPCResponse {
        guard let cid = cascadeId, !cid.isEmpty else {
            return WatchRPCResponse(ok: false, message: String(localized: "无效的会话标识"))
        }
        guard let baseURL = await resolveReachableGatewayURL() else {
            return WatchRPCResponse(ok: false, message: String(localized: "iPhone 暂时无法连接网关"))
        }
        guard let snap = try? await APIClient.shared.fetchMessages(cascadeId: cid, limit: 6, baseURL: baseURL) else {
            return WatchRPCResponse(ok: false, message: String(localized: "拉取最新审批状态失败"))
        }

        if let interaction = snap.pendingInteraction {
            // Strict step-index guard: never approve/reject if desktop or phone moved on to another step.
            if let expected = expectedStepIndex, expected >= 0, interaction.stepIndex != expected {
                let freshDetail = buildDetail(cascadeId: cid, snap: snap)
                return WatchRPCResponse(
                    ok: false,
                    expired: true,
                    message: String(localized: "审批步骤已更新，请重新查看后再确认"),
                    envelope: buildCurrentEnvelope(),
                    detail: freshDetail
                )
            }

            let kind = interaction.type.lowercased()
            let requiresPhone = kind == "ask_question"
                || kind == "workflow_approval"
                || kind == "elicitation"
                || (interaction.questions?.isEmpty == false)
            if allow && requiresPhone {
                return WatchRPCResponse(
                    ok: false,
                    message: String(localized: "该操作包含多选或详细方案，请在 iPhone 审阅"),
                    envelope: buildCurrentEnvelope(),
                    detail: buildDetail(cascadeId: cid, snap: snap)
                )
            }

            do {
                if allow {
                    let approveOpt = interaction.options.first(where: {
                        $0.isDeny != true && $0.id != "5" && $0.id != "__write_in__"
                    }) ?? interaction.options.first
                    let optId = approveOpt?.id ?? interaction.defaultOptionId ?? "1"
                    let scope = approveOpt?.scope ?? 1
                    try await APIClient.shared.submitInteraction(
                        cascadeId: cid,
                        trajectoryId: interaction.trajectoryId,
                        stepIndex: interaction.stepIndex,
                        type: interaction.type,
                        optionId: optId,
                        scope: scope,
                        allow: true,
                        writeInResponse: "",
                        skipped: false,
                        target: interaction.target,
                        questionResponses: nil,
                        baseURL: baseURL
                    )
                } else {
                    let denyOpt = interaction.options.first(where: { $0.isDeny == true || $0.id == "5" })
                    try await APIClient.shared.submitInteraction(
                        cascadeId: cid,
                        trajectoryId: interaction.trajectoryId,
                        stepIndex: interaction.stepIndex,
                        type: interaction.type,
                        optionId: denyOpt?.id ?? "",
                        scope: denyOpt?.scope ?? 1,
                        allow: false,
                        writeInResponse: "",
                        skipped: denyOpt == nil,
                        target: interaction.target,
                        questionResponses: nil,
                        baseURL: baseURL
                    )
                }

                PushNotificationManager.shared.clearDeliveredNotifications(for: cid, approvalOnly: true)
                if ActivityManager.shared.findActiveActivity(for: cid) != nil {
                    ActivityManager.shared.updateActivity(
                        cascadeId: cid,
                        title: snap.title,
                        status: "RUNNING",
                        stepCount: max(1, snap.totalSteps),
                        latestAction: allow ? String(localized: "已允许，继续执行中...") : String(localized: "已拒绝该操作"),
                        hasPendingAction: false,
                        pendingStepIndex: nil,
                        pendingActionKind: nil
                    )
                }

                let refreshed = (try? await APIClient.shared.fetchMessages(cascadeId: cid, limit: 6, baseURL: baseURL))
                    .map { buildDetail(cascadeId: cid, snap: $0) }
                scheduleContextSync(immediate: true)
                return WatchRPCResponse(
                    ok: true,
                    message: allow ? String(localized: "已允许执行") : String(localized: "已拒绝该操作"),
                    envelope: buildCurrentEnvelope(),
                    detail: refreshed
                )
            } catch {
                return WatchRPCResponse(ok: false, message: String(localized: "提交审批失败，请重试"))
            }
        } else if allow, snap.canProceed, let uri = snap.proceedArtifactUri, !uri.isEmpty {
            do {
                try await APIClient.shared.proceedArtifact(
                    cascadeId: cid,
                    artifactUri: uri,
                    model: snap.activeModel,
                    cascadeConfigRaw: snap.cascadeConfigRaw,
                    baseURL: baseURL
                )
                PushNotificationManager.shared.clearDeliveredNotifications(for: cid, approvalOnly: true)
                if ActivityManager.shared.findActiveActivity(for: cid) != nil {
                    ActivityManager.shared.updateActivity(
                        cascadeId: cid,
                        title: snap.title,
                        status: "RUNNING",
                        stepCount: max(1, snap.totalSteps),
                        latestAction: String(localized: "已允许，继续执行中..."),
                        hasPendingAction: false,
                        pendingStepIndex: nil,
                        pendingActionKind: nil
                    )
                }
                let refreshed = (try? await APIClient.shared.fetchMessages(cascadeId: cid, limit: 6, baseURL: baseURL))
                    .map { buildDetail(cascadeId: cid, snap: $0) }
                scheduleContextSync(immediate: true)
                return WatchRPCResponse(
                    ok: true,
                    message: String(localized: "已确认继续执行"),
                    envelope: buildCurrentEnvelope(),
                    detail: refreshed
                )
            } catch {
                return WatchRPCResponse(ok: false, message: String(localized: "确认继续失败，请重试"))
            }
        } else {
            let freshDetail = buildDetail(cascadeId: cid, snap: snap)
            return WatchRPCResponse(
                ok: false,
                expired: true,
                message: String(localized: "该审批已在其他设备处理"),
                envelope: buildCurrentEnvelope(),
                detail: freshDetail
            )
        }
    }

    private func resolveReachableGatewayURL() async -> URL? {
        if let current = AppSettings.shared.serverURL {
            return current
        }
        if let elected = await ConnectionManager.shared.probeEndpoints(),
           let url = URL(string: elected) {
            return url
        }
        return nil
    }
}

#if canImport(WatchConnectivity)
extension WatchSyncManager: WCSessionDelegate {
    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            WatchSyncManager.shared.scheduleContextSync(immediate: true)
        }
    }

    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            WatchSyncManager.shared.scheduleContextSync(immediate: true)
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let req = try? decoder.decode(WatchRPCRequest.self, from: messageData) else {
            let fallback = WatchRPCResponse(ok: false, message: "Invalid RPC payload")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            replyHandler((try? encoder.encode(fallback)) ?? Data())
            return
        }

        Task { @MainActor in
            let response = await WatchSyncManager.shared.handleRPC(req)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = (try? encoder.encode(response)) ?? Data()
            replyHandler(data)
        }
    }
}
#endif

import Foundation
import Observation
import os
import WatchConnectivity
import WatchKit
import WidgetKit

/// Central Apple Watch state & WatchConnectivity client.
/// Enforces strict haptic anti-disturbance rules:
/// - Intermediate updates (`stepCount`, `RUNNING` text, quota ticks) NEVER vibrate.
/// - Only foreground state transitions into `ACTION` (new `pendingStepIndex`) or `COMPLETED` play a single haptic.
///   (When the Watch screen is asleep / wrist down, iOS natively mirrors APNs alerts so we never double-buzz.)
@Observable
@MainActor
public final class WatchSessionStore: NSObject {
    public static let shared = WatchSessionStore()

    private static let appearanceKey = "mgy.watch.appearance_pref"

    public private(set) var envelope: WatchContextEnvelope?
    public private(set) var detailsByCascade: [String: WatchConversationDetail] = [:]
    public private(set) var isReachable: Bool = false
    public private(set) var isRefreshing: Bool = false
    public private(set) var loadingDetailIds: Set<String> = []
    public private(set) var actionInFlightCascadeId: String?
    public var statusBannerMessage: String?

    public var isForegroundActive: Bool = false
    public var isLocalPreviewMode: Bool = false

    public var appearancePreference: WatchAppearancePreference {
        didSet {
            UserDefaults.standard.set(appearancePreference.rawValue, forKey: Self.appearanceKey)
        }
    }

    /// Resolves active Watch palette: defaults to Antigravity Pure White (`antigravityLight`)
    /// and switches to `claudeCutDark` when synced with iPhone dark mode or manually chosen.
    public var palette: WatchPalette {
        let useDark = appearancePreference.resolvesToDark(phoneThemeMode: envelope?.phoneThemeMode)
        return useDark ? .claudeCutDark : .antigravityLight
    }

    public var effectiveEnvelope: WatchContextEnvelope? {
        if isLocalPreviewMode {
            return .demoSample()
        }
        return envelope
    }

    private var isSessionActivated = false
    private var hasSeededInitialState = false
    private var previousStatusByCascade: [String: WatchTaskStatus] = [:]
    private var buzzedApprovalKeys: Set<String> = []
    private var buzzedCompletionKeys: Set<String> = []
    private var lastComplicationSignature: String?

    private override init() {
        let savedPref = UserDefaults.standard.string(forKey: Self.appearanceKey) ?? WatchAppearancePreference.followAppDefaultLight.rawValue
        self.appearancePreference = WatchAppearancePreference(rawValue: savedPref) ?? .followAppDefaultLight
        let cached = WatchSharedStore.shared.loadEnvelope()
        self.envelope = cached
        super.init()
        if let cached {
            seedHapticBaseline(from: cached)
        }
    }

    public func activate() {
        guard WCSession.isSupported(), !isSessionActivated else { return }
        isSessionActivated = true
        let session = WCSession.default
        session.delegate = self
        session.activate()

        // Hydrate immediately from latest applicationContext delivered while suspended
        if let rawData = session.receivedApplicationContext[WatchBridgeConstants.contextPayloadKey] as? Data {
            ingestContextData(rawData, allowForegroundHaptics: false)
        }
    }

    // MARK: - Haptic Transition Deduplication

    private func seedHapticBaseline(from env: WatchContextEnvelope) {
        for item in env.conversations {
            previousStatusByCascade[item.id] = item.status
            if item.status == .action {
                let stepKey = item.pendingApproval?.stepIndex.map(String.init) ?? "proceed"
                buzzedApprovalKeys.insert("\(item.id):\(stepKey)")
            } else if item.status == .completed || item.status == .idle {
                buzzedCompletionKeys.insert("\(item.id):\(item.stepCount)")
            }
        }
        hasSeededInitialState = true
    }

    private func evaluateForegroundTransitionsAndApply(_ next: WatchContextEnvelope, allowForegroundHaptics: Bool) {
        if !hasSeededInitialState {
            seedHapticBaseline(from: next)
        } else {
            var shouldPlayApproval = false
            var shouldPlayComplete = false

            for item in next.conversations {
                let prev = previousStatusByCascade[item.id]

                if item.status == .action {
                    let stepKey = item.pendingApproval?.stepIndex.map(String.init) ?? "proceed"
                    let dedupKey = "\(item.id):\(stepKey)"
                    if buzzedApprovalKeys.insert(dedupKey).inserted {
                        shouldPlayApproval = true
                    }
                } else if (item.status == .completed || item.status == .idle),
                          let prev,
                          (prev == .running || prev == .action) {
                    let doneKey = "\(item.id):\(item.stepCount)"
                    if buzzedCompletionKeys.insert(doneKey).inserted {
                        shouldPlayComplete = true
                    }
                }
                previousStatusByCascade[item.id] = item.status
            }

            // Strictly play haptics ONLY when Watch app is actively open on wrist (prevents background double-buzz with APNs)
            if allowForegroundHaptics && isForegroundActive {
                if shouldPlayApproval {
                    WKInterfaceDevice.current().play(.notification)
                } else if shouldPlayComplete {
                    WKInterfaceDevice.current().play(.success)
                }
            }
        }

        self.envelope = next
        WatchSharedStore.shared.saveEnvelope(next)
        reloadComplicationsIfNeeded(for: next)
    }

    private func reloadComplicationsIfNeeded(for env: WatchContextEnvelope) {
        let primaryPct = env.quota?.primaryComplicationMetric?.window.intPercent ?? -1
        let topId = env.conversations.first?.id ?? ""
        let topStatus = env.conversations.first?.status.rawValue ?? ""
        let sig = "\(env.pendingActionCount)|\(env.runningCount)|\(primaryPct)|\(topId)|\(topStatus)"
        guard sig != lastComplicationSignature else { return }
        lastComplicationSignature = sig
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func ingestContextData(_ data: Data, allowForegroundHaptics: Bool) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(WatchContextEnvelope.self, from: data) else { return }
        evaluateForegroundTransitionsAndApply(decoded, allowForegroundHaptics: allowForegroundHaptics)
    }

    // MARK: - Interactive RPCs to iPhone

    public func refreshSnapshot() async {
        if isLocalPreviewMode { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let resp = await sendRPC(WatchRPCRequest(command: "fetch_snapshot"))
        if let env = resp?.envelope {
            evaluateForegroundTransitionsAndApply(env, allowForegroundHaptics: true)
        } else if let msg = resp?.message, !msg.isEmpty {
            showBanner(msg)
        }
    }

    public func loadDetail(for summary: WatchConversationSummary) async {
        if isLocalPreviewMode {
            detailsByCascade[summary.id] = Self.makePreviewDetail(for: summary)
            return
        }
        loadingDetailIds.insert(summary.id)
        defer { loadingDetailIds.remove(summary.id) }

        let resp = await sendRPC(WatchRPCRequest(command: "fetch_detail", cascadeId: summary.id))
        if let env = resp?.envelope {
            evaluateForegroundTransitionsAndApply(env, allowForegroundHaptics: false)
        }
        if let detail = resp?.detail {
            detailsByCascade[summary.id] = detail
        }
    }

    /// Explicit user tap approval (NEVER bound to hand gestures).
    public func approveAction(cascadeId: String, expectedStepIndex: Int?) async {
        guard actionInFlightCascadeId == nil else { return }
        if isLocalPreviewMode {
            WKInterfaceDevice.current().play(.success)
            showBanner(String(localized: "演示：已允许执行"))
            return
        }

        actionInFlightCascadeId = cascadeId
        defer { actionInFlightCascadeId = nil }

        let resp = await sendRPC(
            WatchRPCRequest(
                command: "approve_action",
                cascadeId: cascadeId,
                expectedStepIndex: expectedStepIndex
            )
        )
        handleActionResponse(resp, cascadeId: cascadeId)
    }

    /// Explicit user tap rejection (NEVER bound to hand gestures).
    public func rejectAction(cascadeId: String, expectedStepIndex: Int?) async {
        guard actionInFlightCascadeId == nil else { return }
        if isLocalPreviewMode {
            WKInterfaceDevice.current().play(.click)
            showBanner(String(localized: "演示：已拒绝该操作"))
            return
        }

        actionInFlightCascadeId = cascadeId
        defer { actionInFlightCascadeId = nil }

        let resp = await sendRPC(
            WatchRPCRequest(
                command: "reject_action",
                cascadeId: cascadeId,
                expectedStepIndex: expectedStepIndex
            )
        )
        handleActionResponse(resp, cascadeId: cascadeId)
    }

    /// Explicit 2-step confirmed task stop.
    public func stopTask(cascadeId: String) async {
        guard actionInFlightCascadeId == nil else { return }
        if isLocalPreviewMode {
            WKInterfaceDevice.current().play(.directionDown)
            showBanner(String(localized: "演示：已停止任务"))
            return
        }

        actionInFlightCascadeId = cascadeId
        defer { actionInFlightCascadeId = nil }

        let resp = await sendRPC(WatchRPCRequest(command: "stop_task", cascadeId: cascadeId))
        handleActionResponse(resp, cascadeId: cascadeId)
    }

    private func handleActionResponse(_ resp: WatchRPCResponse?, cascadeId: String) {
        guard let resp else {
            WKInterfaceDevice.current().play(.failure)
            showBanner(String(localized: "无法连接 iPhone，请确认手机在附近"))
            return
        }
        if let env = resp.envelope {
            evaluateForegroundTransitionsAndApply(env, allowForegroundHaptics: false)
        }
        if let detail = resp.detail {
            detailsByCascade[cascadeId] = detail
        }
        if resp.ok {
            WKInterfaceDevice.current().play(.success)
        } else {
            WKInterfaceDevice.current().play(.failure)
        }
        if let msg = resp.message, !msg.isEmpty {
            showBanner(msg)
        }
    }

    private func showBanner(_ text: String) {
        statusBannerMessage = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if self?.statusBannerMessage == text {
                self?.statusBannerMessage = nil
            }
        }
    }

    private func sendRPC(_ req: WatchRPCRequest) async -> WatchRPCResponse? {
        guard WCSession.isSupported() else { return nil }
        let session = WCSession.default
        guard session.activationState == .activated else { return nil }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let payload = try? encoder.encode(req) else { return nil }

        return await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            func finishOnce(_ value: WatchRPCResponse?) {
                let shouldResume = resumed.withLock { done -> Bool in
                    if done { return false }
                    done = true
                    return true
                }
                if shouldResume {
                    continuation.resume(returning: value)
                }
            }

            // Safety timeout (9s) so UI spinners never hang if iPhone is powered off or out of range
            Task {
                try? await Task.sleep(nanoseconds: 9_000_000_000)
                finishOnce(nil)
            }

            session.sendMessageData(payload, replyHandler: { replyData in
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let parsed = try? decoder.decode(WatchRPCResponse.self, from: replyData)
                finishOnce(parsed)
            }, errorHandler: { _ in
                finishOnce(nil)
            })
        }
    }

    private static func makePreviewDetail(for summary: WatchConversationSummary) -> WatchConversationDetail {
        WatchConversationDetail(
            cascadeId: summary.id,
            title: summary.title,
            workspaceName: summary.displayWorkspace,
            status: summary.status,
            stepCount: summary.stepCount,
            activeFocus: summary.status == .running ? "正在校验双主题配色与无手势点按保护" : nil,
            errorMessage: nil,
            runningTasks: summary.status == .running
                ? [WatchRunningTaskSummary(id: "t1", stepIndex: summary.stepCount, title: "编译 watchOS 组件", redactedCommand: "xcodebuild -scheme MultigravityWatch")]
                : [],
            pendingApproval: summary.pendingApproval,
            recentEvents: [
                WatchTimelineEvent(id: "e1", role: "plan", summary: "正在执行：构建 Apple Watch 原生视图", badge: "计划 3/5", stepIndex: summary.stepCount),
                WatchTimelineEvent(id: "e2", role: "agent", summary: "已对齐 Antigravity 纯白默认主题与黑曜深色模式", badge: "代码片段 · 42行", stepIndex: max(1, summary.stepCount - 1)),
                WatchTimelineEvent(id: "e3", role: "tools", summary: "同步 WatchConnectivity 快照结构", badge: "3 项操作", stepIndex: max(1, summary.stepCount - 2))
            ],
            syncedAt: Date()
        )
    }
}

extension WatchSessionStore: WCSessionDelegate {
    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let reachable = session.isReachable
        let latestData = session.receivedApplicationContext[WatchBridgeConstants.contextPayloadKey] as? Data
        Task { @MainActor in
            WatchSessionStore.shared.isReachable = reachable
            if let latestData {
                WatchSessionStore.shared.ingestContextData(latestData, allowForegroundHaptics: false)
            }
            if reachable {
                await WatchSessionStore.shared.refreshSnapshot()
            }
        }
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            WatchSessionStore.shared.isReachable = reachable
            if reachable && WatchSessionStore.shared.isForegroundActive {
                await WatchSessionStore.shared.refreshSnapshot()
            }
        }
    }

    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let rawData = applicationContext[WatchBridgeConstants.contextPayloadKey] as? Data else { return }
        Task { @MainActor in
            WatchSessionStore.shared.ingestContextData(rawData, allowForegroundHaptics: true)
        }
    }
}

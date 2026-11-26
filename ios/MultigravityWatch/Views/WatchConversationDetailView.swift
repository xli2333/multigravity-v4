import Foundation
import SwiftUI

/// Conversation Detail & Explicit-Tap Approval Screen on Apple Watch.
/// Safety invariants:
/// 1. NEVER attaches `.handGestureShortcut` (Double Tap / wrist gestures) to Approve, Reject, or Stop.
/// 2. Places Approve / Reject buttons below the redacted command/target card so user inspects before tapping.
/// 3. Requires a 2-step confirmation dialog before stopping a running task.
struct WatchConversationDetailScreen: View {
    let cascadeId: String
    @State private var store = WatchSessionStore.shared
    @State private var showStopConfirmation = false

    private var summary: WatchConversationSummary? {
        store.effectiveEnvelope?.conversations.first(where: { $0.id == cascadeId })
    }

    private var detail: WatchConversationDetail? {
        store.detailsByCascade[cascadeId]
    }

    private var effectiveStatus: WatchTaskStatus {
        detail?.status ?? summary?.status ?? .idle
    }

    private var effectiveApproval: WatchPendingApprovalSummary? {
        detail?.pendingApproval ?? summary?.pendingApproval
    }

    private var effectiveTitle: String {
        detail?.title ?? summary?.title ?? String(localized: "任务详情")
    }

    private var effectiveWorkspace: String {
        detail?.workspaceName ?? summary?.displayWorkspace ?? "Chat"
    }

    private var effectiveStepCount: Int {
        detail?.stepCount ?? summary?.stepCount ?? 0
    }

    private var isActionBusy: Bool {
        store.actionInFlightCascadeId == cascadeId
    }

    var body: some View {
        let palette = store.palette
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                titleHeaderCard(palette: palette)

                if effectiveStatus == .action, let approval = effectiveApproval {
                    approvalDecisionSection(approval: approval, palette: palette)
                }

                if let err = detail?.errorMessage, !err.isEmpty {
                    errorBannerCard(message: err, palette: palette)
                }

                if let tasks = detail?.runningTasks, !tasks.isEmpty {
                    runningTasksSection(tasks: tasks, palette: palette)
                }

                recentTimelineSection(palette: palette)

                bottomActionSection(palette: palette)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 12)
        }
        .navigationTitle(effectiveWorkspace)
        .navigationBarTitleDisplayMode(.inline)
        .containerBackground(for: .navigation) {
            WatchCanvasBackground(
                palette: palette,
                statusTint: effectiveStatus == .action
                    ? palette.amberFill
                    : (effectiveStatus == .running ? palette.geminiFill : nil)
            )
        }
        .confirmationDialog(
            String(localized: "确认停止当前任务？"),
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "确认停止"), role: .destructive) {
                Task {
                    await store.stopTask(cascadeId: cascadeId)
                }
            }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "将通知网关立即中断当前运行步骤与后台命令。"))
        }
        .task(id: cascadeId) {
            if let summary {
                await store.loadDetail(for: summary)
            }
        }
    }

    @ViewBuilder
    private func titleHeaderCard(palette: WatchPalette) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                statusBadgePill(palette: palette)
                Spacer(minLength: 4)
                if effectiveStepCount > 0 {
                    Text("Step #\(effectiveStepCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.mutedFg)
                }
            }

            Text(effectiveTitle)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(palette.primaryFg)
                .fixedSize(horizontal: false, vertical: true)

            if let focus = detail?.activeFocus, !focus.isEmpty, effectiveStatus == .running {
                Text(focus)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.geminiText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(9.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(palette.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(palette.cardBorder, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func statusBadgePill(palette: WatchPalette) -> some View {
        let config: (text: String, fg: Color, bg: Color) = {
            switch effectiveStatus {
            case .action:
                return (String(localized: "需要审批"), palette.amberText, palette.amberFill.opacity(0.16))
            case .running:
                return (String(localized: "运行中"), palette.geminiText, palette.geminiFill.opacity(0.14))
            case .error:
                return (String(localized: "执行异常"), palette.roseText, palette.roseSoftBg)
            case .completed:
                return (String(localized: "已完成"), palette.emeraldText, palette.emeraldSoftBg)
            case .idle:
                return (String(localized: "空闲"), palette.secondaryFg, palette.recessedBg)
            }
        }()

        Text(config.text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(config.fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(config.bg))
    }

    @ViewBuilder
    private func approvalDecisionSection(approval: WatchPendingApprovalSummary, palette: WatchPalette) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.amberText)
                Text(approval.kindLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.amberText)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let idx = approval.stepIndex {
                    Text("#\(idx)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.amberText)
                }
            }

            // Redacted Command / File Target Box
            Text(approval.redactedTarget)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.primaryFg)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.recessedBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(palette.cardBorder, lineWidth: 1)
                        )
                )

            if let desc = approval.descriptionText, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondaryFg)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if approval.requiresPhoneReview {
                HStack(spacing: 5) {
                    Image(systemName: "iphone")
                        .font(.system(size: 11, weight: .semibold))
                    Text(String(localized: "包含多选或详细方案，请在 iPhone 查看并确认"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(palette.amberText)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.amberCardBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(palette.amberCardBorder, lineWidth: 1)
                        )
                )
            } else {
                HStack {
                    Text(String(localized: "请核对摘要后点击屏幕按钮确认"))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(palette.mutedFg)
                    Spacer()
                }

                // Explicit on-screen tap buttons ONLY — intentionally no .handGestureShortcut
                VStack(spacing: 6) {
                    Button {
                        Task {
                            await store.approveAction(
                                cascadeId: cascadeId,
                                expectedStepIndex: approval.stepIndex
                            )
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if isActionBusy {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Text(String(localized: "点击允许"))
                                .font(.system(size: 12.5, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(palette.emeraldFill))
                    }
                    .buttonStyle(.plain)
                    .disabled(isActionBusy)

                    Button {
                        Task {
                            await store.rejectAction(
                                cascadeId: cascadeId,
                                expectedStepIndex: approval.stepIndex
                            )
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10.5, weight: .bold))
                            Text(String(localized: "拒绝"))
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(palette.roseText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(palette.roseSoftBg)
                                .overlay(Capsule().stroke(palette.roseBorder, lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isActionBusy)
                }
                .padding(.top, 2)
            }
        }
        .padding(9.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.amberCardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.amberCardBorder, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func errorBannerCard(message: String, palette: WatchPalette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5, weight: .bold))
                Text(String(localized: "错误摘要"))
                    .font(.system(size: 10.5, weight: .bold))
            }
            .foregroundStyle(palette.roseText)

            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.primaryFg)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(palette.roseSoftBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(palette.roseBorder, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func runningTasksSection(tasks: [WatchRunningTaskSummary], palette: WatchPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "运行中命令"))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.mutedFg)

            ForEach(tasks) { task in
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.primaryFg)
                        .lineLimit(1)
                    if let cmd = task.redactedCommand, !cmd.isEmpty {
                        Text(cmd)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(palette.geminiText)
                            .lineLimit(2)
                    }
                }
                .padding(7.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.recessedBg)
                )
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(palette.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(palette.cardBorder, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func recentTimelineSection(palette: WatchPalette) -> some View {
        let events = detail?.recentEvents ?? []
        let isLoading = store.loadingDetailIds.contains(cascadeId)

        VStack(alignment: .leading, spacing: 6.5) {
            HStack {
                Text(String(localized: "最近执行动态"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.mutedFg)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            if events.isEmpty {
                if let fallback = summary?.latestAction, !fallback.isEmpty {
                    Text(fallback)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryFg)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(isLoading ? String(localized: "正在从 iPhone 同步详情...") : String(localized: "暂无更多步骤摘要"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.mutedFg)
                }
            } else {
                ForEach(events) { ev in
                    VStack(alignment: .leading, spacing: 3) {
                        if let badge = ev.badge, !badge.isEmpty {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(ev.role == "error" ? palette.roseText : palette.geminiText)
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(palette.recessedBg)
                                )
                        }
                        Text(ev.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(ev.role == "user" ? palette.secondaryFg : palette.primaryFg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if ev.id != events.last?.id {
                        Divider()
                            .overlay(palette.cardBorder)
                    }
                }
            }
        }
        .padding(9.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(palette.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(palette.cardBorder, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func bottomActionSection(palette: WatchPalette) -> some View {
        VStack(spacing: 6) {
            Button {
                if let summary {
                    Task { await store.loadDetail(for: summary) }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .bold))
                    Text(String(localized: "刷新详情"))
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(palette.secondaryFg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7.5)
                .background(
                    Capsule()
                        .fill(palette.cardBg)
                        .overlay(Capsule().stroke(palette.cardBorder, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)

            if effectiveStatus == .running {
                Button {
                    showStopConfirmation = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9.5, weight: .bold))
                        Text(String(localized: "停止任务"))
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .foregroundStyle(palette.roseText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(palette.roseSoftBg)
                            .overlay(Capsule().stroke(palette.roseBorder, lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isActionBusy)
            }
        }
    }
}

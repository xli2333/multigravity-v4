import SwiftUI

/// Top urgent approval spotlight card in Tab 1 (`会话`):
/// Surfaces conversations where `status.needsAction` is true so users can approve/reject
/// pending terminal commands, permissions, or `implementation_plan.md` Proceed in 1 tap
/// without opening the chat first.
public struct UrgentApprovalTriageCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    public let conversations: [ConversationItem]
    public let onOpenConversation: (ConversationItem) -> Void
    public let onDecisionCompleted: () async -> Void

    @State private var loadedCascadeId: String? = nil
    @State private var pendingInteraction: PendingInteraction? = nil
    @State private var canProceed: Bool = false
    @State private var proceedArtifactUri: String? = nil
    @State private var cascadeConfigRaw: String? = nil
    @State private var activeModel: String? = nil
    @State private var isFetching: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var dismissedIds: Set<String> = []
    @State private var errorToast: String? = nil

    public init(
        conversations: [ConversationItem],
        onOpenConversation: @escaping (ConversationItem) -> Void,
        onDecisionCompleted: @escaping () async -> Void
    ) {
        self.conversations = conversations
        self.onOpenConversation = onOpenConversation
        self.onDecisionCompleted = onDecisionCompleted
    }

    private var urgentConversations: [ConversationItem] {
        conversations.filter { $0.status.needsAction && !dismissedIds.contains($0.id) }
    }

    private var primaryUrgent: ConversationItem? {
        urgentConversations.first
    }

    public var body: some View {
        if let conv = primaryUrgent {
            cardContent(for: conv, totalCount: urgentConversations.count)
                .task(id: "\(conv.id)-\(conv.lastModified?.timeIntervalSince1970 ?? 0)") {
                    await loadInteractionSnapshot(for: conv)
                }
        }
    }

    @ViewBuilder
    private func cardContent(for conv: ConversationItem, totalCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            // Top badge row
            HStack(spacing: 6) {
                AGBadge(
                    totalCount > 1
                        ? String(localized: "待办速批 (\(totalCount)) · 免进会话直接决策")
                        : String(localized: "待办速批 · 免进会话直接决策"),
                    tone: .amber
                ) {
                    AGLinearIcon(.shield, size: 11, color: AGPalette.amberText(colorScheme), lineWidth: 2.0)
                }

                Spacer()

                if !conv.relativeTimeString.isEmpty {
                    Text(conv.relativeTimeString)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(AGPalette.textTertiary(colorScheme))
                }
            }

            // Session title
            Button {
                onOpenConversation(conv)
            } label: {
                HStack(spacing: 6) {
                    Text(conv.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AGPalette.textPrimary(colorScheme))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if !conv.workspaceName.isEmpty {
                        Text(conv.workspaceName)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(AGPalette.textSecondary(colorScheme))
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            // Recessed command / prompt preview well
            HStack(spacing: 7) {
                AGLinearIcon(
                    previewIconKind,
                    size: 12.5,
                    color: AGPalette.amberText(colorScheme),
                    lineWidth: 1.9
                )
                Text(previewCommandText(for: conv))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AGPalette.recessedWell(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(AGPalette.borderSubtle(colorScheme), lineWidth: 1)
            )

            if let err = errorToast, !err.isEmpty {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(AGPalette.roseText(colorScheme))
                    .lineLimit(1)
            }

            // Action button bar
            actionRow(for: conv)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(AGPalette.cardBackground(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(AGPalette.amberFill(colorScheme).opacity(colorScheme == .dark ? 0.55 : 0.48), lineWidth: 1.25)
        )
        .shadow(
            color: colorScheme == .dark ? Color.black.opacity(0.28) : AGPalette.amberFill(.light).opacity(0.08),
            radius: 10,
            x: 0,
            y: 3
        )
    }

    private var previewIconKind: AGLinearIcon.Kind {
        if canProceed && pendingInteraction == nil {
            return .play
        }
        switch pendingInteraction?.type {
        case "run_command":
            return .terminal
        case "mcp":
            return .plug
        case "ask_question", "elicitation":
            return .chat
        default:
            return .shield
        }
    }

    private func previewCommandText(for conv: ConversationItem) -> String {
        if let pi = pendingInteraction {
            if let grant = pi.permissionGrant {
                let scopeText = [grant.binary, grant.action, grant.repo, grant.path]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if !scopeText.isEmpty {
                    return scopeText
                }
            }
            if let target = pi.target?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty {
                return pi.type == "run_command" ? "$ \(target)" : target
            }
            if let desc = pi.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                return desc
            }
            if !pi.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return pi.title
            }
        }
        if canProceed {
            return String(localized: "implementation_plan.md · 实施方案已就绪，等待批准执行")
        }
        if isFetching {
            return String(localized: "正在同步待审批指令上下文...")
        }
        return String(localized: "存在等待确认的操作，点按查看上下文或直接决策")
    }

    private var requiresInChatAnswer: Bool {
        guard let pi = pendingInteraction else {
            return !canProceed
        }
        if pi.type == "ask_question" || pi.type == "elicitation" || pi.type == "workflow_approval" {
            return true
        }
        if let qs = pi.questions, qs.count > 1 {
            return true
        }
        if pi.options.isEmpty && pi.hasWriteIn == true {
            return true
        }
        if !pi.options.contains(where: { $0.isDeny == true }) {
            return true
        }
        return false
    }

    @ViewBuilder
    private func actionRow(for conv: ConversationItem) -> some View {
        HStack(spacing: 8) {
            if let pi = pendingInteraction, !requiresInChatAnswer {
                // Deny button
                Button {
                    Task { await submitDecision(for: conv, interaction: pi, approve: false) }
                } label: {
                    Text(denyButtonLabel(for: pi))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AGPalette.textSecondary(colorScheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 31)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AGPalette.recessedWell(colorScheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AGPalette.border(colorScheme), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)

                // Context button
                contextButton(for: conv)

                // Approve button
                Button {
                    Task { await submitDecision(for: conv, interaction: pi, approve: true) }
                } label: {
                    HStack(spacing: 4) {
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.white)
                        } else {
                            AGLinearIcon(.check, size: 12, color: .white, lineWidth: 2.2)
                        }
                        Text(approveButtonLabel(for: pi))
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 31)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AGPalette.accentFill(colorScheme))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
            } else if canProceed, let uri = proceedArtifactUri, !uri.isEmpty {
                contextButton(for: conv)

                Button {
                    Task { await submitProceed(for: conv, artifactUri: uri) }
                } label: {
                    HStack(spacing: 5) {
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.white)
                        } else {
                            AGLinearIcon(.play, size: 11.5, color: .white, lineWidth: 2.0)
                        }
                        Text("批准并执行")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 31)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AGPalette.accentFill(colorScheme))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
            } else {
                Button {
                    onOpenConversation(conv)
                } label: {
                    HStack(spacing: 5) {
                        Text("进入会话完成确认")
                            .font(.system(size: 12, weight: .bold))
                        AGLinearIcon(.chevronRight, size: 12, color: .white, lineWidth: 2.1)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 31)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AGPalette.accentFill(colorScheme))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func contextButton(for conv: ConversationItem) -> some View {
        Button {
            onOpenConversation(conv)
        } label: {
            HStack(spacing: 3) {
                Text("上下文")
                    .font(.system(size: 12, weight: .semibold))
                AGLinearIcon(.chevronRight, size: 11, color: AGPalette.textSecondary(colorScheme), lineWidth: 2.0)
            }
            .foregroundColor(AGPalette.textSecondary(colorScheme))
            .frame(maxWidth: .infinity)
            .frame(height: 31)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AGPalette.recessedWell(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AGPalette.border(colorScheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func denyButtonLabel(for pi: PendingInteraction) -> String {
        if let opt = pi.options.first(where: { $0.isDeny == true }), !opt.text.isEmpty, opt.text.count <= 6 {
            return opt.text
        }
        return String(localized: "拒绝")
    }

    private func approveButtonLabel(for pi: PendingInteraction) -> String {
        if let opt = resolveAllowOption(for: pi), !opt.text.isEmpty, opt.text.count <= 6 {
            return opt.text
        }
        return String(localized: "允许本次")
    }

    private func resolveAllowOption(for pi: PendingInteraction) -> InteractionOption? {
        if let defId = pi.defaultOptionId,
           let match = pi.options.first(where: { $0.id == defId && $0.isDeny != true }) {
            return match
        }
        return pi.options.first(where: { $0.isDeny != true }) ?? pi.options.first
    }

    private func resolveDenyOption(for pi: PendingInteraction) -> InteractionOption? {
        if let match = pi.options.first(where: { $0.isDeny == true }) {
            return match
        }
        if pi.options.count >= 2 {
            return pi.options.last
        }
        return nil
    }

    private func loadInteractionSnapshot(for conv: ConversationItem) async {
        guard let url = AppSettings.shared.serverURL else { return }
        if loadedCascadeId != conv.id {
            pendingInteraction = nil
            canProceed = false
            proceedArtifactUri = nil
            errorToast = nil
        }
        isFetching = true
        defer { isFetching = false }

        do {
            let res = try await APIClient.shared.fetchMessages(
                cascadeId: conv.id,
                limit: 5,
                baseURL: url
            )
            loadedCascadeId = conv.id
            pendingInteraction = res.pendingInteraction
            canProceed = res.canProceed
            proceedArtifactUri = res.proceedArtifactUri
            cascadeConfigRaw = res.cascadeConfigRaw
            activeModel = res.activeModel
        } catch {
            // Keep graceful fallback button ("进入会话完成确认")
        }
    }

    private func submitDecision(for conv: ConversationItem, interaction pi: PendingInteraction, approve: Bool) async {
        guard let url = AppSettings.shared.serverURL else { return }
        let chosen = approve ? resolveAllowOption(for: pi) : resolveDenyOption(for: pi)
        let optId = chosen?.id ?? (approve ? (pi.defaultOptionId ?? "1") : "0")
        let scope = chosen?.scope ?? 1

        isSubmitting = true
        errorToast = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        defer { isSubmitting = false }

        do {
            try await APIClient.shared.submitInteraction(
                cascadeId: conv.id,
                trajectoryId: pi.trajectoryId,
                stepIndex: pi.stepIndex,
                type: pi.type,
                optionId: optId,
                scope: scope,
                allow: approve,
                writeInResponse: "",
                skipped: !approve && chosen == nil,
                target: pi.target,
                questionResponses: nil,
                baseURL: url
            )
            PushNotificationManager.shared.clearDeliveredNotifications(for: conv.id, approvalOnly: true)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismissedIds.insert(conv.id)
            await onDecisionCompleted()
        } catch {
            errorToast = error.localizedDescription
        }
    }

    private func submitProceed(for conv: ConversationItem, artifactUri: String) async {
        guard let url = AppSettings.shared.serverURL else { return }
        isSubmitting = true
        errorToast = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        defer { isSubmitting = false }

        do {
            try await APIClient.shared.proceedArtifact(
                cascadeId: conv.id,
                artifactUri: artifactUri,
                model: activeModel,
                cascadeConfigRaw: cascadeConfigRaw,
                baseURL: url
            )
            PushNotificationManager.shared.clearDeliveredNotifications(for: conv.id, approvalOnly: true)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismissedIds.insert(conv.id)
            await onDecisionCompleted()
        } catch {
            errorToast = error.localizedDescription
        }
    }
}

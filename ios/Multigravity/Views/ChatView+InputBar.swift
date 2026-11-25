import SwiftUI
import PhotosUI
import AVFoundation

extension ChatView {
    /// 悬浮在输入栏顶部横线上方、覆盖在会话界面底部的斜杠命令/技能选择气泡弹窗
    /// 独立为子 View 以隔离 viewModel.inputText 的 @Observable 订阅，避免每次按键重绘整个 ChatView.body 与历史消息列表
    @ViewBuilder
    var floatingSlashCommandPopup: some View {
        ChatFloatingSlashPopupHost(
            viewModel: viewModel,
            isSlashPickerDismissed: $isSlashPickerDismissed,
            currentViewportHeight: currentViewportHeight,
            onSelectWorkflow: {
                showWorkflowTemplateSheet = true
            }
        )
    }

    /// 悬浮在输入栏上方、覆盖在会话气泡底部的 @ 上下文引用选择浮窗
    @ViewBuilder
    var floatingMentionPopup: some View {
        ChatFloatingMentionPopupHost(
            viewModel: viewModel,
            currentViewportHeight: currentViewportHeight
        )
    }

    var inputBar: some View {
        let hasAuxCommandChip = viewModel.selectedSlashCommand != nil
            && viewModel.selectedSlashCommand?.name != "goal"
            && viewModel.selectedSlashCommand?.name != "swarm"
        let hasInlineProceedCard = viewModel.canProceed && viewModel.messages.contains(where: { !$0.artifacts.isEmpty })
        let showFallbackProceedChip = viewModel.canProceed && !hasInlineProceedCard

        return VStack(alignment: .leading, spacing: 6) {
            // Contextual status / recovery / non-mode slash command chips (only shown when active)
            if hasAuxCommandChip || viewModel.isLatestMessageError || showFallbackProceedChip {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if hasAuxCommandChip, let command = viewModel.selectedSlashCommand {
                            SlashCommandChipView(command: command) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    viewModel.clearSlashCommand()
                                }
                            }
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                        }

                        if viewModel.isLatestMessageError {
                            Button(action: handleContinue) {
                                HStack(spacing: 5) {
                                    AGLinearIcon(.play, size: 11, color: .white, lineWidth: 2.1)
                                    Text("Continue")
                                        .font(.system(size: 12.5, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 29)
                                .background(Capsule().fill(AGPalette.accentFill(colorScheme)))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    insertContinue()
                                } label: {
                                    Label("填入输入框", systemImage: "square.and.pencil")
                                }
                            }
                        }

                        if showFallbackProceedChip {
                            Button(action: handleProceed) {
                                HStack(spacing: 5) {
                                    AGLinearIcon(.play, size: 11, color: .white, lineWidth: 2.1)
                                    Text("批准并执行 (Proceed)")
                                        .font(.system(size: 12.5, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 29)
                                .background(Capsule().fill(AGPalette.accentFill(colorScheme)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                }
            }

            // Image previews strip
            if !viewModel.selectedImageData.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(viewModel.selectedImageData.enumerated()), id: \.offset) { index, data in
                            if let uiImage = UIImage(data: data) {
                                ZStack(alignment: .topTrailing) {
                                    Button(action: {
                                        isInputFocused = false
                                        let draftImages = viewModel.selectedImageData.compactMap { UIImage(data: $0) }.map { IdentifiableImage(image: $0) }
                                        previewDraftGallery = ImageGalleryData(items: draftImages, initialIndex: index)
                                    }) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 50, height: 50)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(AGPalette.border(colorScheme), lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)

                                    Button(action: {
                                        removeImage(at: index)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.white)
                                            .background(Circle().fill(Color.black.opacity(0.65)))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 4, y: -4)
                                }
                                .padding(.top, 4)
                                .padding(.trailing, 4)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // File chips strip
            if !viewModel.selectedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.selectedFiles) { file in
                            DraftFileChipView(
                                file: file,
                                onRemove: { viewModel.removeFile(file.id) },
                                onRetry: { viewModel.retryFileUpload(file.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if narrationPlayer.isPlaying {
                NarrationPlayerBar(player: narrationPlayer)
            }

            if dictationManager.isDictating {
                DictationActiveBar {
                    dictationManager.stop()
                }
            }

            if !viewModel.suggestedResponses.isEmpty && !isInputFocused && !viewModel.isActivelyRunning && !viewModel.showMentionPicker {
                SuggestedResponsesBar(suggestions: viewModel.suggestedResponses) { chosen in
                    Task {
                        viewModel.suggestedResponses = []
                        _ = await viewModel.sendMessage(text: chosen)
                    }
                }
            }

            if !viewModel.selectedContextItems.isEmpty {
                ContextMentionsChipBar(
                    items: viewModel.selectedContextItems,
                    onRemove: { id in viewModel.removeContextItem(id: id) }
                )
            }

            // v4.0 Unified 2-Row Ergonomic Composer Card (isolates viewModel.inputText observation!)
            ChatInputTextAndSendRow(
                viewModel: viewModel,
                voiceCall: voiceCall,
                dictationManager: dictationManager,
                modelPickerState: modelPickerState,
                modelChipForegroundColor: modelChipForegroundColor,
                modelChipBackgroundColor: modelChipBackgroundColor,
                modelChipBorderColor: modelChipBorderColor,
                isInputFocused: $isInputFocused,
                isSlashPickerDismissed: $isSlashPickerDismissed,
                onSend: handleSend,
                onCancel: handleCancel,
                onStartVoiceCall: handleStartVoiceCall,
                onAudioRecord: handleAudioRecordAction,
                onStartDictation: {
                    if let gwUrl = AppSettings.shared.gatewayURL {
                        dictationManager.start(
                            cascadeId: viewModel.cascadeId,
                            baseURL: gwUrl,
                            initialText: viewModel.inputText,
                            onTranscriptUpdate: { fullText in
                                viewModel.inputText = fullText
                            },
                            onError: { err in
                                viewModel.errorMessage = err
                            }
                        )
                    }
                },
                onOpenAttachmentSheet: {
                    isInputFocused = false
                    showAttachmentSheet = true
                },
                onOpenBtw: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let draft = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !draft.isEmpty
                        && viewModel.selectedImageData.isEmpty
                        && viewModel.selectedFiles.isEmpty
                        && !viewModel.isDraftConversation
                        && !viewModel.cascadeId.isEmpty,
                       let gwUrl = AppSettings.shared.gatewayURL {
                        viewModel.inputText = ""
                        isInputFocused = false
                        let parentId = viewModel.cascadeId
                        let activeModel = viewModel.activeModel
                        Task {
                            _ = try? await APIClient.shared.startBtwSideQuestion(
                                parentCascadeId: parentId,
                                question: draft,
                                model: activeModel,
                                baseURL: gwUrl
                            )
                            btwInitialQuote = nil
                            showBtwSheet = true
                        }
                    } else {
                        isInputFocused = false
                        btwInitialQuote = nil
                        showBtwSheet = true
                    }
                },
                onTapSwarm: {
                    if viewModel.isSwarmActive {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        isInputFocused = false
                        showSwarmSheet = true
                    } else {
                        viewModel.toggleQuickSlashMode("swarm", fallbackTitle: "Swarm", fallbackIcon: "swarm_bee")
                    }
                },
                onOpenSwarmBoard: {
                    isInputFocused = false
                    showSwarmSheet = true
                },
                onOpenWorkflowTemplates: {
                    isInputFocused = false
                    workflowSheetStartInEditMode = false
                    showWorkflowTemplateSheet = true
                },
                onTapGoal: {
                    viewModel.toggleQuickSlashMode("goal", fallbackTitle: "Goal", fallbackIcon: "timer")
                }
            )
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .readableChatWidth(horizontalSizeClass == .regular)
        .background(AGPalette.pageBackground(colorScheme))
        .overlay(
            Rectangle()
                .fill(AGPalette.borderSubtle(colorScheme))
                .frame(height: 0.75),
            alignment: .top
        )
    }
    // hasSendableDraft / isSendDisabled 仅在 ChatInputTextAndSendRow 内部计算：
    // 不要在 ChatView 上重新声明并在 body 中读取，否则会把 inputText 订阅带回 ChatView.body，打字时整页重绘。

    private var modelChipForegroundColor: Color {
        switch viewModel.activeModelProviderKind {
        case .claude:
            return AGPalette.claudeBrandText(colorScheme)
        case .gemini:
            return AGPalette.geminiBrandText(colorScheme)
        default:
            return AGPalette.textPrimary(colorScheme)
        }
    }

    private var modelChipBackgroundColor: Color {
        AGPalette.recessedWell(colorScheme)
    }

    private var modelChipBorderColor: Color {
        AGPalette.border(colorScheme)
    }
}

private struct ChatFloatingSlashPopupHost: View {
    @Bindable var viewModel: ChatViewModel
    @Binding var isSlashPickerDismissed: Bool
    let currentViewportHeight: CGFloat
    var onSelectWorkflow: (() -> Void)? = nil

    var body: some View {
        if GatewayCompatStore.shared.isAvailable(GatewayFeature.slash),
           !viewModel.showMentionPicker,
           !isSlashPickerDismissed,
           let slashQuery = SlashCommandFilter.query(of: viewModel.inputText) {
            let maxTotal = currentViewportHeight > 0 ? min(max(currentViewportHeight - 16, 200), 360) : 300
            let maxList = max(maxTotal - 46, 154)
            SlashCommandPickerView(
                commands: SlashCommandFilter.filter(viewModel.slashCommands, query: slashQuery),
                isLoading: viewModel.isLoadingSlashCommands,
                maxListHeight: maxList,
                onSelect: { cmd in
                    isSlashPickerDismissed = false
                    if cmd.name == "workflow" {
                        onSelectWorkflow?()
                        viewModel.selectSlashCommand(cmd)
                    } else {
                        viewModel.selectSlashCommand(cmd)
                    }
                },
                onDismiss: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeOut(duration: 0.18)) {
                        isSlashPickerDismissed = true
                    }
                }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .zIndex(100)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)).combined(with: .offset(y: 6)),
                    removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom))
                )
            )
            .onAppear { viewModel.ensureSlashCommands() }
        }
    }
}

private struct ChatInputTextAndSendRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var viewModel: ChatViewModel
    @ObservedObject var voiceCall: VoiceCallManager
    let dictationManager: AudioDictationManager
    let modelPickerState: ModelSlidePickerState
    let modelChipForegroundColor: Color
    let modelChipBackgroundColor: Color
    let modelChipBorderColor: Color
    @Binding var isInputFocused: Bool
    @Binding var isSlashPickerDismissed: Bool
    let onSend: () -> Void
    let onCancel: () -> Void
    let onStartVoiceCall: () -> Void
    let onAudioRecord: () -> Void
    let onStartDictation: () -> Void
    let onOpenAttachmentSheet: () -> Void
    let onOpenBtw: () -> Void
    let onTapSwarm: () -> Void
    let onOpenSwarmBoard: () -> Void
    let onOpenWorkflowTemplates: () -> Void
    let onTapGoal: () -> Void

    private var hasSendableDraft: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.selectedImageData.isEmpty
            || !viewModel.selectedFiles.isEmpty
            || viewModel.selectedSlashCommand != nil
            || !viewModel.selectedContextItems.isEmpty
    }

    private var isSendDisabled: Bool {
        viewModel.isSending
            || viewModel.selectedFiles.contains(where: { !$0.isUploaded })
            || !hasSendableDraft
    }

    private var isSwarmHighlighted: Bool {
        viewModel.isSwarmActive || viewModel.selectedSlashCommand?.name == "swarm"
    }

    private var isGoalHighlighted: Bool {
        viewModel.selectedSlashCommand?.name == "goal"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Text input + inline right-side Mic / Duplex Voice button
            HStack(alignment: .center, spacing: 8) {
                BracketPlaceholderTextInput(
                    text: $viewModel.inputText,
                    placeholder: viewModel.isActivelyRunning
                        ? String(localized: "向队列追加指令...")
                        : String(localized: "输入指令，@ 引用上下文或 / 调技能..."),
                    isFocused: $isInputFocused,
                    pendingSelectFirstPlaceholder: $viewModel.pendingSelectFirstPlaceholder
                )
                .frame(minHeight: 28)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isInputFocused {
                        isInputFocused = true
                    }
                }

                if AppSettings.shared.enableVoiceMode && !voiceCall.isInCall {
                    VoiceModeButton(
                        isDictating: dictationManager.isDictating,
                        onStartVoiceCall: onStartVoiceCall,
                        onStartDictation: onStartDictation,
                        onStopDictation: {
                            if dictationManager.isDictating {
                                dictationManager.stop()
                            }
                        }
                    )
                } else if !voiceCall.isInCall {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if dictationManager.isDictating {
                            dictationManager.stop()
                        } else if AppSettings.shared.gatewayURL != nil {
                            onStartDictation()
                        } else {
                            onAudioRecord()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(dictationManager.isDictating ? AGPalette.roseSoft(colorScheme) : AGPalette.recessedWell(colorScheme))
                                .frame(width: 28, height: 28)
                            AGLinearIcon(
                                .mic,
                                size: 14,
                                color: dictationManager.isDictating ? AGPalette.roseText(colorScheme) : AGPalette.textSecondary(colorScheme),
                                lineWidth: 1.95
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dictationManager.isDictating ? "停止语音听写" : "语音听写")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Row 2: Left ([+] + Brand Model Chip) | Right (btw · Swarm · Goal + Send/Stop)
            ViewThatFits(in: .horizontal) {
                composerBottomToolbarRow(compactModelTitle: false, showModeIcons: true, fixedModelWidth: true)
                composerBottomToolbarRow(compactModelTitle: true, showModeIcons: false, fixedModelWidth: true)
                composerBottomToolbarRow(compactModelTitle: true, showModeIcons: false, fixedModelWidth: false)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 9)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AGPalette.composerBackground(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isInputFocused
                        ? AGPalette.accentFill(colorScheme).opacity(colorScheme == .dark ? 0.65 : 0.45)
                        : AGPalette.border(colorScheme),
                    lineWidth: isInputFocused ? 1.25 : 1.0
                )
        )
        .shadow(
            color: colorScheme == .dark ? Color.black.opacity(0.28) : Color.black.opacity(0.04),
            radius: 10,
            x: 0,
            y: 3
        )
        .animation(.easeInOut(duration: 0.18), value: viewModel.isActivelyRunning)
        .animation(.easeInOut(duration: 0.18), value: voiceCall.isInCall)
        .animation(.easeInOut(duration: 0.16), value: hasSendableDraft)
        .animation(.easeInOut(duration: 0.16), value: isInputFocused)
        .onChange(of: viewModel.inputText) { oldText, newText in
            if SlashCommandFilter.query(of: newText) == nil {
                isSlashPickerDismissed = false
            } else if newText.hasSuffix("/") && !oldText.hasSuffix("/") {
                isSlashPickerDismissed = false
            }
            detectAtMentionTyping(oldText: oldText, newText: newText)
        }
    }

    private var compactActiveModelDisplayName: String {
        let full = viewModel.activeModelDisplayName
        guard full.count > 15 else { return full }
        if full.hasPrefix("Claude ") {
            return String(full.dropFirst("Claude ".count))
        }
        if full.hasPrefix("Anthropic ") {
            return String(full.dropFirst("Anthropic ".count))
        }
        if full.hasPrefix("Google ") {
            return String(full.dropFirst("Google ".count))
        }
        return full
    }

    @ViewBuilder
    private func composerBottomToolbarRow(
        compactModelTitle: Bool,
        showModeIcons: Bool,
        fixedModelWidth: Bool
    ) -> some View {
        HStack(spacing: 4) {
            // 1. [+] Attachment & @ Context button
            Button(action: onOpenAttachmentSheet) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .fill(AGPalette.recessedWell(colorScheme))
                        .frame(width: 28, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                                .stroke(AGPalette.border(colorScheme), lineWidth: 1)
                        )
                    AGLinearIcon(.plus, size: 13.5, color: AGPalette.textPrimary(colorScheme), lineWidth: 2.1)
                }
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.openMentionPicker()
                }
            )
            .accessibilityLabel("添加附件、照片、录音或 @ 引用上下文")

            // 2. Official Gemini / Claude Brand Model Switch Chip
            let modelChip = ModelSwitchChipButton(
                displayName: compactModelTitle ? compactActiveModelDisplayName : viewModel.activeModelDisplayName,
                foregroundColor: modelChipForegroundColor,
                backgroundColor: modelChipBackgroundColor,
                borderColor: modelChipBorderColor,
                providerKind: viewModel.activeModelProviderKind,
                activeModelID: viewModel.activeModel,
                pickerState: modelPickerState,
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.toggleModel()
                    }
                },
                onSelectModel: { modelId in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.selectModel(modelId)
                    }
                }
            )

            if fixedModelWidth {
                modelChip.fixedSize(horizontal: true, vertical: false)
            } else {
                modelChip
            }

            Spacer(minLength: 3)

            // 3. Right-side Action Cluster: btw · Swarm · Goal
            HStack(spacing: 3.5) {
                composerModeButton(
                    label: "btw",
                    isActive: false,
                    activeTone: .accent,
                    showIcon: showModeIcons,
                    action: onOpenBtw
                ) {
                    SlashCommandIconView(name: "btw", size: 10.5)
                }

                composerModeButton(
                    label: "Swarm",
                    isActive: isSwarmHighlighted,
                    activeTone: .violet,
                    showIcon: showModeIcons,
                    action: onTapSwarm
                ) {
                    SlashCommandIconView(name: "swarm", icon: "swarm_bee", size: 10.5)
                }
                .contextMenu {
                    if !viewModel.isDraftConversation {
                        Button(action: onOpenSwarmBoard) {
                            Label("打开 Swarm 协作看板", systemImage: "point.3.connected.trianglepath.dotted")
                        }
                    }
                    Button(action: onOpenWorkflowTemplates) {
                        Label("多智能体编排模板库", systemImage: "square.stack.3d.up")
                    }
                }

                composerModeButton(
                    label: "Goal",
                    isActive: isGoalHighlighted,
                    activeTone: .accent,
                    showIcon: showModeIcons,
                    action: onTapGoal
                ) {
                    SlashCommandIconView(name: "goal", size: 10.5)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            // 4. Primary Send / Stop / Hang-up button
            primaryActionButton
        }
    }

    @ViewBuilder
    private func composerModeButton<Icon: View>(
        label: String,
        isActive: Bool,
        activeTone: AGSemanticTone,
        showIcon: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        let fg: Color = {
            if !isActive { return AGPalette.textSecondary(colorScheme) }
            return activeTone == .violet ? AGPalette.violetText(colorScheme) : AGPalette.accentText(colorScheme)
        }()
        let bg: Color = {
            if !isActive { return AGPalette.recessedWell(colorScheme) }
            return activeTone == .violet ? AGPalette.violetSoft(colorScheme) : AGPalette.accentSoft(colorScheme)
        }()
        let border: Color = {
            if !isActive { return AGPalette.borderSubtle(colorScheme) }
            return (activeTone == .violet ? AGPalette.violetFill(colorScheme) : AGPalette.accentFill(colorScheme)).opacity(0.55)
        }()

        Button(action: action) {
            HStack(spacing: 3) {
                if showIcon {
                    icon()
                        .foregroundColor(fg)
                }
                Text(label)
                    .font(.system(size: showIcon ? 11 : 10.5, weight: isActive ? .bold : .semibold))
                    .foregroundColor(fg)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, showIcon ? 7 : 6.5)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if voiceCall.isInCall && !hasSendableDraft {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                voiceCall.endCall()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AGPalette.roseFill(colorScheme))
                        .frame(width: 29, height: 29)
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("挂断实时语音通话")
        } else if viewModel.isActivelyRunning && !hasSendableDraft {
            Button(action: onCancel) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AGPalette.roseSoft(colorScheme))
                        .frame(width: 29, height: 29)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(AGPalette.roseFill(colorScheme).opacity(0.45), lineWidth: 1)
                        )
                    AGLinearIcon(.stop, size: 12, color: AGPalette.roseText(colorScheme), lineWidth: 2.1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("停止当前生成")
        } else {
            Button(action: onSend) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSendDisabled ? AGPalette.recessedWell(colorScheme) : AGPalette.accentFill(colorScheme))
                        .frame(width: 29, height: 29)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(isSendDisabled ? AGPalette.borderSubtle(colorScheme) : Color.clear, lineWidth: 1)
                        )
                    AGLinearIcon(
                        .arrowUp,
                        size: 14,
                        color: isSendDisabled ? AGPalette.textTertiary(colorScheme) : .white,
                        lineWidth: 2.25
                    )
                }
            }
            .disabled(isSendDisabled)
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("发送指令")
        }
    }

    private func trailingAtMentionQuery(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "(?:^|\\s)@([^\\s@]*)$", options: []) else {
            return nil
        }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }

    private func detectAtMentionTyping(oldText: String, newText: String) {
        if let query = trailingAtMentionQuery(in: newText) {
            if !viewModel.showMentionPicker {
                viewModel.openMentionPicker(query: query)
            } else {
                viewModel.scheduleMentionSearch(query: query)
            }
            return
        }
        if viewModel.showMentionPicker && (trailingAtMentionQuery(in: oldText) != nil || newText.hasSuffix(" ")) {
            viewModel.closeMentionPicker()
        }
    }
}

private struct NarrationPlayerBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let player: NarrationAudioPlayer

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AGPalette.accentText(colorScheme))
            Text(player.statusLabel.isEmpty ? String(localized: "正在语音播报...") : player.statusLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AGPalette.textPrimary(colorScheme))
            Spacer()
            Button("停止") {
                player.stop()
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(AGPalette.roseText(colorScheme))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AGPalette.accentSoft(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 14)
    }
}

private struct VoiceModeButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let isDictating: Bool
    let onStartVoiceCall: () -> Void
    let onStartDictation: () -> Void
    let onStopDictation: () -> Void

    @State private var isPressing = false
    @State private var hasTriggeredDictation = false
    @State private var holdTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            Circle()
                .fill(isDictating ? AGPalette.accentFill(colorScheme) : AGPalette.recessedWell(colorScheme))
                .frame(width: 29, height: 29)
                .overlay(
                    Circle()
                        .stroke(isDictating ? AGPalette.accentFill(colorScheme) : AGPalette.border(colorScheme), lineWidth: 1)
                )
                .scaleEffect(isDictating ? 1.08 : (isPressing ? 0.94 : 1.0))
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDictating)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressing)

            AntigravityVoiceShape()
                .fill(isDictating ? Color.white : AGPalette.textSecondary(colorScheme))
                .frame(width: 15, height: 15)
        }
        .contentShape(Circle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressing {
                        isPressing = true
                        hasTriggeredDictation = false
                        holdTask?.cancel()
                        holdTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            if !Task.isCancelled && isPressing {
                                hasTriggeredDictation = true
                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                onStartDictation()
                            }
                        }
                    }
                }
                .onEnded { _ in
                    holdTask?.cancel()
                    holdTask = nil
                    let wasDictating = isDictating || hasTriggeredDictation
                    isPressing = false

                    if wasDictating {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onStopDictation()
                    } else {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onStartVoiceCall()
                    }
                    hasTriggeredDictation = false
                }
        )
        .accessibilityLabel(isDictating ? String(localized: "正在流式听写，松开结束") : String(localized: "实时语音对话，按住流式听写"))
        .accessibilityHint("短按开始实时语音对话，按住说话可进行流式听写")
    }
}

private struct DictationActiveBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AGPalette.roseFill(colorScheme))
                .frame(width: 7, height: 7)
            Text("按住流式听写中，松开结束...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AGPalette.textPrimary(colorScheme))
            Spacer()
            Button("完成") {
                onStop()
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(AGPalette.accentText(colorScheme))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AGPalette.roseSoft(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 14)
    }
}

private struct SuggestedResponsesBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(suggestions, id: \.self) { text in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSelect(text)
                    } label: {
                        Text(text)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AGPalette.accentText(colorScheme))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5.5)
                            .background(AGPalette.accentSoft(colorScheme))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(AGPalette.accentFill(colorScheme).opacity(0.28), lineWidth: 0.9)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

private struct ContextMentionsChipBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let items: [ContextMentionItem]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 4) {
                        AGLinearIcon(
                            item.type == "directory" ? .folder : (item.type == "conversation" ? .chat : .fileText),
                            size: 11,
                            color: AGPalette.accentText(colorScheme),
                            lineWidth: 1.95
                        )
                        Text("@\(item.label)")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundColor(AGPalette.textPrimary(colorScheme))
                            .lineLimit(1)
                        Button {
                            onRemove(item.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(AGPalette.textTertiary(colorScheme))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AGPalette.accentSoft(colorScheme))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
        }
    }
}

private struct ChatFloatingMentionPopupHost: View {
    @Bindable var viewModel: ChatViewModel
    let currentViewportHeight: CGFloat

    var body: some View {
        if viewModel.showMentionPicker {
            let maxTotal: CGFloat = currentViewportHeight > 0
                ? min(max(currentViewportHeight - 12, 240), 500)
                : 380
            let maxList = max(maxTotal - 96, 160)
            MentionPickerView(
                viewModel: viewModel,
                maxListHeight: maxList
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .zIndex(101)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)).combined(with: .offset(y: 8)),
                    removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom))
                )
            )
        }
    }
}

private struct MentionPickerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var viewModel: ChatViewModel
    var maxListHeight: CGFloat = 320

    @State private var contentHeight: CGFloat = 0

    private var effectiveListHeight: CGFloat {
        let clampedMax = max(maxListHeight, 160)
        let minComfortable = min(200, clampedMax)
        let fallback = CGFloat(max(viewModel.mentionCandidates.count, 1)) * 68
        let measured = contentHeight > 0 ? contentHeight : fallback
        return min(max(measured, minComfortable), clampedMax)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部标题栏 + 数量徽标 + 关闭按钮
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AGPalette.accentSoft(colorScheme))
                        .frame(width: 24, height: 24)
                    Text("@")
                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                        .foregroundColor(AGPalette.accentText(colorScheme))
                }

                Text("引用文件或关联会话")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))

                if !viewModel.mentionCandidates.isEmpty {
                    Text("\(viewModel.mentionCandidates.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AGPalette.accentText(colorScheme))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(AGPalette.accentSoft(colorScheme))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 8)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.closeMentionPicker()
                } label: {
                    AGLinearIcon(.close, size: 12, color: AGPalette.textSecondary(colorScheme), lineWidth: 2.1)
                        .frame(width: 26, height: 26)
                        .background(AGPalette.recessedWell(colorScheme))
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭引用选择浮窗")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // 搜索输入框
            HStack(spacing: 8) {
                AGLinearIcon(.search, size: 13.5, color: AGPalette.textSecondary(colorScheme))
                TextField("搜索文件、目录或关联会话...", text: Binding(
                    get: { viewModel.mentionQuery },
                    set: { viewModel.scheduleMentionSearch(query: $0) }
                ))
                .font(.system(size: 14))
                .foregroundColor(AGPalette.textPrimary(colorScheme))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                if viewModel.isLoadingMentions {
                    ProgressView().scaleEffect(0.8)
                } else if !viewModel.mentionQuery.isEmpty {
                    Button {
                        viewModel.scheduleMentionSearch(query: "")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AGPalette.textTertiary(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AGPalette.recessedWell(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AGPalette.borderSubtle(colorScheme), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Rectangle()
                .fill(AGPalette.borderSubtle(colorScheme))
                .frame(height: 0.75)

            if viewModel.mentionCandidates.isEmpty {
                VStack(spacing: 10) {
                    if viewModel.isLoadingMentions {
                        ProgressView()
                            .scaleEffect(0.95)
                    } else {
                        AGLinearIcon(.fileText, size: 22, color: AGPalette.textTertiary(colorScheme))
                    }
                    Text(viewModel.isLoadingMentions ? String(localized: "正在检索工作区上下文...") : String(localized: "暂无匹配的文件、目录或关联会话"))
                        .font(.system(size: 13.5))
                        .foregroundColor(AGPalette.textSecondary(colorScheme))
                }
                .frame(maxWidth: .infinity)
                .frame(height: min(200, max(maxListHeight, 160)))
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.mentionCandidates.enumerated()), id: \.element.id) { index, item in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                viewModel.selectMentionItem(item)
                            } label: {
                                mentionRow(item)
                            }
                            .buttonStyle(.plain)

                            if index < viewModel.mentionCandidates.count - 1 {
                                Rectangle()
                                    .fill(AGPalette.borderSubtle(colorScheme))
                                    .frame(height: 0.75)
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        if newHeight > 0 && abs(contentHeight - newHeight) > 0.5 {
                            contentHeight = newHeight
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: effectiveListHeight)
            }
        }
        .agCard(cornerRadius: 16)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.36 : 0.12), radius: 18, x: 0, y: 6)
    }

    private func mentionRow(_ item: ContextMentionItem) -> some View {
        let style = mentionStyle(for: item.type)
        let isAlreadySelected = viewModel.selectedContextItems.contains(where: { $0.id == item.id && $0.label == item.label })

        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(style.softBg)
                    .frame(width: 34, height: 34)
                AGLinearIcon(style.icon, size: 15, color: style.textColor, lineWidth: 1.95)
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.label)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(AGPalette.textPrimary(colorScheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(style.tag)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(style.textColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(style.softBg)
                        .clipShape(Capsule())
                }

                if let detail = item.detail ?? item.path, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(AGPalette.textSecondary(colorScheme))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            if isAlreadySelected {
                AGLinearIcon(.check, size: 15, color: AGPalette.accentText(colorScheme), lineWidth: 2.2)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func mentionStyle(for type: String) -> (icon: AGIconKind, textColor: Color, softBg: Color, tag: String) {
        switch type {
        case "directory":
            return (.folder, AGPalette.accentText(colorScheme), AGPalette.accentSoft(colorScheme), String(localized: "目录"))
        case "conversation":
            return (.chat, AGPalette.emeraldText(colorScheme), AGPalette.emeraldSoft(colorScheme), String(localized: "会话"))
        default:
            return (.fileText, AGPalette.violetText(colorScheme), AGPalette.violetSoft(colorScheme), String(localized: "文件"))
        }
    }
}

/// 1:1 对齐 Antigravity 桌面端（main.js tuc() 组件）的 3 波形条 + 4 芒星矢量图标
nonisolated struct AntigravityVoiceShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let ox = rect.minX
        let oy = rect.minY
        
        // Bar 1: x: 167.8, y: -575.2, width: 82, height: 350, rx: 41
        let bar1 = CGRect(x: ox + w * 0.21021, y: oy + h * 0.35083, width: w * 0.08542, height: h * 0.36458)
        let r1 = w * 0.04271
        path.addRoundedRect(in: bar1, cornerSize: CGSize(width: r1, height: r1))
        
        // Bar 2: x: 359.8, y: -662.7, width: 82, height: 525, rx: 41
        let bar2 = CGRect(x: ox + w * 0.41021, y: oy + h * 0.25969, width: w * 0.08542, height: h * 0.54688)
        let r2 = w * 0.04271
        path.addRoundedRect(in: bar2, cornerSize: CGSize(width: r2, height: r2))
        
        // Bar 3: x: 551.8, y: -512.7, width: 82, height: 225, rx: 41
        let bar3 = CGRect(x: ox + w * 0.61021, y: oy + h * 0.41594, width: w * 0.08542, height: h * 0.23438)
        let r3 = w * 0.04271
        path.addRoundedRect(in: bar3, cornerSize: CGSize(width: r3, height: r3))
        
        // Sparkle 4-point star (upper-right)
        path.move(to: CGPoint(x: ox + w * 0.78958, y: oy + h * 0.37400))
        path.addQuadCurve(to: CGPoint(x: ox + w * 0.78158, y: oy + h * 0.36800), control: CGPoint(x: ox + w * 0.78358, y: oy + h * 0.37400))
        path.addQuadCurve(to: CGPoint(x: ox + w * 0.72416, y: oy + h * 0.26750), control: CGPoint(x: ox + w * 0.76635, y: oy + h * 0.30969))
        path.addQuadCurve(to: CGPoint(x: ox + w * 0.62366, y: oy + h * 0.21008), control: CGPoint(x: ox + w * 0.68197, y: oy + h * 0.22531))
        path.addQuadCurve(to: CGPoint(x: ox + w * 0.61766, y: oy + h * 0.20208), control: CGPoint(x: ox + w * 0.61766, y: oy + h * 0.20808))
        path.addQuadCurve(to: CGPoint(x: ox + w * 0.62366, y: oy + h * 0.19408), control: CGPoint(x: ox + w * 0.61766, y: oy + h * 0.19508))
        path.addQuadCurve(to: CGPoint(x: ox + w * 0.72416, y: oy + h * 0.13666), control: CGPoint(x: ox + w * 0.68197, y: oy + h * 0.17885))
        path.addQuadCurve(to: CGPoint(x: ox + w * 0.78158, y: oy + h * 0.03616), control: CGPoint(x: ox + w * 0.76635, y: oy + h * 0.09447))
        path.addQuadCurve(to: CGPoint(x: ox + w * 0.78958, y: oy + h * 0.03016), control: CGPoint(x: ox + w * 0.78358, y: oy + h * 0.03016))
        path.addQuadCurve(to: CGPoint(x: ox + w * 0.79758, y: oy + h * 0.03616), control: CGPoint(x: ox + w * 0.79658, y: oy + h * 0.03016))
        path.addQuadCurve(to: CGPoint(x: ox + w * 0.85538, y: oy + h * 0.13669), control: CGPoint(x: ox + w * 0.81343, y: oy + h * 0.09447))
        path.addQuadCurve(to: CGPoint(x: ox + w * 0.95550, y: oy + h * 0.19409), control: CGPoint(x: ox + w * 0.89733, y: oy + h * 0.17891))
        path.addQuadCurve(to: CGPoint(x: ox + w * 0.96150, y: oy + h * 0.20209), control: CGPoint(x: ox + w * 0.96150, y: oy + h * 0.19509))
        path.addQuadCurve(to: CGPoint(x: ox + w * 0.95550, y: oy + h * 0.21009), control: CGPoint(x: ox + w * 0.96150, y: oy + h * 0.20809))
        path.addQuadCurve(to: CGPoint(x: ox + w * 0.85500, y: oy + h * 0.26751), control: CGPoint(x: ox + w * 0.89719, y: oy + h * 0.22532))
        path.addQuadCurve(to: CGPoint(x: ox + w * 0.79758, y: oy + h * 0.36801), control: CGPoint(x: ox + w * 0.81281, y: oy + h * 0.30970))
        path.addQuadCurve(to: CGPoint(x: ox + w * 0.78958, y: oy + h * 0.37401), control: CGPoint(x: ox + w * 0.79658, y: oy + h * 0.37401))
        path.closeSubpath()
        
        return path
    }
}

private struct BracketPlaceholderTextInput: View {
    @Binding var text: String
    let placeholder: String
    @Binding var isFocused: Bool
    @Binding var pendingSelectFirstPlaceholder: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            BracketPlaceholderUITextView(
                text: $text,
                isFocused: $isFocused,
                pendingSelectFirstPlaceholder: $pendingSelectFirstPlaceholder
            )
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 16))
                    .foregroundColor(Color(uiColor: .placeholderText))
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct BracketPlaceholderUITextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var pendingSelectFirstPlaceholder: Bool

    private static let placeholderRegex = try? NSRegularExpression(pattern: "\\[[^\\[\\]\\n]+\\]")

    static func bracketPlaceholderRanges(in text: String) -> [NSRange] {
        guard let regex = placeholderRegex, !text.isEmpty else { return [] }
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        return regex.matches(in: text, options: [], range: fullRange).map(\.range)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = context.coordinator
        textView.addGestureRecognizer(tapGesture)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self

        if uiView.markedTextRange == nil && uiView.text != text {
            uiView.text = text
            uiView.invalidateIntrinsicContentSize()
        }

        let parentFocused = isFocused
        let focusChangedFromParent = (parentFocused != context.coordinator.lastParentFocused)
        context.coordinator.lastParentFocused = parentFocused

        if pendingSelectFirstPlaceholder {
            let currentText = uiView.text ?? text
            let firstRange = Self.bracketPlaceholderRanges(in: currentText).first
            DispatchQueue.main.async {
                self.pendingSelectFirstPlaceholder = false
            }
            if let firstRange {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    if !uiView.isFirstResponder {
                        uiView.becomeFirstResponder()
                    }
                    uiView.selectedRange = firstRange
                    uiView.scrollRangeToVisible(firstRange)
                }
                return
            }
        }

        if focusChangedFromParent {
            if parentFocused && !uiView.isFirstResponder {
                DispatchQueue.main.async {
                    if self.isFocused && !uiView.isFirstResponder {
                        uiView.becomeFirstResponder()
                    }
                }
            } else if !parentFocused && uiView.isFirstResponder {
                DispatchQueue.main.async {
                    if !self.isFocused && uiView.isFirstResponder {
                        uiView.resignFirstResponder()
                    }
                }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let targetWidth = proposal.width ?? uiView.bounds.width
        guard targetWidth > 0 else { return nil }
        let lineHeight = max(uiView.font?.lineHeight ?? 20, 22.5)
        let verticalInset = uiView.textContainerInset.top + uiView.textContainerInset.bottom
        let minHeight = max(26, ceil(lineHeight) + verticalInset)
        let maxHeight = ceil(lineHeight * 5) + verticalInset
        let fittingSize = uiView.sizeThatFits(CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
        let clampedHeight = min(max(minHeight, ceil(fittingSize.height)), maxHeight)
        let needsScroll = ceil(fittingSize.height) > maxHeight
        if uiView.isScrollEnabled != needsScroll {
            uiView.isScrollEnabled = needsScroll
            if !needsScroll && uiView.contentOffset != .zero {
                uiView.setContentOffset(.zero, animated: false)
            } else if needsScroll && uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.scrollRangeToVisible(uiView.selectedRange)
                }
            }
        } else if !needsScroll && uiView.contentOffset != .zero {
            uiView.setContentOffset(.zero, animated: false)
        }
        return CGSize(width: targetWidth, height: clampedHeight)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: BracketPlaceholderUITextView
        var lastParentFocused: Bool = false

        init(parent: BracketPlaceholderUITextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            if parent.text != newText {
                parent.text = newText
            }
            textView.invalidateIntrinsicContentSize()
            if textView.isScrollEnabled {
                DispatchQueue.main.async {
                    textView.scrollRangeToVisible(textView.selectedRange)
                }
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.lastParentFocused = true
                if !self.parent.isFocused {
                    self.parent.isFocused = true
                }
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.lastParentFocused = false
                if self.parent.isFocused {
                    self.parent.isFocused = false
                }
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let textView = recognizer.view as? UITextView,
                  let text = textView.text, !text.isEmpty else { return }
            let ranges = BracketPlaceholderUITextView.bracketPlaceholderRanges(in: text)
            guard !ranges.isEmpty else { return }

            var location = recognizer.location(in: textView)
            location.x -= textView.textContainerInset.left
            location.y -= textView.textContainerInset.top

            let layoutManager = textView.layoutManager
            let textContainer = textView.textContainer
            var fraction: CGFloat = 0
            let charIndex = layoutManager.characterIndex(
                for: location,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: &fraction
            )

            let matchedRange = ranges.first { range in
                if NSLocationInRange(charIndex, range) {
                    return true
                }
                if charIndex > 0 && fraction < 0.2 && NSLocationInRange(charIndex - 1, range) {
                    return true
                }
                return false
            }
            guard let targetRange = matchedRange else { return }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: targetRange, actualCharacterRange: nil)
            var boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            boundingRect = boundingRect.insetBy(dx: -6, dy: -6)
            guard boundingRect.contains(location) else { return }

            DispatchQueue.main.async {
                if !textView.isFirstResponder {
                    textView.becomeFirstResponder()
                }
                textView.selectedRange = targetRange
            }
        }
    }
}

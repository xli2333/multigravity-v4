import SwiftUI

public struct RunningTasksCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    public let cascadeId: String
    public let items: [RunningTaskItem]
    public let alwaysExpanded: Bool
    public let onStop: @MainActor @Sendable (RunningTaskItem) -> Void
    public let onSendToBackground: (@MainActor @Sendable (RunningTaskItem) -> Void)?
    public let onToggleExpand: (@MainActor @Sendable (Bool) -> Void)?
    public let onOpenTaskBoard: (@MainActor @Sendable () -> Void)?
    public let onClose: (@MainActor @Sendable () -> Void)?
    
    @State private var settings = AppSettings.shared
    @State private var isCardExpanded: Bool
    @State private var expandedCommandIds: Set<String> = []
    @State private var copiedCommandId: String? = nil
    @State private var showTerminalPanel: Bool = false
    @State private var pendingStopDaemonTask: RunningTaskItem? = nil
    
    public init(
        cascadeId: String = "",
        items: [RunningTaskItem],
        alwaysExpanded: Bool = false,
        onStop: @escaping @MainActor @Sendable (RunningTaskItem) -> Void,
        onSendToBackground: (@MainActor @Sendable (RunningTaskItem) -> Void)? = nil,
        onToggleExpand: (@MainActor @Sendable (Bool) -> Void)? = nil,
        onOpenTaskBoard: (@MainActor @Sendable () -> Void)? = nil,
        onClose: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.cascadeId = cascadeId
        self.items = items
        self.alwaysExpanded = alwaysExpanded
        self.onStop = onStop
        self.onSendToBackground = onSendToBackground
        self.onToggleExpand = onToggleExpand
        self.onOpenTaskBoard = onOpenTaskBoard
        self.onClose = onClose
        _isCardExpanded = State(initialValue: alwaysExpanded ? true : !AppSettings.shared.shouldCollapseRunningTasks)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Row
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(AGPalette.emeraldText(colorScheme))
                
                Text("\(items.count) 个任务正在执行")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))
                
                // Count Badge
                Text("\(items.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AGPalette.textSecondary(colorScheme))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(AGPalette.recessedWell(colorScheme))
                    .clipShape(Capsule())
                
                Spacer()

                if alwaysExpanded || isCardExpanded || !settings.shouldCollapseRunningTasks {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showTerminalPanel.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            AGLinearIcon(
                                .terminal,
                                size: 11.5,
                                color: showTerminalPanel ? .white : AGPalette.accentText(colorScheme),
                                lineWidth: 2.0
                            )
                            Text(showTerminalPanel ? String(localized: "收起终端") : String(localized: "终端交互"))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(showTerminalPanel ? .white : AGPalette.accentText(colorScheme))
                        .padding(.horizontal, 8.5)
                        .padding(.vertical, 4.5)
                        .background(showTerminalPanel ? AGPalette.accentFill(colorScheme) : AGPalette.accentSoft(colorScheme))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else if items.count == 1, let singleTask = items.first {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if singleTask.isDaemon == true {
                            pendingStopDaemonTask = singleTask
                        } else {
                            onStop(singleTask)
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(AGPalette.roseSoft(colorScheme))
                                .frame(width: 24, height: 24)
                            AGLinearIcon(.stop, size: 10.5, color: AGPalette.roseText(colorScheme), lineWidth: 2.1)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                    .accessibilityLabel("终止任务")
                    .help("终止任务")
                }

                if let onOpenTaskBoard {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onOpenTaskBoard()
                    } label: {
                        AGLinearIcon(.layers, size: 13.5, color: AGPalette.textSecondary(colorScheme), lineWidth: 2.0)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(AGPalette.recessedWell(colorScheme)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开全局后台任务看板")
                }

                if let onClose {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onClose()
                    } label: {
                        AGLinearIcon(.close, size: 12, color: AGPalette.textSecondary(colorScheme), lineWidth: 2.1)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(AGPalette.recessedWell(colorScheme)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("收起任务面板")
                } else if !alwaysExpanded {
                    // Expand / Collapse Card Toggle
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isCardExpanded.toggle()
                        }
                        onToggleExpand?(isCardExpanded)
                    }) {
                        AGLinearIcon(.chevronDown, size: 13, color: AGPalette.textSecondary(colorScheme), lineWidth: 2.1)
                            .rotationEffect(.degrees(isCardExpanded ? 0 : 180))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCardExpanded ? String(localized: "折叠任务") : String(localized: "展开任务"))
                    .help(isCardExpanded ? String(localized: "折叠任务") : String(localized: "展开任务"))
                }
            }
            .zIndex(10)
            
            // Expandable Content
            if alwaysExpanded || isCardExpanded {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        taskRow(item: item)
                        
                        if item.id != items.last?.id {
                            Rectangle()
                                .fill(AGPalette.borderSubtle(colorScheme))
                                .frame(height: 0.75)
                        }
                    }

                    if showTerminalPanel {
                        InteractiveTerminalPanelView(cascadeId: cascadeId)
                    }
                }
                .clipped()
                .zIndex(1)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                        removal: .opacity
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipped()
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .agCard(cornerRadius: 16)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .onChange(of: settings.shouldCollapseRunningTasks) { _, shouldCollapse in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isCardExpanded = !shouldCollapse
            }
        }
        .onChange(of: cascadeId) { _, _ in
            isCardExpanded = !settings.shouldCollapseRunningTasks
        }
        .confirmationDialog(
            "停止常驻服务？",
            isPresented: Binding(
                get: { pendingStopDaemonTask != nil },
                set: { if !$0 { pendingStopDaemonTask = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingStopDaemonTask
        ) { item in
            Button("停止服务", role: .destructive) {
                onStop(item)
                pendingStopDaemonTask = nil
            }
            Button("取消", role: .cancel) {
                pendingStopDaemonTask = nil
            }
        } message: { item in
            let title = item.toolSummary ?? item.toolAction ?? ToolLocalization.localizedName(for: item.toolName)
            Text("「\(title)」为常驻服务任务，终止后对应本地端口或开发服务将下线。")
        }
    }
    
    @ViewBuilder
    private func taskRow(item: RunningTaskItem) -> some View {
        let isCmdExpanded = expandedCommandIds.contains(item.id)
        let isCopied = copiedCommandId == item.id
        let isLong = isCommandLong(item.commandLine)
        
        VStack(alignment: .leading, spacing: 6) {
            // Task title and action buttons
            HStack(alignment: .center, spacing: 8) {
                let desc = item.toolSummary ?? item.toolAction ?? ToolLocalization.localizedName(for: item.toolName)
                if !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AGPalette.textPrimary(colorScheme))
                        .lineLimit(1)
                }
                
                Spacer()

                if item.isDaemon != true, let onSendToBackground {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSendToBackground(item)
                    } label: {
                        Text("转后台")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(AGPalette.accentText(colorScheme))
                            .padding(.horizontal, 7.5)
                            .padding(.vertical, 3.5)
                            .background(AGPalette.accentSoft(colorScheme))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                
                // Stop Task Button
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if item.isDaemon == true {
                        pendingStopDaemonTask = item
                    } else {
                        onStop(item)
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(AGPalette.roseSoft(colorScheme))
                            .frame(width: 24, height: 24)
                        AGLinearIcon(.stop, size: 10.5, color: AGPalette.roseText(colorScheme), lineWidth: 2.1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("终止任务")
                .help("终止任务")
            }
            
            // Terminal-style command block (长按复制命令行，减少常驻按钮噪点)
            VStack(alignment: .leading, spacing: 4) {
                Text(highlightCommand(item.commandLine))
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(isCmdExpanded ? nil : 3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Expand / Collapse command text button
                if isLong {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isCmdExpanded {
                                expandedCommandIds.remove(item.id)
                            } else {
                                expandedCommandIds.insert(item.id)
                            }
                        }
                    }) {
                        HStack(spacing: 2) {
                            Text(isCmdExpanded ? String(localized: "收起") : String(localized: "展开完整命令"))
                                .font(.system(size: 10, weight: .medium))
                            AGLinearIcon(isCmdExpanded ? .chevronUp : .chevronDown, size: 9, color: AGPalette.accentText(colorScheme), lineWidth: 2.1)
                        }
                        .foregroundColor(AGPalette.accentText(colorScheme))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AGPalette.recessedWell(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AGPalette.borderSubtle(colorScheme), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if isCopied {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("已复制")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.green.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(4)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onLongPressGesture(minimumDuration: 0.4) {
                copyCommand(item.commandLine, id: item.id)
            }
            .contextMenu {
                Button {
                    copyCommand(item.commandLine, id: item.id)
                } label: {
                    Label("复制完整命令", systemImage: "doc.on.doc")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func isCommandLong(_ cmd: String) -> Bool {
        return cmd.count > 100 || cmd.components(separatedBy: "\n").count > 3
    }

    private func copyCommand(_ cmd: String, id: String) {
        UIPasteboard.general.string = cmd
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        copiedCommandId = id
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedCommandId == id {
                copiedCommandId = nil
            }
        }
    }

    private func highlightCommand(_ command: String) -> AttributedString {
        var result = AttributedString("$ ")
        result.foregroundColor = Color.green.opacity(0.8)
        result.font = .system(size: 11, weight: .bold, design: .monospaced)

        let parts = command.components(separatedBy: " ")
        var isFirstWord = true
        for (idx, part) in parts.enumerated() {
            if idx > 0 {
                result.append(AttributedString(" "))
            }
            var attrPart = AttributedString(part)
            attrPart.font = .system(size: 11, design: .monospaced)
            if part.hasPrefix("-") {
                attrPart.foregroundColor = Color.orange
            } else if part == "&&" || part == "||" || part == "|" || part == ";" {
                attrPart.foregroundColor = Color.purple
                isFirstWord = true
            } else if isFirstWord && !part.isEmpty {
                attrPart.foregroundColor = Color.accentColor
                attrPart.font = .system(size: 11, weight: .semibold, design: .monospaced)
                isFirstWord = false
            } else {
                attrPart.foregroundColor = Color.primary.opacity(0.85)
            }
            result.append(attrPart)
        }
        return result
    }
}

@MainActor
@Observable
final class TerminalStreamSession {
    var terminals: [TerminalItem] = []
    var selectedTerminalId: String = ""
    var outputText: String = ""
    var isConnected = false
    var errorText: String? = nil

    private var wsTask: GatewayWebSocketTask?

    func refreshTerminals() async {
        guard let gwUrl = AppSettings.shared.gatewayURL else { return }
        if let list = try? await APIClient.shared.listTerminals(baseURL: gwUrl) {
            terminals = list
            if selectedTerminalId.isEmpty || !list.contains(where: { $0.effectiveId == selectedTerminalId }) {
                if let first = list.first {
                    connect(terminalId: first.effectiveId)
                }
            }
        }
    }

    func connect(terminalId: String) {
        disconnect()
        selectedTerminalId = terminalId
        guard !terminalId.isEmpty, let gwUrl = AppSettings.shared.gatewayURL else { return }
        let q = terminalId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? terminalId
        guard let req = APIClient.shared.authorizedWebSocketRequest(pathAndQuery: "gateway/terminal/stream?terminalId=\(q)", baseURL: gwUrl) else { return }
        let ws = GatewayWebSocketTask(request: req)
        wsTask = ws
        isConnected = true
        outputText = ""
        ws.resume()
        receiveNext()
    }

    func disconnect() {
        isConnected = false
        wsTask?.cancel()
        wsTask = nil
    }

    func sendInput(_ input: String, cascadeId: String) {
        let tid = selectedTerminalId
        guard !tid.isEmpty, let gwUrl = AppSettings.shared.gatewayURL else { return }
        Task {
            try? await APIClient.shared.sendTerminalInput(terminalId: tid, input: input, conversationId: cascadeId, baseURL: gwUrl)
        }
    }

    private func receiveNext() {
        guard isConnected, let ws = wsTask else { return }
        ws.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.isConnected else { return }
                switch result {
                case .success(let msg):
                    if case .string(let str) = msg {
                        self.appendOutput(str)
                    } else if case .data(let data) = msg, let str = String(data: data, encoding: .utf8) {
                        self.appendOutput(str)
                    }
                    self.receiveNext()
                case .failure(let err):
                    self.errorText = err.localizedDescription
                    self.isConnected = false
                }
            }
        }
    }

    private func appendOutput(_ raw: String) {
        var chunk = raw
        if let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            chunk = (obj["data"] as? String) ?? (obj["output"] as? String) ?? (obj["text"] as? String) ?? raw
        }
        outputText.append(chunk)
        if outputText.count > 12000 {
            outputText = String(outputText.suffix(12000))
        }
    }
}

struct InteractiveTerminalPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    let cascadeId: String
    @State private var session = TerminalStreamSession()
    @State private var commandInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("交互终端")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(AGPalette.accentText(colorScheme))

                if !session.terminals.isEmpty {
                    Menu {
                        ForEach(session.terminals) { t in
                            Button(t.displayTitle) {
                                session.connect(terminalId: t.effectiveId)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(session.terminals.first(where: { $0.effectiveId == session.selectedTerminalId })?.displayTitle ?? String(localized: "选择终端"))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(AGPalette.textPrimary(colorScheme))
                                .lineLimit(1)
                            AGLinearIcon(.chevronDown, size: 9, color: AGPalette.textSecondary(colorScheme), lineWidth: 2.0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(AGPalette.cardBackground(colorScheme))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AGPalette.borderSubtle(colorScheme), lineWidth: 1))
                    }
                }

                Spacer()

                Button {
                    Task { await session.refreshTerminals() }
                } label: {
                    AGLinearIcon(.refresh, size: 12, color: AGPalette.textSecondary(colorScheme))
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                Text(session.outputText.isEmpty ? (session.terminals.isEmpty ? String(localized: "暂无活动终端输出") : String(localized: "等待终端输出...")) : session.outputText)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(AGPalette.textPrimary(colorScheme).opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 130)
            .padding(8)
            .background(AGPalette.cardBackground(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AGPalette.borderSubtle(colorScheme), lineWidth: 1))

            HStack(spacing: 6) {
                quickKey("y", send: "y\n")
                quickKey("n", send: "n\n")
                quickKey("Enter", send: "\n")
                quickKey("Ctrl+C", send: "\u{0003}")
            }

            HStack(spacing: 6) {
                TextField("向终端发送输入...", text: $commandInput)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(AGPalette.cardBackground(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AGPalette.borderSubtle(colorScheme), lineWidth: 1))
                    .onSubmit { submitLine() }

                Button("发送") { submitLine() }
                    .font(.system(size: 11.5, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(AGPalette.accentFill(colorScheme))
                    .disabled(session.selectedTerminalId.isEmpty)
            }
        }
        .padding(10)
        .background(AGPalette.recessedWell(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AGPalette.borderSubtle(colorScheme), lineWidth: 1))
        .task { await session.refreshTerminals() }
        .onDisappear { session.disconnect() }
    }

    private func quickKey(_ label: String, send: String) -> some View {
        Button(label) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            session.sendInput(send, cascadeId: cascadeId)
        }
        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
        .foregroundColor(AGPalette.textPrimary(colorScheme))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AGPalette.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(AGPalette.borderSubtle(colorScheme), lineWidth: 1))
        .buttonStyle(.plain)
        .disabled(session.selectedTerminalId.isEmpty)
    }

    private func submitLine() {
        let txt = commandInput
        commandInput = ""
        session.sendInput(txt + "\n", cascadeId: cascadeId)
    }
}

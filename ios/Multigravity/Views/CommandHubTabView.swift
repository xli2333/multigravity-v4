import SwiftUI

/// Tab 2 (`中枢`): Engineering & Automation Command Hub (v4.0 Pure-SVG Bento Architecture).
/// Unifies Live PTY Terminals, Active Swarms, Workspaces & GitHub PRs, Cron Automations,
/// Workflow Templates, MCP Hot-Toggles, and Skills & Agent Memories in a zero-emoji layout.
public struct CommandHubTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var settings = AppSettings.shared

    public let conversations: [ConversationItem]
    public let globalBackgroundTasks: [GlobalBackgroundTaskItem]
    public let onTasksChanged: ([GlobalBackgroundTaskItem]) -> Void
    public let onOpenConversationId: (String) -> Void
    public let onFilterWorkspaceInSessions: (String) -> Void
    public let onCreateSessionForProject: (ProjectItem) -> Void
    public let onStartTemplateSession: (String) -> Void

    @State private var projects: [ProjectItem] = ProjectCacheManager.shared.loadProjects()
    @State private var terminals: [TerminalItem] = []
    @State private var automations: [AutomationSidecarItem] = []
    @State private var automationEvents: [AutomationEventItem] = []
    @State private var mcpServers: [McpServerState] = CacheManager.shared.loadMcpServers()
    @State private var skills: [SkillInfo] = CacheManager.shared.loadSkills()
    @State private var memories: [MemoryRuleItem] = []

    @State private var isRefreshing: Bool = false
    @State private var runningAutomationIds: Set<String> = []
    @State private var actionToast: String? = nil

    // Sheet destinations
    @State private var showTerminalConsoleSheet: Bool = false
    @State private var activeMcpTabSheet: McpSkillsSheet.Tab? = nil
    @State private var showWorkflowTemplatesSheet: Bool = false
    @State private var showNewConversationSheet: Bool = false
    @State private var activeSwarmCascadeId: String? = nil
    @State private var inspectingAutomation: AutomationSidecarItem? = nil

    // Workspace creation dialogs
    @State private var showCloneAlert: Bool = false
    @State private var cloneRepoSlug: String = ""
    @State private var isCloning: Bool = false
    @State private var showAddWorkspaceAlert: Bool = false
    @State private var localWorkspacePath: String = ""
    @State private var isAddingWorkspace: Bool = false
    @State private var isCreatingWorktree: Bool = false

    public init(
        conversations: [ConversationItem],
        globalBackgroundTasks: [GlobalBackgroundTaskItem],
        onTasksChanged: @escaping ([GlobalBackgroundTaskItem]) -> Void,
        onOpenConversationId: @escaping (String) -> Void,
        onFilterWorkspaceInSessions: @escaping (String) -> Void,
        onCreateSessionForProject: @escaping (ProjectItem) -> Void,
        onStartTemplateSession: @escaping (String) -> Void
    ) {
        self.conversations = conversations
        self.globalBackgroundTasks = globalBackgroundTasks
        self.onTasksChanged = onTasksChanged
        self.onOpenConversationId = onOpenConversationId
        self.onFilterWorkspaceInSessions = onFilterWorkspaceInSessions
        self.onCreateSessionForProject = onCreateSessionForProject
        self.onStartTemplateSession = onStartTemplateSession
    }

    private var activeRunningConversation: ConversationItem? {
        conversations.first(where: { $0.hasRunningSubagents }) ?? conversations.first(where: { $0.status == .running })
    }

    private var readyMcpCount: Int {
        mcpServers.filter(\.isReady).count
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                headerBar

                if let toast = actionToast, !toast.isEmpty {
                    HStack(spacing: 7) {
                        AGLinearIcon(.check, size: 12.5, color: AGPalette.emeraldText(colorScheme), lineWidth: 2.1)
                        Text(toast)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AGPalette.textPrimary(colorScheme))
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .agCard(cornerRadius: 11)
                }

                // Row 1: 2-Column Live Runtime Bento (PTY Terminal + Active Swarm)
                HStack(spacing: 10) {
                    ptyTerminalBentoCard
                    swarmBentoCard
                }

                // Row 2: Workspaces & GitHub PRs
                workspacesCard

                // Row 3: Cron Automations & Workflow Templates
                automationsCard

                // Row 4: 2-Column Capabilities Bento (MCP Hot-Toggles + Skills & Memories)
                HStack(spacing: 10) {
                    mcpQuickCard
                    skillsMemoriesQuickCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 26)
        }
        .refreshable {
            await refreshHubData()
        }
        .task {
            await refreshHubData()
        }
        .sheet(isPresented: $showTerminalConsoleSheet) {
            InteractiveTerminalConsoleSheet(
                defaultCascadeId: activeRunningConversation?.id ?? conversations.first?.id ?? "",
                backgroundTasks: globalBackgroundTasks,
                onOpenAllTasksSheet: {
                    showTerminalConsoleSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        activeMcpTabSheet = .tasks
                    }
                },
                onTerminalsUpdated: { list in
                    self.terminals = list
                }
            )
        }
        .sheet(item: $activeMcpTabSheet) { tab in
            McpSkillsSheet(
                initialTab: tab,
                currentConversationId: activeRunningConversation?.id,
                hasActiveSwarm: activeRunningConversation != nil,
                onSelectConversation: { cid in
                    activeMcpTabSheet = nil
                    onOpenConversationId(cid)
                },
                onTasksChanged: { updated in
                    onTasksChanged(updated)
                },
                onOpenSwarm: {
                    if let cid = (activeRunningConversation ?? conversations.first)?.id {
                        activeMcpTabSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            activeSwarmCascadeId = cid
                        }
                    }
                }
            )
            .onDisappear {
                Task { await refreshHubData() }
            }
        }
        .sheet(isPresented: $showWorkflowTemplatesSheet) {
            WorkflowTemplateSheet { prompt in
                showWorkflowTemplatesSheet = false
                onStartTemplateSession(prompt)
            }
        }
        .sheet(isPresented: $showNewConversationSheet) {
            NewConversationSheet(
                onSelectProject: { project in
                    onCreateSessionForProject(project)
                },
                onCreated: { cid, _ in
                    onOpenConversationId(cid)
                }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { activeSwarmCascadeId != nil },
                set: { if !$0 { activeSwarmCascadeId = nil } }
            )
        ) {
            if let cid = activeSwarmCascadeId {
                SwarmSheet(
                    cascadeId: cid,
                    onSelectConversation: { targetCid in
                        activeSwarmCascadeId = nil
                        onOpenConversationId(targetCid)
                    }
                )
            }
        }
        .sheet(item: $inspectingAutomation) { sidecar in
            NavigationStack {
                AutomationDetailView(
                    sidecar: sidecar,
                    allEvents: automationEvents,
                    onRefresh: {
                        await refreshAutomationsOnly()
                    },
                    onDeleted: {
                        inspectingAutomation = nil
                        Task { await refreshAutomationsOnly() }
                    },
                    onSelectConversation: { cid in
                        inspectingAutomation = nil
                        onOpenConversationId(cid)
                    }
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("克隆 GitHub 仓库", isPresented: $showCloneAlert) {
            TextField("owner/repo 或完整 HTTPS 地址", text: $cloneRepoSlug)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("取消", role: .cancel) { cloneRepoSlug = "" }
            Button("克隆并开启会话") {
                let slug = cloneRepoSlug.trimmingCharacters(in: .whitespacesAndNewlines)
                cloneRepoSlug = ""
                if !slug.isEmpty {
                    Task { await cloneRepo(slug: slug) }
                }
            }
        } message: {
            Text("电脑网关将自动拉取仓库至默认工程目录并关联新会话。")
        }
        .alert("添加本地工作区", isPresented: $showAddWorkspaceAlert) {
            TextField(localWorkspacePlaceholder, text: $localWorkspacePath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("取消", role: .cancel) { localWorkspacePath = "" }
            Button("添加") {
                let path = localWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
                localWorkspacePath = ""
                if !path.isEmpty {
                    Task { await addLocalWorkspace(path: path) }
                }
            }
        } message: {
            Text("输入电脑端本地目录绝对路径以加入工程列表。")
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text("工程与自动化中枢")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))
                Text("仓库 · 终端 · Swarm · Cron · MCP · 记忆库")
                    .font(.system(size: 11.5))
                    .foregroundColor(AGPalette.textSecondary(colorScheme))
            }

            Spacer()

            let liveCount = globalBackgroundTasks.count + terminals.count
            if liveCount > 0 {
                AGBadge("\(liveCount) 运行中", tone: .emerald) {
                    Circle()
                        .fill(AGPalette.emeraldFill(colorScheme))
                        .frame(width: 6, height: 6)
                }
            } else {
                Button {
                    Task { await refreshHubData() }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(AGPalette.cardBackground(colorScheme))
                            .frame(width: 32, height: 32)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(AGPalette.border(colorScheme), lineWidth: 1)
                            )
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            AGLinearIcon(.refresh, size: 14, color: AGPalette.textSecondary(colorScheme), lineWidth: 1.9)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: - Row 1: Live Runtime Bento

    private var ptyTerminalBentoCard: some View {
        let count = terminals.count + globalBackgroundTasks.count
        let previewLine: String = {
            if let task = globalBackgroundTasks.first {
                return "$ \(task.commandLine.isEmpty ? task.displayTitle : task.commandLine)"
            }
            if let term = terminals.first {
                return "$ \(term.command ?? term.displayTitle)"
            }
            return String(localized: "$ 就绪 · 点按开启交互 PTY")
        }()

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showTerminalConsoleSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    AGLinearIcon(
                        .terminal,
                        size: 14,
                        color: Color(red: 0x5C / 255.0, green: 0xE0 / 255.0, blue: 0xA8 / 255.0),
                        lineWidth: 2.0
                    )
                    Text(count > 0 ? String(localized: "实时 PTY 终端 (\(count))") : String(localized: "实时 PTY 终端"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                Text(previewLine)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(red: 0xAF / 255.0, green: 0xB8 / 255.0, blue: 0xC7 / 255.0))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Circle()
                        .fill(count > 0 ? Color(red: 0x2C / 255.0, green: 0xB6 / 255.0, blue: 0x7D / 255.0) : Color.white.opacity(0.35))
                        .frame(width: 5.5, height: 5.5)
                    Text(count > 0 ? String(localized: "在线 · 点按接管输入") : String(localized: "新建远程 Shell ›"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Color(red: 0x5C / 255.0, green: 0xE0 / 255.0, blue: 0xA8 / 255.0))
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0x19 / 255.0, green: 0x1B / 255.0, blue: 0x20 / 255.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(red: 0x2E / 255.0, green: 0x32 / 255.0, blue: 0x3D / 255.0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var swarmBentoCard: some View {
        let targetConv = activeRunningConversation ?? conversations.first
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let cid = targetConv?.id {
                activeSwarmCascadeId = cid
            } else {
                onStartTemplateSession("/teamwork ")
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    SlashCommandIconView(name: "teamwork", icon: "graph_2", size: 13)
                        .foregroundColor(AGPalette.violetText(colorScheme))
                    Text("活跃 Swarm")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AGPalette.violetText(colorScheme))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                Text(targetConv?.title ?? String(localized: "多智能体并发协作"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(targetConv != nil ? String(localized: "概览 · 协作板 · 拓扑 ›") : String(localized: "发起 Swarm 编排 ›"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(AGPalette.textSecondary(colorScheme))
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AGPalette.cardBackground(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AGPalette.violetFill(colorScheme).opacity(colorScheme == .dark ? 0.45 : 0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row 2: Workspaces & PRs

    private var workspacesCard: some View {
        let workspaceProjects = projects.filter(\.isWorkspace)
        let visibleProjects = Array(workspaceProjects.prefix(4))

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                AGLinearIcon(.folder, size: 14.5, color: AGPalette.accentText(colorScheme), lineWidth: 1.95)
                Text("本地工作区与 PR (\(workspaceProjects.count))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))
                Spacer()

                Menu {
                    Button {
                        showCloneAlert = true
                    } label: {
                        Label("克隆 GitHub 仓库", systemImage: "arrow.down.doc")
                    }
                    Button {
                        showAddWorkspaceAlert = true
                    } label: {
                        Label("添加电脑本地目录", systemImage: "folder.badge.plus")
                    }
                    Button {
                        showNewConversationSheet = true
                    } label: {
                        Label("全部工作区与新建会话...", systemImage: "plus.bubble")
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isCloning || isAddingWorkspace || isCreatingWorktree {
                            ProgressView().scaleEffect(0.65)
                        } else {
                            AGLinearIcon(.plus, size: 11, color: AGPalette.accentText(colorScheme), lineWidth: 2.2)
                        }
                        Text("克隆 / 新目录")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AGPalette.accentText(colorScheme))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AGPalette.accentSoft(colorScheme)))
                }
            }

            if visibleProjects.isEmpty {
                Button {
                    showNewConversationSheet = true
                } label: {
                    HStack(spacing: 8) {
                        AGLinearIcon(.folder, size: 14, color: AGPalette.textTertiary(colorScheme))
                        Text("暂未同步本地工程目录，点按添加或克隆仓库")
                            .font(.system(size: 12))
                            .foregroundColor(AGPalette.textSecondary(colorScheme))
                        Spacer()
                        AGLinearIcon(.chevronRight, size: 12, color: AGPalette.textTertiary(colorScheme))
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AGPalette.recessedWell(colorScheme)))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 6) {
                    ForEach(visibleProjects) { project in
                        workspaceRow(for: project)
                    }

                    if workspaceProjects.count > visibleProjects.count {
                        Button {
                            showNewConversationSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("查看全部 \(workspaceProjects.count) 个工作区")
                                    .font(.system(size: 11.5, weight: .semibold))
                                AGLinearIcon(.chevronRight, size: 11, color: AGPalette.accentText(colorScheme), lineWidth: 2.0)
                            }
                            .foregroundColor(AGPalette.accentText(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(13)
        .agCard(cornerRadius: 14)
    }

    @ViewBuilder
    private func workspaceRow(for project: ProjectItem) -> some View {
        let matchedConvs = conversations.filter { $0.workspaceName == project.name || $0.workspaceName == project.displayName }
        let totalSessions = max(project.sessionCount, matchedConvs.count)
        let prItem = matchedConvs.compactMap(\.pullRequest).first
        let branchName = matchedConvs.compactMap(\.currentBranch).first(where: { !$0.isEmpty })

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if totalSessions > 0 {
                onFilterWorkspaceInSessions(project.name)
            } else {
                onCreateSessionForProject(project)
            }
        } label: {
            HStack(spacing: 8) {
                AGLinearIcon(.gitBranch, size: 13, color: AGPalette.textSecondary(colorScheme), lineWidth: 1.9)

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 6) {
                        Text(project.displayName)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(AGPalette.textPrimary(colorScheme))
                            .lineLimit(1)
                        if let branch = branchName {
                            Text("· \(branch)")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundColor(AGPalette.textSecondary(colorScheme))
                                .lineLimit(1)
                        } else if totalSessions > 0 {
                            Text("\(totalSessions) 会话")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AGPalette.textTertiary(colorScheme))
                        }
                    }
                    Text(project.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AGPalette.textTertiary(colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                if let pr = prItem {
                    AGBadge("PR #\(pr.number)", tone: pr.state.lowercased() == "merged" ? .violet : .emerald)
                } else {
                    AGLinearIcon(.chevronRight, size: 12, color: AGPalette.textTertiary(colorScheme), lineWidth: 1.9)
                }
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
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onCreateSessionForProject(project)
            } label: {
                Label("在此工作区开启新会话", systemImage: "plus.message")
            }
            Button {
                onFilterWorkspaceInSessions(project.name)
            } label: {
                Label("在会话页筛选此工作区", systemImage: "line.3.horizontal.decrease.circle")
            }
            Button {
                Task { await createWorktreeSession(for: project) }
            } label: {
                Label("在独立 Worktree 开启会话", systemImage: "arrow.triangle.branch")
            }
        }
    }

    // MARK: - Row 3: Automations & Workflow Templates

    private var automationsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                AGLinearIcon(.clock, size: 14.5, color: AGPalette.accentText(colorScheme), lineWidth: 1.95)
                Text("定时自动化与编排 (\(automations.count))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))
                Spacer()

                Button {
                    showWorkflowTemplatesSheet = true
                } label: {
                    HStack(spacing: 4) {
                        AGLinearIcon(.layers, size: 11, color: AGPalette.textSecondary(colorScheme), lineWidth: 1.9)
                        Text("模板库")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AGPalette.textSecondary(colorScheme))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(Capsule().fill(AGPalette.recessedWell(colorScheme)))
                    .overlay(Capsule().stroke(AGPalette.border(colorScheme), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    activeMcpTabSheet = .automations
                } label: {
                    HStack(spacing: 3) {
                        AGLinearIcon(.plus, size: 10.5, color: AGPalette.accentText(colorScheme), lineWidth: 2.2)
                        Text("管理")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AGPalette.accentText(colorScheme))
                    }
                    .padding(.horizontal, 8.5)
                    .padding(.vertical, 4.5)
                    .background(Capsule().fill(AGPalette.accentSoft(colorScheme)))
                }
                .buttonStyle(.plain)
            }

            if automations.isEmpty {
                Button {
                    activeMcpTabSheet = .automations
                } label: {
                    HStack(spacing: 9) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AGPalette.accentSoft(colorScheme))
                                .frame(width: 28, height: 28)
                            AGLinearIcon(.clock, size: 14, color: AGPalette.accentText(colorScheme), lineWidth: 1.9)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("创建定时巡检或晨报任务")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(AGPalette.textPrimary(colorScheme))
                            Text("支持 Cron 周期调度、一键立即触发与运行日志审计")
                                .font(.system(size: 10.5))
                                .foregroundColor(AGPalette.textSecondary(colorScheme))
                        }
                        Spacer()
                        AGLinearIcon(.chevronRight, size: 12, color: AGPalette.textTertiary(colorScheme))
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AGPalette.recessedWell(colorScheme)))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(automations.prefix(3))) { sidecar in
                        automationRow(for: sidecar)
                    }
                }
            }
        }
        .padding(13)
        .agCard(cornerRadius: 14)
    }

    @ViewBuilder
    private func automationRow(for sidecar: AutomationSidecarItem) -> some View {
        let isBusy = runningAutomationIds.contains(sidecar.id)

        HStack(spacing: 9) {
            Button {
                inspectingAutomation = sidecar
            } label: {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(sidecar.isRunning ? AGPalette.accentSoft(colorScheme) : AGPalette.recessedWell(colorScheme))
                            .frame(width: 28, height: 28)
                        AGLinearIcon(
                            .clock,
                            size: 14,
                            color: sidecar.isRunning ? AGPalette.accentText(colorScheme) : AGPalette.textTertiary(colorScheme),
                            lineWidth: 1.9
                        )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(sidecar.name)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(AGPalette.textPrimary(colorScheme))
                            .lineLimit(1)
                        Text(automationSubtitle(for: sidecar))
                            .font(.system(size: 10.5))
                            .foregroundColor(AGPalette.textSecondary(colorScheme))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await triggerAutomationNow(sidecar) }
            } label: {
                HStack(spacing: 4) {
                    if isBusy {
                        ProgressView().scaleEffect(0.65)
                    } else {
                        AGLinearIcon(.play, size: 10, color: AGPalette.accentText(colorScheme), lineWidth: 2.1)
                    }
                    Text("Run Now")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(AGPalette.accentText(colorScheme))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5.5)
                .background(Capsule().fill(AGPalette.accentSoft(colorScheme)))
                .overlay(
                    Capsule()
                        .stroke(AGPalette.accentFill(colorScheme).opacity(0.28), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7.5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AGPalette.recessedWell(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AGPalette.borderSubtle(colorScheme), lineWidth: 1)
        )
    }

    private func automationSubtitle(for sidecar: AutomationSidecarItem) -> String {
        var parts: [String] = []
        if let cron = sidecar.cronExpression, !cron.isEmpty {
            parts.append(AutomationCronHelper.humanSummary(cron))
        }
        if let last = sidecar.lastRunAt, !last.isEmpty {
            parts.append(String(localized: "上次 \(last)"))
        } else {
            parts.append(sidecar.isRunning ? String(localized: "调度启用中") : String(localized: "已暂停"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Row 4: Capabilities Bento (MCP + Skills/Memories)

    private var mcpQuickCard: some View {
        let totalTools = mcpServers.reduce(0) { $0 + $1.toolCount }
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            activeMcpTabSheet = .mcp
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    AGLinearIcon(.plug, size: 14, color: AGPalette.accentText(colorScheme), lineWidth: 1.95)
                    Text("MCP 热开关")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(AGPalette.textPrimary(colorScheme))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                Text(mcpServers.isEmpty ? String(localized: "查看与热启停服务") : String(localized: "\(readyMcpCount) 已启用 · \(totalTools) 工具"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(readyMcpCount > 0 ? AGPalette.emeraldText(colorScheme) : AGPalette.textSecondary(colorScheme))
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .agCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    private var skillsMemoriesQuickCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            activeMcpTabSheet = .skills
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    AGLinearIcon(.cpu, size: 14, color: AGPalette.accentText(colorScheme), lineWidth: 1.95)
                    Text("技能与记忆库")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(AGPalette.textPrimary(colorScheme))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 3) {
                    Text("\(skills.count) 技能 · \(memories.count) 记忆")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AGPalette.textSecondary(colorScheme))
                        .lineLimit(1)
                    AGLinearIcon(.chevronRight, size: 10.5, color: AGPalette.textTertiary(colorScheme), lineWidth: 2.0)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .agCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                activeMcpTabSheet = .skills
            } label: {
                Label("管理技能与 Agent 记忆库", systemImage: "brain")
            }
            Button {
                activeMcpTabSheet = .plugins
            } label: {
                Label("管理插件与账号授权", systemImage: "puzzlepiece.extension")
            }
        }
    }

    // MARK: - Data & Actions

    private var localWorkspacePlaceholder: String {
        if settings.gatewayPlatform == "windows" {
            return #"C:\Users\...\project"#
        }
        return String(localized: "/Users/... 或 ~/Projects/...")
    }

    private func refreshHubData() async {
        guard let url = settings.serverURL else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let pFetch = try? APIClient.shared.fetchProjects(baseURL: url)
        async let tFetch = try? APIClient.shared.listTerminals(baseURL: url)
        async let bgFetch = try? APIClient.shared.fetchGlobalBackgroundTasks(baseURL: url)
        async let aFetch = try? APIClient.shared.fetchAutomations(baseURL: url)
        async let mFetch = try? APIClient.shared.fetchMcpServerStates(baseURL: url)
        async let sFetch = try? APIClient.shared.fetchAllSkills(baseURL: url)
        async let memFetch = try? APIClient.shared.fetchMemories(baseURL: url)

        let (pRes, tRes, bgRes, aRes, mRes, sRes, memRes) = await (pFetch, tFetch, bgFetch, aFetch, mFetch, sFetch, memFetch)

        if let pRes, !pRes.isEmpty {
            self.projects = pRes
            ProjectCacheManager.shared.saveProjects(pRes)
        }
        if let tRes {
            self.terminals = tRes
        }
        if let bgRes {
            onTasksChanged(bgRes)
        }
        if let aRes {
            self.automations = aRes.automations
            self.automationEvents = aRes.events
        }
        if let mRes {
            self.mcpServers = mRes
            CacheManager.shared.saveMcpServers(mRes)
        }
        if let sRes {
            self.skills = sRes
            CacheManager.shared.saveSkills(sRes)
        }
        if let memRes {
            self.memories = memRes
        }
    }

    private func refreshAutomationsOnly() async {
        guard let url = settings.serverURL else { return }
        if let aRes = try? await APIClient.shared.fetchAutomations(baseURL: url) {
            self.automations = aRes.automations
            self.automationEvents = aRes.events
        }
    }

    private func triggerAutomationNow(_ sidecar: AutomationSidecarItem) async {
        guard let url = settings.serverURL else { return }
        runningAutomationIds.insert(sidecar.id)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        defer { runningAutomationIds.remove(sidecar.id) }

        do {
            try await APIClient.shared.manageAutomation(action: "run_now", sidecarId: sidecar.id, baseURL: url)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showToast(String(localized: "已触发「\(sidecar.name)」立即执行"))
            await refreshAutomationsOnly()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func cloneRepo(slug: String) async {
        guard let url = settings.gatewayURL, !isCloning else { return }
        isCloning = true
        defer { isCloning = false }

        do {
            let resp = try await APIClient.shared.cloneGitHubRepo(repoSlug: slug, startSession: true, baseURL: url)
            await refreshHubData()
            if let cid = resp.cascadeId, !cid.isEmpty {
                onOpenConversationId(cid)
            } else if let err = resp.error, !err.isEmpty {
                showToast(err)
            }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func addLocalWorkspace(path: String) async {
        guard let url = settings.gatewayURL, !isAddingWorkspace else { return }
        isAddingWorkspace = true
        defer { isAddingWorkspace = false }

        do {
            let resp = try await APIClient.shared.createProjectWorkspace(path: path, startSession: false, baseURL: url)
            if resp.ok == false {
                showToast(resp.error ?? String(localized: "添加目录失败"))
                return
            }
            await refreshHubData()
            showToast(String(localized: "已添加工作区"))
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func createWorktreeSession(for project: ProjectItem) async {
        guard let url = settings.gatewayURL, !isCreatingWorktree else { return }
        let wsPath = project.path.isEmpty ? project.uri : project.path
        let repoUri = project.uri.isEmpty ? (wsPath.hasPrefix("/") ? "file://\(wsPath)" : wsPath) : project.uri
        isCreatingWorktree = true
        defer { isCreatingWorktree = false }

        do {
            let resp = try await APIClient.shared.createWorktreeSession(
                repoUri: repoUri,
                workspacePath: wsPath,
                startSession: true,
                baseURL: url
            )
            if let cid = resp.cascadeId, !cid.isEmpty {
                onOpenConversationId(cid)
            } else if let err = resp.error, !err.isEmpty {
                showToast(err)
            }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            actionToast = text
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if actionToast == text {
                withAnimation(.easeInOut(duration: 0.2)) {
                    actionToast = nil
                }
            }
        }
    }
}

// MARK: - Full Interactive PTY Terminal Console Sheet

private struct InteractiveTerminalConsoleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let defaultCascadeId: String
    let backgroundTasks: [GlobalBackgroundTaskItem]
    let onOpenAllTasksSheet: () -> Void
    let onTerminalsUpdated: ([TerminalItem]) -> Void

    @State private var session = TerminalStreamSession()
    @State private var commandInput: String = ""
    @State private var isCreating: Bool = false
    @State private var isClosing: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Top terminal tab bar + Create / Close controls
                HStack(spacing: 8) {
                    if session.terminals.isEmpty {
                        Text("暂无活动 PTY 终端")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(AGPalette.textSecondary(colorScheme))
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(session.terminals) { term in
                                    let selected = term.effectiveId == session.selectedTerminalId
                                    Button {
                                        session.connect(terminalId: term.effectiveId)
                                    } label: {
                                        HStack(spacing: 5) {
                                            AGLinearIcon(
                                                .terminal,
                                                size: 11.5,
                                                color: selected ? .white : AGPalette.textSecondary(colorScheme),
                                                lineWidth: 2.0
                                            )
                                            Text(term.displayTitle)
                                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                                .lineLimit(1)
                                        }
                                        .foregroundColor(selected ? .white : AGPalette.textPrimary(colorScheme))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(selected ? AGPalette.accentFill(colorScheme) : AGPalette.recessedWell(colorScheme))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Spacer()

                    if !session.selectedTerminalId.isEmpty {
                        Button {
                            Task { await closeSelectedTerminal() }
                        } label: {
                            Text("关闭")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(AGPalette.roseText(colorScheme))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5.5)
                                .background(Capsule().fill(AGPalette.roseSoft(colorScheme)))
                        }
                        .buttonStyle(.plain)
                        .disabled(isClosing)
                    }

                    Button {
                        Task { await createNewTerminal() }
                    } label: {
                        HStack(spacing: 4) {
                            if isCreating {
                                ProgressView().scaleEffect(0.65)
                            } else {
                                AGLinearIcon(.plus, size: 11, color: .white, lineWidth: 2.2)
                            }
                            Text("新终端")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(AGPalette.accentFill(colorScheme)))
                    }
                    .buttonStyle(.plain)
                    .disabled(isCreating)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Dark PTY screen
                ScrollView {
                    Text(terminalScreenText)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(Color(red: 0xEE / 255.0, green: 0xF2 / 255.0, blue: 0xF6 / 255.0))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0x12 / 255.0, green: 0x13 / 255.0, blue: 0x17 / 255.0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(red: 0x2E / 255.0, green: 0x32 / 255.0, blue: 0x3D / 255.0), lineWidth: 1)
                )
                .padding(.horizontal, 16)

                // Quick control keys + background tasks shortcut
                HStack(spacing: 6) {
                    quickKeyButton("Ctrl+C", payload: "\u{0003}")
                    quickKeyButton("Enter", payload: "\n")
                    quickKeyButton("y", payload: "y\n")
                    quickKeyButton("n", payload: "n\n")
                    quickKeyButton("clear", payload: "clear\n")

                    Spacer()

                    if !backgroundTasks.isEmpty {
                        Button(action: onOpenAllTasksSheet) {
                            AGBadge("后台任务 (\(backgroundTasks.count)) ›", tone: .accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                // Command input bar
                HStack(spacing: 8) {
                    TextField("输入终端命令并回车发送...", text: $commandInput)
                        .font(.system(size: 13, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AGPalette.recessedWell(colorScheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AGPalette.border(colorScheme), lineWidth: 1)
                        )
                        .onSubmit { sendCommandLine() }

                    Button(action: sendCommandLine) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AGPalette.accentFill(colorScheme))
                                .frame(width: 38, height: 38)
                            AGLinearIcon(.arrowUp, size: 15, color: .white, lineWidth: 2.2)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(session.selectedTerminalId.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .background(AGPageBackgroundView())
            .navigationTitle("实时 PTY 交互终端")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                await session.refreshTerminals()
                onTerminalsUpdated(session.terminals)
            }
            .onDisappear {
                session.disconnect()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var terminalScreenText: String {
        if !session.outputText.isEmpty {
            return session.outputText
        }
        if session.terminals.isEmpty {
            return String(localized: "$ 点击右上角「+ 新终端」即可在电脑网关创建远程交互式 PTY 会话。")
        }
        return String(localized: "$ 已连接终端，等待输出或直接输入命令...")
    }

    private func quickKeyButton(_ title: String, payload: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            session.sendInput(payload, cascadeId: defaultCascadeId)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(AGPalette.textPrimary(colorScheme))
                .padding(.horizontal, 8.5)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AGPalette.cardBackground(colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(AGPalette.border(colorScheme), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(session.selectedTerminalId.isEmpty)
    }

    private func sendCommandLine() {
        let cmd = commandInput
        commandInput = ""
        session.sendInput(cmd + "\n", cascadeId: defaultCascadeId)
    }

    private func createNewTerminal() async {
        guard let url = AppSettings.shared.gatewayURL else { return }
        isCreating = true
        defer { isCreating = false }
        if let created = try? await APIClient.shared.createTerminal(baseURL: url) {
            await session.refreshTerminals()
            if !created.effectiveId.isEmpty {
                session.connect(terminalId: created.effectiveId)
            }
            onTerminalsUpdated(session.terminals)
        }
    }

    private func closeSelectedTerminal() async {
        let tid = session.selectedTerminalId
        guard !tid.isEmpty, let url = AppSettings.shared.gatewayURL else { return }
        isClosing = true
        defer { isClosing = false }
        session.disconnect()
        _ = try? await APIClient.shared.closeTerminal(terminalId: tid, baseURL: url)
        session.selectedTerminalId = ""
        await session.refreshTerminals()
        onTerminalsUpdated(session.terminals)
    }
}

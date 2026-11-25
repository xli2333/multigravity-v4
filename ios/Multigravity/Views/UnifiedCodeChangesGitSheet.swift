import SwiftUI

/// Unified v4.0 single-sheet Code Review + Git Commit & Push workflow (`[⑂ +X -Y]`).
/// Eliminates jumping between two separate modals (`Changes` vs `Commit`) by pairing
/// inline low-glare syntax Diff inspection, full-file Diff viewer, branch switching,
/// file staging/discarding, and 1-tap Commit & Push in one continuous loop.
public struct UnifiedCodeChangesGitSheet: View {
    @Bindable var viewModel: ChatViewModel
    let onDelegateToAgent: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    @State private var uncheckedPaths: Set<String> = []
    @State private var expandedDiffIds: Set<String> = []
    @State private var viewingFullDiffFile: RevertPreviewFile? = nil
    @State private var commitMessage: String = ""
    @State private var messageEdited: Bool = false

    @State private var availableBranches: [String] = []
    @State private var showCreateBranchAlert: Bool = false
    @State private var newBranchName: String = ""
    @State private var fileToDiscard: GitFileStatus? = nil
    @State private var isMutatingGit: Bool = false
    @State private var showPushConfirm: Bool = false
    @State private var gitErrorMessage: String? = nil

    public init(viewModel: ChatViewModel, onDelegateToAgent: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDelegateToAgent = onDelegateToAgent
    }

    private var changesData: CascadeChangesResponse? {
        viewModel.changesSheet?.data
    }

    private var gitState: GitSheetState? {
        viewModel.gitSheet
    }

    private var gitStatus: GitStatusResponse? {
        gitState?.status
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let status = gitStatus {
                            branchSummaryCard(status)

                            if let prs = status.pullRequests, !prs.isEmpty {
                                pullRequestsSection(prs)
                            }
                        }

                        if let result = gitState?.result, result.committed {
                            committedSuccessCard(result)
                        } else {
                            unifiedFilesSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                }

                if let status = gitStatus, !status.clean, gitState?.result?.committed != true {
                    commitComposerBar(status)
                }
            }
            .background(AGPageBackgroundView())
            .navigationTitle("代码变更与提交")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if GatewayCompatStore.shared.isAvailable(GatewayFeature.changes) {
                            viewModel.openChangesSheet()
                        }
                        viewModel.refreshGitStatus()
                    } label: {
                        AGLinearIcon(.refresh, size: 15, color: AGPalette.textSecondary(colorScheme), lineWidth: 1.95)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await loadBranches()
            if let st = gitStatus {
                refreshCommitSuggestion(st)
                expandFirstDiffIfNeeded()
            }
        }
        .onChange(of: gitStatus?.files ?? []) { _, _ in
            if let st = gitStatus {
                refreshCommitSuggestion(st)
            }
        }
        .onChange(of: changesData?.files ?? []) { _, _ in
            expandFirstDiffIfNeeded()
        }
        .onChange(of: uncheckedPaths) { _, _ in
            if let st = gitStatus {
                refreshCommitSuggestion(st)
            }
        }
        .sheet(item: $viewingFullDiffFile) { file in
            DiffViewerSheet(file: file)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("新建并切换分支", isPresented: $showCreateBranchAlert) {
            TextField("输入新分支名（如 feat/ui-v4）", text: $newBranchName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("取消", role: .cancel) { newBranchName = "" }
            Button("创建并切换") {
                let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
                newBranchName = ""
                if !name.isEmpty {
                    checkoutBranch(name, create: true)
                }
            }
        }
        .alert("确定丢弃该文件改动？", isPresented: Binding(
            get: { fileToDiscard != nil },
            set: { if !$0 { fileToDiscard = nil } }
        )) {
            Button("取消", role: .cancel) { fileToDiscard = nil }
            Button("丢弃改动", role: .destructive) {
                if let file = fileToDiscard {
                    discardFile(file)
                }
                fileToDiscard = nil
            }
        } message: {
            Text(fileToDiscard?.path ?? "")
        }
        .confirmationDialog(
            "确认提交并推送远端？",
            isPresented: $showPushConfirm,
            titleVisibility: .visible
        ) {
            if let status = gitStatus {
                let selected = status.files.map(\.path).filter { !uncheckedPaths.contains($0) }
                let pathsArg = selected.count == status.files.count ? [] : selected
                Button("确认提交并推送") {
                    viewModel.commitGit(message: commitMessage, paths: pathsArg, push: true)
                }
                Button("仅本地提交") {
                    viewModel.commitGit(message: commitMessage, paths: pathsArg, push: false)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let status = gitStatus {
                let selectedCount = status.files.filter { !uncheckedPaths.contains($0.path) }.count
                Text("将提交 \(selectedCount) 个文件并推送至分支 \(status.branch) 远程仓库。")
            }
        }
        .alert("Git 操作失败", isPresented: Binding(
            get: { gitErrorMessage != nil },
            set: { if !$0 { gitErrorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { gitErrorMessage = nil }
        } message: {
            Text(gitErrorMessage ?? "")
        }
    }

    // MARK: - Top Branch Summary

    private func branchSummaryCard(_ status: GitStatusResponse) -> some View {
        let repoLabel: String = {
            if let t = status.githubTarget, !t.owner.isEmpty, !t.repo.isEmpty {
                return "\(t.owner)/\(t.repo)"
            }
            return status.repoName
        }()

        return HStack(spacing: 8) {
            AGLinearIcon(.gitBranch, size: 14, color: AGPalette.accentText(colorScheme), lineWidth: 2.0)

            Menu {
                if availableBranches.isEmpty {
                    Text("暂无可选分支")
                } else {
                    ForEach(availableBranches, id: \.self) { b in
                        Button {
                            checkoutBranch(b, create: false)
                        } label: {
                            Label(b, systemImage: b == status.branch ? "checkmark" : "arrow.triangle.branch")
                        }
                    }
                }
                Divider()
                Button {
                    showCreateBranchAlert = true
                } label: {
                    Label("新建分支...", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 4) {
                    Text(status.branch)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                    AGLinearIcon(.chevronDown, size: 10, color: AGPalette.accentText(colorScheme), lineWidth: 2.1)
                }
                .foregroundColor(AGPalette.accentText(colorScheme))
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(Capsule().fill(AGPalette.accentSoft(colorScheme)))
            }
            .disabled(isMutatingGit)

            Text(repoLabel)
                .font(.system(size: 11.5))
                .foregroundColor(AGPalette.textSecondary(colorScheme))
                .lineLimit(1)

            Spacer(minLength: 4)

            if let c = changesData, (c.additions > 0 || c.deletions > 0) {
                HStack(spacing: 5) {
                    Text("+\(c.additions)")
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(AGPalette.emeraldText(colorScheme))
                    Text("-\(c.deletions)")
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(AGPalette.roseText(colorScheme))
                }
            } else if status.ahead > 0 {
                AGBadge("↑\(status.ahead) 待推送", tone: .amber)
            }
        }
        .padding(12)
        .agCard(cornerRadius: 13)
    }

    private func pullRequestsSection(_ prs: [GitPullRequestItem]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(prs) { pr in
                Button {
                    if let url = URL(string: pr.url) { openURL(url) }
                } label: {
                    HStack(spacing: 8) {
                        AGBadge(pr.state.uppercased(), tone: pr.state.uppercased() == "MERGED" ? .violet : .emerald)
                        if pr.number > 0 {
                            Text("#\(pr.number)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(AGPalette.textSecondary(colorScheme))
                        }
                        Text(pr.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(AGPalette.textPrimary(colorScheme))
                            .lineLimit(1)
                        Spacer()
                        AGLinearIcon(.chevronRight, size: 11.5, color: AGPalette.textTertiary(colorScheme))
                    }
                    .padding(11)
                    .agCard(cornerRadius: 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Unified Files + Inline Syntax Diff

    @ViewBuilder
    private var unifiedFilesSection: some View {
        let isLoading = (viewModel.changesSheet?.isLoading == true) && (gitState?.isLoading == true && gitStatus == nil)
        if isLoading {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在汇总代码差异与 Git 工作区状态...")
                    .font(.system(size: 12.5))
                    .foregroundColor(AGPalette.textSecondary(colorScheme))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
        } else {
            let gitFiles = gitStatus?.files ?? []
            let diffFiles = changesData?.files ?? []

            if !gitFiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("工作区待提交文件 (\(gitFiles.count))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AGPalette.textSecondary(colorScheme))
                        Spacer()
                        Text("点按展开 Diff · 勾选纳入提交")
                            .font(.system(size: 10.5))
                            .foregroundColor(AGPalette.textTertiary(colorScheme))
                    }

                    ForEach(gitFiles) { gFile in
                        let matchedDiff = matchPreviewFile(for: gFile.path, in: diffFiles)
                        gitAndDiffCard(gitFile: gFile, previewFile: matchedDiff)
                    }
                }
            } else if !diffFiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("本会话累计代码变更 (\(diffFiles.count))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AGPalette.textSecondary(colorScheme))

                    ForEach(diffFiles) { dFile in
                        sessionOnlyDiffCard(previewFile: dFile)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    AGLinearIcon(.check, size: 28, color: AGPalette.emeraldText(colorScheme), lineWidth: 2.0)
                    Text("工作区干净，暂无未提交改动")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(AGPalette.textPrimary(colorScheme))

                    if let status = gitStatus, status.ahead > 0, status.upstream != nil {
                        Button {
                            viewModel.retryGitPush()
                        } label: {
                            Text(gitState?.isWorking == true ? "正在推送..." : "推送 \(status.ahead) 个本地提交到远端")
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(Capsule().fill(AGPalette.accentFill(colorScheme)))
                        }
                        .buttonStyle(.plain)
                        .disabled(gitState?.isWorking == true)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .agCard(cornerRadius: 14)
            }
        }
    }

    private func matchPreviewFile(for gitPath: String, in diffFiles: [RevertPreviewFile]) -> RevertPreviewFile? {
        let baseName = (gitPath as NSString).lastPathComponent
        return diffFiles.first(where: { $0.fileUri.hasSuffix(gitPath) })
            ?? diffFiles.first(where: { $0.fileName == baseName })
    }

    @ViewBuilder
    private func gitAndDiffCard(gitFile: GitFileStatus, previewFile: RevertPreviewFile?) -> some View {
        let isChecked = !uncheckedPaths.contains(gitFile.path)
        let isExpanded = expandedDiffIds.contains(gitFile.path)
        let fileName = (gitFile.path as NSString).lastPathComponent
        let dirName = (gitFile.path as NSString).deletingLastPathComponent

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                // Stage checkbox
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if isChecked {
                        uncheckedPaths.insert(gitFile.path)
                    } else {
                        uncheckedPaths.remove(gitFile.path)
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isChecked ? AGPalette.accentFill(colorScheme) : Color.clear)
                            .frame(width: 18, height: 18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(isChecked ? AGPalette.accentFill(colorScheme) : AGPalette.border(colorScheme), lineWidth: 1.4)
                            )
                        if isChecked {
                            AGLinearIcon(.check, size: 11, color: .white, lineWidth: 2.3)
                        }
                    }
                }
                .buttonStyle(.plain)

                statusBadge(for: gitFile.status)

                Button {
                    if previewFile != nil {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if isExpanded {
                                expandedDiffIds.remove(gitFile.path)
                            } else {
                                expandedDiffIds.insert(gitFile.path)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1.5) {
                            Text(fileName)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(AGPalette.textPrimary(colorScheme))
                                .lineLimit(1)
                            if !dirName.isEmpty {
                                Text(dirName)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(AGPalette.textTertiary(colorScheme))
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                        }

                        Spacer(minLength: 4)

                        if let pf = previewFile {
                            HStack(spacing: 4) {
                                if pf.additions > 0 {
                                    Text("+\(pf.additions)")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(AGPalette.emeraldText(colorScheme))
                                }
                                if pf.deletions > 0 {
                                    Text("-\(pf.deletions)")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(AGPalette.roseText(colorScheme))
                                }
                            }
                            AGLinearIcon(isExpanded ? .chevronUp : .chevronDown, size: 12, color: AGPalette.textTertiary(colorScheme))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Discard single file changes
                Button {
                    fileToDiscard = gitFile
                } label: {
                    AGLinearIcon(.trash, size: 13.5, color: AGPalette.roseText(colorScheme).opacity(0.85), lineWidth: 1.85)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .disabled(isMutatingGit)
                .accessibilityLabel("丢弃 \(fileName) 改动")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if isExpanded, let pf = previewFile {
                inlineDiffPreviewBlock(pf)
            }
        }
        .agCard(cornerRadius: 13)
    }

    @ViewBuilder
    private func sessionOnlyDiffCard(previewFile pf: RevertPreviewFile) -> some View {
        let isExpanded = expandedDiffIds.contains(pf.id)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded {
                        expandedDiffIds.remove(pf.id)
                    } else {
                        expandedDiffIds.insert(pf.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    AGLinearIcon(.code, size: 13.5, color: AGPalette.accentText(colorScheme), lineWidth: 1.95)
                    Text(pf.fileName)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(AGPalette.textPrimary(colorScheme))
                        .lineLimit(1)
                    Spacer()
                    if pf.additions > 0 {
                        Text("+\(pf.additions)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(AGPalette.emeraldText(colorScheme))
                    }
                    if pf.deletions > 0 {
                        Text("-\(pf.deletions)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(AGPalette.roseText(colorScheme))
                    }
                    AGLinearIcon(isExpanded ? .chevronUp : .chevronDown, size: 12, color: AGPalette.textTertiary(colorScheme))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                inlineDiffPreviewBlock(pf)
            }
        }
        .agCard(cornerRadius: 13)
    }

    @ViewBuilder
    private func inlineDiffPreviewBlock(_ file: RevertPreviewFile) -> some View {
        let changedSample = Array(file.diffLines.filter { $0.type != "UNCHANGED" }.prefix(14))
        let displayLines = changedSample.isEmpty ? Array(file.diffLines.prefix(10)) : changedSample

        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(AGPalette.borderSubtle(colorScheme))
                .frame(height: 1)

            if displayLines.isEmpty {
                Text("无行级差异预览")
                    .font(.system(size: 11))
                    .foregroundColor(AGPalette.textTertiary(colorScheme))
                    .padding(10)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displayLines.enumerated()), id: \.offset) { _, line in
                        let isAdd = line.type == "INSERT"
                        let isDel = line.type == "DELETE"
                        let prefix = isAdd ? "+" : (isDel ? "-" : " ")
                        let fg: Color = isAdd
                            ? AGPalette.emeraldText(colorScheme)
                            : (isDel ? AGPalette.roseText(colorScheme) : AGPalette.textSecondary(colorScheme))
                        let bg: Color = isAdd
                            ? AGPalette.emeraldSoft(colorScheme)
                            : (isDel ? AGPalette.roseSoft(colorScheme) : Color.clear)

                        Text("\(prefix) \(line.text)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(fg)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 2.5)
                            .background(bg)
                    }
                }
                .background(AGPalette.recessedWell(colorScheme))
            }

            HStack {
                Text("共 \(file.diffLines.count) 行上下文")
                    .font(.system(size: 10.5))
                    .foregroundColor(AGPalette.textTertiary(colorScheme))
                Spacer()
                Button {
                    viewingFullDiffFile = file
                } label: {
                    HStack(spacing: 3) {
                        Text("全屏逐行比对")
                            .font(.system(size: 11, weight: .bold))
                        AGLinearIcon(.chevronRight, size: 10.5, color: AGPalette.accentText(colorScheme), lineWidth: 2.0)
                    }
                    .foregroundColor(AGPalette.accentText(colorScheme))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AGPalette.cardBackground(colorScheme))
        }
    }

    private func statusBadge(for rawStatus: String) -> some View {
        let (code, tone): (String, AGSemanticTone) = {
            switch rawStatus {
            case "ADDED", "UNTRACKED": return ("A", .emerald)
            case "DELETED", "CONFLICT": return ("D", .rose)
            case "RENAMED": return ("R", .accent)
            default: return ("M", .amber)
            }
        }()
        return AGBadge(code, tone: tone)
    }

    // MARK: - Bottom Commit & Push Composer

    private func commitComposerBar(_ status: GitStatusResponse) -> some View {
        let selected = status.files.map(\.path).filter { !uncheckedPaths.contains($0) }
        let pathsArg = selected.count == status.files.count ? [] : selected
        let isWorking = gitState?.isWorking == true
        let canCommit = !isWorking
            && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selected.isEmpty

        return VStack(alignment: .leading, spacing: 9) {
            Rectangle()
                .fill(AGPalette.border(colorScheme))
                .frame(height: 0.75)

            VStack(alignment: .leading, spacing: 8) {
                if let err = gitState?.actionError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 11.5))
                        .foregroundColor(AGPalette.roseText(colorScheme))
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    TextField(
                        "输入 Commit 提交说明...",
                        text: Binding(
                            get: { commitMessage },
                            set: { commitMessage = $0; messageEdited = true }
                        ),
                        axis: .vertical
                    )
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1...3)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8.5)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AGPalette.recessedWell(colorScheme)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AGPalette.border(colorScheme), lineWidth: 1))

                    Button {
                        dismiss()
                        onDelegateToAgent()
                    } label: {
                        VStack(spacing: 2) {
                            AGLinearIcon(.sparkles, size: 13, color: AGPalette.accentText(colorScheme), lineWidth: 1.95)
                            Text("AI 提交")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(AGPalette.accentText(colorScheme))
                        }
                        .frame(width: 54, height: 38)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AGPalette.accentSoft(colorScheme)))
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                }

                HStack(spacing: 8) {
                    Button {
                        viewModel.commitGit(message: commitMessage, paths: pathsArg, push: false)
                    } label: {
                        Text("仅提交 (\(selected.count))")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(canCommit ? AGPalette.textPrimary(colorScheme) : AGPalette.textTertiary(colorScheme))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AGPalette.recessedWell(colorScheme)))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AGPalette.border(colorScheme), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCommit)

                    Button {
                        showPushConfirm = true
                    } label: {
                        HStack(spacing: 5) {
                            if isWorking {
                                ProgressView().scaleEffect(0.75).tint(.white)
                            } else {
                                AGLinearIcon(.arrowUp, size: 13.5, color: .white, lineWidth: 2.2)
                            }
                            Text(isWorking ? "处理中..." : "提交并推送远端")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(canCommit ? AGPalette.accentFill(colorScheme) : AGPalette.border(colorScheme))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCommit)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(AGPalette.cardBackground(colorScheme))
    }

    private func committedSuccessCard(_ result: GitCommitResponse) -> some View {
        VStack(spacing: 12) {
            AGLinearIcon(.check, size: 28, color: AGPalette.emeraldText(colorScheme), lineWidth: 2.1)
            Text(result.pushed ? "代码已提交并推送至远端" : "代码已在本地完成提交")
                .font(.system(size: 14.5, weight: .bold))
                .foregroundColor(AGPalette.textPrimary(colorScheme))
            if let sha = result.commitId, !sha.isEmpty {
                Text(sha)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(AGPalette.textSecondary(colorScheme))
            }
            if let pushErr = result.pushError ?? gitState?.actionError, !pushErr.isEmpty {
                Text("推送异常：\(pushErr)")
                    .font(.system(size: 12))
                    .foregroundColor(AGPalette.amberText(colorScheme))
                    .multilineTextAlignment(.center)
                Button("重试推送") {
                    viewModel.retryGitPush()
                }
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(AGPalette.accentText(colorScheme))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .agCard(cornerRadius: 14)
    }

    // MARK: - Helpers

    private func expandFirstDiffIfNeeded() {
        guard expandedDiffIds.isEmpty else { return }
        if let firstGit = gitStatus?.files.first,
           let diffFiles = changesData?.files,
           matchPreviewFile(for: firstGit.path, in: diffFiles) != nil {
            expandedDiffIds.insert(firstGit.path)
        } else if let firstDiff = changesData?.files.first {
            expandedDiffIds.insert(firstDiff.id)
        }
    }

    private func refreshCommitSuggestion(_ status: GitStatusResponse) {
        guard !messageEdited else { return }
        commitMessage = suggestCommitMessage(for: status.files.filter { !uncheckedPaths.contains($0.path) })
    }

    private func loadBranches() async {
        guard let gwUrl = AppSettings.shared.gatewayURL, !viewModel.cascadeId.isEmpty else { return }
        if let resp = try? await APIClient.shared.gitListBranches(cascadeId: viewModel.cascadeId, baseURL: gwUrl) {
            availableBranches = resp.branches ?? []
        }
    }

    private func checkoutBranch(_ branch: String, create: Bool) {
        guard let gwUrl = AppSettings.shared.gatewayURL, !viewModel.cascadeId.isEmpty else { return }
        isMutatingGit = true
        Task {
            defer { isMutatingGit = false }
            do {
                _ = try await APIClient.shared.gitCheckoutBranch(
                    cascadeId: viewModel.cascadeId,
                    branch: branch,
                    create: create,
                    baseURL: gwUrl
                )
                await loadBranches()
                viewModel.refreshGitStatus()
            } catch {
                gitErrorMessage = error.localizedDescription
            }
        }
    }

    private func discardFile(_ file: GitFileStatus) {
        guard let gwUrl = AppSettings.shared.gatewayURL, !viewModel.cascadeId.isEmpty else { return }
        isMutatingGit = true
        Task {
            defer { isMutatingGit = false }
            do {
                try await APIClient.shared.gitDiscardFile(
                    cascadeId: viewModel.cascadeId,
                    path: file.path,
                    baseURL: gwUrl
                )
                viewModel.refreshGitStatus()
            } catch {
                gitErrorMessage = error.localizedDescription
            }
        }
    }
}

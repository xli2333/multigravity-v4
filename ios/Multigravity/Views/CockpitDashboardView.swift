import SwiftUI

/// Tab 3 (`驾驶舱`): v4.0 Precision Telemetry Cockpit Dashboard.
/// Replaces flat horizontal bars with side-by-side 240° Dual-Arc Speedometer Gauges
/// aligned with official Google Gemini & Anthropic Claude vector marks, Argon/Streaming
/// telemetry strip, Standby Account Hot-Swap Deck, and same-screen Token Cost + 3-Chart History.
public struct CockpitDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @AppStorage("cockpit_email_masked") private var isMasked: Bool = false

    @Binding public var quotaResponse: CockpitQuotaResponse?
    public let tokenHistory: TokenHistoryResponse?
    public let isLoadingTokenHistory: Bool
    public let onLoadTokenHistory: ((Bool) async -> Void)?
    public let onSwitch: ((String) async throws -> Void)?
    public let onRefresh: (() async throws -> Void)?
    public let onAppearFetch: (() async -> Void)?
    public let enableSwitchButton: Bool
    public let linkMonitor: ConversationEventsClient?

    @State private var settings = AppSettings.shared
    @State private var switchingAccountId: String? = nil
    @State private var pendingSwitch: CockpitAccountQuota? = nil
    @State private var showSwitchConfirm: Bool = false
    @State private var isRefreshing: Bool = false
    @State private var isSavingPoster: Bool = false
    @State private var showSharePosterSheet: Bool = false
    @State private var showAllModelsSheet: Bool = false
    @State private var paceDetailItem: WeeklyPaceDetailItem? = nil
    @State private var selectedHeatmapDate: String? = nil
    @State private var expandedInspectorModel: String? = nil
    @State private var selectedChartType: TokenHistoryChartType
    @State private var hasInitializedChartType: Bool
    @State private var isCockpitGuideExpanded: Bool = false
    @State private var copiedFeedbackKey: String? = nil
    @State private var errorMessage: String? = nil

    public init(
        quotaResponse: Binding<CockpitQuotaResponse?>,
        tokenHistory: TokenHistoryResponse? = nil,
        isLoadingTokenHistory: Bool = false,
        onLoadTokenHistory: ((Bool) async -> Void)? = nil,
        onSwitch: ((String) async throws -> Void)? = nil,
        onRefresh: (() async throws -> Void)? = nil,
        onAppearFetch: (() async -> Void)? = nil,
        enableSwitchButton: Bool = true,
        linkMonitor: ConversationEventsClient? = nil
    ) {
        self._quotaResponse = quotaResponse
        self.tokenHistory = tokenHistory
        self.isLoadingTokenHistory = isLoadingTokenHistory
        self.onLoadTokenHistory = onLoadTokenHistory
        self.onSwitch = onSwitch
        self.onRefresh = onRefresh
        self.onAppearFetch = onAppearFetch
        self.enableSwitchButton = enableSwitchButton
        self.linkMonitor = linkMonitor

        if let history = tokenHistory {
            let resolved = TokenHistoryChartType.resolveDefault(
                savedRawValue: AppSettings.shared.tokenHistoryChartType,
                activeDays: history.summary.activeDays
            )
            self._selectedChartType = State(initialValue: resolved)
            self._hasInitializedChartType = State(initialValue: true)
        } else {
            let fallback = TokenHistoryChartType(rawValue: AppSettings.shared.tokenHistoryChartType) ?? .dailyBars
            self._selectedChartType = State(initialValue: fallback)
            self._hasInitializedChartType = State(initialValue: false)
        }
    }

    private var currentAccount: CockpitAccountQuota? {
        quotaResponse?.currentAccount ?? quotaResponse?.accounts.first(where: \.isCurrent) ?? quotaResponse?.accounts.first
    }

    private var standbyAccounts: [CockpitAccountQuota] {
        guard let all = quotaResponse?.accounts else { return [] }
        if let cur = currentAccount {
            return all.filter { $0.id != cur.id }
        }
        return []
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                headerBar

                if let current = currentAccount {
                    activeAccountHeaderStrip(for: current)
                    dualGaugeGrid(for: current)
                    telemetryStrip(for: current)
                } else {
                    emptyQuotaPlaceholder
                }

                if quotaResponse?.needsCockpitInstall == true {
                    cockpitInstallHintCard
                } else if !standbyAccounts.isEmpty {
                    standbyDeckCard
                }

                tokenAnalyticsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .refreshable {
            await performManualRefresh()
        }
        .task {
            if tokenHistory == nil {
                await onLoadTokenHistory?(false)
            }
            guard let onAppearFetch else { return }
            await onAppearFetch()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled else { break }
                await onAppearFetch()
            }
        }
        .confirmationDialog(
            "确认热切账号",
            isPresented: $showSwitchConfirm,
            titleVisibility: .visible
        ) {
            Button("热切并重启桌面客户端") {
                if let acc = pendingSwitch {
                    Task { await performAccountSwitch(to: acc) }
                }
                pendingSwitch = nil
            }
            Button("取消", role: .cancel) {
                pendingSwitch = nil
            }
        } message: {
            if let acc = pendingSwitch {
                Text("切换到 \(acc.email) 将平滑重启电脑上的桌面客户端并注入凭证。")
            } else {
                Text("切换账号将关闭并重启电脑上的桌面客户端。")
            }
        }
        .alert("操作提示", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("确定", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $paceDetailItem) { item in
            WeeklyPaceDetailSheet(item: item)
                .presentationDetents([.fraction(0.48), .medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSharePosterSheet) {
            if let history = tokenHistory {
                let activeDate = selectedHeatmapDate
                    ?? history.dailyMatrix.last(where: { $0.total > 0 })?.date
                    ?? history.dailyMatrix.last?.date
                let selectedRec = history.dailyMatrix.first(where: { $0.date == activeDate })
                TokenHistoryShareCardSheet(
                    history: history,
                    selectedRecord: selectedRec,
                    chartType: selectedChartType
                )
            }
        }
        .sheet(isPresented: $showAllModelsSheet) {
            if let history = tokenHistory {
                let allModels = history.resolvedModelSummary
                if !allModels.isEmpty {
                    ModelUsageBreakdownSheet(models: allModels)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
        }
    }

    // MARK: - Top Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text("驾驶舱")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))

                HStack(spacing: 5) {
                    if let updated = quotaResponse?.updatedAt, updated > 0 {
                        let date = Date(timeIntervalSince1970: Double(updated) / 1000.0)
                        Text("Cockpit 实时同步 · \(date.formatted(date: .omitted, time: .shortened))")
                    } else {
                        Text("双模额度仪表盘 · 多号热切 · Token 账本")
                    }
                }
                .font(.system(size: 11.5))
                .foregroundColor(AGPalette.textSecondary(colorScheme))
            }

            Spacer()

            // Mask email button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isMasked.toggle()
                AppSettings.shared.syncWidgetConfiguration()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AGPalette.cardBackground(colorScheme))
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(isMasked ? AGPalette.accentFill(colorScheme) : AGPalette.border(colorScheme), lineWidth: 1)
                        )
                    AGLinearIcon(
                        isMasked ? .eyeOff : .eye,
                        size: 15,
                        color: isMasked ? AGPalette.accentText(colorScheme) : AGPalette.textSecondary(colorScheme),
                        lineWidth: 1.9
                    )
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMasked ? "显示账号邮箱" : "隐藏账号邮箱")

            // Refresh button
            Button {
                Task { await performManualRefresh() }
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
                        ProgressView().scaleEffect(0.7)
                    } else {
                        AGLinearIcon(.refresh, size: 14.5, color: AGPalette.textSecondary(colorScheme), lineWidth: 1.9)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing || switchingAccountId != nil)
        }
        .padding(.bottom, 2)
    }

    // MARK: - Active Account Strip

    private func activeAccountHeaderStrip(for account: CockpitAccountQuota) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(AGPalette.emeraldFill(colorScheme))
                .frame(width: 7, height: 7)

            Text(isMasked ? maskEmail(account.email) : account.email)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AGPalette.textPrimary(colorScheme))
                .lineLimit(1)
                .truncationMode(.middle)

            if let tier = account.subscriptionTier?.trimmingCharacters(in: .whitespacesAndNewlines), !tier.isEmpty {
                AGBadge(tier.uppercased(), tone: tierTone(for: tier))
            }

            Spacer(minLength: 4)

            AGBadge("ACTIVE", tone: .accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .agCard(cornerRadius: 12)
    }

    // MARK: - Dual 240° Speedometer Gauges (Gemini + Claude)

    private func dualGaugeGrid(for account: CockpitAccountQuota) -> some View {
        let geminiPrimary = account.gemini5h ?? account.geminiWeekly
        let geminiPrimaryWindow = account.gemini5h != nil ? "5H" : "7D"
        let geminiPrimaryKind: QuotaBucketKind = account.gemini5h != nil ? .gemini5h : .geminiWeekly
        let geminiSecondary = account.gemini5h != nil ? account.geminiWeekly : nil

        let claudePrimary = account.claude5h ?? account.claudeWeekly
        let claudePrimaryWindow = account.claude5h != nil ? "5H" : "7D"
        let claudePrimaryKind: QuotaBucketKind = account.claude5h != nil ? .claude5h : .claudeWeekly
        let claudeSecondary = account.claude5h != nil ? account.claudeWeekly : nil

        return HStack(spacing: 10) {
            DualArcQuotaGaugeCard(
                provider: .gemini,
                title: "Gemini",
                primaryWindowLabel: geminiPrimaryWindow,
                primaryBucket: geminiPrimary,
                weeklyBucket: geminiSecondary,
                subscriptionTier: account.subscriptionTier,
                isSelectedPrimary: settings.selectedQuotaBucket == geminiPrimaryKind || settings.selectedQuotaBucket == .geminiWeekly,
                activeBadgeWindow: settings.selectedQuotaBucket == .geminiWeekly ? "7d" : (settings.selectedQuotaBucket == geminiPrimaryKind ? geminiPrimaryWindow.lowercased() : nil),
                showPaceCursor: settings.weeklyPaceCursorEnabled,
                onSelectPrimaryBucket: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if settings.selectedQuotaBucket == .gemini5h, account.geminiWeekly != nil {
                        settings.selectedQuotaBucket = .geminiWeekly
                    } else {
                        settings.selectedQuotaBucket = geminiPrimaryKind
                    }
                },
                onInspectPace: { paceInfo in
                    paceDetailItem = WeeklyPaceDetailItem(title: "Gemini · \(geminiPrimaryWindow)", info: paceInfo)
                }
            )

            DualArcQuotaGaugeCard(
                provider: .claude,
                title: "Claude",
                primaryWindowLabel: claudePrimaryWindow,
                primaryBucket: claudePrimary,
                weeklyBucket: claudeSecondary,
                subscriptionTier: account.subscriptionTier,
                isSelectedPrimary: settings.selectedQuotaBucket == claudePrimaryKind || settings.selectedQuotaBucket == .claudeWeekly,
                activeBadgeWindow: settings.selectedQuotaBucket == .claudeWeekly ? "7d" : (settings.selectedQuotaBucket == claudePrimaryKind ? claudePrimaryWindow.lowercased() : nil),
                showPaceCursor: settings.weeklyPaceCursorEnabled,
                onSelectPrimaryBucket: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if settings.selectedQuotaBucket == .claude5h, account.claudeWeekly != nil {
                        settings.selectedQuotaBucket = .claudeWeekly
                    } else {
                        settings.selectedQuotaBucket = claudePrimaryKind
                    }
                },
                onInspectPace: { paceInfo in
                    paceDetailItem = WeeklyPaceDetailItem(title: "Claude · \(claudePrimaryWindow)", info: paceInfo)
                }
            )
        }
    }

    // MARK: - Argon & Streaming Telemetry Strip

    @ViewBuilder
    private func telemetryStrip(for account: CockpitAccountQuota) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                AGLinearIcon(.flask, size: 13.5, color: AGPalette.amberText(colorScheme), lineWidth: 1.95)
                if let argon = account.gemini4Argon {
                    Text("Argon 实验池")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(AGPalette.textSecondary(colorScheme))
                        .lineLimit(1)
                    Text(String(format: "%.0f%%", argon.remainingPercent))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(AGPalette.amberText(colorScheme))
                } else {
                    Text("外环 5h 实时 · 内环 7d 周池")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AGPalette.textSecondary(colorScheme))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let monitor = linkMonitor {
                TimelineView(.periodic(from: .now, by: 2)) { context in
                    let state = monitor.linkState(at: context.date)
                    HStack(spacing: 5) {
                        AGLinearIcon(
                            .bolt,
                            size: 12.5,
                            color: state == .connected ? AGPalette.emeraldText(colorScheme) : AGPalette.amberText(colorScheme),
                            lineWidth: 2.0
                        )
                        Text(state == .connected ? "网关实时在线" : state.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(state == .connected ? AGPalette.emeraldText(colorScheme) : AGPalette.textSecondary(colorScheme))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8.5)
        .agCard(cornerRadius: 12)
    }

    // MARK: - Standby Account Hot-Swap Deck

    private var standbyDeckCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("备用账号无感热切池 (\(standbyAccounts.count))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AGPalette.textSecondary(colorScheme))
                Spacer()
                Text("桌面端自动换号")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(AGPalette.textTertiary(colorScheme))
            }

            VStack(spacing: 7) {
                ForEach(standbyAccounts) { acc in
                    standbyAccountRow(for: acc)
                }
            }
        }
        .padding(13)
        .agCard(cornerRadius: 14)
    }

    @ViewBuilder
    private func standbyAccountRow(for acc: CockpitAccountQuota) -> some View {
        let isSwitchingThis = switchingAccountId == acc.id
        let gemPct = (acc.gemini5h ?? acc.geminiWeekly)?.remainingPercent
        let claPct = (acc.claude5h ?? acc.claudeWeekly)?.remainingPercent
        let argPct = acc.gemini4Argon?.remainingPercent

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 5) {
                    Text(isMasked ? maskEmail(acc.email) : acc.email)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AGPalette.textPrimary(colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let tier = acc.subscriptionTier?.trimmingCharacters(in: .whitespacesAndNewlines), !tier.isEmpty {
                        AGBadge(tier.uppercased(), tone: tierTone(for: tier))
                    }
                }

                let subLabel: String = {
                    if let gReset = (acc.gemini5h ?? acc.geminiWeekly)?.resetFriendly, !gReset.isEmpty {
                        return gReset
                    }
                    return String(localized: "待命就绪")
                }()
                Text(subLabel)
                    .font(.system(size: 10))
                    .foregroundColor(AGPalette.textTertiary(colorScheme))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Dual mini brand rings
            HStack(spacing: 6) {
                if let g = gemPct {
                    MiniBrandQuotaRing(kind: .gemini, percent: g)
                }
                if let c = claPct {
                    MiniBrandQuotaRing(kind: .claude, percent: c)
                } else if let a = argPct {
                    MiniBrandQuotaRing(kind: .argon, percent: a)
                }
            }

            if enableSwitchButton, onSwitch != nil {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    pendingSwitch = acc
                    showSwitchConfirm = true
                } label: {
                    Group {
                        if isSwitchingThis {
                            ProgressView().scaleEffect(0.65)
                        } else {
                            Text("热切")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .foregroundColor(AGPalette.accentText(colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5.5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AGPalette.accentSoft(colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AGPalette.accentFill(colorScheme).opacity(0.28), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(switchingAccountId != nil)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8.5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AGPalette.recessedWell(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AGPalette.borderSubtle(colorScheme), lineWidth: 1)
        )
    }

    // MARK: - Cockpit Install Hint Card

    private var cockpitInstallHintCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                AGLinearIcon(.layers, size: 14, color: AGPalette.accentText(colorScheme), lineWidth: 1.95)
                Text("多账号热切池（可选扩展）")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))
                Spacer()
                AGBadge("Cockpit Tools", tone: .neutral)
            }

            Text("单账号无需配置；若需在手机端一键热切多个账号，可在电脑终端运行 `mgy cockpit` 联动开源 Cockpit Tools。")
                .font(.system(size: 11.5))
                .foregroundColor(AGPalette.textSecondary(colorScheme))
                .lineSpacing(2)

            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = "mgy cockpit"
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    copiedFeedbackKey = "cmd"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        if copiedFeedbackKey == "cmd" { copiedFeedbackKey = nil }
                    }
                } label: {
                    HStack(spacing: 4) {
                        AGLinearIcon(copiedFeedbackKey == "cmd" ? .check : .terminal, size: 11.5, color: AGPalette.accentText(colorScheme), lineWidth: 2.0)
                        Text(copiedFeedbackKey == "cmd" ? "已复制命令" : "复制 mgy cockpit")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(AGPalette.accentText(colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5.5)
                    .background(Capsule().fill(AGPalette.accentSoft(colorScheme)))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCockpitGuideExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(isCockpitGuideExpanded ? "收起步骤" : "配置说明")
                            .font(.system(size: 11, weight: .medium))
                        AGLinearIcon(isCockpitGuideExpanded ? .chevronUp : .chevronDown, size: 10.5, color: AGPalette.textSecondary(colorScheme), lineWidth: 2.0)
                    }
                    .foregroundColor(AGPalette.textSecondary(colorScheme))
                }
                .buttonStyle(.plain)
            }

            if isCockpitGuideExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. 从 GitHub `jlcodes99/cockpit-tools` 下载桌面端并登录备用账号；")
                    Text("2. 在电脑终端执行 `mgy cockpit` 开启本地报表联动；")
                    Text("3. 下拉刷新本页即可显示全部备用号并一键热切。")
                }
                .font(.system(size: 11))
                .foregroundColor(AGPalette.textSecondary(colorScheme))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AGPalette.recessedWell(colorScheme)))
            }
        }
        .padding(13)
        .agCard(cornerRadius: 14)
    }

    // MARK: - Empty Quota State

    private var emptyQuotaPlaceholder: some View {
        VStack(spacing: 8) {
            AGLinearIcon(.gauge, size: 28, color: AGPalette.textTertiary(colorScheme), lineWidth: 1.8)
            Text("正在同步实时账户配额...")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AGPalette.textSecondary(colorScheme))
            Text("连接电脑网关后将自动展示 Gemini 与 Claude 双环仪表盘")
                .font(.system(size: 11.5))
                .foregroundColor(AGPalette.textTertiary(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .agCard(cornerRadius: 15)
    }

    // MARK: - Same-Screen Token Cost & 3-Chart History

    @ViewBuilder
    private var tokenAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Token 账本与趋势分析")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))

                Spacer()

                if tokenHistory != nil {
                    Button {
                        Task { await saveTokenHistoryPoster() }
                    } label: {
                        HStack(spacing: 4) {
                            if isSavingPoster {
                                ProgressView().scaleEffect(0.65)
                            } else {
                                AGLinearIcon(.download, size: 12, color: AGPalette.textSecondary(colorScheme), lineWidth: 1.95)
                            }
                            Text("存图")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(AGPalette.textSecondary(colorScheme))
                        .padding(.horizontal, 8.5)
                        .padding(.vertical, 4.5)
                        .background(Capsule().fill(AGPalette.cardBackground(colorScheme)))
                        .overlay(Capsule().stroke(AGPalette.border(colorScheme), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSavingPoster)

                    Button {
                        showSharePosterSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            AGLinearIcon(.share, size: 12, color: AGPalette.accentText(colorScheme), lineWidth: 1.95)
                            Text("海报")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(AGPalette.accentText(colorScheme))
                        .padding(.horizontal, 8.5)
                        .padding(.vertical, 4.5)
                        .background(Capsule().fill(AGPalette.accentSoft(colorScheme)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)

            if tokenHistory == nil && isLoadingTokenHistory {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在扫描本地 Transcript Token 历史...")
                        .font(.system(size: 12.5))
                        .foregroundColor(AGPalette.textSecondary(colorScheme))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .agCard(cornerRadius: 14)
            } else if let history = tokenHistory {
                let s = history.summary
                let matrix = history.dailyMatrix
                let activeDate = selectedHeatmapDate
                    ?? matrix.last(where: { $0.total > 0 })?.date
                    ?? matrix.last?.date
                let selectedRec = matrix.first(where: { $0.date == activeDate })
                let allModels = history.resolvedModelSummary

                // Compact 2x2 KPI Bento
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    kpiTile(
                        title: String(localized: "今日消耗"),
                        value: AccountQuotaSheet.formatTokensCompact(s.todayTokens),
                        sub: String(localized: "\(s.activeDays) 活跃日")
                    )
                    kpiTile(
                        title: String(localized: "API 折算"),
                        value: String(format: "$%.2f", s.estimatedCostUsd),
                        sub: String(format: "≈ ¥%.1f", s.estimatedCostCny),
                        highlight: true
                    )
                    kpiTile(
                        title: String(localized: "近 7 日"),
                        value: AccountQuotaSheet.formatTokensCompact(s.last7dTokens),
                        sub: String(localized: "\(s.totalSteps) 轮采样")
                    )
                    kpiTile(
                        title: String(localized: "累计总计"),
                        value: AccountQuotaSheet.formatTokensCompact(s.totalTokens),
                        sub: "IDE \(AccountQuotaSheet.formatTokensCompact(s.desktopTokens)) · CLI \(AccountQuotaSheet.formatTokensCompact(s.cliTokens))"
                    )
                }

                // 3-Chart Carousel (14d Bars / Model Donut / 20w Heatmap)
                TokenHistoryChartCarouselCard(
                    matrix: matrix,
                    selectedDate: activeDate,
                    selectedChart: $selectedChartType,
                    onSelectDate: { date in
                        selectedHeatmapDate = date
                        expandedInspectorModel = nil
                    },
                    onUserSelectChart: { chart in
                        AppSettings.shared.tokenHistoryChartType = chart.rawValue
                    },
                    onOpenAllModels: allModels.isEmpty ? nil : {
                        showAllModelsSheet = true
                    }
                )
                .onAppear {
                    if !hasInitializedChartType {
                        let resolved = TokenHistoryChartType.resolveDefault(
                            savedRawValue: AppSettings.shared.tokenHistoryChartType,
                            activeDays: s.activeDays
                        )
                        hasInitializedChartType = true
                        selectedChartType = resolved
                    }
                }
                .onChange(of: selectedChartType) { _, newValue in
                    if hasInitializedChartType {
                        AppSettings.shared.tokenHistoryChartType = newValue.rawValue
                    }
                }

                if let rec = selectedRec {
                    dailyInspectorCard(record: rec)
                }
            } else {
                HStack {
                    Text("暂无本地 Token 统计记录")
                        .font(.system(size: 12.5))
                        .foregroundColor(AGPalette.textSecondary(colorScheme))
                    Spacer()
                    Button("刷新统计") {
                        Task { await onLoadTokenHistory?(true) }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AGPalette.accentText(colorScheme))
                }
                .padding(14)
                .agCard(cornerRadius: 14)
            }
        }
    }

    private func kpiTile(title: String, value: String, sub: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AGPalette.textSecondary(colorScheme))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundColor(highlight ? AGPalette.accentText(colorScheme) : AGPalette.textPrimary(colorScheme))
                .lineLimit(1)
            Text(sub)
                .font(.system(size: 10.5))
                .foregroundColor(AGPalette.textTertiary(colorScheme))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .agCard(cornerRadius: 12)
    }

    private func dailyInspectorCard(record: DailyTokenRecord) -> some View {
        let sortedModels = record.models.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(record.date) 用量明细")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))
                Spacer()
                Text("\(AccountQuotaSheet.formatTokensCompact(record.total)) · $\(String(format: "%.3f", record.costUsd))")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundColor(AGPalette.accentText(colorScheme))
            }

            HStack {
                miniStat("Input", AccountQuotaSheet.formatTokensCompact(record.input))
                Spacer()
                miniStat("Cache", AccountQuotaSheet.formatTokensCompact(record.cacheRead))
                Spacer()
                miniStat("Output", AccountQuotaSheet.formatTokensCompact(record.output))
                Spacer()
                miniStat("Thinking", AccountQuotaSheet.formatTokensCompact(record.thinking))
            }

            if !sortedModels.isEmpty {
                Divider().overlay(AGPalette.borderSubtle(colorScheme))
                VStack(spacing: 5) {
                    ForEach(sortedModels.prefix(6), id: \.key) { pair in
                        let detail = record.modelDetails?[pair.key]
                        let canExpand = detail.map { $0.input > 0 || $0.output > 0 || $0.cacheRead > 0 || $0.thinking > 0 } ?? false
                        let isExpanded = canExpand && expandedInspectorModel == pair.key

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                ModelProviderBrandIcon(modelId: pair.key, size: 12)
                                Text(pair.key)
                                    .font(.system(size: 11, weight: isExpanded ? .semibold : .regular))
                                    .foregroundColor(isExpanded ? AGPalette.textPrimary(colorScheme) : AGPalette.textSecondary(colorScheme))
                                    .lineLimit(1)
                                Spacer()
                                Text(AccountQuotaSheet.formatTokensCompact(pair.value))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(AGPalette.textPrimary(colorScheme))
                            }
                            if isExpanded, let detail {
                                HStack {
                                    Text("In \(AccountQuotaSheet.formatTokensCompact(detail.input))")
                                    Spacer()
                                    Text("Cache \(AccountQuotaSheet.formatTokensCompact(detail.cacheRead))")
                                    Spacer()
                                    Text("Out \(AccountQuotaSheet.formatTokensCompact(detail.output))")
                                    if detail.thinking > 0 {
                                        Spacer()
                                        Text("Think \(AccountQuotaSheet.formatTokensCompact(detail.thinking))")
                                    }
                                }
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(AGPalette.textSecondary(colorScheme))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(AGPalette.recessedWell(colorScheme)))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard canExpand else { return }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.16)) {
                                expandedInspectorModel = isExpanded ? nil : pair.key
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .agCard(cornerRadius: 13)
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1.5) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(AGPalette.textTertiary(colorScheme))
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundColor(AGPalette.textPrimary(colorScheme))
        }
    }

    // MARK: - Helpers

    private func tierTone(for tier: String) -> AGSemanticTone {
        let up = tier.uppercased()
        if up.contains("ULTRA") { return .amber }
        if up.contains("PRO") { return .accent }
        return .neutral
    }

    private func maskEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return email }
        func maskPart(_ str: String) -> String {
            let chars = Array(str)
            guard !chars.isEmpty else { return "" }
            if chars.count <= 2 { return String(chars[0]) + "*" }
            return String(chars[0]) + String(repeating: "*", count: min(5, chars.count - 2)) + String(chars[chars.count - 1])
        }
        let local = String(parts[0])
        let domain = String(parts[1])
        if let dotIdx = domain.lastIndex(of: ".") {
            return "\(maskPart(local))@\(maskPart(String(domain[..<dotIdx])))\(String(domain[dotIdx...]))"
        }
        return "\(maskPart(local))@\(maskPart(domain))"
    }

    private func performManualRefresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if let onRefresh {
            do {
                try await onRefresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        await onLoadTokenHistory?(true)
    }

    private func performAccountSwitch(to account: CockpitAccountQuota) async {
        guard let onSwitch else { return }
        switchingAccountId = account.id
        defer { switchingAccountId = nil }
        do {
            try await onSwitch(account.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveTokenHistoryPoster() async {
        guard let history = tokenHistory, !isSavingPoster else { return }
        isSavingPoster = true
        defer { isSavingPoster = false }

        let matrix = history.dailyMatrix
        let activeDate = selectedHeatmapDate
            ?? matrix.last(where: { $0.total > 0 })?.date
            ?? matrix.last?.date
        let selectedRec = matrix.first(where: { $0.date == activeDate })

        let card = TokenHistoryShareCardView(
            history: history,
            selectedRecord: selectedRec,
            chartType: selectedChartType,
            colorScheme: colorScheme,
            skin: AppSettings.shared.resolvedShareCardSkin(for: colorScheme),
            exportDate: Date()
        )
        guard let image = card.renderImage(displayScale: displayScale) else {
            errorMessage = String(localized: "长图生成失败，请稍后重试")
            return
        }
        await ImageActions.saveWithFeedback(image)
    }
}

// MARK: - 240° Dual-Arc Speedometer Gauge Card

struct DualArcQuotaGaugeCard: View {
    enum Provider {
        case gemini
        case claude
    }

    @Environment(\.colorScheme) private var colorScheme

    let provider: Provider
    let title: String
    let primaryWindowLabel: String
    let primaryBucket: CockpitQuotaBucket?
    let weeklyBucket: CockpitQuotaBucket?
    let subscriptionTier: String?
    let isSelectedPrimary: Bool
    var activeBadgeWindow: String? = nil
    let showPaceCursor: Bool
    let onSelectPrimaryBucket: () -> Void
    let onInspectPace: (WeeklyPaceInfo) -> Void

    private var primaryPercent: Double {
        min(100.0, max(0.0, primaryBucket?.remainingPercent ?? 0.0))
    }

    private var weeklyPercent: Double? {
        guard let weeklyBucket else { return nil }
        return min(100.0, max(0.0, weeklyBucket.remainingPercent))
    }

    private var paceInfo: WeeklyPaceInfo? {
        guard let primaryBucket else { return nil }
        let windowHours = primaryWindowLabel == "5H" ? 5.0 : 168.0
        return primaryBucket.calculateWeeklyPace(totalWindowHours: windowHours)
    }

    private var primaryArcColor: Color {
        if primaryBucket == nil {
            return AGPalette.border(colorScheme)
        }
        if primaryPercent < 15 {
            return AGPalette.roseFill(colorScheme)
        }
        if primaryPercent < 30 {
            return AGPalette.amberFill(colorScheme)
        }
        switch provider {
        case .gemini:
            return AGPalette.geminiBrandFill(colorScheme)
        case .claude:
            return AGPalette.claudeBrandFill
        }
    }

    private var innerArcColor: Color {
        switch provider {
        case .gemini:
            return AGPalette.emeraldFill(colorScheme)
        case .claude:
            return AGPalette.claudeBrandFill.opacity(0.75)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Brand header
            HStack(spacing: 6) {
                switch provider {
                case .gemini:
                    GeminiBrandIcon(size: 15)
                case .claude:
                    ClaudeBrandIcon(size: 15)
                }

                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))
                    .lineLimit(1)

                Spacer(minLength: 2)

                if let activeWin = activeBadgeWindow {
                    Text("\(activeWin) 主显")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(AGPalette.accentText(colorScheme))
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(AGPalette.accentSoft(colorScheme))
                        .clipShape(Capsule())
                } else {
                    Text(weeklyBucket != nil ? "5h / 7d" : primaryWindowLabel.lowercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(AGPalette.textTertiary(colorScheme))
                }
            }

            // 240° Dual-Arc Dial
            DualArcSpeedometerDial(
                outerPercent: primaryPercent,
                innerPercent: weeklyPercent,
                paceExpectedPercent: showPaceCursor ? paceInfo?.expectedRemainingPercent : nil,
                isOverPacing: paceInfo?.isOverPacing ?? false,
                outerColor: primaryArcColor,
                innerColor: innerArcColor,
                centerValueText: primaryBucket != nil ? "\(Int(primaryPercent.rounded()))%" : "—",
                centerSubText: "\(primaryWindowLabel) 剩余"
            )
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelectPrimaryBucket()
            }

            // Bottom telemetry footer
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    if let wp = weeklyPercent {
                        Text("7d 周池 \(Int(wp.rounded()))%")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(AGPalette.textSecondary(colorScheme))
                    } else {
                        Text(subscriptionTier?.uppercased() == "FREE" ? "周度免费池" : "单层配额池")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(AGPalette.textSecondary(colorScheme))
                    }
                    Spacer(minLength: 2)
                    Text(shortResetLabel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AGPalette.textTertiary(colorScheme))
                        .lineLimit(1)
                }

                if let info = paceInfo {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onInspectPace(info)
                    } label: {
                        let deltaStr = (info.paceDeltaPercent >= 0 ? "+" : "") + String(format: "%.0f%%", info.paceDeltaPercent)
                        AGBadge(
                            info.isOverPacing
                                ? String(localized: "\(deltaStr) 消耗偏快 ›")
                                : String(localized: "\(deltaStr) 节奏充裕 ›"),
                            tone: info.isOverPacing ? .amber : .emerald
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    AGBadge(primaryBucket != nil ? "配额监控中" : "暂无该池数据", tone: .neutral)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(AGPalette.cardBackground(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(
                    isSelectedPrimary
                        ? AGPalette.accentFill(colorScheme).opacity(colorScheme == .dark ? 0.65 : 0.45)
                        : AGPalette.border(colorScheme),
                    lineWidth: isSelectedPrimary ? 1.3 : 1.0
                )
        )
    }

    private var shortResetLabel: String {
        guard let friendly = primaryBucket?.resetFriendly, !friendly.isEmpty else {
            return String(localized: "充足")
        }
        return friendly
    }
}

/// Pure vector 240° (`150°` -> `390°`) concentric speedometer dial with 13 graduation ticks and pace needle.
struct DualArcSpeedometerDial: View {
    @Environment(\.colorScheme) private var colorScheme

    let outerPercent: Double
    let innerPercent: Double?
    let paceExpectedPercent: Double?
    let isOverPacing: Bool
    let outerColor: Color
    let innerColor: Color
    let centerValueText: String
    let centerSubText: String

    private let sweepFraction: CGFloat = 240.0 / 360.0

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height + 12)
            let outerRadius = size * 0.41
            let innerRadius = outerRadius - 11.5
            let center = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.56)

            ZStack {
                // 1. 13 radial graduation ticks along the 240° rim
                Canvas { ctx, _ in
                    let tickInner = outerRadius + 6.5
                    for i in 0...12 {
                        let t = Double(i) / 12.0
                        let isMajor = (i % 3 == 0)
                        let tickOuter = tickInner + (isMajor ? 4.2 : 2.4)
                        let deg = 150.0 + 240.0 * t
                        let rad = deg * .pi / 180.0
                        var p = Path()
                        p.move(to: CGPoint(x: center.x + tickInner * cos(rad), y: center.y + tickInner * sin(rad)))
                        p.addLine(to: CGPoint(x: center.x + tickOuter * cos(rad), y: center.y + tickOuter * sin(rad)))
                        ctx.stroke(
                            p,
                            with: .color(
                                isMajor
                                    ? AGPalette.textTertiary(colorScheme).opacity(0.85)
                                    : AGPalette.border(colorScheme)
                            ),
                            style: StrokeStyle(lineWidth: isMajor ? 1.4 : 1.0, lineCap: .round)
                        )
                    }
                }

                // 2. Outer 5h track + active arc
                Circle()
                    .trim(from: 0, to: sweepFraction)
                    .stroke(
                        AGPalette.gaugeTrack(colorScheme),
                        style: StrokeStyle(lineWidth: 8.5, lineCap: .round)
                    )
                    .frame(width: outerRadius * 2, height: outerRadius * 2)
                    .rotationEffect(.degrees(150))
                    .position(center)

                Circle()
                    .trim(from: 0, to: sweepFraction * CGFloat(outerPercent / 100.0))
                    .stroke(
                        outerColor,
                        style: StrokeStyle(lineWidth: 8.5, lineCap: .round)
                    )
                    .frame(width: outerRadius * 2, height: outerRadius * 2)
                    .rotationEffect(.degrees(150))
                    .position(center)
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: outerPercent)

                // 3. Inner 7d concentric track + active arc (when weekly pool exists)
                if let innerPct = innerPercent {
                    Circle()
                        .trim(from: 0, to: sweepFraction)
                        .stroke(
                            AGPalette.gaugeTrack(colorScheme).opacity(0.85),
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                        )
                        .frame(width: innerRadius * 2, height: innerRadius * 2)
                        .rotationEffect(.degrees(150))
                        .position(center)

                    Circle()
                        .trim(from: 0, to: sweepFraction * CGFloat(innerPct / 100.0))
                        .stroke(
                            innerColor,
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                        )
                        .frame(width: innerRadius * 2, height: innerRadius * 2)
                        .rotationEffect(.degrees(150))
                        .position(center)
                        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: innerPct)
                }

                // 4. Physical Time-Pace Needle across outer arc
                if let expected = paceExpectedPercent {
                    Canvas { ctx, _ in
                        let clamped = min(100.0, max(0.0, expected)) / 100.0
                        let deg = 150.0 + 240.0 * clamped
                        let rad = deg * .pi / 180.0
                        let r0 = outerRadius - 6.5
                        let r1 = outerRadius + 6.5
                        var needle = Path()
                        needle.move(to: CGPoint(x: center.x + r0 * cos(rad), y: center.y + r0 * sin(rad)))
                        needle.addLine(to: CGPoint(x: center.x + r1 * cos(rad), y: center.y + r1 * sin(rad)))
                        let needleColor = isOverPacing
                            ? AGPalette.amberFill(colorScheme)
                            : AGPalette.gaugeNeedle(colorScheme)
                        ctx.stroke(
                            needle,
                            with: .color(needleColor),
                            style: StrokeStyle(lineWidth: 2.3, lineCap: .round)
                        )
                    }
                }

                // 5. Center tabular readout
                VStack(spacing: 1) {
                    Text(centerValueText)
                        .font(.system(size: 21, weight: .bold, design: .monospaced))
                        .foregroundColor(AGPalette.textPrimary(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(centerSubText)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(AGPalette.textTertiary(colorScheme))
                        .lineLimit(1)
                }
                .position(x: center.x, y: center.y + 4)
            }
        }
    }
}

/// Compact circular brand ring used in the Standby Account Deck (`Gemini`, `Claude`, `Argon`).
struct MiniBrandQuotaRing: View {
    enum Kind {
        case gemini
        case claude
        case argon
    }

    @Environment(\.colorScheme) private var colorScheme
    let kind: Kind
    let percent: Double

    private var clamped: Double {
        min(100.0, max(0.0, percent))
    }

    private var strokeColor: Color {
        if clamped < 20 { return AGPalette.roseFill(colorScheme) }
        if clamped < 40 { return AGPalette.amberFill(colorScheme) }
        switch kind {
        case .gemini: return AGPalette.geminiBrandFill(colorScheme)
        case .claude: return AGPalette.claudeBrandFill
        case .argon: return AGPalette.amberFill(colorScheme)
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(AGPalette.gaugeTrack(colorScheme), lineWidth: 3.0)
                    .frame(width: 26, height: 26)

                Circle()
                    .trim(from: 0, to: CGFloat(clamped / 100.0))
                    .stroke(strokeColor, style: StrokeStyle(lineWidth: 3.0, lineCap: .round))
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(-90))

                switch kind {
                case .gemini:
                    GeminiBrandIcon(size: 11)
                case .claude:
                    ClaudeBrandIcon(size: 11)
                case .argon:
                    AGLinearIcon(.flask, size: 10.5, color: AGPalette.amberText(colorScheme), lineWidth: 2.0)
                }
            }
            Text("\(Int(clamped.rounded()))%")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(AGPalette.textSecondary(colorScheme))
        }
    }
}

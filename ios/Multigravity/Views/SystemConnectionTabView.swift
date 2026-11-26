import ActivityKit
import SwiftUI
import UIKit
import UserNotifications

/// Tab 4 (`连接`): Visual Zero-Knowledge Link Topology & System Preferences (v4.0 Pure-SVG).
/// Replaces long text-only settings tables with an intuitive iPhone <-> Gateway P-256 + AES-GCM
/// visual topology card, 4-channel smart route pills, a 3-card global permission selector,
/// dual favorite models with official Gemini/Claude icons, and appearance/notification controls.
public struct SystemConnectionTabView: View {
    @Environment(\.colorScheme) private var colorScheme

    public let linkMonitor: ConversationEventsClient?
    public let onScanQRPair: (() -> Void)?
    public let onManualPair: (() -> Void)?

    @State private var settings = AppSettings.shared
    @State private var connectionManager = ConnectionManager.shared
    @State private var pushManager = PushNotificationManager.shared
    @State private var modelCatalog = ModelCatalogStore.shared

    @State private var lanAddress: String = ""
    @State private var customAddress: String = ""
    @State private var showEndpointEditors: Bool = false
    @State private var probeTask: Task<Void, Never>? = nil

    @State private var permissionPreset: String = AppSettings.shared.cachedPermissionPreset
    @State private var confirmedPermissionPreset: String = AppSettings.shared.cachedPermissionPreset
    @State private var showAutoPermissionConfirm: Bool = false
    @State private var permissionErrorMessage: String? = nil

    @State private var showClearCacheAlert: Bool = false
    @State private var cachedMediaSizeText: String = ""
    @State private var showUnpairAlert: Bool = false
    @State private var webSheetURL: IdentifiableURL? = nil
    @State private var showPrivacyPolicySheet: Bool = false
    @State private var showLicensesSheet: Bool = false
    @State private var showSoundSettingsSheet: Bool = false
    @State private var showCompactModeSheet: Bool = false
    @State private var showGesturesGuideSheet: Bool = false

    public init(
        linkMonitor: ConversationEventsClient? = nil,
        onScanQRPair: (() -> Void)? = nil,
        onManualPair: (() -> Void)? = nil
    ) {
        self.linkMonitor = linkMonitor
        self.onScanQRPair = onScanQRPair
        self.onManualPair = onManualPair
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                headerBar

                // 1. Visual Zero-Knowledge Link Topology Card
                topologyCard

                // 2. Visual 3-Card Global Agent Permission Selector
                permissionSelectorCard

                // 3. Dual Favorite Models & Appearance Card
                modelsAndAppearanceCard

                // 4. Voice, Push, Live Activity & Compact Mode Card
                notificationsAndExperienceCard

                // 5. Guide, Storage, About & Unpair Card
                storageAndAboutCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .onAppear {
            lanAddress = settings.lanServerURL ?? ""
            customAddress = settings.customServerURL ?? ""
            permissionPreset = settings.cachedPermissionPreset
            confirmedPermissionPreset = settings.cachedPermissionPreset
        }
        .onDisappear {
            probeTask?.cancel()
            persistDraftEndpointsIfNeeded()
        }
        .task {
            await pushManager.refreshAuthorizationStatus()
            await connectionManager.probeEndpoints()
            if let url = settings.serverURL {
                await modelCatalog.refresh(settings: settings, baseURL: url, force: true)
            }
            if let gwUrl = settings.gatewayURL,
               let state = try? await APIClient.shared.fetchPermissionSettings(baseURL: gwUrl) {
                settings.cachedPermissionPreset = state.preset
                confirmedPermissionPreset = state.preset
                permissionPreset = state.preset
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .permissionPresetDidChange)) { notif in
            if let state = notif.object as? PermissionStateResponse {
                settings.cachedPermissionPreset = state.preset
                confirmedPermissionPreset = state.preset
                permissionPreset = state.preset
            }
        }
        .alert("开启全自动放行？", isPresented: $showAutoPermissionConfirm) {
            Button("取消", role: .cancel) {
                permissionPreset = confirmedPermissionPreset
            }
            Button("确认开启", role: .destructive) {
                applyPermissionPreset("auto")
            }
        } message: {
            Text("开启后 Agent 将自动执行终端命令并访问工作区外文件（同步作用于桌面端全部会话）。建议仅在可信或隔离环境中使用。")
        }
        .alert("权限更新失败", isPresented: Binding(
            get: { permissionErrorMessage != nil },
            set: { if !$0 { permissionErrorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { permissionErrorMessage = nil }
        } message: {
            Text(permissionErrorMessage ?? "")
        }
        .alert("确定清空本地缓存？", isPresented: $showClearCacheAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                CacheManager.shared.clearCache()
                DocumentCacheManager.shared.clearCache()
                cachedMediaSizeText = "0 KB"
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } message: {
            Text("本地永久缓存的图片、视频、离线文档与会话消息将被清理，下次访问时将重新从电脑端加载。")
        }
        .alert(settings.isDemoMode ? String(localized: "确定退出演示模式？") : String(localized: "确定解除设备配对？"), isPresented: $showUnpairAlert) {
            Button("取消", role: .cancel) {}
            Button(settings.isDemoMode ? String(localized: "退出演示") : String(localized: "解除配对"), role: .destructive) {
                performUnpair()
            }
        } message: {
            Text(settings.isDemoMode
                 ? String(localized: "将退出演示模式并回到欢迎页，演示数据会被清除。")
                 : String(localized: "解除配对将通知网关清理此设备绑定，并清除本地访问令牌与网关配置。"))
        }
        .sheet(item: $webSheetURL) { item in
            SafariWebViewSheet(url: item.url)
        }
        .sheet(isPresented: $showPrivacyPolicySheet) {
            PrivacyPolicySheet(onOpenWeb: { url in
                showPrivacyPolicySheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    webSheetURL = IdentifiableURL(url: url)
                }
            })
        }
        .sheet(isPresented: $showLicensesSheet) {
            OpenSourceLicensesSheet()
        }
        .sheet(isPresented: $showSoundSettingsSheet) {
            NavigationStack {
                NotificationSoundSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showSoundSettingsSheet = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCompactModeSheet) {
            NavigationStack {
                CompactModeSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showCompactModeSheet = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGesturesGuideSheet) {
            NavigationStack {
                TipsAndGesturesGuideView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showGesturesGuideSheet = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text("连接与偏好")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))
                Text("零知识 E2EE 链路拓扑 · 权限沙箱 · 主题外观")
                    .font(.system(size: 11.5))
                    .foregroundColor(AGPalette.textSecondary(colorScheme))
            }

            Spacer()

            if let onScanQRPair {
                Button(action: onScanQRPair) {
                    HStack(spacing: 5) {
                        AGLinearIcon(.qrCode, size: 13.5, color: AGPalette.accentText(colorScheme), lineWidth: 2.0)
                        Text("扫码换机")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(AGPalette.accentText(colorScheme))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6.5)
                    .background(Capsule().fill(AGPalette.accentSoft(colorScheme)))
                    .overlay(
                        Capsule()
                            .stroke(AGPalette.accentFill(colorScheme).opacity(0.28), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: - 1. Visual Zero-Knowledge Link Topology Card

    private var topologyCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Top status badge + probe button
            HStack {
                if settings.isDemoMode {
                    AGBadge("离线演示沙箱 · 本地模拟网关", tone: .amber) {
                        AGLinearIcon(.bolt, size: 11, color: AGPalette.amberText(colorScheme), lineWidth: 2.0)
                    }
                } else if let monitor = linkMonitor {
                    TimelineView(.periodic(from: .now, by: 2)) { context in
                        let state = monitor.linkState(at: context.date)
                        let tone: AGSemanticTone = {
                            switch state {
                            case .connected: return .emerald
                            case .attention: return .amber
                            case .disconnected: return .rose
                            case .unknown: return .neutral
                            }
                        }()
                        AGBadge(
                            state == .connected ? String(localized: "已安全直连 · \(bestLatencyText)") : state.title,
                            tone: tone
                        ) {
                            Circle()
                                .fill(tone == .emerald ? AGPalette.emeraldFill(colorScheme) : (tone == .amber ? AGPalette.amberFill(colorScheme) : AGPalette.roseFill(colorScheme)))
                                .frame(width: 6, height: 6)
                        }
                    }
                } else {
                    AGBadge(settings.isPaired ? "已配对网关" : "未配对", tone: settings.isPaired ? .emerald : .neutral)
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    linkMonitor?.reconnect()
                    Task { await connectionManager.probeEndpoints() }
                } label: {
                    HStack(spacing: 4) {
                        if connectionManager.isProbing {
                            ProgressView().scaleEffect(0.65)
                        } else {
                            AGLinearIcon(.refresh, size: 12, color: AGPalette.textSecondary(colorScheme), lineWidth: 1.95)
                        }
                        Text("测速探活")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AGPalette.textSecondary(colorScheme))
                    }
                }
                .buttonStyle(.plain)
            }

            // Visual iPhone <── P-256 + AES-GCM ──> Desktop Gateway diagram
            HStack(spacing: 8) {
                topologyNode(
                    icon: .smartphone,
                    title: "iPhone",
                    subtitle: connectionManager.isWifi ? "Wi-Fi" : (connectionManager.isCellular ? "蜂窝网络" : "本机")
                )

                VStack(spacing: 4) {
                    Text("P-256 + AES-GCM")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(AGPalette.emeraldText(colorScheme))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(AGPalette.emeraldSoft(colorScheme)))

                    ZStack {
                        Rectangle()
                            .fill(AGPalette.emeraldFill(colorScheme).opacity(0.45))
                            .frame(height: 1.5)
                        Circle()
                            .fill(AGPalette.emeraldFill(colorScheme))
                            .frame(width: 6, height: 6)
                    }

                    Text(activeChannelLabel)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(AGPalette.textTertiary(colorScheme))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                topologyNode(
                    icon: .monitor,
                    title: settings.gatewayPlatformDisplayName,
                    subtitle: linkMonitor?.desktopState == "down" ? "桌面未就绪" : "Gateway"
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AGPalette.recessedWell(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AGPalette.borderSubtle(colorScheme), lineWidth: 1)
            )

            // 4-Channel Route Pills (LAN / Tailscale / E2EE Relay / Cloudflare)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                routeChannelPill(
                    title: "LAN 局域网",
                    urlString: settings.lanServerURL,
                    isPrimaryActive: isActiveURL(settings.lanServerURL)
                )
                routeChannelPill(
                    title: "Tailscale",
                    urlString: settings.customServerURL,
                    isPrimaryActive: isActiveURL(settings.customServerURL)
                )
                routeChannelPill(
                    title: "E2EE 中继",
                    urlString: effectiveRelayURL,
                    isPrimaryActive: isActiveURL(effectiveRelayURL)
                )
                routeChannelPill(
                    title: "Cloudflare",
                    urlString: dedicatedCloudflareURL,
                    isPrimaryActive: isActiveURL(dedicatedCloudflareURL)
                )
            }

            // Expandable LAN / Custom URL editor
            DisclosureGroup(isExpanded: $showEndpointEditors) {
                VStack(spacing: 10) {
                    endpointFieldRow(
                        label: String(localized: "局域网直连地址"),
                        placeholder: "http://192.168.1.50:58900",
                        text: $lanAddress,
                        savedValue: settings.lanServerURL,
                        onSave: saveLanAddress
                    )
                    endpointFieldRow(
                        label: String(localized: "Tailscale / 自定义地址"),
                        placeholder: "http://100.x.x.x:58900",
                        text: $customAddress,
                        savedValue: settings.customServerURL,
                        onSave: saveCustomAddress
                    )

                    if let onManualPair {
                        Button(action: onManualPair) {
                            HStack(spacing: 5) {
                                AGLinearIcon(.link, size: 12, color: AGPalette.accentText(colorScheme), lineWidth: 2.0)
                                Text("手动输入配对码或完整配对链接...")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(AGPalette.accentText(colorScheme))
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 6) {
                    AGLinearIcon(.globe, size: 13, color: AGPalette.textSecondary(colorScheme), lineWidth: 1.9)
                    Text("配置局域网与 Tailscale 节点地址")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AGPalette.textSecondary(colorScheme))
                }
            }
            .tint(AGPalette.textSecondary(colorScheme))
        }
        .padding(14)
        .agCard(cornerRadius: 15)
    }

    private func topologyNode(icon: AGLinearIcon.Kind, title: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AGPalette.cardBackground(colorScheme))
                    .frame(width: 38, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AGPalette.border(colorScheme), lineWidth: 1)
                    )
                AGLinearIcon(icon, size: 18, color: AGPalette.textPrimary(colorScheme), lineWidth: 1.9)
            }
            Text(title)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundColor(AGPalette.textPrimary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.system(size: 9.5))
                .foregroundColor(AGPalette.textTertiary(colorScheme))
                .lineLimit(1)
        }
        .frame(width: 88)
    }

    private func routeChannelPill(title: String, urlString: String?, isPrimaryActive: Bool) -> some View {
        let configured = (urlString?.isEmpty == false)
        let status = urlString.flatMap { connectionManager.endpointStatuses[$0] }
        let latencyStr: String = {
            if let s = status, s.isReachable {
                return "\(Int(s.latencyMs.rounded()))ms"
            }
            return configured ? String(localized: "待命") : String(localized: "未配")
        }()

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(
                        isPrimaryActive
                            ? AGPalette.emeraldFill(colorScheme)
                            : (configured ? AGPalette.accentFill(colorScheme).opacity(0.65) : AGPalette.border(colorScheme))
                    )
                    .frame(width: 5.5, height: 5.5)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isPrimaryActive ? AGPalette.textPrimary(colorScheme) : AGPalette.textSecondary(colorScheme))
                    .lineLimit(1)
            }
            Text(latencyStr)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(isPrimaryActive ? AGPalette.emeraldText(colorScheme) : AGPalette.textTertiary(colorScheme))
        }
        .padding(.horizontal, 8.5)
        .padding(.vertical, 6.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isPrimaryActive ? AGPalette.emeraldSoft(colorScheme) : AGPalette.recessedWell(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    isPrimaryActive ? AGPalette.emeraldFill(colorScheme).opacity(0.45) : AGPalette.borderSubtle(colorScheme),
                    lineWidth: 1
                )
        )
    }

    private func endpointFieldRow(
        label: String,
        placeholder: String,
        text: Binding<String>,
        savedValue: String?,
        onSave: @escaping () -> Void
    ) -> some View {
        let isDirty = normalizeURLString(text.wrappedValue) != (savedValue ?? "")
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(AGPalette.textSecondary(colorScheme))
                Spacer()
                Button(action: onSave) {
                    Text(!isDirty && savedValue != nil ? "已保存" : "保存探活")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isDirty ? .white : AGPalette.textSecondary(colorScheme))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill(isDirty ? AGPalette.accentFill(colorScheme) : AGPalette.recessedWell(colorScheme))
                        )
                }
                .buttonStyle(.plain)
            }

            TextField(placeholder, text: text)
                .font(.system(size: 12.5, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AGPalette.recessedWell(colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AGPalette.border(colorScheme), lineWidth: 1)
                )
                .onSubmit(onSave)
        }
    }

    // MARK: - 2. Visual 3-Card Global Permission Selector

    private var permissionSelectorCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                AGLinearIcon(.shield, size: 14.5, color: AGPalette.accentText(colorScheme), lineWidth: 1.95)
                Text("全局 Agent 权限模式")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))
                Spacer()
                Text("实时同步桌面端")
                    .font(.system(size: 10.5))
                    .foregroundColor(AGPalette.textTertiary(colorScheme))
            }

            HStack(spacing: 8) {
                permissionOptionTile(
                    preset: "strict",
                    icon: .lock,
                    title: "严格审批",
                    subtitle: "命令逐条确认",
                    tone: .accent
                )
                permissionOptionTile(
                    preset: "sandbox",
                    icon: .shield,
                    title: "离席沙箱",
                    subtitle: "工作区内放行",
                    tone: .emerald
                )
                permissionOptionTile(
                    preset: "auto",
                    icon: .bolt,
                    title: "全自动",
                    subtitle: "全权免审执行",
                    tone: .amber
                )
            }
        }
        .padding(13)
        .agCard(cornerRadius: 15)
    }

    private func permissionOptionTile(
        preset: String,
        icon: AGLinearIcon.Kind,
        title: String,
        subtitle: String,
        tone: AGSemanticTone
    ) -> some View {
        let selected = permissionPreset == preset
        let activeText: Color = {
            switch tone {
            case .emerald: return AGPalette.emeraldText(colorScheme)
            case .amber: return AGPalette.amberText(colorScheme)
            default: return AGPalette.accentText(colorScheme)
            }
        }()
        let activeFill: Color = {
            switch tone {
            case .emerald: return AGPalette.emeraldSoft(colorScheme)
            case .amber: return AGPalette.amberSoft(colorScheme)
            default: return AGPalette.accentSoft(colorScheme)
            }
        }()
        let activeBorder: Color = {
            switch tone {
            case .emerald: return AGPalette.emeraldFill(colorScheme)
            case .amber: return AGPalette.amberFill(colorScheme)
            default: return AGPalette.accentFill(colorScheme)
            }
        }()

        return Button {
            guard preset != confirmedPermissionPreset else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            permissionPreset = preset
            if preset == "auto" {
                showAutoPermissionConfirm = true
            } else {
                applyPermissionPreset(preset)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                AGLinearIcon(
                    icon,
                    size: 15,
                    color: selected ? activeText : AGPalette.textSecondary(colorScheme),
                    lineWidth: 2.0
                )
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(selected ? activeText : AGPalette.textPrimary(colorScheme))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundColor(AGPalette.textSecondary(colorScheme))
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? activeFill : AGPalette.recessedWell(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        selected ? activeBorder.opacity(0.65) : AGPalette.borderSubtle(colorScheme),
                        lineWidth: selected ? 1.3 : 1.0
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. Favorite Models & Appearance Card

    private var modelsAndAppearanceCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("轮换模型与视觉外观")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))
                Spacer()
                Text("短按输入栏胶囊秒切")
                    .font(.system(size: 10.5))
                    .foregroundColor(AGPalette.textTertiary(colorScheme))
            }

            // Favorite 1 & Favorite 2 pickers with Brand Icons
            VStack(spacing: 8) {
                favoriteModelRow(title: String(localized: "首选模型"), selection: $settings.favoriteModel1)
                favoriteModelRow(title: String(localized: "次选模型"), selection: $settings.favoriteModel2)
            }

            Divider().overlay(AGPalette.borderSubtle(colorScheme))

            // Theme mode segmented control
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("主题配色")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(AGPalette.textPrimary(colorScheme))
                    Spacer()
                    Text(settings.themeMode == "dark" ? "claude cut 黑曜深色" : (settings.themeMode == "light" ? "Antigravity 纯白" : "跟随系统"))
                        .font(.system(size: 11))
                        .foregroundColor(AGPalette.textSecondary(colorScheme))
                }

                Picker("外观模式", selection: $settings.themeMode) {
                    Text("跟随系统").tag("system")
                    Text("纯白浅色").tag("light")
                    Text("黑曜深色").tag("dark")
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.themeMode) { _, _ in
                    settings.applyAppearance()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }

            HStack {
                Text("字号缩放")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))
                Spacer()
                Menu {
                    ForEach(AppSettings.FontSizeScale.allCases) { scale in
                        Button {
                            settings.fontSizeScale = scale
                        } label: {
                            HStack {
                                Text(scale.displayName)
                                if settings.fontSizeScale == scale {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(settings.fontSizeScale.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AGPalette.accentText(colorScheme))
                            .lineLimit(1)
                        AGLinearIcon(.chevronDown, size: 10, color: AGPalette.accentText(colorScheme).opacity(0.8), lineWidth: 2.1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AGPalette.accentSoft(colorScheme)))
                }
            }

            Toggle(isOn: $settings.weeklyPaceCursorEnabled) {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text("仪表盘时间匀速指针")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(AGPalette.textPrimary(colorScheme))
                    Text("在 240° 仪表盘与配额条上标注理论剩余刻度线")
                        .font(.system(size: 10.5))
                        .foregroundColor(AGPalette.textSecondary(colorScheme))
                }
            }
            .tint(AGPalette.accentFill(colorScheme))
        }
        .padding(13)
        .agCard(cornerRadius: 15)
    }

    @ViewBuilder
    private func favoriteModelRow(title: String, selection: Binding<String>) -> some View {
        let all = modelCatalog.allOptions
        let currentLabel = modelCatalog.compactDisplayName(forID: selection.wrappedValue)
        HStack(spacing: 8) {
            ModelProviderBrandIcon(modelId: selection.wrappedValue, size: 14)
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(AGPalette.textPrimary(colorScheme))
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            Menu {
                ForEach(all) { opt in
                    Button {
                        selection.wrappedValue = opt.id
                    } label: {
                        HStack {
                            Text(ModelDefaultsLogic.formatPickerLabel(name: opt.name, tag: opt.tag))
                            if selection.wrappedValue == opt.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(currentLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AGPalette.accentText(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    AGLinearIcon(.chevronDown, size: 10, color: AGPalette.accentText(colorScheme).opacity(0.8), lineWidth: 2.1)
                }
                .padding(.horizontal, 9.5)
                .padding(.vertical, 5.5)
                .background(Capsule().fill(AGPalette.cardBackground(colorScheme)))
                .overlay(Capsule().stroke(AGPalette.border(colorScheme), lineWidth: 1))
            }
            .disabled(all.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AGPalette.recessedWell(colorScheme)))
    }

    // MARK: - 4. Notifications, Voice & Compact Mode

    private var notificationsAndExperienceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("通知、语音与阅读降噪")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AGPalette.textPrimary(colorScheme))

            if !settings.isDemoMode {
                if pushManager.authorizationStatus == .denied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        navRow(icon: .bell, title: "推送通知", value: "前往系统设置开启")
                    }
                    .buttonStyle(.plain)
                } else if pushManager.authorizationStatus == .notDetermined {
                    Button {
                        Task { _ = await pushManager.requestAuthorizationAndRegister() }
                    } label: {
                        navRow(icon: .bell, title: "开启推送通知", value: "立即授权")
                    }
                    .buttonStyle(.plain)
                } else {
                    Toggle("远程推送通知", isOn: $settings.enablePushNotifications)
                        .font(.system(size: 12.5, weight: .medium))
                        .tint(AGPalette.accentFill(colorScheme))
                        .onChange(of: settings.enablePushNotifications) { _, enabled in
                            if enabled {
                                pushManager.syncAllTokensIfPaired(force: true)
                            } else {
                                pushManager.syncPreferencesWithGateway()
                            }
                        }
                }
            }

            Toggle("锁屏实时活动与灵动岛", isOn: $settings.enableLiveActivities)
                .font(.system(size: 12.5, weight: .medium))
                .tint(AGPalette.accentFill(colorScheme))
                .onChange(of: settings.enableLiveActivities) { _, enabled in
                    if !enabled {
                        ActivityManager.shared.endAllActivities(finalStatus: "CANCELLED", dismissalPolicy: .immediate)
                    }
                    pushManager.syncPreferencesWithGateway()
                }

            Toggle("后台长连接保活（静音零打扰）", isOn: $settings.enableBackgroundKeepAlive)
                .font(.system(size: 12.5, weight: .medium))
                .tint(AGPalette.accentFill(colorScheme))
                .onChange(of: settings.enableBackgroundKeepAlive) { _, _ in
                    BackgroundKeepAliveManager.shared.refreshKeepAliveState()
                }

            Toggle("实时双工语音通话模式", isOn: $settings.enableVoiceMode)
                .font(.system(size: 12.5, weight: .medium))
                .tint(AGPalette.accentFill(colorScheme))
                .onChange(of: settings.enableVoiceMode) { _, enabled in
                    if !enabled && VoiceCallManager.shared.isInCall {
                        VoiceCallManager.shared.endCall()
                    }
                }

            Divider().overlay(AGPalette.borderSubtle(colorScheme))

            Button {
                showSoundSettingsSheet = true
            } label: {
                navRow(icon: .bell, title: "通知提示音", value: notificationSoundSummary)
            }
            .buttonStyle(.plain)

            Button {
                showCompactModeSheet = true
            } label: {
                navRow(icon: .layers, title: "对话精简降噪模式", value: settings.isKnowledgeModeEnabled ? "已开启" : "已关闭")
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .agCard(cornerRadius: 15)
    }

    // MARK: - 5. Guide, Storage, About & Unpair

    private var storageAndAboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showGesturesGuideSheet = true
            } label: {
                navRow(icon: .sparkles, title: "功能速查与快捷手势指南", value: "查看")
            }
            .buttonStyle(.plain)

            Divider().overlay(AGPalette.borderSubtle(colorScheme))

            Button {
                showPrivacyPolicySheet = true
            } label: {
                navRow(icon: .shield, title: "隐私政策", value: "零遥测直连")
            }
            .buttonStyle(.plain)

            Button {
                if let url = URL(string: "https://github.com/GHSaiMo/antigravity-mobile") {
                    webSheetURL = IdentifiableURL(url: url)
                }
            } label: {
                navRow(icon: .globe, title: "GitHub 开源仓库", value: "v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.5")")
            }
            .buttonStyle(.plain)

            Button {
                showLicensesSheet = true
            } label: {
                navRow(icon: .fileText, title: "开源许可声明", value: "MIT")
            }
            .buttonStyle(.plain)

            Divider().overlay(AGPalette.borderSubtle(colorScheme))

            HStack(spacing: 8) {
                Button {
                    showClearCacheAlert = true
                } label: {
                    HStack(spacing: 5) {
                        AGLinearIcon(.trash, size: 12.5, color: AGPalette.textSecondary(colorScheme), lineWidth: 1.9)
                        Text(cachedMediaSizeText.isEmpty || cachedMediaSizeText == "0 KB" ? "清空本地缓存" : "清空缓存 (\(cachedMediaSizeText))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AGPalette.textSecondary(colorScheme))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AGPalette.recessedWell(colorScheme)))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(AGPalette.border(colorScheme), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .task {
                    let sizeStr = await Task.detached(priority: .utility) {
                        DocumentCacheManager.shared.formattedCacheSize()
                    }.value
                    cachedMediaSizeText = sizeStr
                }

                Button {
                    showUnpairAlert = true
                } label: {
                    Text(settings.isDemoMode ? "退出演示模式" : "解除设备配对")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AGPalette.roseText(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AGPalette.roseSoft(colorScheme)))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(AGPalette.roseFill(colorScheme).opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .agCard(cornerRadius: 15)
    }

    private func navRow(icon: AGLinearIcon.Kind, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            AGLinearIcon(icon, size: 14, color: AGPalette.textSecondary(colorScheme), lineWidth: 1.9)
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(AGPalette.textPrimary(colorScheme))
            Spacer()
            Text(value)
                .font(.system(size: 11.5))
                .foregroundColor(AGPalette.textSecondary(colorScheme))
                .lineLimit(1)
            AGLinearIcon(.chevronRight, size: 11.5, color: AGPalette.textTertiary(colorScheme), lineWidth: 2.0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private static func isRelayEndpointURL(_ raw: String?) -> Bool {
        guard let raw, !raw.isEmpty, let host = URL(string: raw)?.host?.lowercased() else { return false }
        return host.hasPrefix("r-") && host.contains(".jiuge.space")
    }

    private var effectiveRelayURL: String? {
        if let relay = settings.relayServerURL, !relay.isEmpty {
            return relay
        }
        if Self.isRelayEndpointURL(settings.primaryCloudURL) {
            return settings.primaryCloudURL
        }
        return nil
    }

    private var dedicatedCloudflareURL: String? {
        guard let cloud = settings.primaryCloudURL, !cloud.isEmpty else { return nil }
        if Self.isRelayEndpointURL(cloud) {
            return nil
        }
        if let relay = settings.relayServerURL,
           cloud.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == relay.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
            return nil
        }
        return cloud
    }

    private var bestLatencyText: String {
        if let cur = settings.serverURL?.absoluteString,
           let hit = connectionManager.endpointStatuses[cur],
           hit.isReachable {
            return "\(Int(hit.latencyMs.rounded()))ms"
        }
        if let best = connectionManager.endpointStatuses.values.filter(\.isReachable).min(by: { $0.latencyMs < $1.latencyMs }) {
            return "\(Int(best.latencyMs.rounded()))ms"
        }
        return "E2EE"
    }

    private var activeChannelLabel: String {
        guard let cur = settings.serverURL?.absoluteString else {
            return settings.isDemoMode ? "Demo Sandbox" : "未连接"
        }
        if cur == settings.lanServerURL { return "LAN 局域网直连" }
        if cur == settings.customServerURL { return "自定义 / Tailscale" }
        if cur == settings.relayServerURL { return "Relay 加密中继" }
        if cur == settings.primaryCloudURL { return "Cloudflare 隧道" }
        return URL(string: cur)?.host ?? "直连通道"
    }

    private func isActiveURL(_ candidate: String?) -> Bool {
        guard let candidate, !candidate.isEmpty, let cur = settings.serverURL?.absoluteString else { return false }
        return cur.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == candidate.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var notificationSoundSummary: String {
        let completeName = NotificationSoundOption.displayName(
            for: settings.notificationCompleteSound,
            in: NotificationSoundOption.completeOptions
        )
        let actionName = NotificationSoundOption.displayName(
            for: settings.notificationActionSound,
            in: NotificationSoundOption.actionOptions
        )
        return "\(completeName) · \(actionName)"
    }

    private func normalizeURLString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return "" }
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            return "http://" + trimmed
        }
        return trimmed
    }

    private func saveLanAddress() {
        let normalized = normalizeURLString(lanAddress)
        lanAddress = normalized
        settings.lanServerURL = normalized.isEmpty ? nil : normalized
        scheduleProbeEndpoints()
    }

    private func saveCustomAddress() {
        let normalized = normalizeURLString(customAddress)
        customAddress = normalized
        settings.customServerURL = normalized.isEmpty ? nil : normalized
        scheduleProbeEndpoints()
    }

    private func persistDraftEndpointsIfNeeded() {
        let normCustom = normalizeURLString(customAddress)
        if normCustom != (settings.customServerURL ?? "") {
            settings.customServerURL = normCustom.isEmpty ? nil : normCustom
        }
        let normLan = normalizeURLString(lanAddress)
        if normLan != (settings.lanServerURL ?? "") {
            settings.lanServerURL = normLan.isEmpty ? nil : normLan
        }
    }

    private func scheduleProbeEndpoints() {
        probeTask?.cancel()
        probeTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await connectionManager.probeEndpoints()
        }
    }

    private func applyPermissionPreset(_ preset: String) {
        guard let url = settings.gatewayURL else {
            permissionPreset = confirmedPermissionPreset
            return
        }
        Task {
            do {
                let state = try await APIClient.shared.updatePermissionPreset(preset: preset, baseURL: url)
                settings.cachedPermissionPreset = state.preset
                confirmedPermissionPreset = state.preset
                permissionPreset = state.preset
                NotificationCenter.default.post(name: .permissionPresetDidChange, object: state)
            } catch {
                permissionPreset = confirmedPermissionPreset
                permissionErrorMessage = error.localizedDescription
            }
        }
    }

    private func performUnpair() {
        let currentURL = settings.serverURL
        let currentCandidates = settings.candidateEndpoints.compactMap { URL(string: $0.urlString) }
        let currentToken = settings.deviceToken
        let currentDeviceID = settings.deviceID

        Task {
            await PushNotificationManager.shared.unregisterFromGateway(
                baseURL: currentURL,
                authToken: currentToken,
                deviceId: currentDeviceID
            )
            await APIClient.shared.unpair(
                baseURL: currentURL,
                candidates: currentCandidates,
                token: currentToken,
                deviceID: currentDeviceID
            )
        }
        settings.unpair()
        CacheManager.shared.clearCache()
        DocumentCacheManager.shared.clearCache()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        NotificationCenter.default.post(name: .deviceTokenRevoked, object: nil)
    }
}

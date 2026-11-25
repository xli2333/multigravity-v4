import SwiftUI

/// Primary 4-Tab architecture for Multigravity v4.0 (100% pure-SVG 1.9pt linear icons, zero emoji).
public enum AGMainTab: String, CaseIterable, Identifiable {
    case sessions = "sessions"
    case hub = "hub"
    case cockpit = "cockpit"
    case system = "system"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sessions: return String(localized: "会话")
        case .hub: return String(localized: "中枢")
        case .cockpit: return String(localized: "驾驶舱")
        case .system: return String(localized: "连接")
        }
    }

    public var iconKind: AGLinearIcon.Kind {
        switch self {
        case .sessions: return .chat
        case .hub: return .grid
        case .cockpit: return .gauge
        case .system: return .settings
        }
    }
}

/// Bottom navigation bar matching the approved v4.0 pure-SVG specification:
/// - 会话 (with amber action-required badge)
/// - 中枢 (with accent running-tasks badge)
/// - 驾驶舱 · XX% (live primary quota percentage when inactive)
/// - 连接 (with live LinkHealthState dot)
public struct AGBottomTabBar: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding public var selectedTab: AGMainTab
    public let actionRequiredCount: Int
    public let unreadSessionCount: Int
    public let runningHubCount: Int
    public let primaryQuotaPercent: Double?
    public let linkMonitor: ConversationEventsClient?

    public init(
        selectedTab: Binding<AGMainTab>,
        actionRequiredCount: Int = 0,
        unreadSessionCount: Int = 0,
        runningHubCount: Int = 0,
        primaryQuotaPercent: Double? = nil,
        linkMonitor: ConversationEventsClient? = nil
    ) {
        self._selectedTab = selectedTab
        self.actionRequiredCount = actionRequiredCount
        self.unreadSessionCount = unreadSessionCount
        self.runningHubCount = runningHubCount
        self.primaryQuotaPercent = primaryQuotaPercent
        self.linkMonitor = linkMonitor
    }

    public var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AGPalette.border(colorScheme))
                .frame(height: 0.75)

            HStack(spacing: 0) {
                ForEach(AGMainTab.allCases) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 7)
            .padding(.bottom, 6)
        }
        .background(
            AGPalette.tabBarBackground(colorScheme)
                .ignoresSafeArea(edges: .bottom)
        )
        .compositingGroup()
    }

    @ViewBuilder
    private func tabButton(for tab: AGMainTab) -> some View {
        let isSelected = selectedTab == tab
        let activeColor = AGPalette.accentText(colorScheme)
        let inactiveColor = AGPalette.textTertiary(colorScheme)
        let iconColor = isSelected ? activeColor : inactiveColor

        Button {
            if selectedTab != tab {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    selectedTab = tab
                }
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(AGPalette.accentSoft(colorScheme))
                                .frame(width: 44, height: 28)
                        }
                        AGLinearIcon(
                            tab.iconKind,
                            size: 20,
                            color: iconColor,
                            lineWidth: isSelected ? 2.05 : 1.85
                        )
                    }
                    .frame(width: 46, height: 28)

                    badgeOverlay(for: tab)
                }

                Text(labelText(for: tab, isSelected: isSelected))
                    .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? AGPalette.textPrimary(colorScheme) : inactiveColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(labelText(for: tab, isSelected: true))
    }

    private func labelText(for tab: AGMainTab, isSelected: Bool) -> String {
        if tab == .cockpit, !isSelected, let pct = primaryQuotaPercent {
            return "\(tab.title) · \(Int(pct.rounded()))%"
        }
        return tab.title
    }

    @ViewBuilder
    private func badgeOverlay(for tab: AGMainTab) -> some View {
        switch tab {
        case .sessions:
            if actionRequiredCount > 0 {
                countPill(
                    count: actionRequiredCount,
                    fill: AGPalette.amberFill(colorScheme)
                )
                .offset(x: 4, y: -3)
            } else if unreadSessionCount > 0 {
                Circle()
                    .fill(AGPalette.accentFill(colorScheme))
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(AGPalette.tabBarBackground(colorScheme), lineWidth: 1.5))
                    .offset(x: 1, y: 0)
            }

        case .hub:
            if runningHubCount > 0 {
                countPill(
                    count: runningHubCount,
                    fill: AGPalette.accentFill(colorScheme)
                )
                .offset(x: 4, y: -3)
            }

        case .cockpit:
            if let pct = primaryQuotaPercent, pct < 20 {
                Circle()
                    .fill(AGPalette.roseFill(colorScheme))
                    .frame(width: 7.5, height: 7.5)
                    .overlay(Circle().stroke(AGPalette.tabBarBackground(colorScheme), lineWidth: 1.5))
                    .offset(x: 1, y: 0)
            }

        case .system:
            if let monitor = linkMonitor {
                TimelineView(.periodic(from: .now, by: 2)) { context in
                    let state = monitor.linkState(at: context.date)
                    let reachableViaHTTP = monitor.desktopState != "down" && ConnectionManager.shared.endpointStatuses.values.contains(where: \.isReachable)
                    let dotFill: Color = {
                        switch state {
                        case .connected: return AGPalette.emeraldFill(colorScheme)
                        case .attention: return AGPalette.amberFill(colorScheme)
                        case .disconnected: return reachableViaHTTP ? AGPalette.emeraldFill(colorScheme) : AGPalette.roseFill(colorScheme)
                        case .unknown: return reachableViaHTTP ? AGPalette.emeraldFill(colorScheme) : AGPalette.textTertiary(colorScheme)
                        }
                    }()
                    Circle()
                        .fill(dotFill)
                        .frame(width: 7.5, height: 7.5)
                        .overlay(
                            Circle()
                                .stroke(AGPalette.tabBarBackground(colorScheme), lineWidth: 1.5)
                        )
                }
                .offset(x: 0, y: 0)
            }
        }
    }

    @ViewBuilder
    private func countPill(count: Int, fill: Color) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, count > 9 ? 4.5 : 0)
            .frame(minWidth: 15, minHeight: 15)
            .background(Capsule().fill(fill))
            .overlay(
                Capsule()
                    .stroke(AGPalette.tabBarBackground(colorScheme), lineWidth: 1.4)
            )
    }
}

/// Compact 4-segment pure-SVG switcher used at the top of the iPad split-view sidebar.
public struct AGCompactSidebarTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding public var selectedTab: AGMainTab
    public let actionRequiredCount: Int
    public let runningHubCount: Int

    public init(
        selectedTab: Binding<AGMainTab>,
        actionRequiredCount: Int = 0,
        runningHubCount: Int = 0
    ) {
        self._selectedTab = selectedTab
        self.actionRequiredCount = actionRequiredCount
        self.runningHubCount = runningHubCount
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(AGMainTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        AGLinearIcon(
                            tab.iconKind,
                            size: 13.5,
                            color: isSelected ? AGPalette.accentText(colorScheme) : AGPalette.textSecondary(colorScheme),
                            lineWidth: 1.9
                        )
                        Text(tab.title)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? AGPalette.textPrimary(colorScheme) : AGPalette.textSecondary(colorScheme))
                            .lineLimit(1)
                        if tab == .sessions && actionRequiredCount > 0 {
                            Circle()
                                .fill(AGPalette.amberFill(colorScheme))
                                .frame(width: 6, height: 6)
                        } else if tab == .hub && runningHubCount > 0 {
                            Circle()
                                .fill(AGPalette.accentFill(colorScheme))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isSelected ? AGPalette.cardBackground(colorScheme) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(isSelected ? AGPalette.border(colorScheme) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3.5)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AGPalette.recessedWell(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(AGPalette.borderSubtle(colorScheme), lineWidth: 1)
        )
    }
}

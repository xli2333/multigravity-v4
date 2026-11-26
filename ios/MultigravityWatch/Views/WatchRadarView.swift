import Foundation
import SwiftUI

struct WatchRadarScreen: View {
    @Binding var deepLinkedCascadeId: String?
    @State private var store = WatchSessionStore.shared
    @State private var navPath: [String] = []

    var body: some View {
        let palette = store.palette
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    headerStatusPill(palette: palette)

                    if let env = store.effectiveEnvelope, env.isPaired {
                        if env.conversations.isEmpty {
                            emptyPairedCard(palette: palette)
                        } else {
                            ForEach(env.conversations) { item in
                                NavigationLink(value: item.id) {
                                    WatchTaskCard(item: item, palette: palette)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if store.isLocalPreviewMode {
                            Button {
                                store.isLocalPreviewMode = false
                            } label: {
                                Text(String(localized: "退出演示模式"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(palette.secondaryFg)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(palette.recessedBg)
                                    )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                    } else {
                        unpairedWelcomeCard(palette: palette)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 10)
            }
            .navigationTitle("Multigravity")
            .navigationBarTitleDisplayMode(.inline)
            .containerBackground(for: .navigation) {
                WatchCanvasBackground(palette: palette, statusTint: topAmbientTint(palette: palette))
            }
            .navigationDestination(for: String.self) { cascadeId in
                WatchConversationDetailScreen(cascadeId: cascadeId)
            }
        }
        .onChange(of: deepLinkedCascadeId) { _, target in
            guard let target, !target.isEmpty else { return }
            navPath = [target]
            deepLinkedCascadeId = nil
        }
    }

    private func topAmbientTint(palette: WatchPalette) -> Color? {
        guard let env = store.effectiveEnvelope, env.isPaired else { return nil }
        if env.pendingActionCount > 0 { return palette.amberFill }
        if env.runningCount > 0 { return palette.geminiFill }
        return nil
    }

    @ViewBuilder
    private func headerStatusPill(palette: WatchPalette) -> some View {
        let env = store.effectiveEnvelope
        let pendingCount = env?.pendingActionCount ?? 0
        let runningCount = env?.runningCount ?? 0

        HStack(spacing: 6) {
            if pendingCount > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(palette.amberFill)
                        .frame(width: 6, height: 6)
                    Text(String(localized: "\(pendingCount) 待确认"))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.amberText)
                }
            }

            if runningCount > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(palette.geminiFill)
                        .frame(width: 6, height: 6)
                    Text(String(localized: "\(runningCount) 运行中"))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.geminiText)
                }
            }

            if pendingCount == 0 && runningCount == 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(store.isReachable || store.isLocalPreviewMode ? palette.emeraldFill : palette.mutedFg)
                        .frame(width: 6, height: 6)
                    Text(env?.isPaired == true ? String(localized: "已就绪") : String(localized: "等待同步"))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.secondaryFg)
                }
            }

            Spacer(minLength: 2)

            Button {
                Task { await store.refreshSnapshot() }
            } label: {
                Group {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(palette.secondaryFg)
                    }
                }
                .frame(width: 22, height: 22)
                .background(Circle().fill(palette.recessedBg))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(palette.cardBg)
                .overlay(Capsule().stroke(palette.cardBorder, lineWidth: 1))
        )
    }

    @ViewBuilder
    private func emptyPairedCard(palette: WatchPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.emeraldFill)
                Text(String(localized: "暂无活跃任务"))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(palette.primaryFg)
            }
            Text(String(localized: "当桌面端启动任务或需要审批时，手表会自动同步状态。左滑可查看实时模型额度。"))
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondaryFg)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.cardBorder, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func unpairedWelcomeCard(palette: WatchPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "通过 iPhone 自动连接"))
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(palette.primaryFg)

            Text(String(localized: "在 iPhone 打开 Multigravity 后即可自动同步任务进度与模型额度，无需在手表扫码。"))
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondaryFg)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                store.isLocalPreviewMode = true
            } label: {
                Text(String(localized: "预览手表交互示例"))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7.5)
                    .background(Capsule().fill(palette.geminiFill))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.cardBorder, lineWidth: 1)
                )
        )
    }
}

struct WatchTaskCard: View {
    let item: WatchConversationSummary
    let palette: WatchPalette

    private var statusMeta: (label: String, icon: String, fg: Color, bg: Color, border: Color) {
        switch item.status {
        case .action:
            return (
                String(localized: "需要审批"),
                "exclamationmark.circle.fill",
                palette.amberText,
                palette.amberCardBg,
                palette.amberCardBorder
            )
        case .running:
            return (
                String(localized: "运行中"),
                "terminal.fill",
                palette.geminiText,
                palette.cardBg,
                palette.geminiFill.opacity(0.40)
            )
        case .error:
            return (
                String(localized: "执行异常"),
                "xmark.circle.fill",
                palette.roseText,
                palette.cardBg,
                palette.roseBorder
            )
        case .completed:
            return (
                String(localized: "已完成"),
                "checkmark.circle.fill",
                palette.emeraldText,
                palette.cardBg,
                palette.cardBorder
            )
        case .idle:
            return (
                item.displayWorkspace,
                item.isUnread ? "circle.fill" : "folder",
                item.isUnread ? palette.geminiText : palette.mutedFg,
                palette.cardBg,
                palette.cardBorder
            )
        }
    }

    var body: some View {
        let meta = statusMeta
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: meta.icon)
                    .font(.system(size: item.status == .idle && item.isUnread ? 7 : 10, weight: .bold))
                    .foregroundStyle(meta.fg)

                Text(meta.label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(meta.fg)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if item.stepCount > 0 && (item.status == .action || item.status == .running) {
                    Text("#\(item.stepCount)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.mutedFg)
                } else if let mod = item.lastModified {
                    Text(mod, style: .relative)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(palette.mutedFg)
                        .lineLimit(1)
                }
            }

            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.primaryFg)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let snippet = item.latestAction, !snippet.isEmpty {
                Text(snippet)
                    .font(.system(size: 10, weight: .regular, design: item.status == .action ? .monospaced : .default))
                    .foregroundStyle(item.status == .action ? meta.fg : palette.secondaryFg)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(meta.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(meta.border, lineWidth: 1)
                )
        )
    }
}

struct WatchCanvasBackground: View {
    let palette: WatchPalette
    var statusTint: Color? = nil

    var body: some View {
        ZStack {
            palette.canvasBg
            if let tint = statusTint {
                RadialGradient(
                    colors: [
                        tint.opacity(palette.isDark ? 0.22 : 0.10),
                        Color.clear
                    ],
                    center: .top,
                    startRadius: 4,
                    endRadius: 110
                )
            }
        }
        .ignoresSafeArea()
    }
}

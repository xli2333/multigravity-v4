import SwiftUI

// MARK: - Artifact Preview & In-Place Plan Decision Card (v4.0 Zero-Emoji Vector Design)

public struct ArtifactPreviewCardView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    public let artifact: ArtifactItem
    public var canProceed: Bool = false
    public var onProceed: (() -> Void)? = nil

    public init(
        artifact: ArtifactItem,
        canProceed: Bool = false,
        onProceed: (() -> Void)? = nil
    ) {
        self.artifact = artifact
        self.canProceed = canProceed
        self.onProceed = onProceed
    }

    private var isPlanArtifact: Bool {
        let lower = (artifact.uri + " " + artifact.title).lowercased()
        return lower.contains("implementation_plan") || lower.contains("plan")
    }

    private func openArtifactDocument() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let url = URL(string: artifact.uri) {
            openURL(url)
        }
    }

    public var body: some View {
        let p = AGPalette(colorScheme)
        let isVideo = isVideoURL(artifact.uri) || isVideoURL(artifact.title)
        let showInPlaceProceed = canProceed && onProceed != nil && isPlanArtifact

        VStack(alignment: .leading, spacing: 8) {
            Button(action: openArtifactDocument) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 7) {
                        AGLinearIcon(
                            isVideo ? .video : .fileText,
                            size: 15,
                            color: showInPlaceProceed ? p.accentText : p.ink2,
                            lineWidth: 2.0
                        )

                        Text(artifact.title.isEmpty ? String(localized: "文档详情") : artifact.title)
                            .font(.system(size: 13.5, weight: .bold, design: isPlanArtifact ? .monospaced : .default))
                            .foregroundColor(showInPlaceProceed ? p.accentText : p.ink1)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if showInPlaceProceed {
                            AGBadge(String(localized: "待审阅放行"), tone: .blue)
                        } else if isVideo {
                            AGBadge(String(localized: "MP4 视频"), tone: .zinc)
                        } else {
                            AGLinearIcon(.chevronRight, size: 12, color: p.ink3)
                        }
                    }

                    if let summary = artifact.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundColor(p.ink2)
                            .lineSpacing(2.2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(ArtifactCardButtonStyle())

            if showInPlaceProceed, let onProceed {
                HStack(spacing: 8) {
                    Button(action: openArtifactDocument) {
                        Text("阅读全文 / 查找")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(p.ink1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 8.5, style: .continuous).fill(p.card))
                            .overlay(RoundedRectangle(cornerRadius: 8.5, style: .continuous).stroke(p.borderCard, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onProceed()
                    } label: {
                        HStack(spacing: 5) {
                            AGLinearIcon(.play, size: 11, color: .white, lineWidth: 2.2)
                            Text("批准并执行 (Proceed)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 8.5, style: .continuous).fill(p.accentFill))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    showInPlaceProceed
                        ? LinearGradient(
                            colors: [p.accentSoft, p.card],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        : LinearGradient(
                            colors: [p.card, p.card],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(showInPlaceProceed ? p.accentBorder : p.borderCard, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct ArtifactCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

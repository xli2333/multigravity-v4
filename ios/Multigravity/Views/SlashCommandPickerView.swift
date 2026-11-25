import SwiftUI

public struct SlashCommandShape: Shape {
    public let iconKey: String

    public func path(in rect: CGRect) -> Path {
        let cgPath = SlashCommandIconCatalog.cachedCGPath(for: iconKey)
        let scale = min(rect.width, rect.height) / 960.0
        var transform = CGAffineTransform(scaleX: scale, y: scale)
        let offsetX = (rect.width - 960.0 * scale) / 2.0
        let offsetY = (rect.height - 960.0 * scale) / 2.0
        transform = transform.concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
        if let transformed = cgPath.copy(using: &transform) {
            return Path(transformed)
        }
        return Path()
    }
}

public struct SlashCommandIconView: View {
    public let name: String
    public var icon: String? = nil
    public var kind: String? = nil
    public var size: CGFloat = 16

    public init(name: String, icon: String? = nil, kind: String? = nil, size: CGFloat = 16) {
        self.name = name
        self.icon = icon
        self.kind = kind
        self.size = size
    }

    public var body: some View {
        let key = SlashCommandIconCatalog.resolveIcon(name: name, icon: icon, kind: kind)
        if key == "swarm_bee" {
            SwarmPixelBeeSpriteView(
                name: "coordinator",
                pose: .landed,
                width: size * 1.22,
                height: size
            )
        } else {
            SlashCommandShape(iconKey: key)
                .fill(style: FillStyle(eoFill: false))
                .frame(width: size, height: size)
        }
    }
}

public enum SlashCommandTextRenderer {
    public static func render(
        text: String,
        mentions: [SlashCommandMention] = [],
        availableCommands: [SlashCommandOption] = [],
        iconColor: UIColor = .white,
        iconSize: CGFloat = 15,
        enableSkillLinks: Bool = false
    ) -> Text {
        let segments = SlashCommandTextTokenizer.tokenize(
            text: text,
            mentions: mentions,
            availableCommands: availableCommands
        )
        guard !segments.isEmpty else { return Text(text) }

        var result = Text("")
        for seg in segments {
            switch seg {
            case .text(let str):
                result = result + Text(str)
            case .slash(let mention):
                let iconKey = SlashCommandIconCatalog.resolveIcon(name: mention.name, icon: mention.icon, kind: mention.kind)
                let iconText: Text = {
                    if iconKey == "swarm_bee" {
                        let beeImg = SwarmPixelBeeInlineIcon.cachedImage(height: iconSize + 1)
                        return Text(Image(uiImage: beeImg)).baselineOffset(-2.0)
                    } else {
                        let img = SlashCommandIconCatalog.cachedImage(iconKey: iconKey, size: iconSize, color: iconColor)
                        return Text(Image(uiImage: img)).baselineOffset(-1.5)
                    }
                }()
                if enableSkillLinks,
                   let defPath = mention.definitionPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !defPath.isEmpty {
                    var attr = AttributedString(" \(mention.name)")
                    attr.link = URL(fileURLWithPath: defPath)
                    result = result + iconText + Text(attr).fontWeight(.semibold)
                } else {
                    let nameText = Text(verbatim: " \(mention.name)").fontWeight(.semibold)
                    result = result + iconText + nameText
                }
            }
        }
        return result
    }
}

/// 输入框里键入 "/" 后浮在会话界面底部的命令气泡弹窗（系统命令 + 技能），与桌面端的斜杠菜单同源。
struct SlashCommandPickerView: View {
    @Environment(\.colorScheme) private var colorScheme
    let commands: [SlashCommandOption]
    let isLoading: Bool
    var maxListHeight: CGFloat = 280
    let onSelect: (SlashCommandOption) -> Void
    let onDismiss: () -> Void

    @State private var contentHeight: CGFloat = 0

    private var effectiveListHeight: CGFloat {
        let fallback = CGFloat(max(commands.count, 1)) * 66
        let measured = contentHeight > 0 ? contentHeight : fallback
        return min(measured, max(maxListHeight, 150))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部标题栏 + 右上角关闭按钮
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AGPalette.accentSoft(colorScheme))
                        .frame(width: 24, height: 24)
                    Text("/")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(AGPalette.accentText(colorScheme))
                }

                Text("斜杠命令与技能")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(AGPalette.textPrimary(colorScheme))

                if !commands.isEmpty {
                    Text("\(commands.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AGPalette.accentText(colorScheme))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(AGPalette.accentSoft(colorScheme))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 8)

                Button(action: onDismiss) {
                    AGLinearIcon(.close, size: 12, color: AGPalette.textSecondary(colorScheme), lineWidth: 2.1)
                        .frame(width: 26, height: 26)
                        .background(AGPalette.recessedWell(colorScheme))
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭斜杠命令气泡")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle()
                .fill(AGPalette.borderSubtle(colorScheme))
                .frame(height: 0.75)

            if commands.isEmpty {
                HStack(spacing: 10) {
                    if isLoading { ProgressView().scaleEffect(0.85) }
                    Text(isLoading ? String(localized: "正在读取命令与技能...") : String(localized: "没有匹配的命令或技能"))
                        .font(.system(size: 13.5))
                        .foregroundColor(AGPalette.textSecondary(colorScheme))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onSelect(command)
                            } label: {
                                row(command)
                            }
                            .buttonStyle(.plain)

                            if index < commands.count - 1 {
                                Rectangle()
                                    .fill(AGPalette.borderSubtle(colorScheme))
                                    .frame(height: 0.75)
                                    .padding(.leading, 56)
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

    private func row(_ command: SlashCommandOption) -> some View {
        let isSkill = (command.kind == "skill")
        let textColor = isSkill ? AGPalette.violetText(colorScheme) : AGPalette.accentText(colorScheme)
        let softBg = isSkill ? AGPalette.violetSoft(colorScheme) : AGPalette.accentSoft(colorScheme)

        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(softBg)
                    .frame(width: 32, height: 32)
                SlashCommandIconView(name: command.name, icon: command.icon, kind: command.kind, size: 16)
                    .foregroundColor(textColor)
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("/\(command.name)")
                        .font(.system(size: 14.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(AGPalette.textPrimary(colorScheme))
                        .lineLimit(1)

                    Text(isSkill ? String(localized: "技能") : String(localized: "系统"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(textColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(softBg)
                        .clipShape(Capsule())
                }

                let summary = command.description.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
                if !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12.5))
                        .foregroundColor(AGPalette.textSecondary(colorScheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// 已选中的命令标签：与模型胶囊同风格，右上角带小叉，发送时随消息一起带上。
struct SlashCommandChipView: View {
    @Environment(\.colorScheme) private var colorScheme
    let command: SlashCommandOption
    let onClear: () -> Void

    var body: some View {
        let isSkill = (command.kind == "skill")
        let textColor = isSkill ? AGPalette.violetText(colorScheme) : AGPalette.accentText(colorScheme)
        let softBg = isSkill ? AGPalette.violetSoft(colorScheme) : AGPalette.accentSoft(colorScheme)
        let borderColor = (isSkill ? AGPalette.violetFill(colorScheme) : AGPalette.accentFill(colorScheme)).opacity(0.42)

        Button(action: onClear) {
            HStack(spacing: 5) {
                SlashCommandIconView(name: command.name, icon: command.icon, kind: command.kind, size: 13.5)
                Text(command.name)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundColor(textColor)
            .padding(.horizontal, 10.5)
            .frame(height: 29)
            .background(softBg)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(AGPalette.cardBackground(colorScheme))
                        .frame(width: 15, height: 15)
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.white, isSkill ? AGPalette.violetFill(colorScheme) : AGPalette.accentFill(colorScheme))
                }
                .offset(x: 5, y: -5)
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, 4)
        .accessibilityLabel("移除命令 \(command.name)")
    }
}

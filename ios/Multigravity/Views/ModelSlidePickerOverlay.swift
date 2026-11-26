import SwiftUI
import UIKit

public struct ModelPickerRow: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let providerKind: ModelProviderKind
    public let isGroupStart: Bool
    /// Ordered from Low (index 0, leftmost) -> Medium -> High -> Extra (rightmost).
    public let variantsOrdered: [ModelVariant]
    public let defaultVariantIndex: Int
    public let hasEffortTiers: Bool
    public let badgeTag: String?
}

@MainActor
@Observable
public final class ModelSlidePickerState {
    public var isPresented: Bool = false
    public var isInteractiveTapMode: Bool = false
    public var anchorRect: CGRect = .zero
    public var containerSize: CGSize = .zero
    public var providerKind: ModelProviderKind = .gemini
    public var rows: [ModelPickerRow] = []
    public var selectedRowIndex: Int = 0
    public var selectedVariantIndex: Int = 0
    public var hoveredRowIndex: Int? = nil
    public var hasEnteredMenu: Bool = false
    public var activeModelID: String = ""

    private let selectionHaptic = UISelectionFeedbackGenerator()
    private let stepImpactHaptic = UIImpactFeedbackGenerator(style: .rigid)

    public enum Layout {
        static let defaultRowHeight: CGFloat = 35
        static let compactRowHeight: CGFloat = 31
        static let minRowHeight: CGFloat = 27
        static let defaultRowSpacing: CGFloat = 3
        static let compactRowSpacing: CGFloat = 2
        static let cardPadding: CGFloat = 7
        static let cardMinWidth: CGFloat = 264
        static let cardMaxWidth: CGFloat = 304
        static let sliderSectionHeight: CGFloat = 74
        static let gapBetweenButtonAndMenu: CGFloat = 8
        static let horizontalMargin: CGFloat = 12
        static let topSafeMargin: CGFloat = 12
    }

    public init() {}

    /// 打开统一模型 + 推理等级面板（对齐桌面美化插件卡片：顶部模型列表 + 底部丝滑渐变推理等级滑轨）。
    public func open(activeModel: String, interactive: Bool = false) {
        let families = ModelCatalogStore.shared.modelFamilies()
        var builtRows: [ModelPickerRow] = []
        var prevProvider: ModelProviderKind? = nil

        for family in families {
            let kind = ModelDefaultsLogic.providerKind(forID: family.variants.first?.id ?? family.provider)
            let isFirstInGroup = prevProvider != nil && prevProvider != kind

            if !family.hasEffortVariants && family.variants.count > 1 {
                for (vIndex, variant) in family.variants.enumerated() {
                    let displayTitle = variant.rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                    builtRows.append(
                        ModelPickerRow(
                            id: variant.id,
                            title: displayTitle.isEmpty ? family.name : displayTitle,
                            providerKind: kind,
                            isGroupStart: vIndex == 0 ? isFirstInGroup : false,
                            variantsOrdered: [variant],
                            defaultVariantIndex: 0,
                            hasEffortTiers: false,
                            badgeTag: variant.tag
                        )
                    )
                }
            } else {
                let ordered = family.variantsTopToBottom
                let familyTag = ordered.compactMap(\.tag).first(where: { !$0.isEmpty })
                builtRows.append(
                    ModelPickerRow(
                        id: family.id,
                        title: family.name,
                        providerKind: kind,
                        isGroupStart: isFirstInGroup,
                        variantsOrdered: ordered,
                        defaultVariantIndex: family.defaultVariantIndexTopToBottom,
                        hasEffortTiers: family.hasEffortVariants && ordered.count > 1,
                        badgeTag: familyTag
                    )
                )
            }
            prevProvider = kind
        }
        guard !builtRows.isEmpty else { return }

        var matchedRowIdx = 0
        var matchedVarIdx = 0
        for (rIdx, row) in builtRows.enumerated() {
            if let vIdx = row.variantsOrdered.firstIndex(where: {
                $0.id.caseInsensitiveCompare(activeModel) == .orderedSame
            }) {
                matchedRowIdx = rIdx
                matchedVarIdx = vIdx
                break
            }
        }
        if !builtRows[matchedRowIdx].variantsOrdered.indices.contains(matchedVarIdx) {
            matchedVarIdx = min(max(0, builtRows[matchedRowIdx].defaultVariantIndex), max(0, builtRows[matchedRowIdx].variantsOrdered.count - 1))
        }

        self.providerKind = ModelDefaultsLogic.providerKind(forID: activeModel)
        self.activeModelID = activeModel
        self.rows = builtRows
        self.selectedRowIndex = matchedRowIdx
        self.selectedVariantIndex = matchedVarIdx
        self.hoveredRowIndex = nil
        self.hasEnteredMenu = false
        self.isInteractiveTapMode = interactive
        self.selectionHaptic.prepare()
        self.stepImpactHaptic.prepare()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
            self.isPresented = true
        }
        UIImpactFeedbackGenerator(style: interactive ? .light : .medium).impactOccurred()
    }

    public func dismiss() {
        withAnimation(.easeOut(duration: 0.15)) {
            isPresented = false
        }
        isInteractiveTapMode = false
        hoveredRowIndex = nil
        hasEnteredMenu = false
    }

    public var currentRow: ModelPickerRow? {
        guard rows.indices.contains(selectedRowIndex) else { return rows.first }
        return rows[selectedRowIndex]
    }

    public var currentVariant: ModelVariant? {
        guard let row = currentRow, !row.variantsOrdered.isEmpty else { return nil }
        let idx = min(max(0, selectedVariantIndex), row.variantsOrdered.count - 1)
        return row.variantsOrdered[idx]
    }

    public func triggerStepHaptic() {
        selectionHaptic.selectionChanged()
        stepImpactHaptic.impactOccurred(intensity: 0.55)
        selectionHaptic.prepare()
        stepImpactHaptic.prepare()
    }

    public func selectRow(_ rowIndex: Int, onSelect: (String) -> Void) {
        guard rows.indices.contains(rowIndex) else { return }
        let previousRank = currentVariant?.effortRank
        let targetRow = rows[rowIndex]
        let newVarIdx: Int
        if targetRow.hasEffortTiers, let prevRank = previousRank {
            if let exact = targetRow.variantsOrdered.firstIndex(where: { $0.effortRank == prevRank }) {
                newVarIdx = exact
            } else {
                // Closest available effort rank
                newVarIdx = targetRow.variantsOrdered.enumerated().min(by: { a, b in
                    let da = abs((a.element.effortRank?.rawValue ?? 1) - prevRank.rawValue)
                    let db = abs((b.element.effortRank?.rawValue ?? 1) - prevRank.rawValue)
                    return da < db
                })?.offset ?? targetRow.defaultVariantIndex
            }
        } else {
            newVarIdx = min(max(0, targetRow.defaultVariantIndex), max(0, targetRow.variantsOrdered.count - 1))
        }

        selectedRowIndex = rowIndex
        selectedVariantIndex = newVarIdx
        if targetRow.variantsOrdered.indices.contains(newVarIdx) {
            let chosen = targetRow.variantsOrdered[newVarIdx]
            activeModelID = chosen.id
            providerKind = targetRow.providerKind
            onSelect(chosen.id)
        }
    }

    public func selectVariantIndex(_ variantIndex: Int, onSelect: (String) -> Void) {
        guard let row = currentRow, row.variantsOrdered.indices.contains(variantIndex) else { return }
        guard selectedVariantIndex != variantIndex || activeModelID.caseInsensitiveCompare(row.variantsOrdered[variantIndex].id) != .orderedSame else {
            return
        }
        selectedVariantIndex = variantIndex
        let chosen = row.variantsOrdered[variantIndex]
        activeModelID = chosen.id
        providerKind = row.providerKind
        triggerStepHaptic()
        onSelect(chosen.id)
    }

    // MARK: - Geometry

    private var availableCardHeight: CGFloat {
        if anchorRect.minY > Layout.topSafeMargin + Layout.gapBetweenButtonAndMenu + 140 {
            return anchorRect.minY - Layout.gapBetweenButtonAndMenu - Layout.topSafeMargin
        }
        if containerSize.height > 180 {
            return containerSize.height - Layout.topSafeMargin * 2
        }
        return 460
    }

    public var rowSpacing: CGFloat {
        rows.count > 7 ? Layout.compactRowSpacing : Layout.defaultRowSpacing
    }

    public var rowHeight: CGFloat {
        let count = max(rows.count, 1)
        let preferred = rows.count > 7 ? Layout.compactRowHeight : Layout.defaultRowHeight
        let availableList = availableCardHeight - Layout.sliderSectionHeight - Layout.cardPadding * 2
        let spacingOverhead = CGFloat(max(0, count - 1)) * rowSpacing
        let maxRow = (availableList - spacingOverhead) / CGFloat(count)
        return min(preferred, max(Layout.minRowHeight, floor(maxRow)))
    }

    public var listNaturalHeight: CGFloat {
        let count = max(rows.count, 1)
        return CGFloat(count) * rowHeight + CGFloat(max(0, count - 1)) * rowSpacing
    }

    public var listMaxHeight: CGFloat {
        max(120, availableCardHeight - Layout.sliderSectionHeight - Layout.cardPadding * 2)
    }

    public var listNeedsScroll: Bool {
        listNaturalHeight > listMaxHeight + 1
    }

    public var cardSize: CGSize {
        let listHeight = min(listNaturalHeight, listMaxHeight)
        let totalHeight = listHeight + Layout.sliderSectionHeight + Layout.cardPadding * 2
        let preferredWidth = containerSize.width > 0 ? containerSize.width * 0.76 : 284
        let maxAllowedWidth = containerSize.width > 0
            ? max(Layout.cardMinWidth, containerSize.width - Layout.horizontalMargin * 2)
            : Layout.cardMaxWidth
        let width = min(min(Layout.cardMaxWidth, maxAllowedWidth), max(Layout.cardMinWidth, preferredWidth))
        return CGSize(width: width, height: totalHeight)
    }

    public var cardRect: CGRect {
        let size = cardSize
        let maxLeftX = containerSize.width > 0
            ? max(Layout.horizontalMargin, containerSize.width - size.width - Layout.horizontalMargin)
            : max(Layout.horizontalMargin, anchorRect.minX)
        let minX = min(max(Layout.horizontalMargin, anchorRect.minX), maxLeftX)
        let minY = max(Layout.topSafeMargin, anchorRect.minY - Layout.gapBetweenButtonAndMenu - size.height)
        return CGRect(x: minX, y: minY, width: size.width, height: size.height)
    }

    // MARK: - Continuous 1-Stroke Drag Hit-Testing (from Long-Press on Chip)

    public func updateDrag(at point: CGPoint) {
        guard isPresented, !rows.isEmpty, !isInteractiveTapMode else { return }
        let rect = cardRect
        let listHeight = min(listNaturalHeight, listMaxHeight)
        let listHitRect = CGRect(
            x: rect.minX - 24,
            y: rect.minY - 20,
            width: rect.width + 48,
            height: Layout.cardPadding + listHeight + 8
        )
        if listHitRect.contains(point) {
            hasEnteredMenu = true
            let localY = point.y - (rect.minY + Layout.cardPadding)
            let step = rowHeight + rowSpacing
            let idx = min(max(0, Int(floor(localY / step))), rows.count - 1)
            if hoveredRowIndex != idx {
                hoveredRowIndex = idx
                selectedRowIndex = idx
                let row = rows[idx]
                if row.hasEffortTiers {
                    let curRank = currentVariant?.effortRank
                    if let curRank, let matched = row.variantsOrdered.firstIndex(where: { $0.effortRank == curRank }) {
                        selectedVariantIndex = matched
                    } else {
                        selectedVariantIndex = min(max(0, row.defaultVariantIndex), row.variantsOrdered.count - 1)
                    }
                } else {
                    selectedVariantIndex = 0
                }
                selectionHaptic.selectionChanged()
            }
            return
        }

        // Slider zone hit-testing during 1-stroke drag
        let sliderHitRect = CGRect(
            x: rect.minX - 24,
            y: rect.minY + Layout.cardPadding + listHeight,
            width: rect.width + 48,
            height: Layout.sliderSectionHeight + 16
        )
        if sliderHitRect.contains(point), let row = currentRow, row.hasEffortTiers {
            hasEnteredMenu = true
            let trackInset: CGFloat = 20
            let usable = max(1, rect.width - trackInset * 2)
            let frac = min(max(0, (point.x - (rect.minX + trackInset)) / usable), 1)
            let vIdx = Int((frac * CGFloat(row.variantsOrdered.count - 1)).rounded())
            if selectedVariantIndex != vIdx {
                selectedVariantIndex = vIdx
                triggerStepHaptic()
            }
            return
        }

        if anchorRect.insetBy(dx: -18, dy: -14).contains(point) {
            hoveredRowIndex = nil
            return
        }
    }

    public func endDrag(onSelect: (String) -> Void) {
        guard isPresented else { return }
        if isInteractiveTapMode { return }

        if hasEnteredMenu, let hoveredIdx = hoveredRowIndex, rows.indices.contains(hoveredIdx) {
            let row = rows[hoveredIdx]
            let vIdx = min(max(0, selectedVariantIndex), max(0, row.variantsOrdered.count - 1))
            if row.variantsOrdered.indices.contains(vIdx) {
                let chosen = row.variantsOrdered[vIdx]
                activeModelID = chosen.id
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSelect(chosen.id)
            }
            // Keep open in interactive mode if the model has effort tiers so user can also tweak the slider, or dismiss if single-tier
            hoveredRowIndex = nil
            isInteractiveTapMode = true
            return
        }

        // Finger lifted on chip: stay open in interactive mode so user can tap models & drag slider
        isInteractiveTapMode = true
    }
}

public extension ModelProviderKind {
    /// 厂商专属填充强调色（用于背景高亮与描边）。
    func fillAccentColor(for scheme: ColorScheme) -> Color {
        switch self {
        case .claude: return AGPalette.claudeBrandFill
        case .orchestrator: return AGPalette.violetFill(scheme)
        case .other: return AGPalette.emeraldFill(scheme)
        case .gemini: return AGPalette.geminiBrandFill(scheme)
        }
    }

    /// 厂商专属前景文字色（深色模式下使用 claude cut 抬亮后的 accentText，严禁饱和色直写）。
    func liftedTextColor(for scheme: ColorScheme) -> Color {
        switch self {
        case .claude: return AGPalette.claudeBrandText(scheme)
        case .orchestrator: return AGPalette.violetText(scheme)
        case .other: return AGPalette.emeraldText(scheme)
        case .gemini: return AGPalette.geminiBrandText(scheme)
        }
    }

    /// 兼容旧调用方的默认自适应强调色。
    var accentColor: Color {
        Color(
            uiColor: UIColor { traits in
                let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
                return UIColor(self.liftedTextColor(for: scheme))
            }
        )
    }
}

public struct ModelSlidePickerOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var state: ModelSlidePickerState
    let onSelectModel: (String) -> Void

    private var tierLabelColor: Color {
        colorScheme == .dark
            ? Color(red: 0.54, green: 0.58, blue: 1.00) // Cosmic Indigo-Violet (#8A94FF) matching ref image
            : Color(red: 0.10, green: 0.45, blue: 0.91) // Vibrant Gemini Royal Blue (#1A73E8)
    }

    public var body: some View {
        if state.isPresented {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08)
                            .ignoresSafeArea()
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.dismiss()
                    }

                let rect = state.cardRect
                unifiedPickerCard(size: rect.size)
                    .position(x: rect.midX, y: rect.midY)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .bottomLeading)),
                            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading))
                        )
                    )
            }
            .zIndex(500)
        }
    }

    @ViewBuilder
    private func unifiedPickerCard(size: CGSize) -> some View {
        let listHeight = min(state.listNaturalHeight, state.listMaxHeight)

        VStack(alignment: .leading, spacing: 0) {
            // 1. Model Family List
            let rowsStack = VStack(alignment: .leading, spacing: state.rowSpacing) {
                ForEach(Array(state.rows.enumerated()), id: \.element.id) { index, row in
                    modelRowView(row: row, index: index)
                }
            }

            Group {
                if state.listNeedsScroll {
                    ScrollView(.vertical, showsIndicators: false) {
                        rowsStack
                    }
                } else {
                    rowsStack
                }
            }
            .frame(height: listHeight)

            // 2. Subtle Divider
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07))
                .frame(height: 0.75)
                .padding(.horizontal, 4)
                .padding(.top, 7)
                .padding(.bottom, 7)

            // 3. Gradient Reasoning Effort Slider Section (图1 同款)
            ReasoningEffortSliderSection(
                state: state,
                tierLabelColor: tierLabelColor,
                onSelectModel: onSelectModel
            )
        }
        .padding(ModelSlidePickerState.Layout.cardPadding)
        .frame(width: size.width, height: size.height)
        .background(cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.11) : Color(red: 0.16, green: 0.48, blue: 0.96).opacity(0.18),
                    lineWidth: 1
                )
        )
        .shadow(
            color: colorScheme == .dark ? Color.black.opacity(0.48) : Color(red: 0.10, green: 0.25, blue: 0.55).opacity(0.14),
            radius: 20,
            x: 0,
            y: 8
        )
    }

    @ViewBuilder
    private func modelRowView(row: ModelPickerRow, index: Int) -> some View {
        let isSelectedFamily = state.selectedRowIndex == index
        let isHovered = state.hoveredRowIndex == index
        let isHighlighted = isSelectedFamily || isHovered
        let currentRank = state.currentVariant?.effortRank
        let rowEffortLabel: String? = {
            guard row.hasEffortTiers else { return nil }
            if isSelectedFamily, let cur = state.currentVariant {
                return cur.effortDisplayLabel
            }
            if let currentRank, let matched = row.variantsOrdered.first(where: { $0.effortRank == currentRank }) {
                return matched.effortDisplayLabel
            }
            let defIdx = min(max(0, row.defaultVariantIndex), row.variantsOrdered.count - 1)
            return row.variantsOrdered[defIdx].effortDisplayLabel
        }()

        Button {
            if !row.hasEffortTiers {
                state.selectRow(index, onSelect: onSelectModel)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                state.dismiss()
            } else if state.selectedRowIndex == index {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                state.dismiss()
            } else {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
                    state.selectRow(index, onSelect: onSelectModel)
                }
            }
        } label: {
            HStack(spacing: 7) {
                ModelProviderBrandIcon(
                    modelId: row.variantsOrdered.first?.id ?? row.id,
                    size: 13.5
                )

                Text(row.title)
                    .font(.system(size: state.rowHeight < 30 ? 12.5 : 13.5, weight: isHighlighted ? .semibold : .medium))
                    .foregroundColor(
                        isHighlighted
                            ? (colorScheme == .dark ? .white : Color(red: 0.06, green: 0.09, blue: 0.16))
                            : AGPalette.textPrimary(colorScheme)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if let effortText = rowEffortLabel {
                    Text(effortText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(tierLabelColor)
                        .lineLimit(1)
                }

                if let tag = row.badgeTag, !tag.isEmpty {
                    Text(tag)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : AGPalette.textSecondary(colorScheme))
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                        )
                        .overlay(
                            Capsule()
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.6)
                        )
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isSelectedFamily {
                    AGLinearIcon(
                        .check,
                        size: 11.5,
                        color: colorScheme == .dark ? Color.white.opacity(0.92) : tierLabelColor,
                        lineWidth: 2.2
                    )
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: state.rowHeight)
            .background(rowHighlightFill(isHighlighted: isHighlighted))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(rowHighlightStroke(isHighlighted: isHighlighted), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if row.isGroupStart {
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.07) : AGPalette.borderSubtle(colorScheme))
                    .frame(height: 0.75)
                    .padding(.horizontal, 6)
                    .offset(y: -(state.rowSpacing / 2))
            }
        }
    }

    private var cardSurface: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.115, green: 0.12, blue: 0.16),
                        Color(red: 0.095, green: 0.10, blue: 0.135)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color.white,
                        Color(red: 0.975, green: 0.985, blue: 1.00)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private func rowHighlightFill(isHighlighted: Bool) -> Color {
        guard isHighlighted else { return .clear }
        return colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color(red: 0.16, green: 0.48, blue: 0.96).opacity(0.10)
    }

    private func rowHighlightStroke(isHighlighted: Bool) -> Color {
        guard isHighlighted else { return .clear }
        return colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color(red: 0.16, green: 0.48, blue: 0.96).opacity(0.24)
    }
}

/// 图1 同款丝滑渐变推理等级滑块：
/// - 深色模式：宇宙蓝紫发光渐变 + 微星尘高光粒子 + 纯白发光滑块
/// - 浅色模式：Google Gemini 蓝彩渐变 + 微光粒子 + 纯白立体滑块
/// - 交互：120Hz 跟手无级拖拽，跨档位瞬时触发清脆震动反馈，松手弹簧吸附
private struct ReasoningEffortSliderSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var state: ModelSlidePickerState
    let tierLabelColor: Color
    let onSelectModel: (String) -> Void

    @State private var dragFraction: CGFloat? = nil
    @State private var isDragging: Bool = false

    private var activeRow: ModelPickerRow? { state.currentRow }
    private var variants: [ModelVariant] { activeRow?.variantsOrdered ?? [] }
    private var isAdjustable: Bool { (activeRow?.hasEffortTiers == true) && variants.count > 1 }

    private var currentEffortTitle: String {
        guard let v = state.currentVariant else { return "Auto" }
        return activeRow?.hasEffortTiers == true ? v.effortDisplayLabel : String(localized: "默认")
    }

    private var snappedFraction: CGFloat {
        guard isAdjustable, variants.count > 1 else { return 1.0 }
        let clamped = min(max(0, state.selectedVariantIndex), variants.count - 1)
        return CGFloat(clamped) / CGFloat(variants.count - 1)
    }

    private var effectiveFraction: CGFloat {
        dragFraction ?? snappedFraction
    }

    private var activeGradient: LinearGradient {
        if colorScheme == .dark {
            // 图1 同款宇宙星云蓝紫渐变
            return LinearGradient(
                colors: [
                    Color(red: 0.29, green: 0.42, blue: 0.96), // #4A6BF5
                    Color(red: 0.51, green: 0.38, blue: 0.98), // #8261FA
                    Color(red: 0.74, green: 0.45, blue: 1.00)  // #BD73FF
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            // 白天模式：鲜亮 Google Gemini 蓝渐变
            return LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.41, blue: 0.89), // #1769E3
                    Color(red: 0.26, green: 0.52, blue: 0.96), // #4285F4 (Gemini Core Blue)
                    Color(red: 0.44, green: 0.70, blue: 1.00)  // #70B3FF (Gemini Sky Highlight)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var trackBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.165, green: 0.17, blue: 0.225)
            : Color(red: 0.89, green: 0.935, blue: 0.995)
    }

    private var glowColor: Color {
        colorScheme == .dark
            ? Color(red: 0.64, green: 0.44, blue: 1.00).opacity(isDragging ? 0.58 : 0.42)
            : Color(red: 0.20, green: 0.50, blue: 0.96).opacity(isDragging ? 0.42 : 0.28)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("推理等级")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.72) : Color(red: 0.30, green: 0.35, blue: 0.44))

                Spacer()

                Text(currentEffortTitle)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(tierLabelColor)
                    .contentTransition(.interpolate)
                    .animation(.easeOut(duration: 0.15), value: currentEffortTitle)
            }
            .padding(.horizontal, 5)

            GeometryReader { geo in
                let trackHeight: CGFloat = 30
                let thumbSize: CGFloat = 22
                let inset: CGFloat = trackHeight / 2 // 15pt so thumb centers cleanly inside capsule ends
                let totalWidth = max(trackHeight, geo.size.width)
                let usableWidth = max(1, totalWidth - inset * 2)
                let thumbCenterX = inset + effectiveFraction * usableWidth
                let fillWidth = min(totalWidth, max(trackHeight, thumbCenterX + inset))

                ZStack(alignment: .leading) {
                    // 1. Recessed Pill Track
                    Capsule(style: .continuous)
                        .fill(trackBackground)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(
                                    colorScheme == .dark
                                        ? Color.white.opacity(0.08)
                                        : Color(red: 0.16, green: 0.48, blue: 0.96).opacity(0.16),
                                    lineWidth: 1
                                )
                        )

                    // 2. Discrete Tier Stop Dots
                    if isAdjustable {
                        ForEach(0..<variants.count, id: \.self) { idx in
                            let stopX = inset + (CGFloat(idx) / CGFloat(max(1, variants.count - 1))) * usableWidth
                            Circle()
                                .fill(
                                    colorScheme == .dark
                                        ? Color.white.opacity(0.28)
                                        : Color(red: 0.12, green: 0.42, blue: 0.88).opacity(0.30)
                                )
                                .frame(width: 4, height: 4)
                                .position(x: stopX, y: trackHeight / 2)
                        }
                    }

                    // 3. Active Gradient Fill + Starry Sparkles (matching ref image)
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(activeGradient)

                        SliderSparkleOverlay(width: fillWidth, height: trackHeight)
                    }
                    .frame(width: fillWidth, height: trackHeight)
                    .clipShape(Capsule(style: .continuous))
                    .shadow(color: glowColor, radius: isDragging ? 9 : 6, x: 0, y: 2)
                    .opacity(isAdjustable ? 1.0 : 0.65)

                    // 4. Crisp Luminous White Thumb Knob
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(
                            color: colorScheme == .dark
                                ? Color(red: 0.72, green: 0.50, blue: 1.00).opacity(0.65)
                                : Color(red: 0.10, green: 0.36, blue: 0.82).opacity(0.32),
                            radius: isDragging ? 7 : 4,
                            x: 0,
                            y: 1.5
                        )
                        .scaleEffect(isDragging ? 1.10 : 1.0)
                        .position(x: thumbCenterX, y: trackHeight / 2)
                        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.78), value: isDragging)
                }
                .frame(width: totalWidth, height: trackHeight)
                .contentShape(Rectangle().inset(by: -6))
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isAdjustable, variants.count > 1 else { return }
                            if !isDragging {
                                isDragging = true
                            }
                            let raw = (value.location.x - inset) / usableWidth
                            let clamped = min(max(0, raw), 1)
                            dragFraction = clamped

                            let nearest = Int((clamped * CGFloat(variants.count - 1)).rounded())
                            if nearest != state.selectedVariantIndex {
                                state.selectVariantIndex(nearest, onSelect: onSelectModel)
                            }
                        }
                        .onEnded { value in
                            guard isAdjustable, variants.count > 1 else {
                                isDragging = false
                                dragFraction = nil
                                return
                            }
                            let raw = (value.location.x - inset) / usableWidth
                            let clamped = min(max(0, raw), 1)
                            let nearest = Int((clamped * CGFloat(variants.count - 1)).rounded())
                            if nearest != state.selectedVariantIndex {
                                state.selectVariantIndex(nearest, onSelect: onSelectModel)
                            }
                            isDragging = false
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.80)) {
                                dragFraction = nil
                            }
                        }
                )
            }
            .frame(height: 30)
            .padding(.horizontal, 3)
        }
        .padding(.bottom, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("推理等级")
        .accessibilityValue(currentEffortTitle)
        .accessibilityAdjustableAction { direction in
            guard isAdjustable, variants.count > 1 else { return }
            switch direction {
            case .increment:
                let next = min(variants.count - 1, state.selectedVariantIndex + 1)
                state.selectVariantIndex(next, onSelect: onSelectModel)
            case .decrement:
                let prev = max(0, state.selectedVariantIndex - 1)
                state.selectVariantIndex(prev, onSelect: onSelectModel)
            @unknown default:
                break
            }
        }
    }
}

/// 滑块渐变填充内的微星尘与四角星光点（纯矢量绘制，0% Emoji）
private struct SliderSparkleOverlay: View {
    let width: CGFloat
    let height: CGFloat

    private static let specks: [(xRatio: CGFloat, yRatio: CGFloat, size: CGFloat, opacity: Double)] = [
        (0.14, 0.34, 2.2, 0.45),
        (0.24, 0.68, 1.8, 0.35),
        (0.36, 0.28, 2.8, 0.62),
        (0.48, 0.72, 2.0, 0.42),
        (0.58, 0.40, 3.2, 0.70),
        (0.69, 0.66, 2.1, 0.50),
        (0.78, 0.30, 2.5, 0.65)
    ]

    var body: some View {
        Canvas { context, size in
            guard size.width > 36 else { return }
            // Soft top sheen highlight
            let sheenRect = CGRect(x: 4, y: 2, width: max(0, size.width - 8), height: size.height * 0.38)
            context.fill(
                Path(roundedRect: sheenRect, cornerRadius: sheenRect.height / 2),
                with: .color(Color.white.opacity(0.12))
            )

            // Subtle starry micro-specks
            for speck in Self.specks {
                let x = speck.xRatio * max(0, size.width - 18) + 8
                guard x < size.width - 16 else { continue }
                let y = speck.yRatio * size.height
                let rect = CGRect(x: x - speck.size / 2, y: y - speck.size / 2, width: speck.size, height: speck.size)
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(speck.opacity)))
            }

            // Crisp 4-point Gemini sparkle near ~42% of active bar
            if size.width > 72 {
                let cx = min(size.width - 26, max(22, size.width * 0.46))
                let cy = size.height * 0.48
                let r: CGFloat = 4.2
                var star = Path()
                star.move(to: CGPoint(x: cx, y: cy - r))
                star.addQuadCurve(to: CGPoint(x: cx + r, y: cy), control: CGPoint(x: cx + 0.8, y: cy - 0.8))
                star.addQuadCurve(to: CGPoint(x: cx, y: cy + r), control: CGPoint(x: cx + 0.8, y: cy + 0.8))
                star.addQuadCurve(to: CGPoint(x: cx - r, y: cy), control: CGPoint(x: cx - 0.8, y: cy + 0.8))
                star.addQuadCurve(to: CGPoint(x: cx, y: cy - r), control: CGPoint(x: cx - 0.8, y: cy - 0.8))
                star.closeSubpath()
                context.fill(star, with: .color(Color.white.opacity(0.72)))
            }
        }
        .allowsHitTesting(false)
    }
}

private enum ModelChipGesturePhase: Equatable {
    case inactive
    case pressing
    case active(CGPoint?)
}

public struct ModelSwitchChipButton: View {
    let displayName: String
    let foregroundColor: Color
    let backgroundColor: Color
    let borderColor: Color
    let providerKind: ModelProviderKind
    let activeModelID: String
    @Bindable var pickerState: ModelSlidePickerState
    let onToggle: () -> Void
    let onSelectModel: (String) -> Void

    @GestureState private var gesturePhase: ModelChipGesturePhase = .inactive

    public init(
        displayName: String,
        foregroundColor: Color,
        backgroundColor: Color,
        borderColor: Color,
        providerKind: ModelProviderKind,
        activeModelID: String,
        pickerState: ModelSlidePickerState,
        onToggle: @escaping () -> Void,
        onSelectModel: @escaping (String) -> Void
    ) {
        self.displayName = displayName
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.providerKind = providerKind
        self.activeModelID = activeModelID
        self.pickerState = pickerState
        self.onToggle = onToggle
        self.onSelectModel = onSelectModel
    }

    public var body: some View {
        let longPressThenDrag = LongPressGesture(minimumDuration: 0.22, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("chatRoot")))
            .updating($gesturePhase) { value, state, _ in
                switch value {
                case .first(true):
                    state = .pressing
                case .second(true, let drag):
                    state = .active(drag?.location)
                default:
                    state = .inactive
                }
            }

        HStack(spacing: 5) {
            ModelProviderBrandIcon(modelId: activeModelID, size: 12.5)
            Text(displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(foregroundColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            AGLinearIcon(.chevronDown, size: 9.5, color: foregroundColor.opacity(0.75), lineWidth: 2.1)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(backgroundColor)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
        .scaleEffect(gesturePhase == .pressing ? 0.96 : 1.0)
        .animation(.easeOut(duration: 0.12), value: gesturePhase == .pressing)
        .contentShape(Capsule())
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("chatRoot"))
        } action: { newRect in
            pickerState.anchorRect = newRect
        }
        .onTapGesture {
            if pickerState.isPresented {
                pickerState.dismiss()
            } else {
                pickerState.open(activeModel: activeModelID, interactive: true)
            }
        }
        .gesture(longPressThenDrag)
        .onChange(of: gesturePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active(let point):
                if !pickerState.isPresented {
                    pickerState.open(activeModel: activeModelID, interactive: false)
                }
                if let point {
                    pickerState.updateDrag(at: point)
                }
            case .inactive:
                if case .active = oldPhase {
                    pickerState.endDrag(onSelect: onSelectModel)
                }
            case .pressing:
                break
            }
        }
        .accessibilityLabel("选择模型与推理等级，当前 \(displayName)")
    }
}

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
    public var maxImpactTrigger: Int = 0
    /// 每个模型家族独立记忆各自的思考等级 variant ID（互不串改，持久化在本地 UserDefaults）。
    public var rememberedVariantIDByRow: [String: String] = [:]

    private static let perFamilyVariantDefaultsKey = "mgy.perFamilySelectedVariantID.v1"

    private let selectionHaptic = UISelectionFeedbackGenerator()
    private let stepImpactHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let maxWallHaptic = UIImpactFeedbackGenerator(style: .heavy)

    public enum Layout {
        static let defaultRowHeight: CGFloat = 35
        static let compactRowHeight: CGFloat = 31
        static let minRowHeight: CGFloat = 27
        static let defaultRowSpacing: CGFloat = 3
        static let compactRowSpacing: CGFloat = 2
        static let cardPadding: CGFloat = 7
        static let cardMinWidth: CGFloat = 268
        static let cardMaxWidth: CGFloat = 308
        static let sliderSectionHeight: CGFloat = 68
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

        var storedMap = (UserDefaults.standard.dictionary(forKey: Self.perFamilyVariantDefaultsKey) as? [String: String]) ?? self.rememberedVariantIDByRow
        let activeRowObj = builtRows[matchedRowIdx]
        if activeRowObj.variantsOrdered.indices.contains(matchedVarIdx) {
            storedMap[activeRowObj.id] = activeRowObj.variantsOrdered[matchedVarIdx].id
            UserDefaults.standard.set(storedMap, forKey: Self.perFamilyVariantDefaultsKey)
        }

        self.rememberedVariantIDByRow = storedMap
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
        self.maxWallHaptic.prepare()
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

    /// 读取指定模型家族独立记忆的档位下标（未手动调整过则回退到该模型自身的默认档位）。
    public func rememberedVariantIndex(for row: ModelPickerRow) -> Int {
        guard !row.variantsOrdered.isEmpty else { return 0 }
        if row.hasEffortTiers, let savedID = rememberedVariantIDByRow[row.id],
           let idx = row.variantsOrdered.firstIndex(where: { $0.id.caseInsensitiveCompare(savedID) == .orderedSame }) {
            return idx
        }
        return min(max(0, row.defaultVariantIndex), row.variantsOrdered.count - 1)
    }

    private func persistRememberedVariant(rowID: String, variantID: String) {
        rememberedVariantIDByRow[rowID] = variantID
        UserDefaults.standard.set(rememberedVariantIDByRow, forKey: Self.perFamilyVariantDefaultsKey)
    }

    public func selectRow(_ rowIndex: Int, onSelect: (String) -> Void) {
        guard rows.indices.contains(rowIndex) else { return }
        let targetRow = rows[rowIndex]
        let newVarIdx = rememberedVariantIndex(for: targetRow)

        selectedRowIndex = rowIndex
        selectedVariantIndex = newVarIdx
        if targetRow.variantsOrdered.indices.contains(newVarIdx) {
            let chosen = targetRow.variantsOrdered[newVarIdx]
            activeModelID = chosen.id
            providerKind = targetRow.providerKind
            if targetRow.hasEffortTiers {
                persistRememberedVariant(rowID: targetRow.id, variantID: chosen.id)
            }
            onSelect(chosen.id)
        }
    }

    public func selectVariantIndex(_ variantIndex: Int, onSelect: (String) -> Void) {
        guard let row = currentRow, row.variantsOrdered.indices.contains(variantIndex) else { return }
        guard selectedVariantIndex != variantIndex || activeModelID.caseInsensitiveCompare(row.variantsOrdered[variantIndex].id) != .orderedSame else {
            return
        }
        let wasMax = selectedVariantIndex == row.variantsOrdered.count - 1
        selectedVariantIndex = variantIndex
        let chosen = row.variantsOrdered[variantIndex]
        activeModelID = chosen.id
        providerKind = row.providerKind
        if row.hasEffortTiers {
            persistRememberedVariant(rowID: row.id, variantID: chosen.id)
        }
        let isNowMax = row.hasEffortTiers && row.variantsOrdered.count > 1 && variantIndex == row.variantsOrdered.count - 1
        if isNowMax && !wasMax {
            selectionHaptic.selectionChanged()
            maxWallHaptic.impactOccurred(intensity: 0.88)
            selectionHaptic.prepare()
            maxWallHaptic.prepare()
            maxImpactTrigger &+= 1
        } else {
            triggerStepHaptic()
        }
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
                selectedVariantIndex = row.hasEffortTiers ? rememberedVariantIndex(for: row) : 0
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
                if row.variantsOrdered.indices.contains(vIdx) {
                    persistRememberedVariant(rowID: row.id, variantID: row.variantsOrdered[vIdx].id)
                }
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

    @State private var cardShakeOffsetX: CGFloat = 0

    private var tierLabelColor: Color {
        colorScheme == .dark
            ? Color(red: 0.53, green: 0.58, blue: 0.98) // Refined Periwinkle-Indigo (#8794FA) matching ref image
            : Color(red: 0.259, green: 0.522, blue: 0.957) // Official Google Gemini Blue (#4285F4)
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
                    .offset(x: cardShakeOffsetX)
                    .position(x: rect.midX, y: rect.midY)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .bottomLeading)),
                            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading))
                        )
                    )
            }
            .zIndex(500)
            .onChange(of: state.maxImpactTrigger) { _, _ in
                triggerCardWallMicroShake()
            }
        }
    }

    private func triggerCardWallMicroShake() {
        Task { @MainActor in
            withAnimation(.linear(duration: 0.036)) { cardShakeOffsetX = 2.4 }
            try? await Task.sleep(nanoseconds: 36_000_000)
            withAnimation(.linear(duration: 0.036)) { cardShakeOffsetX = -2.0 }
            try? await Task.sleep(nanoseconds: 36_000_000)
            withAnimation(.linear(duration: 0.036)) { cardShakeOffsetX = 1.3 }
            try? await Task.sleep(nanoseconds: 36_000_000)
            withAnimation(.linear(duration: 0.036)) { cardShakeOffsetX = -0.6 }
            try? await Task.sleep(nanoseconds: 36_000_000)
            withAnimation(.easeOut(duration: 0.045)) { cardShakeOffsetX = 0 }
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

            // 2. Subtle Spacer before Reasoning Effort Well
            Spacer()
                .frame(height: 6)

            // 3. Mature Multi-Hue Gradient Reasoning Effort Slider Section
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
                    colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06),
                    lineWidth: 0.8
                )
        )
        .shadow(
            color: colorScheme == .dark ? Color.black.opacity(0.52) : Color.black.opacity(0.12),
            radius: 24,
            x: 0,
            y: 10
        )
    }

    @ViewBuilder
    private func modelRowView(row: ModelPickerRow, index: Int) -> some View {
        let isSelectedFamily = state.selectedRowIndex == index
        let isHovered = state.hoveredRowIndex == index
        let isHighlighted = isSelectedFamily || isHovered
        let rowVarIdx: Int = isSelectedFamily
            ? min(max(0, state.selectedVariantIndex), max(0, row.variantsOrdered.count - 1))
            : state.rememberedVariantIndex(for: row)
        let rowEffortLabel: String? = {
            guard row.hasEffortTiers, row.variantsOrdered.indices.contains(rowVarIdx) else { return nil }
            return row.variantsOrdered[rowVarIdx].effortDisplayLabel
        }()
        let rowEffortColor: Color = {
            guard row.hasEffortTiers, row.variantsOrdered.count > 1 else { return tierLabelColor }
            let frac = Double(rowVarIdx) / Double(max(1, row.variantsOrdered.count - 1))
            if colorScheme == .dark {
                return FluidMeshPalette.lerpColor(from: (0.42, 0.56, 0.98), to: (0.76, 0.52, 0.99), t: frac)
            } else {
                return FluidMeshPalette.lerpColor(from: (0.22, 0.52, 0.95), to: (0.50, 0.38, 0.92), t: frac)
            }
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
                        .foregroundColor(rowEffortColor)
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
                        Color(red: 0.098, green: 0.102, blue: 0.133),
                        Color(red: 0.082, green: 0.086, blue: 0.114)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                Color.white
            }
        }
    }

    private func rowHighlightFill(isHighlighted: Bool) -> Color {
        guard isHighlighted else { return .clear }
        return colorScheme == .dark
            ? Color.white.opacity(0.075)
            : Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.048)
    }

    private func rowHighlightStroke(isHighlighted: Bool) -> Color {
        guard isHighlighted else { return .clear }
        return colorScheme == .dark
            ? Color.white.opacity(0.09)
            : Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.055)
    }
}

/// Codex 同款流体水波 + MeshGradient 120Hz 实时流动推理等级滑块：
/// - 内部色彩潜流：3x3 MeshGradient 正弦行波控制点实时涡动，手指拖动越快水流涌动越急促，松手自然阻尼平复
/// - 连续流光与尾迹：105° 折射水波扫光（ces-sweep）+ 拖动速度驱动的水滴分流尾迹线 + 滑块背向弯月面柔光
/// - 22 颗黄金分割微泡/星尘：锚定圆钮中心从右向左沿层流波线连续游动，随档位与拖动速度渐次苏醒加速
/// - 水滴表面张力圆钮 + 满档物理撞墙微震颤与文字光斑绽放
private struct ReasoningEffortSliderSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var state: ModelSlidePickerState
    let tierLabelColor: Color
    let onSelectModel: (String) -> Void

    @State private var dragFraction: CGFloat? = nil
    @State private var isDragging: Bool = false
    @State private var fluidEngine = FluidRibbonEngine()
    @State private var maxLabelBloomOpacity: Double = 0
    @State private var maxLabelBloomScale: CGFloat = 0.7

    private static let trackHeight: CGFloat = 24
    private static let thumbSize: CGFloat = 24
    private static let trackInset: CGFloat = 12

    private var activeRow: ModelPickerRow? { state.currentRow }
    private var variants: [ModelVariant] { activeRow?.variantsOrdered ?? [] }
    private var isAdjustable: Bool { (activeRow?.hasEffortTiers == true) && variants.count > 1 }

    private var isAtMaxTier: Bool {
        isAdjustable && state.selectedVariantIndex == variants.count - 1
    }

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

    private var dynamicTierTextColor: Color {
        guard isAdjustable else { return tierLabelColor }
        let f = Double(effectiveFraction)
        if colorScheme == .dark {
            return FluidMeshPalette.lerpColor(
                from: (0.42, 0.56, 0.98),
                to: (0.76, 0.52, 0.99),
                t: f
            )
        } else {
            return FluidMeshPalette.lerpColor(
                from: (0.22, 0.52, 0.95),
                to: (0.50, 0.38, 0.92),
                t: f
            )
        }
    }

    private var trackBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.145, green: 0.150, blue: 0.192)
            : Color(red: 0.925, green: 0.935, blue: 0.957)
    }

    private var trackStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.045)
    }

    private var wellBackgroundColor: Color {
        if isAtMaxTier {
            return colorScheme == .dark
                ? Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.07)
                : Color(red: 0.26, green: 0.52, blue: 0.96).opacity(0.05)
        }
        return colorScheme == .dark ? Color.white.opacity(0.025) : Color(red: 0.973, green: 0.978, blue: 0.990)
    }

    private var wellBorderColor: Color {
        if isAtMaxTier {
            return colorScheme == .dark
                ? Color(red: 0.62, green: 0.42, blue: 0.98).opacity(0.32)
                : Color(red: 0.36, green: 0.48, blue: 0.96).opacity(0.24)
        }
        return colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.045)
    }

    private var headerTitleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.80) : Color(red: 0.24, green: 0.28, blue: 0.36)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            headerRow

            GeometryReader { geo in
                let totalW = max(Self.trackHeight, geo.size.width)
                TimelineView(.animation) { timeline in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    let sample = fluidEngine.step(
                        now: now,
                        fraction: Double(effectiveFraction),
                        isDragging: isDragging
                    )
                    animatedSliderBody(totalWidth: totalW, sample: sample)
                }
            }
            .frame(height: Self.trackHeight)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(wellBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(wellBorderColor, lineWidth: 0.8)
        )
        .animation(.easeOut(duration: 0.2), value: isAtMaxTier)
        .onChange(of: state.maxImpactTrigger) { _, _ in
            triggerMaxLabelBloom()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("推理等级")
        .accessibilityValue(currentEffortTitle)
        .accessibilityAdjustableAction { direction in
            guard isAdjustable, variants.count > 1 else { return }
            switch direction {
            case .increment:
                let next = min(variants.count - 1, state.selectedVariantIndex + 1)
                withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                    state.selectVariantIndex(next, onSelect: onSelectModel)
                }
            case .decrement:
                let prev = max(0, state.selectedVariantIndex - 1)
                withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                    state.selectVariantIndex(prev, onSelect: onSelectModel)
                }
            @unknown default:
                break
            }
        }
    }

    private func triggerMaxLabelBloom() {
        maxLabelBloomOpacity = 0.95
        maxLabelBloomScale = 0.65
        withAnimation(.easeOut(duration: 0.42)) {
            maxLabelBloomOpacity = 0
            maxLabelBloomScale = 1.55
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center) {
            Text("推理等级")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(headerTitleColor)

            Spacer()

            ZStack {
                if maxLabelBloomOpacity > 0.01 {
                    Capsule()
                        .fill(dynamicTierTextColor.opacity(0.55))
                        .frame(width: 44, height: 18)
                        .blur(radius: 7)
                        .scaleEffect(maxLabelBloomScale)
                        .opacity(maxLabelBloomOpacity)
                }

                Text(currentEffortTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(dynamicTierTextColor)
                    .id(currentEffortTitle)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
            }
            .clipped()
            .animation(.spring(response: 0.26, dampingFraction: 0.80), value: currentEffortTitle)
        }
        .padding(.horizontal, 2)
    }

    private func animatedSliderBody(totalWidth: CGFloat, sample: FluidSample) -> some View {
        let inset = Self.trackInset
        let usableWidth = max(1, totalWidth - inset * 2)
        let thumbCenterX = inset + effectiveFraction * usableWidth
        let activeSpanWidth = max(0, thumbCenterX)
        let breathe = isAtMaxTier ? (0.08 * (0.5 + 0.5 * sin(sample.phase * 1.6))) : 0.0
        let glowOpacity = (colorScheme == .dark ? 0.28 : 0.18) + 0.18 * sample.turbulence + breathe
        let glowHue: Color = colorScheme == .dark
            ? Color(red: 0.58, green: 0.36, blue: 0.96)
            : Color(red: 0.29, green: 0.50, blue: 0.96)

        return ZStack(alignment: .leading) {
            if activeSpanWidth > inset {
                Capsule(style: .continuous)
                    .fill(glowHue.opacity(glowOpacity))
                    .frame(width: min(totalWidth, activeSpanWidth + 6), height: Self.trackHeight - 2)
                    .blur(radius: 7)
                    .offset(y: 2)
            }

            clippedLiquidTrack(
                totalWidth: totalWidth,
                usableWidth: usableWidth,
                activeSpanWidth: activeSpanWidth,
                sample: sample
            )

            dropletKnobView(thumbCenterX: thumbCenterX, sample: sample)
        }
        .frame(width: totalWidth, height: Self.trackHeight)
        .contentShape(Rectangle().inset(by: -8))
        .highPriorityGesture(sliderDragGesture(usableWidth: usableWidth))
    }

    private func clippedLiquidTrack(
        totalWidth: CGFloat,
        usableWidth: CGFloat,
        activeSpanWidth: CGFloat,
        sample: FluidSample
    ) -> some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(trackBackground)

            if isAdjustable {
                tierDotsLayer(usableWidth: usableWidth)
            }

            flowingLiquidFill(activeSpanWidth: activeSpanWidth, sample: sample)
        }
        .frame(width: totalWidth, height: Self.trackHeight)
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(trackStrokeColor, lineWidth: 0.6)
        )
    }

    private func tierDotsLayer(usableWidth: CGFloat) -> some View {
        let count = variants.count
        let denom = CGFloat(max(1, count - 1))
        let isDark = colorScheme == .dark
        return ForEach(0..<count, id: \.self) { idx in
            let frac = CGFloat(idx) / denom
            let stopX = Self.trackInset + frac * usableWidth
            let reached = effectiveFraction + 0.001 >= frac
            let dotOpacity: Double = reached ? 0.55 : (isDark ? 0.18 : 0.22)
            let dotColor: Color = reached
                ? Color.white.opacity(dotOpacity)
                : (isDark ? Color.white.opacity(dotOpacity) : Color(red: 0.39, green: 0.45, blue: 0.55).opacity(dotOpacity))
            Circle()
                .fill(dotColor)
                .frame(width: 3, height: 3)
                .position(x: stopX, y: Self.trackHeight / 2)
        }
    }

    private func flowingLiquidFill(activeSpanWidth: CGFloat, sample: FluidSample) -> some View {
        let isDark = colorScheme == .dark
        let meshPts = FluidMeshPalette.points(phase: sample.phase, turbulence: sample.turbulence)
        let meshCols = FluidMeshPalette.colors(isDark: isDark, fraction: sample.energy)
        let baseGrad = FluidMeshPalette.baseUnderlayGradient(isDark: isDark, fraction: sample.energy)

        return ZStack(alignment: .trailing) {
            Rectangle()
                .fill(baseGrad)

            MeshGradient(
                width: 4,
                height: 3,
                points: meshPts,
                colors: meshCols
            )

            FluidCausticsAndStreamCanvas(
                sample: sample,
                isDark: isDark
            )
        }
        .frame(width: activeSpanWidth, height: Self.trackHeight)
        .opacity(isAdjustable ? 1.0 : 0.65)
    }

    private func dropletKnobView(thumbCenterX: CGFloat, sample: FluidSample) -> some View {
        let isDark = colorScheme == .dark
        let rimColor: Color = isDark ? .clear : Color.black.opacity(0.055)
        let speedStretch = min(0.12, abs(sample.signedVelocity) * 0.045)
        let baseScale: Double = isDragging ? 1.03 : 1.0
        let scaleX = CGFloat(baseScale * (1.0 + speedStretch))
        let scaleY = CGFloat(baseScale / sqrt(1.0 + speedStretch))
        let auraOpacity: Double = (isDragging || isAtMaxTier) ? (isDark ? 0.48 : 0.30) : 0.0
        let auraColor: Color = isDark
            ? Color(red: 0.64, green: 0.40, blue: 0.98).opacity(auraOpacity)
            : Color(red: 0.26, green: 0.52, blue: 0.96).opacity(auraOpacity)
        let contactOpacity: Double = isDark ? 0.38 : 0.16

        return Circle()
            .fill(Color.white)
            .frame(width: Self.thumbSize, height: Self.thumbSize)
            .overlay(
                Circle().stroke(rimColor, lineWidth: 0.5)
            )
            .shadow(color: auraColor, radius: isDragging ? 8 : 5, x: 0, y: 0)
            .shadow(
                color: Color.black.opacity(contactOpacity),
                radius: isDragging ? 4.5 : 3.0,
                x: 1,
                y: 1
            )
            .scaleEffect(x: scaleX, y: scaleY)
            .position(x: thumbCenterX, y: Self.trackHeight / 2)
    }

    private func sliderDragGesture(usableWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isAdjustable, variants.count > 1 else { return }
                let now = Date().timeIntervalSinceReferenceDate
                if !isDragging {
                    isDragging = true
                }
                let raw = (value.location.x - Self.trackInset) / usableWidth
                let clamped = min(max(0, raw), 1)
                dragFraction = clamped
                fluidEngine.recordDragInput(fraction: Double(clamped), now: now)

                let nearest = Int((clamped * CGFloat(variants.count - 1)).rounded())
                if nearest != state.selectedVariantIndex {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.80)) {
                        state.selectVariantIndex(nearest, onSelect: onSelectModel)
                    }
                }
            }
            .onEnded { value in
                guard isAdjustable, variants.count > 1 else {
                    isDragging = false
                    dragFraction = nil
                    fluidEngine.endDrag()
                    return
                }
                let raw = (value.location.x - Self.trackInset) / usableWidth
                let clamped = min(max(0, raw), 1)
                let nearest = Int((clamped * CGFloat(variants.count - 1)).rounded())
                if nearest != state.selectedVariantIndex {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.80)) {
                        state.selectVariantIndex(nearest, onSelect: onSelectModel)
                    }
                }
                isDragging = false
                fluidEngine.endDrag()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                    dragFraction = nil
                }
            }
    }
}

// MARK: - 120Hz Liquid Phase & Velocity Physics Engine

private struct FluidSample {
    let phase: Double
    let sweepPhase: Double
    let turbulence: Double
    let signedVelocity: Double
    let energy: Double
}

@MainActor
private final class FluidRibbonEngine {
    private var lastFrameTime: TimeInterval = 0
    private var phase: Double = 0
    private var sweepPhase: Double = 0
    private var turbulence: Double = 0
    private var signedVelocity: Double = 0

    private var lastInputFraction: Double? = nil
    private var lastInputTime: TimeInterval = 0
    private var rawDragSpeed: Double = 0

    func recordDragInput(fraction: Double, now: TimeInterval) {
        if let prevFrac = lastInputFraction, lastInputTime > 0 {
            let dt = now - lastInputTime
            if dt > 0.0005 && dt < 0.25 {
                let instSpeed = (fraction - prevFrac) / dt
                rawDragSpeed = rawDragSpeed * 0.60 + instSpeed * 0.40
            }
        } else {
            rawDragSpeed = 0
        }
        lastInputFraction = fraction
        lastInputTime = now
    }

    func endDrag() {
        lastInputFraction = nil
        rawDragSpeed = 0
    }

    func step(now: TimeInterval, fraction: Double, isDragging: Bool) -> FluidSample {
        let dt: Double
        if lastFrameTime > 0 {
            dt = min(0.05, max(0, now - lastFrameTime))
        } else {
            dt = 1.0 / 60.0
        }
        lastFrameTime = now

        // Decay finger speed smoothly when finger pauses in place
        if isDragging && lastInputTime > 0 && (now - lastInputTime) > 0.04 {
            rawDragSpeed *= exp(-dt * 12.0)
        } else if !isDragging {
            rawDragSpeed *= exp(-dt * 10.0)
        }

        let targetTurb = isDragging ? min(1.0, 0.24 + abs(rawDragSpeed) * 0.48) : 0.0
        let turbRate = isDragging ? 14.0 : 5.2
        turbulence += (targetTurb - turbulence) * (1.0 - exp(-dt * turbRate))

        signedVelocity += (rawDragSpeed - signedVelocity) * (1.0 - exp(-dt * 13.0))

        let energy = max(0.0, min(1.0, fraction))
        // River current speed scales with effort energy + surges up to 3x while finger stirs the water
        phase += dt * (0.72 + 1.15 * energy + 2.75 * turbulence)
        sweepPhase += dt * (0.30 + 0.38 * energy + 0.82 * turbulence)

        return FluidSample(
            phase: phase,
            sweepPhase: sweepPhase,
            turbulence: turbulence,
            signedVelocity: signedVelocity,
            energy: energy
        )
    }
}

// MARK: - 3x3 MeshGradient Liquid Current Palette

private enum FluidMeshPalette {
    static func lerpColor(
        from a: (Double, Double, Double),
        to b: (Double, Double, Double),
        t: Double
    ) -> Color {
        let u = max(0.0, min(1.0, t))
        return Color(
            red: a.0 + (b.0 - a.0) * u,
            green: a.1 + (b.1 - a.1) * u,
            blue: a.2 + (b.2 - a.2) * u
        )
    }

    static func baseUnderlayGradient(isDark: Bool, fraction: Double) -> LinearGradient {
        let reach = max(0.16, min(1.0, fraction))
        if isDark {
            let start = Color(red: 0.310, green: 0.376, blue: 0.898)
            let mid = lerpColor(from: (0.310, 0.376, 0.898), to: (0.486, 0.349, 0.949), t: reach * 0.75)
            let end = lerpColor(from: (0.310, 0.376, 0.898), to: (0.682, 0.369, 0.973), t: reach)
            return LinearGradient(colors: [start, mid, end], startPoint: .leading, endPoint: .trailing)
        } else {
            let start = Color(red: 0.243, green: 0.541, blue: 0.918)
            let mid = lerpColor(from: (0.243, 0.541, 0.918), to: (0.259, 0.482, 0.953), t: reach * 0.75)
            let end = lerpColor(from: (0.243, 0.541, 0.918), to: (0.490, 0.435, 0.925), t: reach)
            return LinearGradient(colors: [start, mid, end], startPoint: .leading, endPoint: .trailing)
        }
    }

    static func points(phase: Double, turbulence: Double) -> [SIMD2<Float>] {
        let edgeAmp = 0.05 + 0.05 * turbulence
        let waveAmpY = 0.16 + 0.14 * turbulence
        let waveAmpX = 0.045 + 0.055 * turbulence

        // Strictly pin outer perimeter (x=0 on col 0, x=1 on col 3, y=0 on row 0, y=1 on row 2)
        // so Bezier boundaries NEVER bow inward or expose dark wedges at the ends!
        let topX1 = Float(0.33 + sin(phase * 0.85) * edgeAmp)
        let topX2 = Float(0.67 + cos(phase * 0.85) * edgeAmp)
        let botX1 = Float(0.33 - sin(phase * 0.85) * edgeAmp)
        let botX2 = Float(0.67 - cos(phase * 0.85) * edgeAmp)

        // Row 1: col 0 pinned at x=0.0, col 3 pinned at x=1.0; interior cols 1 & 2 swirl freely!
        let p10y = Float(min(0.80, max(0.20, 0.50 + sin(phase * 1.45) * (waveAmpY * 0.75))))

        let p11x = Float(min(0.48, max(0.18, 0.33 + cos(phase * 1.10) * waveAmpX)))
        let p11y = Float(min(0.84, max(0.16, 0.50 + sin(phase * 1.45 - 1.25) * waveAmpY)))

        let p12x = Float(min(0.82, max(0.52, 0.67 + sin(phase * 0.95 + 1.1) * waveAmpX)))
        let p12y = Float(min(0.84, max(0.16, 0.49 + sin(phase * 1.45 - 2.50) * waveAmpY)))

        let p13y = Float(min(0.80, max(0.20, 0.50 + sin(phase * 1.45 - 3.75) * (waveAmpY * 0.75))))

        return [
            SIMD2<Float>(0.0, 0.0), SIMD2<Float>(topX1, 0.0), SIMD2<Float>(topX2, 0.0), SIMD2<Float>(1.0, 0.0),
            SIMD2<Float>(0.0, p10y), SIMD2<Float>(p11x, p11y), SIMD2<Float>(p12x, p12y), SIMD2<Float>(1.0, p13y),
            SIMD2<Float>(0.0, 1.0), SIMD2<Float>(botX1, 1.0), SIMD2<Float>(botX2, 1.0), SIMD2<Float>(1.0, 1.0)
        ]
    }

    static func colors(isDark: Bool, fraction: Double) -> [Color] {
        // Progressive Codex unfolding: calm blue at Low -> multi-hue Gemini/Cosmic nebula at Medium/High
        let reach = max(0.16, min(1.0, fraction))
        let c1Reach = reach * 0.38
        let c2Reach = reach * 0.72

        if isDark {
            let t0 = (0.290, 0.361, 0.886) // #4A5CE2 Periwinkle
            let t1 = (0.439, 0.337, 0.941) // #7056F0 Indigo
            let t2 = (0.635, 0.345, 0.973) // #A258F8 Amethyst

            // Luminous underwater river current in middle row
            let m0 = (0.384, 0.518, 1.000) // #6284FF Electric Periwinkle-Sky
            let m1 = (0.612, 0.463, 1.000) // #9C76FF Luminous Iris Current
            let m2 = (0.831, 0.549, 1.000) // #D48CFF Radiant Orchid Crest

            let b0 = (0.322, 0.345, 0.894) // #5258E4 Deep Slate-Blue
            let b1 = (0.486, 0.329, 0.949) // #7C54F2 Velvet Violet
            let b2 = (0.682, 0.361, 0.965) // #AE5CF6 Rich Orchid

            return [
                lerpColor(from: t0, to: t0, t: 0),
                lerpColor(from: t0, to: t1, t: c1Reach * 1.35),
                lerpColor(from: t1, to: t2, t: c2Reach),
                lerpColor(from: t0, to: t2, t: reach),

                lerpColor(from: m0, to: m0, t: 0),
                lerpColor(from: m0, to: m1, t: c1Reach * 1.35),
                lerpColor(from: m1, to: m2, t: c2Reach),
                lerpColor(from: m0, to: m2, t: reach),

                lerpColor(from: b0, to: b0, t: 0),
                lerpColor(from: b0, to: b1, t: c1Reach * 1.35),
                lerpColor(from: b1, to: b2, t: c2Reach),
                lerpColor(from: b0, to: b2, t: reach)
            ]
        } else {
            // Official Google Gemini Multi-Hue Brand Palette with luminous sky-aqua inner current
            let t0 = (0.243, 0.541, 0.910) // #3E8AE8 Gemini Cerulean
            let t1 = (0.227, 0.463, 0.949) // #3A76F2 Google Gemini Blue
            let t2 = (0.424, 0.424, 0.933) // #6C6CEE Gemini Periwinkle

            // Luminous refractive water current in middle row
            let m0 = (0.424, 0.753, 1.000) // #6CC0FF Crisp Gemini Sky Current
            let m1 = (0.376, 0.620, 1.000) // #609EFF Luminous Azure Current
            let m2 = (0.596, 0.557, 0.988) // #988EFC Soft Gemini Iris Crest

            let b0 = (0.220, 0.502, 0.925) // #3880EC Deep Gemini Blue
            let b1 = (0.282, 0.463, 0.957) // #4876F4 Royal Periwinkle
            let b2 = (0.502, 0.424, 0.910) // #806CE8 Official Gemini Iris

            return [
                lerpColor(from: t0, to: t0, t: 0),
                lerpColor(from: t0, to: t1, t: c1Reach * 1.35),
                lerpColor(from: t1, to: t2, t: c2Reach),
                lerpColor(from: t0, to: t2, t: reach),

                lerpColor(from: m0, to: m0, t: 0),
                lerpColor(from: m0, to: m1, t: c1Reach * 1.35),
                lerpColor(from: m1, to: m2, t: c2Reach),
                lerpColor(from: m0, to: m2, t: reach),

                lerpColor(from: b0, to: b0, t: 0),
                lerpColor(from: b0, to: b1, t: c1Reach * 1.35),
                lerpColor(from: b1, to: b2, t: c2Reach),
                lerpColor(from: b0, to: b2, t: reach)
            ]
        }
    }
}

// MARK: - Codex Streaming Bubbles, Refractive Water Sweep & Drag Wake Canvas

private struct FluidParticleSpec {
    let phase: Double
    let baseY: Double
    let size: CGFloat
    let brightness: Double
    let speedMul: Double
}

private enum FluidParticles {
    static let all: [FluidParticleSpec] = {
        let count = 22
        let golden = 0.6180339887498949
        var specs: [FluidParticleSpec] = []
        specs.reserveCapacity(count)
        for i in 0..<count {
            let p = fmod(Double(i + 1) * golden, 1.0)
            let slot = Double((i * 7 + 3) % count) / Double(count - 1)
            let y = 0.15 + slot * 0.70
            let h1 = Double(((i + 1) * 2654435761) % 1000) / 1000.0
            let h2 = Double(((i + 1) * 1597334677) % 1000) / 1000.0
            specs.append(
                FluidParticleSpec(
                    phase: p,
                    baseY: y,
                    size: CGFloat(1.1 + h1 * 1.35),
                    brightness: 0.48 + h2 * 0.46,
                    speedMul: 0.36 + Double(i % 4) * 0.045
                )
            )
        }
        return specs
    }()
}

private struct FluidCausticsAndStreamCanvas: View {
    let sample: FluidSample
    let isDark: Bool

    var body: some View {
        Canvas { context, size in
            guard size.width > 14 else { return }

            // 1. Codex Diagonal Refractive Water-Sheen Sweep (right-to-left)
            if sample.energy > 0.02 || sample.turbulence > 0.04 {
                let cyc = 1.0 - fmod(sample.sweepPhase, 1.0)
                let sweepCenterX = CGFloat(cyc * 1.5 - 0.25) * size.width
                let bandHalfW: CGFloat = max(18, size.width * 0.20)
                let sweepPeak = (isDark ? 0.20 : 0.24) * min(1.0, sample.energy * 1.3 + sample.turbulence * 0.7)
                let startPt = CGPoint(x: sweepCenterX - bandHalfW, y: 0)
                let endPt = CGPoint(x: sweepCenterX + bandHalfW, y: size.height * 0.35)
                var band = Path()
                band.move(to: CGPoint(x: sweepCenterX - bandHalfW, y: 0))
                band.addLine(to: CGPoint(x: sweepCenterX + bandHalfW, y: 0))
                band.addLine(to: CGPoint(x: sweepCenterX + bandHalfW - 9, y: size.height))
                band.addLine(to: CGPoint(x: sweepCenterX - bandHalfW - 9, y: size.height))
                band.closeSubpath()
                context.fill(
                    band,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(sweepPeak),
                            Color.white.opacity(0)
                        ]),
                        startPoint: startPt,
                        endPoint: endPt
                    )
                )
            }

            // 2. Velocity-Driven Undulating Liquid Wake Ribbons Behind Moving Droplet
            if sample.turbulence > 0.03 && size.width > 24 {
                let turb = sample.turbulence
                let rows: [Double] = [0.30, 0.50, 0.70]
                context.drawLayer { wakeCtx in
                    wakeCtx.addFilter(.blur(radius: 1.1))
                    for (idx, rowY) in rows.enumerated() {
                        let maxLen = min(Double(size.width - 10), (20.0 + 44.0 * turb) * (1.0 - Double(idx) * 0.16))
                        guard maxLen > 6 else { continue }
                        var path = Path()
                        let steps = 10
                        for s in 0...steps {
                            let frac = Double(s) / Double(steps)
                            let dx = maxLen * (1.0 - frac)
                            let x = Double(size.width) - 4.0 - dx
                            let wave = sin(dx / 8.5 - sample.phase * 3.6 + Double(idx) * 1.4) * (1.5 * turb)
                            let y = rowY * Double(size.height) + wave
                            if s == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        let startX = CGFloat(Double(size.width) - 4.0 - maxLen)
                        wakeCtx.stroke(
                            path,
                            with: .linearGradient(
                                Gradient(colors: [
                                    Color.white.opacity(0),
                                    Color.white.opacity((idx == 1 ? 0.44 : 0.30) * turb)
                                ]),
                                startPoint: CGPoint(x: startX, y: size.height / 2),
                                endPoint: CGPoint(x: size.width - 4, y: size.height / 2)
                            ),
                            style: StrokeStyle(lineWidth: idx == 1 ? 2.2 : 1.5, lineCap: .round)
                        )
                    }
                }
            }

            // 3. Meniscus Radial Light-Bloom Emitted Backward from Droplet Knob
            let bloomRadius: CGFloat = 30
            let bloomPeak = (isDark ? 0.34 : 0.28) + 0.10 * sample.turbulence
            let bloomCenter = CGPoint(x: size.width, y: size.height / 2)
            let bloomRect = CGRect(
                x: max(0, size.width - bloomRadius),
                y: 0,
                width: min(size.width, bloomRadius),
                height: size.height
            )
            context.fill(
                Path(bloomRect),
                with: .radialGradient(
                    Gradient(colors: [
                        Color.white.opacity(bloomPeak),
                        Color.white.opacity(0)
                    ]),
                    center: bloomCenter,
                    startRadius: 1,
                    endRadius: bloomRadius
                )
            )

            // 4. Codex 22 Golden-Ratio Streaming Micro-Bubbles / Stardust
            let baseCount = Int((sample.energy * Double(FluidParticles.all.count)).rounded())
            let stirBonus = sample.turbulence > 0.12 ? Int((sample.turbulence * 5.0).rounded()) : 0
            let visibleCount = min(FluidParticles.all.count, max(0, baseCount + stirBonus))
            guard visibleCount > 0, size.width > 22 else { return }

            let usableSpan = Double(size.width - 10)
            // Soft outer glow pass
            context.drawLayer { glowCtx in
                glowCtx.addFilter(.blur(radius: 1.15))
                for i in 0..<visibleCount {
                    let p = FluidParticles.all[i]
                    let u = fmod(p.phase + sample.phase * p.speedMul, 1.0)
                    let x = Double(size.width) - 5.0 - u * usableSpan
                    guard x > 5.0 else { continue }
                    let bob = sin(u * 7.2 - sample.phase * 2.6 + Double(i)) * 0.065
                    let y = (p.baseY + bob) * Double(size.height)
                    let edgeFade = min(1.0, min(u / 0.09, (1.0 - u) / 0.13))
                    let alpha = p.brightness * edgeFade * 0.44
                    let d = p.size * 1.9
                    let rect = CGRect(x: CGFloat(x) - d / 2, y: CGFloat(y) - d / 2, width: d, height: d)
                    glowCtx.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha)))
                }
            }

            // Crisp micro-bubble core pass
            for i in 0..<visibleCount {
                let p = FluidParticles.all[i]
                let u = fmod(p.phase + sample.phase * p.speedMul, 1.0)
                let x = Double(size.width) - 5.0 - u * usableSpan
                guard x > 5.0 else { continue }
                let bob = sin(u * 7.2 - sample.phase * 2.6 + Double(i)) * 0.065
                let y = (p.baseY + bob) * Double(size.height)
                let edgeFade = min(1.0, min(u / 0.09, (1.0 - u) / 0.13))
                let alpha = p.brightness * edgeFade * 0.90
                let d = p.size
                let rect = CGRect(x: CGFloat(x) - d / 2, y: CGFloat(y) - d / 2, width: d, height: d)
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha)))
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

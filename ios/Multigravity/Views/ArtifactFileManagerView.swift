import SwiftUI
import UIKit

// MARK: - Tab 4 Embedded Summary Card ("产物库与本机存储管理")

public struct ArtifactStorageSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var library = ArtifactLibraryManager.shared
    @State private var settings = AppSettings.shared
    public let onOpenManager: () -> Void

    public init(onOpenManager: @escaping () -> Void) {
        self.onOpenManager = onOpenManager
    }

    public var body: some View {
        let p = AGPalette(colorScheme)
        let activeCount = library.activeDownloads.count

        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(p.accentSoft)
                        .frame(width: 30, height: 30)
                    AGLinearIcon(.folder, size: 15, color: p.accentText, lineWidth: 2.0)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    Text("会话产物库与离线存储")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(p.ink1)
                    Text(
                        activeCount > 0
                            ? "正在后台同步 \(activeCount) 个产物 · 本机已占 \(library.formattedTotalLocalBytes)"
                            : "共收录 \(library.entries.count) 个产出 · 本机已缓存 \(library.cachedCount) 个 (\(library.formattedTotalLocalBytes))"
                    )
                    .font(.system(size: 11))
                    .foregroundColor(p.ink2)
                    .lineLimit(1)
                }

                Spacer()

                if activeCount > 0 {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Category quick-stats strip
            HStack(spacing: 6) {
                categoryStatPill(icon: .video, label: "视频", count: library.count(for: .video))
                categoryStatPill(icon: .image, label: "图片", count: library.count(for: .image))
                categoryStatPill(icon: .fileText, label: "文档", count: library.count(for: .document))
            }

            Toggle("产物自动下载到手机（点开零等待）", isOn: $settings.autoDownloadArtifacts)
                .font(.system(size: 12.5, weight: .medium))
                .tint(AGPalette.accentFill(colorScheme))

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onOpenManager()
            } label: {
                HStack(spacing: 6) {
                    AGLinearIcon(.archive, size: 13.5, color: p.accentText, lineWidth: 2.0)
                    Text("管理产出文件与清理手机空间")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(p.accentText)
                    Spacer()
                    Text("仅删本机 · 可重下")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(p.ink3)
                    AGLinearIcon(.chevronRight, size: 11.5, color: p.accentText, lineWidth: 2.1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9.5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(p.accentSoft.opacity(colorScheme == .dark ? 0.85 : 0.75))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(p.accentBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .agCard(cornerRadius: 15)
        .onAppear {
            library.bootstrapIfNeeded()
        }
    }

    private func categoryStatPill(icon: AGLinearIcon.Kind, label: String, count: Int) -> some View {
        let p = AGPalette(colorScheme)
        return HStack(spacing: 5) {
            AGLinearIcon(icon, size: 12, color: p.ink2, lineWidth: 1.95)
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(p.ink2)
            Spacer(minLength: 2)
            Text("\(count)")
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundColor(p.ink1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6.5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .fill(p.recessed)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .stroke(p.borderSoft, lineWidth: 0.8)
        )
    }
}

// MARK: - Full Artifact File Manager Sheet

public struct ArtifactFileManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public let onOpenConversationId: ((String) -> Void)?

    @State private var library = ArtifactLibraryManager.shared
    @State private var settings = AppSettings.shared
    @State private var selectedCategory: ArtifactCategory = .all
    @State private var onlyCachedFilter: Bool = false
    @State private var searchText: String = ""
    @State private var isSelecting: Bool = false
    @State private var selectedIds: Set<String> = []
    @State private var showEvictAllConfirm: Bool = false

    // Preview states
    @State private var quickLookItem: IdentifiableLocalFile? = nil
    @State private var htmlItem: IdentifiableLocalFile? = nil
    @State private var markdownViewerData: MarkdownFileViewerData? = nil
    @State private var errorAlertMessage: String? = nil

    public init(onOpenConversationId: ((String) -> Void)? = nil) {
        self.onOpenConversationId = onOpenConversationId
    }

    private var filteredEntries: [ArtifactCatalogEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return library.entries.filter { entry in
            if selectedCategory != .all && entry.category != selectedCategory {
                return false
            }
            if onlyCachedFilter && !entry.isLocallyCached {
                return false
            }
            if !q.isEmpty {
                let hay = "\(entry.displayTitle) \(entry.storageFileName) \(entry.conversationTitle) \(entry.workspaceName) \(entry.summary ?? "")".lowercased()
                if !hay.contains(q) { return false }
            }
            return true
        }
    }

    private var selectedBytesToFree: Int64 {
        library.entries
            .filter { selectedIds.contains($0.id) && $0.isLocallyCached }
            .reduce(0) { $0 + $1.cachedByteSize }
    }

    public var body: some View {
        let p = AGPalette(colorScheme)

        NavigationStack {
            ZStack(alignment: .bottom) {
                p.pageBg.ignoresSafeArea()

                VStack(spacing: 10) {
                    storageBannerCard
                        .padding(.horizontal, 14)
                        .padding(.top, 6)

                    filterAndSearchHeader
                        .padding(.horizontal, 14)

                    if filteredEntries.isEmpty {
                        emptyStateView
                    } else {
                        List {
                            ForEach(filteredEntries) { entry in
                                artifactRow(entry: entry)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        if entry.isLocallyCached {
                                            Button(role: .destructive) {
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                library.deleteLocalStorage(for: entry.id)
                                            } label: {
                                                Label("删本机缓存", systemImage: "iphone.slash")
                                            }
                                        } else {
                                            Button {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                library.triggerManualBackgroundDownload(for: entry)
                                            } label: {
                                                Label("下载到手机", systemImage: "arrow.down.circle")
                                            }
                                            .tint(p.accentFill)
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .padding(.bottom, isSelecting && !selectedIds.isEmpty ? 64 : 0)
                    }
                }

                if isSelecting && !selectedIds.isEmpty {
                    batchActionBottomBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("会话产出文件管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !library.entries.isEmpty {
                        Button(isSelecting ? "完成选择" : "批量清理") {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isSelecting.toggle()
                                if !isSelecting { selectedIds.removeAll() }
                            }
                        }
                        .font(.system(size: 13.5, weight: .semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
            }
            .onAppear {
                library.bootstrapIfNeeded()
                library.reconcileDiskStates()
            }
            .confirmationDialog(
                "释放当前分类的手机本地空间？",
                isPresented: $showEvictAllConfirm,
                titleVisibility: .visible
            ) {
                Button("仅清理手机本地文件（保留列表可重下）", role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    library.deleteAllLocalStorage(in: selectedCategory)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("不会删除电脑上的源文件和此处的产出记录，之后点击任意条目仍可随时重新下载。")
            }
            .alert("无法打开文件", isPresented: Binding(
                get: { errorAlertMessage != nil },
                set: { if !$0 { errorAlertMessage = nil } }
            )) {
                Button("确定", role: .cancel) { errorAlertMessage = nil }
            } message: {
                Text(errorAlertMessage ?? "")
            }
            .sheet(item: $quickLookItem) { item in
                QuickLookPreviewSheet(url: item.url, title: item.title) {
                    quickLookItem = nil
                }
            }
            .sheet(item: $htmlItem) { item in
                HTMLPreviewSheet(url: item.url, title: item.title) {
                    htmlItem = nil
                }
            }
            .sheet(item: $markdownViewerData) { data in
                MarkdownViewerSheet(
                    data: data,
                    onDismiss: { markdownViewerData = nil },
                    onProceed: nil,
                    onRetry: nil,
                    onRefresh: nil
                )
            }
        }
    }

    // MARK: - Subviews

    private var storageBannerCard: some View {
        let p = AGPalette(colorScheme)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("本机占用 \(library.formattedTotalLocalBytes)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(p.ink1)
                        Text("\(library.cachedCount)/\(library.entries.count) 已存本机")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(p.accentText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(p.accentSoft))
                    }
                    Text("左滑或点垃圾桶仅清理手机存储，记录保留在列表中，再次点击即可重下")
                        .font(.system(size: 11))
                        .foregroundColor(p.ink2)
                }

                Spacer(minLength: 4)

                if library.totalLocalBytes > 0 {
                    Button {
                        showEvictAllConfirm = true
                    } label: {
                        HStack(spacing: 4) {
                            AGLinearIcon(.trash, size: 11.5, color: p.roseText, lineWidth: 2.0)
                            Text("一键释放")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(p.roseText)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(p.roseSoft))
                    }
                    .buttonStyle(.plain)
                }
            }

            Toggle("新产出自动后台下载到手机", isOn: $settings.autoDownloadArtifacts)
                .font(.system(size: 12, weight: .medium))
                .tint(AGPalette.accentFill(colorScheme))
        }
        .padding(12)
        .agCard(cornerRadius: 13)
    }

    private var filterAndSearchHeader: some View {
        let p = AGPalette(colorScheme)
        return VStack(spacing: 8) {
            // Search input
            HStack(spacing: 7) {
                AGLinearIcon(.search, size: 14, color: p.ink3, lineWidth: 1.95)
                TextField("搜索文件名、所属会话或工作区...", text: $searchText)
                    .font(.system(size: 13))
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        AGLinearIcon(.close, size: 11.5, color: p.ink3, lineWidth: 2.1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(p.borderCard, lineWidth: 1))

            // Category pills + Only-Cached filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ArtifactCategory.allCases) { cat in
                        let isSel = selectedCategory == cat
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selectedCategory = cat
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(cat.title)
                                    .font(.system(size: 12, weight: isSel ? .bold : .medium))
                                Text("\(library.count(for: cat))")
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .opacity(0.8)
                            }
                            .foregroundColor(isSel ? .white : p.ink2)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5.5)
                            .background(
                                Capsule().fill(isSel ? p.accentFill : p.card)
                            )
                            .overlay(
                                Capsule().stroke(isSel ? Color.clear : p.borderCard, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.16)) {
                            onlyCachedFilter.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            AGLinearIcon(.smartphone, size: 11.5, color: onlyCachedFilter ? p.emeraldText : p.ink2, lineWidth: 2.0)
                            Text("仅看占本机空间")
                                .font(.system(size: 11.5, weight: onlyCachedFilter ? .bold : .medium))
                                .foregroundColor(onlyCachedFilter ? p.emeraldText : p.ink2)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5.5)
                        .background(
                            Capsule().fill(onlyCachedFilter ? p.emeraldSoft : p.card)
                        )
                        .overlay(
                            Capsule().stroke(onlyCachedFilter ? p.emeraldBorder : p.borderCard, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func artifactRow(entry: ArtifactCatalogEntry) -> some View {
        let p = AGPalette(colorScheme)
        let dlProgress = library.activeDownloads[entry.id]
        let isChecked = selectedIds.contains(entry.id)

        return HStack(spacing: 10) {
            if isSelecting {
                Button {
                    toggleSelect(entry.id)
                } label: {
                    ZStack {
                        Circle()
                            .fill(isChecked ? p.accentFill : Color.clear)
                            .frame(width: 21, height: 21)
                            .overlay(
                                Circle()
                                    .stroke(isChecked ? p.accentFill : p.ink3, lineWidth: 1.6)
                            )
                        if isChecked {
                            AGLinearIcon(.check, size: 11, color: .white, lineWidth: 2.3)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            // Thumbnail / Vector Type Badge
            ArtifactThumbnailBadgeView(entry: entry)

            // Title & Metadata
            VStack(alignment: .leading, spacing: 3.5) {
                Text(entry.displayTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(p.ink1)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let dlProgress {
                        Text("下载中 \(Int((dlProgress * 100).rounded()))%")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundColor(p.accentText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(p.accentSoft))
                    } else if entry.isLocallyCached {
                        Text("已在手机 · \(ArtifactLibraryManager.formatBytes(entry.cachedByteSize))")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(p.emeraldText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(p.emeraldSoft))
                    } else {
                        Text("仅云端 · 点击下载")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(p.ink3)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(p.recessed))
                    }

                    Text(entry.conversationTitle)
                        .font(.system(size: 11))
                        .foregroundColor(p.ink3)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Trailing Quick Action (Delete Local Copy vs Download)
            if !isSelecting {
                if dlProgress != nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 30, height: 30)
                } else if entry.isLocallyCached {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        library.deleteLocalStorage(for: entry.id)
                    } label: {
                        AGLinearIcon(.trash, size: 13.5, color: p.roseText, lineWidth: 1.95)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(p.roseSoft))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清理手机本地缓存（保留云端可重下）")
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        library.triggerManualBackgroundDownload(for: entry)
                    } label: {
                        AGLinearIcon(.download, size: 13.5, color: p.accentText, lineWidth: 2.0)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(p.accentSoft))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("重新下载到手机")
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9.5)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(p.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isChecked ? p.accentFill : p.borderCard, lineWidth: isChecked ? 1.4 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            if isSelecting {
                toggleSelect(entry.id)
            } else {
                handleTapEntry(entry)
            }
        }
        .contextMenu {
            Button {
                handleTapEntry(entry)
            } label: {
                Label(entry.isLocallyCached ? "立即打开预览" : "下载并打开预览", systemImage: "eye")
            }

            if !entry.cascadeId.isEmpty, let onOpenConversationId {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onOpenConversationId(entry.cascadeId)
                    }
                } label: {
                    Label("定位到所属会话", systemImage: "bubble.left.and.bubble.right")
                }
            }

            if entry.isLocallyCached {
                Button(role: .destructive) {
                    library.deleteLocalStorage(for: entry.id)
                } label: {
                    Label("仅清理手机存储（可再次下载）", systemImage: "iphone.slash")
                }
            } else {
                Button {
                    library.triggerManualBackgroundDownload(for: entry)
                } label: {
                    Label("后台下载到手机", systemImage: "arrow.down.circle")
                }
            }

            Divider()

            Button(role: .destructive) {
                library.removeRecordCompletely(entryId: entry.id)
            } label: {
                Label("从列表移除此记录", systemImage: "trash")
            }
        }
    }

    private var batchActionBottomBar: some View {
        let p = AGPalette(colorScheme)
        return HStack(spacing: 10) {
            Button {
                let allFilteredIds = Set(filteredEntries.map(\.id))
                if selectedIds == allFilteredIds {
                    selectedIds.removeAll()
                } else {
                    selectedIds = allFilteredIds
                }
            } label: {
                Text(selectedIds.count == filteredEntries.count ? "取消全选" : "全选当前")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(p.ink1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(p.recessed))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                library.deleteLocalStorage(forIds: selectedIds)
                selectedIds.removeAll()
                isSelecting = false
            } label: {
                HStack(spacing: 5) {
                    AGLinearIcon(.trash, size: 13, color: .white, lineWidth: 2.0)
                    Text(
                        selectedBytesToFree > 0
                            ? "清理手机存储 · 释放 \(ArtifactLibraryManager.formatBytes(selectedBytesToFree))"
                            : "清理所选 (\(selectedIds.count))"
                    )
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9.5)
                .background(Capsule().fill(p.roseFill))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            p.card
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: 12, y: -3)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var emptyStateView: some View {
        let p = AGPalette(colorScheme)
        return VStack(spacing: 10) {
            Spacer()
            ZStack {
                Circle()
                    .fill(p.recessed)
                    .frame(width: 54, height: 54)
                AGLinearIcon(.folder, size: 24, color: p.ink3, lineWidth: 1.9)
            }
            Text(onlyCachedFilter ? "当前没有占用手机空间的缓存产物" : "暂无收录的会话产出")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(p.ink2)
            Text("Agent 生成的视频、图片、PDF、Office 与方案文档会自动汇总到这里")
                .font(.system(size: 12))
                .foregroundColor(p.ink3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleSelect(_ id: String) {
        UISelectionFeedbackGenerator().selectionChanged()
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func handleTapEntry(_ entry: ArtifactCatalogEntry) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { @MainActor in
            do {
                let payload = try await library.openOrDownloadAndPreview(entry: entry)
                switch payload {
                case .quickLook(let url, let title):
                    quickLookItem = IdentifiableLocalFile(url: url, title: title)
                case .html(let url, let title):
                    htmlItem = IdentifiableLocalFile(url: url, title: title)
                case .markdown(let data):
                    markdownViewerData = data
                }
            } catch {
                errorAlertMessage = error.localizedDescription
            }
        }
    }
}

private struct IdentifiableLocalFile: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

private struct ArtifactThumbnailBadgeView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: ArtifactCatalogEntry

    @State private var thumb: UIImage? = nil

    var body: some View {
        let p = AGPalette(colorScheme)
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(badgeBg(p))
                .frame(width: 42, height: 42)

            if let thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        if entry.category == .video {
                            ZStack {
                                Color.black.opacity(0.28)
                                AGLinearIcon(.play, size: 13, color: .white, lineWidth: 2.2)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
            } else {
                AGLinearIcon(iconKind, size: 18, color: badgeFg(p), lineWidth: 1.95)
            }
        }
        .frame(width: 42, height: 42)
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(p.borderSoft, lineWidth: 0.7)
        )
        .task(id: "\(entry.id)_\(entry.isLocallyCached)") {
            loadLocalThumbnailIfAvailable()
        }
    }

    private var iconKind: AGLinearIcon.Kind {
        switch entry.category {
        case .video: return .video
        case .image: return .image
        case .document, .all:
            let ext = (entry.storageFileName as NSString).pathExtension.lowercased()
            if ext == "zip" { return .archive }
            return .fileText
        }
    }

    private func badgeBg(_ p: AGPalette) -> Color {
        switch entry.category {
        case .video: return p.violetSoft
        case .image: return p.accentSoft
        case .document, .all: return p.amberSoft
        }
    }

    private func badgeFg(_ p: AGPalette) -> Color {
        switch entry.category {
        case .video: return p.violetText
        case .image: return p.accentText
        case .document, .all: return p.amberText
        }
    }

    private func loadLocalThumbnailIfAvailable() {
        guard let gwURL = AppSettings.shared.serverURL else { return }
        let resolvedStr = APIClient.shared.resolveMediaURL(entry.uri, cascadeId: entry.cascadeId, baseURL: gwURL)
        if entry.category == .video, let u = URL(string: resolvedStr) {
            if let hit = VideoThumbnailCache.shared.image(for: u) {
                thumb = hit
            }
            return
        }
        if entry.category == .image {
            if let u = URL(string: resolvedStr), let hit = MarkdownImageCache.shared.image(for: u) {
                thumb = hit
                return
            }
            if entry.isLocallyCached,
               let info = DocumentCacheManager.shared.localArtifactFileInfo(
                   for: entry.uri,
                   fileName: entry.storageFileName,
                   cascadeId: entry.cascadeId,
                   isMarkdown: false,
                   resolvedMediaURL: URL(string: resolvedStr)
               ),
               info.byteSize < 15 * 1024 * 1024,
               let img = UIImage(contentsOfFile: info.url.path) {
                thumb = img
            }
        }
    }
}

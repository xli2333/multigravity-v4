import Foundation
import Observation
import AVFoundation
import UIKit

public extension Notification.Name {
    static let artifactCacheDidClearAll = Notification.Name("com.multigravity.artifactCacheDidClearAll")
}

public nonisolated enum ArtifactCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case all = "all"
    case video = "video"
    case image = "image"
    case document = "document"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return String(localized: "全部")
        case .video: return String(localized: "视频")
        case .image: return String(localized: "图片")
        case .document: return String(localized: "文档")
        }
    }
}

public nonisolated struct ArtifactCatalogEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var uri: String
    public var storageFileName: String
    public var displayTitle: String
    public var summary: String?
    public var category: ArtifactCategory
    public var isMarkdownArtifact: Bool
    public var isHTML: Bool
    public var cascadeId: String
    public var conversationTitle: String
    public var workspaceName: String
    public var discoveredAt: Date
    public var cachedByteSize: Int64
    public var isLocallyCached: Bool

    public init(
        id: String,
        uri: String,
        storageFileName: String,
        displayTitle: String,
        summary: String? = nil,
        category: ArtifactCategory,
        isMarkdownArtifact: Bool = false,
        isHTML: Bool = false,
        cascadeId: String,
        conversationTitle: String,
        workspaceName: String,
        discoveredAt: Date = Date(),
        cachedByteSize: Int64 = 0,
        isLocallyCached: Bool = false
    ) {
        self.id = id
        self.uri = uri
        self.storageFileName = storageFileName
        self.displayTitle = displayTitle
        self.summary = summary
        self.category = category
        self.isMarkdownArtifact = isMarkdownArtifact
        self.isHTML = isHTML
        self.cascadeId = cascadeId
        self.conversationTitle = conversationTitle
        self.workspaceName = workspaceName
        self.discoveredAt = discoveredAt
        self.cachedByteSize = cachedByteSize
        self.isLocallyCached = isLocallyCached
    }
}

public enum ArtifactPreviewPayload {
    case quickLook(url: URL, title: String)
    case html(url: URL, title: String)
    case markdown(data: MarkdownFileViewerData)
}

@MainActor
@Observable
public final class ArtifactLibraryManager {
    public static let shared = ArtifactLibraryManager()

    public private(set) var entries: [ArtifactCatalogEntry] = []
    /// Live download progress `0.0 ... 1.0` keyed by `entry.id`.
    public private(set) var activeDownloads: [String: Double] = [:]
    public private(set) var isBootstrapped: Bool = false

    private var manuallyEvictedKeys: Set<String> = []
    private var sessionFailedKeys: Set<String> = []
    private var pendingQueue: [String] = []
    private var runningDownloadTasks: [String: Task<Void, Never>] = [:]
    private var pendingIngestTasks: [String: Task<Void, Never>] = [:]
    private var persistTask: Task<Void, Never>? = nil

    private static let maxConcurrentDownloads = 2
    private static let evictedDefaultsKey = "mgy.evictedArtifactKeys.v1"

    private let catalogFileURL: URL = {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let rootDir = appSupport.appendingPathComponent("MultigravityMediaCache", isDirectory: true)
        try? fm.createDirectory(at: rootDir, withIntermediateDirectories: true)
        return rootDir.appendingPathComponent("artifact_catalog_v1.json")
    }()

    private init() {
        let savedEvicted = UserDefaults.standard.stringArray(forKey: Self.evictedDefaultsKey) ?? []
        self.manuallyEvictedKeys = Set(savedEvicted)
        loadCatalogFromDisk()

        NotificationCenter.default.addObserver(
            forName: .artifactCacheDidClearAll,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleGlobalCacheCleared()
            }
        }
    }

    // MARK: - Computed Summaries

    public var totalLocalBytes: Int64 {
        entries.reduce(0) { acc, item in
            acc + (item.isLocallyCached ? max(0, item.cachedByteSize) : 0)
        }
    }

    public var cachedCount: Int {
        entries.filter(\.isLocallyCached).count
    }

    public var formattedTotalLocalBytes: String {
        Self.formatBytes(totalLocalBytes)
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    public func count(for category: ArtifactCategory) -> Int {
        if category == .all { return entries.count }
        return entries.filter { $0.category == category }.count
    }

    // MARK: - Bootstrap & Disk Reconciliation

    public func bootstrapIfNeeded() {
        if isBootstrapped {
            reconcileDiskStates()
            enqueuePendingAutoDownloads()
            return
        }
        isBootstrapped = true
        reconcileDiskStates()

        Task { @MainActor in
            let cachedSessions = await Task.detached(priority: .utility) {
                CacheManager.shared.allCachedSessionsOnDisk()
            }.value
            let convTitles = Dictionary(
                CacheManager.shared.loadConversations().map { ($0.id, $0.title) },
                uniquingKeysWith: { first, _ in first }
            )
            for session in cachedSessions {
                let resolvedTitle = convTitles[session.cascadeId]
                    ?? session.title
                    ?? String(localized: "会话详情")
                self.ingestNow(
                    cascadeId: session.cascadeId,
                    title: resolvedTitle,
                    workspaceName: session.workspaceName ?? "",
                    messages: session.messages,
                    discoveredFallbackDate: session.savedAt,
                    triggerAutoDownload: false
                )
            }
            self.reconcileDiskStates()
            self.enqueuePendingAutoDownloads()
        }
    }

    public func reconcileDiskStates() {
        let gwURL = AppSettings.shared.serverURL
        var changed = false
        for idx in entries.indices {
            let item = entries[idx]
            let resolvedMediaURL: URL? = {
                guard item.category == .image, let gwURL else { return nil }
                let str = APIClient.shared.resolveMediaURL(item.uri, cascadeId: item.cascadeId, baseURL: gwURL)
                return URL(string: str)
            }()
            if let info = DocumentCacheManager.shared.localArtifactFileInfo(
                for: item.uri,
                fileName: item.storageFileName,
                cascadeId: item.cascadeId,
                isMarkdown: item.isMarkdownArtifact,
                resolvedMediaURL: resolvedMediaURL
            ) {
                if !entries[idx].isLocallyCached || entries[idx].cachedByteSize != info.byteSize {
                    entries[idx].isLocallyCached = true
                    entries[idx].cachedByteSize = info.byteSize
                    changed = true
                }
            } else if entries[idx].isLocallyCached || entries[idx].cachedByteSize != 0 {
                entries[idx].isLocallyCached = false
                entries[idx].cachedByteSize = 0
                changed = true
            }
        }
        if changed {
            schedulePersistCatalog()
        }
    }

    private func handleGlobalCacheCleared() {
        for idx in entries.indices {
            entries[idx].isLocallyCached = false
            entries[idx].cachedByteSize = 0
        }
        schedulePersistCatalog()
    }

    // MARK: - Live Ingestion from Chat / Stream

    public func scheduleIngest(
        cascadeId: String,
        title: String,
        workspaceName: String,
        messages: [ChatMessage]
    ) {
        let cid = cascadeId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty, !messages.isEmpty else { return }
        if pendingIngestTasks[cid] != nil { return }

        pendingIngestTasks[cid] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self else { return }
            self.pendingIngestTasks.removeValue(forKey: cid)
            let latestSession = CacheManager.shared.loadMemoryCachedSession(for: cid)
            let msgs = latestSession?.messages ?? messages
            let resolvedTitle = CacheManager.shared.cachedSessionTitle(for: cid) ?? title
            let resolvedWS = latestSession?.workspaceName ?? workspaceName
            self.ingestNow(
                cascadeId: cid,
                title: resolvedTitle,
                workspaceName: resolvedWS,
                messages: msgs,
                discoveredFallbackDate: Date(),
                triggerAutoDownload: true
            )
        }
    }

    private func ingestNow(
        cascadeId: String,
        title: String,
        workspaceName: String,
        messages: [ChatMessage],
        discoveredFallbackDate: Date,
        triggerAutoDownload: Bool
    ) {
        let extracted = Self.extractCandidates(
            from: messages,
            cascadeId: cascadeId,
            conversationTitle: title,
            workspaceName: workspaceName,
            fallbackDate: discoveredFallbackDate
        )
        guard !extracted.isEmpty else { return }

        let gwURL = AppSettings.shared.serverURL
        var indexById = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.id, $0.offset) })
        var didMutate = false

        for var candidate in extracted {
            let resolvedMediaURL: URL? = {
                guard candidate.category == .image, let gwURL else { return nil }
                let s = APIClient.shared.resolveMediaURL(candidate.uri, cascadeId: candidate.cascadeId, baseURL: gwURL)
                return URL(string: s)
            }()
            if let info = DocumentCacheManager.shared.localArtifactFileInfo(
                for: candidate.uri,
                fileName: candidate.storageFileName,
                cascadeId: candidate.cascadeId,
                isMarkdown: candidate.isMarkdownArtifact,
                resolvedMediaURL: resolvedMediaURL
            ) {
                candidate.isLocallyCached = true
                candidate.cachedByteSize = info.byteSize
            }

            if let existingIdx = indexById[candidate.id] {
                var existing = entries[existingIdx]
                var rowChanged = false
                if !candidate.conversationTitle.isEmpty && candidate.conversationTitle != "会话详情" && existing.conversationTitle != candidate.conversationTitle {
                    existing.conversationTitle = candidate.conversationTitle
                    rowChanged = true
                }
                if (existing.summary ?? "").isEmpty, let sum = candidate.summary, !sum.isEmpty {
                    existing.summary = sum
                    rowChanged = true
                }
                if existing.isLocallyCached != candidate.isLocallyCached || existing.cachedByteSize != candidate.cachedByteSize {
                    existing.isLocallyCached = candidate.isLocallyCached
                    existing.cachedByteSize = candidate.cachedByteSize
                    rowChanged = true
                }
                if rowChanged {
                    entries[existingIdx] = existing
                    didMutate = true
                }
            } else {
                entries.insert(candidate, at: 0)
                indexById = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.id, $0.offset) })
                didMutate = true
            }
        }

        if didMutate {
            entries.sort { $0.discoveredAt > $1.discoveredAt }
            if entries.count > 400 {
                entries = Array(entries.prefix(400))
            }
            schedulePersistCatalog()
        }

        if triggerAutoDownload {
            enqueuePendingAutoDownloads()
        }
    }

    // MARK: - Background Auto-Download Engine

    public func enqueuePendingAutoDownloads() {
        guard AppSettings.shared.autoDownloadArtifacts, AppSettings.shared.isPaired else { return }
        guard AppSettings.shared.serverURL != nil else { return }

        for item in entries {
            guard !item.isLocallyCached else { continue }
            guard !manuallyEvictedKeys.contains(item.id) else { continue }
            guard !sessionFailedKeys.contains(item.id) else { continue }
            guard runningDownloadTasks[item.id] == nil else { continue }
            if !pendingQueue.contains(item.id) {
                pendingQueue.append(item.id)
            }
        }
        pumpDownloadQueue()
    }

    private func pumpDownloadQueue() {
        guard AppSettings.shared.isPaired, AppSettings.shared.serverURL != nil else { return }
        while runningDownloadTasks.count < Self.maxConcurrentDownloads, !pendingQueue.isEmpty {
            let nextID = pendingQueue.removeFirst()
            guard runningDownloadTasks[nextID] == nil else { continue }
            guard let entry = entries.first(where: { $0.id == nextID }), !entry.isLocallyCached else {
                continue
            }
            activeDownloads[nextID] = 0.02
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    _ = try await self.performDownload(for: entry)
                } catch {
                    self.sessionFailedKeys.insert(nextID)
                }
                self.activeDownloads.removeValue(forKey: nextID)
                self.runningDownloadTasks.removeValue(forKey: nextID)
                self.pumpDownloadQueue()
            }
            runningDownloadTasks[nextID] = task
        }
    }

    // MARK: - On-Demand Download / Preview / Local Delete

    public func openOrDownloadAndPreview(entry: ArtifactCatalogEntry) async throws -> ArtifactPreviewPayload {
        manuallyEvictedKeys.remove(entry.id)
        persistEvictedKeys()
        sessionFailedKeys.remove(entry.id)

        let gwURL = AppSettings.shared.serverURL
        let resolvedMediaURL: URL? = {
            guard entry.category == .image, let gwURL else { return nil }
            let s = APIClient.shared.resolveMediaURL(entry.uri, cascadeId: entry.cascadeId, baseURL: gwURL)
            return URL(string: s)
        }()

        // 1. Instant 0ms local cache hit
        if entry.isMarkdownArtifact {
            if let hit = DocumentCacheManager.shared.getCachedMarkdown(
                for: entry.uri,
                fileName: entry.storageFileName,
                cascadeId: entry.cascadeId
            ) {
                updateCachedState(id: entry.id, fileURL: hit.fileURL)
                let viewer = MarkdownFileViewerData(
                    id: "\(entry.id)_\(Date().timeIntervalSince1970)",
                    title: entry.displayTitle,
                    uri: entry.uri,
                    content: hit.response.content,
                    summary: hit.response.summary ?? entry.summary,
                    isLoading: false,
                    isRefreshing: false,
                    errorMessage: nil,
                    canProceed: false,
                    cachedFileURL: hit.fileURL,
                    isCached: true
                )
                return .markdown(data: viewer)
            }
        } else if let info = DocumentCacheManager.shared.localArtifactFileInfo(
            for: entry.uri,
            fileName: entry.storageFileName,
            cascadeId: entry.cascadeId,
            isMarkdown: false,
            resolvedMediaURL: resolvedMediaURL
        ) {
            updateCachedState(id: entry.id, fileURL: info.url)
            if entry.isHTML {
                return .html(url: info.url, title: entry.displayTitle)
            } else {
                return .quickLook(url: info.url, title: entry.displayTitle)
            }
        }

        // 2. Not on device (or previously evicted): download now from Gateway
        activeDownloads[entry.id] = 0.05
        defer {
            activeDownloads.removeValue(forKey: entry.id)
        }
        return try await performDownload(for: entry)
    }

    public func triggerManualBackgroundDownload(for entry: ArtifactCatalogEntry) {
        manuallyEvictedKeys.remove(entry.id)
        persistEvictedKeys()
        sessionFailedKeys.remove(entry.id)
        if !pendingQueue.contains(entry.id) && runningDownloadTasks[entry.id] == nil {
            pendingQueue.insert(entry.id, at: 0)
            pumpDownloadQueue()
        }
    }

    /// Deletes ONLY the local file stored on iPhone while keeping the catalog entry so the user can re-download anytime.
    public func deleteLocalStorage(for entryId: String) {
        if let running = runningDownloadTasks.removeValue(forKey: entryId) {
            running.cancel()
        }
        pendingQueue.removeAll { $0 == entryId }
        activeDownloads.removeValue(forKey: entryId)

        guard let idx = entries.firstIndex(where: { $0.id == entryId }) else { return }
        let entry = entries[idx]
        let gwURL = AppSettings.shared.serverURL
        let resolvedMediaURL: URL? = {
            guard let gwURL else { return nil }
            let s = APIClient.shared.resolveMediaURL(entry.uri, cascadeId: entry.cascadeId, baseURL: gwURL)
            return URL(string: s)
        }()

        DocumentCacheManager.shared.evictSingleArtifact(
            uri: entry.uri,
            fileName: entry.storageFileName,
            cascadeId: entry.cascadeId,
            resolvedMediaURL: resolvedMediaURL
        )
        manuallyEvictedKeys.insert(entryId)
        persistEvictedKeys()

        entries[idx].isLocallyCached = false
        entries[idx].cachedByteSize = 0
        schedulePersistCatalog()
    }

    public func deleteLocalStorage(forIds ids: Set<String>) {
        for id in ids {
            deleteLocalStorage(for: id)
        }
    }

    public func deleteAllLocalStorage(in category: ArtifactCategory = .all) {
        let targetIds = entries
            .filter { $0.isLocallyCached && (category == .all || $0.category == category) }
            .map(\.id)
        deleteLocalStorage(forIds: Set(targetIds))
    }

    public func removeRecordCompletely(entryId: String) {
        deleteLocalStorage(for: entryId)
        entries.removeAll { $0.id == entryId }
        schedulePersistCatalog()
    }

    // MARK: - Core Download Execution

    private func performDownload(for entry: ArtifactCatalogEntry) async throws -> ArtifactPreviewPayload {
        guard let gwURL = AppSettings.shared.serverURL else {
            throw APIError.networkError(String(localized: "未连接到电脑网关"))
        }

        if entry.isMarkdownArtifact {
            let resp = try await APIClient.shared.fetchFileContent(
                uri: entry.uri,
                cascadeId: entry.cascadeId.isEmpty ? nil : entry.cascadeId,
                baseURL: gwURL
            )
            let saved = try DocumentCacheManager.shared.saveMarkdownToCache(
                response: resp,
                for: entry.uri,
                fileName: entry.storageFileName,
                cascadeId: entry.cascadeId.isEmpty ? nil : entry.cascadeId
            )
            activeDownloads[entry.id] = 1.0
            updateCachedState(id: entry.id, fileURL: saved.fileURL)
            let viewer = MarkdownFileViewerData(
                id: "\(entry.id)_\(Date().timeIntervalSince1970)",
                title: entry.displayTitle,
                uri: entry.uri,
                content: resp.content,
                summary: resp.summary ?? entry.summary,
                isLoading: false,
                isRefreshing: false,
                errorMessage: nil,
                canProceed: false,
                cachedFileURL: saved.fileURL,
                isCached: true
            )
            return .markdown(data: viewer)
        }

        let entryID = entry.id
        let (localURL, _) = try await APIClient.shared.downloadFile(
            uri: entry.uri,
            cascadeId: entry.cascadeId.isEmpty ? nil : entry.cascadeId,
            baseURL: gwURL
        ) { [weak self] prog, _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.activeDownloads[entryID] != nil else { return }
                self.activeDownloads[entryID] = max(self.activeDownloads[entryID] ?? 0, min(0.99, prog))
            }
        }

        // Pre-warm image or video poster cache for 0ms chat scrolling
        if entry.category == .image {
            let resolvedStr = APIClient.shared.resolveMediaURL(entry.uri, cascadeId: entry.cascadeId, baseURL: gwURL)
            if let resolvedURL = URL(string: resolvedStr),
               let data = try? Data(contentsOf: localURL, options: .mappedIfSafe),
               data.count <= 12 * 1024 * 1024,
               let uiImg = UIImage(data: data) {
                MarkdownImageCache.shared.insertInMemoryOnly(uiImg, for: resolvedURL)
            }
        } else if entry.category == .video {
            let resolvedStr = APIClient.shared.resolveMediaURL(entry.uri, cascadeId: entry.cascadeId, baseURL: gwURL)
            if let resolvedURL = URL(string: resolvedStr),
               VideoThumbnailCache.shared.image(for: resolvedURL) == nil {
                Task.detached(priority: .utility) {
                    let asset = AVURLAsset(url: localURL)
                    let gen = AVAssetImageGenerator(asset: asset)
                    gen.appliesPreferredTrackTransform = true
                    gen.maximumSize = CGSize(width: 640, height: 640)
                    let t = CMTime(seconds: 0.5, preferredTimescale: 600)
                    if let (cg, _) = try? await gen.image(at: t) {
                        await MainActor.run {
                            VideoThumbnailCache.shared.insert(UIImage(cgImage: cg), for: resolvedURL)
                        }
                    } else if let (cg, _) = try? await gen.image(at: .zero) {
                        await MainActor.run {
                            VideoThumbnailCache.shared.insert(UIImage(cgImage: cg), for: resolvedURL)
                        }
                    }
                }
            }
        }

        activeDownloads[entry.id] = 1.0
        updateCachedState(id: entry.id, fileURL: localURL)

        if entry.isHTML {
            return .html(url: localURL, title: entry.displayTitle)
        } else {
            return .quickLook(url: localURL, title: entry.displayTitle)
        }
    }

    private func updateCachedState(id: String, fileURL: URL) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let sz = (attrs?[.size] as? Int64) ?? 0
        entries[idx].isLocallyCached = sz > 0
        entries[idx].cachedByteSize = max(0, sz)
        schedulePersistCatalog()
    }

    // MARK: - Persistence

    private func loadCatalogFromDisk() {
        guard let data = try? Data(contentsOf: catalogFileURL),
              let decoded = try? JSONDecoder().decode([ArtifactCatalogEntry].self, from: data) else {
            return
        }
        self.entries = decoded
    }

    private func schedulePersistCatalog() {
        persistTask?.cancel()
        let snapshot = self.entries
        let url = self.catalogFileURL
        persistTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func persistEvictedKeys() {
        UserDefaults.standard.set(Array(manuallyEvictedKeys), forKey: Self.evictedDefaultsKey)
    }

    // MARK: - Artifact Extraction Rules

    private static let videoExts: Set<String> = ["mp4", "mov", "m4v", "webm", "avi", "mkv", "3gp"]
    private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "heic", "heif", "svg", "bmp", "tiff", "tif"]
    private static let docDeliverableExts: Set<String> = [
        "pdf", "pptx", "ppt", "key", "docx", "doc", "xlsx", "xls", "numbers", "pages",
        "html", "htm", "ipynb", "csv", "zip", "mp3", "m4a", "wav"
    ]
    private static let markdownLinkRegex = try! NSRegularExpression(
        pattern: #"!?\[([^\]]*)\]\(([^\s\)]+)\)"#,
        options: []
    )
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoBasicFormatter = ISO8601DateFormatter()

    private static func parseTimestamp(_ raw: String?, fallback: Date) -> Date {
        guard let raw, !raw.isEmpty else { return fallback }
        return isoFormatter.date(from: raw) ?? isoBasicFormatter.date(from: raw) ?? fallback
    }

    private static func extractCandidates(
        from messages: [ChatMessage],
        cascadeId: String,
        conversationTitle: String,
        workspaceName: String,
        fallbackDate: Date
    ) -> [ArtifactCatalogEntry] {
        var result: [ArtifactCatalogEntry] = []
        var seenIDs = Set<String>()
        let cleanConvTitle = conversationTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "会话详情")
            : conversationTitle

        for (mIdx, msg) in messages.enumerated() {
            guard !msg.isUser else { continue }
            let msgDate = parseTimestamp(msg.timestamp ?? msg.startedAt, fallback: fallbackDate.addingTimeInterval(Double(mIdx) * 0.001))

            // 1. Explicit Structured Artifacts
            for art in msg.artifacts {
                if let entry = buildEntry(
                    rawURI: art.uri,
                    explicitTitle: art.title,
                    summary: art.summary,
                    isExplicitArtifact: true,
                    cascadeId: cascadeId,
                    conversationTitle: cleanConvTitle,
                    workspaceName: workspaceName,
                    discoveredAt: msgDate
                ), seenIDs.insert(entry.id).inserted {
                    result.append(entry)
                }
            }

            // 2. Agent Image / Media URLs
            for imgURL in msg.imageUrls {
                if let entry = buildEntry(
                    rawURI: imgURL,
                    explicitTitle: nil,
                    summary: nil,
                    isExplicitArtifact: false,
                    cascadeId: cascadeId,
                    conversationTitle: cleanConvTitle,
                    workspaceName: workspaceName,
                    discoveredAt: msgDate
                ), seenIDs.insert(entry.id).inserted {
                    result.append(entry)
                }
            }

            // 3. Deliverable Links inside Agent Markdown Text (Videos, Images, PDFs, Office, HTML, Brain Markdown)
            let text = msg.content
            if !text.isEmpty {
                let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
                let matches = markdownLinkRegex.matches(in: text, options: [], range: nsRange)
                for m in matches {
                    guard m.numberOfRanges >= 3,
                          let labelRange = Range(m.range(at: 1), in: text),
                          let urlRange = Range(m.range(at: 2), in: text) else { continue }
                    let label = String(text[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let target = String(text[urlRange])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "`\"'<>"))
                    // Skip line-range code links like file:///.../ChatView.swift#L10-L20
                    if target.contains("#L") { continue }
                    if let entry = buildEntry(
                        rawURI: target,
                        explicitTitle: label.isEmpty ? nil : label,
                        summary: nil,
                        isExplicitArtifact: false,
                        cascadeId: cascadeId,
                        conversationTitle: cleanConvTitle,
                        workspaceName: workspaceName,
                        discoveredAt: msgDate
                    ), seenIDs.insert(entry.id).inserted {
                        result.append(entry)
                    }
                }
            }
        }
        return result
    }

    private static func buildEntry(
        rawURI: String,
        explicitTitle: String?,
        summary: String?,
        isExplicitArtifact: Bool,
        cascadeId: String,
        conversationTitle: String,
        workspaceName: String,
        discoveredAt: Date
    ) -> ArtifactCatalogEntry? {
        let trimmed = rawURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("data:") else { return nil }

        let unescaped = trimmed.removingPercentEncoding ?? trimmed
        let lower = unescaped.lowercased()

        // Skip external internet links that are not served by the user's computer/gateway
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let u = URL(string: trimmed) else { return nil }
            let isGatewayFile = lower.contains("/api/v1/files/") || lower.contains("/static/")
            if !isGatewayFile && !NetworkTransport.isConfiguredGatewayOrigin(u) {
                return nil
            }
        } else if !lower.hasPrefix("file://") && !lower.hasPrefix("/static/") && !lower.hasPrefix("media:") && !lower.hasPrefix("/") {
            // Check Windows drive path like c:/...
            let bytes = Array(lower.utf8)
            let isWinDrive = bytes.count >= 3 && bytes[1] == UInt8(ascii: ":")
            if !isWinDrive && !isExplicitArtifact {
                return nil
            }
        }

        // Extract underlying file path & filename
        let underlyingPath: String = {
            if let comps = URLComponents(string: trimmed),
               let qUri = comps.queryItems?.first(where: { $0.name == "uri" || $0.name == "path" })?.value,
               !qUri.isEmpty {
                return qUri.removingPercentEncoding ?? qUri
            }
            return APIClient.normalizeGatewayFileURI(unescaped)
        }()

        // Strip query/fragment before checking extension
        let cleanPathOnly = underlyingPath
            .components(separatedBy: "?").first?
            .components(separatedBy: "#").first ?? underlyingPath
        let rawBaseName = (cleanPathOnly as NSString).lastPathComponent
        let ext = (rawBaseName as NSString).pathExtension.lowercased()

        // Skip internal scratch temporary previews unless explicitly attached as user-facing artifact
        if !isExplicitArtifact && cleanPathOnly.lowercased().contains("/scratch") && (rawBaseName.hasPrefix("scratch_") || rawBaseName.hasPrefix("tmp_")) {
            return nil
        }

        let category: ArtifactCategory
        var isMarkdown = false
        var isHTML = false

        if videoExts.contains(ext) || isVideoURL(trimmed) {
            category = .video
        } else if imageExts.contains(ext) {
            category = .image
        } else if docDeliverableExts.contains(ext) {
            category = .document
            isHTML = (ext == "html" || ext == "htm")
        } else if ext == "md" || ext == "markdown" || isExplicitArtifact {
            let pathLower = cleanPathOnly.lowercased()
            let isArtifactMarkdown = isExplicitArtifact
                || pathLower.contains("/brain/")
                || pathLower.contains("/artifacts/")
                || pathLower.contains("walkthrough")
                || pathLower.contains("implementation_plan")
            guard isArtifactMarkdown else { return nil }
            category = .document
            isMarkdown = (ext == "md" || ext == "markdown" || ext.isEmpty)
        } else {
            return nil
        }

        let canonicalID = DocumentCacheManager.canonicalMediaKey(for: trimmed)
        guard !canonicalID.isEmpty else { return nil }

        var storageName = rawBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if storageName.isEmpty || storageName == "raw" || storageName == "/" {
            switch category {
            case .video: storageName = "video.mp4"
            case .image: storageName = "image.png"
            case .document: storageName = isMarkdown ? "artifact.md" : "document"
            case .all: storageName = "artifact"
            }
        } else if isMarkdown && !(storageName as NSString).pathExtension.lowercased().contains("md") {
            storageName = "\(storageName).md"
        }

        let resolvedDisplayTitle: String = {
            if let t = explicitTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
               !t.isEmpty, t != "raw", t != "文档详情" {
                return t
            }
            return storageName
        }()

        return ArtifactCatalogEntry(
            id: canonicalID,
            uri: trimmed,
            storageFileName: storageName,
            displayTitle: resolvedDisplayTitle,
            summary: summary,
            category: category,
            isMarkdownArtifact: isMarkdown,
            isHTML: isHTML,
            cascadeId: cascadeId,
            conversationTitle: conversationTitle,
            workspaceName: workspaceName,
            discoveredAt: discoveredAt
        )
    }
}

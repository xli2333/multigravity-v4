import Foundation
import CryptoKit

/// Permanent local disk cache for downloaded documents, videos, markdown files,
/// chat images, and video poster frames.
///
/// Stored under `Library/Application Support/MultigravityMediaCache` with
/// `isExcludedFromBackup = true` so iOS never silently evicts files under cache
/// pressure and iCloud backup quota is unaffected. Files remain cached permanently
/// until the user explicitly clears local cache.
public final class DocumentCacheManager: @unchecked Sendable {
    public static let shared = DocumentCacheManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let mediaDirectory: URL
    private let legacyCacheDirectory: URL
    private let ioQueue = DispatchQueue(label: "com.multigravity.documentcache.io", qos: .utility)
    
    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let rootDir = appSupport.appendingPathComponent("MultigravityMediaCache", isDirectory: true)
        let docsDir = rootDir.appendingPathComponent("documents", isDirectory: true)
        let mediaDir = rootDir.appendingPathComponent("media", isDirectory: true)
        
        try? fileManager.createDirectory(at: docsDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        Self.markExcludedFromBackup(rootDir)
        Self.markExcludedFromBackup(docsDir)
        Self.markExcludedFromBackup(mediaDir)
        
        let baseCaches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.legacyCacheDirectory = baseCaches.appendingPathComponent("antigravity_documents", isDirectory: true)
        self.cacheDirectory = docsDir
        self.mediaDirectory = mediaDir
    }
    
    private static func markExcludedFromBackup(_ url: URL) {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }
    
    /// Produces a stable, host-agnostic cache key so switching between LAN,
    /// Tailscale, Cloudflare, and E2EE Relay always hits the exact same local file.
    public static func canonicalMediaKey(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        if let comps = URLComponents(string: trimmed) {
            let pathLower = comps.path.lowercased()
            // Gateway raw/content file proxy URLs: key by normalized underlying file URI
            if pathLower.contains("/api/v1/files/raw") || pathLower.contains("/api/v1/files/content") {
                if let uriParam = comps.queryItems?.first(where: { $0.name == "uri" || $0.name == "path" })?.value,
                   !uriParam.isEmpty {
                    let norm = APIClient.normalizeGatewayFileURI(uriParam)
                    return "gw_file:\(norm.lowercased())"
                }
            }
            // Gateway static assets: key by path only (host-independent)
            if pathLower.hasPrefix("/static/") {
                return "gw_static:\(comps.path)"
            }
            // External HTTP(S) URLs: strip transient auth query tokens
            if let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                var clean = comps
                if let items = clean.queryItems, !items.isEmpty {
                    let filtered = items.filter { item in
                        let k = item.name.lowercased()
                        return k != "auth_token" && k != "device_token" && k != "token" && k != "ticket"
                    }
                    clean.queryItems = filtered.isEmpty ? nil : filtered
                }
                return "url:\(clean.url?.absoluteString ?? trimmed)"
            }
        }
        
        // Bare local/gateway file path or file:// URI
        let norm = APIClient.normalizeGatewayFileURI(trimmed)
        return "gw_file:\(norm.lowercased())"
    }
    
    private func sha256Hex(_ input: String, prefixLength: Int = 24) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(prefixLength))
    }
    
    /// Computes deterministic target URL in the permanent documents cache directory.
    public func cacheFileURL(for uri: String, fileName: String, cascadeId: String? = nil) -> URL {
        cacheFileURL(in: cacheDirectory, for: uri, fileName: fileName, cascadeId: cascadeId, canonical: true)
    }
    
    private func cacheFileURL(
        in directory: URL,
        for uri: String,
        fileName: String,
        cascadeId: String? = nil,
        canonical: Bool
    ) -> URL {
        let baseKey = canonical
            ? Self.canonicalMediaKey(for: uri)
            : uri.trimmingCharacters(in: .whitespacesAndNewlines)
        let scopeKey: String
        if let cid = cascadeId?.trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty, !baseKey.contains(cid) {
            scopeKey = "\(cid)_\(baseKey)"
        } else {
            scopeKey = baseKey
        }
        let hashPrefix = sha256Hex(scopeKey, prefixLength: 16)
        
        let rawExt = (fileName as NSString).pathExtension
        let ext = rawExt.isEmpty ? (uri.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).pathExtension : rawExt
        let rawBase = (fileName as NSString).deletingPathExtension
        let base = (rawBase.isEmpty ? "document" : rawBase)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "&", with: "_")
        
        let finalFileName = ext.isEmpty ? "\(base)_\(hashPrefix)" : "\(base)_\(hashPrefix).\(ext)"
        return directory.appendingPathComponent(finalFileName)
    }
    
    private func metadataURL(for fileURL: URL) -> URL {
        return fileURL.appendingPathExtension("meta.json")
    }
    
    private func validExistingFile(at url: URL) -> URL? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? Int64) ?? 0
        return size > 0 ? url : nil
    }
    
    private func hashTokens(for uri: String, cascadeId: String?) -> [String] {
        let baseKey = Self.canonicalMediaKey(for: uri)
        guard !baseKey.isEmpty else { return [] }
        var tokens: [String] = []
        if let cid = cascadeId?.trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty, !baseKey.contains(cid) {
            tokens.append("_\(sha256Hex("\(cid)_\(baseKey)", prefixLength: 16))")
        }
        let unoped = "_\(sha256Hex(baseKey, prefixLength: 16))"
        if !tokens.contains(unoped) {
            tokens.append(unoped)
        }
        return tokens
    }
    
    /// Checks if a valid non-empty permanently cached file exists for the given uri/fileName.
    public func getCachedFile(for uri: String, fileName: String, cascadeId: String? = nil) -> URL? {
        if let hit = validExistingFile(at: cacheFileURL(for: uri, fileName: fileName, cascadeId: cascadeId)) {
            return hit
        }
        if cascadeId != nil,
           let hit = validExistingFile(at: cacheFileURL(for: uri, fileName: fileName, cascadeId: nil)) {
            return hit
        }
        // Hash-token fallback: matches files auto-downloaded under server Content-Disposition filename
        // even when tapped in Chat under a custom Markdown display label.
        let tokens = hashTokens(for: uri, cascadeId: cascadeId)
        if !tokens.isEmpty,
           let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for token in tokens {
                if let match = files.first(where: { candidate in
                    let name = candidate.lastPathComponent
                    guard !name.hasSuffix(".meta.json") else { return false }
                    return name.contains(token) && validExistingFile(at: candidate) != nil
                }) {
                    return match
                }
            }
        }
        // Transparent fallback to pre-upgrade Library/Caches directory if present
        if let legacyHit = validExistingFile(at: cacheFileURL(in: legacyCacheDirectory, for: uri, fileName: fileName, cascadeId: cascadeId, canonical: false)) {
            return legacyHit
        }
        if cascadeId != nil,
           let legacyHit = validExistingFile(at: cacheFileURL(in: legacyCacheDirectory, for: uri, fileName: fileName, cascadeId: nil, canonical: false)) {
            return legacyHit
        }
        return nil
    }
    
    /// Saves a downloaded file (video, PDF, Office doc, archive, etc.) into permanent disk cache.
    @discardableResult
    public func saveToCache(from sourceURL: URL, for uri: String, fileName: String, cascadeId: String? = nil) throws -> URL {
        let destination = cacheFileURL(for: uri, fileName: fileName, cascadeId: cascadeId)
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: sourceURL, to: destination)
        Self.markExcludedFromBackup(destination)
        return destination
    }
    
    // MARK: - Permanent Binary Media Cache (Images & Video Posters)
    
    private func mediaFileURL(for url: URL, namespace: String) -> URL {
        let canonical = Self.canonicalMediaKey(for: url.absoluteString)
        let digest = sha256Hex("\(namespace):\(canonical)", prefixLength: 32)
        return mediaDirectory.appendingPathComponent("\(namespace)_\(digest).bin")
    }
    
    /// Synchronously reads cached image/poster raw bytes from permanent local disk cache.
    public func cachedMediaData(for url: URL, namespace: String = "img") -> Data? {
        let fileURL = mediaFileURL(for: url, namespace: namespace)
        if fileManager.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
           !data.isEmpty {
            return data
        }
        if namespace == "img",
           let docHit = getCachedFile(for: url.absoluteString, fileName: url.lastPathComponent),
           let data = try? Data(contentsOf: docHit, options: .mappedIfSafe),
           !data.isEmpty {
            return data
        }
        return nil
    }
    
    /// Asynchronously writes image/poster raw bytes to permanent local disk cache.
    public func saveMediaData(_ data: Data, for url: URL, namespace: String = "img") {
        guard !data.isEmpty else { return }
        let dest = mediaFileURL(for: url, namespace: namespace)
        ioQueue.async {
            if self.fileManager.fileExists(atPath: dest.path) {
                return
            }
            do {
                try data.write(to: dest, options: .atomic)
                Self.markExcludedFromBackup(dest)
            } catch {
                // Non-fatal: RAM cache still holds the decoded image
            }
        }
    }
    
    // MARK: - Markdown Documents Persistent Cache
    
    /// Saves markdown document content and metadata to permanent local disk cache.
    @discardableResult
    public func saveMarkdownToCache(
        response: FileContentResponse,
        for uri: String,
        fileName: String,
        cascadeId: String? = nil
    ) throws -> (fileURL: URL, response: FileContentResponse) {
        var resolvedName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedName.isEmpty {
            resolvedName = "document.md"
        } else if !(resolvedName as NSString).pathExtension.lowercased().contains("md") {
            resolvedName = "\(resolvedName).md"
        }
        let fileURL = cacheFileURL(for: uri, fileName: resolvedName, cascadeId: cascadeId)
        guard let data = response.content.data(using: .utf8) else {
            throw NSError(domain: "DocumentCacheManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid markdown content encoding"])
        }
        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }
        try data.write(to: fileURL, options: .atomic)
        Self.markExcludedFromBackup(fileURL)
        
        let meta = metadataURL(for: fileURL)
        if let metaData = try? JSONEncoder().encode(response) {
            if fileManager.fileExists(atPath: meta.path) {
                try? fileManager.removeItem(at: meta)
            }
            try? metaData.write(to: meta, options: .atomic)
            Self.markExcludedFromBackup(meta)
        }
        return (fileURL, response)
    }
    
    /// Retrieves permanently cached markdown document content and metadata if available on disk.
    public func getCachedMarkdown(
        for uri: String,
        fileName: String,
        cascadeId: String? = nil
    ) -> (fileURL: URL, response: FileContentResponse)? {
        var resolvedName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedName.isEmpty {
            resolvedName = "document.md"
        } else if !(resolvedName as NSString).pathExtension.lowercased().contains("md") {
            resolvedName = "\(resolvedName).md"
        }
        
        let checkCandidate: (URL) -> (fileURL: URL, response: FileContentResponse)? = { url in
            guard self.fileManager.fileExists(atPath: url.path) else { return nil }
            let meta = self.metadataURL(for: url)
            if self.fileManager.fileExists(atPath: meta.path),
               let metaData = try? Data(contentsOf: meta),
               let decoded = try? JSONDecoder().decode(FileContentResponse.self, from: metaData),
               !decoded.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (url, decoded)
            }
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let fallbackResp = FileContentResponse(
                    uri: uri,
                    filename: resolvedName,
                    content: text,
                    summary: nil,
                    requestFeedback: nil,
                    userFacing: nil
                )
                return (url, fallbackResp)
            }
            return nil
        }
        
        let fileURL = cacheFileURL(for: uri, fileName: resolvedName, cascadeId: cascadeId)
        if let hit = checkCandidate(fileURL) {
            return hit
        }
        if cascadeId != nil {
            let fallbackURL = cacheFileURL(for: uri, fileName: resolvedName, cascadeId: nil)
            if let hit = checkCandidate(fallbackURL) {
                return hit
            }
        }
        return nil
    }
    
    // MARK: - Storage Accounting & Explicit Manual Clear
    
    private func directoryByteSize(_ dir: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  vals.isRegularFile == true,
                  let sz = vals.fileSize else { continue }
            total += Int64(sz)
        }
        return total
    }
    
    /// Total bytes occupied by permanently cached images, videos, and documents.
    public func totalCacheSizeBytes() -> Int64 {
        directoryByteSize(cacheDirectory)
            + directoryByteSize(mediaDirectory)
            + directoryByteSize(legacyCacheDirectory)
    }
    
    /// Human-readable disk usage string (e.g. "12.4 MB" or "0 KB").
    public func formattedCacheSize() -> String {
        let bytes = totalCacheSizeBytes()
        if bytes <= 0 { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Explicitly clears all cached documents, videos, images, and posters from disk & RAM.
    public func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.removeItem(at: mediaDirectory)
        try? fileManager.removeItem(at: legacyCacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        Self.markExcludedFromBackup(cacheDirectory)
        Self.markExcludedFromBackup(mediaDirectory)
        WeChatArchiveCacheManager.shared.clearCache()
        MarkdownImageCache.shared.clearMemory()
        VideoThumbnailCache.shared.clearMemory()
        URLCache.shared.removeAllCachedResponses()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .artifactCacheDidClearAll, object: nil)
        }
    }
    
    // MARK: - Per-Artifact Inspection & Targeted Local Eviction
    
    /// Returns the local cached URL and byte size on iPhone if this artifact is currently stored on disk.
    public func localArtifactFileInfo(
        for uri: String,
        fileName: String,
        cascadeId: String? = nil,
        isMarkdown: Bool = false,
        resolvedMediaURL: URL? = nil
    ) -> (url: URL, byteSize: Int64)? {
        let sizeOf: (URL) -> Int64 = { target in
            let attrs = try? self.fileManager.attributesOfItem(atPath: target.path)
            return (attrs?[.size] as? Int64) ?? 0
        }
        if isMarkdown,
           let mdHit = getCachedMarkdown(for: uri, fileName: fileName, cascadeId: cascadeId) {
            let sz = sizeOf(mdHit.fileURL)
            if sz > 0 {
                return (mdHit.fileURL, sz)
            }
        }
        if let docHit = getCachedFile(for: uri, fileName: fileName, cascadeId: cascadeId) {
            let sz = sizeOf(docHit)
            if sz > 0 {
                return (docHit, sz)
            }
        }
        if let mediaURL = resolvedMediaURL,
           let mediaHit = validExistingFile(at: mediaFileURL(for: mediaURL, namespace: "img")) {
            let sz = sizeOf(mediaHit)
            if sz > 0 {
                return (mediaHit, sz)
            }
        }
        return nil
    }
    
    /// Deletes ONLY this single artifact's cached local files from the iPhone without touching server files or catalog metadata.
    public func evictSingleArtifact(
        uri: String,
        fileName: String,
        cascadeId: String? = nil,
        resolvedMediaURL: URL? = nil
    ) {
        let directCandidates: [URL] = [
            cacheFileURL(for: uri, fileName: fileName, cascadeId: cascadeId),
            cacheFileURL(for: uri, fileName: fileName, cascadeId: nil),
            cacheFileURL(in: legacyCacheDirectory, for: uri, fileName: fileName, cascadeId: cascadeId, canonical: false),
            cacheFileURL(in: legacyCacheDirectory, for: uri, fileName: fileName, cascadeId: nil, canonical: false)
        ]
        for candidate in directCandidates {
            if fileManager.fileExists(atPath: candidate.path) {
                try? fileManager.removeItem(at: candidate)
            }
            let meta = metadataURL(for: candidate)
            if fileManager.fileExists(atPath: meta.path) {
                try? fileManager.removeItem(at: meta)
            }
        }
        
        let tokens = hashTokens(for: uri, cascadeId: cascadeId)
        if !tokens.isEmpty {
            for dir in [cacheDirectory, legacyCacheDirectory] {
                if let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for file in files {
                        let name = file.lastPathComponent
                        if tokens.contains(where: { name.contains($0) }) {
                            try? fileManager.removeItem(at: file)
                        }
                    }
                }
            }
        }
        
        if let mediaURL = resolvedMediaURL {
            let imgBin = mediaFileURL(for: mediaURL, namespace: "img")
            if fileManager.fileExists(atPath: imgBin.path) {
                try? fileManager.removeItem(at: imgBin)
            }
            MarkdownImageCache.shared.remove(for: mediaURL)
        }
    }
}

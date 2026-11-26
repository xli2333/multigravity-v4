import Foundation
import UIKit

/// Non-image attachments (documents, archives, source files).
///
/// Picking a file copies it into app storage, then uploads it to the gateway right away so that
/// "send" only has to reference the returned attachment id. State is persisted per draft
/// (see `DraftFileStore`) so that it survives leaving the screen.
extension ChatViewModel {
    /// Adds files picked with the system document picker or shared into the app.
    /// URLs may be security-scoped; they are copied before this returns.
    @MainActor
    public func addFiles(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        if draftKey.isEmpty {
            originDraftId = "local_draft_\(UUID().uuidString)"
        }
        let key = draftKey
        guard !key.isEmpty else { return }
        let dir = DraftFileStore.shared.directory(for: key)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        var accepted: [DraftFile] = []
        var rejected: [String] = []
        
        let tempRoot = NSTemporaryDirectory()
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
                // Clean up `UIDocumentPickerViewController(..., asCopy: true)` staged copy in tmp/
                if url.path.hasPrefix(tempRoot) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            
            var name = url.lastPathComponent
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = "attachment"
            }
            let existing = selectedFiles + accepted
            let declared = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value
                ?? (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
                ?? -1
            if let reason = AttachmentRules.validate(name: name, size: declared > 0 ? declared : 1, existing: existing) {
                rejected.append(reason)
                continue
            }
            
            let fileUUID = UUID().uuidString
            var localName = "\(fileUUID)-\(Self.safeLocalName(name))"
            var target = dir.appendingPathComponent(localName)
            var didCopy = false

            // 1. Fast direct copy (works immediately for `asCopy: true` and `Documents/Inbox` files with zero XPC/entitlement dependency)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                try? FileManager.default.removeItem(at: target)
                didCopy = (try? FileManager.default.copyItem(at: url, to: target)) != nil
                if !didCopy, let rawData = try? Data(contentsOf: url) {
                    didCopy = (try? rawData.write(to: target, options: .atomic)) != nil
                }
            }

            // 2. Coordinated fallback for directory bundles (.pages/.numbers/.rtfd) or unmaterialized cloud items
            if !didCopy {
                var coordinationError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [.forUploading], error: &coordinationError) { readURL in
                    let readExt = readURL.pathExtension.lowercased()
                    let origExt = (name as NSString).pathExtension.lowercased()
                    if readExt == "zip" && origExt != "zip" {
                        name = "\(name).zip"
                        localName = "\(fileUUID)-\(Self.safeLocalName(name))"
                        target = dir.appendingPathComponent(localName)
                    }
                    try? FileManager.default.removeItem(at: target)
                    didCopy = (try? FileManager.default.copyItem(at: readURL, to: target)) != nil
                }
            }

            if !didCopy, let rawData = try? Data(contentsOf: url) {
                didCopy = (try? rawData.write(to: target, options: .atomic)) != nil
            }

            guard didCopy else {
                rejected.append(String(localized: "无法读取文件：\(name)"))
                continue
            }
            let size = ((try? FileManager.default.attributesOfItem(atPath: target.path))?[.size] as? NSNumber)?.int64Value ?? 0
            // Re-validate with the real size (the declared one may be unavailable).
            if let reason = AttachmentRules.validate(name: name, size: size, existing: existing) {
                try? FileManager.default.removeItem(at: target)
                rejected.append(reason)
                continue
            }
            accepted.append(DraftFile(name: name, size: size, fileName: localName))
        }
        
        if !accepted.isEmpty {
            selectedFiles.append(contentsOf: accepted)
            persistDraftFiles()
            for file in accepted { startUpload(fileId: file.id) }
        }
        if !rejected.isEmpty {
            var seen = Set<String>()
            let noticeText = rejected.filter { seen.insert($0).inserted }.joined(separator: "\n")
            // Defer alert presentation until UIDocumentPickerViewController finishes dismissing so UIKit never drops the alert.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.attachmentNotice = noticeText
            }
        }
    }
    
    private static func safeLocalName(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters)
        let cleaned = name.components(separatedBy: bad).joined(separator: "_")
        return String(cleaned.prefix(100))
    }
    
    @MainActor
    func persistDraftFiles() {
        let key = draftKey
        guard !key.isEmpty else { return }
        DraftFileStore.shared.save(key: key, files: selectedFiles)
    }
    
    @MainActor
    private func updateFile(_ id: String, persist: Bool, _ transform: (inout DraftFile) -> Void) {
        guard let idx = selectedFiles.firstIndex(where: { $0.id == id }) else { return }
        transform(&selectedFiles[idx])
        if persist { persistDraftFiles() }
    }
    
    @MainActor
    public func startUpload(fileId: String) {
        guard let file = selectedFiles.first(where: { $0.id == fileId }),
              let baseURL = settings.serverURL else { return }
        let key = draftKey
        let localURL = DraftFileStore.shared.localURL(for: file, key: key)
        fileUploadTasks[fileId]?.cancel()
        updateFile(fileId, persist: true) { $0.state = .uploading; $0.progress = 0; $0.error = nil }
        
        let client = apiClient
        fileUploadTasks[fileId] = Task { [weak self] in
            do {
                let uploaded = try await client.uploadAttachment(
                    fileURL: localURL,
                    displayName: file.name,
                    baseURL: baseURL,
                    onProgress: { progress in
                        Task { @MainActor [weak self] in
                            self?.updateFile(fileId, persist: false) { file in
                                guard file.state == .uploading else { return }
                                file.progress = max(file.progress, progress)
                            }
                        }
                    }
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.updateFile(fileId, persist: true) {
                        $0.state = .done
                        $0.progress = 1
                        $0.attachmentId = uploaded.id
                        $0.line = uploaded.line
                        $0.error = nil
                    }
                    self?.fileUploadTasks[fileId] = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.updateFile(fileId, persist: true) {
                        $0.state = .failed
                        $0.error = error.localizedDescription
                    }
                    self?.fileUploadTasks[fileId] = nil
                }
            }
        }
    }
    
    @MainActor
    public func retryFileUpload(_ fileId: String) {
        startUpload(fileId: fileId)
    }
    
    @MainActor
    public func removeFile(_ fileId: String) {
        fileUploadTasks[fileId]?.cancel()
        fileUploadTasks[fileId] = nil
        guard let file = selectedFiles.first(where: { $0.id == fileId }) else { return }
        selectedFiles.removeAll(where: { $0.id == fileId })
        try? FileManager.default.removeItem(at: DraftFileStore.shared.localURL(for: file, key: draftKey))
        persistDraftFiles()
    }
    
    /// True when every attached file has been uploaded (or there are none).
    public var allFilesUploaded: Bool {
        selectedFiles.allSatisfy { $0.isUploaded }
    }
    
    public var hasPendingFileUploads: Bool {
        selectedFiles.contains { $0.state == .pending || $0.state == .uploading }
    }
    
    /// Reloads a draft's files from storage and resumes any upload that is not already running.
    @MainActor
    public func restoreDraftFiles() {
        let key = draftKey
        guard !key.isEmpty else { return }
        let saved = DraftFileStore.shared.load(key: key)
        guard !saved.isEmpty else { return }
        let inMemory = Dictionary(uniqueKeysWithValues: selectedFiles.map { ($0.id, $0) })
        let merged: [DraftFile] = saved.map { f in
            if fileUploadTasks[f.id] != nil { return inMemory[f.id] ?? f }
            if f.state == .done { return f }
            var copy = f
            copy.state = .pending
            copy.progress = 0
            copy.error = nil
            return copy
        }
        if merged != selectedFiles { selectedFiles = merged }
        for file in merged where file.state == .pending && fileUploadTasks[file.id] == nil {
            startUpload(fileId: file.id)
        }
    }
}

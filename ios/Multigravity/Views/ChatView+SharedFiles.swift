import SwiftUI

/// Files shared into the app from other apps and routed to this conversation (see `ShareInbox`).
extension ChatView {
    /// Drops delivered files into the input bar as attachments. Never sends anything by itself.
    @MainActor
    func consumeSharedFiles() {
        var candidateKeys: [String] = []
        for k in [viewModel.cascadeId, viewModel.draftKey, initialConversation?.id ?? ""] where !k.isEmpty && !candidateKeys.contains(k) {
            candidateKeys.append(k)
        }
        var shared: [SharedFile] = []
        for k in candidateKeys {
            shared.append(contentsOf: ShareInbox.shared.takeDelivery(for: k))
        }
        guard !shared.isEmpty else { return }
        
        let docs = shared.filter { !$0.isImage }
        if !docs.isEmpty { viewModel.addFiles(from: docs.map(\.url)) }
        
        var compressed: [Data] = []
        for file in shared where file.isImage {
            if let image = UIImage(contentsOfFile: file.url.path), let data = compressAndResizeImage(image) {
                compressed.append(data)
            }
        }
        if !compressed.isEmpty { viewModel.appendDraftImages(compressed) }
        
        // addFiles copies synchronously, so the staged copies are no longer needed.
        for file in shared {
            try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
        }
    }
}

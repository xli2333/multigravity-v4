import UIKit
import Photos
import UniformTypeIdentifiers
import ZLPhotoBrowser

@MainActor
public final class ZLPhotoPickerBridge {
    public static let shared = ZLPhotoPickerBridge()
    
    // 保持对当前活动 picker 的引用，避免被提前释放
    private var activePicker: ZLPhotoPicker?
    
    private init() {
        configureDefaults()
    }
    
    private func configureDefaults() {
        let config = ZLPhotoConfiguration.default()
        // 只允许图片，不允许视频，支持相册内点击预览大图
        config.allowSelectImage = true
        config.allowSelectVideo = false
        config.allowPreviewPhotos = true
        config.showPreviewButtonInAlbum = true
        
        // 核心：相册中首格展示相机拍照（微信同款）
        config.allowTakePhotoInLibrary = true
        config.cameraConfiguration.allowTakePhoto = true
        config.cameraConfiguration.allowRecordVideo = false
        
        // 禁用图片与视频编辑，保证快速高效选择
        config.allowEditImage = false
        config.allowEditVideo = false
        
        // UI 配置
        let uiConfig = ZLPhotoUIConfiguration.default()
        // 倒序展示：最新的照片在最上面，相机固定在第 1 个格子（index 0）
        uiConfig.sortAscending = false
        uiConfig.showSelectedMask = true
        uiConfig.themeColor = .systemIndigo
    }
    
    /// 打开相册与相机（首格即相机拍照）
    /// - Parameters:
    ///   - maxCount: 最多可选照片数
    ///   - onImagesPicked: 选取或拍照完成后的图片回调
    public func present(maxCount: Int = 5, onImagesPicked: @escaping ([UIImage]) -> Void) {
        guard maxCount > 0 else { return }
        
        guard let topVC = getTopViewController() else {
            return
        }
        
        let config = ZLPhotoConfiguration.default()
        config.maxSelectCount = maxCount
        
        let picker = ZLPhotoPicker()
        self.activePicker = picker
        
        picker.selectImageBlock = { [weak self] results, isOriginal in
            self?.activePicker = nil
            let images = results.map { $0.image }
            guard !images.isEmpty else { return }
            onImagesPicked(images)
        }
        
        picker.cancelBlock = { [weak self] in
            self?.activePicker = nil
        }
        
        picker.showPhotoLibrary(sender: topVC)
    }
    
    /// 获取当前最顶层的 UIViewController
    private func getTopViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        guard let window = activeScene?.windows.first(where: { $0.isKeyWindow }) ?? activeScene?.windows.first else {
            return nil
        }
        
        var top = window.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

/// Imperative UIKit bridge for `UIDocumentPickerViewController(forOpeningContentTypes:asCopy: true)`.
///
/// Why `asCopy: true` instead of SwiftUI `.fileImporter`:
/// - SwiftUI `.fileImporter` hardcodes `asCopy: false` (security-scoped open-in-place), which fails silently
///   under re-signed / sideloaded provisioning profiles (`全能签` / Feather / TrollStore) when FileProvider or
///   iCloud container entitlements are stripped.
/// - With `asCopy: true`, iOS's privileged system `DocumentManager` XPC service copies the picked files directly
///   into our app's own `tmp/` directory before invoking the delegate, guaranteeing 100% readable local files.
@MainActor
public final class DocumentPickerBridge: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    public static let shared = DocumentPickerBridge()

    private var activePicker: UIDocumentPickerViewController?
    private var onFilesPickedHandler: (([URL]) -> Void)?

    private override init() {
        super.init()
    }

    public func present(onFilesPicked: @escaping ([URL]) -> Void) {
        presentWhenReady(attempt: 0, onFilesPicked: onFilesPicked)
    }

    private func presentWhenReady(attempt: Int, onFilesPicked: @escaping ([URL]) -> Void) {
        guard let window = activeKeyWindow(), let root = window.rootViewController else {
            return
        }

        var top: UIViewController = root
        while let presented = top.presentedViewController {
            if presented.isBeingDismissed {
                if attempt < 12 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                        self?.presentWhenReady(attempt: attempt + 1, onFilesPicked: onFilesPicked)
                    }
                }
                return
            }
            top = presented
        }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .data, .content], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        picker.presentationController?.delegate = self

        self.activePicker = picker
        self.onFilesPickedHandler = onFilesPicked
        top.present(picker, animated: true)
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let callback = onFilesPickedHandler
        activePicker = nil
        onFilesPickedHandler = nil
        guard !urls.isEmpty else { return }
        callback?(urls)
    }

    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        activePicker = nil
        onFilesPickedHandler = nil
    }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        activePicker = nil
        onFilesPickedHandler = nil
    }

    private func activeKeyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return activeScene?.windows.first(where: { $0.isKeyWindow }) ?? activeScene?.windows.first
    }
}

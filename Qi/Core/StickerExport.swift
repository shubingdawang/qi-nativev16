import Foundation
import Photos

/// 把表情存进手机相册：动图按原文件存，存进去还是会动的，
/// 微信、QQ 里从相册挑就能当表情发。
enum StickerExport {

    /// 存进相册。返回给她看的那一句
    @MainActor
    static func saveToPhotos(_ url: URL) async -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "这张表情的文件没找到。" }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return "没有相册权限。去「设置 → 栖 → 照片」里打开「仅添加照片」。"
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                // 按文件存（不转成 UIImage），GIF 才保留每一帧
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, fileURL: url, options: nil)
            }
            return "已存到手机相册。"
        } catch {
            return "没存上：\(error.localizedDescription)"
        }
    }
}

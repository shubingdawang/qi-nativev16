import Foundation
import UIKit

/// 把数据以 JSON 文件的形式存在 App 自己的 Documents 目录里。
/// 这样卸载 App 才会清空，平时关机重启都不会丢。
enum Storage {

    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var imagesURL: URL {
        let url = documentsURL.appendingPathComponent("Images", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func fileURL(_ name: String) -> URL {
        documentsURL.appendingPathComponent(name)
    }

    /// 解不出来的文件都留在这儿，一份都不丢
    nonisolated(unsafe) private(set) static var salvaged: [String] = []

    /// 读一份数据。
    ///
    /// **解码失败绝不能静默地当作"没有"。**
    ///
    /// 每一处调用都写成 `Storage.load(…) ?? 默认值`，所以只要这里返回 nil，
    /// 上面那一层就当成"第一次用"——providers.json 解不开等于**密钥全没**，
    /// conversations.json 解不开等于**聊天记录全没**，而且下一次保存
    /// 就把空的那份原地写回去，覆盖掉本来还好好的文件。
    ///
    /// 最常见的失败原因是**加了一个新字段**：合成的解码器碰到缺的键会直接抛，
    /// 属性写了默认值也不管用（那是给 memberwise init 用的，解码器不看）。
    /// 那几个要紧的类型现在都自己写了容错解码器，但兜底这一层还是得有：
    /// 万一以后又有谁没写，至少文件被挪到一边留着，而不是被覆盖掉。
    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let url = fileURL(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // 挪到一边，别让下一次保存把它盖掉
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = fileURL("\(name).坏了-\(stamp)")
            try? FileManager.default.moveItem(at: url, to: backup)
            salvaged.append(backup.lastPathComponent)
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(value) else { return }
        let url = fileURL(name)
        try? data.write(to: url, options: .atomic)
    }
}

/// 图片单独存成文件，不塞进 JSON 里，不然会越来越卡
enum ImageStore {

    /// 存一张图，返回文件名
    @discardableResult
    static func save(_ image: UIImage, quality: CGFloat = 0.85) -> String? {
        let resized = downscale(image, maxSide: 2048)
        guard let data = resized.jpegData(compressionQuality: quality) else { return nil }
        let name = UUID().uuidString + ".jpg"
        let url = Storage.imagesURL.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func save(data: Data, ext: String = "jpg") -> String? {
        let name = UUID().uuidString + "." + ext
        let url = Storage.imagesURL.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func url(for name: String) -> URL {
        Storage.imagesURL.appendingPathComponent(name)
    }

    static func load(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: name).path)
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }

    /// 转成 base64 的 data URL，发给多模态接口用
    /// 直接把一张图转成 data URL，不经过磁盘
    static func base64DataURL(_ image: UIImage, maxSide: CGFloat = 1280) -> String? {
        let small = downscale(image, maxSide: maxSide)
        guard let data = small.jpegData(compressionQuality: 0.85) else { return nil }
        return "data:image/jpeg;base64," + data.base64EncodedString()
    }

    /// 存一张带透明通道的图。像素图必须走 png，jpg 会把透明填成黑的。
    static func savePNG(_ image: UIImage) -> String? {
        guard let data = image.pngData() else { return nil }
        return save(data: data, ext: "png")
    }

    static func base64DataURL(_ name: String, maxSide: CGFloat = 1280) -> String? {
        guard let image = load(name) else { return nil }
        let small = downscale(image, maxSide: maxSide)
        guard let data = small.jpegData(compressionQuality: 0.8) else { return nil }
        return "data:image/jpeg;base64," + data.base64EncodedString()
    }

    /// 图太大就等比缩小，省内存也省流量
    static func downscale(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let longest = max(w, h)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let newSize = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

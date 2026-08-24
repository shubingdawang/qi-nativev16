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

    /// 按文件**本来的格式**原样存，一个字节都不重编码。
    ///
    /// 为什么要有这个：`save(_ image:)` 收的是 UIImage，
    /// 而 UIImage 只拿得到 gif 的**第一帧**——她发一张会动的图进来，
    /// 存完就不动了。她说的第 8 条（「保存我的 gif 只能保存成表情包，
    /// 不会动的」）根子在这儿，不在存表情那一步：
    /// **动画在她按下发送的那一刻就已经被压没了。**
    static func saveOriginal(_ data: Data) -> String? {
        save(data: data, ext: sniffExt(data))
    }

    /// 认一下这是什么图。只看文件头几个字节，不猜扩展名。
    static func sniffExt(_ data: Data) -> String {
        let head = [UInt8](data.prefix(12))
        if head.count >= 6, head[0] == 0x47, head[1] == 0x49, head[2] == 0x46 { return "gif" }
        if head.count >= 8, head[0] == 0x89, head[1] == 0x50 { return "png" }
        if head.count >= 12, head[8] == 0x57, head[9] == 0x45,
           head[10] == 0x42, head[11] == 0x50 { return "webp" }
        return "jpg"
    }

    /// 会动的图。存表情、发图之前都要问一句——动图得走原始字节那条路。
    static func isAnimated(_ data: Data) -> Bool { sniffExt(data) == "gif" }

    static func url(for name: String) -> URL {
        Storage.imagesURL.appendingPathComponent(name)
    }

    static func load(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: name).path)
    }

    // MARK: 缓存

    /// 已经解开的图。**画面里反复要用的那些必须走这儿。**
    ///
    /// 她说小屋「特别特别卡」，另一半根子在这儿：
    /// `load` 每叫一次就**从磁盘读一遍、把 PNG 重新解码一遍**。
    /// 而 SwiftUI 的 body 是**每一帧都会重新跑**的——
    /// 屋里摆十件她自己的家具图，clawd 还在走路，
    /// 于是「每秒钟从磁盘解码六百张 PNG」。
    ///
    /// `NSCache` 而不是字典：内存紧张的时候系统会自己把它清掉，
    /// 不会因为她导了三百张图就把 App 撑爆。
    private static let memo: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 240
        return c
    }()

    /// 解码一次，之后都从内存里拿。
    ///
    /// **凡是画在会动的画面里的图，一律用这个，别用 `load`。**
    static func cached(_ name: String) -> UIImage? {
        guard !name.isEmpty else { return nil }
        let key = name as NSString
        if let hit = memo.object(forKey: key) { return hit }
        guard let img = load(name) else { return nil }
        memo.setObject(img, forKey: key)
        return img
    }

    /// 这张图换了内容（同名覆盖）或者被删了，把缓存里那份扔掉
    static func forget(_ name: String) {
        guard !name.isEmpty else { return }
        memo.removeObject(forKey: name as NSString)
    }

    static func delete(_ name: String) {
        forget(name)
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

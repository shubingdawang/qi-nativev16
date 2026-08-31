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

    /// 一个文件在 Documents 底下的**相对路径**（`Images/abc.jpg`、
    /// `Memory/transcripts/0f61881f.json` 这样）。不在 Documents 底下就返回 nil。
    ///
    /// ## ⚠️ 这个函数是从一个很贵的 bug 里长出来的
    ///
    /// 备份原来是这么算键的：
    ///
    /// ```swift
    /// let key = url.path.hasPrefix(root.path)
    ///     ? String(url.path.dropFirst(root.path.count))…
    ///     : url.lastPathComponent          // ← 一路走的是这一支
    /// ```
    ///
    /// **`hasPrefix` 永远是 false。** 因为这两个路径根本不是同一种写法：
    ///
    /// · `FileManager.urls(for: .documentDirectory…)` 给的是
    ///   `/var/mobile/Containers/Data/Application/…/Documents`
    /// · `FileManager.enumerator(at:)` 吐出来的是
    ///   `/private/var/mobile/Containers/…`
    ///
    /// iOS 上 `/var` 是指向 `/private/var` 的软链，两条路指的是同一个地方，
    /// **但字符串不一样**。于是每个文件都掉进了 `lastPathComponent` 那一支，
    /// 整份备份里的键全成了光秃秃的文件名。
    ///
    /// 后果是还原那天才显形，而且是**全线的**：
    /// `Images/a.jpg` 变成 `a.jpg` → 放回 Documents 根目录 → 相册里一张图都没有；
    /// `Memory/memories.json` 变成 `memories.json` → 记忆库 0 条、日记 0 篇、存档 0 份；
    /// `Voices/x.mp3` → 语音条点不响；`Music/x.mp3` → 歌放不出来。
    /// 她看到的四五个「毛病」是**同一个 bug**。
    ///
    /// 而它躲了这么多窗，是因为**导出那头看不出任何异常**：
    /// 文件数对、图片数对、包的大小也对——**每一个字节都在里面，
    /// 只是每一个都被贴错了标签。**
    ///
    /// ⚠️ 规矩：**比路径不许比字符串。** 两边都 `resolvingSymlinksInPath()`
    /// 之后按 `pathComponents` 一段一段比，这是唯一稳的比法。
    static func relativePath(of url: URL, under root: URL? = nil) -> String? {
        let base = (root ?? documentsURL).resolvingSymlinksInPath()
            .standardizedFileURL.pathComponents
        let full = url.resolvingSymlinksInPath()
            .standardizedFileURL.pathComponents
        guard full.count > base.count, Array(full.prefix(base.count)) == base
        else { return nil }
        return full.dropFirst(base.count).joined(separator: "/")
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

    /// 写盘那一下**挪到后台**。
    ///
    /// ## 为什么要有这一条
    ///
    /// 她报的：「有时候还是会卡顿，比如发消息的时候我切到左侧栏去看其他数据。」
    ///
    /// 聊天记录那份 JSON 现在有好几兆（她一个窗口就聊到 96k tokens）。
    /// `save` 是**编码 + 写盘全在叫它的那个线程上**，而叫它的是主线程——
    /// 流式输出每 400 毫秒来一次。她这时候切页面，
    /// 新页面要布局要渲染，正好排在那几兆 JSON 后面。
    ///
    /// ## 两个坑
    ///
    /// ⚠️ **顺序不能乱。** 两次保存要是并发跑，先发的可能后落盘，
    /// 把新的盖成旧的。所以走一条**串行队列**，一件一件来。
    ///
    /// ⚠️ 快照要在**调用方那个线程**上取好再递进来。
    /// 把 `self.conversations` 直接扔进后台闭包的话，
    /// 后台读的时候主线程可能正在改它。
    private static let diskQueue =
        DispatchQueue(label: "qi.storage.disk", qos: .utility)

    /// ⚠️ 约束只写 `Encodable`，**不写 `Sendable`**。
    ///
    /// 工程跑的是 Swift 5 语言模式，那儿 `Sendable` 不强制；
    /// 而写上去反倒会把某个成员碰巧还没标 Sendable 的类型挡在门外，
    /// 换来一个跟这件事无关的编译错。
    ///
    /// 传进来的都是**值类型的快照**（在调用方那个线程上取好的），
    /// 后台只读不写，实际是安全的。
    static func saveAsync<T: Encodable>(_ value: T, to name: String) {
        diskQueue.async {
            save(value, to: name)
        }
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

    /// 整个缓存扔掉。**还原完要叫一次**——
    /// 刚从备份里放回来一批图，缓存里可能还留着同名的旧那张。
    static func forgetAll() { memo.removeAllObjects() }

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
    ///
    /// ⚠️ **抠过、擦过的图一律走这个，别走上面那个 `save`。**
    /// 她报的「贴纸擦完之后变成白底了」就是走错了那一条：
    /// 擦掉的地方是透明的，存成 jpg 之后透明一律被填实。
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

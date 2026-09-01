import SwiftUI
import UIKit

/// 她自己攒的那些贴纸。**只在这台手机上，不进仓库。**
///
/// ## 为什么要有这一层
///
/// 她想用いらすとや那批可爱插画。去把条款读完之后：
///
///   · 「20 张上限」**只针对商用设计**（`素材を21点以上使った商用デザイン`），
///     她这是个人自用、不上架，这一条不卡她。
///   · 真正卡住的是另一条：禁止「**素材を主体としたコンテンツ・商品の再配布**」，
///     而且明确把 **LINE 表情包**列为例子。
///
/// 把几十张打包成 App 自带的「贴纸库」，形状跟 LINE 表情包是一样的——
/// 素材本身就是内容主体。再加上这个仓库是**公开的**，
/// 提交进去等于向所有人再分发。那条不行。
///
/// **但「她自己拿来用」完全在条款里。** 那是「使用」，不是「再分发」。
/// 所以这一层做的事很简单：让她在手机上把图导进来，
/// 存在这台设备的沙盒里，跟别的自带贴纸并排出现在那一排里。
/// 图**一张都不进 git**，仓库里只有这段代码。
///
/// ⚠️ 顺带一个好处：这条路对**任何**来源都成立。
/// 以后她在别处看到喜欢的贴纸，存进相册就能用，
/// 不用每次都来问我「这家能不能打包」。
///
/// ## 存在哪儿
///
/// `Documents/MyStickers/*.png`。跟着备份走（`BackupBundle` 扫整个
/// Documents），所以换手机不会丢。
enum MyStickers {

    /// `assetName` 以这个开头的，就是她自己那批。
    ///
    /// ⚠️ 用前缀而不是另开一个字段：`JournalElement` 已经存过好几万条了，
    /// 加字段要动解码器，而前缀是**纯字符串约定**，老数据一个字都不用改。
    static let mark = "my/"

    static var folder: URL {
        let dir = FileManager.default.urls(for: .documentDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("MyStickers", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir,
                                                     withIntermediateDirectories: true)
        }
        return dir
    }

    /// 现在攒了哪些。返回的是带前缀的 `assetName`，可以直接塞进元素里。
    static func all() -> [String] {
        let fs = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return fs.filter { $0.hasSuffix(".png") }
            .sorted()
            .map { mark + $0.replacingOccurrences(of: ".png", with: "") }
    }

    /// 存一张进来。
    ///
    /// ⚠️⚠️ **一定要存 PNG，不能走 `ImageStore.save`。**
    /// 那个是 JPEG，而 **JPEG 没有透明通道**——
    /// 贴纸的透明底会全变成白块，那张贴纸就废了。
    /// （橡皮擦那次栽的是同一个坑，见 `ImageStore.savePNG`。）
    @discardableResult
    static func add(_ data: Data) -> String? {
        guard let img = UIImage(data: data) else { return nil }
        // 太大的先缩一缩。贴纸最大也就贴到两三百点宽，
        // 存一张 4000 像素的原图只是白占空间、白拖慢滚动。
        let side: CGFloat = 512
        let scale = min(1, side / max(img.size.width, img.size.height))
        let target = CGSize(width: img.size.width * scale,
                            height: img.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        fmt.opaque = false          // ⚠️ 留住透明底
        let small = UIGraphicsImageRenderer(size: target, format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let png = small.pngData() else { return nil }
        let name = "s\(Int(Date().timeIntervalSince1970 * 1000))"
        do {
            try png.write(to: folder.appendingPathComponent(name + ".png"))
        } catch {
            return nil
        }
        cache.removeObject(forKey: (mark + name) as NSString)
        return mark + name
    }

    static func remove(_ assetName: String) {
        guard assetName.hasPrefix(mark) else { return }
        let file = String(assetName.dropFirst(mark.count)) + ".png"
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        cache.removeObject(forKey: assetName as NSString)
    }

    /// ⚠️ `NSCache` 不是字典：内存紧张的时候系统会自己清掉几张。
    /// 一页手帐上可能有二三十张贴纸，用无上限的字典存着，
    /// 翻几页就把内存吃满了（贴纸库那次的教训）。
    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ assetName: String) -> UIImage? {
        guard assetName.hasPrefix(mark) else { return nil }
        let key = assetName as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let file = String(assetName.dropFirst(mark.count)) + ".png"
        guard let img = UIImage(contentsOfFile:
                                folder.appendingPathComponent(file).path)
        else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }
}

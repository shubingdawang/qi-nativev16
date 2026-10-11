import SwiftUI
import UIKit

/// 糖果的像素图：跟小屋家具、小岛一个画法（pixelkit 搭小模型、统一打光、深梅色描边）。
///
/// 每种造型 × 每种配色 × 两种样子都在 `CandyJar/candy_art.png` 里，位置表是 `candy_art.json`，
/// 由 `scripts/candy/candies.py --pack` 生成。改图改脚本，别手修 PNG。
@MainActor
enum CandyArt {

    private static var sheet: UIImage? = {
        guard let url = Bundle.main.url(forResource: "candy_art", withExtension: "png") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }()

    private static let rects: [String: [Int]] = {
        guard let url = Bundle.main.url(forResource: "candy_art", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let r = try? JSONDecoder().decode([String: [Int]].self, from: data) else { return [:] }
        return r
    }()

    private static var cache: [String: UIImage] = [:]

    /// 同一种造型分两种样子：按这颗糖的编号算，同一颗每次都一样
    nonisolated static func variant(_ seed: String) -> Int {
        var h: UInt32 = 0
        for u in seed.unicodeScalars { h = h &* 31 &+ u.value }
        h = h &* 1_103_515_245 &+ 12_345
        h = h &* 1_103_515_245 &+ 12_345
        return (h >> 8) % 2 == 0 ? 0 : 1
    }

    static func image(shape: String, scheme: String, seed: String) -> UIImage? {
        let known = ["mm豆", "三角", "五角星", "和果子", "圆珠", "小包子", "弯豆", "方糖", "花果子"]
        let sh = known.contains(shape) ? shape : "mm豆"
        let key = "\(sh)|\(scheme)|\(variant(seed))"
        if let c = cache[key] { return c }
        let r = rects[key] ?? rects["\(sh)|焦糖咖啡|0"]
        guard let r, r.count == 4,
              let cg = sheet?.cgImage?.cropping(to: CGRect(x: r[0], y: r[1], width: r[2], height: r[3])) else { return nil }
        let img = UIImage(cgImage: cg)
        cache[key] = img
        return img
    }
}

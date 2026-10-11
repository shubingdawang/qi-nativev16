import SwiftUI
import UIKit
import CoreImage

// MARK: - 小岛的画（Ninja Adventure 素材包，CC0，见 Resources/Island/LICENSE-Island.txt）
//
// 地面：按格子算好一整张 16 像素一格的小图（草地底 + 小草小花 + 路 / 水 / 沙 / 田按八邻居拼接），
//      放大的时候不插值，像素清清楚楚。只在地块变了的时候重新拼。
// 景：树、花、石头、房子……都是素材包里切出来的图，按格子摆，下沿对齐格子下沿。

enum WorldDecorKind: String, CaseIterable, Identifiable {
    case treeBig, treePink, treeGreen, treeOrange, treeSnow, treeBigPink, pine, treeSmall, bonsai,
         bush, berry, berryBlue, sunflower, flowerY, flowerR, daisy, clover, fern, stump, rock, rocks, boulder,
         houseOrange, houseBeige, houseRed, shop, cabin, fence, barrel, crate, waterBarrel
    var id: String { rawValue }

    var label: String {
        switch self {
        case .treeBig: return "大树"
        case .treePink: return "樱花树"
        case .treeGreen: return "绿树"
        case .treeOrange: return "秋树"
        case .treeSnow: return "雪树"
        case .treeBigPink: return "大樱花"
        case .pine: return "松树林"
        case .treeSmall: return "小树"
        case .bonsai: return "松树"
        case .bush: return "灌木"
        case .berry: return "莓果丛"
        case .berryBlue: return "蓝莓丛"
        case .sunflower: return "向日葵"
        case .flowerY: return "小黄花"
        case .flowerR: return "红花"
        case .daisy: return "雏菊"
        case .clover: return "三叶草"
        case .fern: return "蕨"
        case .stump: return "树桩"
        case .rock: return "石头"
        case .rocks: return "石堆"
        case .boulder: return "大岩石"
        case .houseOrange: return "小屋"
        case .houseBeige: return "米色小屋"
        case .houseRed: return "红瓦小屋"
        case .shop: return "小卖铺"
        case .cabin: return "木屋"
        case .fence: return "篱笆"
        case .barrel: return "木桶"
        case .crate: return "果篮"
        case .waterBarrel: return "菜盆"
        }
    }

    /// 素材图里那一张
    var sprite: String {
        switch self {
        case .treeBig: return "tree_big"
        case .treePink: return "tree_pink"
        case .treeGreen: return "tree_green"
        case .treeOrange: return "tree_orange"
        case .treeSnow: return "tree_snow"
        case .treeBigPink: return "tree_bigpink"
        case .pine: return "pine_big"
        case .treeSmall: return "tree_small"
        case .bonsai: return "pine_small"
        case .bush: return "bush2"
        case .berry: return "berry_o"
        case .berryBlue: return "berry_b"
        case .sunflower: return "sunflower"
        case .flowerY: return "flower_y"
        case .flowerR: return "flower_r"
        case .daisy: return "daisy"
        case .clover: return "clover"
        case .fern: return "fern"
        case .stump: return "stump2"
        case .rock: return "rock_g"
        case .rocks: return "rocks_b"
        case .boulder: return "boulder"
        case .houseOrange: return "house_orange"
        case .houseBeige: return "house_beige"
        case .houseRed: return "house_red"
        case .shop: return "shop"
        case .cabin: return "cabin"
        case .fence: return "fence_h"
        case .barrel: return "barrel_w"
        case .crate: return "crate"
        case .waterBarrel: return "pot_veg"
        }
    }

    var isHouse: Bool { [.houseOrange, .houseBeige, .houseRed, .shop, .cabin].contains(self) }

    /// 占几格（宽、高），按图的大小算。摆的时候左下角对着点的那一格
    var cells: (w: Int, h: Int) {
        guard let r = IslandAtlas.sprites[sprite] else { return (1, 1) }
        return ((r.w + 15) / 16, (r.h + 15) / 16)
    }

    /// 上一版（手画的那套）存下来的名字，换成这套里最像的
    static func resolve(_ raw: String) -> WorldDecorKind? {
        if let k = WorldDecorKind(rawValue: raw) { return k }
        switch raw {
        case "tree": return .treeBig
        case "blossom": return .treePink
        case "pine": return .pine
        case "bush": return .bush
        case "berry": return .berry
        case "rock": return .rock
        case "rocks": return .rocks
        case "stump": return .stump
        case "mushroom": return .flowerR
        case "tallgrass": return .fern
        case "house": return .houseOrange
        case "fence": return .fence
        case "well", "pot": return .waterBarrel
        default: return nil
        }
    }
}

@MainActor
enum IslandArt {

    /// 一格在素材图里是 16 像素
    static let px = 16

    private static var sheets: [String: UIImage] = [:]
    private static var crops: [String: UIImage] = [:]
    private static var groundCache: (key: Int, image: UIImage)?

    static func sheet(_ name: String) -> UIImage? {
        if let s = sheets[name] { return s }
        guard let url = Bundle.main.url(forResource: "island_" + name, withExtension: "png"),
              let raw = UIImage(contentsOfFile: url.path) else { return nil }
        // 原图颜色偏冲，整张收一点饱和度，地面和景一起柔下来
        var img = raw
        if let ci = CIImage(image: raw)?.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.88]),
           let cg = CIContext(options: [.workingColorSpace: NSNull()]).createCGImage(ci, from: ci.extent) {
            img = UIImage(cgImage: cg)
        }
        sheets[name] = img
        return img
    }

    private static func cut(_ sheetName: String, _ r: CGRect) -> UIImage? {
        guard let s = sheet(sheetName), let cg = s.cgImage?.cropping(to: r) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// 素材里的一张（树、花、房子……）
    static func sprite(_ key: String) -> UIImage? {
        if let c = crops[key] { return c }
        guard let r = IslandAtlas.sprites[key],
              let img = cut(r.sheet, CGRect(x: r.x, y: r.y, width: r.w, height: r.h)) else { return nil }
        crops[key] = img
        return img
    }

    static func size(of key: String) -> CGSize {
        guard let r = IslandAtlas.sprites[key] else { return CGSize(width: 16, height: 16) }
        return CGSize(width: r.w, height: r.h)
    }

    /// 某一格（列、行）的那一小块
    private static func tile(_ sheetName: String, _ cx: Int, _ cy: Int) -> UIImage? {
        let key = "\(sheetName)#\(cx),\(cy)"
        if let c = crops[key] { return c }
        guard let img = cut(sheetName, CGRect(x: cx * px, y: cy * px, width: px, height: px)) else { return nil }
        crops[key] = img
        return img
    }

    private static func noise(_ x: Int, _ y: Int, _ k: Int = 0) -> Double {
        let v = sin(Double(x) * 12.9898 + Double(y) * 78.233 + Double(k) * 37.719) * 43758.5453
        return v - floor(v)
    }

    /// 每种地块用哪张图、哪一块（拼接那五行的左上角）
    private static func block(_ g: WorldGround) -> (String, Int, Int)? {
        switch g {
        case .path: return ("TilesetFloor", 0, 7)
        case .sand: return ("TilesetFloor", 0, 0)
        case .soil: return ("TilesetFloor", 11, 14)
        case .water: return ("TilesetWater", 0, 6)
        default: return nil
        }
    }

    /// 周围八格的位：左上、上、右上、右、右下、下、左下、左。角只在两条边都相同的时候才算
    private static func mask(_ at: (Int, Int) -> WorldGround?, _ x: Int, _ y: Int, _ k: WorldGround) -> Int {
        func s(_ dx: Int, _ dy: Int) -> Bool { at(x + dx, y + dy) == k }
        let t = s(0, -1), r = s(1, 0), b = s(0, 1), l = s(-1, 0)
        let bits = [s(-1, -1) && t && l, t, s(1, -1) && t && r, r, s(1, 1) && b && r, b, s(-1, 1) && b && l, l]
        var m = 0
        for (i, v) in bits.enumerated() where v { m |= 1 << i }
        return m
    }

    private static func closest(_ m: Int) -> (Int, Int) {
        if let hit = IslandAtlas.blob[m] { return hit }
        var best = IslandAtlas.blob.first!.value, bestD = 99
        for (k, v) in IslandAtlas.blob {
            let d = (k ^ m).nonzeroBitCount
            if d < bestD { bestD = d; best = v }
        }
        return best
    }

    /// 整片地面拼成一张小图（一格 16 像素）。地块不变就用上次那张
    static func ground(_ g: [WorldGround], width w: Int, height h: Int) -> UIImage {
        var hasher = Hasher()
        hasher.combine(g); hasher.combine(w); hasher.combine(h)
        let key = hasher.finalize()
        if let c = groundCache, c.key == key { return c.image }

        func at(_ x: Int, _ y: Int) -> WorldGround? {
            guard x >= 0, y >= 0, x < w, y < h else { return nil }
            return g[y * w + x]
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: w * px, height: h * px), format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            let flowerKeys = ["flower_y", "daisy", "flower_r", "clover"]
            for y in 0..<h {
                for x in 0..<w {
                    let r = CGRect(x: x * px, y: y * px, width: px, height: px)
                    // 草地底：大多是干净的那块，偶尔一块带纹样
                    let n = noise(x, y)
                    let base = n < 0.12 ? tile("TilesetFloor", 1 + Int(n * 100) % 3, 12) : tile("TilesetFloor", 0, 12)
                    base?.draw(in: r)
                    guard let k = at(x, y) else { continue }
                    switch k {
                    case .grass, .flowers:
                        // 零星的小草小花
                        if noise(x, y, 5) < (k == .flowers ? 0.0 : 0.16) {
                            tile("TilesetFloorDetail", Int(noise(x, y, 6) * 9), 2)?.draw(in: r)
                        }
                        if k == .flowers {
                            for i in 0..<2 {
                                let key = flowerKeys[(x * 3 + y + i) % flowerKeys.count]
                                let s: CGFloat = 10
                                let fx = CGFloat(x * px) + CGFloat(noise(x, y, i + 11)) * (CGFloat(px) - s)
                                let fy = CGFloat(y * px) + CGFloat(noise(x, y, i + 13)) * (CGFloat(px) - s)
                                sprite(key)?.draw(in: CGRect(x: fx, y: fy, width: s, height: s))
                            }
                        }
                    case .wood:
                        tile("TilesetWater", 1 + x % 3, 13 + y % 2)?.draw(in: r)
                    default:
                        if let bl = block(k) {
                            let (sheetName, bx, by) = bl
                            let (rx, ry) = closest(mask(at, x, y, k))
                            tile(sheetName, bx + rx, by + ry)?.draw(in: r)
                        }
                    }
                }
            }
        }
        groundCache = (key, img)
        return img
    }

    /// 海：素材里那块干净的水。放大三倍、不插值，铺满背景
    static var sea: UIImage? {
        if let c = crops["sea@3"] { return c }
        guard let t = tile("TilesetWater", 1, 8) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        let side = CGFloat(px * 3)
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            t.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        crops["sea@3"] = img
        return img
    }
}

/// 一样景：切出来的图，按 tile 放大、不插值
struct IslandSprite: View {
    let key: String
    let scale: CGFloat

    var body: some View {
        let s = IslandArt.size(of: key)
        Group {
            if let img = IslandArt.sprite(key) {
                Image(uiImage: img).resizable().interpolation(.none)
            } else {
                Color.clear
            }
        }
        .frame(width: s.width * scale, height: s.height * scale)
    }
}

// MARK: - 会动的那一层：云影、花瓣、蝴蝶；晚上暗下来、路灯和窗亮、萤火虫

struct AmbientLayer: View {
    let width: Int
    let height: Int
    let tile: CGFloat
    let night: Bool
    /// 路灯、小屋窗户在哪（晚上发光用）
    let lights: [CGPoint]

    private static func noise(_ i: Int, _ k: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + Double(k) * 78.233) * 43758.5453
        return CGFloat(v - floor(v))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let w = size.width, h = size.height
                // 云影：大块软的暗影，慢慢从左往右飘
                for i in 0..<3 {
                    let span = w + 300
                    let x = CGFloat((t * 6 + Double(i) * 230).truncatingRemainder(dividingBy: Double(span))) - 150
                    let y = 120 + CGFloat(i) * 260
                    let r = CGRect(x: x - 120, y: y - 60, width: 240, height: 120)
                    gc.fill(Path(ellipseIn: r), with: .radialGradient(
                        Gradient(colors: [Color(red: 0.16, green: 0.24, blue: 0.2).opacity(night ? 0 : 0.10), .clear]),
                        center: CGPoint(x: r.midX, y: r.midY), startRadius: 0, endRadius: 120))
                }
                if !night {
                    // 飘落的花瓣
                    for i in 0..<10 {
                        let x = (Self.noise(i, 40) * w + CGFloat(t * 6 * Double(1 + i % 3))).truncatingRemainder(dividingBy: w)
                        let y = (Self.noise(i, 41) * h + CGFloat(t * 12)).truncatingRemainder(dividingBy: h)
                        // 像素花瓣：一大一小两块方的，跟地面一个画法
                        let px = (x / 3).rounded() * 3, py = (y / 3).rounded() * 3
                        let flip = Int(t * 2 + Double(i)) % 2 == 0
                        gc.fill(Path(CGRect(x: px, y: py, width: 6, height: 3)),
                                with: .color(Color(red: 0.96, green: 0.71, blue: 0.78).opacity(0.95)))
                        gc.fill(Path(CGRect(x: px + (flip ? 0 : 3), y: py + 3, width: 3, height: 3)),
                                with: .color(Color(red: 0.91, green: 0.55, blue: 0.66).opacity(0.95)))
                    }
                    // 两只蝴蝶
                    for (i, col) in [Color(hexString: "F7D36B")!, Color(hexString: "C9B6E8")!].enumerated() {
                        let bx = (i == 0 ? 0.28 : 0.72) * w + CGFloat(sin(t * (0.6 + Double(i) * 0.2))) * 40
                        let by = (i == 0 ? 0.32 : 0.66) * h + CGFloat(cos(t * (0.8 + Double(i) * 0.1))) * 26
                        let f = CGFloat(abs(sin(t * 9 + Double(i)))) * 4 + 1
                        var g = gc
                        g.translateBy(x: bx, y: by)
                        var l = g; l.rotate(by: .radians(-0.4))
                        l.fill(Path(ellipseIn: CGRect(x: -2 * f, y: -3.2, width: f * 2, height: 6.4)), with: .color(col))
                        var r = g; r.rotate(by: .radians(0.4))
                        r.fill(Path(ellipseIn: CGRect(x: 0, y: -3.2, width: f * 2, height: 6.4)), with: .color(col))
                        g.fill(Path(CGRect(x: -0.6, y: -3, width: 1.2, height: 6)), with: .color(Color(hexString: "6E5A4A")!))
                    }
                } else {
                    // 夜色
                    gc.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                            with: .color(Color(red: 0.12, green: 0.14, blue: 0.31).opacity(0.42)))
                    var lit = gc
                    lit.blendMode = .plusLighter
                    for p in lights {
                        lit.fill(Path(ellipseIn: CGRect(x: p.x - 70, y: p.y - 70, width: 140, height: 140)),
                                 with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.84, blue: 0.55).opacity(0.5), .clear]),
                                                       center: p, startRadius: 0, endRadius: 70))
                    }
                    // 萤火虫
                    for i in 0..<22 {
                        let x = Self.noise(i, 50) * w + CGFloat(sin(t * 0.9 + Double(i))) * 10
                        let y = Self.noise(i, 51) * h + CGFloat(cos(t * 1.2 + Double(i))) * 8
                        let a = 0.5 + 0.5 * sin(t * 2 + Double(i))
                        lit.fill(Path(ellipseIn: CGRect(x: x - 6, y: y - 6, width: 12, height: 12)),
                                 with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.96, blue: 0.67).opacity(0.95 * a), .clear]),
                                                       center: CGPoint(x: x, y: y), startRadius: 0, endRadius: 6))
                    }
                }
            }
        }
        .frame(width: CGFloat(width) * tile, height: CGFloat(height) * tile)
        .allowsHitTesting(false)
    }
}

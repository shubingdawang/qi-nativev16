import SwiftUI
import UIKit
import CoreImage

// MARK: - 小岛的画（Ninja Adventure 素材包，CC0，见 Resources/Island/LICENSE-Island.txt）
//
// 地面：按格子算好一整张 16 像素一格的小图（草地底 + 小草小花 + 路 / 水 / 沙 / 田按八邻居拼接），
//      放大的时候不插值，像素清清楚楚。只在地块变了的时候重新拼。
// 景：树、花、石头、房子……都是素材包里切出来的图，按格子摆，下沿对齐格子下沿。

enum WorldDecorKind: String, CaseIterable, Identifiable {
    case treeBig, treePink, treeGreen, treeOrange, treeSnow, treeBigPink, pine, treeSmall, bonsai, olive, pinkSmall,
         bush, bushSmall, bushThick, berry, berryBlue, sunflower, flowerY, flowerR, daisy, clover, fern, grass, grassTall,
         stump, stumpBig, rock, rockBrown, pebble, pebbleBrown, rocks, boulder,
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
        case .olive: return "橄榄树"
        case .pinkSmall: return "小樱树"
        case .bushSmall: return "小灌木"
        case .bushThick: return "灌木丛"
        case .grass: return "草丛"
        case .grassTall: return "高草"
        case .stumpBig: return "老树桩"
        case .rockBrown: return "褐石"
        case .pebble: return "小石子"
        case .pebbleBrown: return "小石块"
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
        case .olive: return "olive_small"
        case .pinkSmall: return "pink_small"
        case .bushSmall: return "bush1"
        case .bushThick: return "bush3"
        case .grass: return "grass1"
        case .grassTall: return "grass2"
        case .stumpBig: return "stump"
        case .rockBrown: return "rock_b"
        case .pebble: return "rock_gs"
        case .pebbleBrown: return "rock_bs"
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

    /// 她的小人（不收饱和度，原色）。col：站 / 左脚 / 右脚；row：朝下 / 朝上 / 朝左
    static func girl(_ col: Int, _ row: Int) -> UIImage? {
        let key = "girl#\(col),\(row)"
        if let c = crops[key] { return c }
        if sheets["girl"] == nil,
           let url = Bundle.main.url(forResource: "island_girl", withExtension: "png"),
           let raw = UIImage(contentsOfFile: url.path) {
            sheets["girl"] = raw
        }
        guard let cg = sheets["girl"]?.cgImage?.cropping(to: CGRect(x: col * 16, y: row * 25, width: 16, height: 25)) else { return nil }
        let img = UIImage(cgImage: cg)
        crops[key] = img
        return img
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

    /// 周围八格的位：左上、上、右上、右、右下、下、左下、左。角只在两条边都相同的时候才算。
    /// 沙滩朝海那边不画边（海岸线另外按像素画）
    private static func mask(_ at: (Int, Int) -> WorldGround, _ x: Int, _ y: Int, _ k: WorldGround) -> Int {
        func s(_ dx: Int, _ dy: Int) -> Bool {
            let a = at(x + dx, y + dy)
            return a == k || (k == .sand && a == .sea)
        }
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

        // 岛外面都算海
        func at(_ x: Int, _ y: Int) -> WorldGround {
            guard x >= 0, y >= 0, x < w, y < h else { return .sea }
            return g[y * w + x]
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let tiles = UIGraphicsImageRenderer(size: CGSize(width: w * px, height: h * px), format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            let flowerKeys = ["flower_y", "daisy", "flower_r", "clover"]
            for y in 0..<h {
                for x in 0..<w {
                    let r = CGRect(x: x * px, y: y * px, width: px, height: px)
                    let k = at(x, y)
                    if k == .sea {
                        // 海那格先铺沙：海岸线往外鼓的那一点要有底，后面按像素清掉
                        tile("TilesetFloor", 1, 1)?.draw(in: r)
                        continue
                    }
                    // 草地底：大多是干净的那块，偶尔一块带纹样
                    let n = noise(x, y)
                    let base = n < 0.12 ? tile("TilesetFloor", 1 + Int(n * 100) % 3, 12) : tile("TilesetFloor", 0, 12)
                    base?.draw(in: r)
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
        var img = tiles
        if let cg = tiles.cgImage, let c = coast(cg, w: w, h: h, at: at) { img = UIImage(cgImage: c) }
        groundCache = (key, img)
        return img
    }

    // MARK: 海岸线

    /// 平滑的噪声（格点上取 noise，中间三次插值）
    private static func vnoise(_ x: Double, _ y: Double, _ k: Int) -> Double {
        let i = Int(floor(x)), j = Int(floor(y))
        var fx = x - Double(i), fy = y - Double(j)
        fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
        let a = noise(i, j, k), b = noise(i + 1, j, k), c = noise(i, j + 1, k), d = noise(i + 1, j + 1, k)
        return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
    }

    /// 倒角距离（横竖 3、斜 4），两遍。src 里 true 的像素算出离最近的 false 有多远
    private static func chamfer(_ src: [Bool], _ w: Int, _ h: Int) -> [Int32] {
        let big: Int32 = 1 << 28
        var d = src.map { $0 ? big : 0 }
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                guard d[i] != 0 else { continue }
                var m = d[i]
                if x > 0 { m = min(m, d[i - 1] + 3) }
                if y > 0 {
                    m = min(m, d[i - w] + 3)
                    if x > 0 { m = min(m, d[i - w - 1] + 4) }
                    if x < w - 1 { m = min(m, d[i - w + 1] + 4) }
                }
                d[i] = m
            }
        }
        for y in stride(from: h - 1, through: 0, by: -1) {
            for x in stride(from: w - 1, through: 0, by: -1) {
                let i = y * w + x
                guard d[i] != 0 else { continue }
                var m = d[i]
                if x < w - 1 { m = min(m, d[i + 1] + 3) }
                if y < h - 1 {
                    m = min(m, d[i + w] + 3)
                    if x < w - 1 { m = min(m, d[i + w + 1] + 4) }
                    if x > 0 { m = min(m, d[i + w - 1] + 4) }
                }
                d[i] = m
            }
        }
        return d
    }

    /// 素材的颜色整张收过饱和度，自己画的颜色也照样收一下
    private static func soft(_ hex: UInt32) -> (UInt8, UInt8, UInt8) {
        let r = Double((hex >> 16) & 0xFF), g = Double((hex >> 8) & 0xFF), b = Double(hex & 0xFF)
        let l = 0.2125 * r + 0.7154 * g + 0.0721 * b
        func c(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (l + (v - l) * 0.88).rounded()))) }
        return (c(r), c(g), c(b))
    }

    /// 海岸线：按像素画。陆地 = 每格「是不是陆地」双线性插值 + 一点起伏 > 0.5，
    /// 再按离岸几像素分出湿沙、沙滩、沙滩跟草地交界的描边；海上一道白浪、一道断续的浪、浅水往外越来越淡
    private static func coast(_ image: CGImage, w: Int, h: Int, at: (Int, Int) -> WorldGround) -> CGImage? {
        let W = w * px, H = h * px
        // 木头：四边挨着海就是桥 / 栈桥，不算陆地
        func land(_ x: Int, _ y: Int) -> Double {
            let k = at(x, y)
            if k == .sea { return 0 }
            if k == .wood, [(0, 1), (0, -1), (1, 0), (-1, 0)].contains(where: { at(x + $0.0, y + $0.1) == .sea }) { return 0 }
            return 1
        }
        var L = [Double](repeating: 0, count: (w + 2) * (h + 2))
        for y in -1...h { for x in -1...w { L[(y + 1) * (w + 2) + x + 1] = land(x, y) } }
        func lv(_ x: Int, _ y: Int) -> Double {
            guard x >= -1, y >= -1, x <= w, y <= h else { return 0 }
            return L[(y + 1) * (w + 2) + x + 1]
        }
        var inside = [Bool](repeating: false, count: W * H)
        for py in 0..<H {
            let v = (Double(py) + 0.5) / Double(px) - 0.5
            let j = Int(floor(v)), fv = v - Double(j)
            for qx in 0..<W {
                let u = (Double(qx) + 0.5) / Double(px) - 0.5
                let i = Int(floor(u)), fu = u - Double(i)
                var f = (lv(i, j) * (1 - fu) + lv(i + 1, j) * fu) * (1 - fv) + (lv(i, j + 1) * (1 - fu) + lv(i + 1, j + 1) * fu) * fv
                f += (vnoise(Double(qx) / 9, Double(py) / 9, 3) - 0.5) * 0.24
                inside[py * W + qx] = f > 0.5
            }
        }
        let din = chamfer(inside, W, H)
        let dout = chamfer(inside.map { !$0 }, W, H)

        let wet = soft(0xFFAD5D), wet2 = soft(0xFFBC75), sand = soft(0xFFCB8D), edge = soft(0xEF914F)
        let foam = soft(0xFFFFFF), foam2 = soft(0xC9F3F6)

        var buf = [UInt8](repeating: 0, count: W * H * 4)
        return buf.withUnsafeMutableBytes { raw -> CGImage? in
            guard let ctx = CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))
            let p = raw.bindMemory(to: UInt8.self)
            func set(_ i: Int, _ c: (UInt8, UInt8, UInt8)) {
                p[i * 4] = c.0; p[i * 4 + 1] = c.1; p[i * 4 + 2] = c.2; p[i * 4 + 3] = 255
            }
            /// 半透明的白（预乘过）
            func white(_ i: Int, _ a: Double) {
                let v = UInt8(max(0, min(255, (a * 255).rounded())))
                p[i * 4] = v; p[i * 4 + 1] = v; p[i * 4 + 2] = v; p[i * 4 + 3] = v
            }
            for y in 0..<H {
                for x in 0..<W {
                    let i = y * W + x
                    let k = at(x / px, y / px)
                    if k == .wood { continue }                // 木板原样留着
                    if inside[i] {
                        // 路、田、池塘挨着岸也不去改它
                        switch k {
                        case .grass, .flowers, .sand, .sea: break
                        default: continue
                        }
                        let d = Double(din[i]) / 3
                        let sw = 6.5 + vnoise(Double(x) / 11, Double(y) / 11, 7) * 4
                        if d < 1.3 { set(i, wet) }
                        else if d < 2.6 { set(i, wet2) }
                        else if d < sw { set(i, noise(x, y, 21) < 0.035 ? wet2 : sand) }
                        else if d < sw + 1, k != .sand { set(i, edge) }
                        else if k == .sea { set(i, sand) }
                    } else {
                        let d = Double(dout[i]) / 3
                        if d < 1.4 { set(i, foam) }
                        else if d < 2.4 { set(i, foam2) }
                        else if d > 4.2, d < 5.3, vnoise(Double(x) / 5, Double(y) / 5, 9) > 0.45 { white(i, 150.0 / 255) }
                        else if d < 8 { white(i, 70.0 / 255 * (1 - d / 8)) }
                        else { white(i, 0) }
                    }
                }
            }
            // 桥：四边挨着海的木头。上下沿描深色边、上沿一道栏杆亮线，桥下水面一道影子，隔一格一根桩子插进水里
            let dark = soft(0x8A4B36), rail = soft(0xFFD29A), post = soft(0x6E3B2C), deep = soft(0x5E8FA0)
            func isBridge(_ tx: Int, _ ty: Int) -> Bool {
                at(tx, ty) == .wood && [(0, 1), (0, -1), (1, 0), (-1, 0)].contains { at(tx + $0.0, ty + $0.1) == .sea }
            }
            func water(_ x: Int, _ y: Int) -> Bool {
                x >= 0 && y >= 0 && x < W && y < H && !inside[y * W + x] && at(x / px, y / px) != .wood
            }
            func shadow(_ i: Int) {
                let a = 70.0 / 255
                p[i * 4] = UInt8(40 * a); p[i * 4 + 1] = UInt8(70 * a); p[i * 4 + 2] = UInt8(90 * a); p[i * 4 + 3] = 70
            }
            for ty in 0..<h {
                for tx in 0..<w where isBridge(tx, ty) {
                    let x0 = tx * px, y0 = ty * px
                    if at(tx, ty - 1) == .sea || at(tx, ty + 1) == .sea {
                        for x in x0..<(x0 + px) {
                            set(y0 * W + x, dark); set((y0 + 1) * W + x, rail); set((y0 + 2) * W + x, dark)
                            set((y0 + px - 1) * W + x, dark)
                            for k in 1...3 {
                                let yy = y0 + px - 1 + k
                                guard water(x, yy) else { continue }
                                if k > 1 { shadow(yy * W + x) } else { set(yy * W + x, deep) }
                            }
                        }
                        if tx % 2 == 0 {
                            let bx = x0 + 6
                            for k in 0..<5 {
                                let yy = y0 + px - 1 + k
                                guard water(bx, yy) else { continue }
                                set(yy * W + bx, post); set(yy * W + bx + 1, dark)
                            }
                            let yy = y0 + px + 4
                            if water(bx, yy) {
                                set(yy * W + bx - 1, foam); set(yy * W + bx + 2, foam)
                            }
                        }
                    } else {
                        for y in y0..<(y0 + px) {
                            set(y * W + x0, dark); set(y * W + x0 + 1, rail)
                            set(y * W + x0 + px - 1, dark); set(y * W + x0 + px - 2, rail)
                        }
                    }
                }
            }
            return ctx.makeImage()
        }
    }

    /// 海：素材里那块干净的水。放大三倍、不插值，铺满背景
    static var sea: UIImage? {
        if let c = crops["sea@3"] { return c }
        guard let t = tile("TilesetWater", 1, 7) else { return nil }
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

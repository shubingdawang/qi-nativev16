import SwiftUI
import UIKit

// MARK: - 小岛的画（栖岛自己画的一套）
//
// 地面：IslandPaint 按像素画出一整张（一格 16 像素），放大三倍不插值。
// 景：树、花、房子、篱笆……都在 island_art.png 里（scripts/island 生成），按格子摆，下沿对齐格子下沿。
// 她：island_girl.png。他：clawd。

enum WorldDecorKind: String, CaseIterable, Identifiable {
    case treeGreen, treePink, treeBig, treeOrange, pine, treeSmall, pinkSmall, olive, bonsai,
         bush, berry, rock, pebble, rocks, stump,
         daisy, clover, flowerY, flowerR, tulipPeach, lavender, sunflower, lily,
         houseOrange, cabin, shop, houseBeige,
         fence, fenceV, crate, barrel, lamp, mailbox, bench,
         signpost, greenhouse, lighthouse, telescope,
         scarecrow, haybale, wheelbarrow, well, beehive, flowerpot, roseArch,
         fountain, picnic, umbrella, deckchair, shells, rowboat, campfire,
         logpile, tent, mushrooms, birdhouse, reeds, stones, lanterns,
         windmill, wheat, coralPink, seaweed, snowman, sled
    var id: String { rawValue }

    var label: String {
        switch self {
        case .treeGreen: return "绿树"
        case .treePink: return "樱花树"
        case .treeBig: return "果树"
        case .treeOrange: return "秋树"
        case .pine: return "松树"
        case .treeSmall: return "小树"
        case .pinkSmall: return "小樱树"
        case .olive: return "小果树"
        case .bonsai: return "小松树"
        case .bush: return "灌木"
        case .berry: return "莓果丛"
        case .rock: return "石头"
        case .pebble: return "小石头"
        case .rocks: return "石堆"
        case .stump: return "树桩"
        case .daisy: return "雏菊"
        case .clover: return "粉花丛"
        case .flowerY: return "小黄花"
        case .flowerR: return "郁金香"
        case .tulipPeach: return "杏色郁金香"
        case .lavender: return "薰衣草"
        case .sunflower: return "向日葵"
        case .lily: return "睡莲"
        // 四座小屋通到家里的四间：名字就叫那一间
        case .houseOrange: return "客厅"
        case .cabin: return "卧室"
        case .shop: return "厨房"
        case .houseBeige: return "浴室"
        case .fence: return "篱笆"
        case .fenceV: return "竖篱笆"
        case .crate: return "果箱"
        case .barrel: return "水桶"
        case .lamp: return "路灯"
        case .mailbox: return "信箱"
        case .bench: return "长椅"
        case .signpost: return "告示牌"
        case .greenhouse: return "温室"
        case .lighthouse: return "灯塔"
        case .telescope: return "观星台"
        case .scarecrow: return "稻草人"
        case .haybale: return "草垛"
        case .wheelbarrow: return "推车"
        case .well: return "水井"
        case .beehive: return "蜂箱"
        case .flowerpot: return "花盆"
        case .roseArch: return "玫瑰拱门"
        case .fountain: return "喷泉"
        case .picnic: return "野餐布"
        case .umbrella: return "遮阳伞"
        case .deckchair: return "躺椅"
        case .shells: return "贝壳"
        case .rowboat: return "小船"
        case .campfire: return "篝火"
        case .logpile: return "柴堆"
        case .tent: return "帐篷"
        case .mushrooms: return "蘑菇"
        case .birdhouse: return "鸟屋"
        case .reeds: return "芦苇"
        case .stones: return "踏脚石"
        case .lanterns: return "一串小灯"
        case .windmill: return "风车"
        case .wheat: return "麦子"
        case .coralPink: return "粉珊瑚"
        case .seaweed: return "水草"
        case .snowman: return "雪人"
        case .sled: return "雪橇"
        }
    }

    /// island_art.png 里那一张
    var sprite: String {
        switch self {
        case .treeGreen: return "tree_green"
        case .treePink: return "tree_pink"
        case .treeBig: return "tree_fruit"
        case .treeOrange: return "tree_autumn"
        case .pine: return "pine"
        case .treeSmall: return "tree_small"
        case .pinkSmall: return "pink_small"
        case .olive: return "fruit_small"
        case .bonsai: return "pine_small"
        case .bush: return "bush"
        case .berry: return "bush_berry"
        case .rock: return "rock"
        case .pebble: return "rock_small"
        case .rocks: return "rocks"
        case .stump: return "stump"
        case .daisy: return "fl_daisy"
        case .clover: return "fl_pink"
        case .flowerY: return "fl_yellow"
        case .flowerR: return "tulip_pink"
        case .tulipPeach: return "tulip_peach"
        case .lavender: return "lavender"
        case .sunflower: return "sunflower"
        case .lily: return "lily"
        case .houseOrange: return "house_pink"
        case .cabin: return "house_blue"
        case .shop: return "house_lilac"
        case .houseBeige: return "house_sage"
        case .fence: return "fence"
        case .fenceV: return "fence_v"
        case .crate: return "crate"
        case .barrel: return "barrel"
        case .lamp: return "lamp"
        case .mailbox: return "mailbox"
        case .bench: return "bench"
        case .signpost: return "signpost"
        case .greenhouse: return "greenhouse"
        case .lighthouse: return "lighthouse"
        case .telescope: return "telescope"
        case .scarecrow: return "scarecrow"
        case .haybale: return "haybale"
        case .wheelbarrow: return "wheelbarrow"
        case .well: return "well"
        case .beehive: return "beehive"
        case .flowerpot: return "flowerpot"
        case .roseArch: return "rose_arch"
        case .fountain: return "fountain"
        case .picnic: return "picnic"
        case .umbrella: return "umbrella"
        case .deckchair: return "deckchair"
        case .shells: return "shells"
        case .rowboat: return "rowboat"
        case .campfire: return "campfire"
        case .logpile: return "logpile"
        case .tent: return "tent"
        case .mushrooms: return "mushrooms"
        case .birdhouse: return "birdhouse"
        case .reeds: return "reeds"
        case .stones: return "stones"
        case .lanterns: return "lanterns"
        case .windmill: return "windmill"
        case .wheat: return "wheat"
        case .coralPink: return "coral_pink"
        case .seaweed: return "seaweed"
        case .snowman: return "snowman"
        case .sled: return "sled"
        }
    }

    /// 长在水下的（隔着水面看，画淡一点）
    var underwater: Bool { self == .coralPink || self == .seaweed }

    var isHouse: Bool { [.houseOrange, .cabin, .shop, .houseBeige].contains(self) }

    /// 哪一类。换材料只在同一类里换（小屋换屋顶颜色、大树换品种、花换花……）
    var family: String {
        switch self {
        case .houseOrange, .cabin, .shop, .houseBeige: return "小屋"
        case .treeGreen, .treePink, .treeBig, .treeOrange, .pine: return "大树"
        case .treeSmall, .pinkSmall, .olive, .bonsai: return "小树"
        case .bush, .berry: return "灌木"
        case .rock, .pebble, .rocks, .stump: return "石头"
        case .daisy, .clover, .flowerY, .flowerR, .tulipPeach, .lavender, .sunflower: return "花"
        case .fence, .fenceV: return "篱笆"
        case .crate, .barrel: return "箱桶"
        case .lamp, .mailbox, .bench: return "小物"
        case .lily: return "水上"
        case .signpost, .greenhouse, .lighthouse, .telescope: return "地标"
        case .scarecrow, .haybale, .wheelbarrow, .well, .beehive: return "田园"
        case .flowerpot, .picnic, .birdhouse, .lanterns: return "小物"
        case .roseArch, .fountain: return "花园"
        case .umbrella, .deckchair, .shells: return "海边"
        case .rowboat, .reeds: return "水上"
        case .campfire, .logpile, .tent: return "露营"
        case .mushrooms: return "花"
        case .stones: return "石头"
        case .windmill: return "地标"
        case .wheat: return "田园"
        case .coralPink, .seaweed: return "水上"
        case .snowman, .sled: return "雪地"
        }
    }

    /// 要先走完哪段剧情才能自己摆
    var unlockStory: String? {
        switch self {
        case .greenhouse: return "greenhouse"
        case .lighthouse: return "lighthouse"
        case .telescope: return "stargazing"
        default: return nil
        }
    }

    /// 同一类的
    var siblings: [WorldDecorKind] { Self.allCases.filter { $0.family == family } }

    /// 挡路的（走不过去）：树干、房子、石头、箱子桶、长椅
    var blocks: Bool {
        switch self {
        case .daisy, .clover, .flowerY, .flowerR, .tulipPeach, .lavender, .sunflower, .lily, .pebble,
             .flowerpot, .picnic, .shells, .rowboat, .mushrooms, .reeds, .stones, .wheat, .coralPink, .seaweed: return false
        default: return true
        }
    }

    /// 占几格（宽、高），按图的大小算。摆的时候左下角对着点的那一格
    var cells: (w: Int, h: Int) {
        guard let r = IslandAtlas.sprites[sprite] else { return (1, 1) }
        return ((r.w + 15) / 16, (r.h + 15) / 16)
    }

    /// 以前存下来的名字（换过两套画法），换成这套里最像的
    static func resolve(_ raw: String) -> WorldDecorKind? {
        if let k = WorldDecorKind(rawValue: raw) { return k }
        switch raw {
        case "treeSnow": return .pine
        case "treeBigPink", "blossom": return .treePink
        case "tree": return .treeGreen
        case "bushSmall": return .bush
        case "bushThick", "berryBlue": return .berry
        case "fern", "grassTall", "tallgrass": return .lavender
        case "grass": return .tulipPeach
        case "stumpBig": return .stump
        case "rockBrown": return .rock
        case "pebbleBrown": return .pebble
        case "boulder": return .rocks
        case "houseRed", "house": return .houseOrange
        case "waterBarrel": return .crate
        case "mushroom": return .flowerR
        case "well", "pot": return .barrel
        default: return nil
        }
    }
}

@MainActor
enum IslandArt {

    /// 一格是 16 像素
    static let px = IslandPaint.px

    private static var sheets: [String: UIImage] = [:]
    private static var crops: [String: UIImage] = [:]

    private static func sheet(_ name: String) -> UIImage? {
        if let s = sheets[name] { return s }
        guard let url = Bundle.main.url(forResource: "island_" + name, withExtension: "png"),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        sheets[name] = img
        return img
    }

    /// 她的小人。col：站 / 左脚 / 右脚；row：朝下 / 朝上 / 朝左
    static func girl(_ col: Int, _ row: Int) -> UIImage? {
        let key = "girl#\(col),\(row)"
        if let c = crops[key] { return c }
        guard let cg = sheet("girl")?.cgImage?.cropping(to: CGRect(x: col * 16, y: row * 25, width: 16, height: 25)) else { return nil }
        let img = UIImage(cgImage: cg)
        crops[key] = img
        return img
    }

    /// 一样景的季节版：秋天绿叶子变橙红金黄（松树不变），冬天绿的褪一点、朝上的面压一层雪
    static func sprite(_ key: String, season: WorldSeason) -> UIImage? {
        guard season == .autumn || season == .winter else { return sprite(key) }
        let ck = key + "#" + season.rawValue
        if let c = crops[ck] { return c }
        guard let base = sprite(key), let cg = base.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let evergreen = key.hasPrefix("pine")
        let onWater = ["lily", "rowboat", "reeds"].contains(key)
        let out: CGImage? = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            let p = raw.bindMemory(to: UInt8.self)
            func alpha(_ x: Int, _ y: Int) -> UInt8 { x < 0 || y < 0 || x >= w || y >= h ? 0 : p[(y * w + x) * 4 + 3] }
            func isOutline(_ i: Int) -> Bool { Int(p[i]) + Int(p[i + 1]) + Int(p[i + 2]) < 260 }
            // 先换叶子的颜色
            for y in 0..<h {
                for x in 0..<w {
                    let i = (y * w + x) * 4
                    guard p[i + 3] > 200, !evergreen else { continue }
                    var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
                    UIColor(red: CGFloat(p[i]) / 255, green: CGFloat(p[i + 1]) / 255, blue: CGFloat(p[i + 2]) / 255, alpha: 1)
                        .getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
                    guard hue > 0.17, hue < 0.5, sat > 0.12 else { continue }
                    let nh: CGFloat, ns: CGFloat
                    if season == .autumn {
                        let pick = (x * 7 + y * 13 + (x / 5) * 3) % 3
                        nh = [0.07, 0.03, 0.11][pick]; ns = min(1, sat * 1.25 + 0.05)
                    } else {
                        nh = hue; ns = sat * 0.45
                    }
                    let c = UIColor(hue: nh, saturation: ns, brightness: bri, alpha: 1)
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                    c.getRed(&r, green: &g, blue: &b, alpha: &a)
                    p[i] = UInt8(r * 255); p[i + 1] = UInt8(g * 255); p[i + 2] = UInt8(b * 255)
                }
            }
            // 冬天：每一列从上往下，描边下面那两格压成雪
            if season == .winter && !onWater {
                for x in 0..<w {
                    for y in 0..<h where alpha(x, y) > 200 && alpha(x, y - 1) == 0 {
                        for (k, v) in [(1, UInt8(250)), (2, UInt8(232))] where alpha(x, y + k) > 200 {
                            let i = ((y + k) * w + x) * 4
                            guard !isOutline(i) else { break }
                            p[i] = v; p[i + 1] = v; p[i + 2] = min(255, v + 6)
                        }
                    }
                }
            }
            return ctx.makeImage()
        }
        guard let out else { return base }
        let img = UIImage(cgImage: out)
        crops[ck] = img
        return img
    }

    /// 一样景（树、花、房子……）
    static func sprite(_ key: String) -> UIImage? {
        if let c = crops[key] { return c }
        guard let r = IslandAtlas.sprites[key],
              let cg = sheet("art")?.cgImage?.cropping(to: CGRect(x: r.x, y: r.y, width: r.w, height: r.h)) else { return nil }
        let img = UIImage(cgImage: cg)
        crops[key] = img
        return img
    }

    static func size(of key: String) -> CGSize {
        guard let r = IslandAtlas.sprites[key] else { return CGSize(width: 16, height: 16) }
        return CGSize(width: r.w, height: r.h)
    }

    private static var ground: (key: Int, image: CGImage)?

    /// 上次画好的地面（再进小岛不用重画）
    static func cachedGround(_ key: Int) -> CGImage? { ground?.key == key ? ground?.image : nil }
    static func keepGround(_ key: Int, _ img: CGImage) { ground = (key, img) }

    /// 海：一块放大三倍、不插值，铺满背景
    static var sea: UIImage? {
        if let c = crops["sea@3"] { return c }
        guard let t = IslandPaint.seaTile() else { return nil }
        let side = CGFloat(px * 3)
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            UIImage(cgImage: t).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        crops["sea@3"] = img
        return img
    }
}

/// 一样景：切出来的图，按 tile 放大、不插值
struct IslandSprite: View {
    let key: String
    let scale: CGFloat
    var season: WorldSeason = .spring

    var body: some View {
        let s = IslandArt.size(of: key)
        Group {
            if let img = IslandArt.sprite(key, season: season) {
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
    /// 烟囱口（冒烟）、篝火（火苗跳）、喷泉（溅水）、池塘里的点（偶尔一圈涟漪）
    var chimneys: [CGPoint] = []
    var fires: [CGPoint] = []
    var fountains: [CGPoint] = []
    var ponds: [CGPoint] = []
    var season: WorldSeason = .spring

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
                let px = tile / 16
                func dot(_ x: CGFloat, _ y: CGFloat, _ c: Color, _ s: CGFloat = 1) {
                    gc.fill(Path(CGRect(x: (x / px).rounded() * px, y: (y / px).rounded() * px, width: px * s, height: px * s)), with: .color(c))
                }
                // 烟囱冒烟：几团淡淡的方块慢慢往上、往右飘，越高越淡越大
                for (i, p) in chimneys.enumerated() {
                    for k in 0..<4 {
                        let phase = (t * 0.25 + Double(k) / 4 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
                        let y = p.y - CGFloat(phase) * 30 * px
                        let x = p.x + CGFloat(sin(phase * 5 + Double(i))) * 2 * px + CGFloat(phase) * 6 * px
                        let a = 0.55 * (1 - phase)
                        dot(x, y, Color.white.opacity(a), phase > 0.5 ? 3 : 2)
                    }
                }
                // 篝火：火苗一跳一跳，上面飘几颗火星
                for (i, p) in fires.enumerated() {
                    let f = Int(t * 8 + Double(i) * 3) % 3
                    dot(p.x - px, p.y - CGFloat(4 + f) * px, Color(hexString: "F7D46A")!.opacity(0.95))
                    dot(p.x + CGFloat(f - 1) * px, p.y - CGFloat(6 + f) * px, Color(hexString: "F5A35E")!.opacity(0.85))
                    for k in 0..<3 {
                        let phase = (t * 0.6 + Double(k) / 3 + Double(i) * 0.21).truncatingRemainder(dividingBy: 1)
                        dot(p.x + CGFloat(sin(phase * 9 + Double(k))) * 3 * px, p.y - CGFloat(8 + phase * 18) * px,
                            Color(hexString: "FFD27A")!.opacity(1 - phase))
                    }
                }
                // 喷泉：水珠从顶上往两边落
                for (i, p) in fountains.enumerated() {
                    for k in 0..<6 {
                        let phase = (t * 0.9 + Double(k) / 6 + Double(i) * 0.3).truncatingRemainder(dividingBy: 1)
                        let side: CGFloat = k % 2 == 0 ? -1 : 1
                        let x = p.x + side * CGFloat(phase) * CGFloat(5 + k) * px
                        let y = p.y - CGFloat(sin(phase * .pi)) * 7 * px + CGFloat(phase) * 6 * px
                        dot(x, y, Color(hexString: "E6F7F6")!.opacity(0.9 - phase * 0.5))
                    }
                }
                // 池塘：偶尔一圈涟漪慢慢散开
                for (i, p) in ponds.enumerated() {
                    let phase = (t * 0.22 + Double(i) * 0.61).truncatingRemainder(dividingBy: 1)
                    guard phase < 0.6 else { continue }
                    let r = CGFloat(phase / 0.6) * 6 * px + px
                    var ring = Path()
                    ring.addEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.45, width: r * 2, height: r * 0.9))
                    gc.stroke(ring, with: .color(Color.white.opacity(0.55 * (1 - phase / 0.6))), lineWidth: px)
                }
                if season == .winter {
                    // 雪：一颗颗方的，慢慢往下、左右晃
                    for i in 0..<60 {
                        let sway: CGFloat = CGFloat(sin(t * 0.8 + Double(i)) * 14)
                        let fall: CGFloat = CGFloat(t * Double(18 + i % 4 * 6))
                        let x = (Self.noise(i, 70) * w + sway).truncatingRemainder(dividingBy: w)
                        let y = (Self.noise(i, 71) * h + fall).truncatingRemainder(dividingBy: h)
                        dot(x, y, Color.white.opacity(0.9), i % 7 == 0 ? 2 : 1)
                    }
                }
                if !night {
                    // 两只海鸥从左往右飞过，翅膀一扇一扇
                    for k in 0..<2 {
                        let span = w + 200
                        let x = CGFloat((t * 22 + Double(k) * 400).truncatingRemainder(dividingBy: Double(span))) - 100
                        let y = CGFloat(80 + k * 140) + CGFloat(sin(t * 0.7 + Double(k))) * 16
                        let up = Int(t * 4 + Double(k)) % 2 == 0
                        let wc = Color.white.opacity(0.95)
                        dot(x, y, wc); dot(x + px, y, wc)
                        dot(x - px, y + (up ? -px : px), wc); dot(x - 2 * px, y + (up ? -2 * px : px), wc)
                        dot(x + 2 * px, y + (up ? -px : px), wc); dot(x + 3 * px, y + (up ? -2 * px : px), wc)
                    }
                    // 飘落的：春天花瓣、秋天叶子；冬天下雪（见下面）；夏天不飘
                    if season == .spring || season == .autumn {
                        // 飘落的：春天花瓣、秋天叶子。一大一小两块方的，跟地面一个画法
                        let autumn = season == .autumn
                        let big: Color = autumn ? Color(red: 0.95, green: 0.62, blue: 0.40) : Color(red: 0.96, green: 0.71, blue: 0.78)
                        let small: Color = autumn ? Color(red: 0.93, green: 0.77, blue: 0.42) : Color(red: 0.91, green: 0.55, blue: 0.66)
                        for i in 0..<10 {
                            let drift: Double = t * 6 * Double(1 + i % 3)
                            let x0: CGFloat = Self.noise(i, 40) * w + CGFloat(drift)
                            let y0: CGFloat = Self.noise(i, 41) * h + CGFloat(t * 12)
                            let x = x0.truncatingRemainder(dividingBy: w)
                            let y = y0.truncatingRemainder(dividingBy: h)
                            let px: CGFloat = (x / 3).rounded() * 3
                            let py: CGFloat = (y / 3).rounded() * 3
                            let beat: Int = Int(t * 2) + i
                            let flip: Bool = beat % 2 == 0
                            gc.fill(Path(CGRect(x: px, y: py, width: 6, height: 3)), with: .color(big.opacity(0.95)))
                            let sx: CGFloat = flip ? px : px + 3
                            gc.fill(Path(CGRect(x: sx, y: py + 3, width: 3, height: 3)), with: .color(small.opacity(0.95)))
                        }
                    }
                    // 两只蝴蝶
                    let wings: [Color] = season == .winter ? [] : [Color(hexString: "F7D36B")!, Color(hexString: "C9B6E8")!]
                    for (i, col) in wings.enumerated() {
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
                }
            }
        }
        .frame(width: CGFloat(width) * tile, height: CGFloat(height) * tile)
        .allowsHitTesting(false)
    }
}

/// 夜里亮着的：门窗、路灯、灯串、篝火的光晕和萤火虫。压暗那层之上单独画，不被一起压暗
struct NightGlow: View {
    let width: Int
    let height: Int
    let tile: CGFloat
    let lights: [CGPoint]
    var season: WorldSeason = .spring

    private static func noise(_ i: Int, _ k: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + Double(k) * 78.233) * 43758.5453
        return CGFloat(v - floor(v))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                var lit = gc
                lit.blendMode = .plusLighter
                for p in lights {
                    let r = CGRect(x: p.x - 70, y: p.y - 70, width: 140, height: 140)
                    let g = Gradient(colors: [Color(red: 1, green: 0.84, blue: 0.55).opacity(0.5), .clear])
                    lit.fill(Path(ellipseIn: r), with: .radialGradient(g, center: p, startRadius: 0, endRadius: 70))
                }
                let count = season == .winter ? 0 : 22
                for i in 0..<count {
                    let wob: CGFloat = CGFloat(sin(t * 0.9 + Double(i))) * 10
                    let bob: CGFloat = CGFloat(cos(t * 1.2 + Double(i))) * 8
                    let x = Self.noise(i, 50) * size.width + wob
                    let y = Self.noise(i, 51) * size.height + bob
                    let a: Double = 0.5 + 0.5 * sin(t * 2 + Double(i))
                    let g = Gradient(colors: [Color(red: 1, green: 0.96, blue: 0.67).opacity(0.95 * a), .clear])
                    lit.fill(Path(ellipseIn: CGRect(x: x - 6, y: y - 6, width: 12, height: 12)),
                             with: .radialGradient(g, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: 6))
                }
            }
        }
        .frame(width: CGFloat(width) * tile, height: CGFloat(height) * tile)
        .allowsHitTesting(false)
    }
}

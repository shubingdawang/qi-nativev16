import Foundation
import SwiftUI
import UIKit

// MARK: - 拼豆板
//
// 一块电子拼豆板：底下垫一张参考图，上面一格一格放豆子。
// 做好的东西导出成图片，放进家具素材、表情包这些地方（见 `ImportPlacementView`）。
// 纯本机，存档是 `beads.json`，参考图走 `ImageStore`。

struct BeadProject: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    /// 宽几格
    var size = 32
    /// 高几格。nil = 跟宽一样（老存档都是正方形板）
    var rows: Int?
    /// 每一格的颜色（十六进制，"" = 空）。按行排，长度 = w * h
    var cells: [String] = []
    /// 参考图（`ImageStore` 里的文件名），"" = 没有
    var refImage = ""
    var refOpacity: Double = 0.5
    var refShown = true
    /// 参考图的摆法：放大倍数、旋转（度）、平移（占板边长的比例）
    var refScale: Double = 1
    var refRotation: Double = 0
    var refX: Double = 0
    var refY: Double = 0
    /// 参考图整张铺满板子（底图的格子跟板子的格子一一对上）。nil / false = 等比放进去
    var refFill: Bool?
    /// 底图竖着再拉多少（图纸横竖格宽不一样时用，nil = 不拉）
    var refStretchY: Double?
    /// 存成了零件（表情工坊「零件」那一页、动图「逐帧」里能加进来）
    var asPart: Bool?
    var updatedAt = Date()

    init(size: Int, rows: Int? = nil, name: String = "") {
        self.size = size
        self.rows = rows
        self.name = name
        self.cells = Array(repeating: "", count: size * (rows ?? size))
    }

    var w: Int { size }
    var h: Int { rows ?? size }

    /// 一边最多多少格（拼大图用）
    static let maxSide = 200
    var filled: Int { cells.filter { !$0.isEmpty }.count }

    /// 改格数。原来放的豆子按左上角对齐留下来
    mutating func resize(_ nw: Int, _ nh: Int) {
        var out = Array(repeating: "", count: nw * nh)
        for y in 0..<min(h, nh) {
            for x in 0..<min(w, nw) { out[y * nw + x] = cells[y * w + x] }
        }
        size = nw
        rows = nh == nw ? nil : nh
        cells = out
    }
}

// 以后加字段，老存档缺哪个用默认，不许整份读不出来
extension BeadProject {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        size = max(4, (try? c.decodeIfPresent(Int.self, forKey: .size)) ?? 32)
        rows = (try? c.decodeIfPresent(Int.self, forKey: .rows)).flatMap { $0.map { max(4, $0) } }
        cells = (try? c.decodeIfPresent([String].self, forKey: .cells)) ?? []
        let count = size * (rows ?? size)
        if cells.count != count { cells = Array(repeating: "", count: count) }
        refFill = (try? c.decodeIfPresent(Bool.self, forKey: .refFill)) ?? nil
        refStretchY = (try? c.decodeIfPresent(Double.self, forKey: .refStretchY)) ?? nil
        asPart = (try? c.decodeIfPresent(Bool.self, forKey: .asPart)) ?? nil
        refImage = (try? c.decodeIfPresent(String.self, forKey: .refImage)) ?? ""
        refOpacity = (try? c.decodeIfPresent(Double.self, forKey: .refOpacity)) ?? 0.5
        refShown = (try? c.decodeIfPresent(Bool.self, forKey: .refShown)) ?? true
        refScale = (try? c.decodeIfPresent(Double.self, forKey: .refScale)) ?? 1
        refRotation = (try? c.decodeIfPresent(Double.self, forKey: .refRotation)) ?? 0
        refX = (try? c.decodeIfPresent(Double.self, forKey: .refX)) ?? 0
        refY = (try? c.decodeIfPresent(Double.self, forKey: .refY)) ?? 0
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? Date()
    }
}

@MainActor
final class BeadStore: ObservableObject {

    static let shared = BeadStore()

    @Published private(set) var projects: [BeadProject] = [] {
        didSet { if loaded { Storage.save(projects, to: "beads.json") } }
    }
    private var loaded = false

    private init() {
        projects = Storage.load([BeadProject].self, from: "beads.json") ?? []
        loaded = true
    }

    func project(_ id: UUID) -> BeadProject? { projects.first { $0.id == id } }

    @discardableResult
    func create(size: Int, refImage: String = "") -> BeadProject {
        var p = BeadProject(size: size, name: "拼豆 \(projects.count + 1)")
        p.refImage = refImage
        projects.insert(p, at: 0)
        return p
    }

    func save(_ p: BeadProject) {
        var p = p
        p.updatedAt = Date()
        if let i = projects.firstIndex(where: { $0.id == p.id }) {
            // 拼豆页手里那份是打开时拿的，没有后来在导出页打的「零件」记号：留着原来的
            if p.asPart == nil { p.asPart = projects[i].asPart }
            projects[i] = p
        } else {
            projects.insert(p, at: 0)
        }
    }

    func delete(_ id: UUID) {
        if let p = project(id), !p.refImage.isEmpty { ImageStore.delete(p.refImage) }
        projects.removeAll { $0.id == id }
    }

    // MARK: 色板

    /// 拼豆常用色，偏淡一点
    static let palette: [String] = [
        "FFFFFF", "F4F1EC", "E3DED8", "B9B2AB", "7D766F", "3B3634", "1A1717",
        "FAD4DC", "F4A7B9", "E8758F", "C9415E", "8E2440",
        "FBE3CF", "F8C39B", "F09A62", "D96B3A", "A3492A",
        "FFF3B8", "FBE27A", "F2C230", "C99A1B",
        "E2F2D3", "B8DE9C", "7FBF6A", "4C8F45", "2E5E33",
        "D6EEF2", "A9D8E6", "6FB4D2", "3F80B5", "264F82",
        "E7DCF4", "C9B6E8", "A08AD3", "6E58A8", "45346F",
        "F1D9C7", "D9B396", "B48464", "8A5A3C", "5E3A26"
    ]

    // MARK: 出图

    enum Look: String, CaseIterable, Identifiable {
        case bead, pixel
        var id: String { rawValue }
        var label: String { self == .bead ? "豆子" : "像素" }
    }

    /// 把一块板画成图。透明底；cellPx 是一格多少像素
    static func render(_ p: BeadProject, look: Look, cellPx: CGFloat = 16) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = CGSize(width: CGFloat(p.w) * cellPx, height: CGFloat(p.h) * cellPx)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let g = ctx.cgContext
            for row in 0..<p.h {
                for col in 0..<p.w {
                    let hex = p.cells[row * p.w + col]
                    guard !hex.isEmpty, let c = UIColor(beadHex: hex) else { continue }
                    let r = CGRect(x: CGFloat(col) * cellPx, y: CGFloat(row) * cellPx, width: cellPx, height: cellPx)
                    switch look {
                    case .pixel:
                        g.setFillColor(c.cgColor)
                        g.fill(r)
                    case .bead:
                        let inset = r.insetBy(dx: cellPx * 0.06, dy: cellPx * 0.06)
                        g.setFillColor(c.cgColor)
                        g.fillEllipse(in: inset)
                        // 中间那个孔
                        let hole = r.insetBy(dx: cellPx * 0.34, dy: cellPx * 0.34)
                        g.setFillColor(c.darker(0.18).cgColor)
                        g.fillEllipse(in: hole)
                        // 一点高光
                        let shine = CGRect(x: r.minX + cellPx * 0.22, y: r.minY + cellPx * 0.18,
                                           width: cellPx * 0.2, height: cellPx * 0.14)
                        g.setFillColor(UIColor.white.withAlphaComponent(0.45).cgColor)
                        g.fillEllipse(in: shine)
                    }
                }
            }
        }
    }

    /// 一键铺豆：把参考图按现在的摆法缩到 size×size，每格取色，就近换成色板里的颜色。
    /// exact = true 时不换色板，直接用原色
    ///
    /// 每格放大成 10×10 个点来看，只看中间那一圈（边上是格线），
    /// 取出现最多的那个颜色——色号那几个字只占一小撮，投不过底色
    static func trace(_ p: BeadProject, image: UIImage, exact: Bool) -> [String] {
        let k = 10
        let W = p.w * k, H = p.h * k
        // 自己开一块 RGBA 的画布，字节顺序是定的，读起来不用猜
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return p.cells }
        // UIKit 画图是左上角为原点，CGContext 是左下角：翻过来再画
        ctx.translateBy(x: 0, y: CGFloat(H))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .none
        UIGraphicsPushContext(ctx)
        drawReference(image, in: CGSize(width: W, height: H), project: p)
        UIGraphicsPopContext()
        guard let raw = ctx.data else { return p.cells }
        let ptr = raw.bindMemory(to: UInt8.self, capacity: W * H * 4)
        var out = Array(repeating: "", count: p.w * p.h)
        for cy in 0..<p.h {
            for cx in 0..<p.w {
                // 颜色按每通道 16 档分桶，桶里记个数和总和
                var bins: [Int: (n: Int, r: Double, g: Double, b: Double)] = [:]
                var opaque = 0, total = 0
                for yy in 2..<(k - 2) {
                    for xx in 2..<(k - 2) {
                        let o = ((cy * k + yy) * W + (cx * k + xx)) * 4
                        total += 1
                        let a = Double(ptr[o + 3])
                        guard a > 128 else { continue }
                        opaque += 1
                        let m = 255 / max(a, 1)
                        let r = min(255, Double(ptr[o]) * m)
                        let g = min(255, Double(ptr[o + 1]) * m)
                        let b = min(255, Double(ptr[o + 2]) * m)
                        let key = (Int(r) >> 4) << 8 | (Int(g) >> 4) << 4 | (Int(b) >> 4)
                        let e = bins[key] ?? (0, 0, 0, 0)
                        bins[key] = (e.n + 1, e.r + r, e.g + g, e.b + b)
                    }
                }
                guard opaque * 2 > total, let best = bins.values.max(by: { $0.n < $1.n }) else { continue }
                let n = Double(best.n)
                let r = best.r / n, g = best.g / n, b = best.b / n
                out[cy * p.w + cx] = exact ? String(format: "%02X%02X%02X", Int(r), Int(g), Int(b))
                                           : nearest(r, g, b)
            }
        }
        return out
    }

    private static let paletteRGB: [(String, Double, Double, Double)] = palette.compactMap { hex in
        guard let v = Int(hex, radix: 16) else { return nil }
        return (hex, Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
    }

    static func nearest(_ r: Double, _ g: Double, _ b: Double) -> String {
        var best = palette[0]
        var bestD = Double.greatestFiniteMagnitude
        for (hex, pr, pg, pb) in paletteRGB {
            // 人眼对绿最敏感，权重照常见的那组给
            let d = 0.3 * (r - pr) * (r - pr) + 0.59 * (g - pg) * (g - pg) + 0.11 * (b - pb) * (b - pb)
            if d < bestD { bestD = d; best = hex }
        }
        return best
    }

    /// 参考图在板上怎么摆：铺满整块板（`refFill`），或者等比放进去居中；再按项目里的放大、旋转、平移
    static func drawReference(_ image: UIImage, in board: CGSize, project p: BeadProject) {
        guard let g = UIGraphicsGetCurrentContext() else { return }
        let bw = board.width, bh = board.height
        let iw = image.size.width, ih = image.size.height
        guard iw > 0, ih > 0 else { return }
        let fit = min(bw / iw, bh / ih)
        let fill = p.refFill == true
        let w = fill ? bw : iw * fit, h = fill ? bh : ih * fit
        g.saveGState()
        g.translateBy(x: bw / 2 + CGFloat(p.refX) * bw, y: bh / 2 + CGFloat(p.refY) * bh)
        g.rotate(by: CGFloat(p.refRotation) * .pi / 180)
        g.scaleBy(x: CGFloat(p.refScale), y: CGFloat(p.refScale * (p.refStretchY ?? 1)))
        image.draw(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        g.restoreGState()
    }
}

extension UIColor {
    convenience init?(beadHex hex: String) {
        guard hex.count == 6, let v = Int(hex, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    func darker(_ k: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * (1 - k), green: g * (1 - k), blue: b * (1 - k), alpha: a)
    }

    var beadHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(max(0, min(1, r)) * 255),
                      Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
    }
}

// MARK: - 认出图纸上有几格

/// 她垫的常常是一张拼豆图纸（一格一格、格里写着色号）。
/// 看横竖两个方向上颜色跳变的节奏，找出一格多宽、格线从哪儿开始，算出一共几列几行。
/// 认不出来（照片、没有格子的图）返回 nil。
///
/// 一格的宽不一定是整数个点，图纸边上也常常裁掉半格：
/// 所以找的是「一格多宽 + 第一条格线在哪」，不是「一共几格」。
/// 两个方向用同一个格宽（拼豆格子是方的），长方形的图纸也对得上。
enum BeadGrid {

    struct Found {
        var cols: Int
        var rows: Int
        /// 一格多宽、多高（缩放后那张图上的点）。截出来的图纸常常横竖差一点点，分开认
        var cell: Double
        var cellY: Double
        /// 第一条竖 / 横格线在哪
        var ox: Double
        var oy: Double
        /// 缩放后那张图多大
        var w: Int
        var h: Int
    }

    static func detect(_ image: UIImage) -> (cols: Int, rows: Int)? {
        grid(image).map { ($0.cols, $0.rows) }
    }

    static func grid(_ image: UIImage) -> Found? {
        guard let cg = image.cgImage else { return nil }
        // 大图（一百多格的图纸）格线很细：缩到 1600 还看得清，缩到 900 就糊成一片认不出了
        let scale = min(1, 1600 / Double(max(cg.width, cg.height)))
        let W = max(8, Int(Double(cg.width) * scale)), H = max(8, Int(Double(cg.height) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // 直接画 CGImage：内存里第 0 行就是图的最上面那行
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
        guard let raw = ctx.data else { return nil }
        let px = raw.bindMemory(to: UInt8.self, capacity: W * H * 4)
        var gray = [Double](repeating: 0, count: W * H)
        for i in 0..<(W * H) {
            gray[i] = 0.3 * Double(px[i * 4]) + 0.59 * Double(px[i * 4 + 1]) + 0.11 * Double(px[i * 4 + 2])
        }
        var colP = [Double](repeating: 0, count: W)
        var rowP = [Double](repeating: 0, count: H)
        for y in 0..<H {
            for x in 0..<(W - 1) { colP[x] += abs(gray[y * W + x + 1] - gray[y * W + x]) }
        }
        for x in 0..<W {
            for y in 0..<(H - 1) { rowP[y] += abs(gray[(y + 1) * W + x] - gray[y * W + x]) }
        }
        let cp = detrend(colP), rp = detrend(rowP)
        let ax = period(cp), ay = period(rp)
        // 格宽：先按两个方向一起找个大概，再横竖各自细调（一百多格的大图，差 0.1 点累到最后就错开一格）
        var cell: Double
        switch (ax, ay) {
        case let (a?, b?):
            guard abs(a.cell - b.cell) / max(a.cell, b.cell) < 0.2 else { return nil }
            cell = refine(cp, rp, around: a.score >= b.score ? a.cell : b.cell)
        case let (a?, nil): cell = refine(cp, rp, around: a.cell)
        case let (nil, b?): cell = refine(cp, rp, around: b.cell)
        default: return nil
        }
        guard cell >= 4 else { return nil }
        var cx = refineAxis(cp, around: cell), cy = refineAxis(rp, around: cell)
        // 差得很少就当一样（省得把本来方的格子拉歪）
        if abs(cx - cy) / max(cx, cy) < 0.004 { cx = cell; cy = cell }
        let ox = offset(cp, cx).o, oy = offset(rp, cy).o
        // 最左、最上那一格被裁掉一大半的不算
        let cols = Int(((Double(W) - ox) / cx).rounded())
        let rows = Int(((Double(H) - oy) / cy).rounded())
        guard (4...BeadProject.maxSide).contains(cols), (4...BeadProject.maxSide).contains(rows) else { return nil }
        return Found(cols: cols, rows: rows, cell: cx, cellY: cy, ox: ox, oy: oy, w: W, h: H)
    }

    /// 去掉慢慢起伏的那部分，只留一格一格的节奏
    private static func detrend(_ raw: [Double]) -> [Double] {
        let n = raw.count
        var p = [Double](repeating: 0, count: n)
        let win = 9
        for i in 0..<n {
            let a = max(0, i - win), b = min(n - 1, i + win)
            var s = 0.0
            for j in a...b { s += raw[j] }
            p[i] = raw[i] - s / Double(b - a + 1)
        }
        return p
    }

    /// 一格大概多宽（自相关最短的那个够高的峰）
    private static func period(_ p: [Double]) -> (cell: Double, score: Double)? {
        let n = p.count
        guard n >= 16 else { return nil }
        let energy = p.reduce(0) { $0 + $1 * $1 }
        guard energy > 0 else { return nil }
        let lo = 5, hi = n / 3
        guard hi > lo + 1 else { return nil }
        var ac = [Double](repeating: 0, count: hi + 1)
        for L in lo...hi {
            var s = 0.0
            for i in 0..<(n - L) { s += p[i] * p[i + L] }
            ac[L] = s / energy
        }
        guard let peak = ac[lo...hi].max(), peak > 0.25 else { return nil }
        var L0 = (lo...hi).max(by: { ac[$0] < ac[$1] }) ?? lo
        for L in (lo + 1)..<hi where ac[L] >= peak * 0.8 && ac[L] >= ac[L - 1] && ac[L] >= ac[L + 1] {
            L0 = L
            break
        }
        return (Double(L0), ac[L0])
    }

    /// 格线落在 o, o+s, o+2s… 上时，那几处跳变有多强（取平均）
    private static func offset(_ p: [Double], _ s: Double) -> (o: Double, score: Double) {
        let n = p.count
        var best = (o: 0.0, score: -Double.infinity)
        var o = 0.0
        while o < s {
            var sum = 0.0, k = 0
            var x = o
            while x < Double(n) {
                let i = Int(x.rounded())
                var m = -Double.infinity
                for d in -1...1 where i + d >= 0 && i + d < n { m = max(m, p[i + d]) }
                if m > -Double.infinity { sum += m; k += 1 }
                x += s
            }
            if k > 0, sum / Double(k) > best.score { best = (o, sum / Double(k)) }
            o += 0.5
        }
        return best
    }

    /// 只看一个方向，在大概的格宽附近 ±3% 里细找
    private static func refineAxis(_ p: [Double], around c: Double) -> Double {
        var best = (s: c, score: -Double.infinity)
        var s = c * 0.97
        while s <= c * 1.03 {
            let score = offset(p, s).score
            if score > best.score { best = (s, score) }
            s += 0.01
        }
        return best.s
    }

    /// 在大概的格宽附近细找：两个方向的格线一起对得最齐的那个（可以不是整数）
    private static func refine(_ cp: [Double], _ rp: [Double], around c: Double) -> Double {
        var best = (s: c, score: -Double.infinity)
        var s = c * 0.9
        while s <= c * 1.1 {
            let score = offset(cp, s).score + offset(rp, s).score
            if score > best.score { best = (s, score) }
            s += 0.05
        }
        return best.s
    }
}

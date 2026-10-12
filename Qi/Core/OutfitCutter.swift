import UIKit

/// 把她画的「穿着衣服的 clawd」变成一件能穿在 clawd 身上的衣服。
///
/// 她画的是整只：clawd 的身子、眼睛、手脚 + 外面那身衣服。要做的是：
///   1. 认出哪些颜色是 clawd 自己的（珊瑚橙那一团），抠掉——露出来的地方就是他真的身子和脸
///   2. 被 clawd 身子整圈围住的小块（眼睛、腮红）一起抠掉——那是他的脸，不是衣服
///   3. 按 clawd 的轮廓对齐到他那张 36 格的图纸上：手对手、脚对脚
///   4. 分三层：身子上的跟着身子走；伸在两只手外面的（袖子）跟着手转
///
/// 不管她画的是恐龙、小熊还是一件毛衣，走的都是这一套。
struct OutfitCutter {

    let w: Int
    let h: Int
    /// 图纸上每一格的颜色（"" = 空）
    let cells: [String]
    /// 算作 clawd 身子的颜色（抠掉）
    var clawdColors: Set<String>
    /// 图纸一格 = 画布上几格
    var scale: Double
    /// 图纸 (0,0) 那一格的左上角落在画布哪儿（画布格）
    var offX: Double
    var offY: Double

    /// 画布上 clawd 站着时占的地方（含手脚）：第 2..31 列、第 14..31 行
    static let target = (x0: 2.0, x1: 32.0, y0: 14.0, y1: 32.0)
    /// 袖子图比手那一块四周各多出几格
    static let margin = 4

    init(w: Int, h: Int, cells: [String]) {
        self.w = w; self.h = h; self.cells = cells
        self.clawdColors = Self.guessClawd(cells)
        self.scale = 1; self.offX = 0; self.offY = 0
        autoFit()
    }

    /// 图纸里用到的颜色，按用得多少排
    var colors: [String] {
        var n: [String: Int] = [:]
        for c in cells where !c.isEmpty { n[c, default: 0] += 1 }
        return n.sorted { $0.value > $1.value }.map(\.key)
    }

    // MARK: 认出 clawd

    /// 珊瑚橙那一档里用得最多的那个颜色，加上跟它很像的
    static func guessClawd(_ cells: [String]) -> Set<String> {
        var n: [String: Int] = [:]
        for c in cells where !c.isEmpty { n[c, default: 0] += 1 }
        let warm = n.filter { k, _ in
            guard let (hh, s, v) = hsv(k) else { return false }
            return (hh >= 0 && hh <= 40 || hh >= 350) && s >= 0.3 && v >= 0.45
        }
        guard let main = warm.max(by: { $0.value < $1.value })?.key, let m = rgb(main) else { return [] }
        var out: Set<String> = [main]
        for k in warm.keys where k != main {
            if let c = rgb(k), dist(c, m) < 48 { out.insert(k) }
        }
        return out
    }

    /// 哪些格要抠掉：clawd 的颜色 + 被它整圈围住的小块（眼睛、腮红）
    func removed() -> [Bool] {
        var out = cells.map { clawdColors.contains($0) }
        var seen = Array(repeating: false, count: w * h)
        for start in 0..<(w * h) where !seen[start] && !out[start] && !cells[start].isEmpty {
            // 一块同样不是 clawd 的连通区
            var comp: [Int] = [], stack = [start], enclosed = true
            seen[start] = true
            while let i = stack.popLast() {
                comp.append(i)
                let x = i % w, y = i / w
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { enclosed = false; continue }
                    let j = ny * w + nx
                    if out[j] { continue }
                    if cells[j].isEmpty { enclosed = false; continue }
                    if !seen[j] { seen[j] = true; stack.append(j) }
                }
            }
            if enclosed && comp.count <= max(8, w * h / 60) {
                for i in comp { out[i] = true }
            }
        }
        return out
    }

    /// 自动对齐：图纸里 clawd 那一团的外框对上画布上 clawd 的外框，脚底对脚底
    mutating func autoFit() {
        let mask = cells.map { clawdColors.contains($0) }
        var x0 = w, x1 = -1, y0 = h, y1 = -1
        for i in 0..<(w * h) where mask[i] {
            let x = i % w, y = i / w
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        }
        let t = Self.target
        if x1 < x0 {
            // 没认出 clawd：整张放进他身上那一块
            var bx0 = w, bx1 = -1, by0 = h, by1 = -1
            for i in 0..<(w * h) where !cells[i].isEmpty {
                let x = i % w, y = i / w
                bx0 = min(bx0, x); bx1 = max(bx1, x); by0 = min(by0, y); by1 = max(by1, y)
            }
            guard bx1 >= bx0 else { return }
            let s = min((t.x1 - t.x0) / Double(bx1 - bx0 + 1), (t.y1 - t.y0) / Double(by1 - by0 + 1))
            scale = s
            offX = (t.x0 + t.x1) / 2 - Double(bx0 + bx1 + 1) / 2 * s
            offY = t.y1 - Double(by1 + 1) * s
            return
        }
        let sx = (t.x1 - t.x0) / Double(x1 - x0 + 1)
        let sy = (t.y1 - t.y0) / Double(y1 - y0 + 1)
        // 两个方向差不多就取平均；差太多（手或脚被衣服盖住了）以高度为准
        let s = abs(sx - sy) / max(sx, sy) < 0.25 ? (sx + sy) / 2 : sy
        scale = s
        offX = (t.x0 + t.x1) / 2 - Double(x0 + x1 + 1) / 2 * s
        offY = t.y1 - Double(y1 + 1) * s
        uncoverEyes()
    }

    /// clawd 的眼睛在画布上哪几格（站着那张）
    static let eyeCells: [(Int, Int)] = {
        var out: [(Int, Int)] = []
        for (y, row) in ClawdSprites.idle.rows.enumerated() {
            for (x, ch) in row.enumerated() where ch == "k" { out.append((x, y)) }
        }
        return out
    }()

    /// clawd 身子（不算手脚）在画布上哪几格
    static let bodyCells: [(Int, Int)] = {
        var out: [(Int, Int)] = []
        for (y, row) in ClawdSprites.idle.rows.enumerated() where y >= ClawdRig.bodyTop && y < ClawdRig.legTop {
            for (x, ch) in row.enumerated() where ch != "." && x >= ClawdRig.bodyLeft && x <= ClawdRig.bodyRight {
                out.append((x, y))
            }
        }
        return out
    }()

    /// 衣服该盖住的地方却露出了 clawd 的身子：图纸上那儿是空的，他身上却有
    func exposedBody() -> Int {
        let rem = removed()
        var n = 0
        for (bx, by) in Self.bodyCells {
            let gx = Int(((Double(bx) + 0.5) - offX) / scale)
            let gy = Int(((Double(by) + 0.5) - offY) / scale)
            guard gx >= 0, gy >= 0, gx < w, gy < h else { n += 1; continue }
            let i = gy * w + gx
            if !rem[i] && cells[i].isEmpty { n += 1 }
        }
        return n
    }

    /// 眼睛被衣服盖住了几格
    func coveredEyes() -> Int {
        let rem = removed()
        var n = 0
        for (ex, ey) in Self.eyeCells {
            // 这一格画布的中心落在图纸哪一格
            let gx = Int(((Double(ex) + 0.5) - offX) / scale)
            let gy = Int(((Double(ey) + 0.5) - offY) / scale)
            guard gx >= 0, gy >= 0, gx < w, gy < h else { continue }
            let i = gy * w + gx
            if !rem[i] && !cells[i].isEmpty { n += 1 }
        }
        return n
    }

    /// 眼睛被盖住、或者身子露出一截的话，在附近上下左右挪一点、大小调一点，
    /// 挑「盖眼睛 + 露身子」最少、挪得最少的那个（盖眼睛算两倍）
    mutating func uncoverEyes() {
        func score() -> Int { coveredEyes() * 2 + exposedBody() }
        guard score() > 0 else { return }
        let base = (s: scale, x: offX, y: offY)
        var best = (cover: score(), cost: 0.0, s: scale, x: offX, y: offY)
        let cx = (Self.target.x0 + Self.target.x1) / 2, by = Self.target.y1
        for k in [1.0, 0.96, 1.04, 0.92, 1.08] {
            for dy in stride(from: -2.5, through: 2.5, by: 0.5) {
                for dx in stride(from: -1.0, through: 1.0, by: 0.5) {
                    scale = base.s * k
                    offX = cx - (cx - base.x) * k + dx
                    offY = by - (by - base.y) * k + dy
                    let c = score()
                    let cost = abs(dy) + abs(dx) + abs(k - 1) * 20
                    if c < best.cover || (c == best.cover && cost < best.cost) {
                        best = (c, cost, scale, offX, offY)
                    }
                }
            }
        }
        scale = best.s; offX = best.x; offY = best.y
    }

    // MARK: 出图

    struct Layers {
        var body: UIImage
        var left: UIImage?
        var right: UIImage?
    }

    /// 一格画布 = 多少像素
    static let px: CGFloat = 16

    func render() -> Layers {
        let rem = removed()
        let n = CGFloat(ClawdRig.canvas)
        let M = CGFloat(Self.margin)
        let armW = CGFloat(ClawdRig.arm.width), armH = CGFloat(ClawdRig.arm.height)
        let leftX = CGFloat(ClawdRig.bodyLeft - ClawdRig.armOut)
        let rightX = CGFloat(ClawdRig.bodyRight + 1 - ClawdRig.armOut)
        let armY = CGFloat(ClawdRig.armRow)
        // 每一格归哪一层
        var bodyCells: [(CGRect, UIColor)] = []
        var leftCells: [(CGRect, UIColor)] = []
        var rightCells: [(CGRect, UIColor)] = []
        for i in 0..<(w * h) where !rem[i] {
            guard let c = UIColor(beadHex: cells[i]) else { continue }
            let x = Double(i % w), y = Double(i / w)
            let r = CGRect(x: offX + x * scale, y: offY + y * scale, width: scale, height: scale)
            let cx = r.midX, cy = r.midY
            let nearArm = cy >= armY - 2 && cy <= armY + armH + 2
            if nearArm && cx < CGFloat(ClawdRig.bodyLeft) {
                leftCells.append((r.offsetBy(dx: -(leftX - M), dy: -(armY - M)), c))
            } else if nearArm && cx > CGFloat(ClawdRig.bodyRight + 1) {
                rightCells.append((r.offsetBy(dx: -(rightX - M), dy: -(armY - M)), c))
            } else {
                bodyCells.append((r, c))
            }
        }
        let body = Self.paint(bodyCells, size: CGSize(width: n, height: n))
        let sleeveSize = CGSize(width: armW + 2 * M, height: armH + 2 * M)
        return Layers(body: body,
                      left: leftCells.isEmpty ? nil : Self.paint(leftCells, size: sleeveSize),
                      right: rightCells.isEmpty ? nil : Self.paint(rightCells, size: sleeveSize))
    }

    private static func paint(_ cells: [(CGRect, UIColor)], size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let k = px
        return UIGraphicsImageRenderer(size: CGSize(width: size.width * k, height: size.height * k), format: format)
            .image { ctx in
                let g = ctx.cgContext
                g.setShouldAntialias(false)
                for (r, c) in cells {
                    g.setFillColor(c.cgColor)
                    // 往外多铺半个像素，格与格之间不留缝
                    g.fill(CGRect(x: (r.minX * k).rounded(.down), y: (r.minY * k).rounded(.down),
                                  width: (r.width * k).rounded(.up) + 1, height: (r.height * k).rounded(.up) + 1))
                }
            }
    }

    /// 眼睛画在衣服上面
    var eyesOnTop = true

    /// 给她看的样子：站着的 clawd 穿上这件（静止那一帧）
    func preview() -> UIImage {
        let layers = render()
        let n = CGFloat(ClawdRig.canvas)
        let k = Self.px
        let M = CGFloat(Self.margin)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: n * k, height: n * k), format: format).image { ctx in
            let g = ctx.cgContext
            g.interpolationQuality = .none
            // clawd 本身（站着那张）
            let s = ClawdSprites.idle
            for (y, row) in s.rows.enumerated() {
                for (x, ch) in row.enumerated() where ch != "." {
                    let col = UIColor(s.palette[ch] ?? .clear)
                    g.setFillColor(col.cgColor)
                    g.fill(CGRect(x: CGFloat(x) * k, y: CGFloat(y) * k, width: k, height: k))
                }
            }
            let armY = CGFloat(ClawdRig.armRow)
            if let l = layers.left {
                l.draw(in: CGRect(x: (CGFloat(ClawdRig.bodyLeft - ClawdRig.armOut) - M) * k, y: (armY - M) * k,
                                  width: l.size.width, height: l.size.height))
            }
            if let r = layers.right {
                r.draw(in: CGRect(x: (CGFloat(ClawdRig.bodyRight + 1 - ClawdRig.armOut) - M) * k, y: (armY - M) * k,
                                  width: r.size.width, height: r.size.height))
            }
            layers.body.draw(in: CGRect(x: 0, y: 0, width: n * k, height: n * k))
            if eyesOnTop {
                g.setFillColor(UIColor(s.palette["k"] ?? .black).cgColor)
                for (x, y) in Self.eyeCells {
                    g.fill(CGRect(x: CGFloat(x) * k, y: CGFloat(y) * k, width: k, height: k))
                }
            }
        }
    }

    // MARK: 颜色小工具

    static func rgb(_ hex: String) -> (Double, Double, Double)? {
        guard hex.count == 6, let v = Int(hex, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
    }

    static func hsv(_ hex: String) -> (Double, Double, Double)? {
        guard let (r, g, b) = rgb(hex) else { return nil }
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var hh = 0.0
        if d > 0 {
            if mx == r { hh = 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { hh = 60 * ((b - r) / d + 2) }
            else { hh = 60 * ((r - g) / d + 4) }
        }
        if hh < 0 { hh += 360 }
        return (hh, mx == 0 ? 0 : d / mx, mx / 255)
    }

    static func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let dr = a.0 - b.0, dg = a.1 - b.1, db = a.2 - b.2
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    /// 一张图（她导出的、导入的像素图）→ 图纸
    @MainActor
    static func grid(from image: UIImage) -> (w: Int, h: Int, cells: [String])? {
        var p = BeadProject(size: 32)
        p.refFill = true
        if let g = BeadGrid.detect(image) {
            p.resize(g.cols, g.rows)
        } else {
            // 认不出格子：按小边 32 格读
            let iw = image.size.width, ih = image.size.height
            guard iw > 0, ih > 0 else { return nil }
            let ratio = Double(ih / iw)
            p.resize(ratio >= 1 ? 32 : max(4, Int(32 / ratio)), ratio >= 1 ? max(4, Int(32 * ratio)) : 32)
        }
        let cells = BeadStore.trace(p, image: image, exact: true)
        return (p.w, p.h, cells)
    }
}

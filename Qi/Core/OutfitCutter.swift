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

    /// 从存下来的那一份接着改
    init(_ d: OutfitDesign) {
        self.w = d.w; self.h = d.h; self.cells = d.cells
        self.clawdColors = Set(d.clawdColors)
        self.scale = d.scale; self.offX = d.offX; self.offY = d.offY
        self.slot = ClawdRig.WearSlot(rawValue: d.slot) ?? .outer
        self.eyesOnTop = d.eyesOnTop
        self.eyeNudgeX = d.eyeNudgeX; self.eyeNudgeY = d.eyeNudgeY; self.eyeScale = d.eyeScale
    }

    /// 存下来，好回去改
    var design: OutfitDesign {
        OutfitDesign(w: w, h: h, cells: cells, slot: slot.rawValue, clawdColors: Array(clawdColors),
                     scale: scale, offX: offX, offY: offY, eyesOnTop: eyesOnTop,
                     eyeNudgeX: eyeNudgeX, eyeNudgeY: eyeNudgeY, eyeScale: eyeScale)
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
        // 底色：从四边连进来的近白色（她的板子常常整块铺了白豆子当底）。
        // 牙、眼白这种在里面的白不连边，不会被当成底色
        let bg = background()
        for i in 0..<(w * h) where bg[i] { out[i] = true }
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

    /// 从四条边往里连着的近白色格子（底色）
    func background() -> [Bool] {
        var bg = Array(repeating: false, count: w * h)
        func whiteish(_ i: Int) -> Bool {
            guard let (r, g, b) = Self.rgb(cells[i]) else { return false }
            return min(r, g, b) > 226
        }
        var stack: [Int] = []
        for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
        for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
        while let i = stack.popLast() {
            guard !bg[i], whiteish(i) else { continue }
            bg[i] = true
            let x = i % w, y = i / w
            if x > 0 { stack.append(i - 1) }
            if x < w - 1 { stack.append(i + 1) }
            if y > 0 { stack.append(i - w) }
            if y < h - 1 { stack.append(i + w) }
        }
        return bg
    }

    /// 自动对齐：图纸里 clawd 那一团的外框对上画布上 clawd 的外框，脚底对脚底
    /// 这件穿在哪儿。整套（外套）才抠 clawd、分袖子；帽子这些只是一件，直接摆到那个位置
    var slot: ClawdRig.WearSlot = .outer

    var isOutfit: Bool { slot == .outer || slot == .body }

    /// 换一个位置：整套就照着 clawd 抠；单件不抠颜色、眼睛也不动
    mutating func setSlot(_ s: ClawdRig.WearSlot) {
        slot = s
        clawdColors = isOutfit ? Self.guessClawd(cells) : []
        eyesOnTop = isOutfit
        eyeNudgeX = 0; eyeNudgeY = 0; eyeScale = 1
        autoFit()
    }

    /// 单件摆到他身上那个位置：帽子扣在头顶、眼镜在眼睛那儿、鞋在脚底……
    private mutating func placePiece() {
        let bg = background()
        var bx0 = w, bx1 = -1, by0 = h, by1 = -1
        for i in 0..<(w * h) where !cells[i].isEmpty && !bg[i] && !clawdColors.contains(cells[i]) {
            let x = i % w, y = i / w
            bx0 = min(bx0, x); bx1 = max(bx1, x); by0 = min(by0, y); by1 = max(by1, y)
        }
        guard bx1 >= bx0 else { return }
        let pw = Double(bx1 - bx0 + 1), ph = Double(by1 - by0 + 1)
        let cx = 17.0
        // 每个位置：多宽、哪条边对在哪一行
        let width: Double, anchorY: Double, bottomAnchored: Bool
        switch slot {
        case .head:  width = 22; anchorY = 16.5; bottomAnchored = true     // 帽檐压在头顶往下两格
        case .face:  width = 18; anchorY = 20.5; bottomAnchored = false    // 中间对着眼睛
        case .neck, .scarf: width = 20; anchorY = 23.5; bottomAnchored = false
        case .back:  width = 16; anchorY = 22; bottomAnchored = false
        case .feet:  width = 20; anchorY = 32; bottomAnchored = true
        default:     width = 22; anchorY = 22; bottomAnchored = false
        }
        let s = width / pw
        scale = s
        offX = cx - (Double(bx0) + pw / 2) * s
        offY = bottomAnchored ? anchorY - (Double(by0) + ph) * s : anchorY - (Double(by0) + ph / 2) * s
    }

    mutating func autoFit() {
        guard isOutfit else { placePiece(); return }
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
            let bg = background()
            for i in 0..<(w * h) where !cells[i].isEmpty && !bg[i] {
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

    /// 她画的 clawd 眼睛（被身子围住的深色小块）落在画布哪儿。没画就是 nil
    func drawnEyeCenter() -> (x: Double, y: Double)? {
        let rem = removed()
        var sx = 0.0, sy = 0.0, n = 0.0
        for i in 0..<(w * h) where rem[i] && !clawdColors.contains(cells[i]) {
            guard let (r, g, b) = Self.rgb(cells[i]), r + g + b < 240 else { continue }
            sx += offX + (Double(i % w) + 0.5) * scale
            sy += offY + (Double(i / w) + 0.5) * scale
            n += 1
        }
        return n > 0 ? (sx / n, sy / n) : nil
    }

    /// 他的眼睛要挪几格，才落在她画眼睛的地方（眼睛露在外面时才挪）
    var eyeShift: (dx: Int, dy: Int) {
        guard eyesOnTop, let c = drawnEyeCenter(), !Self.eyeCells.isEmpty else { return (0, 0) }
        let ex = Self.eyeCells.reduce(0.0) { $0 + Double($1.0) + 0.5 } / Double(Self.eyeCells.count)
        let ey = Self.eyeCells.reduce(0.0) { $0 + Double($1.1) + 0.5 } / Double(Self.eyeCells.count)
        return (Int((c.x - ex).rounded()), Int((c.y - ey).rounded()))
    }

    /// 两只眼睛合起来的中心（画布格，左上角算起）
    static var eyeCenter: CGPoint {
        guard !eyeCells.isEmpty else { return CGPoint(x: 17, y: 20) }
        let xs = eyeCells.map { Double($0.0) }, ys = eyeCells.map { Double($0.1) }
        return CGPoint(x: (xs.min()! + xs.max()! + 1) / 2, y: (ys.min()! + ys.max()! + 1) / 2)
    }

    /// 眼睛被衣服盖住了几格（按挪过以后的位置算）
    func coveredEyes() -> Int {
        let rem = removed()
        let sh = eyeShift
        var n = 0
        for (ex0, ey0) in Self.eyeCells {
            let ex = ex0 + sh.dx, ey = ey0 + sh.dy
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
        var eyeDX = 0.0
        var eyeDY = 0.0
        var eyeScale = 1.0
    }

    /// 她自己再挪一挪眼睛（画布格）、调大小
    var eyeNudgeX = 0.0
    var eyeNudgeY = 0.0
    var eyeScale = 1.0

    /// 眼睛最后挪多少：按她画的位置挪 + 她自己再挪的那一点
    var eyeOffset: (x: Double, y: Double) {
        let sh = eyeShift
        return (Double(sh.dx) + eyeNudgeX, Double(sh.dy) + eyeNudgeY)
    }

    /// 眼睛挪走以后，原来那双的位置用他身子的颜色盖上（不然会有四只眼睛）。
    /// 上下各多盖一行：闭眼、笑眼那几帧眼睛的位置略有不同
    private func eyePatch() -> [(CGRect, UIColor)] {
        // 眼睛画在衣服上面的时候，原来那双一律盖掉（挪了、放大了都不会冒出第二双）
        guard eyesOnTop else { return [] }
        let col = UIColor(ClawdSprites.idle.palette["p"] ?? .orange)
        var seen = Set<Int>()
        var out: [(CGRect, UIColor)] = []
        for (x, y) in Self.eyeCells {
            for yy in (y - 1)...(y + 1) where seen.insert(yy * 64 + x).inserted {
                out.append((CGRect(x: x, y: yy, width: 1, height: 1), col))
            }
        }
        return out
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
        var bodyCells: [(CGRect, UIColor)] = eyePatch()
        var leftCells: [(CGRect, UIColor)] = []
        var rightCells: [(CGRect, UIColor)] = []
        for i in 0..<(w * h) where !rem[i] {
            guard let c = UIColor(beadHex: cells[i]) else { continue }
            let x = Double(i % w), y = Double(i / w)
            let r = CGRect(x: offX + x * scale, y: offY + y * scale, width: scale, height: scale)
            let cx = r.midX, cy = r.midY
            let nearArm = isOutfit && cy >= armY - 2 && cy <= armY + armH + 2
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
        let off = eyeOffset
        return Layers(body: body,
                      left: leftCells.isEmpty ? nil : Self.paint(leftCells, size: sleeveSize),
                      right: rightCells.isEmpty ? nil : Self.paint(rightCells, size: sleeveSize),
                      eyeDX: off.x, eyeDY: off.y, eyeScale: eyeScale)
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
                let c = Self.eyeCenter
                let sc = CGFloat(layers.eyeScale)
                for (x, y) in Self.eyeCells {
                    // 绕两只眼睛的中心放大缩小，再挪过去
                    let ex = c.x + (CGFloat(x) - c.x) * sc + CGFloat(layers.eyeDX)
                    let ey = c.y + (CGFloat(y) - c.y) * sc + CGFloat(layers.eyeDY)
                    g.fill(CGRect(x: ex * k, y: ey * k, width: k * sc, height: k * sc))
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
        if BeadGrid.grid(image) != nil {
            // 认出格子：跟垫底图一样，格线对格线
            p.fitToReference(image)
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

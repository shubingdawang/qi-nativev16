import SwiftUI

// MARK: - 等距家具：画出来的那一批
//
// 她说「用素材和你画的过渡一起」。这一份是**我画的那一半**。
//
// ## 为什么不是一张张手画
//
// 上一版那批家具是**正面看的**，摆进等距屋里像立牌——
// 一眼就看得出「这张图和这间屋不是一个世界的」。
//
// 但一件件手画等距图是个无底洞：一张床要画顶面、左面、右面、
// 被子、枕头、床腿的明暗……画完二十件，她想加第二十一件又得从头来。
//
// 所以这儿画的不是「家具」，是**一个等距积木**：
// 给它占地几格、多高、什么颜色，它自己算出顶面／左面／右面三块，
// 顶面最亮、左面中等、右面最暗——**光从左上来**，一套光照贯穿全屋。
//
// 家具就是几块积木摞起来：
// 床 = 床板 + 被子 + 枕头，桌子 = 四条腿 + 一块台面，凳子 = 腿 + 座面。
// **加一件新家具是摞几块积木，不是画一张图。**
//
// ## 为什么这样就够好看
//
// 等距像素画的立体感八成来自**三个面的明暗差**，不是细节。
// 三块颜色一分，方块立刻就"立"起来了；
// 细节（花纹、木纹）是锦上添花，没有也成立。
//
// ⚠️ 这一批是**过渡**。等她挑好真正的素材（CC0 那些，或者她自己画的），
// 换的是图，`IsoRoom` 那套几何、遮挡、摆放一行都不用动。

enum IsoArt {

    /// 半格宽多少像素。**决定整批家具的颗粒度。**
    ///
    /// 4 是试出来的：再小一件家具只有十几像素宽，顶面画不出菱形；
    /// 再大整张图就超过屏幕上那一格的实际点数，画了也看不清。
    static let unit = 4

    // MARK: 一块画布

    /// 一张字符网格。`.` 是透明。
    struct Canvas {
        var w: Int
        var h: Int
        var rows: [[Character]]

        init(w: Int, h: Int) {
            self.w = max(1, w)
            self.h = max(1, h)
            rows = Array(repeating: Array(repeating: Character("."), count: self.w),
                         count: self.h)
        }

        mutating func set(_ x: Int, _ y: Int, _ c: Character) {
            guard x >= 0, y >= 0, x < w, y < h else { return }
            rows[y][x] = c
        }

        /// 填一个凸四边形。
        ///
        /// 等距的顶面／侧面都是平行四边形，**扫描线填就够了**——
        /// 不用通用多边形算法：四个点、上下扫一遍、每行求左右边界。
        mutating func quad(_ p: [(Double, Double)], _ c: Character) {
            guard p.count == 4 else { return }
            let minY = Int(p.map(\.1).min()!.rounded(.down))
            let maxY = Int(p.map(\.1).max()!.rounded(.up))
            for y in minY...max(minY, maxY) {
                var xs: [Double] = []
                for i in 0..<4 {
                    let a = p[i], b = p[(i + 1) % 4]
                    // 这条边跨过这一行没有
                    guard (a.1 <= Double(y) && b.1 > Double(y))
                            || (b.1 <= Double(y) && a.1 > Double(y)) else { continue }
                    let t = (Double(y) - a.1) / (b.1 - a.1)
                    xs.append(a.0 + (b.0 - a.0) * t)
                }
                guard xs.count >= 2 else { continue }
                let lo = Int(xs.min()!.rounded()), hi = Int(xs.max()!.rounded())
                for x in lo..<max(lo + 1, hi) { set(x, y, c) }
            }
        }

        var sprite: [String] { rows.map { String($0) } }
    }

    // MARK: 一块等距积木

    /// 一个等距的方块。
    ///
    /// `a × b` 是占地（格），`hi` 是高（像素）。
    /// `at` 是它在画布上落脚的那一点（底面最上那个角）。
    ///
    /// 三个面：顶（最亮）、左前（中）、右前（最暗）。
    /// **光永远从左上来**——全屋一套光，才不会这件亮那件暗。
    static func box(_ cv: inout Canvas,
                    at: (Double, Double),
                    a: Double, b: Double, hi: Double,
                    top: Character, left: Character, right: Character) {
        let u = Double(unit)
        func s(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double) {
            (at.0 + (x - y) * u, at.1 + (x + y) * u / 2 - z)
        }
        // 先画两个侧面，顶面压在最后——顶面盖住侧面的上边缘，接缝才干净
        cv.quad([s(0, b, 0), s(0, b, hi), s(a, b, hi), s(a, b, 0)], left)
        cv.quad([s(a, 0, 0), s(a, 0, hi), s(a, b, hi), s(a, b, 0)], right)
        cv.quad([s(0, 0, hi), s(a, 0, hi), s(a, b, hi), s(0, b, hi)], top)
    }

    /// 起一张够装下 `a × b × hi` 的画布，并给出落脚点。
    ///
    /// 画布要多大：宽 = (a+b) 个半格，高 = (a+b) 个四分格 + 高度。
    /// 落脚点在最上那个角，横着居中。
    static func canvas(a: Double, b: Double, hi: Double) -> (Canvas, (Double, Double)) {
        let u = Double(unit)
        let w = Int(((a + b) * u).rounded(.up)) + 2
        let h = Int(((a + b) * u / 2 + hi).rounded(.up)) + 2
        let cv = Canvas(w: w, h: h)
        // 最上那个角：x 在 b 那一侧算出来，y 留出高度
        let origin = (b * u + 1, hi + 1)
        return (cv, origin)
    }

    // MARK: 颜色

    /// 一种材质的三个面。**深浅差得够开才立得起来**——
    /// 差一点点的话三个面糊成一块，还是平的。
    struct Mat {
        let top: Character, left: Character, right: Character
    }

    static let wood  = Mat(top: "W", left: "w", right: "v")
    static let cloth = Mat(top: "C", left: "c", right: "x")
    static let pink  = Mat(top: "P", left: "p", right: "o")
    static let white = Mat(top: "N", left: "n", right: "m")
    static let green = Mat(top: "G", left: "g", right: "f")
    static let metal = Mat(top: "S", left: "s", right: "r")

    /// 这一批家具的调色板。
    ///
    /// 每种材质三档：顶面最亮、左面中等、右面最暗。
    /// 亮度差**统一按一套来**（大约 100% / 82% / 64%），
    /// 一屋子东西才像是同一盏灯照出来的。
    static let palette: [Character: Color] = [
        "W": Color(hexString: "C89B6A")!, "w": Color(hexString: "A57F53")!,
        "v": Color(hexString: "80613E")!,
        "C": Color(hexString: "E8DCC6")!, "c": Color(hexString: "C7BBA3")!,
        "x": Color(hexString: "9E9380")!,
        "P": Color(hexString: "F0A9B4")!, "p": Color(hexString: "D18693")!,
        "o": Color(hexString: "A96874")!,
        "N": Color(hexString: "F5F1E8")!, "n": Color(hexString: "D6D1C4")!,
        "m": Color(hexString: "ADA89B")!,
        "G": Color(hexString: "8FBF7F")!, "g": Color(hexString: "6E9C61")!,
        "f": Color(hexString: "537745")!,
        "S": Color(hexString: "C3C7CC")!, "s": Color(hexString: "9EA3A9")!,
        "r": Color(hexString: "787D84")!,
        "y": Color(hexString: "F2D98C")!,   // 灯罩透出来的暖黄
        "K": Color(hexString: "2E2A26")!    // 描重的地方（灯罩口、屏幕）
    ]

    // MARK: 几件家具

    /// 摞积木。**每一件就这么几行。**
    static func make(_ build: (inout Canvas, (Double, Double)) -> Void,
                     a: Double, b: Double, hi: Double) -> PixelSprite {
        var (cv, o) = canvas(a: a, b: b, hi: hi)
        build(&cv, o)
        return PixelSprite(cv.sprite, palette)
    }

    /// 床：床板 + 被子 + 枕头
    static let bed = make({ cv, o in
        box(&cv, at: o, a: 2, b: 2, hi: 5, top: wood.top, left: wood.left, right: wood.right)
        // 被子摞在床板上，稍微窄一点，露出一圈床沿
        box(&cv, at: (o.0, o.1 - 5), a: 1.75, b: 1.35, hi: 3,
            top: pink.top, left: pink.left, right: pink.right)
        // 枕头在里侧那一头
        box(&cv, at: (o.0, o.1 - 8), a: 1.6, b: 0.5, hi: 3,
            top: white.top, left: white.left, right: white.right)
    }, a: 2, b: 2, hi: 11)

    /// 桌子：四条腿 + 一块台面。
    ///
    /// ⚠️ **画的占地必须跟 `IsoShape` 里写的一模一样**（桌子是 2×1）。
    /// 对不上的话，摆的位置会差半格——而且是**每一件都差**，
    /// 看着像整屋家具都没对齐地砖。
    static let table = make({ cv, o in
        let u = Double(unit)
        for (dx, dy) in [(0.15, 0.1), (1.55, 0.1), (0.15, 0.7), (1.55, 0.7)] {
            box(&cv, at: (o.0 + (dx - dy) * u, o.1 + (dx + dy) * u / 2),
                a: 0.3, b: 0.25, hi: 7,
                top: wood.top, left: wood.left, right: wood.right)
        }
        box(&cv, at: (o.0, o.1 - 7), a: 2, b: 1, hi: 2,
            top: wood.top, left: wood.left, right: wood.right)
    }, a: 2, b: 1, hi: 9)

    /// 凳子
    static let stool = make({ cv, o in
        let u = Double(unit)
        for (dx, dy) in [(0.1, 0.1), (0.6, 0.1), (0.1, 0.6), (0.6, 0.6)] {
            box(&cv, at: (o.0 + (dx - dy) * u, o.1 + (dx + dy) * u / 2),
                a: 0.25, b: 0.25, hi: 5,
                top: wood.top, left: wood.left, right: wood.right)
        }
        box(&cv, at: (o.0, o.1 - 5), a: 1, b: 1, hi: 2,
            top: cloth.top, left: cloth.left, right: cloth.right)
    }, a: 1, b: 1, hi: 7)

    /// 沙发：坐垫 + 靠背
    static let sofa = make({ cv, o in
        box(&cv, at: o, a: 2, b: 1, hi: 4,
            top: cloth.top, left: cloth.left, right: cloth.right)
        // 靠背贴在里侧
        box(&cv, at: (o.0, o.1 - 4), a: 2, b: 0.35, hi: 6,
            top: cloth.top, left: cloth.left, right: cloth.right)
    }, a: 2, b: 1, hi: 10)

    /// 书架：一根高柜 + 两层隔板
    static let shelf = make({ cv, o in
        box(&cv, at: o, a: 1, b: 1, hi: 16,
            top: wood.top, left: wood.left, right: wood.right)
        for z in [5.0, 10.0] {
            box(&cv, at: (o.0, o.1 - z), a: 0.95, b: 0.95, hi: 1,
                top: green.top, left: green.left, right: green.right)
        }
    }, a: 1, b: 1, hi: 17)

    /// 台灯：细杆 + 灯罩
    static let lamp = make({ cv, o in
        let u = Double(unit)
        box(&cv, at: (o.0 + 0.35 * u, o.1 + 0.35 * u / 2), a: 0.3, b: 0.3, hi: 11,
            top: metal.top, left: metal.left, right: metal.right)
        box(&cv, at: (o.0, o.1 - 11), a: 1, b: 1, hi: 4,
            top: "y", left: "y", right: "K")
    }, a: 1, b: 1, hi: 15)

    /// 地毯：**只有顶面**，它是摊在地上的
    static let rug = make({ cv, o in
        box(&cv, at: o, a: 3, b: 3, hi: 0,
            top: pink.top, left: pink.top, right: pink.top)
    }, a: 3, b: 3, hi: 1)

    /// 电视：柜子 + 屏幕
    static let tv = make({ cv, o in
        box(&cv, at: o, a: 1, b: 1, hi: 4,
            top: wood.top, left: wood.left, right: wood.right)
        box(&cv, at: (o.0, o.1 - 4), a: 0.9, b: 0.25, hi: 6,
            top: metal.top, left: "K", right: "K")
    }, a: 1, b: 1, hi: 11)

    // MARK: 厨房和浴室
    //
    // ⚠️ **画的占地必须跟 `IsoShape` 里写的一模一样**，
    // 对不上的话每一件都会差半格，看着像整屋家具都没对齐地砖。
    // 这八件除了浴缸是 2×1，其余全是 1×1。

    /// 冰箱：一根高柜，中间横一道门缝，右边一个把手
    static let fridge = make({ cv, o in
        box(&cv, at: o, a: 1, b: 1, hi: 18,
            top: white.top, left: white.left, right: white.right)
        // 门缝：在柜身上压一条暗色的薄片
        box(&cv, at: (o.0, o.1 - 11), a: 1.01, b: 1.01, hi: 0.6,
            top: metal.right, left: metal.right, right: metal.right)
        // 把手
        box(&cv, at: (o.0 + 3.4, o.1 - 13.5), a: 0.12, b: 0.5, hi: 3,
            top: metal.top, left: metal.left, right: metal.right)
    }, a: 1, b: 1, hi: 19)

    /// 微波炉：一个矮方盒，正面一块黑玻璃
    static let microwave = make({ cv, o in
        box(&cv, at: o, a: 1, b: 1, hi: 6,
            top: metal.top, left: metal.left, right: metal.right)
        // 那块玻璃门贴在朝镜头的那一面
        box(&cv, at: (o.0 - 0.6, o.1 - 5), a: 0.72, b: 0.05, hi: 4,
            top: "K", left: "K", right: "K")
    }, a: 1, b: 1, hi: 7)

    /// 面包架：两块木隔板 + 上面几个圆滚滚的面包
    static let breadrack = make({ cv, o in
        box(&cv, at: o, a: 1, b: 1, hi: 12,
            top: wood.top, left: wood.left, right: wood.right)
        for z in [4.0, 8.0] {
            box(&cv, at: (o.0, o.1 - z), a: 0.96, b: 0.96, hi: 1,
                top: "y", left: "y", right: "y")
        }
    }, a: 1, b: 1, hi: 13)

    /// 洗衣机：方盒 + 正面一个圆窗（用一小块暗色代圆）
    static let washer = make({ cv, o in
        box(&cv, at: o, a: 1, b: 1, hi: 10,
            top: white.top, left: white.left, right: white.right)
        box(&cv, at: (o.0 - 0.5, o.1 - 7), a: 0.55, b: 0.05, hi: 3.2,
            top: "K", left: "K", right: "K")
    }, a: 1, b: 1, hi: 11)

    /// 马桶：水箱 + 座圈
    static let toilet = make({ cv, o in
        // 座圈在前，水箱在后（`b` 小 = 靠里）
        box(&cv, at: (o.0, o.1 - 0), a: 0.8, b: 0.8, hi: 4,
            top: white.top, left: white.left, right: white.right)
        box(&cv, at: (o.0, o.1 - 4), a: 0.7, b: 0.28, hi: 5,
            top: white.top, left: white.left, right: white.right)
    }, a: 1, b: 1, hi: 10)

    /// 浴缸：一圈缸壁围着一汪水。
    ///
    /// 先画整块缸体，再在顶面上压一块**比缸小一圈**的水——
    /// 露出来的那一圈就是缸沿。等距画里「凹进去」都是这么骗出来的。
    static let bathtub = make({ cv, o in
        box(&cv, at: o, a: 2, b: 1, hi: 5,
            top: white.top, left: white.left, right: white.right)
        box(&cv, at: (o.0, o.1 - 5), a: 1.7, b: 0.75, hi: 0.6,
            top: "b", left: "b", right: "b")
    }, a: 2, b: 1, hi: 7)

    /// 洗手台：柜子 + 台面 + 一汪水 + 后面立一面镜子
    static let sink = make({ cv, o in
        box(&cv, at: o, a: 1, b: 1, hi: 7,
            top: wood.top, left: wood.left, right: wood.right)
        box(&cv, at: (o.0, o.1 - 7), a: 1, b: 1, hi: 1.4,
            top: white.top, left: white.left, right: white.right)
        // 盆里那一小块水
        box(&cv, at: (o.0, o.1 - 8.4), a: 0.55, b: 0.55, hi: 0.5,
            top: "b", left: "b", right: "b")
        // 镜子贴在里侧，立起来
        box(&cv, at: (o.0, o.1 - 8.4), a: 0.85, b: 0.08, hi: 6,
            top: metal.top, left: "b", right: "b")
    }, a: 1, b: 1, hi: 15)

    /// 自动贩卖机：这批里最高的一件。红机身 + 一整面玻璃 + 三排货
    static let vending = make({ cv, o in
        box(&cv, at: o, a: 1, b: 1, hi: 20,
            top: pink.right, left: pink.right, right: pink.right)
        // 玻璃：贴在朝镜头那一面，比机身窄一圈
        box(&cv, at: (o.0 - 0.55, o.1 - 6), a: 0.72, b: 0.05, hi: 12,
            top: "K", left: "K", right: "K")
        // 三排货，一排一个颜色
        let rows: [Character] = ["y", "G", "N"]
        for (i, c) in rows.enumerated() {
            box(&cv, at: (o.0 - 0.55, o.1 - 8.0 - Double(i) * 3.4),
                a: 0.6, b: 0.03, hi: 1.6,
                top: c, left: c, right: c)
        }
    }, a: 1, b: 1, hi: 21)
}

extension FurnitureCatalog {

    /// 这件家具有没有等距版。
    ///
    /// **有就用等距的，没有就还用原来那张正面图。**
    /// 这样这一批可以一件一件换过去，中间任何一天她打开都不会缺东西。
    static func isoSprite(of id: String) -> PixelSprite? {
        switch id {
        case "bed", "bed_berry", "bed_xmas": return IsoArt.bed
        case "table":  return IsoArt.table
        case "stool":  return IsoArt.stool
        case "sofa":   return IsoArt.sofa
        case "shelf":  return IsoArt.shelf
        case "lamp":   return IsoArt.lamp
        case "rug":    return IsoArt.rug
        case "tv":     return IsoArt.tv
        case "fridge":     return IsoArt.fridge
        case "microwave":  return IsoArt.microwave
        case "breadrack":  return IsoArt.breadrack
        case "washer":     return IsoArt.washer
        case "toilet":     return IsoArt.toilet
        case "bathtub":    return IsoArt.bathtub
        case "sink":       return IsoArt.sink
        case "vending":    return IsoArt.vending
        default:       return nil
        }
    }
}

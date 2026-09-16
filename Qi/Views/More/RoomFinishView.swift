import SwiftUI

/// 内置墙面／地面**画出来**的那一半。挑哪一档在 `RoomFinish` 里。
///
/// ⚠️ 全是 `Path` 现画的，**一张素材图都没有**——仓库是公开的，
/// 第三方素材放进去等于再分发。屋里的家具本来就是这么画的，这条路是通的。
///
/// ⚠️ 花纹**不能照着屏幕的横竖画**。等距屋的「水平」是斜的（斜率 ±½），
/// 拿屏幕的水平线画砖缝，砖墙会横穿整间屋，看着像墙上贴了张纸。
/// 所以墙上的每一条线都从 `IsoRoom.leftWallBase` / `rightWallBase`
/// 那条底边算出来——沿着墙自己的方向走。

// MARK: - 墙

struct WallFinishView: View {

    let kind: RoomFinish.Wall
    /// 这面墙的底边（从哪儿到哪儿）和高度
    let base: (CGPoint, CGPoint)
    let height: CGFloat
    /// 底色。右面墙那一档压暗是外面做的，这儿不管
    let tone: Color
    /// 缝／线的颜色
    let seam: Color

    var body: some View {
        ZStack {
            tone
            switch kind {
            case .plain:
                EmptyView()
            case .stripe:
                // 竖条纹。**竖线在等距里还是竖的**，不用跟着斜——
                // 墙是立着的，立着的东西在等距投影里不歪。
                lines(uSteps: 14, vSteps: 0)
                    .stroke(seam, lineWidth: 1)
            case .brick:
                bricks
            case .wainscot:
                wainscot
            case .tile:
                lines(uSteps: 8, vSteps: 5)
                    .stroke(seam, lineWidth: 1)
            case .lace:
                lace
            case .bows:
                bowPrint(cols: 12, rows: 6, v0: 0, v1: 1)
                    .fill(seam.opacity(0.75))
            }
        }
    }

    /// 蕾丝腰线：上面细条纹、下面一块深一档的素板，交界一条腰线 + 一排扇贝花边。
    ///
    /// 照她给的那张参考：墙上半截是粉色细条纹，腰线那儿垂一排白花边。
    /// ⚠️ 扇贝是**沿着墙的方向**一个接一个排的（`at(u, v)` 算），
    /// 拿屏幕横线排的话花边会横穿两面墙。
    private var lace: some View {
        let cut: CGFloat = 0.34
        var panel = Path()
        panel.move(to: at(0, 0)); panel.addLine(to: at(1, 0))
        panel.addLine(to: at(1, cut)); panel.addLine(to: at(0, cut))
        panel.closeSubpath()

        // 上半截的细条纹：一粗一细交替
        var stripes = Path()
        let n = 28
        for i in 0..<n where i % 2 == 0 {
            let u0 = CGFloat(i) / CGFloat(n)
            let u1 = u0 + 0.45 / CGFloat(n)
            stripes.move(to: at(u0, cut)); stripes.addLine(to: at(u1, cut))
            stripes.addLine(to: at(u1, 1)); stripes.addLine(to: at(u0, 1))
            stripes.closeSubpath()
        }

        // 扇贝花边：腰线下面一排半圆（用多边形逼近，跟着墙斜）
        var scallops = Path()
        let k = 24
        let depth: CGFloat = 0.05
        for i in 0..<k {
            let u0 = CGFloat(i) / CGFloat(k)
            let u1 = CGFloat(i + 1) / CGFloat(k)
            scallops.move(to: at(u0, cut))
            for s in 1...6 {
                let t = CGFloat(s) / 6
                let u = u0 + (u1 - u0) * t
                let v = cut - depth * sin(t * .pi)
                scallops.addLine(to: at(u, v))
            }
            scallops.closeSubpath()
        }
        // 花边上的小孔
        var holes = Path()
        for i in 0..<k {
            let c = at((CGFloat(i) + 0.5) / CGFloat(k), cut - depth * 0.45)
            holes.addEllipse(in: CGRect(x: c.x - 0.9, y: c.y - 0.9, width: 1.8, height: 1.8))
        }

        var rail = Path()
        rail.move(to: at(0, cut)); rail.addLine(to: at(1, cut))

        return ZStack {
            stripes.fill(seam.opacity(0.5))
            panel.fill(seam.opacity(0.45))
            scallops.fill(Color.white.opacity(0.78))
            holes.fill(seam.opacity(0.55))
            rail.stroke(Color.white.opacity(0.9), lineWidth: 2.2)
            rail.stroke(seam.opacity(0.6), lineWidth: 0.6)
        }
    }

    /// 墙上一排排的小蝴蝶结，隔一行错半个。
    ///
    /// 蝴蝶结 = 左右两片三角翅膀 + 中间一个结 + 两根短飘带，
    /// 全部在墙自己的 (u, v) 坐标里画，所以跟着墙斜。
    private func bowPrint(cols: Int, rows: Int, v0: CGFloat, v1: CGFloat) -> Path {
        var p = Path()
        let du = 0.30 / CGFloat(cols)          // 翅膀多宽
        let dv = 0.30 / CGFloat(rows)          // 翅膀多高
        for j in 0..<rows {
            let v = v0 + (v1 - v0) * (CGFloat(j) + 0.5) / CGFloat(rows)
            let shift: CGFloat = j % 2 == 0 ? 0.25 : 0.75
            for i in 0..<cols {
                let u = (CGFloat(i) + shift) / CGFloat(cols)
                // 左翅膀
                p.move(to: at(u, v))
                p.addLine(to: at(u - du, v + dv * 0.55))
                p.addLine(to: at(u - du * 0.85, v - dv * 0.5))
                p.closeSubpath()
                // 右翅膀
                p.move(to: at(u, v))
                p.addLine(to: at(u + du, v + dv * 0.55))
                p.addLine(to: at(u + du * 0.85, v - dv * 0.5))
                p.closeSubpath()
                // 飘带
                p.move(to: at(u - du * 0.08, v))
                p.addLine(to: at(u - du * 0.45, v - dv * 0.95))
                p.addLine(to: at(u - du * 0.25, v - dv * 0.95))
                p.closeSubpath()
                p.move(to: at(u + du * 0.08, v))
                p.addLine(to: at(u + du * 0.45, v - dv * 0.95))
                p.addLine(to: at(u + du * 0.25, v - dv * 0.95))
                p.closeSubpath()
                // 结
                let a = at(u - du * 0.18, v + dv * 0.2)
                let b = at(u + du * 0.18, v - dv * 0.2)
                p.addEllipse(in: CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                        width: max(1.6, abs(b.x - a.x)),
                                        height: max(1.6, abs(b.y - a.y))))
            }
        }
        return p
    }

    /// 墙面上的一点。`u` 沿底边走，`v` 往上走，都是 0…1
    private func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        let (a, b) = base
        return CGPoint(x: a.x + (b.x - a.x) * u,
                       y: a.y + (b.y - a.y) * u - height * v)
    }

    /// 一张网：`uSteps` 条竖线 + `vSteps` 条横线（横线是斜的，跟着墙走）
    private func lines(uSteps: Int, vSteps: Int) -> Path {
        var p = Path()
        if uSteps > 0 {
            for i in 1..<max(2, uSteps) {
                let u = CGFloat(i) / CGFloat(uSteps)
                p.move(to: at(u, 0))
                p.addLine(to: at(u, 1))
            }
        }
        if vSteps > 0 {
            for j in 1..<max(2, vSteps) {
                let v = CGFloat(j) / CGFloat(vSteps)
                p.move(to: at(0, v))
                p.addLine(to: at(1, v))
            }
        }
        return p
    }

    /// 砖墙：横缝一层层，竖缝**隔一层错半块**——
    /// 不错开的话那是马赛克，不是砖
    private var bricks: some View {
        let rows = 7
        let cols = 9
        var p = Path()
        for j in 1..<rows {
            let v = CGFloat(j) / CGFloat(rows)
            p.move(to: at(0, v))
            p.addLine(to: at(1, v))
        }
        for j in 0..<rows {
            let v0 = CGFloat(j) / CGFloat(rows)
            let v1 = CGFloat(j + 1) / CGFloat(rows)
            let shift: CGFloat = j % 2 == 0 ? 0 : 0.5
            for i in 0...cols {
                let u = (CGFloat(i) + shift) / CGFloat(cols)
                guard u > 0.001, u < 0.999 else { continue }
                p.move(to: at(u, v0))
                p.addLine(to: at(u, v1))
            }
        }
        return p.stroke(seam, lineWidth: 1)
    }

    /// 木墙裙：下面那截换个色，上面留素的，交界处压一条线。
    /// 下半截再来几道竖槽，才像木板不像色块
    private var wainscot: some View {
        let cut: CGFloat = 0.38
        var panel = Path()
        panel.move(to: at(0, 0))
        panel.addLine(to: at(1, 0))
        panel.addLine(to: at(1, cut))
        panel.addLine(to: at(0, cut))
        panel.closeSubpath()

        var grooves = Path()
        for i in 1..<10 {
            let u = CGFloat(i) / 10
            grooves.move(to: at(u, 0))
            grooves.addLine(to: at(u, cut))
        }
        var edge = Path()
        edge.move(to: at(0, cut))
        edge.addLine(to: at(1, cut))

        return ZStack {
            panel.fill(seam.opacity(0.55))
            grooves.stroke(seam.opacity(0.8), lineWidth: 1)
            edge.stroke(seam, lineWidth: 2)
        }
    }
}

// MARK: - 地

struct FloorFinishView: View {

    let kind: RoomFinish.Floor
    let room: IsoRoom
    let scheme: ColorScheme
    /// 套了主题皮肤的话，用它的配色盖掉花纹自带的那组。
    /// nil = 花纹本来的颜色（也就是原来那五套）。
    var theme: RoomTheme? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            // ⚠️⚠️ **横着有几列要问 `cols`，不是 `size`。**
            //
            // 她报的「平铺视角错误」就是这儿：`size` 是**纵深**（16 排），
            // 平面屋横着是 `cols`（36 列）。按 `size` 铺的话只铺出 16 列，
            // 而地板轮廓、后墙都是按 36 列画的——于是她看到的是
            // **一块靠左的棋盘格 + 右边一大片空**，右边缘还斜着（那是梯形）。
            //
            // 立体屋 `cols == size`，这一行对它没有影响。
            ForEach(0..<(room.across * room.size), id: \.self) { i in
                let gx = i / room.size, gy = i % room.size
                room.tilePath(gx, gy).fill(fill(gx, gy))
            }
            // 缝。**画在所有格子铺完之后**，不然后画的格子会盖住前一格的缝
            if kind != .checker {
                seams.stroke(seamColor, lineWidth: kind == .tile ? 1.2 : 0.8)
            }
            if kind == .terrazzo { speckles }
            if kind == .bows { floorBows }
        }
    }

    /// 地上每格一个蝴蝶结（深浅两格里只印浅的那格，看着不挤）。
    ///
    /// ⚠️ 蝴蝶结**躺在地上**：用这一格自己的两条边当坐标轴（`ex` / `ey`），
    /// 所以在斜着看的屋里它也是扁的、斜的，跟地板贴在一起。
    /// 照着屏幕横平竖直画的话，它会像浮在地板上面的贴纸。
    private var floorBows: some View {
        Canvas { ctx, _ in
            let ink = tone(2)
            for gx in 0..<room.across {
                for gy in 0..<room.size where (gx + gy) % 2 == 0 {
                    let c = room.point(Double(gx), Double(gy))
                    let r = room.point(Double(gx) + 1, Double(gy))
                    let d = room.point(Double(gx), Double(gy) + 1)
                    let ex = CGPoint(x: r.x - c.x, y: r.y - c.y)
                    let ey = CGPoint(x: d.x - c.x, y: d.y - c.y)
                    // 这一格里的一个点：x 沿 gx 方向、y 沿 gy 方向，单位是格
                    func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                        CGPoint(x: c.x + ex.x * x + ey.x * y, y: c.y + ex.y * x + ey.y * y)
                    }
                    // 蝴蝶结朝向屏幕横着摆：左翅沿 (-x,+y)，右翅沿 (+x,-y)
                    let s: CGFloat = 0.21
                    var p = Path()
                    p.move(to: q(0, 0)); p.addLine(to: q(-s, s * 0.4)); p.addLine(to: q(-s * 0.4, s)); p.closeSubpath()
                    p.move(to: q(0, 0)); p.addLine(to: q(s, -s * 0.4)); p.addLine(to: q(s * 0.4, -s)); p.closeSubpath()
                    // 飘带往观察者那边垂
                    p.move(to: q(0, 0)); p.addLine(to: q(s * 0.15, s * 0.95)); p.addLine(to: q(s * 0.35, s * 0.75)); p.closeSubpath()
                    p.move(to: q(0, 0)); p.addLine(to: q(s * 0.95, s * 0.15)); p.addLine(to: q(s * 0.75, s * 0.35)); p.closeSubpath()
                    ctx.fill(p, with: .color(ink.opacity(0.85)))
                    let k = q(0, 0)
                    ctx.fill(Path(ellipseIn: CGRect(x: k.x - 1.3, y: k.y - 1, width: 2.6, height: 2)),
                             with: .color(ink))
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: 每一格什么颜色

    private func fill(_ gx: Int, _ gy: Int) -> Color {
        switch kind {
        case .checker:
            return (gx + gy) % 2 == 0 ? tone(0) : tone(1)
        case .wood:
            // 板子顺着 gy 那条方向铺，所以**按 gx 换色**——
            // 按 gy 换的话板子是横着的，跟缝对不上
            return tone(gx % 3)
        case .tatami:
            // 两格一张席，隔一张换个朝向（用深浅冒充朝向，够看）
            return (gx + gy / 2) % 2 == 0 ? tone(0) : tone(1)
        case .tile:
            return tone(0)
        case .terrazzo:
            return tone(0)
        case .bows:
            return (gx + gy) % 2 == 0 ? tone(0) : tone(1)
        }
    }

    /// 缝画在哪儿
    private var seams: Path {
        var p = Path()
        // ⚠️ **两个维度不是同一个数。**
        //
        // `n` 是纵深（16 排），`w` 是横着几列——立体屋两者相同，
        // 平面屋横着是 36 列。混用的话平面屋的缝只画到第 16 列就断了，
        // 右边一大片地板光秃秃的。
        let n = room.size
        let w = room.across
        switch kind {
        case .checker:
            break
        case .wood:
            // 板子之间那道缝：只画 gx 方向的分界
            for gx in 1..<w {
                p.move(to: room.point(Double(gx), -0.5))
                p.addLine(to: room.point(Double(gx), Double(n) - 0.5))
            }
            // 板子的接头：每条板隔几格断一下，相邻两条错开——
            // 一条缝通到底的是条纹布，不是地板
            for gx in 0...w {
                let shift = (gx * 5) % 4
                for gy in stride(from: shift, to: n, by: 4) where gy > 0 {
                    p.move(to: room.point(max(-0.5, Double(gx) - 1), Double(gy) - 0.5))
                    p.addLine(to: room.point(min(Double(w) - 0.5, Double(gx)), Double(gy) - 0.5))
                }
            }
        case .tatami:
            // 每张席一圈边
            for gx in 0...w {
                p.move(to: room.point(Double(gx) - 0.5, -0.5))
                p.addLine(to: room.point(Double(gx) - 0.5, Double(n) - 0.5))
            }
            for gy in stride(from: 0, through: n, by: 2) {
                p.move(to: room.point(-0.5, Double(gy) - 0.5))
                p.addLine(to: room.point(Double(w) - 0.5, Double(gy) - 0.5))
            }
        case .tile, .terrazzo, .bows:
            for gx in 0...w {
                p.move(to: room.point(Double(gx) - 0.5, -0.5))
                p.addLine(to: room.point(Double(gx) - 0.5, Double(n) - 0.5))
            }
            for gy in 0...n {
                p.move(to: room.point(-0.5, Double(gy) - 0.5))
                p.addLine(to: room.point(Double(w) - 0.5, Double(gy) - 0.5))
            }
        }
        return p
    }

    /// 水磨石那些点子。
    ///
    /// ⚠️ **不能用 `random()`**：body 每一帧都会重跑，
    /// 点子会每帧换个地方，整块地板在那儿沸腾。
    /// 拿格子坐标算一个定死的伪随机，位置就永远不变。
    private var speckles: some View {
        Canvas { ctx, _ in
            for gx in 0..<room.across {
                for gy in 0..<room.size {
                    let c = room.point(Double(gx), Double(gy))
                    var seed = UInt64(gx &* 73856093 ^ gy &* 19349663) | 1
                    for _ in 0..<5 {
                        seed = seed &* 6364136223846793005 &+ 1442695040888963407
                        let rx = Double((seed >> 33) % 1000) / 1000 - 0.5
                        seed = seed &* 6364136223846793005 &+ 1442695040888963407
                        let ry = Double((seed >> 33) % 1000) / 1000 - 0.5
                        // 菱形里面：|x|/w + |y|/h <= 0.5 才算在格子里
                        guard abs(rx) + abs(ry) < 0.42 else { continue }
                        let p = CGPoint(x: c.x + rx * room.tileW,
                                        y: c.y + ry * room.tileH)
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.1, y: p.y - 0.8,
                                                        width: 2.2, height: 1.6)),
                                 with: .color(seamColor.opacity(0.75)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: 配色

    private func tone(_ i: Int) -> Color {
        let hexes: [String]
        switch kind {
        case .checker:
            hexes = scheme == .dark ? ["3B322A", "352D26"] : ["D7C6A9", "CFBD9E"]
        case .wood:
            hexes = scheme == .dark
                ? ["4A3A2B", "433426", "513F2E"]
                : ["C9A57A", "BE9A70", "D2AE84"]
        case .tatami:
            hexes = scheme == .dark ? ["3D4433", "373D2E"] : ["CFCB9B", "C5C191"]
        case .tile:
            hexes = scheme == .dark ? ["3A3A3E"] : ["E4E2DC"]
        case .terrazzo:
            hexes = scheme == .dark ? ["36353A"] : ["EAE7E0"]
        case .bows:
            hexes = scheme == .dark ? ["3E3630", "39322C", "6E5F86"] : ["F8ECD8", "F2E3CB", "B49AD8"]
        }
        // ⚠️ 主题的配色**盖在最外面**，花纹的层数照旧：
        // 木地板还是三档、榻榻米还是两档，只是颜色换了一组。
        // 主题给的档数不够就用它最后一档顶上——
        // 少给一档就整片塌成一个色，那不是"配色不同"，那是花纹没了。
        let pal = theme?.floorColors(scheme) ?? []
        let use = pal.isEmpty ? hexes : pal
        let h = use[min(i, use.count - 1)]
        return Color(hexString: h) ?? .gray
    }

    private var seamColor: Color {
        switch kind {
        case .checker: return .clear
        case .wood: return Color.black.opacity(scheme == .dark ? 0.35 : 0.18)
        case .tatami: return Color(hexString: scheme == .dark ? "2B3124" : "9A9668") ?? .gray
        case .tile: return Color.black.opacity(scheme == .dark ? 0.35 : 0.14)
        case .terrazzo: return Color.black.opacity(scheme == .dark ? 0.45 : 0.30)
        // 细细的格线，淡紫，跟蝴蝶结一个色系
        case .bows: return tone(2).opacity(0.28)
        }
    }
}

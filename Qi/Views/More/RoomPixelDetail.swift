import SwiftUI

/// 墙和地板上**跟家具同一套像素画法**的那层细节：
/// 踢脚线、墙顶线、墙角和墙根的阴影、窗户、窗户投在地上的光、地面颗粒。
///
/// 家具换成像素图之后，光秃秃的纯色墙和平涂地板跟它们对不上——
/// 家具有描边、有明暗台阶、有颗粒，屋子什么都没有，家具像贴上去的。
///
/// ⚠️ 全画在 `Canvas` 里，坐标都**吸附到像素格**（`px`），边是硬的、
/// 阴影是一档一档的，不用渐变——渐变是矢量图的样子。
/// ⚠️ 随机点子拿坐标算伪随机，**不用 `random()`**：body 每次重跑点子不能跳。

/// 墙上开窗的位置
struct RoomWindow: Equatable {
    enum Wall { case left, right, back }
    let wall: Wall
    /// 沿墙走的格坐标（窗户左右两条边）
    let u0: Double
    let u1: Double
}

enum RoomPixel {

    /// 一个像素点多大（点）。跟着格子大小走，手机上大约 1 点
    static func px(_ g: IsoRoom) -> CGFloat {
        max(1, (g.tileW / 22).rounded())
    }

    /// 墙面上一点：`u` 沿墙的格坐标，`v` 离地多高（点）
    static func wallPoint(_ g: IsoRoom, _ wall: RoomWindow.Wall, _ u: Double, _ v: CGFloat) -> CGPoint {
        let base: CGPoint
        switch wall {
        case .left: base = g.point(-0.5, u)
        case .right, .back: base = g.point(u, -0.5)
        }
        return CGPoint(x: base.x, y: base.y - v)
    }

    static func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
        var p = Path()
        p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.addLine(to: d)
        p.closeSubpath()
        return p
    }

    /// 墙上一段：u0…u1、v0…v1 围出来的那块
    static func wallBand(_ g: IsoRoom, _ wall: RoomWindow.Wall,
                         _ u0: Double, _ u1: Double, _ v0: CGFloat, _ v1: CGFloat) -> Path {
        quad(wallPoint(g, wall, u0, v0), wallPoint(g, wall, u1, v0),
             wallPoint(g, wall, u1, v1), wallPoint(g, wall, u0, v1))
    }

    /// 定死的伪随机，0…1
    static func hash(_ a: Int, _ b: Int, _ salt: Int) -> Double {
        var s = UInt64(bitPattern: Int64(a &* 73856093 ^ b &* 19349663 ^ salt &* 83492791)) | 1
        s = s &* 6364136223846793005 &+ 1442695040888963407
        s ^= s >> 29
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double((s >> 33) % 10000) / 10000
    }

    static func color(_ hex: String) -> Color { Color(hexString: hex) ?? .gray }

    /// 这间屋的墙边长（格）
    static func span(_ g: IsoRoom, _ wall: RoomWindow.Wall) -> Double {
        switch wall {
        case .left: return Double(g.size)
        case .right: return Double(g.size)
        case .back: return Double(g.cols)
        }
    }

    static func walls(_ g: IsoRoom) -> [RoomWindow.Wall] {
        g.projection == .flat ? [.back] : [.left, .right]
    }
}

// MARK: - 墙

struct RoomWallDetail: View {

    let room: IsoRoom
    let window: RoomWindow?
    /// 0 白天 … 1 深夜
    let night: Double
    /// 内置墙面才撒颗粒；她自己的图不往上加东西
    let grain: Bool

    var body: some View {
        Canvas { ctx, _ in
            let g = room
            let px = RoomPixel.px(g)
            for wall in RoomPixel.walls(g) {
                let n = RoomPixel.span(g, wall)
                let lo = -0.5, hi = n - 0.5
                if grain { sprinkle(&ctx, wall, lo, hi, px) }

                // 墙角：两面墙相交那条竖线附近一档一档暗下去（等距屋才有）
                if wall != .back {
                    let steps: [(Double, Double)] = [(0.10, 0.10), (0.24, 0.06), (0.42, 0.03)]
                    var from = lo
                    for (w, a) in steps {
                        ctx.fill(RoomPixel.wallBand(g, wall, from, lo + w, 0, g.wallH),
                                 with: .color(.black.opacity(a)))
                        from = lo + w
                    }
                }

                // 墙顶：一条暗线 + 下面一格亮线（像素画里的「收边」）
                ctx.fill(RoomPixel.wallBand(g, wall, lo, hi, g.wallH - px * 2, g.wallH),
                         with: .color(.black.opacity(0.12)))
                ctx.fill(RoomPixel.wallBand(g, wall, lo, hi, g.wallH - px * 3, g.wallH - px * 2),
                         with: .color(.white.opacity(0.10)))

                // 踢脚线：主体压暗、顶上一格亮边、底下一格深线，上面再一格淡阴影
                let bh = max(px * 4, (g.wallH * 0.055 / px).rounded() * px)
                ctx.fill(RoomPixel.wallBand(g, wall, lo, hi, bh, bh + px),
                         with: .color(.black.opacity(0.06)))
                ctx.fill(RoomPixel.wallBand(g, wall, lo, hi, 0, bh),
                         with: .color(.black.opacity(0.13)))
                ctx.fill(RoomPixel.wallBand(g, wall, lo, hi, bh - px, bh),
                         with: .color(.white.opacity(0.28)))
                ctx.fill(RoomPixel.wallBand(g, wall, lo, hi, 0, px),
                         with: .color(.black.opacity(0.14)))
            }
            if let window { drawWindow(&ctx, window, px) }
        }
        .allowsHitTesting(false)
    }

    /// 墙面颗粒：一小颗一小颗亮点暗点，像素墙纸的质感
    private func sprinkle(_ ctx: inout GraphicsContext, _ wall: RoomWindow.Wall,
                          _ lo: Double, _ hi: Double, _ px: CGFloat) {
        let g = room
        let du = Double(px * 3) / Double(g.tileW / (g.projection == .flat ? 1 : 2))
        let rows = Int(g.wallH / (px * 3))
        var i = 0
        var u = lo
        while u < hi {
            for j in 0..<rows {
                let r = RoomPixel.hash(i, j, wall == .right ? 7 : 3)
                guard r < 0.10 else { continue }
                let p = RoomPixel.wallPoint(g, wall, u, CGFloat(j) * px * 3 + px * 2)
                let x = (p.x / px).rounded(.down) * px
                let y = (p.y / px).rounded(.down) * px
                let light = RoomPixel.hash(j, i, 11) < 0.45
                ctx.fill(Path(CGRect(x: x, y: y, width: px, height: px)),
                         with: .color(light ? .white.opacity(0.16) : .black.opacity(0.07)))
            }
            u += du
            i += 1
        }
    }

    private func drawWindow(_ ctx: inout GraphicsContext, _ w: RoomWindow, _ px: CGFloat) {
        let g = room
        let wall = w.wall
        let v0 = (g.wallH * 0.32 / px).rounded() * px
        let v1 = (g.wallH * 0.80 / px).rounded() * px
        // 沿墙一个点对应多少格
        let perPt = 1 / Double(g.projection == .flat ? g.tileW : g.tileW / 2)
        let f = Double(px * 3) * perPt           // 窗框宽
        let band = RoomPixel.wallBand

        // 投在墙上的影子（右下各错一格）
        ctx.fill(band(g, wall, w.u0 - f + Double(px) * perPt, w.u1 + f + Double(px) * perPt,
                      v0 - px * 3 - px, v1 + px * 3 - px),
                 with: .color(.black.opacity(0.10)))
        // 窗框
        ctx.fill(band(g, wall, w.u0 - f, w.u1 + f, v0 - px * 3, v1 + px * 3),
                 with: .color(RoomPixel.color("F6F0E6")))
        ctx.fill(band(g, wall, w.u0 - f, w.u1 + f, v0 - px * 3, v0 - px * 2),
                 with: .color(RoomPixel.color("CDBFAE")))
        ctx.fill(band(g, wall, w.u1 + f - Double(px) * perPt, w.u1 + f, v0 - px * 3, v1 + px * 3),
                 with: .color(RoomPixel.color("DDD1C1")))

        // 玻璃里的天：三档色带，不用渐变
        let sky: [String]
        if night >= 0.6 {
            sky = ["1E2748", "283463", "34437A"]
        } else if night > 0.05 {
            sky = ["8FA8DC", "E9B9A6", "F6D6B0"]
        } else {
            sky = ["96CDEB", "B4DDF1", "D3ECF6"]
        }
        let h = v1 - v0
        let cuts: [CGFloat] = [0, (h * 0.38 / px).rounded() * px, (h * 0.70 / px).rounded() * px, h]
        for k in 0..<3 {
            // 天从上往下：顶上最深
            ctx.fill(band(g, wall, w.u0, w.u1, v1 - cuts[k + 1], v1 - cuts[k]),
                     with: .color(RoomPixel.color(sky[k])))
        }
        if night >= 0.6 {
            // 星星和月亮
            for s in 0..<5 {
                let su = w.u0 + (w.u1 - w.u0) * (0.12 + 0.76 * RoomPixel.hash(s, 5, 21))
                let sv = v1 - h * CGFloat(0.12 + 0.5 * RoomPixel.hash(s, 9, 23))
                let p = RoomPixel.wallPoint(g, wall, su, sv)
                ctx.fill(Path(CGRect(x: (p.x / px).rounded() * px, y: (p.y / px).rounded() * px,
                                     width: px, height: px)),
                         with: .color(RoomPixel.color("FFF6D8")))
            }
            let mu = w.u0 + (w.u1 - w.u0) * 0.72
            let mc = RoomPixel.wallPoint(g, wall, mu, v1 - h * 0.28)
            let r = max(px * 2, (h * 0.09 / px).rounded() * px)
            ctx.fill(Path(ellipseIn: CGRect(x: mc.x - r, y: mc.y - r, width: r * 2, height: r * 2)),
                     with: .color(RoomPixel.color("FFF1C4")))
            ctx.fill(Path(ellipseIn: CGRect(x: mc.x - r * 0.35, y: mc.y - r * 1.05,
                                            width: r * 2, height: r * 2)),
                     with: .color(RoomPixel.color(sky[1])))
        } else {
            // 白天：一朵像素云
            let cu = w.u0 + (w.u1 - w.u0) * 0.3
            let cv = v1 - h * 0.3
            for (du, dv, ww, hh) in [(0.0, 0.0, 6.0, 2.0), (1.0, 2.0, 3.0, 1.0), (2.0, -1.0, 5.0, 1.0)] {
                let a = RoomPixel.wallPoint(g, wall, cu + du * Double(px) * perPt, cv + CGFloat(dv) * px)
                ctx.fill(Path(CGRect(x: (a.x / px).rounded() * px, y: (a.y / px).rounded() * px,
                                     width: CGFloat(ww) * px, height: CGFloat(hh) * px)),
                         with: .color(.white.opacity(night > 0.05 ? 0.55 : 0.9)))
            }
            // 玻璃反光：两道斜的亮点串
            for line in 0..<2 {
                let start = w.u0 + (w.u1 - w.u0) * (line == 0 ? 0.55 : 0.68)
                for k in 0..<(line == 0 ? 5 : 3) {
                    let p = RoomPixel.wallPoint(g, wall, start + Double(k) * Double(px) * perPt,
                                                v0 + px * CGFloat(3 + k))
                    ctx.fill(Path(CGRect(x: (p.x / px).rounded() * px, y: (p.y / px).rounded() * px,
                                         width: px, height: px)),
                             with: .color(.white.opacity(0.6)))
                }
            }
        }
        // 窗棂：一横一竖
        let mid = (w.u0 + w.u1) / 2
        let half = Double(px) * perPt
        ctx.fill(band(g, wall, mid - half, mid + half, v0, v1),
                 with: .color(RoomPixel.color("F6F0E6")))
        let vm = ((v0 + v1) / 2 / px).rounded() * px
        ctx.fill(band(g, wall, w.u0, w.u1, vm - px, vm + px),
                 with: .color(RoomPixel.color("F6F0E6")))
        // 玻璃上沿一格阴影（窗框的厚度）
        ctx.fill(band(g, wall, w.u0, w.u1, v1 - px, v1),
                 with: .color(.black.opacity(0.18)))

        // 窗台：比窗框宽一点，带一个朝屋里的顶面
        let s0 = w.u0 - f * 1.8, s1 = w.u1 + f * 1.8
        let lip = v0 - px * 3
        ctx.fill(band(g, wall, s0, s1, lip - px * 2, lip),
                 with: .color(RoomPixel.color("E2D6C6")))
        ctx.fill(band(g, wall, s0, s1, lip - px * 3, lip - px * 2),
                 with: .color(RoomPixel.color("B9AA97")))
        if wall != .back {
            let depth = 0.22
            func out(_ u: Double) -> CGPoint {
                let p = wall == .left ? g.point(-0.5 + depth, u) : g.point(u, -0.5 + depth)
                return CGPoint(x: p.x, y: p.y - lip)
            }
            ctx.fill(RoomPixel.quad(RoomPixel.wallPoint(g, wall, s0, lip),
                                    RoomPixel.wallPoint(g, wall, s1, lip),
                                    out(s1), out(s0)),
                     with: .color(RoomPixel.color("FBF6EE")))
        }
    }
}

// MARK: - 地

struct RoomFloorDetail: View {

    let room: IsoRoom
    let window: RoomWindow?
    let night: Double
    let grain: Bool

    var body: some View {
        Canvas { ctx, _ in
            let g = room
            let px = RoomPixel.px(g)
            if grain { sprinkle(&ctx, px) }

            // 窗户投在地上的光：四块（中间窗棂那道十字是暗的）
            if let w = window, night < 0.9 {
                let a = 0.18 * (1 - night)
                let warm = RoomPixel.color(night > 0.05 ? "FFD9B0" : "FFF4DA")
                for (s0, s1) in [(0.0, 0.46), (0.54, 1.0)] {
                    for (t0, t1) in [(0.0, 0.45), (0.55, 1.0)] {
                        ctx.fill(RoomPixel.quad(light(w, s0, t0), light(w, s1, t0),
                                                light(w, s1, t1), light(w, s0, t1)),
                                 with: .color(warm.opacity(a)))
                    }
                }
            }

            // 墙根：地板贴墙那一溜一档一档暗下去
            let n = Double(g.size)
            let across = Double(g.across)
            let steps: [(Double, Double)] = [(0.08, 0.13), (0.18, 0.07), (0.30, 0.03)]
            if g.projection == .flat {
                var from = -0.5
                for (w, a) in steps {
                    ctx.fill(RoomPixel.quad(g.point(-0.5, from), g.point(across - 0.5, from),
                                            g.point(across - 0.5, -0.5 + w), g.point(-0.5, -0.5 + w)),
                             with: .color(.black.opacity(a)))
                    from = -0.5 + w
                }
            } else {
                var from = -0.5
                for (w, a) in steps {
                    // 左墙根（gx = -0.5 那条边）
                    ctx.fill(RoomPixel.quad(g.point(from, -0.5), g.point(from, n - 0.5),
                                            g.point(-0.5 + w, n - 0.5), g.point(-0.5 + w, -0.5)),
                             with: .color(.black.opacity(a)))
                    // 右墙根（gy = -0.5 那条边）
                    ctx.fill(RoomPixel.quad(g.point(-0.5, from), g.point(n - 0.5, from),
                                            g.point(n - 0.5, -0.5 + w), g.point(-0.5, -0.5 + w)),
                             with: .color(.black.opacity(a)))
                    from = -0.5 + w
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// 窗户光斑里的一点。`s` 沿窗户宽，`t` 从墙根往屋里
    private func light(_ w: RoomWindow, _ s: Double, _ t: Double) -> CGPoint {
        let g = room
        let u = w.u0 + (w.u1 - w.u0) * s
        switch w.wall {
        case .left:  return g.point(-0.35 + t * 2.6, u + 0.7 + t * 1.4)
        case .right: return g.point(u + 0.7 + t * 1.4, -0.35 + t * 2.6)
        case .back:  return g.point(u + t * 1.2, -0.4 + t * 3.2)
        }
    }

    /// 每格几颗亮点暗点
    private func sprinkle(_ ctx: inout GraphicsContext, _ px: CGFloat) {
        let g = room
        let flat = g.projection == .flat
        for gx in 0..<g.across {
            for gy in 0..<g.size {
                let c = g.point(Double(gx), Double(gy))
                for k in 0..<3 {
                    let rx = RoomPixel.hash(gx, gy, 31 + k) - 0.5
                    let ry = RoomPixel.hash(gy, gx, 57 + k) - 0.5
                    if !flat && abs(rx) + abs(ry) > 0.42 { continue }
                    let p = CGPoint(x: c.x + CGFloat(rx) * g.tileW * (flat ? 0.9 : 1),
                                    y: c.y + CGFloat(ry) * (flat ? g.rowPitch * 0.9 : g.tileH))
                    let light = RoomPixel.hash(gx + k, gy, 77) < 0.5
                    ctx.fill(Path(CGRect(x: (p.x / px).rounded(.down) * px,
                                         y: (p.y / px).rounded(.down) * px,
                                         width: px, height: px)),
                             with: .color(light ? .white.opacity(0.13) : .black.opacity(0.07)))
                }
            }
        }
    }
}

// MARK: - 晚上

/// 整间屋压暗 + 会发光的家具点一圈暖光
struct RoomNightShade: View {

    struct Glow: Hashable {
        let center: CGPoint
        let radius: CGFloat
        let hex: String
    }

    let night: Double
    let glows: [Glow]

    var body: some View {
        if night > 0.01 {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(RoomPixel.color("2A2F55").opacity(0.55 * night))
                    .blendMode(.multiply)
                Canvas { ctx, _ in
                    for gl in glows {
                        // 一圈一圈的台阶光，不用平滑渐变
                        let base = RoomPixel.color(gl.hex)
                        for (scale, a) in [(1.0, 0.07), (0.72, 0.09), (0.46, 0.12), (0.24, 0.16)] {
                            let r = gl.radius * CGFloat(scale)
                            ctx.fill(Path(ellipseIn: CGRect(x: gl.center.x - r, y: gl.center.y - r * 0.8,
                                                            width: r * 2, height: r * 1.6)),
                                     with: .color(base.opacity(a * night)))
                        }
                    }
                }
                .blendMode(.plusLighter)
            }
            .allowsHitTesting(false)
        }
    }
}

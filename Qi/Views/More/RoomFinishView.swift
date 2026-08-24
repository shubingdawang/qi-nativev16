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
            }
        }
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<(room.size * room.size), id: \.self) { i in
                let gx = i / room.size, gy = i % room.size
                room.tilePath(gx, gy).fill(fill(gx, gy))
            }
            // 缝。**画在所有格子铺完之后**，不然后画的格子会盖住前一格的缝
            if kind != .checker {
                seams.stroke(seamColor, lineWidth: kind == .tile ? 1.2 : 0.8)
            }
            if kind == .terrazzo { speckles }
        }
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
        }
    }

    /// 缝画在哪儿
    private var seams: Path {
        var p = Path()
        let n = room.size
        switch kind {
        case .checker:
            break
        case .wood:
            // 板子之间那道缝：只画 gx 方向的分界
            for gx in 1..<n {
                p.move(to: room.point(Double(gx), -0.5))
                p.addLine(to: room.point(Double(gx), Double(n) - 0.5))
            }
        case .tatami:
            // 每张席一圈边
            for gx in 0...n {
                p.move(to: room.point(Double(gx) - 0.5, -0.5))
                p.addLine(to: room.point(Double(gx) - 0.5, Double(n) - 0.5))
            }
            for gy in stride(from: 0, through: n, by: 2) {
                p.move(to: room.point(-0.5, Double(gy) - 0.5))
                p.addLine(to: room.point(Double(n) - 0.5, Double(gy) - 0.5))
            }
        case .tile, .terrazzo:
            for gx in 0...n {
                p.move(to: room.point(Double(gx) - 0.5, -0.5))
                p.addLine(to: room.point(Double(gx) - 0.5, Double(n) - 0.5))
            }
            for gy in 0...n {
                p.move(to: room.point(-0.5, Double(gy) - 0.5))
                p.addLine(to: room.point(Double(n) - 0.5, Double(gy) - 0.5))
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
            for gx in 0..<room.size {
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
        }
        let h = hexes[min(i, hexes.count - 1)]
        return Color(hexString: h) ?? .gray
    }

    private var seamColor: Color {
        switch kind {
        case .checker: return .clear
        case .wood: return Color.black.opacity(scheme == .dark ? 0.35 : 0.18)
        case .tatami: return Color(hexString: scheme == .dark ? "2B3124" : "9A9668") ?? .gray
        case .tile: return Color.black.opacity(scheme == .dark ? 0.35 : 0.14)
        case .terrazzo: return Color.black.opacity(scheme == .dark ? 0.45 : 0.30)
        }
    }
}

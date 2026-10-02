import SwiftUI

/// 开屏：毛玻璃上的一扇彩绘玻璃拱窗。
///
/// 她定的：外面不要纸底，做成**毛玻璃**——底下的聊天页透上来，但一切都是糊的；
/// 窗里不放壁纸（壁纸上的水珠显得突兀），换成一扇彩绘玻璃；窗框要华丽：
/// 打磨过的金边、一圈宝石、藤叶、立柱、卷草、冠饰、窗台下的垂饰。
///
/// 动的东西都讲物理、讲因果（motion-web 那份主张）：
///   · 手指点、划过窗里，彩色玻璃像水面一样起涟漪（`SplashRipple.metal` 的 `qiStained`）
///   · 窗上搭着一串珍珠，是一根真的绳子（Verlet）：进来时从拉直的样子垂下去晃两下；
///     手指拨它会荡，坠子跟着甩
///   · 有一团光从窗上面透进来，慢慢左右移；字一个个浮上来；几颗金色小星一闪一闪
///   · 轻点任何地方：那一点向外让开，露出 App
///
/// 只在冷启动出现一次；设置里能关（`AppSettings.splashOn`）。
struct SplashView: View {

    var onEnter: () -> Void

    @State private var ripples = RippleSet()
    @State private var rope = PearlRope()
    @State private var leaving = false
    @State private var revealR: CGFloat = 0
    @State private var revealAt: CGPoint = .zero
    @State private var lastRipple: CGPoint?
    @State private var dragStart: Date?
    @State private var risen = false
    @State private var stamp = SplashView.stamp(Date())

    // 色板
    //
    // ⚠️ 两套：浅色模式是白天（金框、暖色玻璃），深色模式是同一扇窗到了夜里
    // （珍珠银框、月光色玻璃、窗外飘星屑）。她定的：「深色就要月夜那个」。
    // 开屏只出现一次，所以用一个静态开关切，省得把色板一层层往下传。
    nonisolated(unsafe) static var night = false
    static var gold: Color { night ? Color(red: 0.812, green: 0.820, blue: 0.863) : Color(red: 0.722, green: 0.573, blue: 0.310) }
    static var goldDeep: Color { night ? Color(red: 0.271, green: 0.282, blue: 0.345) : Color(red: 0.431, green: 0.314, blue: 0.114) }
    static var wine: Color { night ? Color(red: 0.839, green: 0.776, blue: 0.949) : Color(red: 0.478, green: 0.133, blue: 0.212) }
    static var rose: Color { night ? Color(red: 0.910, green: 0.737, blue: 0.804) : Color(red: 0.612, green: 0.365, blue: 0.416) }
    static var ink: Color { night ? Color(red: 0.933, green: 0.925, blue: 0.965) : Color(red: 0.227, green: 0.176, blue: 0.169) }
    static var veil: Color { night ? Color(red: 0.086, green: 0.094, blue: 0.141) : Color(red: 0.988, green: 0.973, blue: 0.945) }
    /// 珍珠串下面那颗坠子
    static var drop: Color { night ? Color(red: 0.663, green: 0.722, blue: 0.918) : Color(red: 0.478, green: 0.133, blue: 0.212) }

    @Environment(\.colorScheme) private var systemScheme
    @State private var sparks = SparkField()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let win = Self.windowRect(in: size)
            let _ = { Self.night = systemScheme == .dark }()
            ZStack {
                // 毛玻璃：底下的 App 透上来，全是糊的
                Rectangle().fill(.ultraThinMaterial)
                Self.veil.opacity(Self.night ? 0.62 : 0.42)

                // 静的金线：窗框、立柱、卷草、边框（只画一次）
                Canvas { gc, sz in drawFrame(gc, win: win, size: sz) }
                    .allowsHitTesting(false)

                TimelineView(.animation) { tl in
                    let now = tl.date
                    ZStack {
                        glass(win: win, now: now)
                        Canvas { gc, sz in
                            drawTracery(gc, win: win)
                            drawSparkles(gc, size: sz, now: now)
                            rope.step(now, win: win)
                            rope.draw(gc)
                            // 手指划过落一串星屑；夜里窗外还一直飘着细星屑
                            sparks.step(now, size: sz, finger: rope.finger, night: Self.night)
                            sparks.draw(gc)
                        }
                        .allowsHitTesting(false)
                    }
                }

                words(size: size, win: win, safeBottom: geo.safeAreaInsets.bottom)
            }
            .environment(\.colorScheme, Self.night ? .dark : .light)
            .mask { revealMask }
            .contentShape(Rectangle())
            .gesture(touch(size: size, win: win))
        }
        .ignoresSafeArea()
        .onAppear { withAnimation { risen = true } }
    }

    // MARK: 拱窗

    static func windowRect(in size: CGSize) -> CGRect {
        let w = min(size.width * 0.54, 240)
        let h = w * 1.42
        return CGRect(x: (size.width - w) / 2, y: size.height * 0.23, width: w, height: h)
    }

    /// 窗里：一扇彩绘玻璃，会起涟漪，有一团光从上面透进来慢慢移
    private func glass(win: CGRect, now: Date) -> some View {
        let t = Float(now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
        return Rectangle()
            .fill(.white)
            .frame(width: win.width, height: win.height)
            .colorEffect(ShaderLibrary.qiStained(.floatArray(ripples.args(now: now)),
                                                 .float2(win.size), .float(t),
                                                 .float(Self.night ? 1 : 0)))
            .clipShape(ArchShape())
            .scaleEffect(risen ? 1 : 0.94, anchor: .bottom)
            .animation(.spring(response: 1.2, dampingFraction: 0.7), value: risen)
            .position(x: win.midX, y: win.midY)
    }

    /// 打磨过的金：亮暗相间的一道斜渐变
    static func metal(_ a: CGPoint, _ b: CGPoint) -> GraphicsContext.Shading {
        if night {
            return .linearGradient(Gradient(stops: [
                .init(color: Color(red: 0.333, green: 0.345, blue: 0.416), location: 0),
                .init(color: Color(red: 0.902, green: 0.910, blue: 0.949), location: 0.18),
                .init(color: Color(red: 0.553, green: 0.565, blue: 0.643), location: 0.36),
                .init(color: Color(red: 0.984, green: 0.984, blue: 1.0), location: 0.55),
                .init(color: Color(red: 0.478, green: 0.494, blue: 0.573), location: 0.74),
                .init(color: Color(red: 0.863, green: 0.867, blue: 0.914), location: 0.9),
                .init(color: Color(red: 0.278, green: 0.290, blue: 0.353), location: 1)]),
                startPoint: a, endPoint: b)
        }
        return .linearGradient(Gradient(stops: [
            .init(color: Color(red: 0.478, green: 0.353, blue: 0.133), location: 0),
            .init(color: Color(red: 0.914, green: 0.812, blue: 0.529), location: 0.18),
            .init(color: Color(red: 0.639, green: 0.482, blue: 0.208), location: 0.36),
            .init(color: Color(red: 0.969, green: 0.902, blue: 0.682), location: 0.55),
            .init(color: Color(red: 0.549, green: 0.416, blue: 0.173), location: 0.74),
            .init(color: Color(red: 0.890, green: 0.769, blue: 0.486), location: 0.9),
            .init(color: Color(red: 0.431, green: 0.314, blue: 0.114), location: 1)]),
            startPoint: a, endPoint: b)
    }

    /// 金线、立柱、卷草、宝石……都是静的
    private func drawFrame(_ gc: GraphicsContext, win: CGRect, size: CGSize) {
        let gold = Self.gold
        // 整页边框：两道金线，四角卷草
        let borders: [(CGFloat, CGFloat, Double)] = [(14, 0.7, 0.6), (19, 0.4, 0.4)]
        for (inset, lw, a) in borders {
            gc.stroke(Path(CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)),
                      with: .color(gold.opacity(a)), lineWidth: lw)
        }
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (14, 14, 1, 1), (size.width - 14, 14, -1, 1),
            (14, size.height - 14, 1, -1), (size.width - 14, size.height - 14, -1, -1)]
        for (x, y, sx, sy) in corners {
            var c = gc
            c.translateBy(x: x, y: y)
            c.scaleBy(x: sx, y: sy)
            var p = Path()
            p.move(to: .zero)
            p.addCurve(to: CGPoint(x: 22, y: 18), control1: CGPoint(x: 18, y: 2), control2: CGPoint(x: 26, y: 10))
            p.addCurve(to: CGPoint(x: 15, y: 15), control1: CGPoint(x: 19, y: 23), control2: CGPoint(x: 12, y: 20))
            p.move(to: .zero)
            p.addCurve(to: CGPoint(x: 18, y: 22), control1: CGPoint(x: 2, y: 18), control2: CGPoint(x: 10, y: 26))
            c.stroke(p, with: .color(gold), lineWidth: 0.8)
            c.fill(Self.leaf(at: CGPoint(x: 6, y: 6), angle: .pi / 4, len: 12, wid: 3.5), with: .color(gold))
            c.fill(Self.diamond(at: .zero, r: 4), with: .color(gold))
        }

        let ox = win.minX - 11, oy = win.minY - 11, ow = win.width + 22, oh = win.height + 22
        let outer = CGRect(x: ox, y: oy, width: ow, height: oh)
        let R = ow / 2
        let cx = win.midX, cy = oy + R
        let arch = ArchShape()

        // 窗框：一道有光泽的宽金边，带阴影；两侧暗线、中间一道亮线
        var shadowed = gc
        shadowed.addFilter(.shadow(color: Self.night ? .black.opacity(0.5) : Color(red: 0.27, green: 0.18, blue: 0.08).opacity(0.35),
                                   radius: 9, x: 0, y: 6))
        shadowed.stroke(arch.path(in: outer.insetBy(dx: -1, dy: -1)),
                        with: Self.metal(outer.origin, CGPoint(x: outer.maxX, y: outer.maxY)), lineWidth: 10)
        gc.stroke(arch.path(in: outer.insetBy(dx: -6, dy: -6)), with: .color(Self.goldDeep), lineWidth: 0.7)
        gc.stroke(arch.path(in: outer.insetBy(dx: 4, dy: 4)), with: .color(Self.goldDeep), lineWidth: 0.7)
        gc.stroke(arch.path(in: outer.insetBy(dx: -1, dy: -1)),
                  with: .color(Color(red: 1, green: 0.965, blue: 0.84).opacity(0.7)), lineWidth: 0.6)
        gc.stroke(arch.path(in: win.insetBy(dx: -5, dy: -5)), with: .color(gold.opacity(0.5)), lineWidth: 0.5)

        // 拱上一圈藤：起伏的蔓，两边交替长叶，叶间一颗小金珠
        var vine = Path()
        for d in stride(from: 180.0, through: 360.0, by: 2.0) {
            let a = d * .pi / 180
            let rr: CGFloat = R + 8 + CGFloat(sin(d * 0.35) * 2.2)
            let pt = CGPoint(x: cx + CGFloat(cos(a)) * rr, y: cy + CGFloat(sin(a)) * rr)
            if d == 180 { vine.move(to: pt) } else { vine.addLine(to: pt) }
        }
        gc.stroke(vine, with: .color(gold.opacity(0.85)), lineWidth: 0.7)
        var k = 0
        for d in stride(from: 186.0, through: 354.0, by: 9.0) {
            defer { k += 1 }
            if abs(d - 270) < 10 { continue }
            let a = d * .pi / 180
            let rr: CGFloat = R + 8 + CGFloat(sin(d * 0.35) * 2.2)
            let pt = CGPoint(x: cx + CGFloat(cos(a)) * rr, y: cy + CGFloat(sin(a)) * rr)
            let out: Double = k % 2 == 1 ? 1 : -1
            gc.fill(Self.leaf(at: pt, angle: a + out * 0.9 + (d < 270 ? -0.5 : 0.5), len: 9, wid: 2.6),
                    with: .color(gold.opacity(0.9)))
            if k % 2 == 1 {
                let bp = CGPoint(x: cx + CGFloat(cos(a + 0.05)) * (rr - 4), y: cy + CGFloat(sin(a + 0.05)) * (rr - 4))
                gc.fill(Path(ellipseIn: CGRect(x: bp.x - 1.1, y: bp.y - 1.1, width: 2.2, height: 2.2)),
                        with: .color(gold))
            }
        }

        // 拱上嵌一圈宝石：红蓝珍珠相间，正顶一颗大红宝石
        var gi = 0
        for d in stride(from: 198.0, through: 342.0, by: 18.0) {
            let a = d * .pi / 180
            let pt = CGPoint(x: cx + CGFloat(cos(a)) * R, y: cy + CGFloat(sin(a)) * R)
            let top = d == 270
            Self.gem(gc, at: pt, r: top ? 5.2 : 3.4, kind: top ? .ruby : (gi % 2 == 1 ? .sapphire : .pearl))
            gi += 1
        }

        // 冠饰：中间一片向上的叶、两边卷草、三颗宝石
        gc.fill(Self.leaf(at: CGPoint(x: cx, y: oy - 8), angle: -.pi / 2, len: 22, wid: 5.5), with: .color(gold))
        Self.scroll(gc, from: CGPoint(x: cx - 3, y: oy - 6), dir: -1, s: 13)
        Self.scroll(gc, from: CGPoint(x: cx + 3, y: oy - 6), dir: 1, s: 13)
        gc.fill(Self.leaf(at: CGPoint(x: cx - 4, y: oy - 12), angle: -.pi / 2 - 0.7, len: 12, wid: 3), with: .color(gold))
        gc.fill(Self.leaf(at: CGPoint(x: cx + 4, y: oy - 12), angle: -.pi / 2 + 0.7, len: 12, wid: 3), with: .color(gold))
        Self.gem(gc, at: CGPoint(x: cx, y: oy - 30), r: 4.2, kind: .ruby)
        Self.gem(gc, at: CGPoint(x: cx - 15, y: oy - 15), r: 2.8, kind: .sapphire)
        Self.gem(gc, at: CGPoint(x: cx + 15, y: oy - 15), r: 2.8, kind: .sapphire)

        // 两侧立柱 + 拱肩卷草
        Self.column(gc, x: ox - 12, top: cy + 4, bottom: oy + oh)
        Self.column(gc, x: ox + ow + 12, top: cy + 4, bottom: oy + oh)
        Self.scroll(gc, from: CGPoint(x: ox - 6, y: cy - 10), dir: -1, s: 18)
        Self.scroll(gc, from: CGPoint(x: ox + ow + 6, y: cy - 10), dir: 1, s: 18)

        // 窗台 + 托架 + 一排垂饰
        let sill = CGRect(x: ox - 26, y: oy + oh, width: ow + 52, height: 8)
        gc.fill(Path(sill), with: .color(Self.veil.opacity(0.55)))
        gc.stroke(Path(sill), with: .color(gold), lineWidth: 0.9)
        gc.stroke(Path(CGRect(x: sill.minX + 8, y: sill.maxY, width: sill.width - 16, height: 3)),
                  with: .color(gold.opacity(0.6)), lineWidth: 0.6)
        Self.scroll(gc, from: CGPoint(x: sill.minX + 26, y: sill.minY + 11), dir: -1, s: 12, up: -1)
        Self.scroll(gc, from: CGPoint(x: sill.maxX - 26, y: sill.minY + 11), dir: 1, s: 12, up: -1)
        for i in 0..<9 {
            let px = cx - 48 + CGFloat(i) * 12
            let len = 5 + CGFloat(4 - abs(i - 4)) * 2.5
            var l = Path()
            l.move(to: CGPoint(x: px, y: sill.minY + 11))
            l.addLine(to: CGPoint(x: px, y: sill.minY + 11 + len))
            gc.stroke(l, with: .color(gold.opacity(0.6)), lineWidth: 0.5)
            gc.fill(Path(ellipseIn: CGRect(x: px - 1.4, y: sill.minY + 10.6 + len, width: 2.8, height: 2.8)),
                    with: .color(gold))
        }
    }

    /// 玻璃上那一道金色内框（在玻璃上面，所以每帧画）
    private func drawTracery(_ gc: GraphicsContext, win: CGRect) {
        gc.stroke(ArchShape().path(in: win),
                  with: Self.metal(win.origin, CGPoint(x: win.maxX, y: win.maxY)), lineWidth: 2.2)
    }

    /// 几颗四角的小金星，错开着一闪一闪
    private func drawSparkles(_ gc: GraphicsContext, size: CGSize, now: Date) {
        let t = now.timeIntervalSinceReferenceDate
        let spots: [(CGFloat, CGFloat, CGFloat)] = [
            (0.13, 0.15, 6), (0.87, 0.11, 4), (0.08, 0.50, 4.5), (0.92, 0.45, 7),
            (0.16, 0.82, 3.5), (0.86, 0.85, 5), (0.50, 0.95, 3)]
        for (i, s) in spots.enumerated() {
            let k = 0.35 + 0.65 * pow(sin(t * (0.7 + 0.13 * Double(i)) + Double(i) * 1.9), 2)
            let c = CGPoint(x: size.width * s.0, y: size.height * s.1)
            let r = s.2 * CGFloat(k)
            var p = Path()
            p.move(to: CGPoint(x: c.x, y: c.y - r * 2))
            p.addQuadCurve(to: CGPoint(x: c.x + r * 2, y: c.y), control: c)
            p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r * 2), control: c)
            p.addQuadCurve(to: CGPoint(x: c.x - r * 2, y: c.y), control: c)
            p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r * 2), control: c)
            gc.fill(p, with: .color(Self.gold.opacity(0.4 + 0.5 * k)))
        }
    }

    // MARK: 金饰的小零件

    static func diamond(at c: CGPoint, r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addLine(to: CGPoint(x: c.x + r * 0.7, y: c.y))
        p.addLine(to: CGPoint(x: c.x, y: c.y + r))
        p.addLine(to: CGPoint(x: c.x - r * 0.7, y: c.y))
        p.closeSubpath()
        return p
    }

    /// 一片叶子：从 `at` 往 `angle` 方向长
    static func leaf(at p: CGPoint, angle: Double, len: CGFloat, wid: CGFloat) -> Path {
        var l = Path()
        l.move(to: .zero)
        l.addQuadCurve(to: CGPoint(x: len, y: 0), control: CGPoint(x: len * 0.5, y: -wid))
        l.addQuadCurve(to: .zero, control: CGPoint(x: len * 0.5, y: wid))
        return l.applying(CGAffineTransform(translationX: p.x, y: p.y).rotated(by: angle))
    }

    /// 一个卷草：从 `from` 往 `dir` 方向（1 右 / -1 左）卷一圈半，末端一颗小珠
    static func scroll(_ gc: GraphicsContext, from o: CGPoint, dir: CGFloat, s: CGFloat, up: CGFloat = 1) {
        var p = Path()
        p.move(to: o)
        p.addCurve(to: CGPoint(x: o.x + dir * s * 0.9, y: o.y - up * s * 1.2),
                   control1: CGPoint(x: o.x + dir * s * 0.9, y: o.y - up * s * 0.1),
                   control2: CGPoint(x: o.x + dir * s * 1.4, y: o.y - up * s * 0.9))
        p.addCurve(to: CGPoint(x: o.x + dir * s * 0.7, y: o.y - up * s * 0.8),
                   control1: CGPoint(x: o.x + dir * s * 0.55, y: o.y - up * s * 1.4),
                   control2: CGPoint(x: o.x + dir * s * 0.35, y: o.y - up * s * 0.95))
        gc.stroke(p, with: .color(gold), lineWidth: 0.8)
        let e = CGPoint(x: o.x + dir * s * 0.7, y: o.y - up * s * 0.8)
        gc.fill(Path(ellipseIn: CGRect(x: e.x - 1.3, y: e.y - 1.3, width: 2.6, height: 2.6)), with: .color(gold))
    }

    /// 一根金立柱：柱身打磨金 + 三道凹槽、柱头柱础、柱头两边一对小卷草
    static func column(_ gc: GraphicsContext, x: CGFloat, top: CGFloat, bottom: CGFloat) {
        let w: CGFloat = 9
        let body = CGRect(x: x - w / 2, y: top, width: w, height: bottom - top)
        gc.fill(Path(body), with: metal(CGPoint(x: body.minX, y: 0), CGPoint(x: body.maxX, y: 0)))
        gc.stroke(Path(body), with: .color(gold.opacity(0.9)), lineWidth: 0.8)
        for o: CGFloat in [-2, 0, 2] {
            var l = Path()
            l.move(to: CGPoint(x: x + o, y: top + 10))
            l.addLine(to: CGPoint(x: x + o, y: bottom - 10))
            gc.stroke(l, with: .color(Color(red: 0.35, green: 0.25, blue: 0.09).opacity(0.55)), lineWidth: 0.5)
        }
        gc.fill(Path(CGRect(x: x - w / 2 - 3, y: top - 3, width: w + 6, height: 2.2)), with: .color(gold))
        gc.fill(Path(CGRect(x: x - w / 2 - 1.5, y: top - 6, width: w + 3, height: 1.6)), with: .color(gold))
        gc.fill(Path(CGRect(x: x - w / 2 - 3, y: bottom + 0.8, width: w + 6, height: 2.2)), with: .color(gold))
        gc.fill(Path(CGRect(x: x - w / 2 - 1.5, y: bottom + 4, width: w + 3, height: 1.6)), with: .color(gold))
        scroll(gc, from: CGPoint(x: x - w / 2 - 2, y: top - 2), dir: -1, s: 6, up: -1)
        scroll(gc, from: CGPoint(x: x + w / 2 + 2, y: top - 2), dir: 1, s: 6, up: -1)
    }

    enum GemKind { case ruby, sapphire, pearl }

    /// 一颗切面宝石：金托 + 八边形宝石（径向渐变）+ 一道刻面 + 一个白高光
    static func gem(_ gc: GraphicsContext, at p: CGPoint, r: CGFloat, kind: GemKind) {
        let cols: [Color]
        switch kind {
        // 夜里：红宝石换成月光石，蓝宝石换成淡紫晶，珍珠带一点粉
        case .ruby: cols = night
            ? [.white, Color(red: 0.80, green: 0.85, blue: 0.96), Color(red: 0.46, green: 0.51, blue: 0.62)]
            : [Color(red: 1, green: 0.70, blue: 0.75), Color(red: 0.64, green: 0.07, blue: 0.18), Color(red: 0.30, green: 0.03, blue: 0.09)]
        case .sapphire: cols = night
            ? [Color(red: 0.96, green: 0.93, blue: 1), Color(red: 0.73, green: 0.66, blue: 0.89), Color(red: 0.36, green: 0.32, blue: 0.52)]
            : [Color(red: 0.74, green: 0.82, blue: 1), Color(red: 0.16, green: 0.25, blue: 0.62), Color(red: 0.05, green: 0.09, blue: 0.28)]
        case .pearl: cols = night
            ? [.white, Color(red: 0.95, green: 0.90, blue: 0.94), Color(red: 0.66, green: 0.58, blue: 0.62)]
            : [.white, Color(red: 0.91, green: 0.89, blue: 0.96), Color(red: 0.66, green: 0.63, blue: 0.74)]
        }
        let mount = CGRect(x: p.x - r - 1.6, y: p.y - r - 1.6, width: (r + 1.6) * 2, height: (r + 1.6) * 2)
        gc.fill(Path(ellipseIn: mount), with: metal(mount.origin, CGPoint(x: mount.maxX, y: mount.maxY)))
        var oct = Path()
        for k in 0..<8 {
            let a = Double(k) * .pi / 4 + .pi / 8
            let q = CGPoint(x: p.x + CGFloat(cos(a)) * r, y: p.y + CGFloat(sin(a)) * r)
            if k == 0 { oct.move(to: q) } else { oct.addLine(to: q) }
        }
        oct.closeSubpath()
        gc.fill(oct, with: .radialGradient(Gradient(colors: cols),
                                           center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.3),
                                           startRadius: 0, endRadius: r))
        var facet = Path()
        facet.move(to: CGPoint(x: p.x - r * 0.5, y: p.y - r * 0.2))
        facet.addLine(to: CGPoint(x: p.x, y: p.y - r * 0.6))
        facet.addLine(to: CGPoint(x: p.x + r * 0.5, y: p.y - r * 0.2))
        gc.stroke(facet, with: .color(.white.opacity(0.35)), lineWidth: 0.5)
        gc.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.57, y: p.y - r * 0.57, width: r * 0.44, height: r * 0.44)),
                with: .color(.white.opacity(0.9)))
    }

    // MARK: 字

    private func words(size: CGSize, win: CGRect, safeBottom: CGFloat) -> some View {
        let outerTop = win.minY - 11
        return ZStack {
            // 窗上面：日期，两边各一道细金线
            HStack(spacing: 10) {
                Rectangle().fill(Self.gold.opacity(0.7)).frame(width: 30, height: 0.6)
                rise(stamp.dateLine, delay: 0.3) { s in
                    Text(s).font(.system(size: 18, weight: .regular, design: .serif).italic())
                        .foregroundStyle(Self.wine)
                }
                Rectangle().fill(Self.gold.opacity(0.7)).frame(width: 30, height: 0.6)
            }
            .position(x: size.width / 2, y: outerTop - 54)

            // 窗下面：此刻
            VStack(spacing: 8) {
                rise(stamp.clock, delay: 0.8) { s in
                    Text(s).font(.system(size: 50, weight: .light, design: .serif).italic())
                        .foregroundStyle(Self.ink)
                }
                rise(stamp.words, delay: 1.2) { s in
                    Text(s).font(.system(size: 11.5, weight: .regular, design: .serif))
                        .tracking(5)
                        .foregroundStyle(Self.rose)
                }
            }
            .position(x: size.width / 2, y: win.maxY + 96)

            VStack(spacing: 5) {
                Text("轻点进入")
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .tracking(6)
                    .foregroundStyle(Self.ink.opacity(0.65))
                Text("entrez")
                    .font(.system(size: 12, weight: .regular, design: .serif).italic())
                    .foregroundStyle(Self.gold)
            }
            .offset(y: risen ? 0 : 14)
            .blur(radius: risen ? 0 : 5)
            .animation(.spring(response: 1.2, dampingFraction: 0.8).delay(2.0), value: risen)
            .position(x: size.width / 2, y: size.height - safeBottom - 52)
        }
        .allowsHitTesting(false)
    }

    /// 一行字一个字一个字浮上来（不淡入：往上浮、由虚变实）
    private func rise<G: View>(_ text: String, delay: Double,
                               @ViewBuilder _ glyph: @escaping (String) -> G) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { i, ch in
                glyph(String(ch))
                    .offset(y: risen ? 0 : 12)
                    .blur(radius: risen ? 0 : 6)
                    .animation(.spring(response: 1.0, dampingFraction: 0.75)
                        .delay(delay + Double(i) * 0.06), value: risen)
            }
        }
    }

    // MARK: 手

    private func touch(size: CGSize, win: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard !leaving else { return }
                if dragStart == nil { dragStart = Date() }
                let p = v.location
                rope.finger = p
                if win.contains(p),
                   lastRipple.map({ hypot($0.x - p.x, $0.y - p.y) > 36 }) ?? true {
                    ripples.add(CGPoint(x: p.x - win.minX, y: p.y - win.minY),
                                amp: lastRipple == nil ? 0.8 : 0.45)
                    lastRipple = p
                }
            }
            .onEnded { v in
                defer { dragStart = nil; lastRipple = nil; rope.finger = nil }
                guard !leaving else { return }
                let moved = hypot(v.translation.width, v.translation.height)
                let quick = Date().timeIntervalSince(dragStart ?? Date()) < 0.35
                if moved < 10 && quick { leave(at: v.location, size: size, win: win) }
            }
    }

    // MARK: 离场

    private func leave(at p: CGPoint, size: CGSize, win: CGRect) {
        leaving = true
        let local = win.contains(p) ? CGPoint(x: p.x - win.minX, y: p.y - win.minY)
                                    : CGPoint(x: win.width / 2, y: win.height * 0.6)
        ripples.add(local, amp: 1.5)
        revealAt = p
        let far = [CGPoint.zero, CGPoint(x: size.width, y: 0),
                   CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
            .map { hypot($0.x - p.x, $0.y - p.y) }.max() ?? size.height
        withAnimation(.spring(response: 1.0, dampingFraction: 0.92).delay(0.15)) {
            revealR = far + 40
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) { onEnter() }
    }

    private var revealMask: some View {
        ZStack {
            Rectangle()
            Circle()
                .frame(width: revealR * 2, height: revealR * 2)
                .position(revealAt)
                .blur(radius: revealR > 0 ? 18 : 0)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }

    // MARK: 日期和时间

    struct Stamp { var dateLine: String; var clock: String; var words: String }

    static func stamp(_ d: Date) -> Stamp {
        let c = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: d)
        let mo = c.month ?? 1, day = c.day ?? 1, h = c.hour ?? 0, mi = c.minute ?? 0
        let months = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet",
                      "août", "septembre", "octobre", "novembre", "décembre"]
        let part: String
        switch h {
        case 0..<5: part = "凌晨"
        case 5..<8: part = "清晨"
        case 8..<11: part = "上午"
        case 11..<13: part = "中午"
        case 13..<17: part = "下午"
        case 17..<19: part = "傍晚"
        default: part = "夜里"
        }
        // 零点就叫零点；中午十二点叫十二点；其余按十二小时
        let hourWord: String
        if h == 0 { hourWord = "零" }
        else if h == 12 { hourWord = "十二" }
        else {
            let h12 = h % 12
            hourWord = h12 == 2 ? "两" : cn(h12)
        }
        let minute = mi == 0 ? "整" : (mi < 10 ? "零" + cn(mi) + "分" : cn(mi) + "分")
        return Stamp(dateLine: "\(day) " + months[mo - 1],
                     clock: String(format: "%02d:%02d", h, mi),
                     words: part + " · " + hourWord + "点" + minute)
    }

    /// 1–59 写成汉字
    static func cn(_ n: Int) -> String {
        let d = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        if n < 10 { return d[n] }
        if n == 10 { return "十" }
        if n < 20 { return "十" + d[n % 10] }
        return d[n / 10] + "十" + (n % 10 == 0 ? "" : d[n % 10])
    }
}

/// 拱窗的形状：下面方、上面半圆
struct ArchShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let rad = r.width / 2
        let c = CGPoint(x: r.midX, y: r.minY + rad)
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: c.y))
        // 一点一点走过去，不靠 addArc 的顺逆时针（y 朝下时容易画反）
        for deg in stride(from: 180.0, through: 360.0, by: 3.0) {
            let a = deg * .pi / 180
            p.addLine(to: CGPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - 涟漪

final class RippleSet {
    private var list: [(p: CGPoint, born: Date, amp: Float)] = []

    func add(_ p: CGPoint, amp: Float) {
        list.append((p, Date(), amp))
        if list.count > 10 { list.removeFirst(list.count - 10) }
    }

    /// 交给着色器的那串数：每圈四个（x, y, 几秒, 力）
    func args(now: Date) -> [Float] {
        list.removeAll { now.timeIntervalSince($0.born) > 4.5 }
        var a: [Float] = []
        for r in list {
            a += [Float(r.p.x), Float(r.p.y), Float(now.timeIntervalSince(r.born)), r.amp]
        }
        return a.isEmpty ? [0, 0, 99, 0] : a
    }
}

// MARK: - 珍珠串

/// 搭在拱窗上的一串珍珠。真的绳子：Verlet 积分 + 定长约束，两头钉在拱的两肩。
///
/// ⚠️ 是个类：画的时候推它一步，不触发重画——重画由 `TimelineView` 按帧推。
final class PearlRope {
    private var p: [CGPoint] = []
    private var prev: [CGPoint] = []
    /// 坠子（挂在正中那颗下面的一个点）
    private var drop = CGPoint.zero
    private var dropPrev = CGPoint.zero
    private var seg: CGFloat = 0
    private var a = CGPoint.zero
    private var b = CGPoint.zero
    private var last: Date?
    var finger: CGPoint?
    private let n = 23

    func step(_ now: Date, win: CGRect) {
        if p.isEmpty {
            // 两头钉在拱的两肩；一开始拉直，放手让它自己垂下去、晃两下
            let outer = win.insetBy(dx: -11, dy: -11)
            a = CGPoint(x: outer.minX + 4, y: outer.minY + outer.width / 2 + 6)
            b = CGPoint(x: outer.maxX - 4, y: outer.minY + outer.width / 2 + 6)
            let span = hypot(b.x - a.x, b.y - a.y)
            seg = span * 1.22 / CGFloat(n - 1)
            for i in 0..<n {
                let t = CGFloat(i) / CGFloat(n - 1)
                p.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
            prev = p
            drop = CGPoint(x: p[n / 2].x, y: p[n / 2].y + 14)
            dropPrev = drop
        }
        let dt = CGFloat(min(1.0 / 30, now.timeIntervalSince(last ?? now)))
        last = now
        guard dt > 0 else { return }
        let g: CGFloat = 1500
        let keep: CGFloat = 0.985

        func integrate(_ x: inout CGPoint, _ px: inout CGPoint) {
            let v = CGPoint(x: (x.x - px.x) * keep, y: (x.y - px.y) * keep)
            px = x
            x = CGPoint(x: x.x + v.x, y: x.y + v.y + g * dt * dt)
        }
        for i in 1..<(n - 1) { integrate(&p[i], &prev[i]) }
        integrate(&drop, &dropPrev)

        for _ in 0..<12 {
            p[0] = a
            p[n - 1] = b
            for i in 0..<(n - 1) {
                let d = CGPoint(x: p[i + 1].x - p[i].x, y: p[i + 1].y - p[i].y)
                let len = max(0.001, hypot(d.x, d.y))
                let diff = (len - seg) / len * 0.5
                if i != 0 { p[i].x += d.x * diff; p[i].y += d.y * diff }
                if i + 1 != n - 1 { p[i + 1].x -= d.x * diff; p[i + 1].y -= d.y * diff }
            }
            // 坠子：离正中那颗固定 14 点
            let m = p[n / 2]
            let d = CGPoint(x: drop.x - m.x, y: drop.y - m.y)
            let len = max(0.001, hypot(d.x, d.y))
            drop = CGPoint(x: m.x + d.x / len * 14, y: m.y + d.y / len * 14)
            // 手指：珠子被推开（拨动）
            if let f = finger {
                for i in 1..<(n - 1) {
                    let dx = p[i].x - f.x, dy = p[i].y - f.y
                    let dd = hypot(dx, dy)
                    if dd < 26, dd > 0.001 {
                        p[i] = CGPoint(x: f.x + dx / dd * 26, y: f.y + dy / dd * 26)
                    }
                }
            }
        }
    }

    func draw(_ gc: GraphicsContext) {
        guard !p.isEmpty else { return }
        let gold = SplashView.gold
        // 细金丝
        var line = Path()
        line.move(to: p[0])
        for q in p.dropFirst() { line.addLine(to: q) }
        gc.stroke(line, with: .color(gold.opacity(0.6)), lineWidth: 0.5)
        // 珠与珠之间一颗小金珠
        for i in 0..<(p.count - 1) {
            let m = CGPoint(x: (p[i].x + p[i + 1].x) / 2, y: (p[i].y + p[i + 1].y) / 2)
            gc.fill(Path(ellipseIn: CGRect(x: m.x - 1.4, y: m.y - 1.4, width: 2.8, height: 2.8)),
                    with: .color(gold))
        }
        // 坠子：一小节金链 + 一颗酒红的水滴
        let m = p[p.count / 2]
        var link = Path()
        link.move(to: m)
        link.addLine(to: drop)
        gc.stroke(link, with: .color(gold), lineWidth: 0.8)
        let ang = atan2(drop.y - m.y, drop.x - m.x) - .pi / 2
        var tear = Path()
        tear.move(to: CGPoint(x: 0, y: -1))
        tear.addQuadCurve(to: CGPoint(x: 0, y: 12), control: CGPoint(x: 9, y: 9))
        tear.addQuadCurve(to: CGPoint(x: 0, y: -1), control: CGPoint(x: -9, y: 9))
        let tf = CGAffineTransform(translationX: drop.x, y: drop.y).rotated(by: ang)
        gc.fill(tear.applying(tf), with: .color(SplashView.drop))
        gc.fill(Path(ellipseIn: CGRect(x: -1.6, y: 4, width: 2.2, height: 3.2)).applying(tf),
                with: .color(.white.opacity(0.55)))
        // 珍珠（两头的钉子不画）
        for q in p.dropFirst().dropLast() {
            let r: CGFloat = 4.3
            let rect = CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)
            gc.fill(Path(ellipseIn: rect),
                    with: .radialGradient(Gradient(colors: [.white,
                                                            Color(red: 0.96, green: 0.94, blue: 0.91),
                                                            Color(red: 0.78, green: 0.74, blue: 0.70)]),
                                          center: CGPoint(x: q.x - 1.4, y: q.y - 1.6),
                                          startRadius: 0, endRadius: r * 1.35))
            gc.stroke(Path(ellipseIn: rect), with: .color(Color(red: 0.6, green: 0.55, blue: 0.5).opacity(0.35)),
                      lineWidth: 0.4)
        }
        // 两头的钉子：小金花托
        for e in [p[0], p[p.count - 1]] {
            gc.fill(Path(ellipseIn: CGRect(x: e.x - 3, y: e.y - 3, width: 6, height: 6)), with: .color(gold))
        }
    }
}

// MARK: - 星屑

/// 手指划过时落下的一串小星屑（淡紫、淡粉，夜里偏银白），往上一扬再慢慢落、慢慢淡；
/// 夜里窗外还一直飘着一层很细的星屑。
///
/// 她定的：「星屑的粒子可以保留」——那一版开屏不要了，只要手指移动时出来的这串粒子。
/// ⚠️ 是个类：画的时候推它一步，不触发重画（重画由 `TimelineView` 按帧推）
final class SparkField {
    struct Spark { var p: CGPoint; var v: CGVector; var life: Double; var r: CGFloat; var c: Color }
    struct Dust { var p: CGPoint; var v: CGFloat; var r: CGFloat; var ph: Double; var c: Color }
    private var sparks: [Spark] = []
    private var dust: [Dust] = []
    private var last: Date?
    private var lastFinger: CGPoint?
    private var t: Double = 0
    private var night = false

    func step(_ now: Date, size: CGSize, finger: CGPoint?, night: Bool) {
        self.night = night
        let dt = min(1.0 / 30, now.timeIntervalSince(last ?? now))
        last = now
        t = now.timeIntervalSinceReferenceDate
        let pal: [Color] = night
            ? [Color(red: 0.92, green: 0.89, blue: 1), Color(red: 1, green: 0.84, blue: 0.91), Color(red: 0.87, green: 0.93, blue: 1)]
            : [Color(red: 0.93, green: 0.80, blue: 0.55), Color(red: 0.96, green: 0.76, blue: 0.82), Color(red: 0.86, green: 0.82, blue: 0.95)]
        // 手指在动才落：按这一帧移动的距离决定落几颗
        if let f = finger {
            let moved = lastFinger.map { hypot(f.x - $0.x, f.y - $0.y) } ?? 0
            let n = min(4, Int(moved / 6) + (lastFinger == nil ? 2 : 0))
            for _ in 0..<n {
                sparks.append(Spark(p: CGPoint(x: f.x + .random(in: -6...6), y: f.y + .random(in: -6...6)),
                                    v: CGVector(dx: .random(in: -15...15), dy: .random(in: -36...(-8))),
                                    life: 1, r: .random(in: 0.6...2.2), c: pal.randomElement()!))
            }
        }
        lastFinger = finger
        for i in sparks.indices {
            sparks[i].life -= dt * 0.55
            sparks[i].p.x += sparks[i].v.dx * dt
            sparks[i].p.y += sparks[i].v.dy * dt
            sparks[i].v.dy += 12 * dt
        }
        sparks.removeAll { $0.life <= 0 }
        if sparks.count > 260 { sparks.removeFirst(sparks.count - 260) }

        if night {
            if dust.isEmpty, size.width > 0 {
                dust = (0..<46).map { _ in
                    Dust(p: CGPoint(x: .random(in: 0...size.width), y: .random(in: 0...size.height)),
                         v: .random(in: 6...20), r: .random(in: 0.5...1.8), ph: .random(in: 0...7),
                         c: pal.randomElement()!)
                }
            }
            for i in dust.indices {
                dust[i].p.y += dust[i].v * dt
                dust[i].p.x += CGFloat(sin(t * 0.4 + dust[i].ph)) * 0.08
                if dust[i].p.y > size.height + 4 { dust[i].p.y = -4; dust[i].p.x = .random(in: 0...size.width) }
            }
        } else {
            dust.removeAll()
        }
    }

    func draw(_ gc: GraphicsContext) {
        for d in dust {
            let a = 0.25 + 0.55 * pow(sin(t * 1.3 + d.ph), 2)
            gc.fill(Path(ellipseIn: CGRect(x: d.p.x - d.r, y: d.p.y - d.r, width: d.r * 2, height: d.r * 2)),
                    with: .color(d.c.opacity(a)))
        }
        for s in sparks {
            if s.r > 1.6 {
                // 大一点的画成四角小星
                let r = s.r * 0.8, c = s.p
                var p = Path()
                p.move(to: CGPoint(x: c.x, y: c.y - r * 2))
                p.addQuadCurve(to: CGPoint(x: c.x + r * 2, y: c.y), control: c)
                p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r * 2), control: c)
                p.addQuadCurve(to: CGPoint(x: c.x - r * 2, y: c.y), control: c)
                p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r * 2), control: c)
                gc.fill(p, with: .color(s.c.opacity(s.life * 0.9)))
            } else {
                gc.fill(Path(ellipseIn: CGRect(x: s.p.x - s.r, y: s.p.y - s.r, width: s.r * 2, height: s.r * 2)),
                        with: .color(s.c.opacity(s.life * 0.9)))
            }
        }
    }
}

import SwiftUI

/// 开屏：一页象牙色的纸，中间一扇拱窗。
///
/// 她要的风格：浅、雅、像一页复古手账——象牙白的底、细金线、
/// 藕荷和酒红点一点、衬线斜体的小字。只要这种气质，不照搬别人的物件。
///
/// 动的东西都讲物理、讲因果（motion-web 那份主张）：
///   · 拱窗里是她自己的壁纸，手指点、划过窗里，水波一样起涟漪（`SplashRipple.metal`）
///   · 窗上搭着一串珍珠，是一根真的绳子（Verlet）：进来时从拉直的样子垂下去晃两下；
///     手指拨它会荡，坠子跟着甩
///   · 字一个个浮上来；几颗金色的小星一闪一闪
///   · 轻点任何地方：那一点向外让开，露出 App
///
/// 只在冷启动出现一次；设置里能关（`AppSettings.splashOn`）。
struct SplashView: View {

    var onEnter: () -> Void

    @State private var ripples = RippleSet()
    @State private var rope = PearlRope()
    @State private var grain = PaperGrain()
    @State private var leaving = false
    @State private var revealR: CGFloat = 0
    @State private var revealAt: CGPoint = .zero
    @State private var lastRipple: CGPoint?
    @State private var dragStart: Date?
    @State private var risen = false
    @State private var stamp = SplashView.stamp(Date())

    // 色板
    static let paper = Color(red: 0.965, green: 0.945, blue: 0.915)
    static let gold = Color(red: 0.74, green: 0.60, blue: 0.38)
    static let wine = Color(red: 0.50, green: 0.15, blue: 0.20)
    static let rose = Color(red: 0.70, green: 0.50, blue: 0.52)
    static let ink = Color(red: 0.24, green: 0.19, blue: 0.18)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let win = Self.windowRect(in: size)
            ZStack {
                Self.paper
                // 纸的颗粒和四周一圈微微发暖
                Canvas { gc, sz in grain.draw(gc, size: sz) }
                RadialGradient(colors: [.clear, Color(red: 0.86, green: 0.80, blue: 0.72).opacity(0.35)],
                               center: .center, startRadius: size.height * 0.25,
                               endRadius: size.height * 0.75)

                TimelineView(.animation) { tl in
                    let now = tl.date
                    ZStack {
                        glass(win: win, now: now)
                        Canvas { gc, sz in
                            drawFrame(gc, win: win, size: sz)
                            drawSparkles(gc, size: sz, win: win, now: now)
                            rope.step(now, win: win)
                            rope.draw(gc)
                        }
                    }
                }

                words(size: size, win: win, safeTop: geo.safeAreaInsets.top,
                      safeBottom: geo.safeAreaInsets.bottom)
            }
            .mask { revealMask }
            .contentShape(Rectangle())
            .gesture(touch(size: size, win: win))
        }
        .ignoresSafeArea()
        .onAppear { withAnimation { risen = true } }
    }

    // MARK: 拱窗

    static func windowRect(in size: CGSize) -> CGRect {
        let w = min(size.width * 0.6, 270)
        let h = w * 1.42
        return CGRect(x: (size.width - w) / 2, y: size.height * 0.2, width: w, height: h)
    }

    /// 窗里：她的壁纸，会起涟漪；上面斜斜一道玻璃反光
    private func glass(win: CGRect, now: Date) -> some View {
        ZStack {
            WallpaperBackground()
            LinearGradient(colors: [.white.opacity(0.22), .clear, .clear, .white.opacity(0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .frame(width: win.width, height: win.height)
        .clipped()
        .layerEffect(ShaderLibrary.qiRipple(.floatArray(ripples.args(now: now)),
                                            .float2(win.size)),
                     maxSampleOffset: CGSize(width: 40, height: 40))
        .clipShape(ArchShape())
        .overlay(ArchShape().stroke(Self.ink.opacity(0.12), lineWidth: 3).blur(radius: 3).clipShape(ArchShape()))
        .scaleEffect(risen ? 1 : 0.94, anchor: .bottom)
        .animation(.spring(response: 1.2, dampingFraction: 0.7), value: risen)
        .position(x: win.midX, y: win.midY)
    }

    /// 金线：窗框两道、外圈一串小金珠、拱顶一颗菱形、窗台；整页一道细边框
    private func drawFrame(_ gc: GraphicsContext, win: CGRect, size: CGSize) {
        let gold = Self.gold
        // 整页的边框：两道，四角各一颗菱形
        for (inset, wdt, a) in [(14.0, 0.7, 0.55), (19.0, 0.4, 0.35)] {
            let r = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            gc.stroke(Path(r), with: .color(gold.opacity(a)), lineWidth: wdt)
        }
        for c in [CGPoint(x: 14, y: 14), CGPoint(x: size.width - 14, y: 14),
                  CGPoint(x: 14, y: size.height - 14), CGPoint(x: size.width - 14, y: size.height - 14)] {
            gc.fill(diamond(at: c, r: 4), with: .color(gold.opacity(0.7)))
        }

        // 窗框
        let inner = win
        let outer = win.insetBy(dx: -11, dy: -11)
        gc.stroke(ArchShape().path(in: inner), with: .color(gold.opacity(0.9)), lineWidth: 0.8)
        gc.stroke(ArchShape().path(in: outer), with: .color(gold), lineWidth: 1.2)
        gc.stroke(ArchShape().path(in: win.insetBy(dx: -16, dy: -16)),
                  with: .color(gold.opacity(0.45)), lineWidth: 0.5)
        // 外圈拱上一串小金珠
        let rad = outer.width / 2
        let center = CGPoint(x: outer.midX, y: outer.minY + rad)
        for deg in stride(from: 186.0, through: 354.0, by: 7.0) {
            let a = deg * .pi / 180
            let p = CGPoint(x: center.x + cos(a) * (rad + 5.5), y: center.y + sin(a) * (rad + 5.5))
            gc.fill(Path(ellipseIn: CGRect(x: p.x - 1.3, y: p.y - 1.3, width: 2.6, height: 2.6)),
                    with: .color(gold.opacity(0.8)))
        }
        // 拱顶
        gc.fill(diamond(at: CGPoint(x: outer.midX, y: outer.minY - 9), r: 5.5), with: .color(gold))
        gc.fill(diamond(at: CGPoint(x: outer.midX, y: outer.minY - 9), r: 2.2), with: .color(Self.paper))
        // 窗台
        let sill = CGRect(x: outer.minX - 12, y: outer.maxY, width: outer.width + 24, height: 7)
        gc.fill(Path(sill), with: .color(Self.paper))
        gc.stroke(Path(sill), with: .color(gold), lineWidth: 0.9)
        gc.stroke(Path(CGRect(x: sill.minX + 8, y: sill.maxY, width: sill.width - 16, height: 3)),
                  with: .color(gold.opacity(0.6)), lineWidth: 0.6)
        // 窗的中梃：一根细金线，到拱起的地方为止
        var mullion = Path()
        mullion.move(to: CGPoint(x: inner.midX, y: inner.minY + inner.width / 2))
        mullion.addLine(to: CGPoint(x: inner.midX, y: inner.maxY))
        gc.stroke(mullion, with: .color(gold.opacity(0.55)), lineWidth: 0.6)
    }

    private func diamond(at c: CGPoint, r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addLine(to: CGPoint(x: c.x + r * 0.7, y: c.y))
        p.addLine(to: CGPoint(x: c.x, y: c.y + r))
        p.addLine(to: CGPoint(x: c.x - r * 0.7, y: c.y))
        p.closeSubpath()
        return p
    }

    /// 几颗四角的小金星，错开着一闪一闪（在窗外面）
    private func drawSparkles(_ gc: GraphicsContext, size: CGSize, win: CGRect, now: Date) {
        let t = now.timeIntervalSinceReferenceDate
        let spots: [(CGFloat, CGFloat, CGFloat)] = [
            (0.14, 0.16, 6), (0.86, 0.12, 4), (0.10, 0.52, 4.5), (0.90, 0.47, 7),
            (0.18, 0.80, 3.5), (0.84, 0.84, 5), (0.50, 0.93, 3)]
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

    // MARK: 字

    private func words(size: CGSize, win: CGRect, safeTop: CGFloat, safeBottom: CGFloat) -> some View {
        let outerTop = win.minY - 11
        return ZStack {
            // 窗上面：日期，两边各一道细金线
            HStack(spacing: 10) {
                Rectangle().fill(Self.gold.opacity(0.6)).frame(width: 34, height: 0.6)
                rise(stamp.dateLine, delay: 0.3) { s in
                    Text(s).font(.system(size: 16, weight: .regular, design: .serif).italic())
                        .foregroundStyle(Self.wine)
                }
                Rectangle().fill(Self.gold.opacity(0.6)).frame(width: 34, height: 0.6)
            }
            .position(x: size.width / 2, y: outerTop - 40)

            // 窗下面：此刻
            VStack(spacing: 8) {
                rise(stamp.clock, delay: 0.8) { s in
                    Text(s).font(.system(size: 46, weight: .light, design: .serif).italic())
                        .foregroundStyle(Self.ink)
                }
                rise(stamp.words, delay: 1.2) { s in
                    Text(s).font(.system(size: 11.5, weight: .regular, design: .serif))
                        .tracking(5)
                        .foregroundStyle(Self.rose)
                }
            }
            .position(x: size.width / 2, y: win.maxY + 82)

            VStack(spacing: 5) {
                Text("轻点进入")
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .tracking(6)
                    .foregroundStyle(Self.ink.opacity(0.55))
                Text("entrez")
                    .font(.system(size: 10, weight: .regular, design: .serif).italic())
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
        gc.fill(tear.applying(tf), with: .color(SplashView.wine))
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

// MARK: - 纸纹

/// 纸上细细的颗粒。只算一次
final class PaperGrain {
    private var dots: [(CGFloat, CGFloat, Double)] = []

    func draw(_ gc: GraphicsContext, size: CGSize) {
        if dots.isEmpty {
            for _ in 0..<1400 {
                dots.append((CGFloat.random(in: 0...1), CGFloat.random(in: 0...1),
                             Double.random(in: 0.03...0.09)))
            }
        }
        for d in dots {
            gc.fill(Path(ellipseIn: CGRect(x: d.0 * size.width, y: d.1 * size.height, width: 0.9, height: 0.9)),
                    with: .color(SplashView.ink.opacity(d.2)))
        }
    }
}

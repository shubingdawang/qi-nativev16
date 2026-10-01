import SwiftUI

/// 开屏：夜里的一片静水。
///
/// 参考 motion-web 那份做法的主张——**动效是界面的材料，不是装饰**：
/// 要有物理（弹簧、阻尼），要有因果（手做了什么，才发生什么），不用透明度淡入淡出。
///
///   · 底下是她的壁纸，糊开、压暗，像水面上的倒影；一团光慢慢游
///   · 水面上浮着光尘：近的小而亮，远的大而虚（散景）。手指靠近，它们被推开，再慢慢漂回来
///   · 手指点下、划过：起涟漪，真的折射底下的画面（`SplashRipple.metal`）
///   · 右上角竖着写今天的日期和此刻，一个字一个字从水下浮上来
///   · 轻点：那一点起一圈大涟漪，水面从那儿向外让开，露出 App
///
/// 只在冷启动出现一次；设置里能关（`AppSettings.splashOn`）。
struct SplashView: View {

    var onEnter: () -> Void

    @State private var sim = PondSim()
    @State private var leaving = false
    /// 离场：从点下去的地方向外让开的那个圆
    @State private var revealR: CGFloat = 0
    @State private var revealAt: CGPoint = .zero
    @State private var lastRipple: CGPoint?
    @State private var dragStart: Date?
    @State private var risen = false
    /// 打开那一刻的日期和时间（竖排）。只算一次
    @State private var stamp = SplashView.timeColumns(Date())

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { tl in
                let now = tl.date
                scene(size: geo.size, now: now, safeTop: geo.safeAreaInsets.top,
                      safeBottom: geo.safeAreaInsets.bottom)
                    .layerEffect(ShaderLibrary.qiRipple(.floatArray(sim.shaderArgs(now: now))),
                                 maxSampleOffset: CGSize(width: 28, height: 28))
            }
            .mask { revealMask }
            .contentShape(Rectangle())
            .gesture(touch(size: geo.size))
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation { risen = true }
        }
    }

    // MARK: 画面

    private func scene(size: CGSize, now: Date, safeTop: CGFloat, safeBottom: CGFloat) -> some View {
        ZStack {
            // 倒影：壁纸糊开、放大一点（糊的边不露底）
            WallpaperBackground()
                .blur(radius: 16)
                .scaleEffect(1.12)
            // 夜色。白天浅一些，夜里深一些
            LinearGradient(colors: [Color(red: 0.04, green: 0.06, blue: 0.13).opacity(stamp.night ? 0.55 : 0.30),
                                    Color(red: 0.02, green: 0.03, blue: 0.08).opacity(stamp.night ? 0.78 : 0.50)],
                           startPoint: .top, endPoint: .bottom)

            // 光尘和那团游动的光
            Canvas { gc, sz in
                sim.step(now, size: sz)
                drawGlow(gc, size: sz, now: now)
                drawMotes(gc, now: now)
            }
            .allowsHitTesting(false)

            timeColumns
                .padding(.top, safeTop + 64)
                .padding(.trailing, 34)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)

            Text("轻点进入")
                .font(.system(size: 12, weight: .light, design: .serif))
                .tracking(6)
                .foregroundStyle(.white.opacity(0.62))
                .offset(y: risen ? 0 : 18)
                .blur(radius: risen ? 0 : 6)
                .animation(.spring(response: 1.2, dampingFraction: 0.8).delay(2.2), value: risen)
                .padding(.bottom, safeBottom + 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// 右上角竖排：右边一列是日期，左边一列是此刻。一个字一个字从水下浮上来
    private var timeColumns: some View {
        HStack(alignment: .top, spacing: 16) {
            column(stamp.time, startDelay: 0.9)
                .padding(.top, 34)
            column(stamp.date, startDelay: 0.35)
        }
    }

    private func column(_ text: String, startDelay: Double) -> some View {
        VStack(spacing: 7) {
            ForEach(Array(text.enumerated()), id: \.offset) { i, ch in
                Text(String(ch))
                    .font(.system(size: 21, weight: .light, design: .serif))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.35), radius: 6)
                    .offset(y: risen ? 0 : 16)
                    .blur(radius: risen ? 0 : 7)
                    .animation(.spring(response: 1.1, dampingFraction: 0.72)
                        .delay(startDelay + Double(i) * 0.11), value: risen)
            }
        }
    }

    /// 一团暖光在水面下慢慢游（李萨如轨迹，周期几十秒）
    private func drawGlow(_ gc: GraphicsContext, size: CGSize, now: Date) {
        let t = now.timeIntervalSinceReferenceDate
        let c = CGPoint(x: size.width * (0.5 + 0.28 * sin(t * 0.11)),
                        y: size.height * (0.42 + 0.18 * sin(t * 0.07 + 1.3)))
        let r = max(size.width, size.height) * 0.55
        var g = gc
        g.blendMode = .plusLighter
        g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
               with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.82, blue: 0.6).opacity(0.16),
                                                       Color(red: 1, green: 0.7, blue: 0.5).opacity(0.05),
                                                       .clear]),
                                     center: c, startRadius: 0, endRadius: r))
    }

    /// 光尘：近的是一颗亮点带一圈晕；远的是一片虚的光斑，边上一道淡淡的环（散景）
    private func drawMotes(_ gc: GraphicsContext, now: Date) {
        let t = now.timeIntervalSinceReferenceDate
        var g = gc
        g.blendMode = .plusLighter
        for m in sim.motes {
            let tw = 0.55 + 0.45 * pow(sin(t * m.twinkle + m.phase), 2)
            let color = m.warm ? Color(red: 1, green: 0.86, blue: 0.64) : Color(red: 0.82, green: 0.9, blue: 1)
            let r = m.r
            let rect = CGRect(x: m.p.x - r, y: m.p.y - r, width: r * 2, height: r * 2)
            if m.bokeh {
                g.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.07 * tw)))
                g.stroke(Path(ellipseIn: rect.insetBy(dx: 0.5, dy: 0.5)),
                         with: .color(color.opacity(0.10 * tw)), lineWidth: 1)
            } else {
                g.fill(Path(ellipseIn: rect),
                       with: .radialGradient(Gradient(colors: [color.opacity(0.95 * tw),
                                                               color.opacity(0.28 * tw), .clear]),
                                             center: m.p, startRadius: 0, endRadius: r))
            }
        }
    }

    // MARK: 手

    private func touch(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard !leaving else { return }
                if dragStart == nil { dragStart = Date() }
                let p = v.location
                sim.finger = p
                // 划过去：每隔一段起一圈小涟漪
                if lastRipple.map({ hypot($0.x - p.x, $0.y - p.y) > 42 }) ?? true {
                    sim.addRipple(at: p, amp: lastRipple == nil ? 0.8 : 0.45)
                    lastRipple = p
                }
            }
            .onEnded { v in
                defer { dragStart = nil; lastRipple = nil; sim.finger = nil }
                guard !leaving else { return }
                let moved = hypot(v.translation.width, v.translation.height)
                let quick = Date().timeIntervalSince(dragStart ?? Date()) < 0.35
                if moved < 10 && quick { leave(at: v.location, size: size) }
            }
    }

    // MARK: 离场

    /// 那一点起一圈大涟漪，水面从那儿向外让开（弹簧，不淡出）
    private func leave(at p: CGPoint, size: CGSize) {
        leaving = true
        sim.addRipple(at: p, amp: 1.6)
        revealAt = p
        let far = [CGPoint.zero, CGPoint(x: size.width, y: 0),
                   CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
            .map { hypot($0.x - p.x, $0.y - p.y) }.max() ?? size.height
        withAnimation(.spring(response: 1.0, dampingFraction: 0.92)) {
            revealR = far + 40
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { onEnter() }
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

    // MARK: 竖排的日期和时间

    struct Stamp { var date: String; var time: String; var night: Bool }

    static func timeColumns(_ d: Date) -> Stamp {
        let c = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: d)
        let mo = c.month ?? 1, day = c.day ?? 1, h = c.hour ?? 0, mi = c.minute ?? 0
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
        let h12 = h % 12 == 0 ? 12 : h % 12
        let hour = h12 == 2 ? "两" : cn(h12)
        let minute = mi == 0 ? "整" : (mi < 10 ? "零" + cn(mi) + "分" : cn(mi) + "分")
        return Stamp(date: cn(mo) + "月" + cn(day) + "日",
                     time: part + hour + "点" + minute,
                     night: h >= 19 || h < 6)
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

// MARK: - 模拟

/// 涟漪和光尘。每一帧由画的那一步推一下（见 `step`）。
///
/// ⚠️ 是个类：画的时候改它不触发重画——重画本来就由 `TimelineView` 按帧推着走。
final class PondSim {

    struct Ripple { var p: CGPoint; var born: Date; var amp: Float }

    struct Mote {
        var p: CGPoint
        var v: CGVector = .zero
        var r: CGFloat
        /// 远近：远的漂得慢、被手推得少
        var depth: CGFloat
        var bokeh: Bool
        var warm: Bool
        var phase: Double
        var twinkle: Double
    }

    private(set) var ripples: [Ripple] = []
    private(set) var motes: [Mote] = []
    var finger: CGPoint?
    private var last: Date?

    func addRipple(at p: CGPoint, amp: Float) {
        ripples.append(Ripple(p: p, born: Date(), amp: amp))
        if ripples.count > 10 { ripples.removeFirst(ripples.count - 10) }
    }

    /// 交给着色器的那串数：每圈四个（x, y, 几秒, 力）
    func shaderArgs(now: Date) -> [Float] {
        var a: [Float] = []
        for r in ripples {
            let age = Float(now.timeIntervalSince(r.born))
            if age < 4.5 { a += [Float(r.p.x), Float(r.p.y), age, r.amp] }
        }
        return a.isEmpty ? [0, 0, 99, 0] : a
    }

    func step(_ now: Date, size: CGSize) {
        guard size.width > 0 else { return }
        if motes.isEmpty { seed(size) }
        let dt = CGFloat(min(1.0 / 20, now.timeIntervalSince(last ?? now)))
        last = now
        let t = now.timeIntervalSinceReferenceDate

        for i in motes.indices {
            var m = motes[i]
            // 想去的速度：慢慢往上飘，左右轻轻摆
            let want = CGVector(dx: CGFloat(sin(t * 0.27 + m.phase)) * 9 * m.depth,
                                dy: (-7 - CGFloat(cos(t * 0.19 + m.phase * 1.7)) * 4) * m.depth)
            // 弹簧把速度拉回想去的速度（阻尼）
            m.v.dx += (want.dx - m.v.dx) * 1.4 * dt
            m.v.dy += (want.dy - m.v.dy) * 1.4 * dt
            // 手指推开
            if let f = finger {
                let dx = m.p.x - f.x, dy = m.p.y - f.y
                let d = max(1, hypot(dx, dy))
                if d < 170 {
                    let push = (1 - d / 170) * 1400 * m.depth
                    m.v.dx += dx / d * push * dt
                    m.v.dy += dy / d * push * dt
                }
            }
            // 涟漪的波前经过，也推一下
            for r in ripples {
                let age = CGFloat(now.timeIntervalSince(r.born))
                let dx = m.p.x - r.p.x, dy = m.p.y - r.p.y
                let d = max(1, hypot(dx, dy))
                let x = d - age * 240
                if abs(x) < 40 {
                    let k = CGFloat(r.amp) * exp(-age * 1.25) * 260 * m.depth
                    m.v.dx += dx / d * k * dt
                    m.v.dy += dy / d * k * dt
                }
            }
            m.p.x += m.v.dx * dt
            m.p.y += m.v.dy * dt
            // 出了边就从另一边回来
            let pad = m.r + 10
            if m.p.y < -pad { m.p.y = size.height + pad; m.p.x = .random(in: 0...size.width) }
            if m.p.y > size.height + pad { m.p.y = -pad }
            if m.p.x < -pad { m.p.x = size.width + pad }
            if m.p.x > size.width + pad { m.p.x = -pad }
            motes[i] = m
        }
        ripples.removeAll { now.timeIntervalSince($0.born) > 4.5 }
    }

    private func seed(_ size: CGSize) {
        for i in 0..<46 {
            let bokeh = i < 12
            motes.append(Mote(
                p: CGPoint(x: .random(in: 0...size.width), y: .random(in: 0...size.height)),
                r: bokeh ? .random(in: 16...34) : .random(in: 2...5.5),
                depth: bokeh ? .random(in: 0.35...0.6) : .random(in: 0.7...1.2),
                bokeh: bokeh,
                warm: Double.random(in: 0...1) < 0.6,
                phase: .random(in: 0...(2 * .pi)),
                twinkle: .random(in: 0.6...1.8)))
        }
    }
}

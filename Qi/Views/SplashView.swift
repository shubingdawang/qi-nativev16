import SwiftUI

/// 开屏：一扇起了雾的窗。
///
/// 她要的：「给我的前端搞一个有意思、有意境的交互开屏。」
/// 参考的是 motion-web 那份做法的主张——**动效是界面的材料，不是装饰**：
/// 要有物理（弹簧、阻尼、惯性），要有因果（手做了什么，才发生什么），
/// 不许用「透明度 0 → 1」那种糊弄的淡入淡出。
///
/// ## 为什么是雾窗
///
/// App 叫「栖」，她的壁纸是雨打在玻璃上。开屏就是那扇窗起了雾：
///   · 雾上有人用手指写过一个「栖」——那几笔透着后面清楚的壁纸
///   · 她的手指一划，雾就被擦开；擦开的地方过几秒慢慢又起雾
///   · 水珠在玻璃上**先停住、攒够了才滑**，一路把雾带开，滑到半路可能又卡住
///     （粘滞—滑动：真的水珠就是这么走的，不是匀速落下）
///   · 擦开四成左右，或者轻点一下：整片雾像一层冷凝水被重力拽下去，带一点回弹
///
/// 只在冷启动出现一次；设置里能关（`AppSettings.splashOn`）。
struct SplashView: View {

    var onEnter: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var sim = FogSim()
    /// 整片雾往下滑了多少（离场用，弹簧驱动）
    @State private var slide: CGFloat = 0
    @State private var leaving = false
    @State private var showHint = false
    @State private var dragStart: Date?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 雾后面那扇窗：清楚的壁纸
                WallpaperBackground()

                fogSheet(size: geo.size)
                    .offset(y: slide)

                // 玻璃上的水珠（画在雾外面，擦没擦开都看得见）
                TimelineView(.animation(paused: leaving)) { tl in
                    Canvas { gc, size in
                        sim.step(tl.date, size: size)
                        drawDrops(gc)
                    }
                }
                .offset(y: slide)
                .allowsHitTesting(false)

                if showHint && !leaving {
                    VStack {
                        Spacer()
                        Text("用手指擦开雾气 · 轻点进入")
                            .font(.app(12))
                            .foregroundStyle(.white.opacity(0.75))
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                            .padding(.bottom, geo.safeAreaInsets.bottom + 48)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if dragStart == nil { dragStart = Date() }
                        guard !leaving else { return }
                        sim.wipe(at: v.location)
                    }
                    .onEnded { v in
                        defer { dragStart = nil }
                        guard !leaving else { return }
                        let moved = hypot(v.translation.width, v.translation.height)
                        let quick = Date().timeIntervalSince(dragStart ?? Date()) < 0.3
                        // 轻点一下：进去。擦够了：也进去
                        if (moved < 8 && quick) || sim.clearedFraction > 0.4 {
                            leave(height: geo.size.height)
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { showHint = true }
            }
        }
    }

    // MARK: 雾

    /// 雾那一层：糊掉的壁纸 + 一层水汽的白，按「擦开了哪儿」挖掉
    private func fogSheet(size: CGSize) -> some View {
        ZStack {
            WallpaperBackground()
                .blur(radius: 26)
            Rectangle()
                .fill(scheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.32))
        }
        .compositingGroup()
        .mask {
            TimelineView(.animation(paused: leaving)) { tl in
                Canvas { gc, sz in
                    // 先整片是雾
                    gc.fill(Path(CGRect(origin: .zero, size: sz)), with: .color(.black))
                    gc.blendMode = .destinationOut
                    let now = tl.date
                    // 手指擦开的、水珠带开的：越新越清楚，慢慢又起雾
                    for m in sim.marks {
                        let clear = sim.clearness(of: m, now: now)
                        guard clear > 0.01 else { continue }
                        let r = m.r
                        let rect = CGRect(x: m.p.x - r, y: m.p.y - r, width: r * 2, height: r * 2)
                        gc.fill(Path(ellipseIn: rect), with: .color(.black.opacity(clear)))
                    }
                    // 雾上写着的那个「栖」
                    var ink = gc
                    ink.opacity = 0.55
                    ink.draw(Text("栖").font(.system(size: min(sz.width, sz.height) * 0.36,
                                                      weight: .ultraLight, design: .serif)),
                             at: CGPoint(x: sz.width / 2, y: sz.height * 0.42))
                }
            }
        }
    }

    /// 水珠：一颗亮的椭圆 + 下沿一道暗边 + 左上一个高光点，看着才像立在玻璃上的水
    private func drawDrops(_ gc: GraphicsContext) {
        for d in sim.drops {
            let w = d.r * 1.6, h = d.r * 2
            let rect = CGRect(x: d.x - w / 2, y: d.y - h / 2, width: w, height: h)
            let body = Path(ellipseIn: rect)
            gc.fill(body, with: .color(.white.opacity(0.16)))
            gc.stroke(body, with: .color(.black.opacity(0.18)), lineWidth: 0.8)
            let hl = CGRect(x: rect.minX + w * 0.22, y: rect.minY + h * 0.18,
                            width: w * 0.28, height: h * 0.22)
            gc.fill(Path(ellipseIn: hl), with: .color(.white.opacity(0.7)))
        }
    }

    // MARK: 离场

    /// 整片雾被重力拽下去——弹簧带一点回弹，不淡出。
    /// 雾滑走之后这一层就没了，下面就是 App。
    private func leave(height: CGFloat) {
        leaving = true
        withAnimation(.spring(response: 0.75, dampingFraction: 0.78)) {
            slide = height * 1.08
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { onEnter() }
    }
}

// MARK: - 模拟

/// 雾和水珠。每一帧由画的那一步推一下（见 `step`）。
///
/// ⚠️ 是个类：画的时候改它不触发重画——重画本来就由 `TimelineView` 按帧推着走。
final class FogSim {

    struct Mark {
        var p: CGPoint
        var r: CGFloat
        var born: Date
        /// 手指擦的（算进「擦开了多少」），还是水珠带的（不算）
        var byHand: Bool
    }

    struct Drop {
        var x: CGFloat
        var y: CGFloat
        var r: CGFloat
        var vy: CGFloat = 0
        /// 还要停多久（粘滞）。攒够了才滑
        var rest: Double
        var lastTrailY: CGFloat
        var seed: Double
    }

    private(set) var marks: [Mark] = []
    private(set) var drops: [Drop] = []
    private var last: Date?
    private var size: CGSize = .zero
    private var handArea: CGFloat = 0

    /// 擦开的地方多久起满雾
    private let refog: Double = 7
    /// 重力（点/秒²）和阻力：终端速度大约一百五十点每秒——水珠在玻璃上是被拖着走的
    private let gravity: CGFloat = 900
    private let drag: CGFloat = 6

    /// 手指擦开了大约多少（面积之和，重叠会多算一些，所以门槛放在 0.4）
    var clearedFraction: CGFloat {
        guard size.width > 0 else { return 0 }
        return handArea / (size.width * size.height)
    }

    /// 这一处现在还有多清楚：刚擦开是全清，先保持一会儿，再慢慢起雾
    func clearness(of m: Mark, now: Date) -> Double {
        let age = now.timeIntervalSince(m.born)
        let t = max(0, min(1, age / refog))
        return 1 - t * t
    }

    func wipe(at p: CGPoint) {
        // 跟上一笔离得太近就不另加一个点，省得一秒攒几百个
        if let lastMark = marks.last(where: { $0.byHand }),
           hypot(lastMark.p.x - p.x, lastMark.p.y - p.y) < 6 { return }
        let r: CGFloat = 34
        marks.append(Mark(p: p, r: r, born: Date(), byHand: true))
        handArea += .pi * r * r * 0.55
    }

    func step(_ now: Date, size: CGSize) {
        self.size = size
        let dt = CGFloat(min(1.0 / 20, now.timeIntervalSince(last ?? now)))
        last = now
        guard size.width > 0 else { return }

        // 玻璃上一直有十来颗水珠
        if drops.count < 12, Double.random(in: 0...1) < 0.05 {
            let y = CGFloat.random(in: 0...(size.height * 0.6))
            drops.append(Drop(x: .random(in: 12...(size.width - 12)), y: y,
                              r: .random(in: 3...7), rest: .random(in: 0.3...2.5),
                              lastTrailY: y, seed: .random(in: 0...10)))
        }

        for i in drops.indices {
            if drops[i].rest > 0 {
                // 粘住：攒着
                drops[i].rest -= Double(dt)
                drops[i].vy = 0
                continue
            }
            // 滑：重力往下拉，阻力往回拽
            drops[i].vy += (gravity - drag * drops[i].vy) * dt
            drops[i].y += drops[i].vy * dt
            // 横向是一格一格抖的（十一赫兹量化），不是平滑的正弦——水珠碰到玻璃上的颗粒
            let tick = Double(Int(now.timeIntervalSinceReferenceDate * 11))
            drops[i].x += CGFloat(sin(tick * 1.7 + drops[i].seed)) * 0.35
            // 一路带开一道雾
            if drops[i].y - drops[i].lastTrailY > 5 {
                marks.append(Mark(p: CGPoint(x: drops[i].x, y: drops[i].y),
                                  r: drops[i].r * 0.9, born: now, byHand: false))
                drops[i].lastTrailY = drops[i].y
            }
            // 半路又被卡住
            if Double.random(in: 0...1) < Double(dt) * 0.9 {
                drops[i].rest = .random(in: 0.2...1.0)
            }
        }
        drops.removeAll { $0.y > size.height + 20 }
        // 起满雾的就不用再记了
        marks.removeAll { clearness(of: $0, now: now) <= 0.001 }
    }
}

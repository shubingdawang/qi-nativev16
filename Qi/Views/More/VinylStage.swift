import SwiftUI

/// 「一起听」的唱片页：一张在转的唱片，几只小螃蟹围着组乐队。
///
/// 三种样子可选（毛玻璃 / 极简 / 唱片套），右上角切换。背景都是壁纸。
/// 小螃蟹的位置她自己摆：点一下解锁（虚线圈起来），拖到想放的地方，双击锁住。
/// 每种样子各记一份位置。
enum VinylStyle: String, CaseIterable, Identifiable {
    case glass, minimal, sleeve
    var id: String { rawValue }
    var label: String {
        switch self {
        case .glass: return "毛玻璃"
        case .minimal: return "极简"
        case .sleeve: return "唱片套"
        }
    }
}

struct VinylStage: View {

    let track: Track?
    let playing: Bool

    @EnvironmentObject private var app: AppState
    @AppStorage("vinylStyle") private var styleRaw = VinylStyle.glass.rawValue
    @AppStorage("vinylBand") private var bandRaw = ""
    @AppStorage("listenDay") private var listenDay = ""
    @AppStorage("listenSeconds") private var listenSeconds = 0.0

    @State private var spinBase: Double = 0
    @State private var spinStart: Date?
    @State private var unlocked: Set<String> = []
    @State private var drag: [String: CGSize] = [:]
    @State private var tick: Task<Void, Never>?

    private var style: VinylStyle { VinylStyle(rawValue: styleRaw) ?? .glass }

    /// 乐队：哪只、播哪段动图
    struct Member: Identifiable {
        let id: String
        let gif: String
    }

    static let band: [Member] = [
        Member(id: "listening", gif: "clawd-listening"), Member(id: "piano", gif: "clawd-piano"),
        Member(id: "guitar", gif: "clawd-guitar"), Member(id: "singing", gif: "clawd-singing"),
        Member(id: "dancing", gif: "clawd-dancing")
    ]

    /// 默认站位（占舞台宽高的比例）
    private func defaults(_ s: VinylStyle) -> [String: CGPoint] {
        switch s {
        case .glass:
            return ["listening": .init(x: 0.5, y: 0.1), "piano": .init(x: 0.84, y: 0.68),
                    "guitar": .init(x: 0.14, y: 0.7), "singing": .init(x: 0.38, y: 0.9),
                    "dancing": .init(x: 0.64, y: 0.92)]
        case .minimal:
            return ["listening": .init(x: 0.14, y: 0.9), "piano": .init(x: 0.32, y: 0.9),
                    "guitar": .init(x: 0.5, y: 0.9), "singing": .init(x: 0.68, y: 0.9),
                    "dancing": .init(x: 0.86, y: 0.9)]
        case .sleeve:
            return ["listening": .init(x: 0.3, y: 0.12), "piano": .init(x: 0.86, y: 0.72),
                    "guitar": .init(x: 0.12, y: 0.82), "singing": .init(x: 0.4, y: 0.92),
                    "dancing": .init(x: 0.66, y: 0.92)]
        }
    }

    private var saved: [String: [String: [Double]]] {
        (try? JSONDecoder().decode([String: [String: [Double]]].self, from: Data(bandRaw.utf8))) ?? [:]
    }

    private func spot(_ id: String) -> CGPoint {
        if let v = saved[style.rawValue]?[id], v.count == 2 { return CGPoint(x: v[0], y: v[1]) }
        return defaults(style)[id] ?? CGPoint(x: 0.5, y: 0.5)
    }

    private func save(_ id: String, _ p: CGPoint) {
        var all = saved
        var mine = all[style.rawValue] ?? [:]
        mine[id] = [Double(p.x), Double(p.y)]
        all[style.rawValue] = mine
        if let d = try? JSONEncoder().encode(all) { bandRaw = String(decoding: d, as: UTF8.self) }
    }

    // MARK: 转

    /// 一圈 6 秒。暂停就停在原处，再放接着转
    private static let degPerSec = 60.0

    private func angle(_ now: Date) -> Double {
        spinBase + (spinStart.map { now.timeIntervalSince($0) } ?? 0) * Self.degPerSec
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation(paused: !playing && unlocked.isEmpty)) { ctx in
                let now = ctx.date
                ZStack(alignment: .topLeading) {
                    record(size: size, now: now)
                    ForEach(Self.band) { m in member(m.id, gif: m.gif, size: size, now: now) }
                    togetherPill
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    if !unlocked.isEmpty {
                        Text("拖到想放的地方，双击锁住")
                            .font(.app(11))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(.ultraThinMaterial))
                            .frame(maxWidth: .infinity)
                            .offset(y: size.height - 26)
                    }
                }
            }
        }
        .onAppear {
            if playing { spinStart = Date() }
            startCounting()
        }
        .onDisappear { tick?.cancel() }
        .onChange(of: playing) { _, on in
            if on {
                spinStart = Date()
            } else if let s = spinStart {
                spinBase += Date().timeIntervalSince(s) * Self.degPerSec
                spinStart = nil
            }
        }
    }

    // MARK: 一起听了多久（今天）

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func startCounting() {
        tick?.cancel()
        tick = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let today = Self.dayFormat.string(from: Date())
                if listenDay != today { listenDay = today; listenSeconds = 0 }
                if playing { listenSeconds += 1 }
            }
        }
    }

    private var togetherPill: some View {
        let mins = Int(listenSeconds / 60)
        return HStack(spacing: 6) {
            HStack(spacing: -8) {
                avatar(app.settings.userAvatarName)
                avatar(app.settings.aiAvatarName)
            }
            Text("一起听 \(mins) 分钟")
                .font(.app(11.5, weight: .medium))
        }
        .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 4)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 0.6))
    }

    private func avatar(_ name: String?) -> some View {
        Group {
            if let n = name, let img = ImageStore.thumb(n, maxPixel: 90) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 1.2))
    }

    // MARK: 摆位

    private struct DiscLayout {
        var center: CGPoint
        var d: CGFloat
        /// 唱片套（只有唱片套那一版有）
        var sleeve: CGRect?
    }

    private func layout(_ size: CGSize) -> DiscLayout {
        switch style {
        case .sleeve:
            let s = size.width * 0.6
            let r = CGRect(x: size.width * 0.06, y: size.height * 0.2, width: s, height: s)
            return DiscLayout(center: CGPoint(x: r.midX + s * 0.42, y: r.midY), d: s * 0.94, sleeve: r)
        default:
            let d = min(size.width * 0.66, size.height * 0.56)
            return DiscLayout(center: CGPoint(x: size.width / 2, y: size.height * 0.45), d: d, sleeve: nil)
        }
    }

    // MARK: 唱片

    private func record(size: CGSize, now: Date) -> some View {
        let l = layout(size)
        return ZStack(alignment: .topLeading) {
            disc(d: l.d)
                .rotationEffect(.degrees(angle(now)))
                .frame(width: l.d, height: l.d)
                .position(l.center)
            // 唱片套盖在唱片前面：唱片从里面滑出一半
            if let r = l.sleeve {
                sleeve(side: r.width)
                    .rotationEffect(.degrees(-4))
                    .position(x: r.midX, y: r.midY)
            }
            if style != .sleeve { tonearm(l) }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func sleeve(side: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let t = track {
                    TrackArtwork(track: t, side: side)
                } else {
                    Color.gray.opacity(0.25)
                }
            }
            .frame(width: side, height: side)
            RoundedRectangle(cornerRadius: 3)
                .stroke(.white.opacity(0.55), lineWidth: 1)
                .padding(10)
            Text("SIDE A")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Color(hexString: "9A6F7E")!)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color(hexString: "FFFAF3")!))
                .rotationEffect(.degrees(6))
                .padding(14)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.white.opacity(0.6), lineWidth: 1))
        .shadow(color: Color(red: 0.35, green: 0.24, blue: 0.2).opacity(0.25), radius: 13, y: 14)
    }

    @ViewBuilder
    private func disc(d: CGFloat) -> some View {
        let label = d * 0.36
        ZStack {
            switch style {
            case .glass:
                Circle().fill(RadialGradient(colors: [Color(hexString: "FFC9DC")!.opacity(0.65),
                                                      Color(hexString: "F2A9C8")!.opacity(0.7),
                                                      Color(hexString: "D6AAE8")!.opacity(0.7)],
                                             center: .center, startRadius: label / 2, endRadius: d / 2))
                grooves(d: d, color: .white.opacity(0.35))
                Circle().fill(AngularGradient(colors: [.clear, .white.opacity(0.5), .clear, .clear,
                                                       .white.opacity(0.35), .clear, .clear],
                                              center: .center))
                Circle().stroke(.white.opacity(0.8), lineWidth: 1)
            case .minimal:
                // 只留一道外圈，不画纹路
                Circle().fill(Color(hexString: "FBFAF8")!)
                Circle().inset(by: 0.9).stroke(Color(hexString: "B9B2AB")!, lineWidth: 1.8)
            case .sleeve:
                Circle().fill(Color(hexString: "26201F")!)
                grooves(d: d, color: .white.opacity(0.07))
                Circle().fill(AngularGradient(colors: [.clear, Color(hexString: "FFF0E6")!.opacity(0.2), .clear,
                                                       .clear, Color(hexString: "FFF0E6")!.opacity(0.14), .clear],
                                              center: .center))
            }
            // 贴纸：歌的封面
            Group {
                if let t = track {
                    TrackArtwork(track: t, side: label)
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .frame(width: label, height: label)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(style == .sleeve ? 0.3 : 0.8), lineWidth: 1.5))
            curvedText(radius: label / 2 + d * 0.045, size: max(7, d * 0.03))
            Circle()
                .fill(style == .sleeve ? Color(hexString: "F4E7DC")! : .white)
                .frame(width: max(5, d * 0.03), height: max(5, d * 0.03))
        }
        .frame(width: d, height: d)
        .shadow(color: .black.opacity(style == .minimal ? 0.05 : 0.22),
                radius: style == .minimal ? 6 : 14, y: 8)
    }

    private func grooves(d: CGFloat, color: Color) -> some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                Circle()
                    .inset(by: d * (0.07 + CGFloat(i) * 0.035))
                    .stroke(color, lineWidth: 0.6)
            }
        }
    }

    /// 贴纸外面那一圈小字：歌名 · SIDE A · 日期
    private func curvedText(radius: CGFloat, size: CGFloat) -> some View {
        let title = (track?.title ?? "").uppercased()
        let text = Array((title.isEmpty ? "TOGETHER" : title) + " · SIDE A · " + Self.dayFormat.string(from: Date()) + " · ")
        let color: Color = {
            switch style {
            case .glass: return Color(hexString: "A0708A")!
            case .minimal: return Color(hexString: "A39D97")!
            case .sleeve: return Color(hexString: "FFECE0")!.opacity(0.75)
            }
        }()
        return Canvas { gc, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let step = min(0.16, (2 * Double.pi * 0.86) / Double(max(text.count, 1)))
            for (i, ch) in text.enumerated() {
                let a = -Double.pi / 2 + Double(i) * step
                var g = gc
                g.translateBy(x: c.x + CGFloat(cos(a)) * radius, y: c.y + CGFloat(sin(a)) * radius)
                g.rotate(by: .radians(a + .pi / 2))
                g.draw(Text(String(ch)).font(.system(size: size, weight: .medium)).foregroundColor(color),
                       at: .zero)
            }
        }
        .allowsHitTesting(false)
    }

    /// 唱臂：压在唱片上面。支点在唱片右上角外面；放歌时唱针落在外圈纹路上，停了抬到唱片外
    private func tonearm(_ l: DiscLayout) -> some View {
        let d = l.d
        let len = d * 0.62
        let pivot = CGPoint(x: l.center.x + d * 0.46, y: l.center.y - d * 0.46)
        let metal: Color = style == .minimal ? Color(hexString: "B3ACA5")! : .white
        let ring: Color = style == .minimal ? Color(hexString: "ECE8E3")! : .white.opacity(0.5)
        let w = max(3, d * 0.016)
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .top) {
                Capsule().fill(metal).frame(width: w, height: len)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(metal)
                    .frame(width: d * 0.06, height: d * 0.1)
                    .offset(y: len - d * 0.02)
            }
            .frame(width: d * 0.06, height: len + d * 0.08, alignment: .top)
            .rotationEffect(.degrees(playing ? 12 : -4), anchor: .top)
            .animation(.easeInOut(duration: 0.8), value: playing)
            .shadow(color: .black.opacity(0.22), radius: 3, x: 2, y: 4)
            .position(x: pivot.x, y: pivot.y + (len + d * 0.08) / 2)
            Circle()
                .fill(metal)
                .frame(width: d * 0.12, height: d * 0.12)
                .overlay(Circle().stroke(.black.opacity(0.12), lineWidth: 1))
                .padding(d * 0.02)
                .background(Circle().fill(ring))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                .position(pivot)
        }
        .allowsHitTesting(false)
    }

    // MARK: 小螃蟹

    private func member(_ id: String, gif: String, size: CGSize, now: Date) -> some View {
        let side = min(size.width * 0.2, 80)
        let p = spot(id)
        let open = unlocked.contains(id)
        let t = now.timeIntervalSinceReferenceDate
        let bob = playing && !open ? CGFloat(abs(sin(t * 4 + Double(id.count)))) * -3 : 0
        let off = drag[id] ?? .zero
        return ClawdGifView(name: gif, size: side)
            .frame(width: side, height: side)
            .overlay {
                if open {
                    Circle()
                        .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.25), radius: 2)
                        .frame(width: side * 0.7, height: side * 0.7)
                        .offset(y: side * 0.22)
                }
            }
            .scaleEffect(open ? 1.08 : 1)
            .contentShape(Rectangle())
            .position(x: p.x * size.width + off.width, y: p.y * size.height + off.height + bob)
            .onTapGesture(count: 2) {
                withAnimation(.easeOut(duration: 0.15)) { _ = unlocked.remove(id) }
            }
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) { _ = unlocked.insert(id) }
            }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in drag[id] = v.translation }
                    .onEnded { v in
                        drag[id] = nil
                        let np = CGPoint(
                            x: min(max(p.x + v.translation.width / max(size.width, 1), 0.05), 0.95),
                            y: min(max(p.y + v.translation.height / max(size.height, 1), 0.05), 0.98))
                        save(id, np)
                    },
                including: open ? .all : .subviews
            )
    }
}

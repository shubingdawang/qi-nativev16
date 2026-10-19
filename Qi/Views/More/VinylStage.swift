import SwiftUI

/// 「一起听」的唱片页：一张在转的唱片，几只小螃蟹围着组乐队。
///
/// 三种样子可选（毛玻璃 / 极简 / 唱片套），右上角切换。背景都是壁纸。
/// 小螃蟹的位置她自己摆：点一下解锁（虚线圈起来），拖到想放的地方，双击锁住。
/// 每种样子各记一份位置。
enum VinylStyle: String, CaseIterable, Identifiable {
    case tint, glass, minimal, sleeve
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tint: return "彩胶"
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
    @AppStorage("vinylStyle") private var styleRaw = VinylStyle.tint.rawValue
    @AppStorage("vinylBand") private var bandRaw = ""
    /// 一起听了多久（放歌的时候记，见 `MusicPlayer`），一直累加
    @AppStorage("listenTotalSeconds") private var listenSeconds = 0.0
    @Environment(\.colorScheme) private var scheme

    @State private var spinBase: Double = 0
    @State private var spinStart: Date?
    @State private var unlocked: Set<String> = []
    @State private var tick: Task<Void, Never>?

    private var style: VinylStyle { VinylStyle(rawValue: styleRaw) ?? .tint }

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
        case .tint:
            return ["listening": .init(x: 0.12, y: 0.82), "piano": .init(x: 0.88, y: 0.84),
                    "guitar": .init(x: 0.3, y: 0.94), "singing": .init(x: 0.52, y: 0.95),
                    "dancing": .init(x: 0.72, y: 0.94)]
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
        // ⚠️ 外面这一层**不跟着时间走**：每一帧只重画唱片那一块的角度
        // （见 `record`），小螃蟹各管各的。以前整页一起按帧重画，拖小螃蟹会卡
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                    record(size: size)
                    ForEach(Self.band) { m in
                        BandCrab(id: m.id, gif: m.gif, spot: spot(m.id), stage: size,
                                 playing: playing, unlocked: $unlocked) { save(m.id, $0) }
                    }
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
        .onAppear {
            if playing { spinStart = Date() }
        }
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

    private var togetherPill: some View {
        let total = Int(listenSeconds / 60)
        let text = total >= 60 ? "一起听 \(total / 60) 小时 \(total % 60) 分钟" : "一起听 \(total) 分钟"
        return HStack(spacing: 6) {
            HStack(spacing: -8) {
                avatar(app.settings.userAvatarName)
                avatar(app.settings.aiAvatarName)
            }
            Text(text)
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

    private func record(size: CGSize) -> some View {
        let l = layout(size)
        let key = "\(style.rawValue)|\(track?.id.uuidString ?? "")|\(Int(l.d))|\(scheme == .dark ? "d" : "l")"
        return ZStack(alignment: .topLeading) {
            // 只有角度按帧变；唱片本身（封面、那圈字）包成不变的一块，不跟着重画
            TimelineView(.animation(paused: !playing)) { ctx in
                Frozen(key: key) { disc(d: l.d) }
                    .equatable()
                    .rotationEffect(.degrees(angle(ctx.date)))
            }
            .frame(width: l.d, height: l.d)
            // 反光：不跟着转，像灯照在唱片上
            .overlay(
                Circle().fill(LinearGradient(stops: [
                    .init(color: .white.opacity(0.38), location: 0),
                    .init(color: .white.opacity(0), location: 0.32),
                    .init(color: .white.opacity(0), location: 0.64),
                    .init(color: .white.opacity(0.18), location: 0.82),
                    .init(color: .white.opacity(0), location: 1)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .allowsHitTesting(false)
            )
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
    /// 唱片：封面做成一张大贴纸，占唱片大半；外面只留一圈细纹。
    /// 反光不在这里画——它不跟着转（见 `record` 里的 `gloss`）
    private func disc(d: CGFloat) -> some View {
        let label = d * (style == .tint ? 0.36 : 0.66)
        ZStack {
            switch style {
            case .tint:
                // 彩胶：拿封面糊开当唱片本身的颜色，半透明，透出后面的底；中间贴一小张封面
                Circle().fill(.ultraThinMaterial)
                if let t = track {
                    TrackArtwork(track: t, side: d)
                        .frame(width: d, height: d)
                        .blur(radius: d * 0.07)
                        .saturation(1.25)
                        .opacity(0.72)
                        .clipShape(Circle())
                }
                Circle().fill(.white.opacity(scheme == .dark ? 0.04 : 0.14))
                grooves(d: d, color: .white.opacity(0.28))
                Circle().stroke(.white.opacity(0.65), lineWidth: 1)
                // 贴纸外面一圈亮一点的空槽
                Circle().stroke(.white.opacity(0.35), lineWidth: d * 0.035)
                    .frame(width: label + d * 0.07, height: label + d * 0.07)
            case .glass:
                // 真的毛玻璃：透出后面的壁纸，只压一层很淡的白，跟背景融在一起
                Circle().fill(.ultraThinMaterial)
                Circle().fill(.white.opacity(scheme == .dark ? 0.06 : 0.18))
                grooves(d: d, color: .white.opacity(0.32))
                Circle().stroke(.white.opacity(0.7), lineWidth: 1)
            case .minimal:
                // 浅色是白唱片，深色是黑胶
                if scheme == .dark {
                    Circle().fill(Color(hexString: "1A191B")!)
                    grooves(d: d, color: .white.opacity(0.09))
                    Circle().inset(by: 0.9).stroke(Color(hexString: "3E3A3D")!, lineWidth: 1.8)
                } else {
                    Circle().fill(Color(hexString: "FBFAF8")!)
                    grooves(d: d, color: Color(hexString: "E4DFD9")!)
                    Circle().inset(by: 0.9).stroke(Color(hexString: "B9B2AB")!, lineWidth: 1.8)
                }
            case .sleeve:
                Circle().fill(Color(hexString: "1D1A1A")!)
                grooves(d: d, color: .white.opacity(0.08))
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
            // 贴纸边上一道压痕：里面一圈暗、外面一圈亮
            .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1.5))
            .overlay(Circle().inset(by: -2).stroke(.white.opacity(style == .minimal && scheme != .dark ? 0.6 : 0.1), lineWidth: 1.5))
            Circle()
                .fill(style == .sleeve ? Color(hexString: "F4E7DC")! : .white)
                .frame(width: max(5, d * 0.03), height: max(5, d * 0.03))
        }
        .frame(width: d, height: d)
        .shadow(color: .black.opacity(style == .minimal ? 0.05 : 0.22),
                radius: style == .minimal ? 6 : 14, y: 8)
    }

    /// 细纹只在贴纸外面那一圈
    private func grooves(d: CGFloat, color: Color) -> some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                Circle()
                    .inset(by: d * (0.03 + CGFloat(i) * 0.019))
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
            case .tint, .glass: return Color(hexString: "A0708A")!
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

}

/// 内容不变就不重画的一块（只认 key）
private struct Frozen<Content: View>: View, Equatable {
    let key: String
    @ViewBuilder let content: () -> Content

    static func == (a: Frozen, b: Frozen) -> Bool { a.key == b.key }

    var body: some View { content() }
}

/// 乐队里的一只。拖动、晃动都只动它自己，不惊动整页
private struct BandCrab: View {
    let id: String
    let gif: String
    let spot: CGPoint
    let stage: CGSize
    let playing: Bool
    @Binding var unlocked: Set<String>
    var onMoved: (CGPoint) -> Void

    @State private var drag: CGSize = .zero

    private var open: Bool { unlocked.contains(id) }

    var body: some View {
        let side = min(stage.width * 0.2, 80)
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !playing || open)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let bob = playing && !open ? CGFloat(abs(sin(t * 4 + Double(id.count)))) * -3 : 0
            ClawdGifView(name: gif, size: side)
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
                .offset(y: bob)
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .offset(drag)
        .onTapGesture(count: 2) {
            withAnimation(.easeOut(duration: 0.15)) { _ = unlocked.remove(id) }
        }
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) { _ = unlocked.insert(id) }
        }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { v in drag = v.translation }
                .onEnded { v in
                    let np = CGPoint(
                        x: min(max(spot.x + v.translation.width / max(stage.width, 1), 0.05), 0.95),
                        y: min(max(spot.y + v.translation.height / max(stage.height, 1), 0.05), 0.98))
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        drag = .zero
                        onMoved(np)
                    }
                },
            including: open ? .all : .subviews
        )
        .position(x: spot.x * stage.width, y: spot.y * stage.height)
    }
}

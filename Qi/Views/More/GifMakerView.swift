import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

// MARK: - 动图工坊
//
// 一张图 → 会动的表情包：图自己怎么动、身边飘什么、写一句什么字、字怎么动。
// 预览和导出走**同一个画法**（`GifFrame.draw`），看到什么存下来就是什么。
// 一圈 24 帧，存成 GIF 进表情库。

struct GifSpec {
    var motion: GifMotion = .bounce
    var effect: GifEffect = .none
    var text = ""
    /// 字的中心在画面上的位置（0…1）
    var textX: Double = 0.5
    var textY: Double = 0.86
    var textSize: Double = 0.15
    var textColor = "FFFFFF"
    var strokeColor = "4A3442"
    /// 描边多粗（占字号的比例）。0 = 不描
    var strokeWidth: Double = 0.09
    var font: GifFont = .rounded
    var textAnim: GifTextAnim = .none
    /// 一圈多快（1 = 两秒一圈）
    var speed: Double = 1
    /// 像素图：放大不糊
    var pixel = false
    var whiteBG = false
    /// 图占画面多大
    var imageScale: Double = 0.74

    static let frames = 24
}

enum GifMotion: String, CaseIterable, Identifiable {
    case none, bounce, shake, heartbeat, jelly, float, jitter, walk, spin, pop, zoom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "不动"
        case .bounce: return "蹦跳"
        case .shake: return "摇头"
        case .heartbeat: return "心跳"
        case .jelly: return "果冻"
        case .float: return "飘着"
        case .jitter: return "气得发抖"
        case .walk: return "走路"
        case .spin: return "转圈"
        case .pop: return "冒出来"
        case .zoom: return "怼脸"
        }
    }
}

enum GifEffect: String, CaseIterable, Identifiable {
    case none, hearts, sparkles, rain, sweat, anger, notes, petals, sleepy, question, fire, tears
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "无"
        case .hearts: return "冒爱心"
        case .sparkles: return "闪闪"
        case .rain: return "下雨"
        case .sweat: return "流汗"
        case .anger: return "生气"
        case .notes: return "哼歌"
        case .petals: return "飘花"
        case .sleepy: return "犯困"
        case .question: return "问号"
        case .fire: return "燃起来"
        case .tears: return "掉眼泪"
        }
    }
    var glyph: String {
        switch self {
        case .none: return ""
        case .hearts: return "💕"
        case .sparkles: return "✨"
        case .rain: return "💧"
        case .sweat: return "💦"
        case .anger: return "💢"
        case .notes: return "🎵"
        case .petals: return "🌸"
        case .sleepy: return "💤"
        case .question: return "❓"
        case .fire: return "🔥"
        case .tears: return "💧"
        }
    }
}

enum GifFont: String, CaseIterable, Identifiable {
    case rounded, heavy, serif, mono
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rounded: return "圆润"
        case .heavy: return "粗黑"
        case .serif: return "宋体"
        case .mono: return "像素感"
        }
    }
    func ui(_ size: CGFloat) -> UIFont {
        switch self {
        case .rounded:
            let base = UIFont.systemFont(ofSize: size, weight: .heavy)
            return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        case .heavy:
            return UIFont.systemFont(ofSize: size, weight: .black)
        case .serif:
            return UIFont(name: "STSongti-SC-Black", size: size)
                ?? UIFont(name: "STSongti-SC-Bold", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .bold)
        case .mono:
            return UIFont.monospacedSystemFont(ofSize: size, weight: .heavy)
        }
    }
}

enum GifTextAnim: String, CaseIterable, Identifiable {
    case none, type, hop, blink, shake, grow
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "不动"
        case .type: return "一个个打出来"
        case .hop: return "一跳一跳"
        case .blink: return "闪"
        case .shake: return "抖"
        case .grow: return "一下变大"
        }
    }
}

// MARK: - 一帧怎么画

enum GifFrame {

    /// 在当前 UIKit 画布上画第 t（0…1）那一刻。画布左上是原点、y 向下
    static func draw(_ image: UIImage?, spec: GifSpec, side: CGFloat, t: Double) {
        guard let g = UIGraphicsGetCurrentContext() else { return }
        if spec.whiteBG {
            g.setFillColor(UIColor.white.cgColor)
            g.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        // 身后那一层特效（下雨、飘花）
        if [.rain, .petals].contains(spec.effect) {
            drawEffect(spec.effect, side: side, t: t)
        }
        if let image { drawImage(image, spec: spec, side: side, t: t, in: g) }
        if ![.rain, .petals, .none].contains(spec.effect) {
            drawEffect(spec.effect, side: side, t: t)
        }
        drawText(spec, side: side, t: t)
    }

    private static func drawImage(_ image: UIImage, spec: GifSpec, side: CGFloat, t: Double, in g: CGContext) {
        let iw = image.size.width, ih = image.size.height
        guard iw > 0, ih > 0 else { return }
        let box = side * CGFloat(spec.imageScale)
        let fit = min(box / iw, box / ih)
        let w = iw * fit, h = ih * fit
        let m = motion(spec.motion, t: t)
        g.saveGState()
        g.interpolationQuality = spec.pixel ? .none : .high
        // 绕脚底变形（蹦跳、果冻落地时是脚底不动）
        let cx = side / 2 + CGFloat(m.dx) * side
        let footY = side / 2 + h / 2 + CGFloat(m.dy) * side
        g.translateBy(x: cx, y: footY)
        g.rotate(by: CGFloat(m.rot) * .pi / 180)
        g.scaleBy(x: CGFloat(m.sx), y: CGFloat(m.sy))
        g.setAlpha(CGFloat(m.alpha))
        image.draw(in: CGRect(x: -w / 2, y: -h, width: w, height: h))
        g.restoreGState()
    }

    struct Pose { var dx = 0.0, dy = 0.0, rot = 0.0, sx = 1.0, sy = 1.0, alpha = 1.0 }

    static func motion(_ m: GifMotion, t: Double) -> Pose {
        var p = Pose()
        let tau = 2 * Double.pi
        switch m {
        case .none: break
        case .bounce:
            let ph = (t * 2).truncatingRemainder(dividingBy: 1)
            p.dy = -abs(sin(ph * .pi)) * 0.10
            // 落地那一下扁一点
            if ph < 0.12 || ph > 0.88 { p.sx = 1.08; p.sy = 0.9 }
        case .shake:
            p.rot = sin(t * tau * 2) * 10
        case .heartbeat:
            let ph = t.truncatingRemainder(dividingBy: 1)
            // 咚、咚：一大一小两下
            var beat = 0.0
            if ph < 0.15 {
                beat = sin(ph / 0.15 * .pi)
            } else if ph > 0.25 && ph < 0.4 {
                beat = sin((ph - 0.25) / 0.15 * .pi) * 0.7
            }
            p.sx = 1 + beat * 0.12; p.sy = p.sx
            p.dy = beat * 0.04 * 0.5
        case .jelly:
            let s = sin(t * tau * 2)
            p.sx = 1 + s * 0.09; p.sy = 1 - s * 0.09
        case .float:
            p.dy = sin(t * tau) * 0.05 - 0.02
            p.rot = sin(t * tau + 1) * 3
        case .jitter:
            let k = Int(t * 24)
            p.dx = Double((k * 37) % 7 - 3) * 0.006
            p.dy = Double((k * 53) % 5 - 2) * 0.006
        case .walk:
            p.rot = sin(t * tau * 2) * 6
            p.dy = -abs(sin(t * tau * 2)) * 0.03
            p.dx = sin(t * tau) * 0.06
        case .spin:
            p.rot = t * 360
            p.dy = -0.12          // 绕中心转：抬到中间
        case .pop:
            let e = min(1, t / 0.35)
            let over = e < 1 ? (sin(e * .pi * 0.5) * 1.15) : 1
            p.sx = max(0.01, over); p.sy = p.sx
        case .zoom:
            let e = min(1, t / 0.4)
            p.sx = 1 + 0.28 * (1 - pow(1 - e, 3)); p.sy = p.sx
            p.dy = 0.06 * e
        }
        return p
    }

    /// 身边飘的那些。每一颗的位置只由 t 和它自己的序号算出来，一圈首尾接得上
    private static func drawEffect(_ e: GifEffect, side: CGFloat, t: Double) {
        guard e != .none else { return }
        let glyph = e.glyph
        func put(_ x: Double, _ y: Double, _ size: Double, _ alpha: Double, _ rot: Double = 0) {
            guard alpha > 0.02 else { return }
            let font = UIFont.systemFont(ofSize: CGFloat(size) * side)
            let s = NSAttributedString(string: glyph, attributes: [.font: font])
            let sz = s.size()
            guard let g = UIGraphicsGetCurrentContext() else { return }
            g.saveGState()
            g.setAlpha(CGFloat(alpha))
            g.translateBy(x: CGFloat(x) * side, y: CGFloat(y) * side)
            g.rotate(by: CGFloat(rot) * .pi / 180)
            s.draw(at: CGPoint(x: -sz.width / 2, y: -sz.height / 2))
            g.restoreGState()
        }
        let tau = 2 * Double.pi
        switch e {
        case .hearts, .notes, .sleepy, .fire:
            // 从身边往上冒，越高越淡
            let n = e == .sleepy ? 3 : 4
            for i in 0..<n {
                let ph = (t + Double(i) / Double(n)).truncatingRemainder(dividingBy: 1)
                let side0 = e == .sleepy ? 0.72 : (i % 2 == 0 ? 0.22 : 0.78)
                let x = side0 + sin(ph * tau + Double(i)) * 0.04 + (e == .sleepy ? ph * 0.1 : 0)
                let y = 0.55 - ph * 0.45
                let size = (e == .sleepy ? 0.07 + ph * 0.06 : 0.1)
                put(x, y, size, ph < 0.15 ? ph / 0.15 : 1 - (ph - 0.15) / 0.85)
            }
        case .sparkles:
            let spots: [(Double, Double)] = [(0.2, 0.25), (0.8, 0.3), (0.15, 0.62), (0.85, 0.66), (0.5, 0.12)]
            for (i, s) in spots.enumerated() {
                let ph = (t * 2 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
                let a = sin(ph * .pi)
                put(s.0, s.1, 0.06 + a * 0.05, a)
            }
        case .rain, .petals:
            let n = e == .rain ? 9 : 7
            for i in 0..<n {
                let x0 = (Double(i) + 0.5) / Double(n) + sin(Double(i) * 2.3) * 0.04
                let ph = (t * (e == .rain ? 2 : 1) + Double(i) * 0.29).truncatingRemainder(dividingBy: 1)
                let x = x0 + (e == .petals ? sin(ph * tau + Double(i)) * 0.05 : 0)
                put(x, -0.05 + ph * 1.1, e == .rain ? 0.05 : 0.07, 0.9, e == .petals ? ph * 360 : 0)
            }
        case .sweat:
            let ph = t.truncatingRemainder(dividingBy: 1)
            put(0.78, 0.2 + ph * 0.18, 0.1, ph < 0.8 ? 1 : (1 - ph) / 0.2)
        case .anger:
            let a = 0.6 + 0.4 * abs(sin(t * tau * 2))
            put(0.76, 0.2, 0.09 + 0.03 * a, 1)
        case .question:
            let a = sin(t * tau) * 12
            put(0.78, 0.18, 0.12, 1, a)
        case .tears:
            for i in 0..<2 {
                let ph = (t * 2 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                put(i == 0 ? 0.36 : 0.64, 0.45 + ph * 0.3, 0.06, 1 - ph)
            }
        case .none:
            break
        }
    }

    private static func drawText(_ spec: GifSpec, side: CGFloat, t: Double) {
        let raw = spec.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let g = UIGraphicsGetCurrentContext() else { return }
        let chars = Array(raw)
        var shown = chars.count
        if spec.textAnim == .type { shown = min(chars.count, Int(Double(chars.count + 1) * min(1, t / 0.6))) }
        if spec.textAnim == .blink, Int(t * 6) % 2 == 1 { return }
        guard shown > 0 else { return }
        var scale = 1.0
        if spec.textAnim == .grow {
            let e = min(1, t / 0.25)
            scale = e < 1 ? 0.3 + 0.95 * sin(e * .pi / 2) : 1
        }
        let size = CGFloat(spec.textSize * scale) * side
        let font = spec.font.ui(size)
        let fill = UIColor(beadHex: spec.textColor) ?? .white
        let stroke = UIColor(beadHex: spec.strokeColor) ?? .black
        // 每个字单独摆，一跳一跳 / 抖的时候各动各的
        let pieces = chars.map { String($0) }
        let widths = pieces.map { NSAttributedString(string: $0, attributes: [.font: font]).size().width }
        let total = widths.reduce(0, +)
        var x = CGFloat(spec.textX) * side - total / 2
        let cy = CGFloat(spec.textY) * side
        for (i, p) in pieces.enumerated() {
            defer { x += widths[i] }
            guard i < shown else { continue }
            var dy: CGFloat = 0, dx: CGFloat = 0
            if spec.textAnim == .hop {
                let phase: Double = (t * 2 - Double(i) * 0.12) * 2 * .pi
                let up: Double = max(0, sin(phase))
                dy = -CGFloat(up) * size * 0.25
            }
            if spec.textAnim == .shake {
                let k = Int(t * 24) + i * 7
                dx = CGFloat((k * 37) % 5 - 2) * size * 0.03
                dy = CGFloat((k * 53) % 5 - 2) * size * 0.03
            }
            let at = CGPoint(x: x + dx, y: cy - font.lineHeight / 2 + dy)
            g.saveGState()
            // 描边：同一个字用描边色绕一圈画 16 次，叠出一圈**圆的**边——
            // 以前用字体自带的描边，转角是尖的，看着有毛刺
            let r = CGFloat(spec.strokeWidth) * size
            if r > 0.3 {
                let outline = NSAttributedString(string: p, attributes: [.font: font, .foregroundColor: stroke])
                for k in 0..<16 {
                    let a = Double(k) / 16 * 2 * .pi
                    outline.draw(at: CGPoint(x: at.x + CGFloat(cos(a)) * r, y: at.y + CGFloat(sin(a)) * r))
                }
                // 里面再补一圈，粗描边时中间不漏
                for k in 0..<8 {
                    let a = Double(k) / 8 * 2 * .pi
                    outline.draw(at: CGPoint(x: at.x + CGFloat(cos(a)) * r * 0.5, y: at.y + CGFloat(sin(a)) * r * 0.5))
                }
            }
            NSAttributedString(string: p, attributes: [
                .font: font, .foregroundColor: fill
            ]).draw(at: at)
            g.restoreGState()
        }
    }

    /// 存成 GIF
    static func gif(_ image: UIImage?, spec: GifSpec, side: CGFloat = 240) -> Data? {
        let data = NSMutableData()
        let n = GifSpec.frames
        guard let dest = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, n, nil)
        else { return nil }
        let delay = 2.0 / Double(n) / max(0.25, spec.speed)
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        for i in 0..<n {
            let frame = renderer.image { _ in
                draw(image, spec: spec, side: side, t: Double(i) / Double(n))
            }
            guard let cg = frame.cgImage else { continue }
            CGImageDestinationAddImage(dest, cg, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay
                ]
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

// MARK: - 页面

/// 从哪张图开始做动图
struct GifStart: Identifiable {
    let id = UUID()
    let image: UIImage?
    let name: String
}

struct GifMakerView: View {

    var image: UIImage?
    var name: String = ""

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var stickers = StickerStore.shared

    @State private var base: UIImage?
    @State private var spec = GifSpec()
    @State private var section = 0
    @State private var photo: PhotosPickerItem?
    @State private var choosing = false
    @State private var saving = false
    @State private var title = ""
    @State private var notice: String?
    @State private var dragFrom: (x: Double, y: Double)?

    private let textColors = ["FFFFFF", "4A3442", "F4A9BB", "FFD86B", "A8D8F0", "B8DE9C", "E8758F", "1A1717"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                stage
                sectionPicker
                ScrollView { controls.padding(.horizontal, 16).padding(.bottom, 24) }
            }
            .padding(.top, 8)
            .background(WallpaperBackground())
            .navigationTitle("动图工坊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("存成表情") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                        title = name.isEmpty ? spec.text : name
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            saving = true
                        }
                    }
                        .disabled(base == nil && spec.text.isEmpty)
                }
            }
            .onAppear {
                if base == nil, let image {
                    base = image
                    spec.pixel = max(image.size.width, image.size.height) <= 160
                }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                        use(img)
                    }
                    photo = nil
                }
            }
            .sheet(isPresented: $choosing) { stickerPicker }
            .alert("存成表情", isPresented: $saving) {
                TextField("名字", text: $title)
                Button("取消", role: .cancel) {}
                Button("存") { save() }
            } message: {
                Text("存进表情库「我的」里，一圈 \(GifSpec.frames) 帧。")
            }
            .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("好") { notice = nil }
            }
        }
    }

    private func use(_ img: UIImage) {
        base = img
        spec.pixel = max(img.size.width, img.size.height) <= 160
    }

    // MARK: 预览

    private var stage: some View {
        TimelineView(.animation) { ctx in
            let period = 2.0 / max(0.25, spec.speed)
            let raw = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            // 跟导出一样按 24 帧一跳，预览看到的就是存下来的节奏
            let t = (raw * Double(GifSpec.frames)).rounded(.down) / Double(GifSpec.frames)
            Canvas { gc, size in
                let side = min(size.width, size.height)
                gc.withCGContext { cg in
                    UIGraphicsPushContext(cg)
                    GifFrame.draw(base, spec: spec, side: side, t: t)
                    UIGraphicsPopContext()
                }
            }
        }
        .frame(width: 260, height: 260)
        .background(TransparencyGrid().clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
        .overlay(alignment: .center) {
            if base == nil {
                VStack(spacing: 10) {
                    Text("先挑一张图").font(.app(13)).foregroundStyle(Theme.textMuted(scheme))
                    pickButtons
                }
            }
        }
        .contentShape(Rectangle())
        // 在预览上拖：挪字
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { v in
                guard !spec.text.isEmpty else { return }
                if dragFrom == nil { dragFrom = (spec.textX, spec.textY) }
                guard let f = dragFrom else { return }
                spec.textX = min(0.95, max(0.05, f.x + Double(v.translation.width / 260)))
                spec.textY = min(0.95, max(0.05, f.y + Double(v.translation.height / 260)))
            }
            .onEnded { _ in dragFrom = nil })
    }

    private var pickButtons: some View {
        HStack(spacing: 10) {
            Button { choosing = true } label: {
                Label("从表情包挑", systemImage: "face.smiling").font(.app(12.5))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.softFillDeep))
            }
            PhotosPicker(selection: $photo, matching: .images) {
                Label("从相册", systemImage: "photo").font(.app(12.5))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.softFillDeep))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textMain(scheme))
    }

    private var sectionPicker: some View {
        Picker("", selection: $section) {
            Text("动作").tag(0)
            Text("特效").tag(1)
            Text("文字").tag(2)
            Text("其他").tag(3)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var controls: some View {
        switch section {
        case 0: chips(GifMotion.allCases, selected: spec.motion, label: { $0.label }) { spec.motion = $0 }
        case 1: chips(GifEffect.allCases, selected: spec.effect, label: { e in
                    e == .none ? "无" : e.glyph + " " + e.label }) { spec.effect = $0 }
        case 2: textControls
        default: otherControls
        }
    }

    private func chips<T: Hashable>(_ all: [T], selected: T, label: @escaping (T) -> String,
                                    pick: @escaping (T) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
            ForEach(all, id: \.self) { v in
                Button { pick(v) } label: {
                    Text(label(v))
                        .font(.app(13))
                        .foregroundStyle(v == selected ? app.settings.accentColor : Theme.textMain(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(v == selected ? app.settings.accentColor.opacity(0.16) : Theme.softFillDeep))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var textControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("写一句，比如：在吗", text: $spec.text)
                .font(.app(15))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
            Text("在预览上拖动可以挪字的位置").font(.app(10.5)).foregroundStyle(Theme.textMuted(scheme))
            row("字号") {
                Slider(value: $spec.textSize, in: 0.07...0.3)
            }
            row("颜色") { swatches($spec.textColor) }
            row("描边") { swatches($spec.strokeColor) }
            row("描边粗细") {
                Slider(value: $spec.strokeWidth, in: 0...0.22)
            }
            row("字体") {
                Picker("", selection: $spec.font) {
                    ForEach(GifFont.allCases) { f in Text(f.label).tag(f) }
                }
                .pickerStyle(.segmented)
            }
            Text("字怎么动").font(.app(12, weight: .medium)).foregroundStyle(Theme.textSoft(scheme))
            chips(GifTextAnim.allCases, selected: spec.textAnim, label: { $0.label }) { spec.textAnim = $0 }
        }
    }

    private var otherControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("速度") {
                Slider(value: $spec.speed, in: 0.4...2.5)
            }
            row("图的大小") {
                Slider(value: $spec.imageScale, in: 0.4...0.95)
            }
            Toggle("像素图（放大不糊）", isOn: $spec.pixel).font(.app(14))
            Toggle("白底（边缘更干净）", isOn: $spec.whiteBG).font(.app(14))
            Text("换一张图").font(.app(12, weight: .medium)).foregroundStyle(Theme.textSoft(scheme))
            pickButtons
        }
        .tint(app.settings.accentColor)
    }

    private func row<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.app(13)).foregroundStyle(Theme.textSoft(scheme)).frame(width: 64, alignment: .leading)
            content()
        }
    }

    private func swatches(_ value: Binding<String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(textColors, id: \.self) { hex in
                    Button { value.wrappedValue = hex } label: {
                        Circle().fill(Color(hexString: hex) ?? .white)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 0.6))
                            .overlay(Circle().stroke(app.settings.accentColor, lineWidth: value.wrappedValue == hex ? 2.2 : 0)
                                .padding(-3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 3)
        }
    }

    // MARK: 从表情包挑

    private var stickerPicker: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 12) {
                    ForEach(stickers.stickers.filter { $0.isUser }) { s in
                        Button {
                            if let img = Self.firstFrame(s) { use(img) }
                            choosing = false
                        } label: {
                            StickerImage(sticker: s, size: 62).frame(height: 68)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("挑一张表情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { choosing = false } } }
        }
    }

    /// 一张表情的图（动图取第一帧）
    static func firstFrame(_ s: Sticker) -> UIImage? {
        let store = StickerStore.shared
        if s.animated, !s.thumbName.isEmpty, let img = UIImage(contentsOfFile: store.url(s.thumbName).path) {
            return img
        }
        return UIImage(contentsOfFile: store.url(of: s).path)
    }

    // MARK: 存

    private func save() {
        let spec = spec, base = base
        Task { @MainActor in
            guard let data = await Task.detached(priority: .userInitiated, operation: {
                GifFrame.gif(base, spec: spec)
            }).value, var s = StickerStore.shared.add(data: data, ext: "gif", owner: "user") else {
                notice = "没存上，再试一次。"
                return
            }
            let n = title.trimmingCharacters(in: .whitespacesAndNewlines)
            s.name = n.isEmpty ? (spec.text.isEmpty ? "动图" : spec.text) : n
            // 描述替她写好一句（他靠描述知道这张什么时候用），想改去表情库里改
            var about = (name.isEmpty ? "一张会动的表情" : name) + "，" + spec.motion.label
            if spec.effect != .none { about += "，" + spec.effect.label }
            if !spec.text.isEmpty { about += "，写着「" + spec.text + "」" }
            s.description = about
            s.animated = true
            StickerStore.shared.update(s)
            notice = "存好了，在表情库「我的」里。"
        }
    }
}

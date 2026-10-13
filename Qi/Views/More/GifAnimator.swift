import SwiftUI
import UIKit

// MARK: - 自己做动画（逐帧）
//
// 她要的：「每一帧该怎么动由我来决定，就像画动画一样——别人是一帧一帧地画，
// 我是一帧一帧地细微拖动各个部位来实现动作。」
//
// 做法：
//   · 先把图切成几个部位：框一块，或者点一下把同一个颜色连着的那片拿出来（像素图最好用）
//   · 每个部位有一个转轴（手臂就设在肩膀上）
//   · 每一帧里，每个部位挪多少、转多少、放多大，都由她摆
//   · 播放时一帧一帧放；开着「补间」的话帧和帧之间自动过渡，动作更顺
//
// 画法在 `GifFrame.drawParts`，预览和导出是同一套。

struct GifPart: Identifiable {
    let id = UUID()
    var name: String
    /// 这个部位的图（切出来的跟底图一样大，只有这个部位的像素；零件就是零件那张）
    var image: UIImage
    /// 转轴在整张图上的位置（0…1）
    var pivot: CGPoint
    /// 这张图摆在整张图的哪一块（0…1）。切出来的就是整块
    var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
}

struct PartPose: Equatable {
    /// 挪多少（以整张图的宽为 1）
    var dx = 0.0
    var dy = 0.0
    /// 转多少度
    var rot = 0.0
    var scale = 1.0

    static func lerp(_ a: PartPose, _ b: PartPose, _ t: Double) -> PartPose {
        PartPose(dx: a.dx + (b.dx - a.dx) * t, dy: a.dy + (b.dy - a.dy) * t,
                 rot: a.rot + (b.rot - a.rot) * t, scale: a.scale + (b.scale - a.scale) * t)
    }
}

struct GifAnim {
    var parts: [GifPart] = []
    /// 每一帧里每个部位的样子。没写的部位就是原样
    var frames: [[UUID: PartPose]] = [[:], [:], [:], [:]]
    /// 帧和帧之间自动过渡
    var tween = true

    var count: Int { max(1, frames.count) }

    /// 第 t（0…1）那一刻这个部位的样子
    func pose(_ id: UUID, t: Double) -> PartPose {
        let n = count
        let x = t.truncatingRemainder(dividingBy: 1) * Double(n)
        let i = Int(x.rounded(.down)) % n
        let a = frames[i][id] ?? PartPose()
        guard tween, n > 1 else { return a }
        let b = frames[(i + 1) % n][id] ?? PartPose()
        let f = x - Double(Int(x.rounded(.down)))
        // 两头慢、中间快
        let e = f * f * (3 - 2 * f)
        return PartPose.lerp(a, b, e)
    }

    /// 第 i 帧（不补间）
    func pose(_ id: UUID, frame i: Int) -> PartPose {
        frames[max(0, min(count - 1, i))][id] ?? PartPose()
    }

    // MARK: 切部位

    /// 从一张图建：整张就是第一个部位
    static func start(_ img: UIImage) -> GifAnim {
        let norm = GifAnim.normalized(img)
        return GifAnim(parts: [GifPart(name: "整张", image: norm, pivot: CGPoint(x: 0.5, y: 0.85))])
    }

    /// 切图要逐像素读，图太大太慢：长边超过 512 就缩到 512（像素图不插值）
    static func normalized(_ img: UIImage) -> UIImage {
        let w = img.size.width * img.scale, h = img.size.height * img.scale
        let k = min(1, 512 / max(w, h))
        let size = CGSize(width: max(1, (w * k).rounded()), height: max(1, (h * k).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.interpolationQuality = max(w, h) <= 200 ? .none : .high
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    struct Pixels {
        var w: Int
        var h: Int
        var data: [UInt8]       // RGBA
    }

    static func pixels(_ img: UIImage) -> Pixels? {
        guard let cg = img.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Pixels(w: w, h: h, data: data)
    }

    static func image(_ p: Pixels) -> UIImage? {
        var data = p.data
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &data, width: p.w, height: p.h, bitsPerComponent: 8, bytesPerRow: p.w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg)
    }

    /// 框一块：图上的像素矩形
    static func rectMask(_ p: Pixels, _ r: CGRect) -> [Bool] {
        var m = [Bool](repeating: false, count: p.w * p.h)
        let x0 = max(0, Int(r.minX)), x1 = min(p.w, Int(r.maxX.rounded(.up)))
        let y0 = max(0, Int(r.minY)), y1 = min(p.h, Int(r.maxY.rounded(.up)))
        guard x1 > x0, y1 > y0 else { return m }
        for y in y0..<y1 { for x in x0..<x1 where p.data[(y * p.w + x) * 4 + 3] > 16 { m[y * p.w + x] = true } }
        return m
    }

    /// 点同色：从这一点往外，颜色差不多、连在一起的那一片
    static func wandMask(_ p: Pixels, _ sx: Int, _ sy: Int, tolerance: Int = 34) -> [Bool] {
        var m = [Bool](repeating: false, count: p.w * p.h)
        guard sx >= 0, sy >= 0, sx < p.w, sy < p.h else { return m }
        let s = (sy * p.w + sx) * 4
        guard p.data[s + 3] > 16 else { return m }
        let r0 = Int(p.data[s]), g0 = Int(p.data[s + 1]), b0 = Int(p.data[s + 2])
        var stack = [sy * p.w + sx]
        while let i = stack.popLast() {
            guard !m[i] else { continue }
            let o = i * 4
            guard p.data[o + 3] > 16,
                  abs(Int(p.data[o]) - r0) + abs(Int(p.data[o + 1]) - g0) + abs(Int(p.data[o + 2]) - b0) <= tolerance
            else { continue }
            m[i] = true
            let x = i % p.w, y = i / p.w
            if x > 0 { stack.append(i - 1) }
            if x < p.w - 1 { stack.append(i + 1) }
            if y > 0 { stack.append(i - p.w) }
            if y < p.h - 1 { stack.append(i + p.w) }
        }
        return m
    }

    /// 从某个部位里把 mask 那一片切出来，成为新的部位。返回新部位的 id
    @discardableResult
    mutating func cut(from id: UUID, mask: [Bool], name: String) -> UUID? {
        guard let k = parts.firstIndex(where: { $0.id == id }),
              var src = Self.pixels(parts[k].image), mask.count == src.w * src.h else { return nil }
        var out = Pixels(w: src.w, h: src.h, data: [UInt8](repeating: 0, count: src.data.count))
        var any = false
        var x0 = src.w, x1 = 0, y0 = src.h, y1 = 0
        for i in 0..<(src.w * src.h) where mask[i] {
            any = true
            for c in 0..<4 { out.data[i * 4 + c] = src.data[i * 4 + c]; src.data[i * 4 + c] = 0 }
            let x = i % src.w, y = i / src.w
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        }
        guard any, let piece = Self.image(out), let rest = Self.image(src) else { return nil }
        parts[k].image = rest
        // 转轴先放在切出来那一块的中间（换成整张图上的位置）
        let r = parts[k].rect
        let pivot = CGPoint(x: r.minX + (Double(x0 + x1) / 2 + 0.5) / Double(src.w) * r.width,
                            y: r.minY + (Double(y0 + y1) / 2 + 0.5) / Double(src.h) * r.height)
        var part = GifPart(name: name, image: piece, pivot: pivot)
        part.rect = r
        // 切出来的放在原来那块的上面一层
        parts.insert(part, at: k + 1)
        return part.id
    }

    /// 加一个零件（拼豆存的）：摆在正中间，宽占整张的三分之一
    mutating func addPart(_ raw: UIImage, name: String, baseAspect: Double) {
        let img = Self.normalized(raw)
        let iw = Double(img.size.width), ih = Double(img.size.height)
        guard iw > 0, ih > 0 else { return }
        let w = 0.34
        let h = w * (ih / iw) * baseAspect
        let rect = CGRect(x: 0.5 - w / 2, y: 0.5 - h / 2, width: w, height: h)
        var p = GifPart(name: name, image: img, pivot: CGPoint(x: 0.5, y: 0.5))
        p.rect = rect
        parts.append(p)
    }

    /// 把一个部位并回它下面那一层（切错了用）
    mutating func merge(_ id: UUID) {
        guard let k = parts.firstIndex(where: { $0.id == id }), k > 0,
              parts[k].rect == parts[k - 1].rect else {
            // 零件那种自己一块的，并不回去，直接拿掉
            if let k = parts.firstIndex(where: { $0.id == id }), k > 0 {
                parts.remove(at: k)
                for f in frames.indices { frames[f][id] = nil }
            }
            return
        }
        let size = parts[k - 1].image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            parts[k - 1].image.draw(in: CGRect(origin: .zero, size: size))
            parts[k].image.draw(in: CGRect(origin: .zero, size: size))
        }
        parts[k - 1].image = img
        parts.remove(at: k)
        for f in frames.indices { frames[f][id] = nil }
    }
}

extension GifFrame {

    /// 在「整张图摆在哪」那个框里画所有部位。`local` 是那个框（已经套上了整体的动作）
    static func drawParts(_ anim: GifAnim, in local: CGRect, t: Double, frame: Int?, alpha: CGFloat,
                          pixel: Bool, in g: CGContext) {
        let w = local.width, h = local.height
        for part in anim.parts {
            let p = frame.map { anim.pose(part.id, frame: $0) } ?? anim.pose(part.id, t: t)
            let pv = CGPoint(x: local.minX + part.pivot.x * w, y: local.minY + part.pivot.y * h)
            g.saveGState()
            g.setAlpha(alpha)
            g.interpolationQuality = pixel ? .none : .high
            g.translateBy(x: pv.x + CGFloat(p.dx) * w, y: pv.y + CGFloat(p.dy) * w)
            g.rotate(by: CGFloat(p.rot) * .pi / 180)
            g.scaleBy(x: CGFloat(p.scale), y: CGFloat(p.scale))
            let r = part.rect
            part.image.draw(in: CGRect(x: local.minX + r.minX * w - pv.x, y: local.minY + r.minY * h - pv.y,
                                       width: r.width * w, height: r.height * h))
            g.restoreGState()
        }
    }
}

// MARK: - 编辑那一页（动图工坊里「逐帧」那一档）

struct GifAnimEditor: View {

    @Binding var anim: GifAnim
    @Binding var frame: Int
    @Binding var selected: UUID?
    @Binding var tool: Tool
    @Binding var playing: Bool
    @Binding var onion: Bool
    /// 工具底下多一排（点选像素那几个按钮）
    var extras: AnyView? = nil

    enum Tool: String, CaseIterable, Identifiable {
        case pose, paint, wand, pivot
        var id: String { rawValue }
        var label: String {
            switch self {
            case .pose: return "摆动作"
            case .paint: return "点选像素"
            case .wand: return "点同色"
            case .pivot: return "设转轴"
            }
        }
        var hint: String {
            switch self {
            case .pose: return "在预览上拖动挪选中的部位，两指转、两指放大；底下的滑条能细调"
            case .paint: return "在预览上一格一格点，或者按住拖着涂；选好了点「切成部位」"
            case .wand: return "点一下，把同一个颜色连着的那一片加进选区（像素图最好用）"
            case .pivot: return "点一下或者拖到想要的地方松手，转轴就设在那儿（手臂设在肩膀上）"
            }
        }
    }

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    private var sel: UUID? { selected ?? anim.parts.first?.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $tool) {
                ForEach(Tool.allCases) { t in Text(t.label).tag(t) }
            }
            .pickerStyle(.segmented)
            Text(tool.hint).font(.app(10.5)).foregroundStyle(Theme.textMuted(scheme))
            if let extras { extras }

            // 部位
            Text("部位").font(.app(12, weight: .medium)).foregroundStyle(Theme.textSoft(scheme))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(anim.parts) { p in
                        let on = sel == p.id
                        Button { selected = p.id } label: {
                            HStack(spacing: 6) {
                                Image(uiImage: p.image).resizable().interpolation(.none).scaledToFit()
                                    .frame(width: 26, height: 26)
                                Text(p.name).font(.app(12))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(on ? app.settings.accentColor.opacity(0.18) : Theme.softFillDeep))
                            .foregroundStyle(on ? app.settings.accentColor : Theme.textMain(scheme))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if anim.parts.first?.id != p.id {
                                Button("并回下面那块（零件就拿掉）") { anim.merge(p.id); selected = nil }
                            }
                        }
                    }
                }
            }

            // 帧
            HStack {
                Text("第 \(frame + 1) / \(anim.count) 帧").font(.app(12, weight: .medium))
                    .foregroundStyle(Theme.textSoft(scheme))
                Spacer()
                Toggle("淡影", isOn: $onion).font(.app(12)).fixedSize()
                Toggle("补间", isOn: $anim.tween).font(.app(12)).fixedSize()
            }
            .tint(app.settings.accentColor)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<anim.count, id: \.self) { i in
                        Button { frame = i; playing = false } label: {
                            Text("\(i + 1)").font(.app(12, weight: .medium))
                                .frame(width: 34, height: 30)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(frame == i ? app.settings.accentColor.opacity(0.22) : Theme.softFillDeep))
                                .foregroundStyle(frame == i ? app.settings.accentColor : Theme.textMain(scheme))
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        // 加一帧：照着这一帧复制一份接在后面，接着细调
                        anim.frames.insert(anim.frames[frame], at: frame + 1)
                        frame += 1
                        playing = false
                    } label: {
                        Image(systemName: "plus").frame(width: 34, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 10) {
                small(playing ? "停" : "播放", playing ? "pause.fill" : "play.fill") { playing.toggle() }
                small("删这帧", "trash") {
                    guard anim.frames.count > 1 else { return }
                    anim.frames.remove(at: frame)
                    frame = min(frame, anim.frames.count - 1)
                }
                small("这帧归位", "arrow.counterclockwise") {
                    if let id = sel { anim.frames[frame][id] = nil }
                }
            }

            // 选中部位在这一帧的细调
            if let id = sel {
                let b = poseBinding(id)
                slider("左右", value: Binding(get: { b.wrappedValue.dx }, set: { b.wrappedValue.dx = $0 }), -0.5...0.5)
                slider("上下", value: Binding(get: { b.wrappedValue.dy }, set: { b.wrappedValue.dy = $0 }), -0.5...0.5)
                slider("旋转", value: Binding(get: { b.wrappedValue.rot }, set: { b.wrappedValue.rot = $0 }), -180...180)
                slider("大小", value: Binding(get: { b.wrappedValue.scale }, set: { b.wrappedValue.scale = $0 }), 0.3...2)
            }
        }
    }

    private func poseBinding(_ id: UUID) -> Binding<PartPose> {
        Binding(get: { anim.frames[min(frame, anim.count - 1)][id] ?? PartPose() },
                set: { anim.frames[min(frame, anim.count - 1)][id] = $0 })
    }

    private func slider(_ title: String, value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.app(12.5)).foregroundStyle(Theme.textSoft(scheme)).frame(width: 40, alignment: .leading)
            Slider(value: value, in: range).tint(app.settings.accentColor)
        }
    }

    private func small(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.app(12))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Capsule().fill(Theme.softFillDeep))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textMain(scheme))
    }
}

// MARK: - 点选像素

extension GifAnim {

    /// 像素图一格是几个像素（拼豆导出的一格是好几个像素，点一下选的是一整格）。
    /// 认不出格子的（照片这种）按长边分成 96 格左右
    static func cellSize(_ p: Pixels) -> Double {
        var hist: [Int: Int] = [:]
        var total = 0
        func key(_ i: Int) -> Int {
            let o = i * 4
            guard p.data[o + 3] > 16 else { return -1 }
            return Int(p.data[o]) << 16 | Int(p.data[o + 1]) << 8 | Int(p.data[o + 2])
        }
        // 同一个颜色连着几个像素：不算贴着边的那一段（可能被截了）
        func runs(_ n: Int, _ index: (Int) -> Int) {
            var start = 0, last = key(index(0))
            for i in 1...n {
                let k = i < n ? key(index(i)) : -2
                guard k != last else { continue }
                if last >= 0, start > 0, i < n { hist[i - start, default: 0] += 1; total += 1 }
                start = i
                last = k
            }
        }
        for y in 0..<p.h { runs(p.w) { y * p.w + $0 } }
        for x in 0..<p.w { runs(p.h) { $0 * p.w + x } }
        let fallback = max(1, Double(max(p.w, p.h)) / 96)
        guard total >= 12 else { return fallback }
        let need = max(3, total / 20)
        guard let l = hist.keys.sorted().first(where: { (hist[$0] ?? 0) >= need }), l >= 2 else { return fallback }
        // 缩放过的像素图一格是 6、7 个像素交替：取平均，再按整张有几列对齐
        let near = [l, l + 1]
        let n = near.reduce(0) { $0 + (hist[$1] ?? 0) }
        var c = Double(near.reduce(0) { $0 + $1 * (hist[$1] ?? 0) }) / Double(max(1, n))
        let cols = (Double(p.w) / c).rounded()
        if cols > 0 { c = Double(p.w) / cols }
        return max(1, c)
    }
}

/// 逐帧里「点选像素」「点同色」正在选的那一片（还没切）
struct PaintSel {
    let part: UUID
    let px: GifAnim.Pixels
    /// 一格是几个像素
    let cell: Double
    var mask: [Bool]
    var count = 0
    var overlay: UIImage?

    /// 在 (x, y) 那一格（加上周围 radius 格）选上 / 擦掉
    mutating func paint(at x: Double, _ y: Double, radius: Int, erase: Bool) -> Bool {
        guard x >= 0, y >= 0, x < Double(px.w), y < Double(px.h) else { return false }
        let gx = Int(x / cell), gy = Int(y / cell)
        var changed = false
        for cy in (gy - radius)...(gy + radius) {
            for cx in (gx - radius)...(gx + radius) {
                let x0 = max(0, Int((Double(cx) * cell).rounded())), x1 = min(px.w, Int((Double(cx + 1) * cell).rounded()))
                let y0 = max(0, Int((Double(cy) * cell).rounded())), y1 = min(px.h, Int((Double(cy + 1) * cell).rounded()))
                guard x1 > x0, y1 > y0 else { continue }
                for yy in y0..<y1 {
                    for xx in x0..<x1 {
                        let i = yy * px.w + xx
                        if erase {
                            if mask[i] { mask[i] = false; count -= 1; changed = true }
                        } else if !mask[i], px.data[i * 4 + 3] > 16 {
                            mask[i] = true; count += 1; changed = true
                        }
                    }
                }
            }
        }
        return changed
    }

    /// 点同色那一片并进来 / 擦出去
    mutating func add(_ m: [Bool], erase: Bool) -> Bool {
        guard m.count == mask.count else { return false }
        var changed = false
        for i in m.indices where m[i] && mask[i] == erase {
            mask[i] = !erase
            count += erase ? -1 : 1
            changed = true
        }
        return changed
    }

    /// 选中的像素涂一层主题色，盖在部位上给她看
    func overlayImage(_ c: (CGFloat, CGFloat, CGFloat)) -> UIImage? {
        var out = GifAnim.Pixels(w: px.w, h: px.h, data: [UInt8](repeating: 0, count: px.w * px.h * 4))
        let a: CGFloat = 0.62
        func ch(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(1, v)) * a * 255) }
        let r = ch(c.0), g = ch(c.1), b = ch(c.2), al = UInt8(a * 255)
        for i in mask.indices where mask[i] {
            out.data[i * 4] = r
            out.data[i * 4 + 1] = g
            out.data[i * 4 + 2] = b
            out.data[i * 4 + 3] = al
        }
        return GifAnim.image(out)
    }
}

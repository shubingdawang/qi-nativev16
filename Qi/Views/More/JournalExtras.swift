import SwiftUI

// MARK: - 手帐：线条、墨印、纹理、占位
//
// 模板和质感那一轮加的几样。纹理图都在 Resources/Paper（scripts/journal_textures.py 算出来的）。

/// 在不在编辑页里。编辑页画占位提示（灰字、虚线框），给他看的快照里不画
private struct JournalEditingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var journalEditing: Bool {
        get { self[JournalEditingKey.self] }
        set { self[JournalEditingKey.self] = newValue }
    }
}

enum JournalTextures {
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 12
        return c
    }()

    static func image(_ name: String, ext: String = "jpg") -> UIImage? {
        let key = (name + "." + ext) as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }
}

/// 墨没吃匀：拿斑驳那张图当遮罩（透明的地方露出底下的纸）
struct JournalDistress: ViewModifier {
    var on: Bool

    func body(content: Content) -> some View {
        if on, let img = JournalTextures.image("ink_mask", ext: "png") {
            content.mask {
                Image(uiImage: img)
                    .resizable(resizingMode: .tile)
            }
        } else {
            content
        }
    }
}

/// 字像印在纸上：深色的墨用正片叠底压进纸纹里；打字机那种再加一层斑驳
struct JournalInk: ViewModifier {
    let fontKey: String
    let hex: String

    func body(content: Content) -> some View {
        let dark = hex.isEmpty || JournalTheme.luma(hex) < 0.55
        content
            .modifier(JournalDistress(on: fontKey == "type"))
            .blendMode(dark ? .multiply : .normal)
    }
}

/// 一条线
struct JournalLineView: View {
    let pattern: String
    let color: Color
    var width: CGFloat = 180

    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2
            let w = size.width
            func line(_ y: CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: w, y: y))
                return p
            }
            switch pattern {
            case "dash":
                ctx.stroke(line(mid), with: .color(color.opacity(0.75)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            case "double":
                ctx.stroke(line(mid - 2), with: .color(color.opacity(0.85)), lineWidth: 1.3)
                ctx.stroke(line(mid + 2), with: .color(color.opacity(0.7)), lineWidth: 0.6)
            case "dots":
                var p = Path()
                var x: CGFloat = 2
                while x < w {
                    p.addEllipse(in: CGRect(x: x - 1, y: mid - 1, width: 2, height: 2))
                    x += 6
                }
                ctx.fill(p, with: .color(color.opacity(0.7)))
            case "wave":
                var p = Path()
                p.move(to: CGPoint(x: 0, y: mid))
                var x: CGFloat = 0
                var up = true
                while x < w {
                    p.addQuadCurve(to: CGPoint(x: min(w, x + 8), y: mid),
                                   control: CGPoint(x: x + 4, y: mid + (up ? -3.5 : 3.5)))
                    x += 8; up.toggle()
                }
                ctx.stroke(p, with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            case "hand":
                // 手画的：一笔带过，起笔低、中间略拱、收笔微微上挑，粗细有一点变化
                var p = Path()
                p.move(to: CGPoint(x: 2, y: mid + 1.5))
                p.addCurve(to: CGPoint(x: w * 0.55, y: mid + 0.5),
                           control1: CGPoint(x: w * 0.2, y: mid - 1.5), control2: CGPoint(x: w * 0.38, y: mid + 2.5))
                p.addCurve(to: CGPoint(x: w - 2, y: mid - 2),
                           control1: CGPoint(x: w * 0.72, y: mid - 1.2), control2: CGPoint(x: w * 0.9, y: mid))
                ctx.stroke(p, with: .color(color.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                var q = Path()
                q.move(to: CGPoint(x: w * 0.12, y: mid + 0.8))
                q.addCurve(to: CGPoint(x: w * 0.8, y: mid),
                           control1: CGPoint(x: w * 0.35, y: mid - 0.6), control2: CGPoint(x: w * 0.6, y: mid + 1.4))
                ctx.stroke(q, with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            default:
                ctx.stroke(line(mid), with: .color(color.opacity(0.85)), lineWidth: 1)
            }
        }
        .frame(width: width, height: 14)
        .modifier(JournalDistress(on: pattern == "hand"))
    }
}

/// 墨印圆章：两圈、中间一两个字、底下一行小字，墨没吃匀
struct JournalInkStamp: View {
    let text: String
    let sub: String
    let color: Color
    /// 印泥的色号：深色才压进纸里（正片叠底），浅色印在深纸上照常画
    var hex: String = ""

    var body: some View {
        ZStack {
            Circle().strokeBorder(color, lineWidth: 2.4)
            Circle().strokeBorder(color.opacity(0.8), lineWidth: 0.8).padding(5)
            VStack(spacing: 3) {
                Text(text)
                    .font(JournalFonts.font("", size: text.count > 2 ? 14 : 18, weight: .semibold))
                    .tracking(2)
                if !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .tracking(1.5)
                }
            }
            .foregroundStyle(color)
        }
        .frame(width: 84, height: 84)
        .modifier(JournalDistress(on: true))
        .opacity(0.88)
        .blendMode(hex.isEmpty || JournalTheme.luma(hex) < 0.55 ? .multiply : .normal)
    }
}

/// 还没填的文字：灰的提示 + 一圈虚线
struct JournalTextHint: View {
    let e: JournalElement

    var body: some View {
        let w = e.width > 0 ? CGFloat(e.width) : 160
        Text(e.hint)
            .font(JournalFonts.font(e.pattern, size: 17 * CGFloat(Theme.fontScale), weight: .medium))
            .tracking(e.pattern == "label" ? 2.5 : 0)
            .foregroundStyle(e.color.opacity(0.38))
            .multilineTextAlignment(e.align == "center" ? .center : (e.align == "trailing" ? .trailing : .leading))
            .frame(width: w, alignment: e.align == "center" ? .center : (e.align == "trailing" ? .trailing : .leading))
            .padding(.vertical, 3)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(e.color.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .padding(-3)
            }
    }
}

/// 还没放照片的格子：虚线框 + 「添加照片」
struct JournalPhotoHint: View {
    let hint: String
    var side: CGFloat = 120

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.white.opacity(0.35))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color(hexString: "8A8378")!.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            }
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 18, weight: .light))
                    Text(hint.isEmpty ? "添加照片" : hint).font(.app(10))
                }
                .foregroundStyle(Color(hexString: "6B655A")!)
            }
            .frame(width: side, height: side)
    }
}

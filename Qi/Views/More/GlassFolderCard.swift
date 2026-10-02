import SwiftUI

/// 相册首页的一个文件夹：📁 的形状，前片是一块毛玻璃，
/// 后面探出一只 clawd 在做它自己的事（用的就是聊天页那套动画）。
///
/// 她要的：照那张「把浪漫装进文件夹」的样子，但不放花——
/// 「文件夹不能按照起名全部做出图片，所以每一个文件夹随机一个 clawd 的动画就行」。
/// 哪只 clawd 由文件夹名字和日期定：同一天里不会一刷新就换，第二天换一批。
struct GlassFolderCard: View {

    let title: String
    let count: Int
    let tint: Color

    @Environment(\.colorScheme) private var scheme
    @State private var hop = false

    /// 会去探头的那些（都是「在做一件事」的，站着发呆的不要）
    static let moods: [ClawdMood] = [
        .coffee, .reading, .eating, .painting, .listening, .watering, .gaming,
        .guitar, .photo, .singing, .piano, .dancing, .bubbles, .bubbletea,
        .baking, .sushi, .ramen, .hotpot, .loving, .sweeping
    ]

    /// 名字 + 今天 → 一只 clawd。FNV-1a：`hashValue` 每次启动都会变，不能用
    private var mood: ClawdMood {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        var h: UInt64 = 0xcbf29ce484222325
        for b in (title + "#\(day)").utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return Self.moods[Int(h % UInt64(Self.moods.count))]
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                // 后片：一块板 + 左上角的标签
                TabbedFolderBack()
                    .fill(tint)
                    .overlay(TabbedFolderBack().fill(.black.opacity(scheme == .dark ? 0.55 : 0.38)))
                    .frame(width: w, height: h * 0.80)
                    .offset(y: h * 0.20)

                // clawd：站在后片里，腰以下藏在玻璃后面
                clawd(width: w * 0.5)
                    .position(x: w * 0.58, y: h * 0.31)
                    .offset(y: hop ? -h * 0.12 : 0)

                // 前片：毛玻璃（字跟着卡片大小走：每行 4 个的时候卡片只有一半大）
                front(w)
                    .frame(width: w, height: h * 0.54)
                    .offset(y: h * 0.46)
            }
        }
        .aspectRatio(1.15, contentMode: .fit)
        .simultaneousGesture(TapGesture().onEnded {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { hop = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { hop = false }
            }
        })
    }

    private func clawd(width: CGFloat) -> some View {
        let frames = mood.frames
        let total = frames.reduce(0) { $0 + $1.1 }
        let base = frames.first?.0 ?? ClawdSprites.idle
        let scale = width / CGFloat(max(1, base.width))
        return TimelineView(.periodic(from: .now, by: 0.12)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: max(0.1, total))
            let sprite = Self.frame(at: t, in: frames) ?? base
            PixelSpriteView(sprite: sprite, scale: scale)
                .shadow(color: tint.opacity(0.7), radius: 6)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
        }
    }

    static func frame(at t: Double, in frames: [(PixelSprite, Double)]) -> PixelSprite? {
        var acc = 0.0
        for (s, d) in frames {
            acc += d
            if t < acc { return s }
        }
        return frames.last?.0
    }

    private func front(_ w: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(16, w * 0.1), style: .continuous)
        return ZStack(alignment: .bottomLeading) {
            shape.fill(.ultraThinMaterial)
            shape.fill(LinearGradient(colors: [tint.opacity(0.45), tint.opacity(0.22)],
                                      startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(.white.opacity(0.28), lineWidth: 1)
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .clear],
                                              startPoint: .top, endPoint: .center), lineWidth: 1)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.app(max(10, min(15, w * 0.085)), weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.25), radius: 4)
                    Text("\(count) 张")
                        .font(.app(max(8, min(10, w * 0.06)), weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 4)
                if w > 110 {
                    Image(systemName: "folder")
                        .font(.app(14, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, min(12, w * 0.07))
            .padding(.bottom, min(10, w * 0.06))
        }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
    }
}

/// 文件夹后片：一块圆角板，左上角凸起一截标签，标签右边是一道斜坡
struct TabbedFolderBack: Shape {
    func path(in r: CGRect) -> Path {
        let tabH = min(r.height * 0.14, 18)
        let tabW = r.width * 0.42
        let rad: CGFloat = 14
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + rad))
        p.addQuadCurve(to: CGPoint(x: r.minX + rad, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + tabW - 6, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + tabW + 4, y: r.minY + 4), control: CGPoint(x: r.minX + tabW, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + tabW + 12, y: r.minY + tabH))
        p.addLine(to: CGPoint(x: r.maxX - rad, y: r.minY + tabH))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + tabH + rad), control: CGPoint(x: r.maxX, y: r.minY + tabH))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.maxX - rad, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - rad), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

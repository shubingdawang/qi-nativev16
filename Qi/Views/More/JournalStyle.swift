import SwiftUI

/// 相框、照片边、便签、夹子、邮票各自的几种样子。
///
/// 她定的：「相框、便签、夹子、邮票需要多种风格，
/// 照片需要可以选择边框。」
///
/// ⚠️ 全都走元素身上那个 `pattern` 字段（跟胶带的花纹、贴纸的形状共用一个）。
/// 合用一个字段是因为**一件东西只可能是其中一种**——
/// 一张便签不会同时还是一卷胶带。
///
/// ⚠️ **空字符串一律是老样子。** 老页面上那些元素 `pattern` 都是空的，
/// 它们必须原样不动——她做过的那些页不该因为我加了几个花样就变个样。
enum JournalStyle {

    // MARK: 相框

    /// 边多宽。拍立得的边是宽的，窄白边就窄，撕边留出毛边的地方。
    static func framePad(_ kind: String) -> CGFloat {
        switch kind {
        case "thin":   return 3
        case "round":  return 6
        case "double": return 9
        case "torn":   return 8
        case "wood":   return 8
        default:       return 7      // 拍立得
        }
    }

    static func frameRadius(_ kind: String) -> CGFloat {
        kind == "round" ? 10 : 0
    }

    @ViewBuilder
    static func frameFill(_ kind: String) -> some View {
        switch kind {
        case "wood":
            // 木框：两道深浅不一的木色斜着叠，像木纹
            LinearGradient(colors: [Color(hexString: "B08C62")!,
                                    Color(hexString: "8E6C46")!,
                                    Color(hexString: "A98457")!],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case "torn":
            Color(hexString: "FBF8F1")!
        default:
            Color.white
        }
    }

    // MARK: 照片的边

    /// 照片加不加边、加什么边。
    ///
    /// ⚠️ 做成 `ViewModifier` 而不是包一层 View：
    /// 照片那一支原来就是直接摆一张 `Image`，
    /// 外面再套个容器会改掉它的尺寸，贴在页面上的位置就跟着挪了。
    struct PhotoEdge: ViewModifier {
        let kind: String
        let tint: Color

        func body(content: Content) -> some View {
            switch kind {
            case "white":
                content
                    .padding(7)
                    .background(Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            case "hair":
                content
                    .overlay {
                        Rectangle().strokeBorder(tint.opacity(0.55), lineWidth: 1)
                    }
            case "round":
                content
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            case "film":
                // 胶片：上下两条黑边，边上打一排小方孔
                content
                    .padding(.vertical, 9)
                    .background(Color(hexString: "2B2A27")!)
                    .overlay(alignment: .top) { filmHoles }
                    .overlay(alignment: .bottom) { filmHoles }
            case "dash":
                content
                    .padding(4)
                    .overlay {
                        Rectangle().strokeBorder(tint.opacity(0.7),
                                                 style: StrokeStyle(lineWidth: 1.4,
                                                                    dash: [4, 3]))
                    }
            default:
                content
            }
        }

        private var filmHoles: some View {
            HStack(spacing: 6) {
                ForEach(0..<9, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hexString: "F3F1EA")!)
                        .frame(width: 6, height: 4)
                }
            }
            .padding(.vertical, 2.5)
        }
    }

    // MARK: 便签

    /// 便签上的纹路。底色是她挑的那个，这一层只画线。
    struct NoteSkin: View {
        let kind: String

        var body: some View {
            Canvas { ctx, size in
                let ink = Color.black.opacity(0.10)
                var p = Path()
                switch kind {
                case "ruled":
                    var y: CGFloat = 22
                    while y < size.height {
                        p.move(to: CGPoint(x: 8, y: y))
                        p.addLine(to: CGPoint(x: size.width - 8, y: y))
                        y += 16
                    }
                    ctx.stroke(p, with: .color(ink), lineWidth: 0.8)
                case "grid":
                    var y: CGFloat = 10
                    while y < size.height { p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y)); y += 14 }
                    var x: CGFloat = 10
                    while x < size.width { p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height)); x += 14 }
                    ctx.stroke(p, with: .color(ink), lineWidth: 0.7)
                case "punch":
                    // 顶上一排装订孔
                    for i in 0..<4 {
                        let x = size.width * (0.2 + Double(i) * 0.2)
                        p.addEllipse(in: CGRect(x: x - 3, y: 6, width: 6, height: 6))
                    }
                    ctx.fill(p, with: .color(Color.black.opacity(0.16)))
                default:
                    break
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// 便签的外形。撕口和折角是**把纸剪掉一块**，所以是形状不是纹路。
    struct NoteShape: Shape {
        let kind: String

        func path(in r: CGRect) -> Path {
            var p = Path()
            switch kind {
            case "torn":
                // 底边撕开：一排小三角咬进去
                p.move(to: CGPoint(x: r.minX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 7))
                var x = r.maxX
                var up = true
                while x > r.minX {
                    x = max(r.minX, x - 9)
                    p.addLine(to: CGPoint(x: x, y: up ? r.maxY : r.maxY - 7))
                    up.toggle()
                }
                p.closeSubpath()
            case "fold":
                // 右下角折起来一块
                let f: CGFloat = 18
                p.move(to: CGPoint(x: r.minX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - f))
                p.addLine(to: CGPoint(x: r.maxX - f, y: r.maxY))
                p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                p.closeSubpath()
            default:
                p.addRect(r)
            }
            return p
        }
    }

    // MARK: 夹子

    struct Clip: View {
        let kind: String
        let tint: Color

        var body: some View {
            Group {
                switch kind {
                case "paper":
                    // 回形针：两道回折的线
                    PaperClip()
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.4,
                                                         lineCap: .round,
                                                         lineJoin: .round))
                        .frame(width: 16, height: 34)
                case "wood":
                    // 木夹：两条木片夹着，中间一根弹簧线
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hexString: "C9A97A")!)
                            .frame(width: 12, height: 32)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hexString: "B08C62")!)
                            .frame(width: 12, height: 32)
                            .offset(x: 7)
                        Capsule()
                            .fill(Color(hexString: "9A9488")!)
                            .frame(width: 17, height: 3)
                            .offset(x: 3, y: -3)
                    }
                case "bull":
                    // 长尾夹：一个黑梯形加两只银耳朵
                    ZStack(alignment: .top) {
                        Trapezoid()
                            .fill(Color(hexString: "3A362E")!)
                            .frame(width: 24, height: 26)
                        HStack(spacing: 10) {
                            Capsule().fill(Color(hexString: "C9C4B8")!)
                                .frame(width: 3, height: 13)
                            Capsule().fill(Color(hexString: "C9C4B8")!)
                                .frame(width: 3, height: 13)
                        }
                        .offset(y: -7)
                    }
                case "pin":
                    // 别针：一根斜线加一个圆头
                    ZStack {
                        Capsule()
                            .fill(tint)
                            .frame(width: 2.6, height: 30)
                            .rotationEffect(.degrees(28))
                        Circle()
                            .fill(tint)
                            .frame(width: 8, height: 8)
                            .offset(x: -7, y: -13)
                    }
                default:
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint)
                        .frame(width: 20, height: 30)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
                                .padding(4)
                        }
                }
            }
            .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
        }
    }

    /// 回形针那根线
    struct PaperClip: Shape {
        func path(in r: CGRect) -> Path {
            let w = r.width, h = r.height
            var p = Path()
            p.move(to: CGPoint(x: w * 0.28, y: h * 0.92))
            p.addLine(to: CGPoint(x: w * 0.28, y: h * 0.16))
            p.addQuadCurve(to: CGPoint(x: w * 0.78, y: h * 0.16),
                           control: CGPoint(x: w * 0.53, y: h * -0.06))
            p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.80))
            p.addQuadCurve(to: CGPoint(x: w * 0.10, y: h * 0.80),
                           control: CGPoint(x: w * 0.44, y: h * 1.04))
            p.addLine(to: CGPoint(x: w * 0.10, y: h * 0.34))
            return p
        }
    }

    /// 长尾夹那个梯形
    struct Trapezoid: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX + r.width * 0.16, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - r.width * 0.16, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
            return p
        }
    }

    // MARK: 邮票

    /// 邮票的边。锯齿那种是老样子（在外面画），这儿画别的几种。
    struct StampSkin: View {
        let kind: String
        let tint: Color

        var body: some View {
            switch kind {
            case "square":
                Rectangle()
                    .strokeBorder(tint.opacity(0.75), lineWidth: 2.5)
                    .padding(3)
            case "round":
                // 圆戳：两个同心圆
                ZStack {
                    Circle().strokeBorder(tint.opacity(0.75), lineWidth: 2).padding(4)
                    Circle().strokeBorder(tint.opacity(0.45), lineWidth: 1).padding(9)
                }
            case "double":
                ZStack {
                    Rectangle().strokeBorder(tint.opacity(0.7), lineWidth: 1.6).padding(3)
                    Rectangle().strokeBorder(tint.opacity(0.45), lineWidth: 1).padding(7)
                }
            case "aged":
                // 旧票：四角压暗一点，像放久了
                RadialGradient(colors: [.clear, Color(hexString: "8A7B5E")!.opacity(0.28)],
                               center: .center, startRadius: 8, endRadius: 40)
            default:
                Color.clear
            }
        }
    }
}

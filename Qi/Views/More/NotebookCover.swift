import SwiftUI

/// 手帐书架上一本的封面样式
struct NotebookStyle {
    enum Fill { case stripes, linen, gingham, dots, kraft, leather }
    enum Label { case text, plate, oval }
    enum Clasp { case snap, band, none }

    let name: String
    let fill: Fill
    let base: Color
    let accent: Color
    let label: Label
    let clasp: Clasp
    /// 月份字的颜色
    let ink: Color
    /// 封面边上一圈缝线
    var stitch = false

    static func hex(_ s: String) -> Color { Color(hexString: s) ?? .gray }

    static let all: [NotebookStyle] = [
        .init(name: "粉条纹", fill: .stripes, base: hex("FBE9E6"), accent: hex("F3C6C8"),
              label: .text, clasp: .snap, ink: hex("B8863B")),
        .init(name: "雾蓝亚麻", fill: .linen, base: hex("A9C4DC"), accent: hex("6F8FAE"),
              label: .plate, clasp: .band, ink: hex("3D3631")),
        .init(name: "黄格子", fill: .gingham, base: hex("FDE3A3"), accent: hex("F0B43C"),
              label: .oval, clasp: .snap, ink: hex("3D3631")),
        .init(name: "薄荷条纹", fill: .stripes, base: hex("E5F4EA"), accent: hex("A9D8BD"),
              label: .text, clasp: .snap, ink: hex("B8863B")),
        .init(name: "牛皮纸", fill: .kraft, base: hex("D7B48A"), accent: hex("7A5030"),
              label: .plate, clasp: .band, ink: hex("3D3631"), stitch: true),
        .init(name: "紫波点", fill: .dots, base: hex("CBBFE3"), accent: hex("FFFFFF"),
              label: .oval, clasp: .snap, ink: hex("3D3631")),
        .init(name: "墨绿皮面", fill: .leather, base: hex("2F4A3F"), accent: hex("23382F"),
              label: .text, clasp: .band, ink: hex("D9B36A"), stitch: true),
        .init(name: "灰蓝格子", fill: .gingham, base: hex("E3EBF2"), accent: hex("8FA7BF"),
              label: .text, clasp: .snap, ink: hex("5B6F84"))
    ]

    static let monthNames = ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
                             "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]
    static let monthShort = ["JAN", "FEB", "MAR", "APR", "MAY", "JUNE",
                             "JULY", "AUG", "SEPT", "OCT", "NOV", "DEC"]
}

/// 一本日记本：深色底板从书脊包过来，比封面长出一截，白色书页夹在中间
struct NotebookCover: View {
    let style: NotebookStyle
    /// 1…12
    let month: Int

    private let board = Color(hexString: "3D3631") ?? .black

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let spine = max(10, w * 0.1)
            let lip = max(8, h * 0.06)
            let coverH = h - lip
            ZStack(alignment: .topLeading) {
                // 底板（连着书脊）：比封面窄一点、长一截
                UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 7,
                                       bottomTrailingRadius: 9, topTrailingRadius: 9, style: .continuous)
                    .fill(board)
                    .frame(width: w - 3, height: h)

                // 书页：夹在封面下沿和底板之间
                pagesEdge
                    .frame(width: w - spine - 9, height: lip - 2.5)
                    .offset(x: spine + 1, y: coverH - 0.5)

                // 封面
                coverFace(w: w - spine + 2, h: coverH)
                    .frame(width: w - spine + 2, height: coverH)
                    .clipShape(coverShape)
                    .overlay(coverShape.stroke(board.opacity(0.9), lineWidth: 1.2))
                    .offset(x: spine - 2)

                // 书脊上的两道压痕
                VStack(spacing: 0) {
                    Spacer().frame(height: coverH * 0.08)
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1.5)
                    Spacer()
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1.5)
                    Spacer().frame(height: coverH * 0.08)
                }
                .frame(width: spine - 3, height: coverH)
                .offset(x: 1)

                clasp(w: w, coverH: coverH)
                label(w: w, spine: spine, coverH: coverH)
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
    }

    private var coverShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2,
                               bottomTrailingRadius: 10, topTrailingRadius: 10, style: .continuous)
    }

    private var pagesEdge: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hexString: "FFFDF7") ?? .white))
            var y: CGFloat = 1.6
            while y < size.height {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(Color(hexString: "DDD3C3") ?? .gray), lineWidth: 0.6)
                y += 2
            }
        }
    }

    // MARK: 封面花纹

    private func coverFace(w: CGFloat, h: CGFloat) -> some View {
        let s = style
        return Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(Path(rect), with: .color(s.base))
            switch s.fill {
            case .stripes:
                let bar = max(5, size.width / 15)
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: bar * 0.55, height: size.height)), with: .color(s.accent))
                    x += bar
                }
            case .linen:
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.6)),
                             with: .color(Color.white.opacity(0.22)))
                    y += 2.4
                }
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: 0.6, height: size.height)),
                             with: .color(s.accent.opacity(0.18)))
                    x += 2.4
                }
            case .gingham:
                let cell = max(7, size.width / 10)
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: cell / 2, height: size.height)),
                             with: .color(s.accent.opacity(0.42)))
                    x += cell
                }
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: cell / 2)),
                             with: .color(s.accent.opacity(0.42)))
                    y += cell
                }
            case .dots:
                let step = max(9, size.width / 9)
                var row = 0
                var y: CGFloat = step / 2
                while y < size.height {
                    var x: CGFloat = row % 2 == 0 ? step / 2 : step
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)),
                                 with: .color(s.accent))
                        x += step
                    }
                    y += step * 0.8
                    row += 1
                }
            case .kraft:
                var seed: UInt64 = 7
                for _ in 0..<Int(size.width * size.height / 26) {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let x = CGFloat(seed >> 40 & 0xFFFF) / 65535 * size.width
                    let y = CGFloat(seed >> 20 & 0xFFFF) / 65535 * size.height
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.1, height: 1.1)),
                             with: .color(s.accent.opacity(0.22)))
                }
            case .leather:
                ctx.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(0.06), Color.black.opacity(0.12)]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            }
            if s.stitch {
                let r = rect.insetBy(dx: 6, dy: 6)
                ctx.stroke(Path(roundedRect: r, cornerRadius: 6),
                           with: .color((s.fill == .leather ? s.ink : Color.white).opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
            }
        }
    }

    // MARK: 搭扣 / 松紧带

    @ViewBuilder
    private func clasp(w: CGFloat, coverH: CGFloat) -> some View {
        switch style.clasp {
        case .snap:
            let tw = w * 0.17, th = coverH * 0.13
            ZStack {
                UnevenRoundedRectangle(topLeadingRadius: th / 2, bottomLeadingRadius: th / 2,
                                       bottomTrailingRadius: 0, topTrailingRadius: 0)
                    .fill(style.fill == .stripes || style.fill == .dots ? style.accent : style.base)
                UnevenRoundedRectangle(topLeadingRadius: th / 2, bottomLeadingRadius: th / 2,
                                       bottomTrailingRadius: 0, topTrailingRadius: 0)
                    .stroke(board, lineWidth: 1.3)
                Circle().fill(Color.white)
                    .overlay(Circle().stroke(board, lineWidth: 1.3))
                    .frame(width: th * 0.42, height: th * 0.42)
                    .offset(x: -tw * 0.08)
            }
            .frame(width: tw, height: th)
            .offset(x: w - tw + 0.5, y: coverH * 0.47)
        case .band:
            Rectangle()
                .fill(Color(hexString: "2C2F3A") ?? .black)
                .frame(width: max(3.5, w * 0.035), height: coverH)
                .offset(x: w - w * 0.14)
        case .none:
            EmptyView()
        }
    }

    // MARK: 月份标签

    @ViewBuilder
    private func label(w: CGFloat, spine: CGFloat, coverH: CGFloat) -> some View {
        let i = max(0, min(11, month - 1))
        let faceW = w - spine
        switch style.label {
        case .text:
            Text(NotebookStyle.monthNames[i])
                .font(.system(size: max(8, w * 0.07), weight: .medium, design: .serif))
                .tracking(1.6)
                .foregroundStyle(style.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: faceW * 0.8)
                .offset(x: spine + faceW * 0.08, y: coverH * 0.1)
        case .plate:
            Text(NotebookStyle.monthShort[i])
                .font(.system(size: max(7, w * 0.062), weight: .semibold, design: .serif))
                .tracking(1)
                .foregroundStyle(board)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.white)
                .overlay(Rectangle().inset(by: 1.5).stroke(board, lineWidth: 0.8))
                .overlay(Rectangle().stroke(board, lineWidth: 1.1))
                .frame(width: faceW * 0.8)
                .offset(x: spine + faceW * 0.06, y: coverH * 0.1)
        case .oval:
            Text(NotebookStyle.monthNames[i].capitalized)
                .font(.system(size: max(7, w * 0.065), design: .serif))
                .foregroundStyle(board)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: faceW * 0.52, height: coverH * 0.15)
                .background(Ellipse().fill(Color(hexString: "FFFAF0") ?? .white))
                .overlay(Ellipse().stroke(board, lineWidth: 1.2))
                .frame(width: faceW * 0.86)
                .offset(x: spine + faceW * 0.02, y: coverH * 0.2)
        }
    }
}

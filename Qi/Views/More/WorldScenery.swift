import SwiftUI

// MARK: - 小岛的风景
//
// 树、灌木、石头、篱笆、小屋这些「景」，跟她摆的家具分开：
// 它们是岛本来就有的，也能在「摆东西 → 风景」里加、在「拿走」里拿掉。
// 画法是柔和的插画：几团圆叠出树冠、底下一层深色压出体积、脚下一团软影子。

enum WorldDecorKind: String, CaseIterable, Identifiable {
    case tree, blossom, pine, bush, berry, rock, rocks, stump, mushroom, tallgrass,
         lamp, fence, lily, reed, stone, bench, house, mailbox, sign, well, pot
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tree: return "大树"
        case .blossom: return "樱花树"
        case .pine: return "松树"
        case .bush: return "灌木"
        case .berry: return "莓果丛"
        case .rock: return "石头"
        case .rocks: return "碎石"
        case .stump: return "树桩"
        case .mushroom: return "蘑菇"
        case .tallgrass: return "高草"
        case .lamp: return "路灯"
        case .fence: return "篱笆"
        case .lily: return "荷叶"
        case .reed: return "芦苇"
        case .stone: return "踏脚石"
        case .bench: return "长椅"
        case .house: return "小屋"
        case .mailbox: return "信箱"
        case .sign: return "木牌"
        case .well: return "水井"
        case .pot: return "花盆"
        }
    }
}

struct DecorCanvas: View, Equatable {
    let decor: [WorldDecor]
    let tile: CGFloat
    let width: Int
    let height: Int
    let night: Bool

    static func == (a: DecorCanvas, b: DecorCanvas) -> Bool {
        a.decor == b.decor && a.night == b.night && a.tile == b.tile
    }

    private static func noise(_ x: Int, _ y: Int, _ k: Int = 0) -> CGFloat {
        let v = sin(Double(x) * 12.9898 + Double(y) * 78.233 + Double(k) * 37.719) * 43758.5453
        return CGFloat(v - floor(v))
    }
    private static func c(_ h: String, _ a: Double = 1) -> Color { Color(hexString: h)!.opacity(a) }

    var body: some View {
        Canvas { gc, _ in
            for d in decor.sorted(by: { $0.y < $1.y }) {
                guard let k = WorldDecorKind(rawValue: d.kind) else { continue }
                draw(gc, k, d.x, d.y)
            }
        }
        .frame(width: CGFloat(width) * tile, height: CGFloat(height) * tile)
        .allowsHitTesting(false)
    }

    // MARK: 小工具

    private func blob(_ gc: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ col: Color) {
        gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(col))
    }

    private func shadow(_ gc: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        gc.drawLayer { l in
            l.addFilter(.blur(radius: 2))
            l.fill(Path(ellipseIn: CGRect(x: x - w, y: y - h, width: w * 2, height: h * 2)),
                   with: .color(Color(red: 0.2, green: 0.25, blue: 0.15).opacity(0.2)))
        }
    }

    private func rr(_ gc: GraphicsContext, _ r: CGRect, _ rad: CGFloat, _ col: Color) {
        gc.fill(Path(roundedRect: r, cornerRadius: rad), with: .color(col))
    }

    private func line(_ gc: GraphicsContext, _ pts: [CGPoint], _ col: Color, _ w: CGFloat) {
        var p = Path()
        p.addLines(pts)
        gc.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: w, lineCap: .round))
    }

    // MARK: 每一样

    private func draw(_ base: GraphicsContext, _ k: WorldDecorKind, _ gx: Int, _ gy: Int) {
        let t = tile
        let x = CGFloat(gx) * t + t / 2
        let b = CGFloat(gy) * t + t * 0.92
        var gc = base
        switch k {
        case .tree, .blossom:
            let big = k == .tree
            let (dk, d, m, l) = big ? ("5F8F55", "79A86A", "92BF7C", "B5D79B") : ("CF7F98", "E59AB0", "F1B5C6", "FAD6E0")
            gc.translateBy(x: x, y: b); gc.scaleBy(x: 1.35, y: 1.35); gc.translateBy(x: -x, y: -b)
            shadow(gc, x + 10, b, 32, 10)
            rr(gc, CGRect(x: x - 4.5, y: b - 30, width: 9, height: 30), 3, Self.c("8E6A4C"))
            gc.fill(Path(CGRect(x: x - 1.5, y: b - 28, width: 2, height: 24)), with: .color(Self.c("A98260")))
            blob(gc, x - 14, b - 37, 18, Self.c(dk)); blob(gc, x + 14, b - 39, 18, Self.c(dk)); blob(gc, x, b - 55, 22, Self.c(dk))
            blob(gc, x - 14, b - 40, 17, Self.c(d)); blob(gc, x + 14, b - 42, 17, Self.c(d)); blob(gc, x, b - 58, 21, Self.c(d))
            blob(gc, x - 6, b - 50, 17, Self.c(m)); blob(gc, x + 10, b - 56, 14, Self.c(m))
            blob(gc, x - 8, b - 62, 10, Self.c(l)); blob(gc, x + 4, b - 67, 6, Self.c(l))
            for i in 0..<7 {
                blob(gc, x - 20 + Self.noise(gx, gy, i) * 40, b - 74 + Self.noise(gx, gy, i + 3) * 36,
                     big ? 1.6 : 2, big ? Self.c("D2ECB4", 0.9) : .white)
            }
        case .pine:
            gc.translateBy(x: x, y: b); gc.scaleBy(x: 1.3, y: 1.3); gc.translateBy(x: -x, y: -b)
            shadow(gc, x + 6, b, 22, 7)
            gc.fill(Path(CGRect(x: x - 3, y: b - 14, width: 6, height: 14)), with: .color(Self.c("8A6A4E")))
            for (col, w, y) in [("4F8268", 28.0, b - 8), ("5E9478", 26.0, b - 10), ("6FA587", 21.0, b - 28), ("83B798", 15.0, b - 44)] {
                var p = Path()
                p.move(to: CGPoint(x: x - w, y: y))
                p.addQuadCurve(to: CGPoint(x: x + w, y: y), control: CGPoint(x: x, y: y - 34))
                p.closeSubpath()
                gc.fill(p, with: .color(Self.c(col)))
            }
        case .bush, .berry:
            shadow(gc, x + 4, b, 20, 6)
            blob(gc, x - 9, b - 9, 11, Self.c("83B26F")); blob(gc, x + 9, b - 9, 11, Self.c("83B26F"))
            blob(gc, x, b - 15, 13, Self.c("98C483")); blob(gc, x - 4, b - 19, 5, Self.c("B6D89E"))
            if k == .berry {
                for i in 0..<5 {
                    blob(gc, x - 12 + Self.noise(gx, gy, i) * 24, b - 22 + Self.noise(gx, gy, i + 5) * 16, 2.2, Self.c("D9546E"))
                }
            }
        case .rock, .rocks:
            let n = k == .rocks ? 3 : 1
            for i in 0..<n {
                let ox: CGFloat = n > 1 ? CGFloat(i - 1) * 12 : 0, s: CGFloat = n > 1 ? 0.6 : 1
                shadow(gc, x + ox + 3, b, 14 * s, 4 * s)
                gc.fill(Path(ellipseIn: CGRect(x: x + ox - 15 * s, y: b - 19 * s, width: 30 * s, height: 22 * s)),
                        with: .color(Self.c("B9B2A7")))
                gc.fill(Path(ellipseIn: CGRect(x: x + ox - 11 * s, y: b - 16 * s, width: 14 * s, height: 8 * s)),
                        with: .color(Self.c("D4CEC4")))
            }
        case .stump:
            shadow(gc, x + 3, b, 12, 4)
            rr(gc, CGRect(x: x - 10, y: b - 14, width: 20, height: 14), 4, Self.c("9A7354"))
            gc.fill(Path(ellipseIn: CGRect(x: x - 10, y: b - 18, width: 20, height: 8)), with: .color(Self.c("D8B48C")))
            gc.stroke(Path(ellipseIn: CGRect(x: x - 5, y: b - 16, width: 10, height: 4)), with: .color(Self.c("B48C66")), lineWidth: 1)
        case .mushroom:
            for (i, (dx, dy)) in [(-6.0, 0.0), (6.0, 3.0)].enumerated() {
                shadow(gc, x + dx, b, 6, 2)
                gc.fill(Path(CGRect(x: x + dx - 2, y: b - 9 + dy, width: 4, height: 9 - dy)), with: .color(Self.c("F6EDE2")))
                var cap = Path()
                cap.addArc(center: CGPoint(x: x + dx, y: b - 10 + dy), radius: 7, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                cap.closeSubpath()
                gc.fill(cap, with: .color(Self.c(i == 1 ? "E8758F" : "F09A62")))
                blob(gc, x + dx - 2, b - 13 + dy, 1.2, .white)
            }
        case .tallgrass:
            for i in 0..<9 {
                let px = x - 14 + CGFloat(i) * 3.5, h = 12 + Self.noise(gx, gy, i) * 12
                var p = Path()
                p.move(to: CGPoint(x: px, y: b))
                p.addQuadCurve(to: CGPoint(x: px + CGFloat(i % 3 - 1) * 3, y: b - h), control: CGPoint(x: px + 2, y: b - h / 2))
                gc.stroke(p, with: .color(Self.c(i % 2 == 1 ? "7EA96A" : "9BC284")), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        case .lamp:
            shadow(gc, x, b, 7, 3)
            gc.fill(Path(CGRect(x: x - 1.5, y: b - 38, width: 3, height: 38)), with: .color(Self.c("5E5652")))
            rr(gc, CGRect(x: x - 6, y: b - 46, width: 12, height: 9), 2, Self.c("5E5652"))
            rr(gc, CGRect(x: x - 4, y: b - 44, width: 8, height: 6), 1, night ? Self.c("FFE2A0") : Self.c("F6EBD3"))
        case .fence:
            let left = CGFloat(gx) * t
            gc.fill(Path(CGRect(x: left, y: b - 16, width: t, height: 3.5)), with: .color(Self.c("C9A47D")))
            gc.fill(Path(CGRect(x: left, y: b - 8, width: t, height: 3.5)), with: .color(Self.c("C9A47D")))
            for px in [left + 4, left + t - 9] {
                rr(gc, CGRect(x: px, y: b - 22, width: 5, height: 22), 2, Self.c("B48C66"))
            }
        case .lily:
            let X = CGFloat(gx) * t + 18, Y = CGFloat(gy) * t + 20
            var p = Path()
            p.move(to: CGPoint(x: X, y: Y))
            p.addArc(center: CGPoint(x: X, y: Y), radius: 8, startAngle: .radians(0.3), endAngle: .radians(2 * .pi - 0.1), clockwise: false)
            p.closeSubpath()
            gc.fill(p, with: .color(Self.c("7FB27A")))
            blob(gc, X + 3, Y - 2, 2.5, Self.c("F4A7B9"))
        case .reed:
            for i in 0..<4 {
                let px = CGFloat(gx) * t + 10 + CGFloat(i) * 6
                let tipX = px + (i % 2 == 1 ? 3 : -2), tipY = b - 26 - CGFloat(i) * 2
                var p = Path()
                p.move(to: CGPoint(x: px, y: b))
                p.addQuadCurve(to: CGPoint(x: tipX, y: tipY), control: CGPoint(x: px + 2, y: b - 14))
                gc.stroke(p, with: .color(Self.c("7E9E63")), lineWidth: 1.4)
                gc.fill(Path(ellipseIn: CGRect(x: tipX - 1.8, y: tipY - 6, width: 3.6, height: 8)), with: .color(Self.c("9C7B58")))
            }
        case .stone:
            let cy = CGFloat(gy) * t + t / 2
            gc.fill(Path(ellipseIn: CGRect(x: x - 11, y: cy - 7, width: 22, height: 14)), with: .color(Self.c("D9D3C8")))
            gc.fill(Path(ellipseIn: CGRect(x: x - 8, y: cy - 4.5, width: 10, height: 5)), with: .color(Self.c("E9E4DB")))
        case .bench:
            shadow(gc, x + t / 2, b, 30, 6)
            rr(gc, CGRect(x: x - 14, y: b - 16, width: t + 20, height: 6), 2, Self.c("B48C66"))
            rr(gc, CGRect(x: x - 14, y: b - 26, width: t + 20, height: 5), 2, Self.c("B48C66"))
            gc.fill(Path(CGRect(x: x - 10, y: b - 10, width: 3, height: 10)), with: .color(Self.c("8E6A4C")))
            gc.fill(Path(CGRect(x: x + t + 1, y: b - 10, width: 3, height: 10)), with: .color(Self.c("8E6A4C")))
        case .house:
            let X = CGFloat(gx) * t, Y = CGFloat(gy) * t, w = 2 * t, h = 2 * t
            shadow(gc, X + w / 2 + 8, Y + h + 4, w / 2 + 10, 10)
            gc.fill(Path(CGRect(x: X + 6, y: Y + h * 0.45, width: w - 12, height: h * 0.55)), with: .color(Self.c("F6EFE4")))
            gc.fill(Path(CGRect(x: X + w - 22, y: Y + 8, width: 7, height: 14)), with: .color(Self.c("B98E86")))
            var roof = Path()
            roof.move(to: CGPoint(x: X - 2, y: Y + h * 0.5))
            roof.addLine(to: CGPoint(x: X + w / 2, y: Y + 4))
            roof.addLine(to: CGPoint(x: X + w + 2, y: Y + h * 0.5))
            roof.closeSubpath()
            gc.fill(roof, with: .color(Self.c("E9A8B4")))
            for i in 1..<4 {
                line(gc, [CGPoint(x: X + w / 2 - CGFloat(i) * 9, y: Y + 4 + CGFloat(i) * 9),
                          CGPoint(x: X + w / 2 + CGFloat(i) * 9, y: Y + 4 + CGFloat(i) * 9)], Self.c("AA5A6E", 0.35), 1)
            }
            rr(gc, CGRect(x: X + w / 2 - 7, y: Y + h - 22, width: 14, height: 22), 6, Self.c("C9A47D"))
            let win = night ? Self.c("FFDFA0") : Self.c("CFE3EE")
            rr(gc, CGRect(x: X + 12, y: Y + h * 0.6, width: 14, height: 12), 3, win)
            rr(gc, CGRect(x: X + w - 26, y: Y + h * 0.6, width: 14, height: 12), 3, win)
        case .mailbox:
            shadow(gc, x, b, 8, 3)
            gc.fill(Path(CGRect(x: x - 1.5, y: b - 18, width: 3, height: 18)), with: .color(Self.c("8E6A4C")))
            rr(gc, CGRect(x: x - 8, y: b - 28, width: 16, height: 11), 5, Self.c("E8758F"))
            gc.fill(Path(CGRect(x: x + 5, y: b - 30, width: 2, height: 6)), with: .color(Self.c("C9415E")))
            gc.fill(Path(CGRect(x: x + 5, y: b - 30, width: 5, height: 3)), with: .color(Self.c("F2C230")))
        case .sign:
            shadow(gc, x, b, 8, 3)
            gc.fill(Path(CGRect(x: x - 1.5, y: b - 22, width: 3, height: 22)), with: .color(Self.c("8E6A4C")))
            rr(gc, CGRect(x: x - 13, y: b - 30, width: 26, height: 11), 3, Self.c("D9B58F"))
            line(gc, [CGPoint(x: x - 8, y: b - 24.5), CGPoint(x: x + 8, y: b - 24.5)], Self.c("A98260"), 1)
        case .well:
            shadow(gc, x + 3, b, 18, 5)
            rr(gc, CGRect(x: x - 14, y: b - 16, width: 28, height: 16), 6, Self.c("C9C2B7"))
            gc.fill(Path(ellipseIn: CGRect(x: x - 11, y: b - 20, width: 22, height: 8)), with: .color(Self.c("A9D5E6")))
            gc.fill(Path(CGRect(x: x - 13, y: b - 38, width: 3, height: 22)), with: .color(Self.c("8E6A4C")))
            gc.fill(Path(CGRect(x: x + 10, y: b - 38, width: 3, height: 22)), with: .color(Self.c("8E6A4C")))
            var roof = Path()
            roof.move(to: CGPoint(x: x - 17, y: b - 36)); roof.addLine(to: CGPoint(x: x, y: b - 46))
            roof.addLine(to: CGPoint(x: x + 17, y: b - 36)); roof.closeSubpath()
            gc.fill(roof, with: .color(Self.c("E9A8B4")))
        case .pot:
            shadow(gc, x, b, 9, 3)
            var p = Path()
            p.move(to: CGPoint(x: x - 8, y: b - 12)); p.addLine(to: CGPoint(x: x + 8, y: b - 12))
            p.addLine(to: CGPoint(x: x + 6, y: b)); p.addLine(to: CGPoint(x: x - 6, y: b)); p.closeSubpath()
            gc.fill(p, with: .color(Self.c("D98B6A")))
            blob(gc, x - 4, b - 16, 5, Self.c("88B874")); blob(gc, x + 4, b - 17, 5, Self.c("88B874"))
            blob(gc, x, b - 21, 5, Self.c("9CC786"))
            blob(gc, x - 2, b - 23, 2.2, Self.c("F4A7B9")); blob(gc, x + 3, b - 19, 2, Self.c("FBE27A"))
        }
    }
}

// MARK: - 会动的那一层：云影、花瓣、蝴蝶；晚上暗下来、路灯和窗亮、萤火虫

struct AmbientLayer: View {
    let width: Int
    let height: Int
    let tile: CGFloat
    let night: Bool
    /// 路灯、小屋窗户在哪（晚上发光用）
    let lights: [CGPoint]

    private static func noise(_ i: Int, _ k: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + Double(k) * 78.233) * 43758.5453
        return CGFloat(v - floor(v))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let w = size.width, h = size.height
                // 云影：大块软的暗影，慢慢从左往右飘
                for i in 0..<3 {
                    let span = w + 300
                    let x = CGFloat((t * 6 + Double(i) * 230).truncatingRemainder(dividingBy: Double(span))) - 150
                    let y = 120 + CGFloat(i) * 260
                    let r = CGRect(x: x - 120, y: y - 60, width: 240, height: 120)
                    gc.fill(Path(ellipseIn: r), with: .radialGradient(
                        Gradient(colors: [Color(red: 0.16, green: 0.24, blue: 0.2).opacity(night ? 0 : 0.10), .clear]),
                        center: CGPoint(x: r.midX, y: r.midY), startRadius: 0, endRadius: 120))
                }
                if !night {
                    // 飘落的花瓣
                    for i in 0..<10 {
                        let x = (Self.noise(i, 40) * w + CGFloat(t * 6 * Double(1 + i % 3))).truncatingRemainder(dividingBy: w)
                        let y = (Self.noise(i, 41) * h + CGFloat(t * 12)).truncatingRemainder(dividingBy: h)
                        var g = gc
                        g.translateBy(x: x, y: y)
                        g.rotate(by: .radians(t * 0.8 + Double(i)))
                        g.fill(Path(ellipseIn: CGRect(x: -3.2, y: -1.8, width: 6.4, height: 3.6)),
                               with: .color(Color(red: 0.96, green: 0.71, blue: 0.78).opacity(0.9)))
                    }
                    // 两只蝴蝶
                    for (i, col) in [Color(hexString: "F7D36B")!, Color(hexString: "C9B6E8")!].enumerated() {
                        let bx = (i == 0 ? 0.28 : 0.72) * w + CGFloat(sin(t * (0.6 + Double(i) * 0.2))) * 40
                        let by = (i == 0 ? 0.32 : 0.66) * h + CGFloat(cos(t * (0.8 + Double(i) * 0.1))) * 26
                        let f = CGFloat(abs(sin(t * 9 + Double(i)))) * 4 + 1
                        var g = gc
                        g.translateBy(x: bx, y: by)
                        var l = g; l.rotate(by: .radians(-0.4))
                        l.fill(Path(ellipseIn: CGRect(x: -2 * f, y: -3.2, width: f * 2, height: 6.4)), with: .color(col))
                        var r = g; r.rotate(by: .radians(0.4))
                        r.fill(Path(ellipseIn: CGRect(x: 0, y: -3.2, width: f * 2, height: 6.4)), with: .color(col))
                        g.fill(Path(CGRect(x: -0.6, y: -3, width: 1.2, height: 6)), with: .color(Color(hexString: "6E5A4A")!))
                    }
                } else {
                    // 夜色
                    gc.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                            with: .color(Color(red: 0.12, green: 0.14, blue: 0.31).opacity(0.42)))
                    var lit = gc
                    lit.blendMode = .plusLighter
                    for p in lights {
                        lit.fill(Path(ellipseIn: CGRect(x: p.x - 70, y: p.y - 70, width: 140, height: 140)),
                                 with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.84, blue: 0.55).opacity(0.5), .clear]),
                                                       center: p, startRadius: 0, endRadius: 70))
                    }
                    // 萤火虫
                    for i in 0..<22 {
                        let x = Self.noise(i, 50) * w + CGFloat(sin(t * 0.9 + Double(i))) * 10
                        let y = Self.noise(i, 51) * h + CGFloat(cos(t * 1.2 + Double(i))) * 8
                        let a = 0.5 + 0.5 * sin(t * 2 + Double(i))
                        lit.fill(Path(ellipseIn: CGRect(x: x - 6, y: y - 6, width: 12, height: 12)),
                                 with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.96, blue: 0.67).opacity(0.95 * a), .clear]),
                                                       center: CGPoint(x: x, y: y), startRadius: 0, endRadius: 6))
                    }
                }
            }
        }
        .frame(width: CGFloat(width) * tile, height: CGFloat(height) * tile)
        .allowsHitTesting(false)
    }
}

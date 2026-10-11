import SwiftUI

/// 一颗糖画出来的样子。在 100×100 的格子里画，按要的大小缩放。
///
/// 每种造型一套画法（方糖有顶面侧面和糖霜、圆珠是玻璃纸硬糖或棒棒糖、五角星是砂糖软糖、
/// 和果子是五瓣练切、花果子是夹果酱的花边曲奇、小包子是带褶的麻薯、弯豆是月牙软糖、
/// 三角是水果软糖、其余是糖衣巧克力豆），同一种造型按每颗糖分两种样子，颜色跟着配色。
/// 预览见 `_看一眼/糖果预览.html`（同一套画法）。
enum CandyArt {

    struct RGB { var r: Double, g: Double, b: Double }

    static func rgb(_ hex: String) -> RGB {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        return RGB(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }

    static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        RGB(r: a.r * (1 - t) + b.r * t, g: a.g * (1 - t) + b.g * t, b: a.b * (1 - t) + b.b * t)
    }

    static func color(_ c: RGB, _ a: Double = 1) -> Color { Color(red: c.r, green: c.g, blue: c.b, opacity: a) }

    /// 按字算出来的一串随机数（同一颗糖每次画得一样）
    struct Seeded {
        var s: UInt32
        init(_ text: String) {
            var h: UInt32 = 0
            for u in text.unicodeScalars { h = h &* 31 &+ u.value }
            s = h
        }
        mutating func next() -> Double {
            s = s &* 1_103_515_245 &+ 12_345
            return Double(s >> 8) / 16_777_216
        }
    }

    static func variant(_ seed: String) -> Int {
        var r = Seeded(seed)
        _ = r.next()
        return r.next() < 0.5 ? 0 : 1
    }

    static func draw(_ gc: inout GraphicsContext, shape: String, hex: String, seed: String) {
        let b = rgb(hex), white = RGB(r: 1, g: 1, b: 1), ink = RGB(r: 0.24, g: 0.16, b: 0.2)
        let L = mix(b, white, 0.45), LL = mix(b, white, 0.75), D = mix(b, ink, 0.28)
        let v = variant(seed)
        var rnd = Seeded(seed + shape)
        func grad(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> GraphicsContext.Shading {
            .linearGradient(Gradient(stops: [.init(color: color(L), location: 0), .init(color: color(b), location: 0.55),
                                             .init(color: color(D), location: 1)]),
                            startPoint: CGPoint(x: x0, y: y0), endPoint: CGPoint(x: x1, y: y1))
        }
        func gloss(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ a: Double = 0.55) {
            let p = Path(ellipseIn: CGRect(x: -w, y: -h, width: w * 2, height: h * 2))
                .applying(CGAffineTransform(rotationAngle: -0.5).concatenating(CGAffineTransform(translationX: x, y: y)))
            gc.fill(p, with: .color(.white.opacity(a)))
        }
        func speck(_ clip: Path, _ n: Int, _ c: Color, _ size: CGFloat = 1.1) {
            var g = gc
            g.clip(to: clip)
            for _ in 0..<n {
                let x = CGFloat(rnd.next()) * 100, y = CGFloat(rnd.next()) * 100
                let r = size * CGFloat(0.6 + rnd.next() * 0.8)
                g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(c))
            }
        }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        func poly(_ pts: [(CGFloat, CGFloat)]) -> Path {
            var p = Path()
            p.addLines(pts.map { CGPoint(x: $0.0, y: $0.1) })
            p.closeSubpath()
            return p
        }
        let round = StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)

        // 脚下一团软影子
        gc.fill(Path(ellipseIn: CGRect(x: 22, y: 82, width: 56, height: 9)), with: .color(Color(red: 0.27, green: 0.2, blue: 0.24).opacity(0.1)))

        switch shape {
        case "方糖":
            let top = poly([(50, 22), (80, 36), (50, 50), (20, 36)])
            let left = poly([(20, 36), (50, 50), (50, 82), (20, 68)])
            let right = poly([(80, 36), (50, 50), (50, 82), (80, 68)])
            gc.fill(top, with: .color(color(LL)))
            gc.fill(left, with: .color(color(b)))
            gc.fill(right, with: .color(color(D)))
            speck(top, 26, .white.opacity(0.9)); speck(left, 18, color(LL, 0.8)); speck(right, 14, color(L, 0.5))
            for p in [top, left, right] { gc.stroke(p, with: .color(color(mix(D, ink, 0.3), 0.35)), style: round) }
            if v == 1 {
                var h = Path()
                h.move(to: CGPoint(x: 50, y: 41))
                h.addCurve(to: CGPoint(x: 44, y: 33), control1: CGPoint(x: 50, y: 40), control2: CGPoint(x: 44, y: 37))
                h.addCurve(to: CGPoint(x: 50, y: 33), control1: CGPoint(x: 44, y: 29), control2: CGPoint(x: 50, y: 29))
                h.addCurve(to: CGPoint(x: 56, y: 33), control1: CGPoint(x: 50, y: 29), control2: CGPoint(x: 56, y: 29))
                h.addCurve(to: CGPoint(x: 50, y: 41), control1: CGPoint(x: 56, y: 37), control2: CGPoint(x: 50, y: 40))
                gc.fill(h, with: .color(color(mix(b, RGB(r: 0.94, g: 0.47, b: 0.55), 0.6))))
            }

        case "圆珠":
            if v == 1 {
                // 棒棒糖：一圈一圈的螺旋
                var stick = Path(); stick.move(to: CGPoint(x: 50, y: 54)); stick.addLine(to: CGPoint(x: 50, y: 90))
                gc.stroke(stick, with: .color(Color(red: 0.96, green: 0.94, blue: 0.91)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                let ball = circle(50, 40, 24)
                gc.fill(ball, with: .color(color(LL)))
                var g = gc; g.clip(to: ball)
                var sp = Path(); var t = 0.0
                sp.move(to: CGPoint(x: 50, y: 40))
                while t < 14 { sp.addLine(to: CGPoint(x: 50 + cos(t) * t * 1.8, y: 40 + sin(t) * t * 1.8)); t += 0.1 }
                g.stroke(sp, with: .color(color(b)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                gloss(40, 30, 8, 4)
            } else {
                // 玻璃纸包着，两头拧起来
                gc.fill(poly([(26, 52), (6, 40), (9, 52), (5, 64)]), with: .color(color(LL, 0.75)))
                gc.fill(poly([(74, 52), (94, 40), (91, 52), (95, 64)]), with: .color(color(LL, 0.75)))
                for a in [(10.0, 44.0, 22.0, 52.0), (9, 60, 22, 52), (90, 44, 78, 52), (91, 60, 78, 52)] {
                    var l = Path(); l.move(to: CGPoint(x: a.0, y: a.1)); l.addLine(to: CGPoint(x: a.2, y: a.3))
                    gc.stroke(l, with: .color(color(L)), lineWidth: 1)
                }
                let ball = circle(50, 52, 24)
                gc.fill(ball, with: grad(30, 30, 70, 74))
                var g = gc; g.clip(to: ball)
                for k in -3...3 {
                    var s = Path()
                    let x = 30 + CGFloat(k) * 9
                    s.move(to: CGPoint(x: x, y: 28))
                    s.addQuadCurve(to: CGPoint(x: x, y: 78), control: CGPoint(x: x + 20, y: 52))
                    g.stroke(s, with: .color(color(LL, 0.85)), lineWidth: 4)
                }
                gloss(41, 41, 8, 4.5)
            }

        case "五角星":
            var p = Path()
            for i in 0..<10 {
                let a = -Double.pi / 2 + Double(i) * .pi / 5, r: Double = i % 2 == 1 ? 14 : 30
                let pt = CGPoint(x: 50 + cos(a) * r, y: 52 + sin(a) * r)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            gc.stroke(p, with: grad(25, 25, 75, 80), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            gc.fill(p, with: grad(25, 25, 75, 80))
            if v == 0 {
                speck(p, 40, .white.opacity(0.85), 1)
            } else {
                gc.stroke(p, with: .color(color(LL, 0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 3]))
            }
            gloss(42, 40, 6, 3.5, 0.6)

        case "和果子":
            let fill = grad(25, 25, 75, 80)
            for i in 0..<5 {
                let a = -Double.pi / 2 + Double(i) * 2 * .pi / 5
                gc.fill(circle(50 + cos(a) * 15, 52 + sin(a) * 15, 15), with: fill)
            }
            for i in 0..<5 {
                let a = -Double.pi / 2 + Double(i) * 2 * .pi / 5 + .pi / 5
                var l = Path(); l.move(to: CGPoint(x: 50, y: 52)); l.addLine(to: CGPoint(x: 50 + cos(a) * 24, y: 52 + sin(a) * 24))
                gc.stroke(l, with: .color(color(D, 0.45)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
            gc.fill(circle(50, 52, 5), with: .color(v == 1 ? Color(red: 0.98, green: 0.89, blue: 0.65) : color(LL)))
            for i in 0..<6 {
                gc.fill(circle(50 + cos(Double(i)) * 3, 52 + sin(Double(i)) * 3, 1), with: .color(Color(red: 0.95, green: 0.77, blue: 0.42)))
            }
            gloss(38, 36, 7, 3.5, 0.4)

        case "花果子":
            // 花边曲奇：一圈小圆鼓出来，中间一块果酱
            let cookie = Color(red: 0.91, green: 0.78, blue: 0.6)
            var c = circle(50, 52, 22)
            for i in 0..<12 {
                let a = Double(i) * .pi / 6
                c.addPath(circle(50 + cos(a) * 22, 52 + sin(a) * 22, 8))
            }
            gc.fill(c, with: .color(cookie))
            speck(c, 14, Color(red: 0.59, green: 0.39, blue: 0.24).opacity(0.35), 0.9)
            gc.stroke(circle(50, 52, 15), with: .color(Color(red: 0.75, green: 0.58, blue: 0.4).opacity(0.5)), lineWidth: 1)
            gc.fill(circle(50, 52, 11), with: grad(38, 40, 62, 64))
            if v == 1 {
                var st = Path()
                for i in 0..<10 {
                    let a = -Double.pi / 2 + Double(i) * .pi / 5, r: Double = i % 2 == 1 ? 5 : 11
                    let pt = CGPoint(x: 50 + cos(a) * r, y: 52 + sin(a) * r)
                    if i == 0 { st.move(to: pt) } else { st.addLine(to: pt) }
                }
                st.closeSubpath()
                gc.fill(st, with: .color(color(b)))
            }
            gloss(46, 47, 4, 2, 0.7)

        case "小包子":
            var p = Path()
            p.move(to: CGPoint(x: 50, y: 26))
            p.addCurve(to: CGPoint(x: 80, y: 62), control1: CGPoint(x: 66, y: 26), control2: CGPoint(x: 80, y: 46))
            p.addCurve(to: CGPoint(x: 50, y: 82), control1: CGPoint(x: 80, y: 76), control2: CGPoint(x: 66, y: 82))
            p.addCurve(to: CGPoint(x: 20, y: 62), control1: CGPoint(x: 34, y: 82), control2: CGPoint(x: 20, y: 76))
            p.addCurve(to: CGPoint(x: 50, y: 26), control1: CGPoint(x: 20, y: 46), control2: CGPoint(x: 34, y: 26))
            gc.fill(p, with: grad(25, 25, 75, 85))
            for k in -2...2 {
                var l = Path()
                l.move(to: CGPoint(x: 50, y: 28))
                l.addQuadCurve(to: CGPoint(x: 50 + CGFloat(k) * 9, y: 44), control: CGPoint(x: 50 + CGFloat(k) * 6, y: 34))
                gc.stroke(l, with: .color(color(D, 0.4)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            }
            if v == 1 {
                gc.fill(Path(ellipseIn: CGRect(x: 31, y: 61, width: 10, height: 6)), with: .color(Color(red: 0.97, green: 0.72, blue: 0.77)))
                gc.fill(Path(ellipseIn: CGRect(x: 59, y: 61, width: 10, height: 6)), with: .color(Color(red: 0.97, green: 0.72, blue: 0.77)))
                gc.fill(circle(42, 58, 1.6), with: .color(Color(red: 0.43, green: 0.29, blue: 0.31)))
                gc.fill(circle(58, 58, 1.6), with: .color(Color(red: 0.43, green: 0.29, blue: 0.31)))
            }
            gloss(38, 46, 8, 4, 0.45)

        case "弯豆":
            let moon = circle(50, 52, 28).subtracting(circle(62, 42, 24))
            gc.fill(moon, with: grad(22, 30, 70, 82))
            if v == 1 { speck(moon, 14, .white.opacity(0.7), 1.6) }
            let hl = Path(ellipseIn: CGRect(x: -4, y: -8, width: 8, height: 16))
                .applying(CGAffineTransform(rotationAngle: 0.4).concatenating(CGAffineTransform(translationX: 32, y: 58)))
            gc.fill(hl, with: .color(.white.opacity(0.55)))

        case "三角":
            var p = Path()
            p.move(to: CGPoint(x: 50, y: 22))
            p.addQuadCurve(to: CGPoint(x: 56, y: 26), control: CGPoint(x: 54, y: 22))
            p.addLine(to: CGPoint(x: 80, y: 72))
            p.addQuadCurve(to: CGPoint(x: 76, y: 78), control: CGPoint(x: 82, y: 78))
            p.addLine(to: CGPoint(x: 24, y: 78))
            p.addQuadCurve(to: CGPoint(x: 20, y: 72), control: CGPoint(x: 18, y: 78))
            p.addLine(to: CGPoint(x: 44, y: 26))
            p.addQuadCurve(to: CGPoint(x: 50, y: 22), control: CGPoint(x: 46, y: 22))
            gc.fill(p, with: grad(30, 25, 70, 80))
            speck(p, 30, .white.opacity(0.85), 1)
            if v == 1 {
                var g = gc; g.clip(to: p)
                g.fill(Path(CGRect(x: 0, y: 56, width: 100, height: 7)), with: .color(color(LL, 0.8)))
            }
            gloss(44, 40, 4, 7, 0.5)

        default:
            // 糖衣巧克力豆：扁扁的一颗，上面印一个小记号
            gc.fill(Path(ellipseIn: CGRect(x: 23, y: 32, width: 54, height: 44)), with: grad(25, 30, 75, 80))
            var under = Path()
            under.addArc(center: CGPoint(x: 50, y: 62), radius: 24, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
            gc.fill(under.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: 0.5, tx: 0, ty: 31)), with: .color(color(D, 0.35)))
            let mark = v == 1 ? "♡" : "✦"
            gc.draw(Text(mark).font(.system(size: 14, weight: .bold)).foregroundColor(.white.opacity(0.92)),
                    at: CGPoint(x: 50, y: 53))
            gloss(38, 42, 9, 4.5, 0.6)
        }
    }
}

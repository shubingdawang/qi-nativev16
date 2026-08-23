import SwiftUI

// MARK: - 手帐素材库
//
// 她要的是「贴纸／胶带／纸张，网上免费的那些」。
//
// **但这儿一张图都没打包进来**，全是画出来的。三个理由：
//
//   1. 网上「免费」的素材，授权大多写得含糊，有的还禁止再分发。
//      打进包里等于把风险塞给她。
//   2. 图是死的。画出来的能**跟着颜色走**——同一张叶子，
//      她换个色就是另一张贴纸，不用再找一套。
//   3. 体积。一套像样的手帐素材几十上百 MB，她那台机器空间是有数的。
//
// 这跟塔罗那 78 张、书脊色、clawd 那只是同一条路子：**用形状算出来**。
//
// 真的想要网上那些的话，「剪贴」那一样管这件事：
// 她自己挑一张 PNG 贴进来，透明底原样留着（走 `saveOriginal`，不重编码）。

// MARK: 纸

/// 纸底。**编辑页和快照共用这一份**——
/// 两份迟早会长歪，那时候他看到的就不是她看到的了。
struct JournalPaperView: View {

    let hex: String
    /// plain / grid / ruled / dot / graph / stripe
    let pattern: String

    private var base: Color {
        Color(hexString: hex) ?? Color(hexString: "F3E9D8") ?? .white
    }

    /// 纹路的颜色：比纸底深一点点。**不用固定的灰**——
    /// 深棕纸上压一层灰线会脏，压一层"更深的自己"才像纸的压纹。
    private var lineColor: Color { Color.black.opacity(0.07) }

    var body: some View {
        base.overlay {
            Canvas { ctx, size in
                switch pattern {
                case "grid":   grid(&ctx, size, step: 26)
                case "graph":  grid(&ctx, size, step: 12)
                case "ruled":  ruled(&ctx, size, step: 30)
                case "dot":    dots(&ctx, size, step: 24)
                case "stripe": stripes(&ctx, size, step: 22)
                default:       break
                }
            }
            .allowsHitTesting(false)
        }
        .overlay {
            // 纸的颗粒。很淡，凑近才看得见——
            // 没有它那就是一块塑料色板，不像纸。
            GrainOverlay(opacity: 0.05)
        }
    }

    private func grid(_ ctx: inout GraphicsContext, _ size: CGSize, step: CGFloat) {
        var p = Path()
        var x: CGFloat = 0
        while x <= size.width {
            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        var y: CGFloat = 0
        while y <= size.height {
            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        ctx.stroke(p, with: .color(lineColor), lineWidth: 0.6)
    }

    private func ruled(_ ctx: inout GraphicsContext, _ size: CGSize, step: CGFloat) {
        var p = Path()
        var y: CGFloat = step
        while y <= size.height {
            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        ctx.stroke(p, with: .color(lineColor), lineWidth: 0.7)
    }

    private func dots(_ ctx: inout GraphicsContext, _ size: CGSize, step: CGFloat) {
        var p = Path()
        var y: CGFloat = step / 2
        while y <= size.height {
            var x: CGFloat = step / 2
            while x <= size.width {
                p.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                x += step
            }
            y += step
        }
        ctx.fill(p, with: .color(lineColor.opacity(0.9)))
    }

    private func stripes(_ ctx: inout GraphicsContext, _ size: CGSize, step: CGFloat) {
        var p = Path()
        var x: CGFloat = 0
        while x <= size.width {
            p.addRect(CGRect(x: x, y: 0, width: step / 2, height: size.height))
            x += step
        }
        ctx.fill(p, with: .color(lineColor.opacity(0.55)))
    }
}

// MARK: 胶带

/// 一条胶带。半透明、两头是撕开的毛边，上面可以有花纹。
struct JournalTapeView: View {

    let color: Color
    /// plain / stripe / check / dot / wave / dash
    let pattern: String
    var width: CGFloat = 110
    var height: CGFloat = 26

    var body: some View {
        ZStack {
            TornTape()
                .fill(color.opacity(0.62))
            Canvas { ctx, size in
                let ink = Color.white.opacity(0.5)
                switch pattern {
                case "stripe":
                    var p = Path()
                    var x: CGFloat = -size.height
                    while x < size.width {
                        p.move(to: CGPoint(x: x, y: size.height))
                        p.addLine(to: CGPoint(x: x + size.height, y: 0))
                        x += 9
                    }
                    ctx.stroke(p, with: .color(ink), lineWidth: 3)
                case "check":
                    var p = Path()
                    var x: CGFloat = 0
                    while x < size.width {
                        p.addRect(CGRect(x: x, y: 0, width: 4, height: size.height))
                        x += 9
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        p.addRect(CGRect(x: 0, y: y, width: size.width, height: 3))
                        y += 9
                    }
                    ctx.fill(p, with: .color(ink.opacity(0.6)))
                case "dot":
                    var p = Path()
                    var y: CGFloat = 7
                    var row = 0
                    while y < size.height {
                        var x: CGFloat = row % 2 == 0 ? 7 : 13
                        while x < size.width {
                            p.addEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
                            x += 12
                        }
                        y += 11; row += 1
                    }
                    ctx.fill(p, with: .color(ink))
                case "wave":
                    var p = Path()
                    let mid = size.height / 2
                    p.move(to: CGPoint(x: 0, y: mid))
                    var x: CGFloat = 0
                    var up = true
                    while x < size.width {
                        p.addQuadCurve(to: CGPoint(x: x + 10, y: mid),
                                       control: CGPoint(x: x + 5,
                                                        y: up ? mid - 7 : mid + 7))
                        x += 10; up.toggle()
                    }
                    ctx.stroke(p, with: .color(ink), lineWidth: 2)
                case "dash":
                    var p = Path()
                    let mid = size.height / 2
                    p.move(to: CGPoint(x: 0, y: mid))
                    p.addLine(to: CGPoint(x: size.width, y: mid))
                    ctx.stroke(p, with: .color(ink),
                               style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                default:
                    break
                }
            }
            .mask(TornTape())
        }
        .frame(width: width, height: height)
    }
}

/// 撕开的那条边。两头是锯齿，中间是直的——真胶带就是这么撕的。
struct TornTape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let teeth: CGFloat = 4
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: 0))
        // 右边那道撕口
        var y: CGFloat = 0
        var inward = true
        while y < rect.maxY {
            let next = min(y + teeth, rect.maxY)
            p.addLine(to: CGPoint(x: rect.maxX - (inward ? 3 : 0), y: next))
            y = next; inward.toggle()
        }
        p.addLine(to: CGPoint(x: 0, y: rect.maxY))
        // 左边那道
        y = rect.maxY
        inward = true
        while y > 0 {
            let next = max(y - teeth, 0)
            p.addLine(to: CGPoint(x: inward ? 3 : 0, y: next))
            y = next; inward.toggle()
        }
        p.closeSubpath()
        return p
    }
}

// MARK: 贴纸

/// 画出来的贴纸。**外面那圈白边是关键**——
/// 真贴纸是模切出来的，边上留一圈白纸；没有那圈白边，
/// 它看着就只是一个图形，不是一张贴纸。
struct JournalStickerView: View {

    let shape: String
    let color: Color
    var side: CGFloat = 42

    var body: some View {
        let style = FillStyle(eoFill: JournalStickerShape.needsEO(shape))
        JournalStickerShape(kind: shape)
            .fill(color, style: style)
            .frame(width: side, height: side)
            .padding(4)
            .background {
                JournalStickerShape(kind: shape)
                    .fill(Color.white, style: style)
                    .padding(-1)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            }
    }
}

/// 那几个形状。全是手算的路径——没有一张图。
struct JournalStickerShape: Shape {

    let kind: String

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        switch kind {
        case "leaf":
            p.move(to: CGPoint(x: w * 0.5, y: 0))
            p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h),
                           control: CGPoint(x: w * 1.05, y: h * 0.35))
            p.addQuadCurve(to: CGPoint(x: w * 0.5, y: 0),
                           control: CGPoint(x: -w * 0.05, y: h * 0.35))

        case "flower":
            let c = CGPoint(x: w / 2, y: h / 2)
            let petal = min(w, h) * 0.27
            for i in 0..<5 {
                let a = Double(i) / 5 * 2 * .pi - .pi / 2
                let px = c.x + cos(a) * petal * 1.3
                let py = c.y + sin(a) * petal * 1.3
                p.addEllipse(in: CGRect(x: px - petal, y: py - petal,
                                        width: petal * 2, height: petal * 2))
            }

        case "star":
            let c = CGPoint(x: w / 2, y: h / 2)
            let outer = min(w, h) / 2
            let inner = outer * 0.42
            for i in 0..<10 {
                let a = Double(i) / 10 * 2 * .pi - .pi / 2
                let rr = i % 2 == 0 ? outer : inner
                let pt = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()

        case "heart":
            p.move(to: CGPoint(x: w * 0.5, y: h * 0.95))
            p.addCurve(to: CGPoint(x: 0, y: h * 0.32),
                       control1: CGPoint(x: w * 0.18, y: h * 0.75),
                       control2: CGPoint(x: 0, y: h * 0.55))
            p.addArc(center: CGPoint(x: w * 0.25, y: h * 0.32),
                     radius: w * 0.25, startAngle: .degrees(180),
                     endAngle: .degrees(0), clockwise: false)
            p.addArc(center: CGPoint(x: w * 0.75, y: h * 0.32),
                     radius: w * 0.25, startAngle: .degrees(180),
                     endAngle: .degrees(0), clockwise: false)
            p.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.95),
                       control1: CGPoint(x: w, y: h * 0.55),
                       control2: CGPoint(x: w * 0.82, y: h * 0.75))

        case "cloud":
            p.addEllipse(in: CGRect(x: 0, y: h * 0.42, width: w * 0.5, height: h * 0.46))
            p.addEllipse(in: CGRect(x: w * 0.5, y: h * 0.42, width: w * 0.5, height: h * 0.46))
            p.addEllipse(in: CGRect(x: w * 0.22, y: h * 0.18, width: w * 0.56, height: h * 0.56))
            p.addRect(CGRect(x: w * 0.12, y: h * 0.6, width: w * 0.76, height: h * 0.22))

        case "moon":
            p.addEllipse(in: CGRect(x: 0, y: 0, width: w, height: h))
            p.addEllipse(in: CGRect(x: w * 0.28, y: -h * 0.06,
                                    width: w * 0.86, height: h * 0.94))

        case "bow":
            p.move(to: CGPoint(x: w * 0.5, y: h * 0.5))
            p.addLine(to: CGPoint(x: 0, y: h * 0.18))
            p.addLine(to: CGPoint(x: 0, y: h * 0.82))
            p.closeSubpath()
            p.move(to: CGPoint(x: w * 0.5, y: h * 0.5))
            p.addLine(to: CGPoint(x: w, y: h * 0.18))
            p.addLine(to: CGPoint(x: w, y: h * 0.82))
            p.closeSubpath()
            p.addEllipse(in: CGRect(x: w * 0.38, y: h * 0.38,
                                    width: w * 0.24, height: h * 0.24))

        case "ticket":
            let notch = h * 0.16
            p.addRoundedRect(in: CGRect(x: 0, y: h * 0.22, width: w, height: h * 0.56),
                             cornerSize: CGSize(width: 4, height: 4))
            // 两个半圆缺口
            p.addEllipse(in: CGRect(x: w * 0.32 - notch, y: h * 0.5 - notch,
                                    width: notch * 2, height: notch * 2))

        default:
            p.addEllipse(in: r)
        }
        return p
    }

    /// 月亮那个是「大圆挖掉小圆」，得用奇偶填充；票根那个缺口同理。
    /// 别的正常填——正常填的话月亮会是一个整圆，缺口那一半填不掉。
    static func needsEO(_ kind: String) -> Bool {
        kind == "moon" || kind == "ticket"
    }
}

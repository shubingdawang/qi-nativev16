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
    /// 纸的织纹文件名。空 = 不铺。见 Resources/Weave/来历.txt
    var weave: String = ""

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
                case "diag":   diag(&ctx, size, step: 20)
                case "cross":  cross(&ctx, size, step: 24)
                case "manuscript": manuscript(&ctx, size)
                default:       break
                }
            }
            .allowsHitTesting(false)
        }
        .overlay {
            // 真的织纹。**铺在格线之上、颗粒之下**：
            // 格线是印在纸上的，织纹是纸本身的质地。
            if !weave.isEmpty, let img = JournalPaperView.weaveImage(weave) {
                Image(uiImage: img)
                    .resizable(resizingMode: .tile)
                    // ⚠️ 叠加混合，不是直接盖。
                    // 图存的是中性灰（平均明度正好 128），叠加以 128 为界——
                    // 亮的地方提一点、暗的地方压一点，**纸的颜色照样透过来**。
                    // 换成 normal 就是拿一张灰布把她选的纸色盖掉了。
                    .blendMode(.overlay)
                    .opacity(0.55)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            // 纸的颗粒。很淡，凑近才看得见——
            // 没有它那就是一块塑料色板，不像纸。
            GrainOverlay(opacity: 0.05)
        }
    }

    /// 织纹图。**读过的记着**——这一张会铺满整页，
    /// 每次重绘都重解一遍 jpg 的话，拖一下贴纸就卡。
    ///
    /// ⚠️ 走 `NSCache`：一共就六张、每张几十 KB，
    /// 但内存紧张的时候该让系统能收走（塔罗那处就是栽在字典上）。
    nonisolated(unsafe) private static let weaveCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 8
        return c
    }()

    static func weaveImage(_ name: String) -> UIImage? {
        let key = name as NSString
        if let hit = weaveCache.object(forKey: key) { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        weaveCache.setObject(img, forKey: key)
        return img
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

    /// 斜纹。跟 `stripes` 的区别只在方向，但方向就是全部——
    /// 竖条是本子，斜条是包装纸。
    private func diag(_ ctx: inout GraphicsContext, _ size: CGSize, step: CGFloat) {
        var p = Path()
        var x: CGFloat = -size.height
        while x <= size.width {
            p.move(to: CGPoint(x: x, y: size.height))
            p.addLine(to: CGPoint(x: x + size.height, y: 0))
            x += step
        }
        ctx.stroke(p, with: .color(lineColor), lineWidth: 0.7)
    }

    /// 十字。方格纸的交点画个小十字，不画整条线——
    /// 比满格的线轻，写字的时候不抢。
    private func cross(_ ctx: inout GraphicsContext, _ size: CGSize, step: CGFloat) {
        var p = Path()
        let arm: CGFloat = 2.5
        var y: CGFloat = step / 2
        while y <= size.height {
            var x: CGFloat = step / 2
            while x <= size.width {
                p.move(to: CGPoint(x: x - arm, y: y)); p.addLine(to: CGPoint(x: x + arm, y: y))
                p.move(to: CGPoint(x: x, y: y - arm)); p.addLine(to: CGPoint(x: x, y: y + arm))
                x += step
            }
            y += step
        }
        ctx.stroke(p, with: .color(lineColor), lineWidth: 0.7)
    }

    /// 稿纸。一格一格的方框，中间留一道缝——就是那种作文本。
    private func manuscript(_ ctx: inout GraphicsContext, _ size: CGSize) {
        var p = Path()
        let cell: CGFloat = 22, gap: CGFloat = 3
        var y: CGFloat = 8
        while y + cell <= size.height {
            var x: CGFloat = 8
            while x + cell <= size.width {
                p.addRect(CGRect(x: x, y: y, width: cell, height: cell))
                x += cell + gap
            }
            y += cell + gap * 2
        }
        ctx.stroke(p, with: .color(lineColor), lineWidth: 0.6)
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
    /// 花纹自己的颜色。不给就还是半透明的白（老页面全是这一种）。
    ///
    /// 她定的：「一个素底点点图案的胶带，我想做红白配色，
    /// 我就可以把底色选红色、圆点点选白色。」
    ///
    /// ⚠️ **摆在 `width` 前面**。Swift 的逐成员构造器要求实参顺序
    /// 跟属性声明顺序一致——摆在后面的话，
    /// `JournalTapeView(color:pattern:ink:width:height:)` 编译不过
    /// （「argument 'width' must precede argument 'ink'」）。
    var ink: Color? = nil
    var width: CGFloat = 110
    var height: CGFloat = 26

    var body: some View {
        ZStack {
            TornTape()
                .fill(color.opacity(0.62))
            Canvas { ctx, size in
                // ⚠️ 自己选了花纹色就**用实的**，不再压半透。
                // 压了的话红底上的白点会透出红来变成粉的，
                // 她要的「红底白点」就不成立了。
                let ink = self.ink ?? Color.white.opacity(0.5)
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

                // ── 后加的八种。**每一种配上两层色就是几十卷**，
                // 所以这儿加一个花纹，比去扒十张胶带图划算得多。
                case "hline":
                    var p = Path()
                    var y: CGFloat = size.height / 6
                    while y < size.height {
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        y += size.height / 3
                    }
                    ctx.stroke(p, with: .color(ink), lineWidth: 2)
                case "vline":
                    var p = Path()
                    var x: CGFloat = 4
                    while x < size.width {
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        x += 8
                    }
                    ctx.stroke(p, with: .color(ink), lineWidth: 1.6)
                case "graph":
                    var p = Path()
                    var x: CGFloat = 0
                    while x < size.width { p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height)); x += 7 }
                    var y: CGFloat = 0
                    while y < size.height { p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y)); y += 7 }
                    ctx.stroke(p, with: .color(ink), lineWidth: 0.9)
                case "hound":
                    // 千鸟格：一排小方块，隔一行错开半格
                    var p = Path()
                    var y: CGFloat = 0
                    var row = 0
                    while y < size.height {
                        var x: CGFloat = row % 2 == 0 ? 0 : 5
                        while x < size.width {
                            p.addRect(CGRect(x: x, y: y, width: 5, height: 5))
                            x += 10
                        }
                        y += 5; row += 1
                    }
                    ctx.fill(p, with: .color(ink))
                case "tri":
                    var p = Path()
                    var x: CGFloat = 0
                    while x < size.width {
                        p.move(to: CGPoint(x: x, y: size.height - 3))
                        p.addLine(to: CGPoint(x: x + 5, y: 4))
                        p.addLine(to: CGPoint(x: x + 10, y: size.height - 3))
                        p.closeSubpath()
                        x += 13
                    }
                    ctx.fill(p, with: .color(ink))
                case "rhomb":
                    var p = Path()
                    let mid = size.height / 2
                    var x: CGFloat = 0
                    while x < size.width {
                        p.move(to: CGPoint(x: x, y: mid))
                        p.addLine(to: CGPoint(x: x + 5, y: mid - 5))
                        p.addLine(to: CGPoint(x: x + 10, y: mid))
                        p.addLine(to: CGPoint(x: x + 5, y: mid + 5))
                        p.closeSubpath()
                        x += 13
                    }
                    ctx.fill(p, with: .color(ink))
                case "plus":
                    var p = Path()
                    let arm: CGFloat = 3
                    var y: CGFloat = size.height / 4
                    while y < size.height {
                        var x: CGFloat = 6
                        while x < size.width {
                            p.move(to: CGPoint(x: x - arm, y: y))
                            p.addLine(to: CGPoint(x: x + arm, y: y))
                            p.move(to: CGPoint(x: x, y: y - arm))
                            p.addLine(to: CGPoint(x: x, y: y + arm))
                            x += 12
                        }
                        y += size.height / 2
                    }
                    ctx.stroke(p, with: .color(ink), lineWidth: 1.6)
                case "spark":
                    var p = Path()
                    var y: CGFloat = 5
                    var row = 0
                    while y < size.height {
                        var x: CGFloat = row % 2 == 0 ? 6 : 12
                        while x < size.width {
                            p.addEllipse(in: CGRect(x: x - 1.6, y: y - 1.6,
                                                    width: 3.2, height: 3.2))
                            x += 12
                        }
                        y += 9; row += 1
                    }
                    ctx.fill(p, with: .color(ink))

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
    /// 底下那圈模切白边的颜色。不给就还是白的（老页面全是这一种）。
    ///
    /// 贴纸的「两层色」是这么分的：`color` 是图案本身，这个是衬在底下那一层。
    /// 跟胶带那边的 `ink` 是同一个字段（`inkHex`），
    /// 只是在这两种东西上指的位置不一样——胶带的第二层在上面（花纹），
    /// 贴纸的第二层在下面（白边）。合成一个字段是因为它俩不会同时出现。
    var backing: Color? = nil

    var body: some View {
        let style = FillStyle(eoFill: JournalStickerShape.needsEO(shape))
        JournalStickerShape(kind: shape)
            .fill(color, style: style)
            .frame(width: side, height: side)
            .padding(4)
            .background {
                JournalStickerShape(kind: shape)
                    .fill(backing ?? Color.white, style: style)
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

        // ── 后加的十二个。都跟着颜色走，一个形状就是一整套配色。
        case "fly":
            // 蝴蝶：四片翅膀 + 中间一条身子
            p.addEllipse(in: CGRect(x: 0, y: h * 0.08, width: w * 0.46, height: h * 0.46))
            p.addEllipse(in: CGRect(x: w * 0.54, y: h * 0.08, width: w * 0.46, height: h * 0.46))
            p.addEllipse(in: CGRect(x: w * 0.06, y: h * 0.48, width: w * 0.40, height: h * 0.42))
            p.addEllipse(in: CGRect(x: w * 0.54, y: h * 0.48, width: w * 0.40, height: h * 0.42))
            p.addRoundedRect(in: CGRect(x: w * 0.45, y: h * 0.14, width: w * 0.10, height: h * 0.74),
                             cornerSize: CGSize(width: w * 0.05, height: w * 0.05))
        case "bird":
            p.move(to: CGPoint(x: w * 0.10, y: h * 0.62))
            p.addQuadCurve(to: CGPoint(x: w * 0.62, y: h * 0.30),
                           control: CGPoint(x: w * 0.28, y: h * 0.22))
            p.addQuadCurve(to: CGPoint(x: w * 0.92, y: h * 0.52),
                           control: CGPoint(x: w * 0.90, y: h * 0.26))
            p.addQuadCurve(to: CGPoint(x: w * 0.46, y: h * 0.86),
                           control: CGPoint(x: w * 0.74, y: h * 0.88))
            p.closeSubpath()
        case "sakura":
            // 五片花瓣绕一圈
            let cx = w / 2, cy = h / 2, pr = w * 0.22
            for i in 0..<5 {
                let a = Double(i) / 5 * .pi * 2 - .pi / 2
                p.addEllipse(in: CGRect(x: cx + cos(a) * w * 0.24 - pr,
                                        y: cy + sin(a) * h * 0.24 - pr,
                                        width: pr * 2, height: pr * 2))
            }
        case "grass":
            for (i, lean) in [(0, -0.12), (1, 0.0), (2, 0.14)] {
                let x0 = w * (0.28 + Double(i) * 0.22)
                p.move(to: CGPoint(x: x0, y: h * 0.92))
                p.addQuadCurve(to: CGPoint(x: x0 + w * lean, y: h * 0.14),
                               control: CGPoint(x: x0 + w * lean * 2, y: h * 0.5))
                p.addQuadCurve(to: CGPoint(x: x0 + w * 0.07, y: h * 0.92),
                               control: CGPoint(x: x0 + w * 0.06, y: h * 0.5))
                p.closeSubpath()
            }
        case "stamp":
            // 邮戳：一个圆环，中间一道横杠
            p.addEllipse(in: CGRect(x: w * 0.06, y: h * 0.06, width: w * 0.88, height: h * 0.88))
            p.addEllipse(in: CGRect(x: w * 0.20, y: h * 0.20, width: w * 0.60, height: h * 0.60))
            p.addRect(CGRect(x: w * 0.14, y: h * 0.44, width: w * 0.72, height: h * 0.12))
        case "mail":
            p.addRoundedRect(in: CGRect(x: 0, y: h * 0.20, width: w, height: h * 0.60),
                             cornerSize: CGSize(width: 3, height: 3))
            p.move(to: CGPoint(x: w * 0.04, y: h * 0.24))
            p.addLine(to: CGPoint(x: w / 2, y: h * 0.56))
            p.addLine(to: CGPoint(x: w * 0.96, y: h * 0.24))
            p.addLine(to: CGPoint(x: w * 0.96, y: h * 0.32))
            p.addLine(to: CGPoint(x: w / 2, y: h * 0.64))
            p.addLine(to: CGPoint(x: w * 0.04, y: h * 0.32))
            p.closeSubpath()
        case "tag":
            p.move(to: CGPoint(x: w * 0.30, y: h * 0.08))
            p.addLine(to: CGPoint(x: w * 0.94, y: h * 0.08))
            p.addLine(to: CGPoint(x: w * 0.94, y: h * 0.92))
            p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.92))
            p.addLine(to: CGPoint(x: w * 0.06, y: h * 0.50))
            p.closeSubpath()
            p.addEllipse(in: CGRect(x: w * 0.26, y: h * 0.42, width: w * 0.14, height: h * 0.14))
        case "flag":
            p.addRect(CGRect(x: w * 0.10, y: h * 0.06, width: w * 0.09, height: h * 0.88))
            p.move(to: CGPoint(x: w * 0.19, y: h * 0.10))
            p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.10))
            p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.32))
            p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.54))
            p.addLine(to: CGPoint(x: w * 0.19, y: h * 0.54))
            p.closeSubpath()
        case "drop":
            p.move(to: CGPoint(x: w / 2, y: h * 0.06))
            p.addQuadCurve(to: CGPoint(x: w * 0.88, y: h * 0.62),
                           control: CGPoint(x: w * 0.86, y: h * 0.32))
            p.addQuadCurve(to: CGPoint(x: w / 2, y: h * 0.94),
                           control: CGPoint(x: w * 0.88, y: h * 0.94))
            p.addQuadCurve(to: CGPoint(x: w * 0.12, y: h * 0.62),
                           control: CGPoint(x: w * 0.12, y: h * 0.94))
            p.addQuadCurve(to: CGPoint(x: w / 2, y: h * 0.06),
                           control: CGPoint(x: w * 0.14, y: h * 0.32))
        case "snow":
            let cx2 = w / 2, cy2 = h / 2
            for i in 0..<6 {
                let a = Double(i) / 6 * .pi * 2
                let dx = cos(a) * w * 0.44
                let dy = sin(a) * h * 0.44
                p.move(to: CGPoint(x: cx2 - dx * 0.12, y: cy2 - dy * 0.12))
                p.addLine(to: CGPoint(x: cx2 + dx, y: cy2 + dy))
                p.addLine(to: CGPoint(x: cx2 + dx * 0.94 - dy * 0.10,
                                      y: cy2 + dy * 0.94 + dx * 0.10))
                p.closeSubpath()
            }
            p.addEllipse(in: CGRect(x: cx2 - w * 0.10, y: cy2 - h * 0.10,
                                    width: w * 0.20, height: h * 0.20))
        case "sun":
            p.addEllipse(in: CGRect(x: w * 0.26, y: h * 0.26, width: w * 0.48, height: h * 0.48))
            let cx3 = w / 2, cy3 = h / 2
            for i in 0..<8 {
                let a = Double(i) / 8 * .pi * 2
                let x1 = cx3 + cos(a) * w * 0.34
                let y1 = cy3 + sin(a) * h * 0.34
                let x2 = cx3 + cos(a) * w * 0.48
                let y2 = cy3 + sin(a) * h * 0.48
                p.addRoundedRect(in: CGRect(x: min(x1, x2) - 1.4, y: min(y1, y2) - 1.4,
                                            width: abs(x2 - x1) + 2.8,
                                            height: abs(y2 - y1) + 2.8),
                                 cornerSize: CGSize(width: 1.4, height: 1.4))
            }
        case "shell":
            p.move(to: CGPoint(x: w / 2, y: h * 0.92))
            p.addQuadCurve(to: CGPoint(x: w * 0.06, y: h * 0.30),
                           control: CGPoint(x: w * 0.02, y: h * 0.74))
            p.addQuadCurve(to: CGPoint(x: w * 0.94, y: h * 0.30),
                           control: CGPoint(x: w / 2, y: h * -0.14))
            p.addQuadCurve(to: CGPoint(x: w / 2, y: h * 0.92),
                           control: CGPoint(x: w * 0.98, y: h * 0.74))
            p.closeSubpath()

        default:
            p.addEllipse(in: r)
        }
        return p
    }

    /// 月亮那个是「大圆挖掉小圆」，得用奇偶填充；票根那个缺口同理。
    /// 别的正常填——正常填的话月亮会是一个整圆，缺口那一半填不掉。
    static func needsEO(_ kind: String) -> Bool {
        // ⚠️ 这几个都是「一个形状里挖掉另一个」，得用奇偶填充。
        // 不用的话邮戳会是一个实心圆、信封那道折线看不见。
        ["moon", "ticket", "stamp", "mail"].contains(kind)
    }
}

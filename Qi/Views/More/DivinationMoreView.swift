import SwiftUI

/// 占卜页那层花纹。
///
/// 她说「占卜页我觉得太朴素了……可以适当增加点花纹或者玄学的装饰之类的」，
/// 后来又说「这个背景花纹太简单了，画复杂点」。
///
/// 上一版是两圈圆、一圈刻度、四颗星、一弯月——摊在整块屏幕上确实太空。
/// 这一版按**层**来画，从外往内七层，每一层都比上一层暗一点：
///
///     ① 最外一圈点阵（72 颗）          ⑤ 八角星（两个方叠 45°）
///     ② 刻度环：12 长 + 36 短          ⑥ 六芒星（两个三角对扣）
///     ③ 十二宫符号（画的，不是字）      ⑦ 正中日月
///     ④ 从内圈发散的光芒（24 道）      ＋ 四角卷草、满天星
///
/// 全是 Shape 画的——不占空间，放多大都不糊，深浅色各调各的。
///
/// ⚠️ **不能抢戏。** 这一页真正的主角是那把牌和那段话。
/// 所以层数加了，**每一层的墨反而更淡**：最重的一层也只有 0.16。
/// 复杂靠的是层数和疏密，不是靠加深。
///
/// ⚠️ 十二宫那一圈是**画出来的短笔画**，不是 Unicode 符号。
/// 用字符的话得挑字体，缺字就变成豆腐块——而且那些字符在小字号下
/// 挤成一团，看不出是什么。
struct OracleOrnament: View {

    var tint: Color
    var scheme: ColorScheme

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height * 0.42)
            let r = min(size.width, size.height) * 0.36
            let dark = scheme == .dark
            // 一层一层往里走，墨一层比一层深，但最深也只有 0.16
            func ink(_ k: Double) -> GraphicsContext.Shading {
                .color(tint.opacity((dark ? 0.16 : 0.13) * k))
            }
            func at(_ a: Double, _ k: Double) -> CGPoint {
                CGPoint(x: c.x + cos(a) * r * k, y: c.y + sin(a) * r * k)
            }
            // 正上方是 0，顺时针
            func ang(_ i: Int, _ n: Int) -> Double {
                Double(i) / Double(n) * 2 * .pi - .pi / 2
            }

            // ① 最外一圈点阵。72 颗，疏密均匀——单看是点，整体是一道虚线的环。
            for i in 0..<72 {
                let p = at(ang(i, 72), 1.18)
                let d = i % 6 == 0 ? 1.6 : 0.9
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2,
                                                width: d, height: d)),
                         with: ink(i % 6 == 0 ? 1.0 : 0.6))
            }

            // ② 三圈同心圆
            for k in [1.08, 1.0, 0.72] {
                let rect = CGRect(x: c.x - r * k, y: c.y - r * k,
                                  width: r * k * 2, height: r * k * 2)
                ctx.stroke(Path(ellipseIn: rect), with: ink(k == 1.0 ? 1.0 : 0.7),
                           lineWidth: k == 1.0 ? 0.9 : 0.6)
            }

            // ③ 刻度环：十二根长的（对十二宫、十二地支），三十六根短的
            for i in 0..<36 {
                let a = ang(i, 36)
                var p = Path()
                let long = i % 3 == 0
                p.move(to: at(a, 1.0))
                p.addLine(to: at(a, long ? 0.88 : 0.95))
                ctx.stroke(p, with: ink(long ? 1.0 : 0.55),
                           lineWidth: long ? 1.3 : 0.6)
            }

            // ④ 十二宫符号。每一格中间放一个短笔画，画的不是字——
            //    用字符要挑字体，缺字就是豆腐块。
            //
            //    每个符号是一串「相对坐标的折线」，在 12 个格位上各画一份。
            //    形不求准，求的是**一眼看过去是十二个不一样的记号**。
            let glyphs: [[(Double, Double)]] = [
                [(-1, 1), (-0.4, -1), (0, 0.2), (0.4, -1), (1, 1)],       // 白羊
                [(-1, 0.6), (0, -0.2), (1, 0.6), (0, 1), (-1, 0.6)],      // 金牛
                [(-0.7, -1), (-0.7, 1), (0.7, 1), (0.7, -1)],             // 双子
                [(-1, 0), (0, -0.8), (1, 0), (0, 0.9), (-1, 0)],          // 巨蟹
                [(-1, 1), (-0.3, -1), (0.4, 0.6), (1, -0.6)],             // 狮子
                [(-1, -1), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0.4)],  // 处女
                [(-1, -0.4), (1, -0.4), (1, 0.6), (-1, 0.6)],             // 天秤
                [(-1, -1), (-1, 0.6), (0, 0.6), (0, -1), (1, -1), (1, 1)],// 天蝎
                [(-1, 1), (1, -1), (0.2, -1), (1, -1), (1, -0.2)],        // 射手
                [(-1, -0.6), (-0.2, 0.8), (0.5, -0.4), (1, 0.8)],         // 摩羯
                [(-1, 0.2), (-0.3, -0.4), (0.3, 0.2), (1, -0.4)],         // 水瓶
                [(-0.8, -1), (-0.8, 1), (0.8, -1), (0.8, 1)],             // 双鱼
            ]
            let gs = r * 0.055
            for i in 0..<12 {
                // 格位取两根长刻度的正中间
                let a = ang(i, 12) + .pi / 12
                let o = at(a, 1.04)
                var p = Path()
                for (j, v) in glyphs[i].enumerated() {
                    let q = CGPoint(x: o.x + v.0 * gs, y: o.y + v.1 * gs)
                    if j == 0 { p.move(to: q) } else { p.addLine(to: q) }
                }
                ctx.stroke(p, with: ink(0.9), lineWidth: 0.9)
            }

            // ⑤ 从内圈发散的光芒，二十四道，长短交替
            for i in 0..<24 {
                let a = ang(i, 24)
                var p = Path()
                p.move(to: at(a, 0.72))
                p.addLine(to: at(a, i % 2 == 0 ? 0.86 : 0.79))
                ctx.stroke(p, with: ink(0.45), lineWidth: 0.6)
            }

            // ⑥ 八角星：两个正方叠 45°
            for turn in [0.0, Double.pi / 4] {
                var sq = Path()
                for i in 0..<4 {
                    let p = at(ang(i, 4) + turn + .pi / 4, 0.52)
                    if i == 0 { sq.move(to: p) } else { sq.addLine(to: p) }
                }
                sq.closeSubpath()
                ctx.stroke(sq, with: ink(0.8), lineWidth: 0.7)
            }

            // ⑦ 六芒星：两个三角对扣。最里面这层最淡，免得压住正中的日月。
            for turn in [0.0, Double.pi] {
                var tri = Path()
                for i in 0..<3 {
                    let p = at(ang(i, 3) + turn, 0.40)
                    if i == 0 { tri.move(to: p) } else { tri.addLine(to: p) }
                }
                tri.closeSubpath()
                ctx.stroke(tri, with: ink(0.55), lineWidth: 0.7)
            }

            // 正中：一弯月（缺口朝右）和一轮带芒的日，一左一右
            var moon = Path()
            moon.addArc(center: CGPoint(x: c.x - r * 0.13, y: c.y), radius: r * 0.15,
                        startAngle: .degrees(55), endAngle: .degrees(305),
                        clockwise: false)
            ctx.stroke(moon, with: ink(1.0), lineWidth: 1.2)

            let sun = CGPoint(x: c.x + r * 0.15, y: c.y)
            ctx.stroke(Path(ellipseIn: CGRect(x: sun.x - r * 0.07, y: sun.y - r * 0.07,
                                              width: r * 0.14, height: r * 0.14)),
                       with: ink(1.0), lineWidth: 1.0)
            for i in 0..<8 {
                let a = ang(i, 8)
                var p = Path()
                p.move(to: CGPoint(x: sun.x + cos(a) * r * 0.10,
                                   y: sun.y + sin(a) * r * 0.10))
                p.addLine(to: CGPoint(x: sun.x + cos(a) * r * 0.15,
                                      y: sun.y + sin(a) * r * 0.15))
                ctx.stroke(p, with: ink(0.7), lineWidth: 0.8)
            }

            // 满天星。位置是写死的，不是随机的——
            // ⚠️ 随机的话每次重画都跳一下，滚动时整页在闪。
            let stars: [(Double, Double, Double)] = [
                (-1.35, -0.95, 5.0), (1.28, -0.72, 4.0), (0.92, 1.05, 3.0),
                (-1.05, 0.98, 3.5), (-0.35, -1.42, 2.5), (0.48, -1.30, 3.2),
                (1.45, 0.35, 2.6), (-1.48, 0.18, 3.0), (0.15, 1.38, 2.4),
                (-0.72, 1.30, 2.0), (1.12, -1.22, 2.2), (-1.22, -1.35, 2.0),
            ]
            for (dx, dy, s) in stars {
                let p = CGPoint(x: c.x + r * dx, y: c.y + r * dy)
                var star = Path()
                star.move(to: CGPoint(x: p.x, y: p.y - s))
                star.addLine(to: CGPoint(x: p.x, y: p.y + s))
                star.move(to: CGPoint(x: p.x - s, y: p.y))
                star.addLine(to: CGPoint(x: p.x + s, y: p.y))
                // 大的那几颗再加一对斜芒
                if s > 3 {
                    let d = s * 0.42
                    star.move(to: CGPoint(x: p.x - d, y: p.y - d))
                    star.addLine(to: CGPoint(x: p.x + d, y: p.y + d))
                    star.move(to: CGPoint(x: p.x + d, y: p.y - d))
                    star.addLine(to: CGPoint(x: p.x - d, y: p.y + d))
                }
                ctx.stroke(star, with: .color(tint.opacity(dark ? 0.2 : 0.17)),
                           lineWidth: 0.9)
            }

            // 四角卷草：每个角一段圆弧配一颗小点，把整块画面收住
            let corners: [(CGPoint, Double)] = [
                (CGPoint(x: 18, y: 18), 0),
                (CGPoint(x: size.width - 18, y: 18), .pi / 2),
                (CGPoint(x: size.width - 18, y: size.height - 18), .pi),
                (CGPoint(x: 18, y: size.height - 18), .pi * 1.5),
            ]
            for (o, turn) in corners {
                var p = Path()
                p.addArc(center: o, radius: 26,
                         startAngle: .radians(turn), endAngle: .radians(turn + .pi / 2),
                         clockwise: false)
                ctx.stroke(p, with: ink(0.6), lineWidth: 0.8)
                var q = Path()
                q.addArc(center: o, radius: 34,
                         startAngle: .radians(turn + 0.25),
                         endAngle: .radians(turn + .pi / 2 - 0.25),
                         clockwise: false)
                ctx.stroke(q, with: ink(0.4), lineWidth: 0.6)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 骰子

struct DicePane: View {

    @Binding var question: String
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = DivinationStore.shared

    @State private var dice: [Int] = []
    @State private var record: DivinationRecord?
    @State private var rolling = false
    @State private var reading = ""
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            QuestionBox(question: $question,
                        hint: "适用于具体问题，结果直接给出结论。")

            HStack(spacing: 12) {
                ForEach(Array(dice.enumerated()), id: \.offset) { _, d in
                    DieFace(value: d, tint: app.settings.accentColor)
                        .frame(width: 52, height: 52)
                }
                if dice.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Theme.textMuted(scheme).opacity(0.3),
                                          style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .frame(width: 52, height: 52)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .rotationEffect(.degrees(rolling ? 8 : 0))
            .animation(.easeInOut(duration: 0.12).repeatCount(6, autoreverses: true),
                       value: rolling)

            Button {
                roll()
            } label: {
                Text(dice.isEmpty ? "摇" : "再摇一次")
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14)
                        .fill(app.settings.accentColor.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)

            if let record {
                ReadingBox(record: record, reading: $reading, asking: $asking)
            }
        }
        .glassCard()
    }

    private func roll() {
        rolling = true
        Task { @MainActor in
            // 摇的那一下让点数跳几下，不然「摇」这个动作就没了
            for _ in 0..<6 {
                dice = (0..<3).map { _ in Int.random(in: 1...6) }
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
            let r = DiviceMore.rollDice()
            dice = r.dice
            rolling = false
            var rec = DivinationRecord(kind: "dice", question: question, layout: r.layout)
            rec.tosses = r.dice
            record = rec
            reading = ""
            store.add(rec)
            if app.settings.haptics {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

/// 一颗骰子。点是画的，不是字——字体里那几个骰子符号大小不一。
struct DieFace: View {
    let value: Int
    let tint: Color

    private var dots: [(Double, Double)] {
        switch value {
        case 1: return [(0.5, 0.5)]
        case 2: return [(0.28, 0.28), (0.72, 0.72)]
        case 3: return [(0.26, 0.26), (0.5, 0.5), (0.74, 0.74)]
        case 4: return [(0.3, 0.3), (0.7, 0.3), (0.3, 0.7), (0.7, 0.7)]
        case 5: return [(0.28, 0.28), (0.72, 0.28), (0.5, 0.5), (0.28, 0.72), (0.72, 0.72)]
        default: return [(0.3, 0.25), (0.7, 0.25), (0.3, 0.5),
                         (0.7, 0.5), (0.3, 0.75), (0.7, 0.75)]
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: geo.size.width * 0.22, style: .continuous)
                    .fill(tint.opacity(0.18))
                RoundedRectangle(cornerRadius: geo.size.width * 0.22, style: .continuous)
                    .strokeBorder(tint.opacity(0.5), lineWidth: 1)
                ForEach(Array(dots.enumerated()), id: \.offset) { _, d in
                    Circle()
                        .fill(tint)
                        .frame(width: geo.size.width * 0.15,
                               height: geo.size.width * 0.15)
                        .position(x: geo.size.width * d.0, y: geo.size.height * d.1)
                }
            }
        }
    }
}

// MARK: - 八字

struct BaziPane: View {

    @Binding var question: String
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = DivinationStore.shared

    @AppStorage("baziBirth") private var birthStamp: Double = 0
    @State private var birth = Date()
    @State private var record: DivinationRecord?
    @State private var reading = ""
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("生辰")
                .font(.app(14, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))
            DatePicker("出生那一刻", selection: $birth,
                       displayedComponents: [.date, .hourAndMinute])
                .font(.app(13))
                .datePickerStyle(.compact)

            QuestionBox(question: $question,
                        hint: "可选取事业、感情或近年走势等方向。")

            Button {
                排盘()
            } label: {
                Text("排盘")
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14)
                        .fill(app.settings.accentColor.opacity(0.3)))
            }
            .buttonStyle(.plain)

            if let record {
                Text(.init(record.layout))
                    .font(.app(13, design: .monospaced))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.softFillDeep))
                ReadingBox(record: record, reading: $reading, asking: $asking)
            }
        }
        .glassCard()
        .onAppear {
            if birthStamp > 0 { birth = Date(timeIntervalSince1970: birthStamp) }
        }
    }

    private func 排盘() {
        birthStamp = birth.timeIntervalSince1970
        let layout = DiviceMore.bazi(for: birth)
        let r = DivinationRecord(kind: "bazi", question: question, layout: layout)
        record = r
        reading = ""
        store.add(r)
    }
}

// MARK: - 解梦

struct DreamPane: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = DivinationStore.shared

    @State private var dream = ""
    @State private var record: DivinationRecord?
    @State private var reading = ""
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("梦见了什么")
                .font(.app(14, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))
            Text(MD.inline("按回忆顺序记录即可，无需整理。不合逻辑的细节同样具有解读价值。"))
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))

            TextEditor(text: $dream)
                .font(.app(14))
                .scrollContentBackground(.hidden)
                .frame(height: 140)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))

            Button {
                let r = DivinationRecord(kind: "dream", question: "解这个梦",
                                         layout: "她讲的梦：\n\(dream)")
                record = r
                reading = ""
                store.add(r)
            } label: {
                Text("讲给他听")
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14)
                        .fill(app.settings.accentColor.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .disabled(dream.trimmingCharacters(in: .whitespaces).count < 4)

            if let record {
                ReadingBox(record: record, reading: $reading, asking: $asking)
            }
        }
        .glassCard()
    }
}

// MARK: - 水晶球

struct CrystalPane: View {

    @Binding var question: String
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = DivinationStore.shared

    @State private var record: DivinationRecord?
    @State private var reading = ""
    @State private var asking = false
    @State private var swirl = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            QuestionBox(question: $question, hint: "问题可不具体，解读依据整体氛围。")

            // 球
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [app.settings.accentColor.opacity(0.42),
                                 app.settings.accentColor.opacity(0.10)],
                        center: .init(x: 0.38, y: 0.32),
                        startRadius: 4, endRadius: 90))
                Circle()
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 16, height: 16)
                    .offset(x: -22, y: -26)
                    .blur(radius: 3)
            }
            .frame(width: 132, height: 132)
            .frame(maxWidth: .infinity)
            .rotationEffect(.degrees(swirl ? 360 : 0))
            .animation(.linear(duration: 18).repeatForever(autoreverses: false), value: swirl)
            .onAppear { swirl = true }

            Button {
                let layout = DiviceMore.crystal()
                let r = DivinationRecord(kind: "ball", question: question, layout: layout)
                record = r
                reading = ""
                store.add(r)
                if app.settings.haptics {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            } label: {
                Text(record == nil ? "看进去" : "再看一次")
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14)
                        .fill(app.settings.accentColor.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)

            if let record {
                Text(.init(record.layout))
                    .font(.app(14))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                ReadingBox(record: record, reading: $reading, asking: $asking)
            }
        }
        .glassCard()
    }
}

// MARK: - 共用的两块

/// 问题输入框。四套新占法都用它，省得各写一份。
struct QuestionBox: View {
    @Binding var question: String
    var hint: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("在心里默念，或者写在这里…", text: $question, axis: .vertical)
                .font(.app(14))
                .lineLimit(1...3)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
            Text(MD.inline(hint))
                .font(.app(10.5))
                .foregroundStyle(Theme.textMuted(scheme))
        }
    }
}

/// 「让他解」那一块。四套新占法共用。
struct ReadingBox: View {
    let record: DivinationRecord
    @Binding var reading: String
    @Binding var asking: Bool

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if reading.isEmpty {
                Button {
                    Task {
                        asking = true
                        let text = await app.interpret(record)
                        reading = text
                        DivinationStore.shared.setReading(record.id, text: text)
                        asking = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if asking { ProgressView().scaleEffect(0.8) }
                        Text(asking ? "他在看…" : "让他解")
                            .font(.app(14, weight: .medium))
                    }
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 13)
                        .fill(app.settings.accentColor.opacity(0.22)))
                }
                .buttonStyle(.plain)
                .disabled(asking)
                // 这一步是**要花钱的**，所以写明白，别让她误按
                Text("本步骤调用一次模型，产生一次费用。盘面由本机推算，不产生费用。")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
            } else {
                Text(reading)
                    .font(.app(14))
                    .lineSpacing(5)
                    .foregroundStyle(Theme.textMain(scheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(app.settings.accentColor.opacity(0.10)))
            }
        }
    }
}

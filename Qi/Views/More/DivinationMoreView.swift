import SwiftUI

/// 占卜页那层花纹。
///
/// 她说「占卜页我觉得太朴素了……可以适当增加点花纹或者玄学的装饰之类的」。
/// 参考图那张是一整块留白 + 一行衬线小标题 + 底下一把扇开的牌。
///
/// 所以花纹**画在底下、很淡**：两圈同心圆、一圈刻度、几颗星、一弯月。
/// 全是 Shape 画的——不占空间，放多大都不糊，深浅色也能各调各的。
/// **不能抢戏**：这一页真正的主角是那把牌和那段话。
struct OracleOrnament: View {

    var tint: Color
    var scheme: ColorScheme

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height * 0.42)
            let r = min(size.width, size.height) * 0.36
            let ink = tint.opacity(scheme == .dark ? 0.16 : 0.13)

            // 两圈同心圆
            for k in [1.0, 0.72] {
                let rect = CGRect(x: c.x - r * k, y: c.y - r * k,
                                  width: r * k * 2, height: r * k * 2)
                ctx.stroke(Path(ellipseIn: rect), with: .color(ink), lineWidth: 0.8)
            }

            // 一圈刻度：十二等分，跟十二宫、十二地支都对得上
            for i in 0..<12 {
                let a = Double(i) / 12 * 2 * .pi - .pi / 2
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                p.addLine(to: CGPoint(x: c.x + cos(a) * r * 0.9,
                                      y: c.y + sin(a) * r * 0.9))
                ctx.stroke(p, with: .color(ink), lineWidth: i % 3 == 0 ? 1.4 : 0.7)
            }

            // 内圈里一个正方 + 一个倒三角，是最老的那种符号味道
            var square = Path()
            for i in 0..<4 {
                let a = Double(i) / 4 * 2 * .pi - .pi / 4
                let p = CGPoint(x: c.x + cos(a) * r * 0.52, y: c.y + sin(a) * r * 0.52)
                if i == 0 { square.move(to: p) } else { square.addLine(to: p) }
            }
            square.closeSubpath()
            ctx.stroke(square, with: .color(ink), lineWidth: 0.8)

            // 几颗星
            for (dx, dy, s) in [(-0.62, -0.5, 5.0), (0.58, -0.36, 4.0),
                                (0.42, 0.55, 3.0), (-0.5, 0.48, 3.5)] {
                let p = CGPoint(x: c.x + r * dx, y: c.y + r * dy)
                var star = Path()
                star.move(to: CGPoint(x: p.x, y: p.y - s))
                star.addLine(to: CGPoint(x: p.x, y: p.y + s))
                star.move(to: CGPoint(x: p.x - s, y: p.y))
                star.addLine(to: CGPoint(x: p.x + s, y: p.y))
                ctx.stroke(star, with: .color(tint.opacity(0.22)), lineWidth: 1)
            }

            // 一弯月，缺口朝右
            var moon = Path()
            moon.addArc(center: CGPoint(x: c.x, y: c.y), radius: r * 0.26,
                        startAngle: .degrees(60), endAngle: .degrees(300),
                        clockwise: false)
            ctx.stroke(moon, with: .color(ink), lineWidth: 1.2)
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
                        hint: "问一件具体的事。骰子答得直，不绕弯。")

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
                        hint: "想问哪一块？事业、感情、这几年的走势都行。")

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
            QuestionBox(question: $question, hint: "问得含糊也行。球看的是氛围，不是条款。")

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
            Text(hint)
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
                Text("这一步会调一次模型（花钱）。盘面本身是本机算的，不花钱。")
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

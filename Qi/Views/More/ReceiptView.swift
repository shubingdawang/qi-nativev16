import SwiftUI

// MARK: - 纸

/// 小票纸。上下两条锯齿边——机器撕下来的那道口子。
struct ReceiptEdgeShape: Shape {
    var tooth: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let count = max(2, Int(rect.width / tooth))
        let w = rect.width / CGFloat(count)

        p.move(to: CGPoint(x: 0, y: tooth))
        for i in 0..<count {
            let x = CGFloat(i) * w
            p.addLine(to: CGPoint(x: x + w / 2, y: 0))
            p.addLine(to: CGPoint(x: x + w, y: tooth))
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height - tooth))
        for i in 0..<count {
            let x = rect.width - CGFloat(i) * w
            p.addLine(to: CGPoint(x: x - w / 2, y: rect.height))
            p.addLine(to: CGPoint(x: x - w, y: rect.height - tooth))
        }
        p.addLine(to: CGPoint(x: 0, y: tooth))
        p.closeSubpath()
        return p
    }
}

/// 日式票券上那种手绘波浪线
struct WaveLine: Shape {
    var amplitude: CGFloat = 2.2
    var wavelength: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.height / 2
        p.move(to: CGPoint(x: 0, y: mid))
        var x: CGFloat = 0
        var up = true
        while x < rect.width {
            let next = min(x + wavelength, rect.width)
            p.addQuadCurve(
                to: CGPoint(x: next, y: mid),
                control: CGPoint(x: x + (next - x) / 2,
                                 y: up ? mid - amplitude * 2 : mid + amplitude * 2)
            )
            x = next
            up.toggle()
        }
        return p
    }
}

// MARK: - 小票配色
//
// 小票不跟深色模式走——它是一张纸，纸在夜里也是纸。
// 用的还是「家」那套的墨和纸，只是把橘留给最后那个合计。

private enum Slip {
    static let paper = HomePalette.paper
    static let paperEdge = Color(hexString: "EFEADF") ?? HomePalette.panel
    static let ink = HomePalette.ink
    static let inkSoft = HomePalette.inkSoft
    static let accent = HomePalette.orange
    static let sage = HomePalette.sage

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func title(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - 票面

/// 一整张票。故意不依赖 EnvironmentObject，
/// 这样 ImageRenderer 拿去渲染成图片时不会缺东西。
struct ReceiptSlip: View {

    let day: Date
    let usage: DayUsage
    let pricing: Pricing
    let digest: DayDigest?
    let messageCount: Int
    let aiName: String
    let userName: String
    let togetherSince: Date

    var body: some View {
        VStack(spacing: 0) {
            header
            band("本日明細")
            details
            totals
            band("今日のことば")
            keywords
            band("いっしょに")
            together
            message
            footer
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 24)
        .frame(width: 330)
        .background(
            ZStack {
                ReceiptEdgeShape()
                    .fill(
                        LinearGradient(colors: [Slip.paper, Slip.paperEdge],
                                       startPoint: .top, endPoint: .bottom)
                    )
                // 中间那道折痕
                Rectangle()
                    .fill(Slip.ink.opacity(0.05))
                    .frame(height: 1)
            }
        )
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.14), radius: 12, x: 0, y: 6)
    }

    // MARK: 票头

    private var header: some View {
        VStack(spacing: 8) {
            WaveLine()
                .stroke(Slip.ink.opacity(0.45), lineWidth: 1.1)
                .frame(height: 8)

            Text("[ QI · DAILY RECEIPT ]")
                .font(Slip.mono(9, .medium))
                .tracking(1.6)
                .foregroundStyle(Slip.inkSoft)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("栖")
                    .font(Slip.title(34, .bold))
                    .foregroundStyle(Slip.ink)
                Text("今日の小票")
                    .font(Slip.title(19, .semibold))
                    .foregroundStyle(Slip.ink.opacity(0.85))
            }

            HStack(spacing: 0) {
                stub("·NAME·", aiName.isEmpty ? "阿晏" : aiName)
                Rectangle()
                    .fill(Slip.ink.opacity(0.25))
                    .frame(width: 1, height: 22)
                stub("·DATE·", dateText)
            }
            .padding(.top, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Slip.ink.opacity(0.35), lineWidth: 1)
                    .padding(.top, 2)
            )

            WaveLine()
                .stroke(Slip.ink.opacity(0.45), lineWidth: 1.1)
                .frame(height: 8)
        }
        .padding(.bottom, 14)
    }

    private func stub(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(Slip.mono(8))
                .foregroundStyle(Slip.inkSoft)
            Text(value)
                .font(Slip.mono(13, .semibold))
                .foregroundStyle(Slip.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
    }

    /// 中间那种深色小牌，日式票券上用来分段
    private func band(_ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Slip.paper).frame(width: 3, height: 3)
            Text(text)
                .font(Slip.mono(10, .medium))
                .tracking(2)
                .foregroundStyle(Slip.paper)
            Circle().fill(Slip.paper).frame(width: 3, height: 3)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Slip.ink.opacity(0.86))
        )
        .padding(.vertical, 10)
    }

    // MARK: 明细

    private var details: some View {
        let items = usage.sorted
        return VStack(spacing: 9) {
            if items.isEmpty {
                Text("今天还没有花过钱。")
                    .font(Slip.mono(11))
                    .foregroundStyle(Slip.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(items.indices, id: \.self) { i in
                    lineItem(index: i + 1, source: items[i].source, u: items[i].usage)
                }
            }
        }
    }

    private func lineItem(index: Int, source: UsageSource, u: TokenUsage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(String(format: "#%02d", index))
                    .font(Slip.mono(10, .semibold))
                    .foregroundStyle(Slip.inkSoft)
                Text(source.label)
                    .font(Slip.title(15, .semibold))
                    .foregroundStyle(Slip.ink)
                Text(String(repeating: "·", count: 40))
                    .font(Slip.mono(10))
                    .foregroundStyle(Slip.inkSoft.opacity(0.7))
                    .lineLimit(1)
                    .layoutPriority(-1)
                Text("¥" + UsageFormat.money(pricing.cost(u, source: source)))
                    .font(Slip.mono(12, .semibold))
                    .foregroundStyle(Slip.ink)
            }
            HStack(spacing: 8) {
                if source.isTokenBased {
                    detailChip("入", UsageFormat.short(u.input))
                    detailChip("命中", UsageFormat.short(u.cacheRead))
                    if u.cacheWrite > 0 { detailChip("写入", UsageFormat.short(u.cacheWrite)) }
                    detailChip("出", UsageFormat.short(u.output))
                }
                detailChip("次", "\(u.calls)")
                Spacer(minLength: 0)
            }
            .padding(.leading, 26)
        }
    }

    private func detailChip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(Slip.mono(8))
                .foregroundStyle(Slip.inkSoft)
            Text(value)
                .font(Slip.mono(10, .medium))
                .foregroundStyle(Slip.ink.opacity(0.8))
        }
    }

    // MARK: 合计

    private var totals: some View {
        let u = usage.total
        return VStack(spacing: 7) {
            dashed
            totalRow("聊了几句", "\(messageCount)")
            totalRow("調用回数", "\(u.calls)")
            totalRow("入力 token", UsageFormat.grouped(u.inputAll))
            totalRow("出力 token", UsageFormat.grouped(u.output))
            hitRow(u)
            dashed
            HStack(alignment: .lastTextBaseline) {
                Text("合計")
                    .font(Slip.title(16, .bold))
                    .foregroundStyle(Slip.ink)
                Spacer()
                Text("¥")
                    .font(Slip.mono(11, .semibold))
                    .foregroundStyle(Slip.accent)
                Text(UsageFormat.money(usage.cost(pricing)))
                    .font(.app(30, weight: .bold, design: .rounded))
                    .foregroundStyle(Slip.accent)
            }
            Text("※ 按你自己填的单价估的，不是真实账单")
                .font(Slip.mono(8))
                .foregroundStyle(Slip.inkSoft)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.top, 12)
    }

    private var dashed: some View {
        SlipLine()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(Slip.ink.opacity(0.3))
            .frame(height: 1)
    }

    private func totalRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text("▶ " + title)
                .font(Slip.mono(11))
                .foregroundStyle(Slip.ink.opacity(0.8))
            Spacer()
            Text(value)
                .font(Slip.mono(12, .medium))
                .foregroundStyle(Slip.ink)
        }
    }

    /// 命中率给一条实体进度条，因为这条是真的能省钱的地方
    private func hitRow(_ u: TokenUsage) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("▶ キャッシュ命中")
                    .font(Slip.mono(11))
                    .foregroundStyle(Slip.ink.opacity(0.8))
                Spacer()
                Text(String(format: "%.0f%%", u.hitRate * 100))
                    .font(Slip.mono(12, .medium))
                    .foregroundStyle(Slip.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Slip.ink.opacity(0.10))
                    // 命中的部分画成实心方块，跟票面的印刷感对上
                    Rectangle()
                        .fill(Slip.sage.opacity(0.85))
                        .frame(width: max(0, geo.size.width * u.hitRate))
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: 关键词

    private var keywords: some View {
        Group {
            if let words = digest?.keywords, !words.isEmpty {
                FlowRow(spacing: 7) {
                    ForEach(words, id: \.self) { w in
                        Text(w)
                            .font(Slip.title(13, .semibold))
                            .foregroundStyle(Slip.ink)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(Slip.ink.opacity(0.4), lineWidth: 1)
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("还没让他写。小票右上角那个按钮点一下，他会读一遍今天。")
                    .font(Slip.mono(10))
                    .foregroundStyle(Slip.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 在一起

    private var together: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text("第")
                .font(Slip.mono(10))
                .foregroundStyle(Slip.inkSoft)
            Text("\(togetherDays)")
                .font(.app(26, weight: .bold, design: .rounded))
                .foregroundStyle(Slip.ink)
            Text("天")
                .font(Slip.mono(10))
                .foregroundStyle(Slip.inkSoft)
            Spacer()
            Text(sinceText + " から")
                .font(Slip.mono(9))
                .foregroundStyle(Slip.inkSoft)
        }
    }

    // MARK: 留言

    private var message: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Rectangle().fill(Slip.ink.opacity(0.6)).frame(width: 14, height: 1)
                Text("· MESSAGE ·")
                    .font(Slip.mono(9, .medium))
                    .tracking(1.5)
                    .foregroundStyle(Slip.inkSoft)
                Rectangle().fill(Slip.ink.opacity(0.6)).frame(height: 1)
            }
            Text(digest?.line.isEmpty == false ? digest!.line : "　")
                .font(Slip.title(15))
                .foregroundStyle(Slip.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Slip.ink.opacity(0.18)).frame(height: 1)
                }
            HStack {
                Spacer()
                Text("MESSAGE DATE")
                    .font(Slip.mono(8))
                    .foregroundStyle(Slip.inkSoft)
                Text(shortDate)
                    .font(Slip.mono(9, .semibold))
                    .foregroundStyle(Slip.paper)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Slip.ink.opacity(0.85))
            }
        }
        .padding(.top, 16)
    }

    // MARK: 票尾

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Text("伝票番号")
                    .font(Slip.mono(8))
                    .foregroundStyle(Slip.inkSoft)
                Spacer()
                Text(serial)
                    .font(Slip.mono(11, .semibold))
                    .foregroundStyle(Slip.ink)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Slip.ink.opacity(0.3), lineWidth: 1)
            )

            // 条形码，画的
            Barcode(seed: serial)
                .frame(height: 30)

            Text("〈 システム自動発券 · 再発行不可 〉")
                .font(Slip.mono(8))
                .foregroundStyle(Slip.inkSoft)

            WaveLine(amplitude: 1.6, wavelength: 8)
                .stroke(Slip.ink.opacity(0.35), lineWidth: 1)
                .frame(height: 6)

            Text("ご来店ありがとうございました")
                .font(Slip.mono(8))
                .foregroundStyle(Slip.inkSoft)
        }
        .padding(.top, 18)
    }

    // MARK: 文字

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: day)
    }

    private var shortDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM.dd"
        return f.string(from: day)
    }

    private var sinceText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: togetherSince)
    }

    private var serial: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f.string(from: day)
    }

    private var togetherDays: Int {
        let cal = Calendar.current
        let a = cal.startOfDay(for: togetherSince)
        let b = cal.startOfDay(for: day)
        let n = cal.dateComponents([.day], from: a, to: b).day ?? 0
        return max(1, n + 1)
    }
}

// MARK: - 零件

/// 一条直线，用来画虚线
struct SlipLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return p
    }
}

/// 假条形码。宽窄由日期算出来，同一天永远画出同一条。
struct Barcode: View {
    let seed: String

    var body: some View {
        let widths = bars
        return HStack(alignment: .center, spacing: 1.5) {
            ForEach(widths.indices, id: \.self) { i in
                Rectangle()
                    .fill(Slip.ink.opacity(widths[i].alpha))
                    .frame(width: widths[i].width)
            }
        }
    }

    struct Bar {
        var width: CGFloat
        var alpha: Double
    }

    private var bars: [Bar] {
        var out: [Bar] = []
        var h = 5381
        for ch in seed.unicodeScalars { h = (h &* 33) &+ Int(ch.value) }
        for i in 0..<46 {
            h = (h &* 1103515245 &+ 12345) & 0x7fffffff
            let choices: [CGFloat] = [1, 1, 2, 3]
            let w: CGFloat = choices[(h >> 6) % 4]
            let alpha: Double = (h >> 3) % 5 == 0 ? Double(0.25) : Double(0.85)
            out.append(Bar(width: w, alpha: i % 9 == 0 ? Double(0.9) : alpha))
        }
        return out
    }
}

/// 会自动折行的一排小标签。
/// 用 SwiftUI.Layout 的全名——项目里另有一个 enum Layout。
struct FlowRow: SwiftUI.Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - 小票页

struct ReceiptView: View {

    let day: Date

    @EnvironmentObject var app: AppState
    @ObservedObject private var usage = UsageStore.shared
    @ObservedObject private var receipts = ReceiptStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var busy = false
    @State private var failed = ""
    @State private var shareItem: ShareImage?
    @State private var askWrite = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    slip
                        .padding(.top, 10)

                    if !failed.isEmpty {
                        Text(failed)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }

                    Text("小票不会自己生成关键词——那要让他读一遍今天，是要花钱的。\n数字部分是本来就记着的，看小票不花钱。")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 30)
            }
            .background(Theme.pageBackground(.light).opacity(0.6))
            .navigationTitle("小票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关上") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            askWrite = true
                        } label: {
                            Label(receipts.digest(day) == nil ? "让他写关键词" : "重新写一次",
                                  systemImage: "pencil.line")
                        }
                        Button {
                            save()
                        } label: {
                            Label("存成图片", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        if busy {
                            ProgressView()
                        } else {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    .disabled(busy)
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.image])
            }
            .alert("让他读一遍今天？", isPresented: $askWrite) {
                Button("算了", role: .cancel) {}
                Button("好") { write() }
            } message: {
                Text("他会把今天说过的话读一遍，写三到五个关键词和一句留言。这会调一次模型，花一次的钱。")
            }
        }
    }

    private var slip: some View {
        ReceiptSlip(
            day: day,
            usage: usage.day(day),
            pricing: app.settings.pricing,
            digest: receipts.digest(day),
            messageCount: messageCount,
            aiName: app.settings.aiName,
            userName: app.settings.userName,
            togetherSince: app.settings.togetherSince
        )
    }

    private var messageCount: Int {
        let cal = Calendar.current
        return app.conversations.reduce(0) { sum, c in
            sum + c.messages.filter { cal.isDate($0.createdAt, inSameDayAs: day) }.count
        }
    }

    private func write() {
        busy = true
        failed = ""
        Task {
            let result = await app.makeDigest(for: day)
            busy = false
            if result == nil {
                failed = "写不出来——今天可能还没说过话，或者模型没配好。"
            }
        }
    }

    private func save() {
        let renderer = ImageRenderer(content: slip.padding(18).background(Slip.paperEdge))
        renderer.scale = 3
        renderer.isOpaque = true
        if let image = renderer.uiImage {
            shareItem = ShareImage(image: image)
        } else {
            failed = "存不下来，再试一次。"
        }
    }
}

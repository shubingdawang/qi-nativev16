import SwiftUI

struct FootprintView: View {

    @EnvironmentObject var app: AppState
    @ObservedObject private var usage = UsageStore.shared
    @Environment(\.colorScheme) private var scheme

    /// 热力图上点中的那天。默认今天。
    @State private var picked: Date = Calendar.current.startOfDay(for: Date())
    @State private var showReceipt = false

    private var pricing: Pricing { app.settings.pricing }
    private var dayUsage: DayUsage { usage.day(picked) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                heatmapCard
                dayCard
                statsCard
                pricingCard
                storageCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, Layout.tabBarExpanded + 20)
        }
        .navigationTitle("足迹")
        .sheet(isPresented: $showReceipt) {
            ReceiptView(day: picked)
                .environmentObject(app)
        }
    }

    // MARK: 热力图

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("这些天")
            HeatmapView(counts: dailyCounts, picked: $picked)
            Text("点一个方块，看那天都说了什么、花了多少。")
                .font(.caption)
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .glassCard()
    }

    // MARK: 选中那天

    private var dayCard: some View {
        let u = dayUsage.total
        let cost = dayUsage.cost(pricing)
        return VStack(alignment: .leading, spacing: 12) {

            HStack(alignment: .firstTextBaseline) {
                Text(dayTitle)
                    .font(.app(19, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer()
                if !Calendar.current.isDateInToday(picked) {
                    Button("回今天") {
                        withAnimation { picked = Calendar.current.startOfDay(for: Date()) }
                    }
                    .font(.caption)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tile("聊了几句", "\(messageCount(on: picked))")
                tile("调用次数", "\(u.calls)")
                // 「新输入」其实就是没命中缓存的那部分，叫「缓存未命中」
                // 跟旁边那个「缓存命中」才对得上，一眼能看出是同一件事的两半
                tile("缓存未命中", UsageFormat.short(u.input))
                tile("输出（含思考）", UsageFormat.short(u.output))
                tile("缓存命中", UsageFormat.short(u.cacheRead))
                tile("缓存写入", UsageFormat.short(u.cacheWrite))
            }

            // 想掉的那部分。只有他真的报了才显示——
            // 不是所有模型都给这个数，摆一个常年为 0 的格子没意义。
            if u.reasoning > 0 {
                HStack {
                    Text("其中思考")
                        .font(.caption)
                        .foregroundStyle(Theme.textSoft(scheme))
                    Spacer()
                    Text(UsageFormat.short(u.reasoning))
                        .font(.app(13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSoft(scheme))
                    Text(String(format: "占输出 %.0f%%",
                                Double(u.reasoning) / Double(max(1, u.output)) * 100))
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }

            hitRateBar(u)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("这天大概花了")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSoft(scheme))
                Text(UsageFormat.money(cost))
                    .font(.app(26, weight: .semibold, design: .rounded))
                    .foregroundStyle(HomePalette.orange)
                Text("元")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSoft(scheme))
                Spacer()
            }
            .padding(.top, 2)

            if !dayUsage.sorted.isEmpty {
                Divider().opacity(0.35)
                VStack(spacing: 8) {
                    ForEach(dayUsage.sorted) { line in
                        sourceRow(line.source, line.usage)
                    }
                }
            } else {
                Text("这天还没有记录。用量是从这版开始记的，之前的补不回来。")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted(scheme))
            }

            Button {
                showReceipt = true
            } label: {
                HStack {
                    Image(systemName: "doc.plaintext")
                    Text("打一张这天的小票")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }
                .font(.app(15, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.softFill)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .glassCard()
    }

    /// 命中率那条。缓存命中越多越省钱，所以它值得单独占一行。
    private func hitRateBar(_ u: TokenUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("缓存命中率")
                    .font(.caption)
                    .foregroundStyle(Theme.textSoft(scheme))
                Spacer()
                Text(String(format: "%.0f%%", u.hitRate * 100))
                    .font(.app(13, weight: .semibold, design: .rounded))
                    .foregroundStyle(u.hitRate > 0.5 ? HomePalette.sage : Theme.textSoft(scheme))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.softFill)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [HomePalette.sage.opacity(0.75), HomePalette.sage],
                                startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(0, geo.size.width * u.hitRate))
                }
            }
            .frame(height: 8)
            Text("命中的部分只按很低的价钱算，所以这条越长越好。")
                .font(.caption2)
                .foregroundStyle(Theme.textMuted(scheme))
        }
    }

    private func sourceRow(_ source: UsageSource, _ u: TokenUsage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: source.symbol)
                .font(.app(13))
                .foregroundStyle(Theme.textSoft(scheme))
                .frame(width: 20)
            Text(source.label)
                .font(.app(14))
                .foregroundStyle(Theme.textMain(scheme))
            Spacer()
            if source.isTokenBased {
                Text(UsageFormat.short(u.total))
                    .font(.app(13, design: .rounded))
                    .foregroundStyle(Theme.textSoft(scheme))
            }
            Text("\(u.calls) 次")
                .font(.app(13, design: .rounded))
                .foregroundStyle(Theme.textMuted(scheme))
                .frame(width: 54, alignment: .trailing)
            Text(UsageFormat.money(pricing.cost(u, source: source)))
                .font(.app(13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textMain(scheme))
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSoft(scheme))
            Text(value)
                .font(.app(22, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textMain(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.softFill)
        )
    }

    // MARK: 老的那几项统计

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("一共")
            statRow("对话", "\(app.conversations.count) 个")
            statRow("消息", "\(totalMessages) 条")
            statRow("其中我说的", "\(userMessages) 条")
            statRow("发过的图", "\(totalImages) 张")
            statRow("连续记录", "\(streak) 天")
            statRow("到今天为止", UsageFormat.money(usage.allTimeCost(pricing)) + " 元")
        }
        .glassCard()
    }

    // MARK: 计费设置

    private var pricingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("计费设置")
            Text("花费只是按这个单价估算的，不是真实账单。")
                .font(.caption)
                .foregroundStyle(Theme.textMuted(scheme))

            Picker("计价方式", selection: Binding(
                get: { app.settings.pricing.mode },
                set: { app.settings.pricing.mode = $0 }
            )) {
                Text("按次").tag(BillingMode.perCall)
                Text("按 token").tag(BillingMode.perToken)
            }
            .pickerStyle(.segmented)

            if app.settings.pricing.mode == .perCall {
                priceField("每次回复", keyPath: \.perCall, unit: "元 / 次")
                Text("有些中转是一次调用一个价，不分输入输出。")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted(scheme))
            } else {
                priceField("新输入", keyPath: \.input, unit: "元 / 百万")
                priceField("缓存命中", keyPath: \.cacheRead, unit: "元 / 百万")
                priceField("缓存写入", keyPath: \.cacheWrite, unit: "元 / 百万")
                priceField("输出", keyPath: \.output, unit: "元 / 百万")
            }

            Divider().opacity(0.35)
            priceField("画一张图", keyPath: \.perImage, unit: "元 / 张")
            priceField("朗读一次", keyPath: \.perTTS, unit: "元 / 次")
            priceField("语音转字", keyPath: \.perASR, unit: "元 / 次")
            priceField("联网搜一次", keyPath: \.perSearch, unit: "元 / 次")
        }
        .glassCard()
    }

    private func priceField(_ title: String,
                            keyPath: WritableKeyPath<Pricing, Double>,
                            unit: String) -> some View {
        HStack {
            Text(title)
                .font(.app(14))
                .foregroundStyle(Theme.textMain(scheme))
            Spacer()
            // ⚠️ 以前是 `TextField(value:format: .number)`。
            // **那样填不进小数**：她敲下小数点的那一刻，"0." 被解析成 0，
            // 输入框立刻被改写回 "0"，点就没了，永远只能是整数。
            // 改成收字符串、只在**收键盘的时候**才解析，中间敲什么就显示什么。
            PriceField(value: Binding(
                get: { app.settings.pricing[keyPath: keyPath] },
                set: { app.settings.pricing[keyPath: keyPath] = $0 }
            ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.app(15, design: .rounded))
                .frame(width: 88)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.softFill)
                )
            Text(unit)
                .font(.caption2)
                .foregroundStyle(Theme.textMuted(scheme))
                .frame(width: 64, alignment: .leading)
        }
    }

    // MARK: 存储

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("存储")
            statRow("占用空间", storageText)
            Text("图片和聊天记录都存在这台手机上，不上传任何服务器。卸载 App 才会清空。")
                .font(.caption)
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .glassCard()
    }

    // MARK: 零件

    private func cardTitle(_ text: String) -> some View {
        Text(text)
            .font(.app(16, weight: .semibold))
            .foregroundStyle(Theme.textMain(scheme))
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.app(14))
                .foregroundStyle(Theme.textMain(scheme))
            Spacer()
            Text(value)
                .font(.app(14, design: .rounded))
                .foregroundStyle(Theme.textSoft(scheme))
        }
    }

    private var dayTitle: String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        let base = f.string(from: picked)
        if cal.isDateInToday(picked) { return base + " · 今天" }
        if cal.isDateInYesterday(picked) { return base + " · 昨天" }
        let w = DateFormatter()
        w.locale = Locale(identifier: "zh_CN")
        w.dateFormat = "EEEE"
        return base + " · " + w.string(from: picked)
    }

    // MARK: 数据

    private var totalMessages: Int {
        app.conversations.reduce(0) { $0 + $1.messages.count }
    }

    private var userMessages: Int {
        app.conversations.reduce(0) { sum, c in
            sum + c.messages.filter { $0.role == .user }.count
        }
    }

    private var totalImages: Int {
        app.conversations.reduce(0) { sum, c in
            sum + c.messages.reduce(0) { $0 + $1.imageNames.count }
        }
    }

    private func messageCount(on day: Date) -> Int {
        dailyCounts[Calendar.current.startOfDay(for: day)] ?? 0
    }

    /// 过去 91 天，每天有多少条消息
    private var dailyCounts: [Date: Int] {
        var result: [Date: Int] = [:]
        let cal = Calendar.current
        for c in app.conversations {
            for m in c.messages {
                let day = cal.startOfDay(for: m.createdAt)
                result[day, default: 0] += 1
            }
        }
        return result
    }

    private var streak: Int {
        let cal = Calendar.current
        let counts = dailyCounts
        var day = cal.startOfDay(for: Date())
        var n = 0
        // 今天还没说话的话，从昨天开始算
        if counts[day] == nil {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        while let count = counts[day], count > 0 {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }

    private var storageText: String {
        let url = Storage.documentsURL
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "—"
        }
        var total: Int64 = 0
        for case let file as URL in files {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: total)
    }
}

/// GitHub 那种小方块热力图。点一下就选中那天。
struct HeatmapView: View {

    let counts: [Date: Int]
    @Binding var picked: Date

    private let weeks = 13
    private let cal = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let day = date(week: week, weekday: weekday)
                            let isFuture = day > Date()
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(color(for: counts[day] ?? 0))
                                .frame(height: 13)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2.5)
                                        .strokeBorder(Color.primary.opacity(0.75), lineWidth: 1.4)
                                        .opacity(cal.isDate(day, inSameDayAs: picked) && !isFuture ? 1 : 0)
                                )
                                .opacity(isFuture ? 0 : 1)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard !isFuture else { return }
                                    withAnimation(.easeOut(duration: 0.15)) { picked = day }
                                }
                        }
                    }
                }
            }

            HStack(spacing: 4) {
                Text("少")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ForEach([0, 1, 4, 9, 20], id: \.self) { n in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: n))
                        .frame(width: 11, height: 11)
                }
                Text("多")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }

    /// 网格右下角是今天
    private func date(week: Int, weekday: Int) -> Date {
        let today = cal.startOfDay(for: Date())
        let todayWeekday = (cal.component(.weekday, from: today) + 6) % 7  // 周一 = 0
        let daysBack = (weeks - 1 - week) * 7 + (todayWeekday - weekday)
        return cal.date(byAdding: .day, value: -daysBack, to: today) ?? today
    }

    private func color(for count: Int) -> Color {
        switch count {
        case 0: return Color.gray.opacity(0.14)
        case 1...3: return Color.accentColor.opacity(0.30)
        case 4...8: return Color.accentColor.opacity(0.52)
        case 9...19: return Color.accentColor.opacity(0.74)
        default: return Color.accentColor
        }
    }
}

// MARK: - 能填小数的价格输入框

/// `TextField(value:format:)` 每敲一个键就解析一次，
/// 于是 "0." 变成 0、"0.0" 变成 0——**小数点根本落不下去**。
/// 这个改成拿字符串当中间态：她敲什么就显示什么，
/// 只有失去焦点（收键盘/切走）的时候才真的解析一次写回去。
struct PriceField: View {

    @Binding var value: Double
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("0", text: $text)
            .focused($focused)
            .onAppear { text = format(value) }
            .onChange(of: focused) { _, now in
                if now {
                    // 刚点进来：0 就清空，省得她要先删掉那个 0
                    if value == 0 { text = "" }
                } else {
                    commit()
                }
            }
            .onChange(of: value) { _, v in
                if !focused { text = format(v) }
            }
            .onSubmit { commit() }
    }

    private func commit() {
        let t = text.replacingOccurrences(of: "，", with: ".")
            .replacingOccurrences(of: "。", with: ".")
            .trimmingCharacters(in: .whitespaces)
        value = Double(t) ?? 0
        text = format(value)
    }

    /// 0.04 显示成 0.04，不是 0.040000000000000001，也不是 4e-02
    private func format(_ v: Double) -> String {
        if v == 0 { return "0" }
        let s = String(format: "%.6f", v)
        var out = s
        while out.hasSuffix("0") { out.removeLast() }
        if out.hasSuffix(".") { out.removeLast() }
        return out
    }
}

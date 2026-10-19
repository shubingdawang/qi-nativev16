import SwiftUI
import PhotosUI

// MARK: - 工资 | 记账

/// 侧边栏「工资」点进来：顶上一个小开关，左边工资、右边记账
struct WageHubView: View {
    @AppStorage("wageHub.tab") private var tab = 0

    var body: some View {
        Group {
            if tab == 0 { WageView() } else { AccountBookView() }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HubSwitch(tab: $tab)
                .padding(.top, 2)
                .padding(.bottom, 8)
        }
    }
}

private struct HubSwitch: View {
    @Binding var tab: Int
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            pill("工资", 0)
            pill("记账", 1)
        }
        .padding(3)
        .background(GlassSurface(radius: 18, strength: app.settings.glassOpacity))
    }

    private func pill(_ title: String, _ i: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { tab = i }
        } label: {
            Text(title)
                .font(.app(13.5, weight: tab == i ? .semibold : .regular))
                .foregroundStyle(tab == i ? Color.white : Theme.textMuted(scheme))
                .frame(width: 76, height: 30)
                .background {
                    if tab == i {
                        Capsule().fill(app.settings.accentColor)
                            .matchedGeometryEffect(id: "pill", in: ns)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 小零件

/// 分类图标：她挑的图 > 表情 > 线条图标
struct CategoryIcon: View {
    let category: ExpenseCategory
    var size: CGFloat = 34
    var tint: Color

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.12))
            if let name = category.image, let img = ImageStore.cached(name) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if !category.emoji.isEmpty {
                Text(category.emoji).font(.system(size: size * 0.5))
            } else {
                Image(systemName: category.symbol)
                    .font(.system(size: size * 0.42, weight: .light))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 名字和金额中间那一串点
struct DotLeader: View {
    var color: Color

    var body: some View {
        GeometryReader { g in
            Path { p in
                p.move(to: CGPoint(x: 2, y: g.size.height / 2))
                p.addLine(to: CGPoint(x: max(2, g.size.width - 2), y: g.size.height / 2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [0.1, 4]))
        }
        .frame(height: 6)
        .frame(minWidth: 12)
    }
}

/// 一类花了多少（列表用）
private struct CatSum: Identifiable {
    let cat: ExpenseCategory
    let amount: Double
    var id: String { cat.id }
}

/// 打开编辑页用
struct ExpenseRef: Identifiable {
    let id = UUID()
    let expense: Expense
    let isNew: Bool
    var proposal: UUID? = nil
}

enum BookFormat {
    static func money(_ v: Double) -> String { "¥" + WageStore.money(v) }

    static func day(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: d)
    }

    static func weekday(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEE"
        return f.string(from: d)
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

// MARK: - 记账页

struct AccountBookView: View {

    @ObservedObject private var book = AccountBook.shared
    @ObservedObject private var wage = WageStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var month = Date()
    @State private var showCalendar = false
    @State private var dayShown: Date?
    @State private var editing: ExpenseRef?
    @State private var receipt = false
    @State private var preview: String?
    @State private var editingLevels = false

    private let cal = Calendar.current
    private var accent: Color { app.settings.accentColor }
    private var main: Color { Theme.textMain(scheme) }
    private var muted: Color { Theme.textMuted(scheme) }

    var body: some View {
        ZStack {
            PaneScroll {
                if !book.pending.isEmpty { pendingSection }
                summaryCard
                if showCalendar {
                    calendarCard
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                addCard
                todaySection
                MoneyCard(accent: accent)
                if !book.widgetStatus.isEmpty {
                    Text("小组件同步：" + book.widgetStatus)
                        .font(.app(10))
                        .foregroundStyle(muted.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
            }

            if let d = dayShown {
                dayOverlay(d)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
            }
            if receipt {
                BookReceipt(accent: accent) { receipt = false }
                    .transition(.opacity)
                    .zIndex(15)
            }
            if editingLevels {
                LevelsEditor(levels: book.levels, accent: accent) { new in
                    if let new { book.setLevels(new) }
                    editingLevels = false
                }
                .transition(.opacity)
                .zIndex(16)
            }
            if let name = preview {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    if let img = ImageStore.cached(name) {
                        WageZoomImage(image: img).padding(20)
                    }
                }
                .onTapGesture { preview = nil }
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(.easeOut(duration: 0.2), value: dayShown)
        .animation(.easeOut(duration: 0.2), value: receipt)
        .animation(.easeOut(duration: 0.2), value: editingLevels)
        .animation(.easeOut(duration: 0.18), value: preview)
        .navigationTitle("记账")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { receipt = true } label: {
                    Text("总结")
                        .font(.app(14, weight: .medium))
                        .foregroundStyle(accent)
                }
            }
        }
        .sheet(item: $editing) { ref in
            ExpenseEditor(start: ref.expense, isNew: ref.isNew, proposalID: ref.proposal, accent: accent)
        }
    }

    // MARK: 新一笔

    private func newExpense(at day: Date = Date()) -> Expense {
        let last = book.file.expenses.max { $0.at < $1.at }
        var at = Date()
        if !cal.isDateInToday(day) {
            // 补别的日子：时间先放在那天中午
            at = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        }
        return Expense(category: last?.category ?? "food", name: "", amount: 0, at: at)
    }

    // MARK: 他提的

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("等你确认")
                .font(.app(13, weight: .semibold))
                .foregroundStyle(main)
            ForEach(book.pending) { p in
                ProposalCard(proposal: p, accent: accent,
                             onApprove: { withAnimation { book.approve(p.id) } },
                             onRevise: {
                                 editing = ExpenseRef(expense: p.expense, isNew: p.kind == .add, proposal: p.id)
                             },
                             onReject: { withAnimation { book.dismiss(p.id) } })
            }
        }
    }

    // MARK: 顶上：这个月

    private var isThisMonth: Bool { cal.isDate(month, equalTo: Date(), toGranularity: .month) }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = cal.isDate(month, equalTo: Date(), toGranularity: .year) ? "M月" : "yyyy年M月"
        return f.string(from: month)
    }

    private var sums: [CatSum] {
        book.byCategory(month: month, upTo: isThisMonth ? Date() : nil).map { CatSum(cat: $0.0, amount: $0.1) }
    }

    private var elapsedDays: Int {
        if isThisMonth { return cal.component(.day, from: Date()) }
        return cal.range(of: .day, in: .month, for: month)?.count ?? 30
    }

    private var summaryCard: some View {
        let list = sums
        let total = list.reduce(0) { $0 + $1.amount }
        return Button {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { showCalendar.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(monthTitle + "支出")
                        .font(.app(12))
                        .foregroundStyle(muted)
                    Spacer()
                    HStack(spacing: 4) {
                        Text(showCalendar ? "收起日历" : "按天看")
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showCalendar ? 180 : 0))
                    }
                    .font(.app(11.5))
                    .foregroundStyle(accent)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("¥")
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(accent)
                    Text(WageStore.money(total))
                        .font(HomeType.number(32, weight: .semibold))
                        .foregroundStyle(main)
                        .contentTransition(.numericText())
                    Spacer()
                    if total > 0 {
                        Text("日均 " + BookFormat.money(total / Double(max(1, elapsedDays))))
                            .font(.app(11.5))
                            .foregroundStyle(muted)
                    }
                }
                if list.isEmpty {
                    Text("这个月还没有花销")
                        .font(.app(12.5))
                        .foregroundStyle(muted)
                } else {
                    VStack(spacing: 10) {
                        ForEach(list) { s in categoryRow(s, total: total) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard()
    }

    private func categoryRow(_ s: CatSum, total: Double) -> some View {
        HStack(spacing: 10) {
            CategoryIcon(category: s.cat, size: 28, tint: accent)
            Text(s.cat.name)
                .font(.app(13))
                .foregroundStyle(main)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(main.opacity(0.06))
                    Capsule().fill(accent.opacity(0.55))
                        .frame(width: max(4, g.size.width * CGFloat(total > 0 ? s.amount / total : 0)))
                }
            }
            .frame(height: 5)
            Text(BookFormat.money(s.amount))
                .font(.app(13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(main)
                .frame(minWidth: 64, alignment: .trailing)
        }
    }

    // MARK: 按天看

    private var monthCells: [Date?] {
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: month)) else { return [] }
        let lead = cal.component(.weekday, from: first) - 1
        return Array(repeating: nil, count: lead) + book.days(in: month).map { Optional($0) }
    }

    private func shift(_ n: Int) {
        guard let m = cal.date(byAdding: .month, value: n, to: month) else { return }
        withAnimation(.easeOut(duration: 0.2)) { month = m }
    }

    private var calendarCard: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text(monthTitle)
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(main)
                Spacer()
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 0) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { d in
                    Text(d)
                        .font(.app(11))
                        .foregroundStyle(muted)
                        .frame(maxWidth: .infinity)
                }
            }
            let cells = monthCells
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(cells.indices, id: \.self) { i in
                    if let d = cells[i] {
                        heatCell(d)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
            legend
        }
        .glassCard()
    }

    /// 第几档 → 多深
    private func heat(_ lv: Int) -> Color {
        guard lv > 0 else { return main.opacity(0.04) }
        let n = max(1, book.levels.count)
        let t = Double(lv - 1) / Double(n)
        return accent.opacity(0.14 + 0.72 * t)
    }

    private func heatCell(_ d: Date) -> some View {
        let amount = book.total(on: d)
        let lv = book.level(amount)
        let today = cal.isDateInToday(d)
        let dark = lv > 0 && Double(lv - 1) / Double(max(1, book.levels.count)) >= 0.5
        return Button { dayShown = d } label: {
            VStack(spacing: 1) {
                Text("\(cal.component(.day, from: d))")
                    .font(.app(12, weight: today ? .bold : .regular))
                Text(amount > 0 ? WageStore.money(amount) : " ")
                    .font(.app(8.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(dark ? Color.white : main)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(heat(lv)))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(today ? accent : Color.clear, lineWidth: 1.2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private struct LegendItem: Identifiable {
        let text: String
        let level: Int
        var id: Int { level }
    }

    private var legendItems: [LegendItem] {
        let l = book.levels
        var out = [LegendItem(text: "0", level: 0)]
        for (i, v) in l.enumerated() {
            let lo = i == 0 ? 0 : l[i - 1]
            let hi: String = WageStore.money(v)
            let low: String = WageStore.money(lo)
            let t: String = i == 0 ? "<\(hi)" : "\(low)–\(hi)"
            out.append(LegendItem(text: t, level: i + 1))
        }
        if let last = l.last { out.append(LegendItem(text: "≥" + WageStore.money(last), level: l.count + 1)) }
        return out
    }

    private var legend: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(legendItems) { item in
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3).fill(heat(item.level)).frame(width: 11, height: 11)
                            Text(item.text).font(.app(10)).foregroundStyle(muted)
                        }
                    }
                }
            }
            Button { editingLevels = true } label: {
                Text("调整")
                    .font(.app(11.5, weight: .medium))
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    // MARK: 记一笔（钉在汇总下面）

    private var addCard: some View {
        Button { editing = ExpenseRef(expense: newExpense(), isNew: true) } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().strokeBorder(accent.opacity(0.5),
                                                      style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                VStack(alignment: .leading, spacing: 2) {
                    Text("记一笔")
                        .font(.app(15, weight: .semibold))
                        .foregroundStyle(main)
                    Text("今天 · " + BookFormat.day(Date()))
                        .font(.app(11.5))
                        .foregroundStyle(muted)
                }
                Spacer()
            }
            .padding(Look.inset)
            .frame(maxWidth: .infinity)
            .background(GlassSurface(radius: Theme.cardRadius, strength: app.settings.glassOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(accent.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 今天

    private var todaySection: some View {
        let lines = book.lines(on: Date())
        let sum = lines.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今天")
                    .font(.app(13, weight: .semibold))
                    .foregroundStyle(main)
                Spacer()
                if sum > 0 {
                    Text(BookFormat.money(sum))
                        .font(.app(12.5, weight: .medium))
                        .foregroundStyle(muted)
                }
            }
            if lines.isEmpty {
                Text("今天还没有记账")
                    .font(.app(12.5))
                    .foregroundStyle(muted)
                    .padding(.vertical, 6)
            }
            ForEach(lines) { l in lineCard(l) }
        }
    }

    private func open(_ l: BookLine) {
        guard case .book(let id) = l.source, let e = book.expense(id) else { return }
        editing = ExpenseRef(expense: e, isNew: false)
    }

    private func lineCard(_ l: BookLine) -> some View {
        let c = book.category(l.category)
        var sub = [c.name, BookFormat.time(l.at)]
        if case .wage = l.source { sub = [c.name, "工资页记的"] }
        if !l.spreadNote.isEmpty { sub.append(l.spreadNote) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                CategoryIcon(category: c, size: 36, tint: accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(l.name.isEmpty ? c.name : l.name)
                        .font(.app(14.5, weight: .medium))
                        .foregroundStyle(main)
                        .lineLimit(1)
                    Text(sub.joined(separator: " · "))
                        .font(.app(11))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(BookFormat.money(l.amount))
                    .font(.app(15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(main)
            }
            if !l.note.isEmpty {
                Text(l.note)
                    .font(.app(11.5))
                    .foregroundStyle(muted)
                    .padding(.leading, 48)
            }
            if !l.images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(l.images, id: \.self) { n in
                            Button { preview = n } label: { WageThumb(name: n, size: 46) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.leading, 48)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .contentShape(Rectangle())
        .onTapGesture { open(l) }
        .contextMenu {
            if case .book(let id) = l.source {
                Button { open(l) } label: { Label("编辑", systemImage: "pencil") }
                Button(role: .destructive) { withAnimation { book.delete(id) } } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    // MARK: 点开某一天

    private func dayOverlay(_ d: Date) -> some View {
        let lines = book.lines(on: d)
        let sum = lines.reduce(0) { $0 + $1.amount }
        return ZStack {
            Color.black.opacity(0.32).ignoresSafeArea()
                .onTapGesture { dayShown = nil }
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(BookFormat.day(d))
                        .font(.app(17, weight: .semibold))
                        .foregroundStyle(main)
                    Text(BookFormat.weekday(d))
                        .font(.app(12))
                        .foregroundStyle(muted)
                    Spacer()
                    Text(BookFormat.money(sum))
                        .font(.app(15, weight: .semibold))
                        .foregroundStyle(accent)
                }
                if lines.isEmpty {
                    Text("这天没有花销")
                        .font(.app(13))
                        .foregroundStyle(muted)
                } else {
                    ViewThatFits(in: .vertical) {
                        dayList(lines)
                        ScrollView { dayList(lines) }.frame(maxHeight: 420)
                    }
                }
                Button {
                    let e = newExpense(at: d)
                    dayShown = nil
                    editing = ExpenseRef(expense: e, isNew: true)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("在这天记一笔")
                    }
                    .font(.app(13, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .frame(maxWidth: 360)
            .background(GlassSurface(radius: 22, strength: max(1, app.settings.glassOpacity)))
            .padding(.horizontal, 22)
        }
    }

    private func dayList(_ lines: [BookLine]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(lines) { l in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("•").foregroundStyle(accent)
                        Text(l.name.isEmpty ? book.category(l.category).name : l.name)
                            .font(.app(14))
                            .foregroundStyle(main)
                            .lineLimit(1)
                            .layoutPriority(1)
                        DotLeader(color: muted.opacity(0.7))
                        Text(BookFormat.money(l.amount))
                            .font(.app(14, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(main)
                            .layoutPriority(1)
                    }
                    let small = [l.spreadNote, l.note].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !small.isEmpty {
                        Text(small)
                            .font(.app(11))
                            .foregroundStyle(muted)
                            .padding(.leading, 13)
                    }
                    if !l.images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(l.images, id: \.self) { n in
                                    Button { preview = n } label: { WageThumb(name: n, size: 52) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.leading, 13)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard case .book = l.source else { return }
                    dayShown = nil
                    open(l)
                }
            }
        }
    }
}

// MARK: - 他提的那张卡

/// 他写好的一笔：分类、名字、金额都填好了，等她点头
struct ProposalCard: View {
    let proposal: BookProposal
    let accent: Color
    var reviseTitle = "改一改"
    let onApprove: () -> Void
    let onRevise: () -> Void
    var onReject: (() -> Void)? = nil

    @ObservedObject private var book = AccountBook.shared
    @Environment(\.colorScheme) private var scheme

    private var main: Color { Theme.textMain(scheme) }
    private var muted: Color { Theme.textMuted(scheme) }

    private var kindText: String {
        switch proposal.kind {
        case .add: return "新记一笔"
        case .update: return "改一笔"
        case .delete: return "删一笔"
        }
    }

    var body: some View {
        let e = proposal.expense
        let c = book.category(e.category)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(kindText)
                    .font(.app(11, weight: .semibold))
                    .foregroundStyle(proposal.kind == .delete ? Color.red : accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill((proposal.kind == .delete ? Color.red : accent).opacity(0.12)))
                Spacer()
                Text(BookFormat.day(e.at) + " " + BookFormat.time(e.at))
                    .font(.app(11))
                    .foregroundStyle(muted)
            }
            HStack(spacing: 12) {
                CategoryIcon(category: c, size: 40, tint: accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(e.name.isEmpty ? c.name : e.name)
                        .strikethrough(proposal.kind == .delete)
                        .font(.app(15, weight: .semibold))
                        .foregroundStyle(main)
                    Text(detail(e, c))
                        .font(.app(11.5))
                        .foregroundStyle(muted)
                }
                Spacer()
                Text(BookFormat.money(e.amount))
                    .strikethrough(proposal.kind == .delete)
                    .font(.app(17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(main)
            }
            if let b = proposal.before, proposal.kind == .update {
                Text(beforeText(b))
                    .font(.app(11.5))
                    .foregroundStyle(muted)
            }
            if !e.note.isEmpty {
                Text("备注：" + e.note)
                    .font(.app(11.5))
                    .foregroundStyle(muted)
            }
            if !e.images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(e.images, id: \.self) { WageThumb(name: $0, size: 40) }
                }
            }
            if !proposal.why.isEmpty {
                Text(proposal.why)
                    .italic()
                    .font(.app(12))
                    .foregroundStyle(main.opacity(0.8))
            }
            HStack(spacing: 10) {
                Button(action: onApprove) {
                    Text("同意")
                        .font(.app(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent))
                }
                .buttonStyle(.plain)
                Button(action: onRevise) {
                    Text(reviseTitle)
                        .font(.app(14, weight: .medium))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(accent.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            if let onReject {
                Button(action: onReject) {
                    Text("不要这一笔")
                        .font(.app(11.5))
                        .foregroundStyle(muted)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .glassCard()
    }

    private func beforeText(_ b: Expense) -> String {
        let name: String = b.name.isEmpty ? "未命名" : b.name
        let cat: String = book.category(b.category).name
        let money: String = BookFormat.money(b.amount)
        return "原来：\(cat) · \(name) · \(money)"
    }

    private func detail(_ e: Expense, _ c: ExpenseCategory) -> String {
        var bits = [c.name]
        if let n = e.spreadDays, n > 1 {
            bits.append("摊 \(n) 天，每天 " + BookFormat.money(e.amount / Double(n)))
        }
        if let r = e.remindEvery, r > 0 { bits.append("每 \(r) 天问一次") }
        return bits.joined(separator: " · ")
    }
}

// MARK: - 编辑一笔

struct ExpenseEditor: View {

    @ObservedObject private var book = AccountBook.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let isNew: Bool
    let proposalID: UUID?
    let accent: Color

    @State private var e: Expense
    @State private var amountText: String
    @State private var spreadOn: Bool
    @State private var daysText: String
    /// 按用量算（一包几片）
    @State private var countOn: Bool
    @State private var packText: String
    @State private var unitText: String
    /// 0 = 不问，-1 = 自己填
    @State private var remind: Int
    @State private var remindText: String
    @State private var picking = false
    @State private var picked: [PhotosPickerItem] = []
    /// 这次新挂上的图：没存就走的话删掉
    @State private var added: Set<String> = []
    @State private var saved = false
    @State private var managing = false
    @State private var confirmDelete = false
    /// 拍小票
    @State private var shooting = false
    @State private var scanning = false

    static let remindPresets = [0, 1, 3, 7, 14, 30]

    init(start: Expense, isNew: Bool, proposalID: UUID? = nil, accent: Color) {
        self.isNew = isNew
        self.proposalID = proposalID
        self.accent = accent
        _e = State(initialValue: start)
        _amountText = State(initialValue: start.amount > 0 ? WageStore.money(start.amount) : "")
        _spreadOn = State(initialValue: (start.spreadDays ?? 0) > 1)
        _daysText = State(initialValue: start.spreadDays.map { String($0) } ?? "")
        _countOn = State(initialValue: (start.packCount ?? 0) > 0)
        _packText = State(initialValue: start.packCount.map { String($0) } ?? "")
        _unitText = State(initialValue: start.unit)
        let r = start.remindEvery ?? 0
        _remind = State(initialValue: Self.remindPresets.contains(r) ? r : -1)
        _remindText = State(initialValue: r > 0 ? String(r) : "")
    }

    private var main: Color { Theme.textMain(scheme) }
    private var muted: Color { Theme.textMuted(scheme) }

    private var amount: Double {
        Double(amountText.replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "¥", with: "")
            .trimmingCharacters(in: .whitespaces)) ?? 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(spacing: Look.gap) {
                        categorySection
                        mainSection
                        timeSection
                        photoSection
                        spreadSection
                        if !isNew && proposalID == nil { deleteButton }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isNew ? "记一笔" : "改一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("存") { save() }
                        .font(.app(15, weight: .semibold))
                        .foregroundStyle(amount > 0 ? accent : muted)
                        .disabled(amount <= 0)
                }
            }
        }
        .background(PhotoPickHost(open: $picking, picked: $picked,
                                  maxCount: max(1, Expense.maxImages - e.images.count)))
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task { @MainActor in
                var first: UIImage?
                for it in items {
                    guard e.images.count < Expense.maxImages,
                          let data = try? await it.loadTransferable(type: Data.self),
                          let raw = UIImage(data: data),
                          let name = ImageStore.save(ImageStore.downscale(raw, maxSide: 1600))
                    else { continue }
                    added.insert(name)
                    e.images.append(name)
                    if first == nil { first = raw }
                }
                picked = []
                // 还没填金额：挑的第一张当小票认一下
                if amount <= 0, let first { await scan(first) }
            }
        }
        .sheet(isPresented: $managing) { CategoryManager(accent: accent) }
        .fullScreenCover(isPresented: $shooting) {
            CameraPicker { img in
                shooting = false
                guard let img else { return }
                Task { @MainActor in
                    if e.images.count < Expense.maxImages,
                       let name = ImageStore.save(ImageStore.downscale(img, maxSide: 1600)) {
                        added.insert(name)
                        e.images.append(name)
                    }
                    await scan(img)
                }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("删掉这一笔？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                book.delete(e.id)
                saved = true
                dismiss()
            }
        }
        .onDisappear {
            // 没存就走了：这次挂上的图别留着占地方
            if !saved { added.forEach { ImageStore.delete($0) } }
        }
    }

    // MARK: 分类

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分类").font(.app(12)).foregroundStyle(muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 14) {
                ForEach(book.categories) { c in
                    Button { e.category = c.id } label: {
                        VStack(spacing: 5) {
                            CategoryIcon(category: c, size: 40, tint: accent)
                                .overlay(Circle().strokeBorder(accent, lineWidth: e.category == c.id ? 1.6 : 0))
                            Text(c.name)
                                .font(.app(10.5))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .foregroundStyle(e.category == c.id ? accent : muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button { managing = true } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(muted)
                            .frame(width: 40, height: 40)
                            .background(Circle().strokeBorder(muted.opacity(0.5),
                                                              style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        Text("管理").font(.app(10.5)).foregroundStyle(muted)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 名字、金额、备注

    private var mainSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(.app(20, weight: .medium))
                    .foregroundStyle(accent)
                TextField("0", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(HomeType.number(30, weight: .semibold))
                    .foregroundStyle(main)
            }
            Divider().opacity(0.5)
            TextField("名字，比如：拿铁", text: $e.name)
                .font(.app(15))
                .foregroundStyle(main)
            Divider().opacity(0.5)
            TextField("备注", text: $e.note, axis: .vertical)
                .lineLimit(1...4)
                .font(.app(13.5))
                .foregroundStyle(main)
        }
        .glassCard()
    }

    // MARK: 时间

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker(selection: $e.at, displayedComponents: [.date, .hourAndMinute]) {
                Text("时间").font(.app(14)).foregroundStyle(main)
            }
            .tint(accent)
        }
        .glassCard()
    }

    // MARK: 照片

    /// 认小票：金额、店名空着才填，填过的不动
    private func scan(_ img: UIImage) async {
        scanning = true
        let r = await ReceiptReader.read(img)
        scanning = false
        if amount <= 0, let v = r.amount { amountText = WageStore.money(v) }
        if e.name.trimmingCharacters(in: .whitespaces).isEmpty, let m = r.merchant { e.name = m }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("照片 \(e.images.count)/\(Expense.maxImages)").font(.app(12)).foregroundStyle(muted)
                Spacer()
                if scanning {
                    ProgressView().controlSize(.small)
                    Text("在认小票…").font(.app(11.5)).foregroundStyle(muted)
                } else {
                    Button { shooting = true } label: {
                        Label("拍小票", systemImage: "doc.text.viewfinder")
                            .font(.app(12, weight: .medium))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(e.images.count >= Expense.maxImages)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(e.images, id: \.self) { n in
                        WageThumb(name: n, size: 64)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    e.images.removeAll { $0 == n }
                                    if added.contains(n) { added.remove(n); ImageStore.delete(n) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 17))
                                        .foregroundStyle(Color.white, Color.black.opacity(0.45))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 5, y: -5)
                            }
                    }
                    if e.images.count < Expense.maxImages {
                        Button { picking = true } label: {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(accent)
                                .frame(width: 64, height: 64)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
                .padding(.trailing, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 摊销

    /// 0 整笔，1 按天摊，2 按用量
    private var mode: Binding<Int> {
        Binding(get: { countOn ? 2 : (spreadOn ? 1 : 0) },
                set: { v in
                    withAnimation(.easeOut(duration: 0.2)) {
                        spreadOn = v == 1
                        countOn = v == 2
                    }
                })
    }

    private var spreadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("怎么算").font(.app(14)).foregroundStyle(main)
            Picker("", selection: mode) {
                Text("整笔").tag(0)
                Text("按天摊").tag(1)
                Text("按用量").tag(2)
            }
            .pickerStyle(.segmented)
            Text(countOn ? "数得清的东西（卫生巾、药）：一包几片，每天用了几就算几份。从买的那天起，每天的编辑页里会问「今天用了吗」，用完就不再出现"
                 : spreadOn ? "能用很久的东西：每天只算一份，用完那天把剩下的一起算上"
                 : "整笔算在花钱那天")
                .font(.app(11))
                .foregroundStyle(muted)
            if countOn {
                HStack(spacing: 6) {
                    Text("一包几").font(.app(13.5)).foregroundStyle(main)
                    Spacer()
                    TextField("20", text: $packText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.app(14, weight: .medium))
                        .frame(width: 60)
                    TextField("片", text: $unitText)
                        .multilineTextAlignment(.center)
                        .font(.app(13.5))
                        .frame(width: 36)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.softFillDeep))
                }
                if let n = Int(packText), n > 0, amount > 0 {
                    Text("每" + unitName + "约 " + BookFormat.money(amount / Double(n)))
                        .font(.app(11.5))
                        .foregroundStyle(accent)
                }
                if !isNew { countUsedRow }
            }
            if spreadOn {
                HStack(spacing: 6) {
                    Text("用多少天").font(.app(13.5)).foregroundStyle(main)
                    Spacer()
                    TextField("30", text: $daysText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.app(14, weight: .medium))
                        .frame(width: 70)
                    Text("天").font(.app(13.5)).foregroundStyle(muted)
                }
                if let n = Int(daysText), n > 1, amount > 0 {
                    Text("每天约 " + BookFormat.money(amount / Double(n)))
                        .font(.app(11.5))
                        .foregroundStyle(accent)
                }
                HStack {
                    Text("多久问一次还在不在用").font(.app(13.5)).foregroundStyle(main)
                    Spacer()
                    Picker("", selection: $remind) {
                        Text("不问").tag(0)
                        Text("每天").tag(1)
                        Text("每 3 天").tag(3)
                        Text("每 7 天").tag(7)
                        Text("每 14 天").tag(14)
                        Text("每 30 天").tag(30)
                        Text("自己填").tag(-1)
                    }
                    .pickerStyle(.menu)
                    .tint(accent)
                }
                if remind == -1 {
                    HStack(spacing: 6) {
                        Text("每").font(.app(13.5)).foregroundStyle(muted)
                        TextField("5", text: $remindText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 50)
                        Text("天问一次").font(.app(13.5)).foregroundStyle(muted)
                    }
                }
                if !isNew {
                    usedUpRow
                }
            }
        }
        .glassCard()
    }

    private var unitName: String {
        let u = unitText.trimmingCharacters(in: .whitespaces)
        return u.isEmpty ? "片" : u
    }

    /// 按用量算的那一笔：用了几、还剩几，可以提前标成用完
    private var countUsedRow: some View {
        let total = min(Int(packText) ?? 0, e.usage.values.reduce(0, +))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已用 \(total)/\(Int(packText) ?? 0) " + unitName)
                    .font(.app(12.5))
                    .foregroundStyle(muted)
                Spacer()
                if e.usedUp != nil {
                    Button("还没用完") { e.usedUp = nil }
                        .font(.app(12.5, weight: .medium))
                        .foregroundStyle(accent)
                } else {
                    Button("已用完") { e.usedUp = Date() }
                        .font(.app(12.5, weight: .medium))
                        .foregroundStyle(accent)
                }
            }
            if e.usedUp != nil {
                DatePicker(selection: Binding(get: { e.usedUp ?? Date() }, set: { e.usedUp = $0 }),
                           in: min(e.at, Date())...Date(), displayedComponents: .date) {
                    Text("用完那天").font(.app(13.5)).foregroundStyle(main)
                }
                .tint(accent)
                Text("没用的那几" + unitName + "算在这一天")
                    .font(.app(11))
                    .foregroundStyle(muted)
            }
        }
    }

    private var usedUpRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if e.usedUp != nil {
                    Text("用了 \(book.daysUsed(e)) 天 · 每天 \(BookFormat.money(amount / Double(max(1, book.daysUsed(e)))))")
                        .font(.app(12.5))
                        .foregroundStyle(muted)
                    Spacer()
                    Button("还在用") { e.usedUp = nil }
                        .font(.app(12.5, weight: .medium))
                        .foregroundStyle(accent)
                } else {
                    Text("已经用了 \(book.daysUsed(e)) 天")
                        .font(.app(12.5))
                        .foregroundStyle(muted)
                    Spacer()
                    Button("已用完") { e.usedUp = Date() }
                        .font(.app(12.5, weight: .medium))
                        .foregroundStyle(accent)
                }
            }
            if e.usedUp != nil {
                // 哪天用完的可以改：以前每天那一份按实际天数重新摊
                DatePicker(selection: Binding(get: { e.usedUp ?? Date() }, set: { e.usedUp = $0 }),
                           in: min(e.at, Date())...Date(), displayedComponents: .date) {
                    Text("用完那天").font(.app(13.5)).foregroundStyle(main)
                }
                .tint(accent)
            }
        }
    }

    private var deleteButton: some View {
        Button { confirmDelete = true } label: {
            Text("删除这一笔")
                .font(.app(14))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .glassCard(padding: 0)
    }

    // MARK: 存

    private func save() {
        guard amount > 0 else { return }
        var out = e
        out.amount = amount
        out.name = out.name.trimmingCharacters(in: .whitespacesAndNewlines)
        out.note = out.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.name.isEmpty { out.name = book.category(out.category).name }
        if countOn, let n = Int(packText), n > 0 {
            out.packCount = n
            out.unit = unitName
            out.spreadDays = nil
            out.remindEvery = nil
        } else if spreadOn, let n = Int(daysText), n > 1 {
            out.packCount = nil
            out.usage = [:]
            out.spreadDays = n
            let r = remind == -1 ? (Int(remindText) ?? 0) : remind
            out.remindEvery = r > 0 ? r : nil
        } else {
            out.packCount = nil
            out.usage = [:]
            out.spreadDays = nil
            out.remindEvery = nil
            out.usedUp = nil
        }
        if let pid = proposalID { book.settle(pid, with: out) } else { book.save(out) }
        saved = true
        dismiss()
    }
}

// MARK: - 分类管理

struct CategoryManager: View {
    let accent: Color
    @ObservedObject private var book = AccountBook.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(book.categories) { c in
                            NavigationLink {
                                CategoryEditor(start: c, isNew: false, accent: accent)
                            } label: {
                                row(c)
                            }
                            .buttonStyle(.plain)
                        }
                        NavigationLink {
                            CategoryEditor(start: ExpenseCategory(id: "c" + String(UUID().uuidString.prefix(8)),
                                                                  name: "", symbol: "star", custom: true),
                                           isNew: true, accent: accent)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                Text("新分类")
                            }
                            .font(.app(14, weight: .medium))
                            .foregroundStyle(accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                    .strokeBorder(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("分类")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ c: ExpenseCategory) -> some View {
        HStack(spacing: 12) {
            CategoryIcon(category: c, size: 34, tint: accent)
            Text(c.name)
                .font(.app(14.5))
                .foregroundStyle(Theme.textMain(scheme))
            Spacer()
            if c.custom {
                Text("自己加的")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .glassCard(padding: 12)
        .contentShape(Rectangle())
    }
}

struct CategoryEditor: View {
    let isNew: Bool
    let accent: Color
    @State private var c: ExpenseCategory
    @State private var mode: Int
    @State private var picking = false
    @State private var picked: PhotosPickerItem?
    @State private var confirmDelete = false
    @ObservedObject private var book = AccountBook.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    init(start: ExpenseCategory, isNew: Bool, accent: Color) {
        self.isNew = isNew
        self.accent = accent
        _c = State(initialValue: start)
        _mode = State(initialValue: start.image != nil ? 2 : (start.emoji.isEmpty ? 0 : 1))
    }

    private var main: Color { Theme.textMain(scheme) }
    private var muted: Color { Theme.textMuted(scheme) }

    var body: some View {
        ZStack {
            WallpaperBackground()
            ScrollView {
                VStack(spacing: Look.gap) {
                    VStack(spacing: 14) {
                        CategoryIcon(category: c, size: 64, tint: accent)
                        TextField("分类名字", text: $c.name)
                            .multilineTextAlignment(.center)
                            .font(.app(16, weight: .medium))
                            .foregroundStyle(main)
                    }
                    .frame(maxWidth: .infinity)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Picker("", selection: $mode) {
                            Text("线条").tag(0)
                            Text("表情").tag(1)
                            Text("照片").tag(2)
                        }
                        .pickerStyle(.segmented)
                        switch mode {
                        case 0: symbolGrid
                        case 1: emojiField
                        default: photoPick
                        }
                    }
                    .glassCard()

                    if c.custom && !isNew {
                        Button { confirmDelete = true } label: {
                            Text("删掉这个分类")
                                .font(.app(14))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .glassCard(padding: 0)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(isNew ? "新分类" : "改分类")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("存") {
                    var out = c
                    out.name = out.name.trimmingCharacters(in: .whitespaces)
                    if out.name.isEmpty { out.name = "新分类" }
                    book.saveCategory(out)
                    dismiss()
                }
                .foregroundStyle(accent)
            }
        }
        .background(SinglePhotoPickHost(open: $picking, picked: $picked))
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self),
                   let raw = UIImage(data: data),
                   let name = ImageStore.save(ImageStore.downscale(raw, maxSide: 300)) {
                    c.image = name
                    c.emoji = ""
                }
                picked = nil
            }
        }
        .confirmationDialog("删掉「\(c.name)」？这一类下面的账会挪到「其他」", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                book.deleteCategory(c.id)
                dismiss()
            }
        }
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 12) {
            ForEach(AccountBook.symbolChoices, id: \.self) { s in
                Button {
                    c.symbol = s
                    c.emoji = ""
                    c.image = nil
                } label: {
                    Image(systemName: s)
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(c.symbol == s && c.emoji.isEmpty && c.image == nil ? accent : main.opacity(0.75))
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(c.symbol == s && c.emoji.isEmpty && c.image == nil
                                                  ? accent.opacity(0.14) : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emojiField: some View {
        HStack {
            Text("输入一个表情").font(.app(13.5)).foregroundStyle(muted)
            Spacer()
            TextField("🍰", text: Binding(
                get: { c.emoji },
                set: { v in
                    c.emoji = String(v.trimmingCharacters(in: .whitespaces).suffix(1))
                    if !c.emoji.isEmpty { c.image = nil }
                }))
                .multilineTextAlignment(.center)
                .font(.system(size: 28))
                .frame(width: 60)
        }
    }

    private var photoPick: some View {
        Button { picking = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "photo")
                Text(c.image == nil ? "从相册挑一张" : "换一张")
            }
            .font(.app(14, weight: .medium))
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 日历颜色分档

private struct LevelsEditor: View {
    let accent: Color
    let done: ([Double]?) -> Void
    @State private var texts: [String]
    @Environment(\.colorScheme) private var scheme

    init(levels: [Double], accent: Color, done: @escaping ([Double]?) -> Void) {
        self.accent = accent
        self.done = done
        _texts = State(initialValue: levels.map { WageStore.money($0) })
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.32).ignoresSafeArea()
                .onTapGesture { done(nil) }
            VStack(alignment: .leading, spacing: 14) {
                Text("日历颜色怎么分")
                    .font(.app(16, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Text("一天花到第一个数以下最浅，每过一个数深一档")
                    .font(.app(11.5))
                    .foregroundStyle(Theme.textMuted(scheme))
                ForEach(texts.indices, id: \.self) { i in
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(accent.opacity(0.14 + 0.72 * Double(i + 1) / Double(max(1, texts.count))))
                            .frame(width: 16, height: 16)
                        Text("第 \(i + 1) 个数").font(.app(13.5)).foregroundStyle(Theme.textMain(scheme))
                        Spacer()
                        Text("¥").foregroundStyle(Theme.textMuted(scheme))
                        TextField("0", text: Binding(
                            get: { i < texts.count ? texts[i] : "" },
                            set: { v in if i < texts.count { texts[i] = v } }))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                HStack(spacing: 16) {
                    Button("加一档") {
                        let last = Double(texts.last ?? "") ?? 100
                        texts.append(WageStore.money(last * 2))
                    }
                    .disabled(texts.count >= 7)
                    Button("减一档") { if texts.count > 1 { texts.removeLast() } }
                        .disabled(texts.count <= 1)
                    Spacer()
                    Button("存") {
                        done(texts.compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) })
                    }
                    .font(.app(15, weight: .semibold))
                }
                .font(.app(13.5))
                .foregroundStyle(accent)
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.regularMaterial))
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - 总结小票

/// 右上角「总结」：从小票机里吐出来一张，这个月 1 号到今天
struct BookReceipt: View {
    let accent: Color
    let close: () -> Void

    @ObservedObject private var book = AccountBook.shared
    @State private var out: CGFloat = 0
    @State private var paperH: CGFloat = 560

    private let ink = Color(red: 0.17, green: 0.16, blue: 0.15)
    private let paper = Color(red: 0.988, green: 0.981, blue: 0.965)

    var body: some View {
        let now = Date()
        let cats = book.byCategory(month: now, upTo: now).map { CatSum(cat: $0.0, amount: $0.1) }
        let spent = cats.reduce(0) { $0 + $1.amount }
        let inc = book.income(month: now, upTo: now)
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture(perform: close)
            VStack(spacing: 0) {
                // 出纸口
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.12)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 320, height: 22)
                    Capsule().fill(Color.black.opacity(0.85)).frame(width: 300, height: 4).offset(y: 5)
                }
                .zIndex(1)
                ScrollView(showsIndicators: false) {
                    receiptBody(cats: cats, spent: spent, wage: inc.wage, other: inc.other, now: now)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { g in
                            Color.clear.onAppear { paperH = g.size.height }
                        })
                        .offset(y: (out - 1) * paperH)
                }
                .frame(width: 296)
                .frame(maxHeight: min(paperH, 620))
                .clipped()
                .scrollDisabled(out < 1)

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
                .opacity(Double(out))
            }
        }
        .onAppear {
            withAnimation(.timingCurve(0.22, 0.9, 0.32, 1, duration: 1.6)) { out = 1 }
            // 吐纸的时候手里一下一下地震
            Task { @MainActor in
                let g = UIImpactFeedbackGenerator(style: .soft)
                for _ in 0..<9 {
                    g.impactOccurred(intensity: 0.5)
                    try? await Task.sleep(nanoseconds: 110_000_000)
                }
            }
        }
    }

    private func receiptBody(cats: [CatSum], spent: Double,
                             wage: Double, other: Double, now: Date) -> some View {
        VStack(spacing: 9) {
            Text("栖")
                .font(.system(size: 22, weight: .semibold, design: .serif))
            Text("本 月 小 票")
                .font(.system(size: 11, design: .monospaced))
                .tracking(3)
            Text(rangeText(now))
                .font(.system(size: 11, design: .monospaced))
                .opacity(0.7)
            dashes
            sectionTitle("支出")
            if cats.isEmpty {
                Text("还没有花销").font(.system(size: 12, design: .monospaced)).opacity(0.6)
            }
            ForEach(cats) { c in
                row(c.cat.name, c.amount)
            }
            dashes
            row("支出合计", spent, bold: true)
            dashes
            sectionTitle("收入")
            row("工资", wage)
            if other > 0.0001 { row("其他收入", other) }
            row("收入合计", wage + other, bold: true)
            doubleDashes
            row("结余", wage + other - spent, bold: true, big: true)
            barcode(now)
                .padding(.top, 10)
            Text(stamp(now))
                .font(.system(size: 10, design: .monospaced))
                .opacity(0.55)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 30)
        .frame(width: 296)
        .background(paper)
        .clipShape(ReceiptEdge())
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ name: String, _ v: Double, bold: Bool = false, big: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .lineLimit(1)
                .layoutPriority(1)
            DotLeader(color: ink.opacity(0.35))
            Text((v < 0 ? "-" : "") + BookFormat.money(abs(v)))
                .layoutPriority(1)
        }
        .font(.system(size: big ? 15 : 12.5, weight: bold ? .semibold : .regular, design: .monospaced))
    }

    private var dashes: some View {
        Line()
            .stroke(ink.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(height: 1)
            .padding(.vertical, 2)
    }

    private var doubleDashes: some View {
        VStack(spacing: 2) { dashes; dashes }
    }

    private func rangeText(_ now: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        let cal = Calendar.current
        let first = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let g = DateFormatter()
        g.dateFormat = "MM.dd"
        return f.string(from: first) + " — " + g.string(from: now)
    }

    private func stamp(_ now: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: now)
    }

    /// 底下那一条条码（按月份算出来的，同一个月每次都一样）
    private func barcode(_ now: Date) -> some View {
        var seed = UInt64(Calendar.current.component(.month, from: now) * 7919
                          + Calendar.current.component(.year, from: now))
        var bars: [CGFloat] = []
        for _ in 0..<46 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            bars.append(CGFloat(1 + (seed >> 61)))
        }
        return HStack(spacing: 1.2) {
            ForEach(bars.indices, id: \.self) { i in
                Rectangle().fill(ink).frame(width: bars[i], height: 34)
            }
        }
    }
}

private struct Line: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

/// 小票底下那一排锯齿
private struct ReceiptEdge: Shape {
    func path(in r: CGRect) -> Path {
        let tooth: CGFloat = 9, depth: CGFloat = 6
        var p = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: r.maxX, y: 0))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - depth))
        var x = r.maxX
        var down = true
        while x > 0 {
            x -= tooth / 2
            p.addLine(to: CGPoint(x: max(0, x), y: down ? r.maxY : r.maxY - depth))
            down.toggle()
        }
        p.addLine(to: CGPoint(x: 0, y: r.maxY - depth))
        p.closeSubpath()
        return p
    }
}

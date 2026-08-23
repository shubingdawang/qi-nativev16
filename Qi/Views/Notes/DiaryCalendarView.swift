import SwiftUI

/// 日记的第三种看法：日历。
///
/// 出处是她给的 p7 那张图——一个月摊在格子里，哪天写过，那天就有点儿东西；
/// 下面跟着「条目」。她提的几条：
/// · 「本月条目」改成「条目」（选了哪天就是哪天的，写「本月」是错的）
/// · 点月份能挑月，`<` `>` 能翻到前后月
/// · 点「年」就把今年的日记全摊出来
/// · **现有的功能一样都不能丢**——所以列表和便签那两种看法都还在，
///   这里只是多加一种，点右上角那个图标轮着换。
///
/// 日期是从 `dateText` 里读的（`2026/8/5` 或 `2026-08-05` 两种都认）。
/// 读不出来的那些不会丢——底下会单独有一撮「没写日期」。
struct DiaryCalendarView: View {

    let entries: [MCPEntry]

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    /// 现在看的是哪个月
    @State private var year: Int
    @State private var month: Int
    /// 点中的那一天（0 表示没点，看整月）
    @State private var day = 0
    /// 年模式：整年摊开，不显示格子
    @State private var yearMode = false
    @State private var picking = false
    @State private var opened: MCPEntry?

    init(entries: [MCPEntry]) {
        self.entries = entries
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        _year = State(initialValue: now.year ?? 2026)
        _month = State(initialValue: now.month ?? 1)
    }

    // MARK: 日期

    /// 一条日记落在哪天。读不出来就是 nil。
    ///
    /// 不用 `DateFormatter` 是因为她那边回来的日期没补零（`2026/8/5`），
    /// 而且分隔符 `/ - .` 三种都出现过——自己切三段反而稳。
    static func ymd(_ text: String) -> (y: Int, m: Int, d: Int)? {
        let parts = text
            .components(separatedBy: CharacterSet(charactersIn: "/-."))
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              y > 1900, (1...12).contains(m), (1...31).contains(d) else { return nil }
        return (y, m, d)
    }

    /// 这个月有多少天、1 号是星期几（0 = 周日）
    private var monthInfo: (days: Int, firstWeekday: Int) {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = 1
        let cal = Calendar(identifier: .gregorian)
        guard let first = cal.date(from: c),
              let range = cal.range(of: .day, in: .month, for: first) else {
            return (30, 0)
        }
        return (range.count, cal.component(.weekday, from: first) - 1)
    }

    // MARK: 分堆

    /// 那一天写了哪几条
    private func items(y: Int, m: Int, d: Int) -> [MCPEntry] {
        entries.filter {
            guard let p = Self.ymd($0.dateText) else { return false }
            return p.y == y && p.m == m && p.d == d
        }
    }

    private func items(y: Int, m: Int) -> [MCPEntry] {
        entries.filter {
            guard let p = Self.ymd($0.dateText) else { return false }
            return p.y == y && p.m == m
        }
    }

    private func items(y: Int) -> [MCPEntry] {
        entries.filter {
            guard let p = Self.ymd($0.dateText) else { return false }
            return p.y == y
        }
    }

    /// 日期读不出来的那些。**不能丢**——丢了她会以为日记没了。
    private var undated: [MCPEntry] {
        entries.filter { Self.ymd($0.dateText) == nil }
    }

    /// 下面「条目」那一栏此刻该显示谁
    private var listed: [MCPEntry] {
        if yearMode { return items(y: year) }
        if day > 0 { return items(y: year, m: month, d: day) }
        return items(y: year, m: month)
    }

    private var listTitle: String {
        if yearMode { return "\(year) 年" }
        if day > 0 { return "\(month) 月 \(day) 日" }
        return "\(month) 月"
    }

    // MARK: 界面

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !yearMode {
                grid
            }

            entryList

            if !undated.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("没写日期 · \(undated.count) 条")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                    ForEach(undated) { row($0) }
                }
            }
        }
        .sheet(isPresented: $picking) { monthPicker }
        .sheet(item: $opened) { DiaryEntrySheet(entry: $0) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { step(-1) } label: { arrow("chevron.left") }
                .buttonStyle(.plain)

            Button {
                if yearMode { yearMode = false } else { picking = true }
            } label: {
                HStack(spacing: 5) {
                    Text(yearMode ? "\(String(year)) 年" : "\(String(year)) 年 \(month) 月")
                        .heading(17)
                        .foregroundStyle(Theme.textMain(scheme))
                    Image(systemName: "chevron.down")
                        .font(.app(9, weight: .semibold))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .buttonStyle(.plain)

            Button { step(1) } label: { arrow("chevron.right") }
                .buttonStyle(.plain)

            Spacer(minLength: 4)

            // 「年」：一按就是今年全部。她要的那条。
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    yearMode.toggle()
                    day = 0
                }
            } label: {
                Text("年")
                    .font(.app(12, weight: .medium))
                    .foregroundStyle(yearMode ? .white : app.settings.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(yearMode
                        ? app.settings.accentColor
                        : app.settings.accentColor.opacity(0.16)))
            }
            .buttonStyle(.plain)
        }
    }

    private func arrow(_ name: String) -> some View {
        Image(systemName: name)
            .font(.app(12, weight: .semibold))
            .foregroundStyle(Theme.textSoft(scheme))
            .frame(width: 32, height: 32)
            .background(Circle().fill(Theme.softFillDeep))
    }

    /// 翻。月模式翻月，年模式翻年。
    private func step(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            day = 0
            if yearMode { year += delta; return }
            month += delta
            if month > 12 { month = 1; year += 1 }
            if month < 1 { month = 12; year -= 1 }
        }
    }

    private var grid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { w in
                    Text(w)
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(maxWidth: .infinity)
                }
            }

            let info = monthInfo
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                      spacing: 4) {
                // 月初空出来的那几格
                ForEach(0..<info.firstWeekday, id: \.self) { i in
                    Color.clear.frame(height: 42).id("pad\(i)")
                }
                ForEach(1...info.days, id: \.self) { d in
                    cell(d)
                }
            }
        }
        .padding(12)
        .glassBackground(radius: 18, strength: app.settings.glassOpacity * 0.8)
    }

    /// 一格。写过的那天底下有点，点几个就是几条（最多三个）。
    private func cell(_ d: Int) -> some View {
        let n = items(y: year, m: month, d: d).count
        let on = day == d
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { day = (day == d ? 0 : d) }
        } label: {
            VStack(spacing: 3) {
                Text("\(d)")
                    .font(.app(13, weight: n > 0 ? .semibold : .regular))
                    .foregroundStyle(on ? .white
                                     : (n > 0 ? Theme.textMain(scheme) : Theme.textMuted(scheme)))
                HStack(spacing: 2) {
                    ForEach(0..<min(n, 3), id: \.self) { _ in
                        Circle()
                            .fill(on ? Color.white.opacity(0.9) : app.settings.accentColor)
                            .frame(width: 3.5, height: 3.5)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(on ? app.settings.accentColor
                          : (n > 0 ? app.settings.accentColor.opacity(0.10) : .clear))
            }
        }
        .buttonStyle(.plain)
    }

    private var entryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                // 她说的：这里以前写「本月条目」，可选了某一天之后就不是本月了。
                // 现在标题只写「条目」，看的是哪一段挂在后面。
                Text("条目")
                    .heading(15)
                    .foregroundStyle(Theme.textMain(scheme))
                Text(listTitle)
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                Spacer()
                Text("\(listed.count) 条")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }

            if listed.isEmpty {
                EmptyNote(title: day > 0 ? "这天没写" : "这段时间没写")
            } else {
                ForEach(listed) { row($0) }
            }
        }
    }

    private func row(_ e: MCPEntry) -> some View {
        Button { opened = e } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if !e.author.isEmpty {
                        Text(e.author)
                            .font(.app(10.5, weight: .semibold))
                            .foregroundStyle(app.settings.accentColor)
                    }
                    Text(e.dateText)
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Spacer(minLength: 4)
                }
                Text(e.displayTitle)
                    .font(.app(14, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !e.body.isEmpty {
                    Text(e.body)
                        .font(.app(11.5))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if !e.tags.isEmpty {
                    Text(e.tags.prefix(4).joined(separator: "、"))
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassBackground(radius: 14, strength: app.settings.glassOpacity * 0.7)
        }
        .buttonStyle(.plain)
    }

    /// 挑月份：年份用 `<` `>` 拨，月份十二格摆着，点哪个是哪个。
    private var monthPicker: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                VStack(spacing: 18) {
                    HStack(spacing: 16) {
                        Button { year -= 1 } label: { arrow("chevron.left") }
                            .buttonStyle(.plain)
                        Text("\(String(year)) 年")
                            .font(.app(20, weight: .semibold))
                            .foregroundStyle(Theme.textMain(scheme))
                        Button { year += 1 } label: { arrow("chevron.right") }
                            .buttonStyle(.plain)
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                              spacing: 10) {
                        ForEach(1...12, id: \.self) { m in
                            let n = items(y: year, m: m).count
                            Button {
                                month = m
                                day = 0
                                yearMode = false
                                picking = false
                            } label: {
                                VStack(spacing: 3) {
                                    Text("\(m) 月")
                                        .font(.app(15, weight: .medium))
                                        .foregroundStyle(month == m ? .white : Theme.textMain(scheme))
                                    Text(n > 0 ? "\(n) 条" : "—")
                                        .font(.app(10))
                                        .foregroundStyle(month == m
                                                         ? Color.white.opacity(0.8)
                                                         : Theme.textMuted(scheme))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(month == m
                                              ? app.settings.accentColor
                                              : app.settings.accentColor.opacity(n > 0 ? 0.12 : 0.05))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        yearMode = true
                        day = 0
                        picking = false
                    } label: {
                        Text("看今年全部")
                            .font(.app(13, weight: .medium))
                            .foregroundStyle(app.settings.accentColor)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(18)
            }
            .navigationTitle("选择月份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关上") { picking = false }
                }
            }
        }
    }
}

/// 点开一条日记看全文。
///
/// 便签那一叠和日历这两处都要用同一张，所以拎出来单独放——
/// 抄两份的话改一处另一处就长歪。
struct DiaryEntrySheet: View {

    let entry: MCPEntry

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            if !entry.author.isEmpty {
                                Text(entry.author)
                                    .font(.app(12, weight: .semibold))
                                    .foregroundStyle(app.settings.accentColor)
                            }
                            Text(entry.dateText)
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                        if !entry.title.isEmpty {
                            Text(entry.title)
                                .font(.app(18, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                        }
                        Text(entry.body)
                            .font(.app(15))
                            .lineSpacing(7)
                            .foregroundStyle(Theme.textSoft(scheme))
                            .textSelection(.enabled)
                        if !entry.tags.isEmpty {
                            HStack(spacing: 5) {
                                ForEach(entry.tags, id: \.self) { t in
                                    Text(t)
                                        .font(.app(10))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule()
                                            .fill(app.settings.accentColor.opacity(0.16)))
                                        .foregroundStyle(Theme.textSoft(scheme))
                                }
                            }
                        }
                    }
                    .padding(18)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关上") { dismiss() }
                }
            }
        }
    }
}

import SwiftUI

/// 手帐本。
///
/// 每个月一本日记本，按月份排在书架上；点开是这个月的横线本，
/// 每天一条：日期、那天几页的标题、下面一排缩略图，点缩略图进去接着改。
struct JournalView: View {

    @ObservedObject private var store = JournalStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var opened: JournalPage?
    @State private var openedMonth: String?
    @State private var pickingMonth = false

    private let columns = [GridItem(.flexible(), spacing: 22), GridItem(.flexible(), spacing: 22)]

    /// 一本：月份那一串字 + 那个月的页
    struct Volume: Identifiable {
        let key: String
        let year: Int
        let month: Int
        let pages: [JournalPage]
        var id: String { key }
    }

    /// 书架上的每一本：写过的月份都在（页撕光了也还在，长按能收起来），
    /// 这个月就算还没写也摆一本空的
    private var volumes: [Volume] {
        var keys = store.shelf
        for g in store.byMonth where !keys.contains(g.month) { keys.append(g.month) }
        let nowKey = JournalPage(day: Date()).monthKey
        if !keys.contains(nowKey) { keys.append(nowKey) }
        let groups = Dictionary(uniqueKeysWithValues: store.byMonth.map { ($0.month, $0.pages) })
        return keys.compactMap { k -> Volume? in
            // 「2026 年 9 月」→ 2026, 9
            let nums = k.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            guard nums.count >= 2 else { return nil }
            return Volume(key: k, year: nums[0], month: nums[1], pages: groups[k] ?? [])
        }
        .sorted { ($0.year, $0.month) > ($1.year, $1.month) }
    }

    private var years: [Int] {
        var seen: [Int] = []
        for v in volumes where !seen.contains(v.year) { seen.append(v.year) }
        return seen
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(years, id: \.self) { y in
                    Text(Self.yearText(y))
                        .font(.system(size: 13, design: .serif))
                        .tracking(3)
                        .foregroundStyle(Theme.textMuted(scheme))
                    LazyVGrid(columns: columns, spacing: 26) {
                        ForEach(volumes.filter { $0.year == y }) { v in
                            book(v)
                        }
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 12)
            .padding(.bottom, Layout.tabBarExpanded + 20)
        }
        .navigationTitle("手帐")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        opened = store.newPage()
                    } label: {
                        Label("写今天这一页", systemImage: "square.and.pencil")
                    }
                    Button {
                        pickingMonth = true
                    } label: {
                        Label("摆一本以前的月份", systemImage: "books.vertical")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $pickingMonth) {
            MonthPickSheet { d in
                store.addVolume(JournalPage(day: d).monthKey)
                pickingMonth = false
            }
            .presentationDetents([.height(320)])
        }
        .navigationDestination(item: $opened) { p in
            JournalPageView(page: p)
        }
        .navigationDestination(item: $openedMonth) { key in
            JournalMonthView(monthKey: key)
        }
    }

    static func yearText(_ y: Int) -> String {
        let digits = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        return String(y).compactMap { c in c.wholeNumberValue.map { digits[$0] } }.joined()
    }

    private func book(_ v: Volume) -> some View {
        let styleIndex = store.cover(for: v.key, number: v.month)
        let style = NotebookStyle.all[styleIndex % NotebookStyle.all.count]
        return Button { openedMonth = v.key } label: {
            VStack(spacing: 6) {
                NotebookCover(style: style, month: v.month)
                VStack(spacing: 1) {
                    Text("\(v.month)月")
                        .font(.app(13.5))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text(v.pages.isEmpty ? "还没写" : "\(v.pages.count) 页")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if v.pages.isEmpty && v.key != JournalPage(day: Date()).monthKey {
                Button(role: .destructive) {
                    withAnimation(.easeOut(duration: 0.2)) { store.removeVolume(v.key) }
                } label: {
                    Label("收起这一本", systemImage: "archivebox")
                }
            }
            ForEach(NotebookStyle.all.indices, id: \.self) { i in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { store.setCover(i, for: v.key) }
                } label: {
                    if i == styleIndex {
                        Label(NotebookStyle.all[i].name, systemImage: "checkmark")
                    } else {
                        Text(NotebookStyle.all[i].name)
                    }
                }
            }
        }
    }
}

// MARK: - 翻开一本

/// 这个月的横线本：每天一条
struct JournalMonthView: View {
    let monthKey: String

    @ObservedObject private var store = JournalStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var opened: JournalPage?
    @State private var confirmDelete: JournalPage?

    private let cal = Calendar.current

    private var pages: [JournalPage] {
        store.pages.filter { $0.monthKey == monthKey }
    }

    struct DayGroup: Identifiable {
        let day: Date
        let pages: [JournalPage]
        var id: Date { day }
    }

    /// 按天分好，新的一天在上面
    private var days: [DayGroup] {
        var buckets: [Date: [JournalPage]] = [:]
        for p in pages { buckets[cal.startOfDay(for: p.day), default: []].append(p) }
        return buckets.keys.sorted(by: >).map { d in
            DayGroup(day: d, pages: (buckets[d] ?? []).sorted { $0.updatedAt < $1.updatedAt })
        }
    }

    /// 「2026 年 9 月」里的年和月
    private var keyNums: (year: Int, month: Int) {
        let n = monthKey.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        let now = Date()
        return n.count >= 2 ? (n[0], n[1]) : (cal.component(.year, from: now), cal.component(.month, from: now))
    }

    private var monthNumber: Int { keyNums.month }

    private var paper: Color { scheme == .dark ? Color(hexString: "2A2622")! : Color(hexString: "FFFDF6")! }
    private var rule: Color { scheme == .dark ? Color.white.opacity(0.07) : Color(hexString: "ECE4D5")! }
    private var dateInk: Color { Color(hexString: "B07A5A")! }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Notes")
                        .font(.system(size: 22, design: .serif))
                        .foregroundStyle(Theme.textMain(scheme))
                    Spacer()
                    Text("month / \(String(format: "%02d", monthNumber))")
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .padding(.bottom, 18)

                if days.isEmpty {
                    Text("这一本还是空的。右上角 ＋ 写第一页")
                        .font(.app(13))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(height: 30)
                }
                ForEach(days) { d in
                    entry(d.day, d.pages)
                        .padding(.bottom, 16)
                }
                Spacer(minLength: 220)
            }
            .padding(.leading, 34)
            .padding(.trailing, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) { ruledPaper }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4,
                                              bottomTrailingRadius: 14, topTrailingRadius: 14,
                                              style: .continuous))
            .background(alignment: .leading) {
                // 左边那条深色的装订
                Color(hexString: "3D3631")!
                    .frame(width: 10)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6,
                                                      bottomTrailingRadius: 0, topTrailingRadius: 0))
                    .offset(x: -8)
            }
            .padding(.leading, 26)
            .padding(.trailing, 18)
            .padding(.top, 8)
            .padding(.bottom, Layout.tabBarExpanded + 20)
        }
        .navigationTitle("\(monthNumber)月")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { opened = store.newPage(on: newPageDay) } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(item: $opened) { p in
            JournalPageView(page: p)
        }
        .confirmationDialog("撕掉这一页？", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        ), titleVisibility: .visible) {
            Button("撕掉", role: .destructive) {
                if let p = confirmDelete { store.remove(p.id) }
                confirmDelete = nil
            }
            Button("取消", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("该页上的照片将一并删除。")
        }
    }

    /// 在这一本里新建：这个月就记在今天，以前的月份记在那个月最后一天
    private var newPageDay: Date {
        let k = keyNums
        guard let any = cal.date(from: DateComponents(year: k.year, month: k.month, day: 1)),
              !cal.isDate(any, equalTo: Date(), toGranularity: .month),
              let range = cal.range(of: .day, in: .month, for: any),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: any)),
              let last = cal.date(byAdding: .day, value: range.count - 1, to: first)
        else { return Date() }
        return cal.date(bySettingHour: 20, minute: 0, second: 0, of: last) ?? last
    }

    /// 横线 + 左边一列小孔
    private var ruledPaper: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper))
            var y: CGFloat = 62
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(rule))
                y += 30
            }
            var hy: CGFloat = 30
            while hy < size.height - 20 {
                ctx.fill(Path(ellipseIn: CGRect(x: 11, y: hy, width: 6, height: 6)),
                         with: .color(Color.gray.opacity(0.35)))
                hy += 26
            }
        }
    }

    private func dayLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M/d · EEE"
        return f.string(from: d)
    }

    private func entry(_ day: Date, _ list: [JournalPage]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayLabel(day))
                .font(.app(11))
                .foregroundStyle(dateInk)
            Text(list.map(\.displayTitle).joined(separator: "  ·  "))
                .font(.app(14))
                .foregroundStyle(Theme.textMain(scheme))
                .lineLimit(2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(list) { p in
                        Button { opened = p } label: {
                            JournalThumb(page: p, height: 92)
                                .overlay(alignment: .topTrailing) {
                                    if p.shared {
                                        Image(systemName: "person.2.fill")
                                            .font(.system(size: 7))
                                            .foregroundStyle(app.settings.accentColor)
                                            .padding(4)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                store.toggleShared(p.id)
                            } label: {
                                Label(p.shared ? "不给他看了" : "给他看",
                                      systemImage: p.shared ? "person.slash" : "person.2")
                            }
                            Button(role: .destructive) { confirmDelete = p } label: {
                                Label("撕掉这一页", systemImage: Icon.trash)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - 一页的缩略图

/// 缩略图是**把那一页真的缩小画一遍**，不是截图——所以永远跟里面一致，也不用管缓存失效。
struct JournalThumb: View {
    let page: JournalPage
    var height: CGFloat = 132

    var body: some View {
        ZStack {
            (Color(hexString: page.paperHex) ?? Color(hexString: "F3E9D8")!)
            GeometryReader { geo in
                ForEach(page.elements.sorted { $0.z < $1.z }) { e in
                    thumb(e)
                        .scaleEffect(height / 132)
                        .position(x: e.x * geo.size.width,
                                  y: e.y * geo.size.height)
                }
            }
        }
        .frame(width: height * 0.74, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
    }

    /// 缩略图里的一样东西。只画个意思——一格才一百来点宽，
    /// 画细节没人看得见，画个色块和轮廓反而看得清这一页大概长什么样。
    @ViewBuilder
    private func thumb(_ e: JournalElement) -> some View {
        Group {
            switch e.kind {
            case .text, .quote:
                Text(e.text)
                    .font(.app(5))
                    .foregroundStyle(e.color)
                    .lineLimit(3)
                    .frame(maxWidth: 54)
            case .tape:
                Rectangle().fill(e.color.opacity(0.62))
                    .frame(width: 30, height: 7)
            case .sticker:
                Text(e.emoji).font(.app(11))
            case .stamp:
                Text(e.emoji.isEmpty ? "📮" : e.emoji)
                    .font(.app(8))
                    .frame(width: 15, height: 17)
                    .background(Color(hexString: "F6F2E8")!)
            case .clip:
                RoundedRectangle(cornerRadius: 1).fill(e.color)
                    .frame(width: 6, height: 9)
            case .note:
                Rectangle().fill(e.color).frame(width: 30, height: 25)
            case .photo:
                if let img = ImageStore.thumb(e.imageName, maxPixel: 120) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 33, height: 33).clipped()
                } else {
                    Rectangle().fill(Color.gray.opacity(0.3))
                        .frame(width: 33, height: 33)
                }
            case .cutout:
                // 剪贴是透明底的 PNG，**不裁方块也不套框**——
                // 裁了透明的那圈就没了，看着就不是贴纸了
                if let img = ImageStore.thumb(e.imageName, maxPixel: 120) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "scissors")
                        .font(.app(11))
                        .foregroundStyle(e.color)
                }
            case .frame:
                VStack(spacing: 0) {
                    if let img = ImageStore.thumb(e.imageName, maxPixel: 120) {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 30, height: 30).clipped()
                    } else {
                        Rectangle().fill(Color(hexString: "DDD8CE")!)
                            .frame(width: 30, height: 30)
                    }
                    Rectangle().fill(Color.white).frame(width: 30, height: 7)
                }
                .padding(2)
                .background(Color.white)
            }
        }
        .scaleEffect(e.scale)
        .rotationEffect(.degrees(e.angle))
    }
}

/// 挑一个月份（摆一本以前的手帐本用）
struct MonthPickSheet: View {
    let done: (Date) -> Void
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var month = Calendar.current.component(.month, from: Date())

    var body: some View {
        VStack(spacing: 14) {
            Text("摆哪个月的那一本")
                .font(.app(15, weight: .semibold))
                .padding(.top, 18)
            HStack(spacing: 0) {
                Picker("年", selection: $year) {
                    ForEach((2020...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { y in
                        Text("\(String(y)) 年").tag(y)
                    }
                }
                .pickerStyle(.wheel)
                Picker("月", selection: $month) {
                    ForEach(1...12, id: \.self) { m in Text("\(m) 月").tag(m) }
                }
                .pickerStyle(.wheel)
            }
            .frame(height: 160)
            Button {
                if let d = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) { done(d) }
            } label: {
                Text("摆上去")
                    .font(.app(15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
        }
    }
}

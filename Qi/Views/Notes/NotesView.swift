import SwiftUI

/// 札记：日记 / 记忆 / 经期 / 心跳 / 状态。
/// 这五样的数据都在小屋的 MCP 服务器上，所以这里做的事情就是
/// 调对应的工具，把结果显示出来，再提供写入的表单。
struct NotesView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var tab = 0

    private let tabs: [(String, String)] = [
        (Icon.diary, "日记"), (Icon.memory, "记忆"), (Icon.cycle, "经期"),
        (Icon.heart, "心跳"), (Icon.body, "身体")
    ]

    var body: some View {
        VStack(spacing: 0) {

            HStack(alignment: .top) {
                Text("札记")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            HStack(spacing: 8) {
                    ForEach(tabs.indices, id: \.self) { i in
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { tab = i }
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: tabs[i].0)
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundStyle(tab == i
                                                     ? app.settings.accentColor
                                                     : Theme.textMuted(scheme))
                                Text(tabs[i].1)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(tab == i ? Theme.textMain(scheme) : Theme.textMuted(scheme))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(tab == i
                                          ? app.settings.accentColor.opacity(0.28)
                                          : Theme.softFillDeep)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Theme.softStroke, lineWidth: 0.8)
                            }
                        }
                        .buttonStyle(.plain)
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Group {
                switch tab {
                case 0: DiaryPane()
                case 1: MemoryPane()
                case 2: PeriodPane()
                case 3: PulsePane()
                default: StatusPane()
                }
            }
        }
    }
}

// MARK: - 通用零件

/// MCP 返回的内容，直接以卡片显示。
/// 服务器回的可能是 JSON 也可能是排好版的文字，两种都能看。
struct MCPResultCard: View {
    let text: String
    let failed: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(prettified)
            .font(.system(size: 13))
            .foregroundStyle(failed ? Color.red : Theme.textSoft(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .glassCard()
    }

    /// 是 JSON 的话排一下版，好读一点
    private var prettified: String {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .withoutEscapingSlashes]),
              let s = String(data: pretty, encoding: .utf8)
        else { return text }
        return s
    }
}


/// 一条日记 / 一条记忆，单独一张卡
struct MCPEntryCard: View {
    let entry: MCPEntry
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if !entry.author.isEmpty {
                    Text(entry.author)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(app.settings.accentColor)
                }
                if !entry.dateText.isEmpty {
                    Text(entry.dateText)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                Spacer(minLength: 0)
                if !entry.id.isEmpty {
                    Text(entry.id)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.textMuted(scheme).opacity(0.6))
                }
            }

            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .lineLimit(expanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            if !entry.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(entry.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(app.settings.accentColor.opacity(0.16)))
                                .foregroundStyle(Theme.textSoft(scheme))
                        }
                    }
                }
            }
        }
        .glassCard()
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
        }
    }
}

/// 能一条条删的列表，札记的记忆页用它
struct DeletableEntryList: View {
    let text: String
    let failed: Bool
    let emptyHint: String
    /// 删一条，返回一句给人看的结果
    var onDelete: (MCPEntry) async -> String

    @State private var pending: MCPEntry?
    @State private var notice: String?

    var body: some View {
        let entries = failed ? [] : MCPEntryParser.parse(text)

        if let notice {
            Text(notice)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }

        if failed || (entries.isEmpty && !text.isEmpty) {
            MCPResultCard(text: text, failed: failed)
        } else if entries.isEmpty {
            Text(emptyHint)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            Text("共 \(entries.count) 条")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ForEach(entries) { entry in
                MCPEntryCard(entry: entry)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = entry.body.isEmpty ? entry.title : entry.body
                        } label: {
                            Label("拷贝", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            pending = entry
                        } label: {
                            Label("删掉这条", systemImage: Icon.trash)
                        }
                    }
            }
            .confirmationDialog("删掉这条记忆？",
                                isPresented: Binding(get: { pending != nil },
                                                     set: { if !$0 { pending = nil } }),
                                titleVisibility: .visible) {
                Button("删掉", role: .destructive) {
                    if let e = pending {
                        Task { notice = await onDelete(e) }
                    }
                    pending = nil
                }
                Button("算了", role: .cancel) { pending = nil }
            } message: {
                Text(pending?.displayTitle ?? "")
            }
        }
    }
}

/// 带关键词过滤的条目列表
struct FilteredEntryList: View {
    let text: String
    let failed: Bool
    var keyword: String = ""
    let emptyHint: String

    var body: some View {
        let all = failed ? [] : MCPEntryParser.parse(text)
        let entries = keyword.isEmpty ? all : all.filter {
            $0.title.localizedCaseInsensitiveContains(keyword)
            || $0.body.localizedCaseInsensitiveContains(keyword)
            || $0.tags.contains { t in t.localizedCaseInsensitiveContains(keyword) }
        }

        if failed || (all.isEmpty && !text.isEmpty) {
            MCPResultCard(text: text, failed: failed)
        } else if entries.isEmpty {
            Text(text.isEmpty ? emptyHint : (keyword.isEmpty ? emptyHint : "没找到"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            if !keyword.isEmpty {
                Text("找到 \(entries.count) 条")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                MCPEntryCard(entry: entry)
            }
        }
    }
}

/// 一段返回内容：能拆成条就一条条显示，拆不动就原样摆出来
struct MCPEntryList: View {
    let text: String
    let failed: Bool
    let emptyHint: String

    var body: some View {
        let entries = failed ? [] : MCPEntryParser.parse(text)
        if failed || entries.isEmpty {
            if text.isEmpty {
                Text(emptyHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                MCPResultCard(text: text, failed: failed)
            }
        } else {
            ForEach(entries) { entry in
                MCPEntryCard(entry: entry)
            }
        }
    }
}

/// 每个面板都要的那套：加载中、结果、刷新
@MainActor
final class PaneModel: ObservableObject {
    @Published var text = ""
    @Published var failed = false
    @Published var loading = false

    func run(_ app: AppState, tool: String, args: [String: Any] = [:]) async {
        loading = true
        let r = await app.callTool(tool, args: args)
        text = r.text
        failed = r.failed
        loading = false
    }
}

struct PaneScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, Layout.tabBarExpanded + 12)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - 日记

struct DiaryPane: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @StateObject private var model = PaneModel()
    @State private var author = "饼饼"
    @State private var content = ""
    @State private var mood = ""
    @State private var keyword = ""
    @AppStorage("diaryStacked") private var stacked = false

    var body: some View {
        PaneScroll {
            VStack(alignment: .leading, spacing: 10) {
                Text("写一篇").font(.system(size: 15, weight: .semibold))
                Picker("", selection: $author) {
                    Text("饼饼").tag("饼饼")
                    Text("阿晏").tag("阿晏")
                }
                .pickerStyle(.segmented)

                TextField("今天想写点什么…", text: $content, axis: .vertical)
                    .lineLimit(3...8)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))

                TextField("心情（可不填）", text: $mood)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))

                Button {
                    Task {
                        var args: [String: Any] = ["author": author, "content": content]
                        if !mood.isEmpty { args["mood"] = mood }
                        await model.run(app, tool: "add_diary", args: args)
                        content = ""; mood = ""
                        await model.run(app, tool: "get_diaries", args: ["limit": 20])
                    }
                } label: {
                    Text("写进日记本")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(app.settings.accentColor.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .disabled(content.isEmpty || model.loading)
            }
            .glassCard()

            HStack {
                Text("最近的日记").font(.system(size: 15, weight: .semibold))
                Spacer()
                // 一条条看是查东西用的，一叠叠看是回味用的
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { stacked.toggle() }
                } label: {
                    Image(systemName: stacked ? "list.bullet" : "square.stack")
                        .font(.system(size: 13))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
                Button {
                    Task { await model.run(app, tool: "get_diaries", args: ["limit": 50]) }
                } label: {
                    if model.loading { ProgressView() }
                    else { Image(systemName: Icon.refresh).foregroundStyle(app.settings.accentColor) }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Image(systemName: Icon.search)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted(scheme))
                TextField("搜日记里的词", text: $keyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                if !keyword.isEmpty {
                    Button { keyword = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.softFillDeep))

            if stacked {
                DiaryStackView(entries: model.failed ? [] : MCPEntryParser.parse(model.text))
            } else {
                FilteredEntryList(text: model.text, failed: model.failed,
                                  keyword: keyword,
                                  emptyHint: "还没有日记，写一篇吧")
            }
        }
        .task {
            if model.text.isEmpty {
                await model.run(app, tool: "get_diaries", args: ["limit": 20])
            }
        }
    }
}

// MARK: - 记忆

struct MemoryPane: View {
    @EnvironmentObject var app: AppState
    @StateObject private var model = PaneModel()
    @State private var author = "饼饼"
    @State private var content = ""
    @State private var tags = ""
    @State private var level = 3.0
    @State private var query = ""

    var body: some View {
        PaneScroll {
            VStack(alignment: .leading, spacing: 10) {
                Text("记一条").font(.system(size: 15, weight: .semibold))
                Picker("", selection: $author) {
                    Text("饼饼").tag("饼饼")
                    Text("阿晏").tag("阿晏")
                }
                .pickerStyle(.segmented)

                TextField("记忆内容…", text: $content, axis: .vertical)
                    .lineLimit(2...6)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))

                TextField("标签，逗号隔开", text: $tags)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))

                HStack {
                    Text("重要程度 \(Int(level))").font(.system(size: 13))
                    Slider(value: $level, in: 1...5, step: 1)
                }

                Button {
                    Task {
                        var args: [String: Any] = [
                            "content": content, "author": author, "level": Int(level)
                        ]
                        let list = tags.split(whereSeparator: { ",，、 ".contains($0) }).map(String.init)
                        if !list.isEmpty { args["tags"] = list }
                        await model.run(app, tool: "add_memory", args: args)
                        content = ""; tags = ""
                    }
                } label: {
                    Text("存进记忆库")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(app.settings.accentColor.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .disabled(content.isEmpty || model.loading)
            }
            .glassCard()

            HStack(spacing: 8) {
                TextField("搜关键词，留空看全部", text: $query)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
                Button {
                    Task {
                        if query.isEmpty {
                            await model.run(app, tool: "get_all_memories")
                        } else {
                            await model.run(app, tool: "search_memories",
                                            args: ["query": query, "limit": 30])
                        }
                    }
                } label: {
                    if model.loading {
                        ProgressView().frame(width: 44, height: 42)
                    } else {
                        Text("搜")
                            .frame(width: 44, height: 42)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(app.settings.accentColor.opacity(0.3)))
                    }
                }
                .buttonStyle(.plain)
            }

            DeletableEntryList(text: model.text, failed: model.failed,
                               emptyHint: "点上面的搜，或者留空看全部") { entry in
                let r = await app.deleteMemory(id: String(entry.id.prefix(8)))
                if !r.failed {
                    if query.isEmpty {
                        await model.run(app, tool: "get_all_memories")
                    } else {
                        await model.run(app, tool: "search_memories",
                                        args: ["query": query, "limit": 30])
                    }
                }
                return r.failed ? r.text : "删掉了"
            }
        }
        .task {
            if model.text.isEmpty {
                await model.run(app, tool: "get_all_memories")
            }
        }
    }
}

// MARK: - 经期

struct PeriodPane: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @StateObject private var model = PaneModel()

    @State private var month = Date()
    @State private var picked: Date?
    @State private var note = ""
    @State private var showSheet = false

    private let cal = Calendar.current

    private var df: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// 从 period_status 那段文字里把日期抠出来，好在日历上标出来
    private var info: (last: Date?, next: Date?, days: Int) {
        let text = model.text
        func date(after keyword: String) -> Date? {
            guard let r = text.range(of: keyword) else { return nil }
            let tail = String(text[r.upperBound...].prefix(24))
            guard let m = tail.range(of: #"\d{4}-\d{1,2}-\d{1,2}"#, options: .regularExpression)
            else { return nil }
            return df.date(from: String(tail[m]))
        }
        var days = 7
        if let r = text.range(of: #"平均经期\s*(\d+)"#, options: .regularExpression) {
            let n = String(text[r]).filter { $0.isNumber }
            days = Int(n) ?? 7
        }
        return (date(after: "上次"), date(after: "预测下次"), days)
    }

    var body: some View {
        PaneScroll {
            HStack {
                Text("当前状态").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    Task { await model.run(app, tool: "period_status") }
                } label: {
                    if model.loading { ProgressView() }
                    else { Image(systemName: Icon.refresh).foregroundStyle(app.settings.accentColor) }
                }
                .buttonStyle(.plain)
            }

            if !model.text.isEmpty {
                MCPResultCard(text: model.text, failed: model.failed)
            }

            // 状态用统一的那套颜色说话：粉是身体的事
            if let last = info.last {
                let days = Calendar.current.dateComponents(
                    [.day], from: Calendar.current.startOfDay(for: last),
                    to: Calendar.current.startOfDay(for: Date())).day ?? 0
                if days >= 0 && days < info.days {
                    StatusChip(tone: .body, text: "经期 · 第 \(days + 1) 天")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            calendar

            VStack(alignment: .leading, spacing: 8) {
                Text("点日历上的某一天，可以记下开始，或者写点当天的情况。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted(scheme))
                HStack(spacing: 14) {
                    legend(app.settings.accentColor.opacity(0.75), "这次")
                    legend(app.settings.accentColor.opacity(0.28), "预测")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { if model.text.isEmpty { await model.run(app, tool: "period_status") } }
        .sheet(isPresented: $showSheet) { daySheet }
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textMuted(scheme))
        }
    }

    // MARK: 日历

    private var calendar: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    month = cal.date(byAdding: .month, value: -1, to: month) ?? month
                } label: {
                    Image(systemName: "chevron.left").foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)

                Spacer()
                Text(monthTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer()

                Button {
                    month = cal.date(byAdding: .month, value: 1, to: month) ?? month
                } label: {
                    Image(systemName: "chevron.right").foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 0) {
                ForEach(["日","一","二","三","四","五","六"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .frame(maxWidth: .infinity)
                }
            }

            let days = monthDays
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
                ForEach(days.indices, id: \.self) { i in
                    if let day = days[i] {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
        }
        .glassCard()
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = cal.isDateInToday(day)
        let mark = marking(day)
        return Button {
            picked = day
            note = ""
            showSheet = true
        } label: {
            ZStack {
                if mark > 0 {
                    Circle()
                        .fill(app.settings.accentColor.opacity(mark == 1 ? 0.75 : 0.28))
                        .frame(width: 32, height: 32)
                }
                if isToday && mark == 0 {
                    Circle()
                        .strokeBorder(app.settings.accentColor.opacity(0.7), lineWidth: 1.2)
                        .frame(width: 32, height: 32)
                }
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 13, weight: isToday ? .semibold : .regular))
                    .foregroundStyle(mark == 1 ? Color.white : Theme.textMain(scheme))
            }
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 0 = 普通，1 = 这次经期，2 = 预测的下次
    private func marking(_ day: Date) -> Int {
        let i = info
        if let last = i.last,
           let end = cal.date(byAdding: .day, value: i.days - 1, to: last),
           day >= cal.startOfDay(for: last), day <= end { return 1 }
        if let next = i.next,
           let end = cal.date(byAdding: .day, value: i.days - 1, to: next),
           day >= cal.startOfDay(for: next), day <= end { return 2 }
        return 0
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: month)
    }

    /// 这个月的格子，前面用 nil 补齐到星期几
    private var monthDays: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: month))
        else { return [] }
        let leading = cal.component(.weekday, from: first) - 1
        var out: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            if let day = cal.date(byAdding: .day, value: d - 1, to: first) {
                out.append(day)
            }
        }
        return out
    }

    // MARK: 点开某一天

    private var daySheet: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(picked.map { dayTitle($0) } ?? "")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textMain(scheme))

                        Button {
                            guard let d = picked else { return }
                            Task {
                                await model.run(app, tool: "log_period",
                                                args: ["start": df.string(from: d)])
                                showSheet = false
                                await model.run(app, tool: "period_status")
                            }
                        } label: {
                            Text("这天开始的")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 14)
                                    .fill(app.settings.accentColor.opacity(0.32)))
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("写点当天的").font(.system(size: 14, weight: .medium))
                            TextField("身体状况、心情、他怎么照顾你的…", text: $note, axis: .vertical)
                                .lineLimit(3...6)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
                            Button {
                                guard let d = picked else { return }
                                Task {
                                    await model.run(app, tool: "add_period_note", args: [
                                        "date": df.string(from: d),
                                        "text": note,
                                        "author": app.settings.userName
                                    ])
                                    note = ""
                                    showSheet = false
                                }
                            } label: {
                                Text("写上去")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 14)
                                        .fill(app.settings.accentColor.opacity(0.32)))
                            }
                            .buttonStyle(.plain)
                            .disabled(note.isEmpty)
                        }
                        .glassCard()
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关上") { showSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func dayTitle(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: d)
    }
}

// MARK: - 心跳

/// 直接连你电脑上的 PulseEngine。
/// 电脑没开的时候，显示上一次拿到的读数，并注明是什么时候的。
struct PulsePane: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var snap: PulseAPI.Snapshot?
    @State private var offline = false
    @State private var loading = false
    @State private var error: String?
    @State private var history: [PulseAPI.HistoryPoint] = []

    private var base: String { app.settings.pulseBaseURL }

    var body: some View {
        PaneScroll {
            if base.isEmpty && !app.settings.localPulse {
                VStack(alignment: .leading, spacing: 8) {
                    Text("还没填心跳服务的地址").font(.system(size: 15, weight: .semibold))
                    Text("去「设置 → 后端服务」填上 PulseEngine 的地址，比如 http://你电脑的地址:8000")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .glassCard()
            } else {
                HStack {
                    Text("阿晏现在").font(.system(size: 15, weight: .semibold))
                    if offline {
                        Text("电脑没开")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange.opacity(0.25)))
                    }
                    Spacer()
                    Button { Task { await load() } } label: {
                        if loading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .buttonStyle(.plain)
                }

                if let snap {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        vital("心跳", "\(snap.heartRate)", "次/分", "heart.fill", .red)
                        vital("呼吸", "\(snap.breathing)", snap.breathDepth, "wind", .teal)
                        vital("体温", String(format: "%.1f", snap.temperature), "℃", "thermometer", .orange)
                        vital("疲劳", String(format: "%.0f%%", snap.fatigue * 100), "", "zzz", .purple)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        row("情绪", snap.emotion)
                        row("身体紧张", snap.nervous)
                        if !snap.chord.isEmpty { row("和弦", snap.chord) }
                        Text(offline
                             ? "这是 \(timeText(snap.fetchedAt)) 最后一次读到的"
                             : "更新于 \(timeText(snap.fetchedAt))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                    .glassCard()

                    if !history.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("今天的心率").font(.system(size: 14, weight: .semibold))
                            HeartRateChart(points: history, color: app.settings.accentColor)
                                .frame(height: 90)
                        }
                        .glassCard()
                    }
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("调一下").font(.system(size: 15, weight: .semibold))
                    Text("直接改电脑上那个引擎的状态")
                        .font(.caption).foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(PulseAPI.emotions, id: \.0) { key, label in
                            Button {
                                Task { await setEmotion(key) }
                            } label: {
                                Text(label)
                                    .font(.system(size: 13))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(RoundedRectangle(cornerRadius: 12)
                                        .fill(snap?.emotion.contains(label) == true
                                              ? app.settings.accentColor.opacity(0.35)
                                              : Theme.softFillDeep))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        Task { await spike() }
                    } label: {
                        Label("让心跳漏一拍", systemImage: "bolt.heart")
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
                    }
                    .buttonStyle(.plain)
                }
                .glassCard()
            }
        }
        .task { await load() }
    }

    private func vital(_ title: String, _ value: String, _ unit: String,
                       _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(color)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textMain(scheme))
            Text(unit.isEmpty ? title : "\(title) · \(unit)")
                .font(.system(size: 10)).foregroundStyle(Theme.textMuted(scheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.softFillDeep))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 13)).foregroundStyle(Theme.textMuted(scheme))
            Spacer()
            Text(v).font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
        }
    }

    private func timeText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
    }

    private func load() async {
        // 走本机那套的话，一次网络都不用发——公式在手机上现算
        if app.settings.localPulse {
            snap = LocalPulse.shared.snapshot()
            history = LocalPulse.shared.history()
            offline = false
            error = nil
            loading = false
            return
        }
        guard !base.isEmpty else { return }
        loading = true
        error = nil
        do {
            snap = try await PulseAPI.fetch(baseURL: base)
            offline = false
            history = (try? await PulseAPI.history(baseURL: base)) ?? []
        } catch {
            // 连不上就把上次的拿出来看
            if let cache = PulseAPI.cached {
                snap = cache
                offline = true
            } else {
                self.error = error.localizedDescription
            }
        }
        loading = false
    }

    private func setEmotion(_ key: String) async {
        if app.settings.localPulse {
            LocalPulse.shared.setEmotion(key, reason: "她在心跳页点的")
            await load()
            return
        }
        do {
            try await PulseAPI.setEmotion(base, emotion: key)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func spike() async {
        if app.settings.localPulse {
            LocalPulse.shared.spike(25)
            await load()
            return
        }
        do {
            try await PulseAPI.spike(base, magnitude: 25)
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

/// 心率折线，用 Path 手画的，不依赖图表库
struct HeartRateChart: View {
    let points: [PulseAPI.HistoryPoint]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let values = points.map { Double($0.hr) }
            let lo = (values.min() ?? 60) - 4
            let hi = (values.max() ?? 90) + 4
            let span = max(1, hi - lo)

            Path { path in
                for (i, v) in values.enumerated() {
                    let x = geo.size.width * (values.count <= 1 ? 0 : Double(i) / Double(values.count - 1))
                    let y = geo.size.height * (1 - (v - lo) / span)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - 状态（身体状况 + 给阿晏留话）

struct StatusPane: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @StateObject private var model = PaneModel()

    @State private var body_: EventideAPI.State?
    @State private var offline = false
    @State private var loading = false
    @State private var bodyError: String?

    private var base: String { app.settings.adminBaseURL }

    var body: some View {
        PaneScroll {

            // ---- 身体状况 ----
            HStack {
                Text("身体状况").font(.system(size: 15, weight: .semibold))
                if offline {
                    Text("电脑没开")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                }
                Spacer()
                Button { Task { await loadBody() } } label: {
                    if loading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.plain)
            }

            if base.isEmpty {
                Text("去「设置 → 后端服务」填上主动消息服务的地址，才能读到身体状况。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .glassCard()
            } else if let st = body_ {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        infoBox("周期", st.cycleName, st.cycleRemaining)
                        infoBox("事件", st.eventName, st.eventDuration ?? "—")
                    }

                    VStack(spacing: 10) {
                        ForEach(EventideAPI.State.valueOrder, id: \.key) { item in
                            let v = st.values[item.key] ?? 0
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.name)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.textSoft(scheme))
                                    Spacer()
                                    Text("\(Int(v))")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(app.settings.accentColor)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Theme.softFillDeep)
                                        Capsule()
                                            .fill(app.settings.accentColor.opacity(0.75))
                                            .frame(width: geo.size.width * min(1, max(0, v / 100)))
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                    }

                    if !st.settlementReason.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("上次结算")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.textMuted(scheme))
                                Text(st.resultName)
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.softFillDeep))
                                if st.peaked {
                                    Text("到过峰值")
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                                }
                            }
                            Text(st.settlementReason)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSoft(scheme))
                        }
                        .padding(.top, 2)
                    }

                    Text(offline
                         ? "这是 \(timeText(st.fetchedAt)) 最后一次读到的"
                         : "更新于 \(timeText(st.fetchedAt))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .glassCard()
            } else if let bodyError {
                Text(bodyError).font(.footnote).foregroundStyle(.red).glassCard()
            }

            HStack(spacing: 10) {
                Button {
                    Task { await model.run(app, tool: "get_today_review") }
                } label: {
                    Text("今日回顾")
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.softFillDeep))
                }
                .buttonStyle(.plain)

            }

            if !model.text.isEmpty {
                MCPResultCard(text: model.text, failed: model.failed)
            }
        }
        .task { await loadBody() }
    }

    private func infoBox(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.textMuted(scheme))
            Text(value).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(app.settings.accentColor)
            Text(sub).font(.system(size: 10)).foregroundStyle(Theme.textMuted(scheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.softFillDeep))
    }

    private func timeText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
    }

    private func loadBody() async {
        guard !base.isEmpty else { return }
        loading = true
        bodyError = nil
        do {
            body_ = try await EventideAPI.fetch(baseURL: base)
            offline = false
        } catch {
            if let cache = EventideAPI.cached {
                body_ = cache
                offline = true
            } else {
                bodyError = error.localizedDescription
            }
        }
        loading = false
    }
}

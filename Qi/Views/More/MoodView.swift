import SwiftUI

/// 心情。最上面是在一起多久，然后是纪念日、给他留的话、今天的心情。
///
/// 纪念日存在小屋的记忆库里（打上「纪念日」标签），
/// 所以他也看得见、也能自己添加和删除，不是只存在你手机上的一份。
struct MoodView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var raw = ""
    @State private var failed = false
    @State private var loading = false
    @State private var notice: String?

    @State private var message = ""
    @State private var mood = ""

    @State private var addingDay = false
    @State private var newDayText = ""
    @State private var newDayDate = Date()
    @State private var pendingDelete: MCPEntry?

    /// 纪念日那一栏是不是摊开的。日子多起来之后整张卡会很长，
    /// 底下的「留句话」「今天的心情」就得一路划过去才够得着。
    @State private var daysOpen = true
    @State private var daySearch = ""

    private let tag = "纪念日"

    private var days: [MCPEntry] {
        guard !failed else { return [] }
        return MCPEntryParser.parse(raw)
    }

    /// 搜索框里打了字就只留对得上的。标题、正文、日期时间**一起找**——
    /// 「七夕」和「8/29」她都可能拿来搜。
    private var shownDays: [MCPEntry] {
        let q = daySearch.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return days }
        return days.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(q)
                || $0.body.localizedCaseInsensitiveContains(q)
                || $0.stamp.contains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                together
                anniversaries
                messageCard
                moodCard

                if let notice {
                    Text(notice)
                        .font(.app(12))
                        .foregroundStyle(app.settings.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, Layout.tabBarExpanded + 20)
        }
        .navigationTitle("心情")
        .navigationBarTitleDisplayMode(.inline)
        .task { if raw.isEmpty { await load() } }
        .sheet(isPresented: $addingDay) { addSheet }
        .confirmationDialog("删掉这个纪念日？", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删掉", role: .destructive) {
                if let e = pendingDelete { Task { await remove(e) } }
                pendingDelete = nil
            }
            Button("算了", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(pendingDelete?.displayTitle ?? "")
        }
    }

    // MARK: 在一起多久

    private var together: some View {
        VStack(spacing: 6) {
            Text("在一起")
                .font(.app(12))
                .foregroundStyle(Theme.textMuted(scheme))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(daysTogether)")
                    .font(.app(44, weight: .light, design: .rounded))
                    .foregroundStyle(app.settings.accentColor)
                Text("天")
                    .font(.app(15))
                    .foregroundStyle(Theme.textSoft(scheme))
            }

            DatePicker("从这天算起", selection: Binding(
                get: { app.settings.togetherSince },
                set: { app.settings.togetherSince = $0 }
            ), displayedComponents: .date)
            .font(.app(12))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private var daysTogether: Int {
        let cal = Calendar.current
        let from = cal.startOfDay(for: app.settings.togetherSince)
        let to = cal.startOfDay(for: Date())
        return max(0, (cal.dateComponents([.day], from: from, to: to).day ?? 0) + 1)
    }

    // MARK: 纪念日

    private var anniversaries: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // 抽屉的把手。整行都能点——只点得中那个小箭头的话太难按了。
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { daysOpen.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text("纪念日").heading(15)
                            .foregroundStyle(Theme.textMain(scheme))
                        if !days.isEmpty {
                            Text("\(days.count)")
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                        Image(systemName: "chevron.right")
                            .font(.app(10, weight: .semibold))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .rotationEffect(.degrees(daysOpen ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                if loading { ProgressView().scaleEffect(0.7) }
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: Icon.refresh)
                        .font(.app(13))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
                Button {
                    newDayText = ""
                    newDayDate = Date()
                    addingDay = true
                } label: {
                    Image(systemName: Icon.add)
                        .font(.app(15))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
            }

            if !daysOpen {
                // 收起来的时候不摆一整片空白，也不摆搜索框——
                // 搜索框在收起的抽屉上是够不着结果的
                EmptyView()
            } else if days.isEmpty {
                Text(loading ? "在读…" : "还没记过什么日子。点右上角加一个。")
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
            } else {
                // 搜索框。条数少的时候不摆——十条以内一眼扫得完，
                // 摆一个框反而占地方。
                if days.count > 8 {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                        TextField("搜日子", text: $daySearch)
                            .font(.app(13))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !daySearch.isEmpty {
                            Button { daySearch = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.app(12))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.softFillDeep))
                }

                if shownDays.isEmpty {
                    Text("没有对得上的。")
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                }

                ForEach(shownDays) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(app.settings.accentColor.opacity(0.6))
                            .frame(width: 7, height: 7)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.displayTitle)
                                .font(.app(14))
                                .foregroundStyle(Theme.textMain(scheme))
                            // 谁记的 + **什么时候记的**，精确到分。
                            //
                            // 她定的：「每一条写上记得的准确时间，
                            // 防止像今天这样被塞入很多条。」
                            // 只写到天的话，同一下塞进来的十几条看着都一样。
                            if !entry.author.isEmpty || !entry.stamp.isEmpty {
                                Text([entry.stamp,
                                      entry.author.isEmpty ? "" : entry.author + " 记的"]
                                        .filter { !$0.isEmpty }
                                        .joined(separator: "　"))
                                    .font(.app(10))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = entry.displayTitle
                        } label: {
                            Label("拷贝", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            pendingDelete = entry
                        } label: {
                            Label("删掉", systemImage: Icon.trash)
                        }
                    }
                }

                Text("记录存于记忆库，模型可读取，亦可自行增删。")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 留言 / 心情

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("留句话").heading(15)
                .foregroundStyle(Theme.textMain(scheme))
            Text("将在下次唤醒时优先显示")
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))
            TextField("想说的话…", text: $message, axis: .vertical)
                .lineLimit(2...5)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
            actionButton("留下", enabled: !message.isEmpty) {
                let r = await app.callTool("leave_message", args: ["text": message])
                notice = r.failed ? r.text : "留下了"
                if !r.failed { message = "" }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var moodCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今天的心情").heading(15)
                .foregroundStyle(Theme.textMain(scheme))
            TextField("还行、有点累、很开心…", text: $mood)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
            actionButton("记下", enabled: !mood.isEmpty) {
                let r = await app.callTool("set_mood",
                                           args: ["who": app.settings.userName, "mood": mood])
                notice = r.failed ? r.text : "记下了"
                if !r.failed { mood = "" }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func actionButton(_ title: String, enabled: Bool,
                              run: @escaping () async -> Void) -> some View {
        Button {
            Task { await run() }
        } label: {
            Text(title)
                .font(.app(14))
                .foregroundStyle(Theme.textMain(scheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 14)
                    .fill(app.settings.accentColor.opacity(enabled ? 0.32 : 0.12)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: 加一个纪念日

    private var addSheet: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                VStack(alignment: .leading, spacing: 14) {
                    DatePicker("哪一天", selection: $newDayDate, displayedComponents: .date)
                    TextField("这天发生了什么", text: $newDayText, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("加个纪念日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { addingDay = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("记下") {
                        Task { await addDay() }
                    }
                    .fontWeight(.semibold)
                    .disabled(newDayText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: 数据

    private func load() async {
        loading = true
        // ⚠️ **这儿以前传的是 `query: "纪念日"`，那是全文检索，不是筛标签。**
        //
        // 于是任何一条**提到**「纪念日」的记忆都会跑到这张卡上来，
        // 而且检索是带语义的，库越大捞回来的越多——
        // 她说「一开始只有七夕这一条，不知道为什么多了很多条」，就是这个。
        //
        // `search_memories` 本来就收 `tags`，走的是集合求交，只认真打了标签的。
        let r = await app.callTool("search_memories", args: ["tags": [tag], "limit": 200])
        raw = r.text
        failed = r.failed
        loading = false
    }

    private func addDay() async {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        let content = "\(f.string(from: newDayDate))　\(newDayText)"
        let r = await app.callTool("add_memory", args: [
            "content": content,
            "tags": [tag],
            "level": 5,
            "author": app.settings.userName
        ])
        notice = r.failed ? r.text : "记下了"
        addingDay = false
        newDayText = ""
        if !r.failed { await load() }
    }

    private func remove(_ entry: MCPEntry) async {
        let r = await app.deleteMemory(id: String(entry.id.prefix(8)))
        notice = r.failed ? "没删掉：\(r.text)" : "删掉了"
        if !r.failed { await load() }
    }
}

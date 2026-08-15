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

    private let tag = "纪念日"

    private var days: [MCPEntry] {
        guard !failed else { return [] }
        return MCPEntryParser.parse(raw)
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
                        .font(.system(size: 12))
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
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted(scheme))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(daysTogether)")
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .foregroundStyle(app.settings.accentColor)
                Text("天")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSoft(scheme))
            }

            DatePicker("从这天算起", selection: Binding(
                get: { app.settings.togetherSince },
                set: { app.settings.togetherSince = $0 }
            ), displayedComponents: .date)
            .font(.system(size: 12))
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
                Text("纪念日").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer()
                if loading { ProgressView().scaleEffect(0.7) }
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: Icon.refresh)
                        .font(.system(size: 13))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
                Button {
                    newDayText = ""
                    newDayDate = Date()
                    addingDay = true
                } label: {
                    Image(systemName: Icon.add)
                        .font(.system(size: 15))
                        .foregroundStyle(app.settings.accentColor)
                }
                .buttonStyle(.plain)
            }

            if days.isEmpty {
                Text(loading ? "在读…" : "还没记过什么日子。点右上角加一个。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted(scheme))
            } else {
                ForEach(days) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(app.settings.accentColor.opacity(0.6))
                            .frame(width: 7, height: 7)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.displayTitle)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textMain(scheme))
                            if !entry.author.isEmpty {
                                Text(entry.author + " 记的")
                                    .font(.system(size: 10))
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

                Text("这些存在小屋的记忆里，他也看得见，也能自己加、自己删。")
                    .font(.system(size: 10))
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
            Text("留句话").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textMain(scheme))
            Text("他下次醒来第一眼会看到")
                .font(.system(size: 11))
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
            Text("今天的心情").font(.system(size: 15, weight: .semibold))
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
                .font(.system(size: 14))
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
        let r = await app.callTool("search_memories", args: ["query": tag, "limit": 60])
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

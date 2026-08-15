import SwiftUI
import UniformTypeIdentifiers

/// 记忆库。
///
/// 原来这套跑在她电脑上（memory-mcp.js + caddy 反代到公网），
/// 电脑一关他就失忆。这一页是把那台服务搬进手机之后的入口：
/// 从电脑导一次，之后就再也不用开电脑了。
struct MemoryLibraryView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = MemoryStore.shared

    @State private var importing = false
    @State private var report: String?
    @State private var exportURL: URL?
    @State private var confirmWipe = false

    var body: some View {
        ZStack {
            WallpaperBackground()

            ScrollView {
                VStack(spacing: 18) {
                    switchCard
                    contentCard
                    importCard
                    if !store.isEmpty { browseCard }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
        }
        .navigationTitle("记忆库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .failure(let e): report = "选文件失败：\(e.localizedDescription)"
            case .success(let urls): report = store.importFiles(urls).text
            }
        }
        .sheet(item: Binding(
            get: { exportURL.map { Folder(url: $0) } },
            set: { _ in exportURL = nil }
        )) { f in
            ShareSheet(items: [f.url])
        }
        .alert("导入结果", isPresented: Binding(
            get: { report != nil }, set: { if !$0 { report = nil } }
        )) {
            Button("好") { report = nil }
        } message: {
            Text(report ?? "")
        }
        .confirmationDialog("确定要清空本机记忆库吗？", isPresented: $confirmWipe,
                            titleVisibility: .visible) {
            Button("清空", role: .destructive) { store.wipe() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("记忆、日记、经期、存档对话全都会删掉，删了找不回来。电脑上那份不受影响。")
        }
    }

    // MARK: 总开关

    private var switchCard: some View {
        SettingsCard(title: "本机记忆库") {
            Toggle(isOn: $app.settings.localMemory) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("用本机这份")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text("不走 MCP、不用开电脑、不用挂 Tailscale")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .tint(app.settings.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            SettingsNote(app.settings.localMemory
                ? "记忆库那 28 个工具（wake_up、add_memory、checkpoint、end_of_day…）现在是 App 内置的，名字和参数跟电脑上那套一模一样。\n\n⚠️ 建议去「设置 → MCP」把「小屋」那台关掉——两边都开着的话，同一件事他手上有两套工具，会来回打架。"
                : "关着的时候他还是走小屋那台 MCP，也就是还得开着电脑。")

            SettingsDivider()

            Toggle(isOn: $app.settings.localPulse) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("心跳也在本机算")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text("不用再开 PulseEngine")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .tint(app.settings.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            SettingsNote("""
            把 PulseEngine 那几条公式原样搬进来了：心率的分时段基线、情绪偏移、天气偏移、突刺的指数衰减、那条慢正弦抖动——常数一个没改，所以算出来的数跟电脑上是一样的。

            那套东西本来就是**每次请求现算**的纯公式，不是靠一秒一次 tick 累积出来的，所以少了那个循环什么都不缺。心率历史照样一分钟记一条，存在手机上。

            开着之后「札记 → 心跳」和他手上的 get_pulse_status 都走本机，一次网络都不发。
            """)
        }
    }

    // MARK: 现在有什么

    private var contentCard: some View {
        SettingsCard(title: "现在存了什么") {
            row("记忆", "\(store.memories.count) 条")
            SettingsDivider()
            row("日记", "\(store.diaries.count) 篇")
            SettingsDivider()
            row("存档对话", "\(store.transcripts.count) 份")
            SettingsDivider()
            row("经期", "\(store.periods.records.count) 次")
            SettingsDivider()
            row("身份认知", store.identity.isEmpty ? "空" : "\(store.identity.count) 字")
            SettingsDivider()
            row("当前状态", store.currentState.text.isEmpty ? "空" : "有")
            SettingsDivider()
            row("上次聊到哪", store.checkpoint?.text.isEmpty == false ? "有" : "空")
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        SettingsRowLabel(title: title, value: value)
    }

    // MARK: 搬家

    private var importCard: some View {
        SettingsCard(title: "搬家") {
            Button { importing = true } label: {
                SettingsRowLabel(title: "从电脑导进来", icon: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
            SettingsDivider()

            Button {
                exportURL = store.exportBundle()
            } label: {
                SettingsRowLabel(title: "导出一份", icon: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .disabled(store.isEmpty)
            .opacity(store.isEmpty ? 0.45 : 1)
            SettingsDivider()

            Button { confirmWipe = true } label: {
                SettingsRowLabel(title: "清空本机记忆库", icon: "trash", tint: .red)
            }
            .buttonStyle(.plain)

            SettingsNote("""
            导入的时候，把电脑上 dylan-heartbeat 文件夹里这些 json **一次全选**（可以多选）：

            memories.json　diaries.json　identity.json
            current_state.json　state_history.json
            live_checkpoint.json　partner_message.json
            periods.json　moods.json　emotional_events.json
            memories_log.json

            还有 transcripts 文件夹里那些散文件，也一起选上——它们没有固定名字，是按内容认的。

            按文件名一个个对上，认不出来的会告诉你是哪个。同名的直接覆盖，所以电脑那边改过之后可以随时再导一次。
            """)
        }
    }

    // MARK: 翻一翻

    private var browseCard: some View {
        SettingsCard(title: "翻一翻") {
            NavigationLink {
                MemoryListView()
            } label: {
                SettingsRowLabel(title: "记忆", value: "\(store.memories.count)", chevron: true)
            }
            .buttonStyle(.plain)
            SettingsDivider()
            NavigationLink {
                MemoryDiaryListView()
            } label: {
                SettingsRowLabel(title: "日记", value: "\(store.diaries.count)", chevron: true)
            }
            .buttonStyle(.plain)
            SettingsDivider()
            NavigationLink {
                MemoryTranscriptListView()
            } label: {
                SettingsRowLabel(title: "存档对话", value: "\(store.transcripts.count)", chevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    private struct Folder: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }
}

// MARK: - 记忆列表

struct MemoryListView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = MemoryStore.shared
    @State private var search = ""

    private var list: [MemoryItem] {
        guard !search.isEmpty else { return store.memories }
        return store.memories.filter {
            $0.content.localizedCaseInsensitiveContains(search)
            || $0.tags.contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        ZStack {
            WallpaperBackground()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(list) { mem in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(String(repeating: "★", count: max(1, min(5, mem.level))))
                                    .font(.system(size: 11))
                                    .foregroundStyle(app.settings.accentColor)
                                Text(mem.author)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textMuted(scheme))
                                Spacer()
                                Text(String(mem.created_at.prefix(10)))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            Text(mem.content)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textMain(scheme))
                                // 不加这一条，长文会被上层的 stack 压成一行截断
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                            if !mem.tags.isEmpty {
                                Text("#" + mem.tags.joined(separator: " #"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            ForEach(mem.annotations ?? [], id: \.self) { a in
                                Text("⤷ \(a.author)：把「\(a.original)」改成「\(a.correction)」")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red.opacity(0.8))
                            }
                        }
                        .padding(13)
                        .glassBackground(radius: 16, strength: app.settings.glassOpacity)
                        .contextMenu {
                            Button(role: .destructive) {
                                if let i = store.memoryIndex(mem.id) {
                                    store.memories.remove(at: i)
                                    store.saveMemories()
                                }
                            } label: {
                                Label("删掉", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
        }
        .searchable(text: $search, prompt: "搜记忆")
        .navigationTitle("记忆")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 日记列表

struct MemoryDiaryListView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = MemoryStore.shared

    var body: some View {
        ZStack {
            WallpaperBackground()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.diaries) { d in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(d.author + (d.mood ?? ""))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(app.settings.accentColor)
                                Spacer()
                                Text(String(d.created_at.prefix(10)))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            Text(d.content)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textMain(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                            ForEach(d.annotations ?? [], id: \.self) { a in
                                Text("⤷ \(a.author)：把「\(a.original)」改成「\(a.correction)」")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red.opacity(0.8))
                            }
                        }
                        .padding(13)
                        .glassBackground(radius: 16, strength: app.settings.glassOpacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
        }
        .navigationTitle("日记")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 存档对话

struct MemoryTranscriptListView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = MemoryStore.shared

    var body: some View {
        ZStack {
            WallpaperBackground()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.transcripts) { t in
                        NavigationLink {
                            MemoryTranscriptReader(id: t.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(t.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Theme.textMain(scheme))
                                        .lineLimit(1)
                                    Spacer(minLength: 6)
                                    Text("\(t.count) 条")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.textMuted(scheme))
                                }
                                Text(t.summary ?? "还没写摘要")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textMuted(scheme))
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassBackground(radius: 16, strength: app.settings.glassOpacity)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.deleteTranscript(t.id)
                            } label: {
                                Label("删掉这份存档", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
        }
        .navigationTitle("存档对话")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 翻一份存档的正文。几千条消息，用 LazyVStack 一点点出。
struct MemoryTranscriptReader: View {

    let id: String
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var file: TranscriptFile?

    var body: some View {
        ZStack {
            WallpaperBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array((file?.msgs ?? []).enumerated()), id: \.offset) { i, msg in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(i)  \(msg.role)")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textMuted(scheme))
                            Text(msg.text)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textMain(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassBackground(radius: 14, strength: app.settings.glassOpacity * 0.85)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
        }
        .navigationTitle(file?.title ?? "存档")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { file = MemoryStore.shared.transcript(id) }
    }
}

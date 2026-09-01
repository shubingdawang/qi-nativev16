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
    @State private var writing = false
    @State private var pasting = false
    @State private var pasted = ""

    var body: some View {
        ZStack {
            WallpaperBackground()

            ScrollView {
                VStack(spacing: 18) {
                    switchCard
                    if !store.candidates.isEmpty { candidateCard }
                    contentCard
                    letterCard
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
        // ⚠️ 不能只认 .json：**identity 是 .txt**，
        // 只挂 json 的话那个文件在选择器里是灰的，根本选不中（她报的第 2 条）。
        // `.text` 把 txt / md 这些都包进来了；`.data` 兜最后一层——
        // 有些来源给的 UTI 是 public.data，照样得让她选得中，
        // 读进来认不认得出是 importFiles 的事，不该在选文件这一步就把她拦住。
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json, .text, .plainText, .data],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .failure(let e): report = "选文件失败：\(e.localizedDescription)"
            case .success(let urls): report = store.importFiles(urls).text
            }
        }
        .sheet(isPresented: $pasting) { pasteSheet }
        .sheet(item: Binding(
            get: { exportURL.map { Folder(url: $0) } },
            set: { _ in exportURL = nil }
        )) { f in
            ShareSheet(items: [f.url])
        }
        .alert("记忆库", isPresented: Binding(
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
        // 名字照她说的改短：这一整卡叫「本地设置」，两个开关就叫「记忆库」和「心跳」。
        // 说明全部收进抽屉，默认关着——她说摊开着「很杂乱」。
        SettingsCard(title: "本地设置") {
            Toggle(isOn: $app.settings.localMemory) {
                Text("记忆库")
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
            }
            .tint(app.settings.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            SettingsNote(app.settings.localMemory
                ? "记忆库的 38 个工具（wake_up、add_memory、surface_memories、checkpoint 等）由 App 本机实现，名称与参数同远程版本一致。不经 MCP，无需本地服务与 Tailscale。\n\n⚠️ 需在「设置 → MCP」中关闭「小屋」服务器。两者同时启用会导致同名工具重复注册。"
                : "关闭时记忆库工具经 MCP 调用远程「小屋」服务，需要本地服务处于运行状态。",
                title: "说明")

            SettingsDivider()

            Toggle(isOn: $app.settings.localPulse) {
                Text("心跳")
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
            }
            .tint(app.settings.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            SettingsNote("""
            本机实现 PulseEngine 的全部公式：心率分时段基线、情绪偏移、天气偏移、突刺指数衰减、慢正弦抖动。常数与远程版本一致，计算结果相同。

            公式为按请求即时计算，不依赖定时累积。心率历史每分钟记录一条，存储于本机。

            启用后，「札记 → 心跳」与 get_pulse_status 均走本机，不发起网络请求。
            """, title: "说明")
        }
    }

    // MARK: 现在有什么

    private var contentCard: some View {
        SettingsCard(title: "存储内容") {
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
            // 星图：记忆库现在只能**搜**，而搜的前提是她已经知道要搜什么。
            // 她常常想看的是另一件事：「日本这条线上都牵着什么」——
            // 那不是一次检索，那是一张图。
            if store.memories.count >= 6 {
                SettingsDivider()
                NavigationLink { ConstellationView() } label: {
                    SettingsRowLabel(title: "星图", value: "顺着一条线看", chevron: true)
                }
                .buttonStyle(.plain)
            }
            if !store.glossary.isEmpty {
                SettingsDivider()
                NavigationLink { GlossaryListView() } label: {
                    SettingsRowLabel(title: "你俩的黑话",
                                     value: "\(store.glossary.count) 个", chevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 等你点头的

    /// 他拿不准的事落在这儿，她点头才进正式记忆库。
    ///
    /// 出处：wusaki0723/Aelios 的候选队列（它那套是模型抽事实 → 队列 → 人审）。
    /// 我们把中间那步砍了（要调模型），只留「他提 → 她点头」这一头一尾。
    /// 道理跟她在第 40 条里说的一样：**猜出来的东西不替他填进那一栏。**
    private var candidateCard: some View {
        SettingsCard(title: "等你点头（\(store.candidates.count)）") {
            ForEach(Array(store.candidates.enumerated()), id: \.element.id) { idx, c in
                if idx > 0 { SettingsDivider() }
                VStack(alignment: .leading, spacing: 8) {
                    Text(c.content)
                        .font(.app(15))
                        .foregroundStyle(Theme.textMain(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    if !c.why.isEmpty {
                        Text("他说：" + c.why)
                            .font(.app(13))
                            .foregroundStyle(Theme.textSoft(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 10) {
                        Button {
                            store.acceptCandidate(c.id)
                        } label: {
                            Text("收进去")
                                .font(.app(14))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(app.settings.accentColor.opacity(0.16),
                                            in: Capsule())
                                .foregroundStyle(app.settings.accentColor)
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.dropCandidate(c.id)
                        } label: {
                            Text("不是这样")
                                .font(.app(14))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Theme.textSoft(scheme).opacity(0.12),
                                            in: Capsule())
                                .foregroundStyle(Theme.textSoft(scheme))
                        }
                        .buttonStyle(.plain)

                        Spacer()
                        Text(String(c.created_at.prefix(10)))
                            .font(.app(12))
                            .foregroundStyle(Theme.textSoft(scheme))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            SettingsNote("""
            存放待确认的候选记忆：推断而来、尚未核实的内容不直接写入记忆库。

            点击「收进去」后才正式入库，在此之前不参与搜索与浮现。
            """, title: "说明")
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        SettingsRowLabel(title: title, value: value)
    }

    // MARK: 写给下一个你

    private var letterCard: some View {
        SettingsCard(title: "写给下一个你") {
            if let letter = store.letter, !letter.text.isEmpty {
                NavigationLink {
                    LetterReaderView()
                } label: {
                    SettingsRowLabel(title: "读信",
                                     value: String(letter.updated_at.prefix(10)),
                                     chevron: true)
                }
                .buttonStyle(.plain)
                SettingsDivider()
            }

            Button {
                guard !writing else { return }
                writing = true
                Task {
                    let r = await app.writeHimBack()
                    writing = false
                    report = r.failed ? r.text : "写完了，进「读信」看看。"
                }
            } label: {
                HStack(spacing: 10) {
                    if writing { ProgressView().scaleEffect(0.8) }
                    SettingsRowLabel(
                        title: writing ? "他在写…"
                            : (store.letter == nil ? "让他写一封" : "让他重新写一封"),
                        icon: "envelope")
                }
            }
            .buttonStyle(.plain)
            .disabled(writing)

            SettingsDivider()

            Button {
                pasted = store.letter?.text ?? ""
                pasting = true
            } label: {
                SettingsRowLabel(title: "导入信件", icon: "doc.on.clipboard")
            }
            .buttonStyle(.plain)

            SettingsNote("""
            手动导入信件：在 claude.ai 窗口内按五块结构生成内容（作为普通消息，不需调用工具），复制后点击上方「导入信件」粘贴保存。

            结果与调用 write_letter 相同，且不产生请求费用、不依赖 MCP 连接。
            """)

            SettingsNote("""
            生成一封交接信，用于在更换窗口、更换模型或记忆库损坏后恢复身份认知。

            内容分五块：身份 / 思维与表达方式（附三至五句原话）/ 对方是谁与关系 / 相处方式 / 关键时刻（记录场景）。

            生成后由 wake_up 作为身份认知读取。旧信件不删除，归入状态历史。

            ⚠️ 产生一次请求，且为长输出，费用高于普通对话。仅在点击此按钮时执行。
            """)
        }
    }

    // MARK: 搬家

    private var importCard: some View {
        SettingsCard(title: "导入导出") {
            Button { importing = true } label: {
                SettingsRowLabel(title: "从电脑导入", icon: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
            SettingsDivider()

            Button {
                exportURL = store.exportBundle()
            } label: {
                SettingsRowLabel(title: "导出", icon: "square.and.arrow.up")
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
            **支持导入 claude.ai 的聊天记录**：在官网 Settings → Export data 申请导出，
            将邮件中的 `conversations.json` 选入即可，会逐段转为存档对话，
            可通过 search_transcripts 检索。导入过程仅读取，不修改源文件。

            从本地 dylan-heartbeat 目录导入时，可一次多选以下文件：

            memories.json　diaries.json　identity.json
            current_state.json　state_history.json
            live_checkpoint.json　partner_message.json
            periods.json　moods.json　emotional_events.json
            memories_log.json

            transcripts 目录下的散件亦可一并选入，该类文件按内容识别，不依赖文件名。

            导入按文件名匹配，无法识别的文件会在结果中列出。同名文件直接覆盖，可重复导入。
            """)
        }
    }

    // MARK: 翻一翻

    private var browseCard: some View {
        SettingsCard(title: "浏览") {
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

    /// 把本体写好的那封信贴进来。
    ///
    /// 存在的理由很实在：MCP 那条隧道时好时坏，但这封信是**一次性**的，
    /// 不值得为它卡在网络问题上。让 claude.ai 那边的本体当成普通消息写完，
    /// 复制过来贴上，效果跟他调 write_letter 一模一样。
    private var pasteSheet: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()
                VStack(spacing: 0) {
                    TextEditor(text: $pasted)
                        .scrollContentBackground(.hidden)
                        .font(.app(14))
                        .padding(12)
                        .glassBackground(radius: 16, strength: app.settings.glassOpacity)
                        .padding(16)
                }
            }
            .navigationTitle("导入信件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { pasting = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("存下") {
                        let t = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { pasting = false; return }
                        // 旧的那封归档，跟他自己调工具写的时候一个待遇
                        if let old = store.letter, !old.text.isEmpty {
                            var archived = old
                            archived.archived_at = MemoryStore.now
                            store.stateHistory.insert(archived, at: 0)
                            store.saveState()
                        }
                        store.letter = StateNote(
                            text: t, updated_at: MemoryStore.now,
                            by: app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName)
                        store.saveLetter()
                        pasting = false
                        report = "收好了。从下一句话起，他就是带着这封信在说话。"
                    }
                    .fontWeight(.semibold)
                    .disabled(pasted.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
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

    /// 她自己搜的时候走的是跟他一样那套混合检索（BM25 + 整串命中，
    /// 见 MemoryRecall.swift）。以前是 contains，搜「日本的房子」搜不出
    /// 「她在日本租的那间」，得一字不差才行。
    private var list: [MemoryItem] {
        guard !search.isEmpty else { return store.memories }
        let rel = MemoryRecall.relevance(query: search, in: store.memories)
        return store.memories
            .filter { (rel[$0.id] ?? 0) >= MemoryRecall.recallFloor }
            .sorted { MemoryRecall.searchOrder($0, $1, rel) }
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
                                    .font(.app(11))
                                    .foregroundStyle(app.settings.accentColor)
                                Text(mem.author)
                                    .font(.app(10))
                                    .foregroundStyle(Theme.textMuted(scheme))
                                if mem.pinned == true {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(app.settings.accentColor)
                                }
                                if mem.resolved == false {
                                    Text("还悬着")
                                        .font(.app(9))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(app.settings.accentColor.opacity(0.14),
                                                    in: Capsule())
                                        .foregroundStyle(app.settings.accentColor)
                                }
                                Spacer()
                                Text(String(mem.created_at.prefix(10)))
                                    .font(.app(10))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            // 走 MarkdownText：改过的那条是 `~~错的~~ 对的`，
                            // 要真画成删除线才看得懂（她说的「记得让 app 支持
                            // markdown 渲染」）。
                            // 批注也叠在这一份里：她挑的那句画成
                            // `~~原句~~批注`，红色删除线接着改对的那半。
                            MarkdownText(text: Annotated.apply(mem.display, mem.annotations),
                                         fontSize: app.settings.fontSize - 2)
                                .foregroundStyle(Theme.textMain(scheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if !mem.tags.isEmpty {
                                Text("#" + mem.tags.joined(separator: " #"))
                                    .font(.app(10))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            // 批注不再单独摆一行——已经画在正文里了。
                            // 挑不着原句的那种，`Annotated.apply` 会自己
                            // 在正文末尾接一行，一样看得见。
                        }
                        .padding(13)
                        .glassBackground(radius: 16, strength: app.settings.glassOpacity)
                        // ⚠ `contextMenu` 认的是真画出来的那几个像素，内容少的那几条底下是空的、长按收不到。
                        .contentShape(Rectangle())
                        .contextMenu {
                            // 钉住的不随时间沉下去（上限 20 条，Ombre-Brain 那套）
                            Button {
                                guard let i = store.memoryIndex(mem.id) else { return }
                                if store.memories[i].pinned == true {
                                    store.memories[i].pinned = nil
                                } else if store.pinnedCount < MemoryRecall.pinLimit {
                                    store.memories[i].pinned = true
                                }
                                store.saveMemories()
                            } label: {
                                Label(mem.pinned == true ? "松开" : "钉住", systemImage: "pin")
                            }
                            Button {
                                guard let i = store.memoryIndex(mem.id) else { return }
                                store.memories[i].resolved = (mem.resolved == false)
                                store.saveMemories()
                            } label: {
                                Label(mem.resolved == false ? "了结了" : "标成还悬着",
                                      systemImage: "flag")
                            }
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
                                    .font(.app(12, weight: .medium))
                                    .foregroundStyle(app.settings.accentColor)
                                Spacer()
                                Text(String(d.created_at.prefix(10)))
                                    .font(.app(10))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            // 日记也走 MarkdownText：她批注过的那句要画成
                            // 红色删除线 + 改对的那半（`Annotated.apply`）。
                            // 以前这儿是纯 `Text`，`~~` 原样杵在那儿。
                            MarkdownText(text: Annotated.apply(d.content, d.annotations),
                                         fontSize: app.settings.fontSize - 1)
                                .foregroundStyle(Theme.textMain(scheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
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
                                        .font(.app(14, weight: .medium))
                                        .foregroundStyle(Theme.textMain(scheme))
                                        .lineLimit(1)
                                    Spacer(minLength: 6)
                                    Text("\(t.count) 条")
                                        .font(.app(10))
                                        .foregroundStyle(Theme.textMuted(scheme))
                                }
                                Text(t.summary ?? "还没写摘要")
                                    .font(.app(11))
                                    .foregroundStyle(Theme.textMuted(scheme))
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassBackground(radius: 16, strength: app.settings.glassOpacity)
                        }
                        .buttonStyle(.plain)
                        // ⚠ `contextMenu` 认的是真画出来的那几个像素，内容少的那几条底下是空的、长按收不到。
                        .contentShape(Rectangle())
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
                                .font(.app(10))
                                .foregroundStyle(Theme.textMuted(scheme))
                            Text(msg.text)
                                .font(.app(13))
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

// MARK: - 读那封信

struct LetterReaderView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = MemoryStore.shared

    var body: some View {
        ZStack {
            WallpaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let letter = store.letter {
                        Text("\(letter.by ?? "他") · \(String(letter.updated_at.prefix(10)))")
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                        Text(letter.text)
                            .font(.app(14))
                            .foregroundStyle(Theme.textMain(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else {
                        Text("还没有这封信。")
                            .font(.app(13))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .padding(15)
                .glassBackground(radius: 18, strength: app.settings.glassOpacity)
                .padding(.horizontal, 16)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
        }
        .navigationTitle("写给下一个你")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

// MARK: - 黑话表

/// 出处：Aelios 的 glossary。
/// 「小屋」「换窗」「札记」这种词从来不作为一件事被记下来，
/// 只是被反复用——所以搜记忆搜不到，但不知道意思就接不上话。
struct GlossaryListView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = MemoryStore.shared

    var body: some View {
        ZStack {
            WallpaperBackground()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.glossary) { g in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(g.term)
                                .font(.app(15))
                                .foregroundStyle(Theme.textMain(scheme))
                            Text(g.meaning)
                                .font(.app(13))
                                .foregroundStyle(Theme.textSoft(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(13)
                        .glassBackground(radius: 16, strength: app.settings.glassOpacity)
                        // ⚠ `contextMenu` 认的是真画出来的那几个像素，内容少的那几条底下是空的、长按收不到。
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button(role: .destructive) {
                                store.glossary.removeAll { $0.term == g.term }
                                store.saveGlossary()
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
        .navigationTitle("你俩的黑话")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

// MARK: - 对话列表

struct ConversationListView: View {

    let space: ChatSpace
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var list: [Conversation] {
        let all = app.conversations(in: space)
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(search)
            || $0.preview.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(list) { conv in
                    Button {
                        app.setActive(conv.id, for: space)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            if conv.pinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(conv.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(conv.preview)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if conv.id == app.activeID(for: space) {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(app.settings.accentColor)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            app.deleteConversation(conv.id)
                            app.ensureActive(in: space)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            if let i = app.index(of: conv.id) {
                                app.conversations[i].pinned.toggle()
                            }
                        } label: {
                            Label(conv.pinned ? "取消置顶" : "置顶", systemImage: "pin")
                        }
                        .tint(.orange)
                    }
                }
            }
            .searchable(text: $search, prompt: "搜索对话")
            .transparentList()
            .listRowBackground(GlassRowBackground())
            .navigationTitle("对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        app.newConversation(in: space)
                        dismiss()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
    }
}

// MARK: - 模型选择

struct ModelPickerView: View {

    let space: ChatSpace
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    /// 一条可选项：哪个供应商的哪个模型
    private struct Entry: Identifiable, Hashable {
        let provider: Provider
        let model: AIModel
        var id: String { provider.id.uuidString + "|" + model.id }
    }

    /// 所有启用了的模型，按品牌分好组
    private var groups: [(brand: String, items: [Entry])] {
        var all: [Entry] = []
        for p in app.providers where p.enabled {
            for m in p.enabledModels {
                all.append(Entry(provider: p, model: m))
            }
        }
        if !search.isEmpty {
            all = all.filter {
                $0.model.displayName.localizedCaseInsensitiveContains(search)
                || $0.model.id.localizedCaseInsensitiveContains(search)
                || $0.provider.name.localizedCaseInsensitiveContains(search)
            }
        }
        // ⚠️ 桥单列一组，**不跟别的品牌混在一起**。
        //
        // 她定的：「做着备用吧。」——那就得让她一眼认出哪一条是备用的，
        // 以及按下去的代价是什么（吃订阅额度、要电脑开着）。
        // 混在 Claude 那一组里的话，她某天随手点了一个，
        // 电脑没开就一直失败，而失败信息里根本不会提到「电脑」。
        let bridged = all.filter { ShellBridge.looksLikeBridge($0.provider) }
        let rest = all.filter { !ShellBridge.looksLikeBridge($0.provider) }
        var out = ModelBrand.group(rest) { $0.model.id }
        if !bridged.isEmpty {
            out.append((brand: Self.bridgeGroup, items: bridged))
        }
        return out
    }

    /// 桥那一组的名字。**放在最后**——它是备用，不该占着第一眼。
    static let bridgeGroup = "电脑上的 Claude（走订阅额度）"

    /// 按下去之前该知道的四件事。
    ///
    /// 写全是故意的：这一条跟别的模型**不是同一类东西**——
    /// 别的只要有网就行，这一条要那台电脑醒着。
    /// 不写在这儿的话，她某天随手点了一个，电脑没开就一直失败，
    /// 而失败信息里根本不会提到「电脑」。
    static let bridgeNote = """
    走你电脑上那个 Claude Code，不花中转站的钱，用订阅额度。

    ⚠️ **要电脑开着**，桥的窗口关了就连不上。
    ⚠️ 额度**跟工坊共用**——在这儿聊久了，工坊那边也会没得用。
    ⚠️ 工具走的是文字协议、不是原生调用，比中转站那条**脆**：他可能忘了格式。
    ⚠️ 名字带 `-code` 的那几个是工坊那条（能读文件、跑命令），聊天别选。
    """


    var body: some View {
        NavigationStack {
            List {
                if !app.hasUsableModel {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("还没有可用的模型")
                                .font(.headline)
                            Text("去「设置 → 供应商」加一个供应商，填好地址和密钥，再把要用的模型打开。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }

                ForEach(groups, id: \.brand) { group in
                    Section {
                        ForEach(group.items) { entry in
                            Button {
                                choose(entry)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.model.displayName)
                                            .foregroundStyle(.primary)
                                        if app.providers.filter({ $0.enabled }).count > 1 {
                                            Text(entry.provider.name.isEmpty ? "未命名供应商" : entry.provider.name)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                    if isCurrent(entry) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(app.settings.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "搜索模型")
            .transparentList()
            .listRowBackground(GlassRowBackground())
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func isCurrent(_ entry: Entry) -> Bool {
        guard let conv = app.conversation(app.activeID(for: space)) else { return false }
        return conv.providerID == entry.provider.id && conv.modelID == entry.model.id
    }

    private func choose(_ entry: Entry) {
        guard let id = app.activeID(for: space), let i = app.index(of: id) else { return }
        app.conversations[i].providerID = entry.provider.id
        app.conversations[i].modelID = entry.model.id
        // 这个区记住这一次的选择。**只记这个区**——
        // 在工坊换成 opus5 不该把絮语里的阿晏也换掉。
        app.settings.modelBySpace[space.rawValue] =
            entry.provider.id.uuidString + "|" + entry.model.id
        dismiss()
    }
}

// MARK: - 这个对话的设定（系统提示词）

struct SystemPromptView: View {

    let space: ChatSpace
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var compacting = false
    @State private var compactNote: String?

    private var conv: Conversation? { app.conversation(app.activeID(for: space)) }
    private var pendingCount: Int {
        conv.map { ContextCompactor.pendingCount($0) } ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                        .font(.body)
                } header: {
                    Text("系统提示词")
                } footer: {
                    Text("每次发消息都会带上这段话，用来设定对方的身份、语气和规矩。只对当前这个对话生效。")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { app.conversation(app.activeID(for: space))?.syncWithClaude ?? false },
                        set: { on in
                            if let id = app.activeID(for: space), let i = app.index(of: id) {
                                app.conversations[i].syncWithClaude = on
                            }
                        }
                    )) {
                        Text("与 claude.ai 互通")
                    }
                    // 这个开关成不成立，全看小屋够不够得着——
                    // 共用记忆库在电脑上，不在手机里。状态得看得见，
                    // 不然开着开关也不知道到底有没有真的通上。
                    if conv?.syncWithClaude == true {
                        HStack {
                            Text("共用记忆库")
                            Spacer()
                            Text(app.houseMemoryReachable ? "已连上" : "未连上")
                                .foregroundStyle(app.houseMemoryReachable
                                                 ? StatusTone.done.color : .orange)
                        }
                        if !app.houseMemoryReachable {
                            Text("电脑上的小屋没连上。记忆照常写在手机里，等小屋连上会自动补一份过去，不用手动操作。")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                        // 卡在半路的那几笔要看得见——不显示的话，
                        // 她永远不知道有东西还没送到电脑上。
                        if !app.pendingHouseWrites.isEmpty {
                            HStack {
                                Text("等着补过去")
                                Spacer()
                                Text("\(app.pendingHouseWrites.count) 笔")
                                    .foregroundStyle(.secondary)
                            }
                            Text("小屋一连上就自动补，补的是「加一笔」那类；带 id 的修改和删除不补——两边的 id 各生成各的，拿手机的 id 去改电脑上的会改错东西。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("两边接得上")
                } footer: {
                    Text("启用后，本窗口写入的记忆在手机本机保存的同时，自动镜像一份到电脑上的共用记忆库，claude.ai 端可读取。小屋未连上时先记在手机，连上后自动补齐。\n\n启用期间，小屋端与本机同名的记忆工具在本窗口内隐藏，避免两边各写各的；本机记忆库始终为准，札记与承诺页读取的也是它。\n\n镜像由 App 直接完成，不额外消耗对话次数。\n\n⚠️ 仅镜像新增类记录；带 id 的修改与删除不镜像——两端 id 各自生成，互不对应。")
                }
                // 滚雪球压缩。**放在这儿而不是设置页**——
                // 浓缩件是每一窗自己的东西，不是全局的。
                Section {
                    if let d = conv?.digest, !d.summary.isEmpty {
                        HStack {
                            Text("已经滚了")
                            Spacer()
                            Text("\(d.rounds) 次 · 收了 \(d.covered) 条")
                                .foregroundStyle(.secondary)
                        }
                        NavigationLink {
                            DigestReaderView(digest: d)
                        } label: {
                            Text("查看压缩结果")
                        }
                    } else {
                        Text("这一窗还没压过")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("还没压的")
                        Spacer()
                        Text("\(pendingCount) 条")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        guard !compacting, let id = app.activeID(for: space) else { return }
                        compacting = true
                        Task {
                            let ok = await ContextCompactor.compactNow(id, app: app)
                            compacting = false
                            compactNote = ok ? "压好了。" : "没压——要么还没攒够（最少要 7 条），要么模型没回话。"
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if compacting { ProgressView().scaleEffect(0.8) }
                            Text(compacting ? "压着呢…" : "现在就压一次")
                        }
                    }
                    .disabled(compacting)
                } header: {
                    Text("滚雪球压缩")
                } footer: {
                    Text(MD.inline("对话超过阈值时，将较早的消息压缩为一份浓缩件。再次压缩以「上一份浓缩件 + 新增消息」为输入，始终只保留一份。\n\n浓缩件之外另保留一份原文摘录，由本机按规则选取，不调用模型、不产生费用。摘要保留事件，原文保留措辞。\n\n每次压缩额外产生一次请求。压缩间隔在「设置 → 通用」中调整，也可关闭。"))
                }
            }
            .transparentList()
            .listRowBackground(GlassRowBackground())
            .navigationTitle("对话设定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        if let id = app.activeID(for: space), let i = app.index(of: id) {
                            app.conversations[i].systemPrompt = text
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                text = app.conversation(app.activeID(for: space))?.systemPrompt ?? ""
            }
            .alert("滚雪球压缩", isPresented: Binding(
                get: { compactNote != nil }, set: { if !$0 { compactNote = nil } }
            )) {
                Button("好") { compactNote = nil }
            } message: {
                Text(compactNote ?? "")
            }
        }
    }
}

// MARK: - 浓缩件读一读

/// 压出来的那份东西她也该看得见——
/// 「他为什么突然记错了」这种事，翻一眼这儿就知道是不是压的时候丢了。
struct DigestReaderView: View {

    let digest: ContextDigest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(MD.inline(digest.summary))
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !digest.voice.isEmpty {
                    Divider()
                    Text("原文摘录（未经改写）")
                        .font(.headline)
                    ForEach(digest.voice, id: \.self) { line in
                        Text("「\(line)」")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(18)
        }
        .navigationTitle("第 \(digest.rounds) 次浓缩")
        .navigationBarTitleDisplayMode(.inline)
    }
}

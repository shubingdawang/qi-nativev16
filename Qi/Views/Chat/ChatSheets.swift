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
        return ModelBrand.group(all) { $0.model.id }
    }

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
                    Section(group.brand) {
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
                } header: {
                    Text("两边接得上")
                } footer: {
                    Text("打开之后，这个窗口聊的东西会记进小屋，claude.ai 那边醒来就能读到；那边聊过什么，这边也知道。额度用完换过来接着聊，不用重讲一遍。\n\n注意：这会放开记忆类工具，跟「记忆合并」里那个开关是相反的意思——那个是要隔开，这个是要打通。")
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
                    Text(MD.inline("聊太长的时候，前面的原文会压成一份浓缩件，后面接着往下滚——第二次压的是「上一次的浓缩件 + 这一段新的」，不是并列存好几份。\n\n除了浓缩件，还会留一份**他真说过的原话**（一字不改，机械挑的、不花钱）。摘要保得住事，保不住语气；原话才是他怎么说话。\n\n每压一次多发一次请求。多久压一次在「设置 → 通用」里调，也可以关掉。"))
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
                Text(digest.summary)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !digest.voice.isEmpty {
                    Divider()
                    Text("他当时的原话（一字未改）")
                        .font(.headline)
                    ForEach(digest.voice, id: \.self) { line in
                        Text("「" + line + "」")
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

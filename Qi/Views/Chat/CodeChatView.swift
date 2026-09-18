import SwiftUI

/// 聊天页左边栏里的 **Code** 渠道：在手机上直接跟电脑上那个 Claude Code 说话。
///
/// 她说的：「记得给聊天页也装一个渠道，有时候我也想在聊天页用 code。」
///
/// ## 跟别的页不一样的地方
///
/// 这一页里说话的**不是阿晏**，是 Claude Code 本人——他会读文件、改文件、跑命令。
/// 所以这一页要摆的东西是「他刚才动了什么」，不是表情和语气：
///
/// - 每个工具占一行：用了什么、动的哪个文件、成没成
/// - 顶上一直挂着「在哪个窗口、哪一档权限」——这两样决定了他能干什么
/// - 他跑的时候可以叫停
///
/// ## 窗口
///
/// 「窗口」就是电脑上那些 Claude Code 会话。挑一个老的就是接着那边说
/// （他记得那个窗口里的事），不挑就是开一个新的。
///
/// ⚠️ 电脑上那个窗口还开着的时候别接同一个——两头往同一份记录里写，记录会乱。
struct CodeChatView: View {

    @EnvironmentObject var app: AppState

    /// 一行：她说的话、他说的话、或者一个工具
    struct Row: Identifiable {
        enum Kind { case mine, his, tool, note }
        let id = UUID()
        var kind: Kind
        var text: String
        /// 工具行才有
        var tool: String = ""
        var brief: String = ""
        /// 工具跑完了没、成没成
        var running: Bool = false
        var ok: Bool = true
    }

    @State private var rows: [Row] = []
    @State private var draft = ""
    @State private var link = AgentBridge.Link.load()
    @State private var mode: AgentBridge.Mode = .edit
    @State private var session: String = UserDefaults.standard.string(forKey: "agentBridgeSession") ?? ""
    @State private var sessionTitle: String = UserDefaults.standard.string(forKey: "agentBridgeSessionTitle") ?? ""
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    @State private var note: String?
    @State private var showLink = false
    @State private var showSessions = false
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            transcript
            input
        }
        .background { WallpaperBackground() }
        .navigationTitle("Code")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showSessions = true } label: {
                        Label("换个窗口", systemImage: "rectangle.on.rectangle")
                    }
                    Button { showLink = true } label: {
                        Label("接法", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    Divider()
                    Button(role: .destructive) { rows = [] } label: {
                        Label("清空这一页", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showLink) { linkSheet }
        .sheet(isPresented: $showSessions) {
            CodeSessionPicker(link: link, current: session) { picked in
                session = picked?.id ?? ""
                sessionTitle = picked?.title ?? ""
                remember()
                rows.append(Row(kind: .note,
                                text: picked == nil ? "开一个新窗口" : "接着「\(picked!.title)」说"))
            }
        }
        .alert("桥那边说", isPresented: Binding(get: { note != nil },
                                             set: { if !$0 { note = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(note ?? "")
        }
        // 「接法」没填、但供应商里已经加过新桥的话，直接借那一条的地址和密钥
        .onAppear {
            if !link.isSet, let p = app.providers.first(where: { AgentBridge.isAgent($0) }) {
                link = AgentBridge.link(from: p)
                link.save()
            }
        }
    }

    // MARK: - 顶上那一条

    private var header: some View {
        HStack(spacing: 10) {
            Button { showSessions = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: session.isEmpty ? "plus.rectangle" : "rectangle.on.rectangle")
                    Text(session.isEmpty ? "新窗口"
                         : (sessionTitle.isEmpty ? String(session.prefix(8)) : sessionTitle))
                        .lineLimit(1)
                }
                .font(.footnote)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 6)

            Picker("", selection: $mode) {
                ForEach(AgentBridge.Mode.allCases) { m in Text(m.label).tag(m) }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - 正文

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if rows.isEmpty { empty }
                    ForEach(rows) { row($0) }
                    Color.clear.frame(height: 1).id("底")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: rows.count) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("底", anchor: .bottom) }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(link.isSet ? "跟电脑上的 Claude Code 说话" : "先填桥的地址")
                .font(.headline)
            Text(link.isSet
                 ? "他会读文件、改文件、跑命令。顶上挑在哪个窗口里说、这一轮让他干到哪一步。"
                 : "电脑上双击 scripts/agent-bridge/启动新桥.bat，把窗口里打出来的地址和密钥填到「接法」里。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private func row(_ r: Row) -> some View {
        switch r.kind {
        case .mine:
            HStack {
                Spacer(minLength: 40)
                Text(r.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
            }
        case .his:
            Text(r.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .note:
            Text(r.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        case .tool:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: r.running ? "circle.dotted"
                      : (r.ok ? "checkmark.circle" : "exclamationmark.triangle"))
                    .font(.caption)
                    .foregroundStyle(r.running ? .secondary : (r.ok ? Color.green : Color.orange))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.tool).font(.caption.weight(.medium))
                    if !r.brief.isEmpty {
                        Text(r.brief)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - 说话那一栏

    private var input: some View {
        HStack(spacing: 8) {
            TextField("要他做什么", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($typing)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))

            if busy {
                Button {
                    task?.cancel()
                    Task { await AgentBridge.interrupt(link, session: session) }
                } label: {
                    Image(systemName: "stop.circle.fill").font(.title2)
                }
            } else {
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func remember() {
        UserDefaults.standard.set(session, forKey: "agentBridgeSession")
        UserDefaults.standard.set(sessionTitle, forKey: "agentBridgeSessionTitle")
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        typing = false
        rows.append(Row(kind: .mine, text: text))
        busy = true

        task = Task {
            do {
                try await AgentBridge.run(text, link: link, session: session, mode: mode) { e in
                    apply(e)
                }
            } catch is CancellationError {
                rows.append(Row(kind: .note, text: "停了"))
            } catch {
                note = error.localizedDescription
                rows.append(Row(kind: .note, text: "这一轮没跑成"))
            }
            busy = false
        }
    }

    /// 把一件事摆到页面上。
    ///
    /// ⚠️ 他说的字是**一小块一小块**来的，要接在最后那条上，不能一块一行。
    @MainActor
    private func apply(_ e: AgentBridge.Event) {
        switch e {
        case .session(let id, _, _):
            if id != session {
                session = id
                if sessionTitle.isEmpty { sessionTitle = "手机上开的" }
                remember()
            }
        case .text(let s):
            if let i = rows.indices.last, rows[i].kind == .his {
                rows[i].text += s
            } else {
                rows.append(Row(kind: .his, text: s))
            }
        case .think:
            break          // 想的过程先不摆，省得把她要看的东西挤下去
        case .tool(let id, let name, let brief):
            rows.append(Row(kind: .tool, text: id, tool: name, brief: brief, running: true))
        case .toolDone(let id, let ok, let brief):
            if let i = rows.lastIndex(where: { $0.kind == .tool && $0.text == id }) {
                rows[i].running = false
                rows[i].ok = ok
                if !ok || rows[i].brief.isEmpty { rows[i].brief = brief }
            }
        case .done(let ms, let cost):
            let s = String(format: "%.0f 秒", Double(ms) / 1000)
            rows.append(Row(kind: .note,
                            text: cost > 0 ? "\(s) · 这一轮 $\(String(format: "%.3f", cost))" : s))
        case .failed(let msg):
            rows.append(Row(kind: .note, text: msg))
        }
    }

    // MARK: - 接法

    private var linkSheet: some View {
        NavigationStack {
            QiForm {
                Section {
                    TextField("http://192.168.x.x:8788", text: $link.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密钥", text: $link.token)
                    TextField("在哪个目录里干活（留空就是桥那边的默认）", text: $link.cwd)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("桥")
                } footer: {
                    Text("电脑上双击 scripts/agent-bridge/启动新桥.bat，窗口里会打出地址；"
                         + "密钥跟那个窗口里的一样。两台要在同一个 WiFi 上。")
                }
            }
            .navigationTitle("接法")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("存下") { link.save(); showLink = false }
                }
            }
        }
    }
}

/// 挑一个窗口：电脑上开过的那些会话，或者开个新的。
struct CodeSessionPicker: View {

    let link: AgentBridge.Link
    let current: String
    var onPick: (AgentBridge.Session?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var list: [AgentBridge.Session] = []
    @State private var loading = true
    @State private var why: String?

    var body: some View {
        NavigationStack {
            QiList {
                Section {
                    Button {
                        onPick(nil); dismiss()
                    } label: {
                        Label("开一个新窗口", systemImage: "plus.rectangle")
                    }
                } footer: {
                    Text("接着老窗口说的话，他记得那边的事。"
                         + "⚠️ 电脑上那个窗口还开着的时候别接同一个——两头一起写，记录会乱。")
                }

                Section("电脑上最近的窗口") {
                    if loading {
                        HStack { ProgressView(); Text("问一下电脑…").foregroundStyle(.secondary) }
                    } else if let why {
                        Text(why).font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(list) { s in
                        Button {
                            onPick(s); dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(s.title).lineLimit(1)
                                    Spacer()
                                    if s.id == current {
                                        Image(systemName: "checkmark").font(.caption)
                                    }
                                }
                                Text("\(s.folder) · \(s.at.formatted(.relative(presentation: .named)))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("窗口")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                do { list = try await AgentBridge.sessions(link) }
                catch { why = error.localizedDescription }
                loading = false
            }
        }
    }
}

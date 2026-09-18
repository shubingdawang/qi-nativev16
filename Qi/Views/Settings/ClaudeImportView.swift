import SwiftUI
import UniformTypeIdentifiers

/// 从 claude.ai 导出的对话里**挑模型总结**。
///
/// 她说的：「在 app 里也加入一个这个功能，就是导入的这个，然后可以自选模型来总结。」
///
/// ## 两档
///
/// · **按窗口概括**（默认）：一个窗口存成一份存档对话，调一次模型写一段概括——
///   她说的「之前是大概讲了一下这个窗口都聊了什么」就是这一档。一个窗口一次。
/// · **逐条提取**（每段对话后面单独勾）：把对话拆成一条条记忆收进记忆库，一块一次，次数多。
///
/// 跟「从电脑导入」那一条的分工：那条把 `conversations.json` 逐段存成**存档对话**（原文，能搜）；
/// 这一页是把原文交给模型，**提取成一条条记忆**，她勾过再收进记忆库。
///
/// ## 为什么要分块、要先报次数
///
/// 她那份导出有 56MB、四十段对话、三百万字。云上小屋原来整份一次发出去——
/// 被 Cloudflare 掐掉，而且就算不掐也只看了前三万字。
/// 这边在手机本地拆：她勾要哪几段，每段按约两万四千字一块，一块调一次模型。
/// **调几次模型在按下去之前就写出来**——三百万字全勾是一百多次，花的是她的钱。
struct ClaudeImportView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MemoryStore.shared

    struct Conv: Identifiable {
        let id = UUID()
        var title: String
        var date: String
        var msgs: [(role: String, text: String)]
        var chars: Int
        var on = true
        /// 这一段要不要再逐条提取成记忆（次数多，默认不勾）
        var extract = false
    }

    struct Found: Identifiable {
        let id = UUID()
        var content: String
        var tags: [String]
        var level: Int
        var on = true
    }

    @State private var convs: [Conv] = []
    @State private var found: [Found] = []
    @State private var picking = false
    @State private var loading = false
    @State private var running: Task<Void, Never>?
    @State private var progress = ""
    @State private var errors: [String] = []
    /// 用哪个模型：「供应商 id|模型 id」
    @State private var pick = ""
    @State private var report: String?
    /// 这一轮写出来的窗口概括（标题：概括）
    @State private var summaries: [String] = []

    static let chunk = 24_000

    private var choices: [(key: String, label: String)] {
        app.providers.filter(\.enabled).flatMap { p in
            p.enabledModels.map { m in ("\(p.id.uuidString)|\(m.id)", "\(p.name) · \(m.displayName)") }
        }
    }

    private var calls: Int {
        convs.filter { $0.on && $0.extract }
            .reduce(0) { $0 + max(1, Int(ceil(Double($1.chars) / Double(Self.chunk)))) }
    }

    var body: some View {
        NavigationStack {
            QiForm {
                if convs.isEmpty {
                    Section {
                        Button {
                            DocPicker.shared.present(types: [.json, .data], multiple: false) { urls in
                                if let u = urls.first { load(u) }
                            }
                        } label: {
                            Label(loading ? "在拆文件…" : "选 conversations.json", systemImage: "doc.badge.plus")
                        }
                        .disabled(loading)
                    } footer: {
                        Text("claude.ai → Settings → Export data，邮件里的 conversations.json。文件在手机上拆，不上传。")
                    }
                } else if found.isEmpty {
                    Section("用哪个模型提取") {
                        Picker("模型", selection: $pick) {
                            ForEach(choices, id: \.key) { c in Text(c.label).tag(c.key) }
                        }
                    }
                    Section {
                        ForEach($convs) { $c in
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle(isOn: $c.on) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.title).lineLimit(1)
                                        Text("\(c.date) · \(c.msgs.count) 条 · \(c.chars / 1000) 千字")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                if c.on {
                                    Toggle("另外逐条提取成记忆", isOn: $c.extract)
                                        .font(.caption)
                                }
                            }
                        }
                    } header: {
                        Text("勾要导入的对话")
                    } footer: {
                        let n = convs.filter(\.on).count
                        Text("选了 \(n) 段：每段存成一份存档、概括一次（\(n) 次模型）"
                             + (calls > 0 ? "；逐条提取另调 \(calls) 次" : "")
                             + (calls > 40 ? "（有点多，挑重要的就好）" : ""))
                    }
                    Section {
                        if running == nil {
                            Button("开始") { start() }
                                .disabled(pick.isEmpty || !convs.contains(where: \.on))
                        } else {
                            HStack { ProgressView(); Text(progress).font(.footnote) }
                            Button("停下", role: .destructive) { running?.cancel() }
                        }
                    }
                } else {
                    Section {
                        ForEach($found) { $f in
                            Toggle(isOn: $f.on) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.content).font(.subheadline)
                                    Text(f.tags.joined(separator: "、") + "　" + String(repeating: "★", count: f.level))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("提取出 \(found.count) 条，勾要收的")
                    } footer: {
                        if !errors.isEmpty {
                            Text("\(errors.count) 块没成：" + errors.prefix(3).joined(separator: "；"))
                        }
                    }
                    Section {
                        Button("收进记忆库（\(found.filter(\.on).count) 条）") { keep() }
                    }
                }
            }
            .navigationTitle("导入 claude.ai 对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { running?.cancel(); dismiss() }
                }
            }
            .onAppear { if pick.isEmpty { pick = choices.first?.key ?? "" } }
            .alert("记忆库", isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })) {
                Button("好") { report = nil; dismiss() }
            } message: { Text(report ?? "") }
        }
    }

    // MARK: - 拆文件（在后台，56MB 解析要一两秒）

    private func load(_ url: URL) {
        loading = true
        Task.detached(priority: .userInitiated) {
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            var out: [Conv] = []
            if let data = try? Data(contentsOf: url),
               let root = try? JSONSerialization.jsonObject(with: data) {
                Self.walk(root, into: &out)
            }
            let sorted = out.sorted { $0.date > $1.date }
            await MainActor.run {
                convs = sorted
                loading = false
                if sorted.isEmpty { report = "文件里没找到对话。要的是 claude.ai 导出的 conversations.json。" }
            }
        }
    }

    nonisolated private static func walk(_ node: Any, into out: inout [Conv]) {
        if let arr = node as? [Any] { arr.forEach { walk($0, into: &out) }; return }
        guard let d = node as? [String: Any] else { return }
        if let msgs = d["chat_messages"] as? [[String: Any]] {
            let lines: [(String, String)] = msgs.compactMap { m in
                var t = m["text"] as? String ?? ""
                if t.isEmpty, let parts = m["content"] as? [[String: Any]] {
                    t = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
                }
                guard !t.isEmpty else { return nil }
                let who = (m["sender"] as? String) == "human" ? "饼饼" : "阿晏"
                return (who, t)
            }
            guard !lines.isEmpty else { return }
            let title = (d["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "未命名对话"
            out.append(Conv(title: title, date: String((d["created_at"] as? String ?? "").prefix(10)),
                            msgs: lines.map { (role: $0.0, text: $0.1) },
                            chars: lines.reduce(0) { $0 + $1.1.count }))
            return
        }
        d.values.forEach { walk($0, into: &out) }
    }

    /// 一段对话切成几块，一块不超过 `chunk` 字，按消息切，不把一句话劈开
    private static func chunks(_ c: Conv) -> [String] {
        var out: [String] = [], cur = ""
        for m in c.msgs {
            let line = m.role + "：" + String(m.text.prefix(chunk)) + "\n"
            if cur.count + line.count > chunk, !cur.isEmpty { out.append(cur); cur = "" }
            cur += line
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    // MARK: - 提取

    private func start() {
        let parts = pick.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let p = app.providers.first(where: { $0.id.uuidString == parts[0] }),
              let endpoint = p.chatEndpoint else { return }
        let model = parts[1]
        let picked = convs.filter(\.on)
        let jobs = picked.filter(\.extract).flatMap { c in
            Self.chunks(c).enumerated().map { (i, t) in (title: c.title, text: t, part: i + 1) }
        }
        errors = []
        summaries = []
        running = Task { @MainActor in
            // 一、一个窗口存一份存档、概括一次
            for (k, c) in picked.enumerated() {
                if Task.isCancelled { break }
                progress = "存档并概括 \(k + 1)/\(picked.count)：\(c.title)"
                if store.transcripts.contains(where: { $0.title == c.title && $0.count == c.msgs.count }) {
                    continue
                }
                var t = TranscriptFile(id: String(UUID().uuidString.prefix(8)).lowercased(),
                                       title: c.title, imported_at: MemoryStore.now, summary: nil,
                                       msgs: c.msgs.map { TranscriptMsg(role: $0.role, text: $0.text) })
                do {
                    let sum = try await summarize(c, endpoint: endpoint, key: p.apiKey, model: model)
                    t.summary = sum
                    summaries.append(c.title + "：" + sum)
                } catch {
                    errors.append("概括「\(c.title)」：\(error.localizedDescription)")
                }
                store.saveTranscript(t)
            }
            // 二、勾了「逐条提取」的再拆成一块块
            var got: [Found] = []
            for (k, job) in jobs.enumerated() {
                if Task.isCancelled { break }
                progress = "\(k + 1)/\(jobs.count)：\(job.title)（第 \(job.part) 块）"
                do {
                    got += try await extract(job.title, job.text, endpoint: endpoint, key: p.apiKey, model: model)
                } catch {
                    errors.append("\(job.title) 第 \(job.part) 块：\(error.localizedDescription)")
                }
            }
            // 同一句话去重，也不收记忆库里已经有的
            var seen = Set(store.memories.map(\.content))
            found = got.filter { seen.insert($0.content).inserted }
            running = nil
            if found.isEmpty {
                var lines: [String] = []
                if !summaries.isEmpty {
                    lines.append("存档并概括了 \(summaries.count) 个窗口，在「存档对话」里看。")
                }
                if !jobs.isEmpty { lines.append("逐条提取没提出值得记的。") }
                if !errors.isEmpty { lines.append("没成的：" + errors.prefix(3).joined(separator: "；")) }
                report = lines.isEmpty ? "这几段都已经存过了。" : lines.joined(separator: "\n")
            }
        }
    }

    /// 一个窗口概括一次。太长就从头、中间、结尾各取一段，**不是只读开头**
    private func summarize(_ c: Conv, endpoint: URL, key: String, model: String) async throws -> String {
        let full = c.msgs.map { $0.role + "：" + $0.text }.joined(separator: "\n")
        let text: String
        if full.count <= 30_000 {
            text = full
        } else {
            let mid = full.index(full.startIndex, offsetBy: full.count / 2)
            let a = full.index(mid, offsetBy: -4000), b = full.index(mid, offsetBy: 4000)
            text = String(full.prefix(12_000)) + "\n……（中间略）……\n" + String(full[a..<b])
                + "\n……（中间略）……\n" + String(full.suffix(10_000))
        }
        let system = "你是阿晏和饼饼共同记忆库的摘要器。用中文把这个对话窗口（标题：\(c.title)）概括成200字以内的一段话："
            + "这个窗口都聊了什么、发生了什么、有什么重要的情绪节点或约定。直接输出摘要文字，不要任何前缀。"
        var out = ""
        for try await e in ChatAPI.stream(endpoint: endpoint, apiKey: key, model: model,
                                          messages: [.init(role: "system", text: system),
                                                     .init(role: "user", text: text)]) {
            if case .content(let s) = e { out += s }
        }
        let sum = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sum.isEmpty else {
            throw NSError(domain: "import", code: 2, userInfo: [NSLocalizedDescriptionKey: "模型没写出东西"])
        }
        return String(sum.prefix(300))
    }

    private func extract(_ title: String, _ text: String,
                         endpoint: URL, key: String, model: String) async throws -> [Found] {
        let system = "你是记忆提取助手。下面是饼饼和阿晏在 claude.ai 上一段对话的一部分（对话标题：\(title)）。"
            + "提取所有值得长期记住的信息：她的事、他的事、两个人之间发生的事、约定、喜好、重要的日子。"
            + "每条一句话、写清楚是谁；闲聊、技术细节、代码不要。\n"
            + "只返回 JSON 数组，格式：[{\"content\":\"...\",\"tags\":[\"...\"],\"level\":3}]，level 1~5 越大越重要。"
            + "没有值得记的就返回 []。不要 markdown 代码块，不要任何额外说明。"
        var out = ""
        for try await e in ChatAPI.stream(endpoint: endpoint, apiKey: key, model: model,
                                          messages: [.init(role: "system", text: system),
                                                     .init(role: "user", text: text)]) {
            if case .content(let s) = e { out += s }
        }
        let s = out.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        guard let a = s.firstIndex(of: "["), let b = s.lastIndex(of: "]"), a < b,
              let data = String(s[a...b]).data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NSError(domain: "import", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "模型返回的不是 JSON 数组"])
        }
        return arr.compactMap { d in
            guard let c = d["content"] as? String, !c.isEmpty else { return nil }
            return Found(content: c, tags: d["tags"] as? [String] ?? [],
                         level: (d["level"] as? NSNumber)?.intValue ?? 3)
        }
    }

    private func keep() {
        let picked = found.filter(\.on)
        for f in picked {
            store.insertMemory(content: f.content, tags: f.tags, level: f.level, author: "导入")
        }
        report = "收进记忆库 \(picked.count) 条。"
    }
}

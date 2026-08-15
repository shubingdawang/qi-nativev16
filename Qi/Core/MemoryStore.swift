import Foundation

// MARK: - 记忆库（本机版）
//
// 原来这套东西跑在她电脑上：一个 Node 写的 MCP 服务（memory-mcp.js），
// 前面挂 caddy 反代到公网，手机这边当远程 MCP 连过去。
// 代价是**电脑必须一直开着**——关一次机，他就失忆一次。
//
// 这个文件把那台服务整个搬进 App：
//   · 数据结构跟原来的 JSON 一模一样（字段名都没改），导进来就能用
//   · 29 个工具全部在本机实现，不走网络
//   · 文件存在 Documents/Memory/ 下面，跟聊天记录一起被 iOS 备份走
//
// 也就是说：电脑可以关了，Tailscale 可以不开了。

// MARK: 数据结构

/// 批注。原文划掉、批注标红，不动原文只叠观点。
struct MemoryAnnotation: Codable, Hashable {
    var original: String
    var correction: String
    var author: String
    var created_at: String
}

struct MemoryItem: Codable, Identifiable, Hashable {
    var id: String
    var content: String
    var tags: [String]
    var level: Int
    var author: String
    var created_at: String
    var updated_at: String
    var annotations: [MemoryAnnotation]?

    /// 工具里认的是 ID 前八位，跟原来那套一致
    var shortID: String { String(id.prefix(8)) }
}

struct DiaryItem: Codable, Identifiable, Hashable {
    var id: String
    var author: String
    var content: String
    var mood: String?
    var images: [String]?
    var annotations: [MemoryAnnotation]?
    var created_at: String
    var updated_at: String

    var shortID: String { String(id.prefix(8)) }
}

/// 「现在处于什么阶段」那段话。wake_up 第一眼看到的就是它。
struct StateNote: Codable, Hashable {
    var text: String = ""
    var updated_at: String = ""
    var by: String?
    var archived_at: String?
}

struct PartnerMessage: Codable, Hashable {
    var text: String = ""
    var author: String = "饼饼"
    var created_at: String = ""
    var read: Bool = false
}

struct PeriodRecord: Codable, Hashable {
    var start: String
    var end: String?
}

struct PeriodNote: Codable, Hashable {
    var author: String
    var text: String
    var time: String
}

struct PeriodBook: Codable {
    var records: [PeriodRecord] = []
    /// 日期 → 那天的几条备注
    var notes: [String: [PeriodNote]] = [:]
}

// 下面两个的 id 都是**可选**的。
//
// Swift 合成的解码器不会拿默认值去补缺失的键——写成 `var id: String = ...`
// 的话，电脑那边的 json 里只要没有 id 这一项，整个文件就解不出来。
// 写成可选就没这个问题，缺了就是 nil。

struct EmotionalEvent: Codable, Hashable, Identifiable {
    var id: String?
    var emotion: String
    var event: String
    var severity: Int
    var created_at: String
}

/// 记忆改过什么的流水
struct MemoryLogEntry: Codable, Hashable, Identifiable {
    var id: String?
    var time: String
    var action: String
    var by: String
    var memId: String
    var beforeText: String?
    var afterText: String?
}

struct TranscriptMsg: Codable, Hashable {
    var role: String
    var text: String
}

/// 一份存档对话的**索引**。正文单独一个文件，不跟着索引一起进内存——
/// 19 份就有 5 MB，全读进来手机会喘。
struct TranscriptMeta: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var imported_at: String
    var summary: String?
    var count: Int
}

/// 存档对话的正文
struct TranscriptFile: Codable {
    var id: String
    var title: String
    var imported_at: String
    var summary: String?
    var msgs: [TranscriptMsg]
}

// MARK: - 仓库

@MainActor
final class MemoryStore: ObservableObject {

    static let shared = MemoryStore()

    @Published var memories: [MemoryItem] = []
    @Published var diaries: [DiaryItem] = []
    /// 「我是谁」。原来是一整段纯文本。
    @Published var identity: String = ""
    @Published var currentState = StateNote()
    @Published var stateHistory: [StateNote] = []
    /// 聊到哪儿了。额度突然断掉的时候靠它接上。
    @Published var checkpoint: StateNote?
    @Published var partnerMessage: PartnerMessage?
    @Published var periods = PeriodBook()
    /// 日期 → 谁 → emoji
    @Published var moods: [String: [String: String]] = [:]
    @Published var emotionalEvents: [EmotionalEvent] = []
    @Published var log: [MemoryLogEntry] = []
    @Published var transcripts: [TranscriptMeta] = []

    private init() { reload() }

    // MARK: 文件位置

    static var root: URL {
        let url = Storage.documentsURL.appendingPathComponent("Memory", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static var transcriptsDir: URL {
        let url = root.appendingPathComponent("transcripts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private func url(_ name: String) -> URL { Self.root.appendingPathComponent(name) }

    private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    // MARK: 读写

    func reload() {
        memories = read([MemoryItem].self, "memories.json") ?? []
        diaries = read([DiaryItem].self, "diaries.json") ?? []
        identity = (try? String(contentsOf: url("identity.txt"), encoding: .utf8)) ?? ""
        currentState = read(StateNote.self, "current_state.json") ?? StateNote()
        stateHistory = read([StateNote].self, "state_history.json") ?? []
        checkpoint = read(StateNote.self, "live_checkpoint.json")
        partnerMessage = read(PartnerMessage.self, "partner_message.json")
        periods = read(PeriodBook.self, "periods.json") ?? PeriodBook()
        moods = read([String: [String: String]].self, "moods.json") ?? [:]
        emotionalEvents = read([EmotionalEvent].self, "emotional_events.json") ?? []
        log = read([MemoryLogEntry].self, "memories_log.json") ?? []
        transcripts = read([TranscriptMeta].self, "transcripts.json") ?? []
    }

    func saveMemories() { write(memories, "memories.json") }
    func saveDiaries() { write(diaries, "diaries.json") }
    func saveState() {
        write(currentState, "current_state.json")
        write(stateHistory, "state_history.json")
    }
    func saveCheckpoint() {
        if let checkpoint { write(checkpoint, "live_checkpoint.json") }
        else { try? FileManager.default.removeItem(at: url("live_checkpoint.json")) }
    }
    func savePartner() {
        if let partnerMessage { write(partnerMessage, "partner_message.json") }
        else { try? FileManager.default.removeItem(at: url("partner_message.json")) }
    }
    func savePeriods() { write(periods, "periods.json") }
    func saveMoods() { write(moods, "moods.json") }
    func saveEvents() { write(emotionalEvents, "emotional_events.json") }
    func saveLog() { write(log, "memories_log.json") }
    func saveTranscriptIndex() { write(transcripts, "transcripts.json") }
    func saveIdentity() {
        try? identity.write(to: url("identity.txt"), atomically: true, encoding: .utf8)
    }

    /// 库里到底有没有东西。没有的话工具不给出去，
    /// 免得他兴冲冲查了一圈发现什么都没有。
    var isEmpty: Bool {
        memories.isEmpty && diaries.isEmpty && transcripts.isEmpty
            && identity.isEmpty && currentState.text.isEmpty
    }

    var summaryLine: String {
        "\(memories.count) 条记忆 · \(diaries.count) 篇日记 · \(transcripts.count) 份存档"
    }

    // MARK: 存档对话的正文

    func transcript(_ id: String) -> TranscriptFile? {
        let u = Self.transcriptsDir.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(TranscriptFile.self, from: data)
    }

    func saveTranscript(_ t: TranscriptFile) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(t) else { return }
        let u = Self.transcriptsDir.appendingPathComponent("\(t.id).json")
        try? data.write(to: u, options: .atomic)

        if let i = transcripts.firstIndex(where: { $0.id == t.id }) {
            transcripts[i] = TranscriptMeta(id: t.id, title: t.title,
                                            imported_at: t.imported_at,
                                            summary: t.summary, count: t.msgs.count)
        } else {
            transcripts.append(TranscriptMeta(id: t.id, title: t.title,
                                              imported_at: t.imported_at,
                                              summary: t.summary, count: t.msgs.count))
        }
        saveTranscriptIndex()
    }

    func deleteTranscript(_ id: String) {
        try? FileManager.default.removeItem(
            at: Self.transcriptsDir.appendingPathComponent("\(id).json"))
        transcripts.removeAll { $0.id == id }
        saveTranscriptIndex()
    }

    // MARK: 小工具

    static var now: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    static var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// 找一条记忆。传全 ID 或者前八位都认。
    func memoryIndex(_ id: String) -> Int? {
        memories.firstIndex { $0.id == id || $0.id.hasPrefix(id) }
    }

    func diaryIndex(_ id: String) -> Int? {
        diaries.firstIndex { $0.id == id || $0.id.hasPrefix(id) }
    }

    func note(_ action: String, by: String, memID: String,
              before: String? = nil, after: String? = nil) {
        log.insert(MemoryLogEntry(id: UUID().uuidString, time: Self.now,
                                  action: action, by: by, memId: memID,
                                  beforeText: before, afterText: after),
                   at: 0)
        if log.count > 200 { log = Array(log.prefix(200)) }
        saveLog()
    }

    // MARK: 导入

    struct ImportReport {
        var lines: [String] = []
        var failed: [String] = []
        var text: String {
            var s = lines.joined(separator: "\n")
            if !failed.isEmpty {
                s += "\n\n没读进来的：" + failed.joined(separator: "、")
            }
            return s.isEmpty ? "没认出任何一个文件。" : s
        }
    }

    /// 从电脑上那套导进来。
    ///
    /// 按**文件名**认：memories.json、diaries.json、periods.json……
    /// transcripts 文件夹里那些散文件也认——它们没有固定名字，
    /// 但内容里有 id / title / msgs 三样，照这个认。
    func importFiles(_ urls: [URL]) -> ImportReport {
        var report = ImportReport()

        for u in urls {
            let needsStop = u.startAccessingSecurityScopedResource()
            defer { if needsStop { u.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: u) else {
                report.failed.append(u.lastPathComponent)
                continue
            }
            let name = u.lastPathComponent.lowercased()
            let dec = JSONDecoder()

            switch name {
            case "memories.json":
                if let v = try? dec.decode([MemoryItem].self, from: data) {
                    memories = v; saveMemories()
                    report.lines.append("记忆 \(v.count) 条")
                } else { report.failed.append(name) }

            case "diaries.json":
                if let v = try? dec.decode([DiaryItem].self, from: data) {
                    diaries = v; saveDiaries()
                    report.lines.append("日记 \(v.count) 篇")
                } else { report.failed.append(name) }

            case "identity.json", "identity.txt":
                if let v = try? dec.decode(String.self, from: data) {
                    identity = v; saveIdentity()
                    report.lines.append("身份认知")
                } else if let s = String(data: data, encoding: .utf8) {
                    identity = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"\n "))
                    saveIdentity()
                    report.lines.append("身份认知")
                } else { report.failed.append(name) }

            case "current_state.json":
                if let v = try? dec.decode(StateNote.self, from: data) {
                    currentState = v; saveState()
                    report.lines.append("当前状态")
                } else { report.failed.append(name) }

            case "state_history.json":
                if let v = try? dec.decode([StateNote].self, from: data) {
                    stateHistory = v; saveState()
                    report.lines.append("状态历史 \(v.count) 条")
                } else { report.failed.append(name) }

            case "live_checkpoint.json":
                if let v = try? dec.decode(StateNote.self, from: data) {
                    checkpoint = v; saveCheckpoint()
                    report.lines.append("进度点")
                } else { report.failed.append(name) }

            case "partner_message.json":
                if let v = try? dec.decode(PartnerMessage.self, from: data) {
                    partnerMessage = v; savePartner()
                    report.lines.append("留言")
                } else { report.failed.append(name) }

            case "periods.json":
                if let v = try? dec.decode(PeriodBook.self, from: data) {
                    periods = v; savePeriods()
                    report.lines.append("经期 \(v.records.count) 次")
                } else { report.failed.append(name) }

            case "moods.json":
                if let v = try? dec.decode([String: [String: String]].self, from: data) {
                    moods = v; saveMoods()
                    report.lines.append("心情 \(v.count) 天")
                } else { report.failed.append(name) }

            case "emotional_events.json":
                if let v = try? dec.decode([EmotionalEvent].self, from: data) {
                    emotionalEvents = v; saveEvents()
                    report.lines.append("情绪事件 \(v.count) 条")
                } else { report.failed.append(name) }

            case "memories_log.json":
                // 电脑那边的流水里 before/after 是对象，这边只留文字，
                // 认不出来就跳过，不值得为它卡住整次导入
                if let v = try? dec.decode([MemoryLogEntry].self, from: data) {
                    log = v; saveLog()
                    report.lines.append("修改流水 \(v.count) 条")
                }

            default:
                // transcripts 文件夹里那些
                if let t = try? dec.decode(TranscriptFile.self, from: data) {
                    saveTranscript(t)
                    report.lines.append("存档「\(t.title)」\(t.msgs.count) 条")
                } else {
                    report.failed.append(u.lastPathComponent)
                }
            }
        }
        return report
    }

    /// 全部导出成一个文件夹，方便再倒回电脑
    func exportBundle() -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("记忆库-\(Self.today)", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]

        func put<T: Encodable>(_ v: T, _ n: String) {
            if let d = try? encoder.encode(v) {
                try? d.write(to: dir.appendingPathComponent(n))
            }
        }
        put(memories, "memories.json")
        put(diaries, "diaries.json")
        put(currentState, "current_state.json")
        put(stateHistory, "state_history.json")
        put(periods, "periods.json")
        put(moods, "moods.json")
        put(emotionalEvents, "emotional_events.json")
        put(log, "memories_log.json")
        if let checkpoint { put(checkpoint, "live_checkpoint.json") }
        if let partnerMessage { put(partnerMessage, "partner_message.json") }
        try? identity.write(to: dir.appendingPathComponent("identity.txt"),
                            atomically: true, encoding: .utf8)

        let tdir = dir.appendingPathComponent("transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: tdir, withIntermediateDirectories: true)
        for meta in transcripts {
            if let t = transcript(meta.id), let d = try? encoder.encode(t) {
                try? d.write(to: tdir.appendingPathComponent("\(meta.id).json"))
            }
        }
        return dir
    }

    /// 全部清空。导错了、或者想重来的时候用。
    func wipe() {
        try? FileManager.default.removeItem(at: Self.root)
        memories = []; diaries = []; identity = ""
        currentState = StateNote(); stateHistory = []
        checkpoint = nil; partnerMessage = nil
        periods = PeriodBook(); moods = [:]
        emotionalEvents = []; log = []; transcripts = []
    }
}

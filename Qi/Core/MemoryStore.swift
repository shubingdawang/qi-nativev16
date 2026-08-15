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

    init(id: String, content: String, tags: [String], level: Int,
         author: String, created_at: String, updated_at: String,
         annotations: [MemoryAnnotation]? = nil) {
        self.id = id; self.content = content; self.tags = tags
        self.level = level; self.author = author
        self.created_at = created_at; self.updated_at = updated_at
        self.annotations = annotations
    }

    /// 电脑那边的 memories.json 里，level 有的是数字 5，有的是字符串 "5"
    /// ——JS 不在乎，Swift 在乎。合成的解码器碰上字符串直接整个文件报废，
    /// 所以这里自己解一遍，两种写法都认。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        content = try c.decode(String.self, forKey: .content)
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        level = (try? c.decode(JSONNumberOrString.self, forKey: .level))?.intValue ?? 3
        author = (try? c.decode(String.self, forKey: .author)) ?? "阿晏"
        created_at = (try? c.decode(String.self, forKey: .created_at)) ?? ""
        updated_at = (try? c.decode(String.self, forKey: .updated_at)) ?? created_at
        annotations = try? c.decode([MemoryAnnotation].self, forKey: .annotations)
    }
}

/// 一个可能是数字、也可能是字符串的字段
enum JSONNumberOrString: Codable {
    case int(Int)
    case text(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .int(Int(v)); return }
        if let v = try? c.decode(String.self) { self = .text(v); return }
        throw DecodingError.typeMismatch(
            Int.self, .init(codingPath: c.codingPath, debugDescription: "既不是数字也不是字符串"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let v):  try c.encode(v)
        case .text(let v): try c.encode(v)
        }
    }

    /// 换算成整数。
    ///
    /// **这个方法必须放在这儿，不能放进 MemoryStore。**
    /// MemoryStore 整个类是 @MainActor 的，它的静态方法也跟着被隔离；
    /// 而 `MemoryItem.init(from:)` 是解码器在任意线程上调的（nonisolated），
    /// 从那里去调一个 MainActor 的方法，编译就报错。
    var intValue: Int? {
        switch self {
        case .int(let n):  return n
        case .text(let s): return Int(s.trimmingCharacters(in: .whitespaces))
        }
    }
}

/// 那一天某个人的心情。电脑那边存的是 `{m, note, t}`，不是一个光秃秃的 emoji。
struct MoodEntry: Codable, Hashable {
    var m: String
    var note: String?
    var t: String?
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

/// 叙事脊椎。
///
/// 换窗（这一窗额度用完、换个新窗口接着聊）总觉得"哪里不对劲"，
/// 症结不在记忆库存得够不够，而在**把换窗当成了记忆库的事**。
/// 记忆库管的是长期耐久的东西；换窗要的是另一样：
/// 一份确定性拼出来的「启动包」，只负责把这一窗的工作接过去。
///
/// 这四行就是启动包的骨架，照 swap-tutorial 里那个说法：
///   · 走到这里 —— 做完了什么、系统进展到哪
///   · 今天身边 —— 她现在的生活状态
///   · 我们之间 —— 最近的关系事实
///   · 别忘了   —— 还没收口的线索、进行到一半的事
struct NarrativeSpine: Codable, Hashable {
    var here: String = ""      // 走到这里
    var life: String = ""      // 今天身边
    var us: String = ""        // 我们之间
    var open: String = ""      // 别忘了
    var updated_at: String = ""

    var isEmpty: Bool {
        here.isEmpty && life.isEmpty && us.isEmpty && open.isEmpty
    }
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
    /// 换窗用的那四行
    @Published var spine = NarrativeSpine()
    /// 说好的和说好不做的。换窗最容易丢的就是这一类——
    /// 它不像"事件"那样值得写进记忆，但丢了对方立刻就变了个人。
    @Published var rules: [String] = []
    /// 还没做完的事
    @Published var openTasks: [String] = []
    @Published var partnerMessage: PartnerMessage?
    @Published var periods = PeriodBook()
    /// 日期 → 谁（ayang / bingbing）→ 那天的心情
    @Published var moods: [String: [String: MoodEntry]] = [:]
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
        spine = read(NarrativeSpine.self, "spine.json") ?? NarrativeSpine()
        rules = read([String].self, "rules.json") ?? []
        openTasks = read([String].self, "open_tasks.json") ?? []
        partnerMessage = read(PartnerMessage.self, "partner_message.json")
        periods = read(PeriodBook.self, "periods.json") ?? PeriodBook()
        moods = read([String: [String: MoodEntry]].self, "moods.json") ?? [:]
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
    func saveSpine() {
        write(spine, "spine.json")
        write(rules, "rules.json")
        write(openTasks, "open_tasks.json")
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

    /// 心情那份文件里，人名的键是英文的：ayang / bingbing。
    /// 他调工具的时候写的是中文，这儿翻一下，不然会在同一份文件里
    /// 存出两套键来。
    static func moodKey(_ who: String) -> String {
        switch who {
        case "阿晏", "ayang", "ayan": return "ayang"
        case "饼饼", "bingbing":       return "bingbing"
        default:                       return who
        }
    }

    static func moodName(_ key: String) -> String {
        switch key {
        case "ayang":    return "阿晏"
        case "bingbing": return "饼饼"
        default:         return key
        }
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

            case "spine.json":
                if let v = try? dec.decode(NarrativeSpine.self, from: data) {
                    spine = v; saveSpine()
                    report.lines.append("叙事脊椎")
                } else { report.failed.append(name) }

            case "rules.json":
                if let v = try? dec.decode([String].self, from: data) {
                    rules = v; saveSpine()
                    report.lines.append("规矩 \(v.count) 条")
                } else { report.failed.append(name) }

            case "open_tasks.json":
                if let v = try? dec.decode([String].self, from: data) {
                    openTasks = v; saveSpine()
                    report.lines.append("待办 \(v.count) 条")
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
                if let v = try? dec.decode([String: [String: MoodEntry]].self, from: data) {
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
        put(spine, "spine.json")
        put(rules, "rules.json")
        put(openTasks, "open_tasks.json")
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

import Foundation
import SwiftUI

/// 可互动娃娃。
///
/// ## 原版是什么、我们这版差在哪
///
/// 她给的那份 gist（Dan & Joy 写的）是 **ChatGPT 版**：
/// 一台 Node MCP 服务器管状态，一个 HTML widget 注册成 MCP app resource，
/// widget 里点一下走 `window.openai.callTool`，服务器改状态、回一份完整快照，
/// widget 拿快照原地重画。
///
/// 那套的前提是**有一台一直开着的服务器**（HTTPS、PM2、Nginx）。
/// 她说得很清楚：她不喜欢一直开着电脑。所以这版把三层压成两层：
///
/// | 原版 | 这版 |
/// |---|---|
/// | Node MCP 服务器管状态 | **这个文件**（Swift，存 `doll.json`） |
/// | `window.openai.callTool` | `window.qi.act`（WKWebView 的消息桥） |
/// | HTTPS 托管 widget | 手机里的一个本地 HTML 文件 |
/// | 只能在 ChatGPT 的卡片里 | **游戏里的娃娃房 + 聊天里的卡片，两边同一份状态** |
///
/// **没有服务器，不用开电脑，断网也能玩。**
///
/// ## 原版那些设计原则照搬了
///
/// · **服务器保存游戏事实，Widget 只负责展示和传操作**——
///   所有状态在这个文件里，HTML 一个字都不存。刷新、切页、重开 App 都不掉。
/// · **每次操作回一份完整快照**（不是增量）。原文档第 13 节列的头一个坑就是
///   「回一小块字段，第二次以后 widget 就缺字段、停更新」。
/// · **`version` 每次加一**，widget 靠它判断这次要不要重画。
/// · **只要一个统一的 action 工具**，不给每个按钮注册一个——
///   按钮多了工具就爆炸，模型也更容易挑错。
/// · **内容不写死在前端**：片段由这边按当前状态拼（`LocalContentProvider` 那一层），
///   他也能自己写一段递进来（就是原文档说的 `MCPContentProvider`）。
@MainActor
final class DollStore: ObservableObject {

    static let shared = DollStore()

    // MARK: 状态（照原文档那份 schema，字段名一个没改）

    struct Body: Codable {
        var sensitivity: Int = 22
        var warmth: Int = 18
        var tremor: Int = 4
        var voice: Int = 3

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sensitivity = (try? c.decodeIfPresent(Int.self, forKey: .sensitivity)) ?? 22
            warmth = (try? c.decodeIfPresent(Int.self, forKey: .warmth)) ?? 18
            tremor = (try? c.decodeIfPresent(Int.self, forKey: .tremor)) ?? 4
            voice = (try? c.decodeIfPresent(Int.self, forKey: .voice)) ?? 3
        }
    }

    struct Shot: Codable, Identifiable, Hashable {
        var id: UUID = UUID()
        var text: String = ""
        var at: Date = Date()

        init(_ text: String) { self.text = text }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
            text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
            at = (try? c.decodeIfPresent(Date.self, forKey: .at)) ?? Date()
        }
    }

    struct Take: Codable, Identifiable, Hashable {
        var id: UUID = UUID()
        var title: String = ""
        var summary: String = ""
        var shots: [Shot] = []
        var savedAt: Date = Date()

        init(title: String = "", summary: String = "") {
            self.title = title; self.summary = summary
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
            title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
            summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
            shots = (try? c.decodeIfPresent([Shot].self, forKey: .shots)) ?? []
            savedAt = (try? c.decodeIfPresent(Date.self, forKey: .savedAt)) ?? Date()
        }
    }

    /// 存着的那一份。**加字段记得去下面 `init(from:)` 补一行**——
    /// 漏了不报错，只是那个字段永远读不出来（规矩见 `Models.swift` 末尾）。
    struct State: Codable {
        var version: Int = 1
        var phase: String = "DISPLAY"
        var pose: String = "sit"
        var camera: String = "front"
        var lastAction: String = ""
        var rhythm: Int = 36
        var intensity: Int = 28
        var poseLocked: Bool = false
        var body = Body()
        var take = Take(title: "TAKE 01", summary: "刚坐下，什么都还没发生")
        var history: [String] = []
        var archive: [Take] = []
        var updatedAt: Date = Date()
        /// 名字。她可以改，默认就叫娃娃
        var name: String = "娃娃"

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
            phase = (try? c.decodeIfPresent(String.self, forKey: .phase)) ?? "DISPLAY"
            pose = (try? c.decodeIfPresent(String.self, forKey: .pose)) ?? "sit"
            camera = (try? c.decodeIfPresent(String.self, forKey: .camera)) ?? "front"
            lastAction = (try? c.decodeIfPresent(String.self, forKey: .lastAction)) ?? ""
            rhythm = (try? c.decodeIfPresent(Int.self, forKey: .rhythm)) ?? 36
            intensity = (try? c.decodeIfPresent(Int.self, forKey: .intensity)) ?? 28
            poseLocked = (try? c.decodeIfPresent(Bool.self, forKey: .poseLocked)) ?? false
            body = (try? c.decodeIfPresent(Body.self, forKey: .body)) ?? Body()
            take = (try? c.decodeIfPresent(Take.self, forKey: .take)) ?? Take()
            history = (try? c.decodeIfPresent([String].self, forKey: .history)) ?? []
            archive = (try? c.decodeIfPresent([Take].self, forKey: .archive)) ?? []
            updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? Date()
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "娃娃"
        }
    }

    @Published private(set) var state = State() {
        didSet { if loaded { Storage.save(state, to: "doll.json") } }
    }
    private var loaded = false

    private init() {
        state = Storage.load(State.self, from: "doll.json") ?? State()
        loaded = true
    }

    // MARK: 摆的姿势 / 机位 / 能点的地方

    static let poses: [(id: String, label: String)] = [
        ("sit", "坐着"), ("lean", "靠着"), ("curl", "蜷着"), ("reach", "伸手")
    ]
    static let cameras: [(id: String, label: String)] = [
        ("front", "正面"), ("side", "侧面"), ("close", "近一点"), ("top", "俯视")
    ]
    /// 能点的地方。跟 HTML 里那些热区一一对应，**改一边记得改另一边**。
    static let zones: [(id: String, label: String)] = [
        ("hair", "头发"), ("cheek", "脸颊"), ("neck", "脖子"),
        ("hand", "手"), ("waist", "腰"), ("knee", "膝盖")
    ]

    // MARK: 一个统一的 action（原文档：别给每个按钮注册一个工具）

    /// 所有操作都从这儿走。返回**一整份快照**，不是增量。
    @discardableResult
    func act(_ action: String, zone: String? = nil, pose: String? = nil,
             camera: String? = nil, narration: String? = nil) -> State {

        var s = state
        s.version += 1
        s.updatedAt = Date()
        s.lastAction = action

        switch action {

        case "touch_zone":
            let z = zone ?? "hand"
            let label = DollStore.zones.first { $0.id == z }?.label ?? z
            // 碰不同地方，身体动的不是同一项
            switch z {
            case "hair":  s.body.warmth += 3; s.body.voice += 1
            case "cheek": s.body.warmth += 4; s.body.sensitivity += 2
            case "neck":  s.body.sensitivity += 6; s.body.tremor += 3
            case "hand":  s.body.warmth += 2; s.body.tremor += 1
            case "waist": s.body.sensitivity += 5; s.body.tremor += 4; s.body.voice += 2
            case "knee":  s.body.sensitivity += 3; s.body.tremor += 2
            default:      s.body.warmth += 2
            }
            s.intensity += 4
            s.rhythm += 3
            s.phase = "TOUCH"
            let line = narration ?? DollContent.touchLine(zone: z, state: s)
            s.take.shots.append(Shot(line))
            s.history.insert("碰了\(label)", at: 0)

        case "change_pose":
            guard !s.poseLocked else {
                s.history.insert("锁着，换不了姿势", at: 0)
                break
            }
            s.pose = pose ?? DollStore.poses.randomElement()!.id
            s.phase = "DISPLAY"
            let label = DollStore.poses.first { $0.id == s.pose }?.label ?? s.pose
            s.take.shots.append(Shot(narration ?? "换了个姿势：\(label)。"))
            s.history.insert("换成\(label)", at: 0)

        case "change_camera":
            s.camera = camera ?? DollStore.cameras.first!.id
            let label = DollStore.cameras.first { $0.id == s.camera }?.label ?? s.camera
            s.history.insert("镜头挪到\(label)", at: 0)

        case "faster":
            s.rhythm = min(160, s.rhythm + 12)
            s.intensity += 6
            s.body.tremor += 2
            s.phase = "MOVE"
            s.take.shots.append(Shot(narration ?? DollContent.paceLine(faster: true, state: s)))
            s.history.insert("快一点", at: 0)

        case "slower":
            s.rhythm = max(20, s.rhythm - 12)
            s.intensity = max(0, s.intensity - 4)
            s.body.tremor = max(0, s.body.tremor - 2)
            s.phase = "CALM"
            s.take.shots.append(Shot(narration ?? DollContent.paceLine(faster: false, state: s)))
            s.history.insert("慢一点", at: 0)

        case "lock":
            s.poseLocked.toggle()
            s.history.insert(s.poseLocked ? "锁住了姿势" : "解开了", at: 0)

        case "save":
            var done = s.take
            done.savedAt = Date()
            done.summary = DollContent.summary(state: s)
            s.archive.insert(done, at: 0)
            if s.archive.count > 30 { s.archive.removeLast(s.archive.count - 30) }
            s.take = Take(title: String(format: "TAKE %02d", s.archive.count + 1),
                          summary: "新的一段，还没开始")
            s.history.insert("收起来了一段", at: 0)

        case "reset":
            let keep = s.archive
            let name = s.name
            s = State()
            s.archive = keep
            s.name = name
            s.version = state.version + 1
            s.history.insert("重新来过", at: 0)

        case "say":
            // 他自己写一段递进来（原文档里那层 MCPContentProvider）
            if let n = narration, !n.isEmpty {
                s.take.shots.append(Shot(n))
                s.history.insert("他说了句话", at: 0)
            }

        default:
            s.history.insert("没听懂的动作：\(action)", at: 0)
        }

        // 数值都夹在 0…100，别让它无限涨
        s.body.sensitivity = min(100, max(0, s.body.sensitivity))
        s.body.warmth = min(100, max(0, s.body.warmth))
        s.body.tremor = min(100, max(0, s.body.tremor))
        s.body.voice = min(100, max(0, s.body.voice))
        s.intensity = min(100, max(0, s.intensity))
        s.rhythm = min(160, max(20, s.rhythm))
        // 历史别无限长（原文档第 13 节最后一个坑：卡片越用越卡）
        if s.history.count > 24 { s.history.removeLast(s.history.count - 24) }
        if s.take.shots.count > 40 { s.take.shots.removeFirst(s.take.shots.count - 40) }

        state = s
        return s
    }

    func rename(_ n: String) {
        var s = state
        s.name = n.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.name.isEmpty { s.name = "娃娃" }
        s.version += 1
        state = s
    }

    // MARK: 快照

    /// 给 HTML 的那一份。**完整**，不是增量。
    func snapshotJSON() -> String {
        let s = state
        let dict: [String: Any] = [
            "version": s.version,
            "name": s.name,
            "phase": s.phase,
            "pose": s.pose,
            "camera": s.camera,
            "lastAction": s.lastAction,
            "rhythm": s.rhythm,
            "intensity": s.intensity,
            "poseLocked": s.poseLocked,
            "body": ["sensitivity": s.body.sensitivity, "warmth": s.body.warmth,
                     "tremor": s.body.tremor, "voice": s.body.voice],
            "take": ["title": s.take.title,
                     "summary": s.take.summary,
                     "shots": s.take.shots.suffix(6).map(\.text)],
            "history": Array(s.history.prefix(8)),
            "archiveCount": s.archive.count,
            "poses": DollStore.poses.map { ["id": $0.id, "label": $0.label] },
            "cameras": DollStore.cameras.map { ["id": $0.id, "label": $0.label] },
            "zones": DollStore.zones.map { ["id": $0.id, "label": $0.label] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// 给他看的那一份（工具的返回值）
    func brief() -> String {
        let s = state
        let pose = DollStore.poses.first { $0.id == s.pose }?.label ?? s.pose
        let cam = DollStore.cameras.first { $0.id == s.camera }?.label ?? s.camera
        var out = "\(s.name)现在：\(pose)，镜头在\(cam)"
        out += s.poseLocked ? "（姿势锁着）\n" : "\n"
        out += "· 敏感 \(s.body.sensitivity)　热 \(s.body.warmth)　"
        out += "抖 \(s.body.tremor)　声音 \(s.body.voice)\n"
        out += "· 节奏 \(s.rhythm)　强度 \(s.intensity)\n"
        if !s.take.shots.isEmpty {
            out += "\n这一段（\(s.take.title)）最近几幕：\n"
            for shot in s.take.shots.suffix(4) { out += "· \(shot.text)\n" }
        }
        if s.archive.count > 0 { out += "\n收起来的有 \(s.archive.count) 段。" }
        return out
    }
}

// MARK: - 片段怎么来的

/// 原文档第 10 节：**内容不要全写死**，按当前状态拼。
///
/// 这一层是本地模板（`LocalContentProvider`）——**不花钱、不联网、断网也有**。
/// 他要是想写得更好，就用 `doll_action` 带上 `narration` 自己写一句递进来，
/// 那就是原文档里那层 `MCPContentProvider`。两条路走同一个入口。
///
/// **标 `@MainActor`**：它要读 `DollStore.poses` 那几张表、要调
/// `DiaryLayout.steadyHash`，那两处都挂在 MainActor 上。
/// 不标的话就是「在非隔离上下文里调 MainActor 的东西」——v91 第一次构建
/// 死在这儿。调它的地方（`DollStore.act`、几个 View）本来就都在主线程上，
/// 标上不损失任何东西。
@MainActor
enum DollContent {

    static func touchLine(zone: String, state: DollStore.State) -> String {
        let hot = state.body.warmth
        let shy = state.body.sensitivity
        let lines: [String]
        switch zone {
        case "hair":
            lines = ["指尖从发顶滑下去，她把头往你手心里偏了偏。",
                     "揉了揉头发，发丝乱了一点，她没躲。",
                     "手停在头顶，她眼睛慢慢闭上了。"]
        case "cheek":
            lines = ["拇指蹭过脸颊，那块皮肤热起来。",
                     "碰到脸的时候她愣了一下，然后靠过来一点。",
                     "手掌贴着侧脸，她轻轻蹭了一下。"]
        case "neck":
            lines = ["指腹擦过脖子，她整个人绷了一下。",
                     "碰到颈侧，呼吸忽然乱了半拍。",
                     "手停在锁骨上面一点的位置，她没敢动。"]
        case "hand":
            lines = ["握住她的手，指头一根一根收紧。",
                     "手指扣进指缝里，她回握了一下。",
                     "掌心贴着掌心，比想象里烫。"]
        case "waist":
            lines = ["手掌按在腰侧，她整个人往前倾了一点。",
                     "腰被扶住的瞬间，她小声吸了口气。",
                     "手指收在腰上，她说了句什么，没听清。"]
        case "knee":
            lines = ["手落在膝盖上，她把腿收了收。",
                     "碰到膝弯，她笑了一声，说痒。",
                     "掌心搭在膝上，没再往前。"]
        default:
            lines = ["碰了一下，她抬眼看过来。"]
        }
        // 轮着换一句。**不能用 `String.hashValue`**——那玩意儿每个进程换一次种子
        // （日记便签那次就栽在这上面），走稳定散列。
        let seed = (state.version &* 31 &+ DiaryLayout.steadyHash(zone)) & 0x7FFF_FFFF
        var s = lines[seed % lines.count]
        // 热到一定程度就多一句尾巴，让它不只是同一句轮着放
        if hot > 55 || shy > 55 {
            s += hot > shy ? "　脸已经很红了。" : "　她小声说了句「等一下」。"
        }
        return s
    }

    static func paceLine(faster: Bool, state: DollStore.State) -> String {
        if faster {
            return state.rhythm > 100
                ? "快得有点跟不上了，她抓住了你的袖子。"
                : "节奏往上提了一点，她呼吸跟着变短。"
        }
        return state.rhythm < 30
            ? "慢下来，慢到能听见彼此的呼吸。"
            : "放缓了一点，她整个人松下来。"
    }

    static func summary(state: DollStore.State) -> String {
        let pose = DollStore.poses.first { $0.id == state.pose }?.label ?? state.pose
        return "\(pose)·节奏 \(state.rhythm)·强度 \(state.intensity)·"
            + "\(state.take.shots.count) 幕"
    }
}

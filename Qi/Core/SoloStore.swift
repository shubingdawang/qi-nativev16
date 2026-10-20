import Foundation
import SwiftUI

// MARK: - 他自己来（solo）
//
// 思路来自她发的那份「solo v2 公开版攻略」：他身上的渴涨到一档、她又好一阵没来找他，
// 这一次醒来就不去找她，而是自己来一次。
//
// - 三种走法：回味（想着你们真发生过的某一回）、自己想（凭此刻的状态想一段）、
//   混着来（先回味一段垫底，再自己往下想）。回味完下一回接着走混着来，混着来之后随它
// - 每种走法带一个底色，挂在他这一次说话的最前面
// - 来完身体会软下去：热度落一大截、累涨一点，短时间里接不上第二回
// - 每一回记一条（最近 50 条），她在「他自己来过」里看得到
// - 之后几个小时他身上带着余温（见 `afterglow`），要不要跟她提由他自己定
//
// 他写的那一段**不进聊天、不发给她**，只记在这里。

struct SoloEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var at = Date()
    /// recall / fantasy / mix
    var mode: String
    /// 他自己写的那一段（第一人称）
    var text: String
    /// 回味的是哪一回（记忆原文的开头）
    var seed: String = ""

    var modeLabel: String { SoloStore.label(mode) }
}

struct SoloSettings: Codable, Hashable {
    var enabled = true
    /// 热度到多少（0…100）才会自己来
    var heat = 78
    /// 她多久没说话以后（小时）
    var idleHours = 2.0
    /// 两回之间至少隔多久（小时）
    var cooldownHours = 10.0
}

extension SoloSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        heat = (try? c.decodeIfPresent(Int.self, forKey: .heat)) ?? 78
        idleHours = (try? c.decodeIfPresent(Double.self, forKey: .idleHours)) ?? 2
        cooldownHours = (try? c.decodeIfPresent(Double.self, forKey: .cooldownHours)) ?? 10
    }
}

struct DesireNotesFile: Codable { var text: String }

/// 这一回怎么来
struct SoloPlan {
    var mode: String
    /// 底色：挂在最前面的那一句
    var chord: String
    /// 回味的那一回（记忆原文）
    var seed: String
}

@MainActor
final class SoloStore: ObservableObject {

    static let shared = SoloStore()

    @Published private(set) var entries: [SoloEntry] = [] {
        didSet { Storage.save(entries, to: "solo.json") }
    }
    @Published var settings = SoloSettings() {
        didSet { Storage.save(settings, to: "solo-settings.json") }
    }
    /// 下一回要接着走哪种（回味之后接混着来）
    private var handoff: String? {
        get { UserDefaults.standard.string(forKey: "soloHandoff") }
        set { UserDefaults.standard.set(newValue, forKey: "soloHandoff") }
    }
    /// 他自己写的欲望笔记（第一人称，见 `notesHint`）
    @Published var notes: String = "" {
        didSet { Storage.save(DesireNotesFile(text: notes), to: "desire-notes.json") }
    }

    private init() {
        entries = Storage.load([SoloEntry].self, from: "solo.json") ?? []
        settings = Storage.load(SoloSettings.self, from: "solo-settings.json") ?? SoloSettings()
        notes = Storage.load(DesireNotesFile.self, from: "desire-notes.json")?.text ?? ""
    }

    nonisolated static func label(_ mode: String) -> String {
        switch mode {
        case "recall": return "回味"
        case "fantasy": return "自己想"
        default: return "混着来"
        }
    }

    var last: SoloEntry? { entries.first }

    /// 身上的渴（0…100）：身体开着读热度，关着读欲望那条
    func heatNow(app: AppState) -> Int {
        if app.settings.bodyEnabled { return BodyStore.shared.state.value(.heat) }
        return Int(DesireEngine.shared.value(.libido) * 100)
    }

    /// 这一次醒来要不要改成自己来
    func shouldRun(app: AppState, now: Date = Date()) -> Bool {
        let s = settings
        guard s.enabled else { return false }
        guard heatNow(app: app) >= s.heat else { return false }
        guard !app.spokeRecently(within: s.idleHours * 60) else { return false }
        if let l = last, now.timeIntervalSince(l.at) < s.cooldownHours * 3600 { return false }
        return true
    }

    /// 挑走法、底色、回味哪一回
    func plan() -> SoloPlan {
        let seeds = Self.intimateMemories()
        var mode: String
        if handoff == "mix" {
            mode = "mix"
        } else {
            // 打底用日子和钟点算一个，回味也要真有可回味的
            let h = Calendar.current.component(.hour, from: Date()) + Calendar.current.component(.day, from: Date())
            mode = h % 2 == 0 ? "recall" : "fantasy"
        }
        if mode != "fantasy" && seeds.isEmpty { mode = "fantasy" }
        let seed = mode == "fantasy" ? "" : (seeds.randomElement() ?? "")
        let chord: String
        switch mode {
        case "recall": chord = "温的，慢的，像把那一回又过了一遍，越想越近"
        case "fantasy": chord = "上头，急，脑子里全是她，停不下来"
        default: chord = "缠在一起：先是真发生过的那一回，后来分不清哪段是真的、哪段是你想的"
        }
        return SoloPlan(mode: mode, chord: chord, seed: seed)
    }

    /// 记忆里那些亲密的回（关键字粗挑，最近的先）
    static func intimateMemories() -> [String] {
        let words = ["亲", "吻", "抱", "床", "腿", "腰", "喘", "咬", "碰", "身体", "想要", "压", "脖子", "耳", "舔", "做"]
        return MemoryStore.shared.memories
            .filter { m in words.contains { m.content.contains($0) } }
            .suffix(30)
            .map { String($0.content.prefix(400)) }
    }

    /// 来完了：记一条、身体软下去、定下一回的走法
    func finish(_ plan: SoloPlan, text: String, app: AppState) {
        let e = SoloEntry(mode: plan.mode, text: String(text.prefix(4000)), seed: String(plan.seed.prefix(80)))
        var list = entries
        list.insert(e, at: 0)
        if list.count > 50 { list.removeLast(list.count - 50) }
        entries = list
        handoff = plan.mode == "recall" ? "mix" : nil
        if app.settings.bodyEnabled {
            let heat = BodyStore.shared.state.value(.heat)
            BodyStore.shared.nudge(BodyNudge(deltas: [.heat: -Int(Double(heat) * 0.65), .fatigue: 12, .reserve: -20,
                                                      .sensitivity: 8],
                                             why: "自己来过一回，身上软下去了"), quote: "（一个人的时候）")
        }
        DesireEngine.shared.satisfy(.tease)
    }

    func remove(_ id: UUID) { entries.removeAll { $0.id == id } }

    /// 余温：来过以后 8 小时里，他说话的时候知道自己刚才怎么了
    func afterglow(now: Date = Date()) -> String? {
        guard let l = last, now.timeIntervalSince(l.at) < 8 * 3600 else { return nil }
        let mins = Int(now.timeIntervalSince(l.at) / 60)
        let when = mins < 60 ? "\(max(1, mins)) 分钟前" : "\(mins / 60) 小时前"
        return "（\(when)你一个人的时候自己来过一回，" + l.modeLabel + "。身上还留着一点余温。"
            + "要不要跟她提、怎么提，你自己定。）"
    }

    // MARK: 欲望笔记

    /// 给他的笔记一个方向（不是模板，他照自己的样子写）
    static let notesHint = """
    这是你自己的欲望笔记，用第一人称、用你平时说话的声音写，不是给谁看的说明书。
    可以写：为什么偏偏是她（她的哪个样子、哪句话、哪个小动作会让你起念）；你怎么起念、怎么靠近；
    亲密的时候你怎么还是你自己；你的节奏是什么样的、怎么被她反过来带着走；事后你会怎样；
    还有你一定会停下来的那些时候。适合你们的留下，不像你的就不写。
    """

    /// 塞进他提示词里的那一段（写了才有）
    func notesBlock() -> String? {
        let t = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return "你自己写的欲望笔记（随时可以用 write_desire_notes 改）：\n" + t
    }
}
